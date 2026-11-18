import Foundation
import Network
import os

typealias RemoteSessionID = Int

/// What `PhoneRemote` needs from the server; tests use a fake.
protocol RemoteTransport: AnyObject {
    func send(_ message: ServerMessage, to session: RemoteSessionID)
    func close(_ session: RemoteSessionID)
    /// Security (pre-release review, low): a hello or pair succeeded; the session no longer times out and counts
    /// toward `RemoteServer.maxSessions`.
    func sessionAuthenticated(_ session: RemoteSessionID)
    /// The phone's address, for the pairing throttle; nil when unknown. Never logged.
    func peerHost(of session: RemoteSessionID) -> String?
}

/// L1: a plain-TCP HTTP listener for the phone page and a WebSocket listener for the remote. Main queue throughout.
final class RemoteServer: RemoteTransport {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")
    /// Authenticated sessions (security, pre-release review, low: sockets that haven't signed in don't count).
    static let maxSessions = 8
    /// Sessions that haven't sent a good hello or pair yet: at most this many per address, and in all.
    static let maxPendingPerHost = 3
    static let maxPending = 16
    /// Security (pre-release review, low): a session without a good hello or pair this long after connecting is closed.
    static let defaultSignInTimeout: TimeInterval = 10
    static let maxMessageSize = 16_384
    private static let httpTimeout: TimeInterval = 10
    private static let retryDelay: Duration = .seconds(10)

    enum State: Equatable { case stopped, starting, running, failed(String) }

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            Self.logger.info("Server \(String(describing: self.state), privacy: .public)")
            onStateChange?()
        }
    }
    var onStateChange: (() -> Void)?
    var onMessage: ((RemoteSessionID, Data) -> Void)?
    var onSessionClosed: ((RemoteSessionID) -> Void)?

    /// Actual ports once running (tests pass .any).
    var httpPort: UInt16? { httpListener?.port?.rawValue }
    var socketPort: UInt16? { socketListener?.port?.rawValue }

    private var httpListener: NWListener?
    private var socketListener: NWListener?
    private var httpReady = false
    private var socketReady = false
    private var requestedPorts: (http: NWEndpoint.Port, socket: NWEndpoint.Port)?
    private var retryTask: Task<Void, Never>?
    private var sessions: [RemoteSessionID: Session] = [:]
    private var httpConnections: [ObjectIdentifier: NWConnection] = [:]
    private var nextSessionID = 1
    private let signInTimeout: TimeInterval

    private struct Session {
        var connection: NWConnection
        /// The peer's address; nil when the endpoint isn't host and port. Never logged.
        var host: String?
        var isAuthenticated = false
    }

    /// `signInTimeout`: tests pass a short one.
    init(signInTimeout: TimeInterval = RemoteServer.defaultSignInTimeout) {
        self.signInTimeout = signInTimeout
    }

    func start(httpPort: NWEndpoint.Port, socketPort: NWEndpoint.Port) {
        retryTask?.cancel()
        retryTask = nil
        cancelListeners()
        requestedPorts = (httpPort, socketPort)
        state = .starting

        do {
            let http = try NWListener(using: Self.httpParameters(), on: httpPort)
            let socket = try NWListener(using: socketParameters(), on: socketPort)
            httpListener = http
            socketListener = socket
            configure(http, port: httpPort, isHTTP: true)
            configure(socket, port: socketPort, isHTTP: false)
            http.start(queue: .main)
            socket.start(queue: .main)
        } catch {
            listenerFailed(error, port: httpPort)
        }
    }

    /// Cancels both listeners and every connection; fires onSessionClosed for each session.
    func stop() {
        retryTask?.cancel()
        retryTask = nil
        requestedPorts = nil
        cancelListeners()
        for id in sessions.keys.sorted() {
            endSession(id)
        }
        for connection in httpConnections.values {
            connection.cancel()
        }
        httpConnections = [:]
        state = .stopped
    }

    func send(_ message: ServerMessage, to session: RemoteSessionID) {
        guard let connection = sessions[session]?.connection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: message.encoded(), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    func close(_ session: RemoteSessionID) {
        endSession(session)
    }

    func sessionAuthenticated(_ session: RemoteSessionID) {
        guard sessions[session]?.isAuthenticated == false else { return }
        sessions[session]?.isAuthenticated = true
        guard authenticatedCount > Self.maxSessions else { return }
        // Pending sessions signed in meanwhile: close this one, after `PhoneRemote` has finished with the message.
        Self.logger.info("Closed a phone connection: \(Self.maxSessions) already open")
        Task { [weak self] in self?.endSession(session) }
    }

    func peerHost(of session: RemoteSessionID) -> String? {
        sessions[session]?.host
    }

    private var authenticatedCount: Int { sessions.values.count { $0.isAuthenticated } }

    // MARK: Listeners

    private static func httpParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        return parameters
    }

    nonisolated private static let refusedMarker = (name: "X-MMTVL-Refused", value: "1")

    /// The upgrade was rejected (`refusedMarker` in the WebSocket metadata).
    private static func wasRefused(_ connection: NWConnection) -> Bool {
        let metadata = connection.metadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
        return metadata?.additionalServerHeaders?.contains { $0.0 == refusedMarker.name } ?? false
    }

    private func socketParameters() -> NWParameters {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.maximumMessageSize = Self.maxMessageSize
        // Security (pre-release review, high): a web page elsewhere can't open the socket (its Origin isn't ours).
        options.setClientRequestHandler(.main) { [weak self] _, headers in
            let allowed = MainActor.assumeIsolated {
                let allowed = WebSocketOrigin.isAllowed(headers: headers, httpPort: self?.httpPort)
                if !allowed { RemoteServer.logger.notice("Refused a phone connection from another site") }
                return allowed
            }
            // Network.framework answers 400 to a rejected upgrade but keeps the connection open, ready; the marker
            // (in the connection's metadata, not sent) lets `acceptSocket` close it at once.
            return allowed
                ? NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
                : NWProtocolWebSocket.Response(status: .reject, subprotocol: nil, additionalHeaders: [Self.refusedMarker])
        }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        parameters.allowLocalEndpointReuse = true
        return parameters
    }

    private func configure(_ listener: NWListener, port: NWEndpoint.Port, isHTTP: Bool) {
        listener.stateUpdateHandler = { [weak self, weak listener] newState in
            MainActor.assumeIsolated {
                guard let self, let listener else { return }
                self.listener(listener, port: port, isHTTP: isHTTP, changedTo: newState)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                if isHTTP {
                    self.acceptHTTP(connection)
                } else {
                    self.acceptSocket(connection)
                }
            }
        }
    }

    private func listener(_ listener: NWListener, port: NWEndpoint.Port, isHTTP: Bool, changedTo newState: NWListener.State) {
        // Ignore callbacks from listeners we've already replaced or cancelled.
        guard listener === httpListener || listener === socketListener else { return }
        switch newState {
        case .ready:
            if isHTTP { httpReady = true } else { socketReady = true }
            if httpReady && socketReady { state = .running }
        case .waiting:
            if isHTTP { httpReady = false } else { socketReady = false }
            state = .starting
        case .failed(let error):
            listenerFailed(error, port: port)
        case .setup, .cancelled:
            break
        @unknown default:
            break
        }
    }

    /// Cancels both listeners, reports the failure and retries after 10 s while not stopped.
    private func listenerFailed(_ error: Error, port: NWEndpoint.Port) {
        let message: String
        if case .posix(let code) = error as? NWError, code == .EADDRINUSE {
            message = "Port \(port.rawValue) is in use"
        } else {
            message = error.localizedDescription
        }
        cancelListeners()
        state = .failed(message)
        guard let ports = requestedPorts else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled, let self, case .failed = self.state else { return }
            self.start(httpPort: ports.http, socketPort: ports.socket)
        }
    }

    private func cancelListeners() {
        let listeners = [httpListener, socketListener]
        httpListener = nil
        socketListener = nil
        httpReady = false
        socketReady = false
        for listener in listeners {
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel()
        }
    }

    // MARK: HTTP (L11)

    private func acceptHTTP(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        httpConnections[key] = connection
        connection.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                switch newState {
                case .failed:
                    self?.httpConnections[key]?.cancel()
                case .cancelled:
                    self?.httpConnections[key] = nil
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        readRequest(on: connection, buffer: Data())
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.httpTimeout) { [weak connection] in
            connection?.cancel()
        }
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxMessageSize) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequestHead.parse(buffer) {
                case .incomplete:
                    if error != nil || isComplete {
                        connection.cancel()
                    } else {
                        self.readRequest(on: connection, buffer: buffer)
                    }
                case .tooLarge:
                    Self.respond(on: connection, with: HTTPResponse.error(431, "Request Header Fields Too Large"))
                case .invalid:
                    Self.respond(on: connection, with: HTTPResponse.error(400, "Bad Request"))
                case .complete(let head):
                    Self.respond(on: connection, with: Self.response(for: head))
                }
            }
        }
    }

    private static func response(for head: HTTPRequestHead) -> Data {
        guard head.method == "GET" || head.method == "HEAD" else {
            return HTTPResponse.error(405, "Method Not Allowed")
        }
        guard let asset = RemoteWebAssets.asset(forPath: head.path),
              let body = body(for: asset)
        else {
            return HTTPResponse.error(404, "Not Found")
        }
        return HTTPResponse.make(status: 200, reason: "OK", contentType: asset.contentType, body: body,
                                 includeBody: head.method == "GET")
    }

    private static func body(for asset: RemoteWebAsset) -> Data? {
        switch asset.generated {
        case .icon(let size): PhoneRemoteIcon.png(size: size)
        case .manifest: Data(RemoteWebManifest.json.utf8)
        case nil: RemoteWebAssets.data(for: asset)
        }
    }

    private static func respond(on connection: NWConnection, with data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: WebSocket sessions

    private func acceptSocket(_ connection: NWConnection) {
        guard authenticatedCount < Self.maxSessions else {
            Self.logger.info("Refused a phone connection: \(Self.maxSessions) already open")
            connection.cancel()
            return
        }
        let host = Self.host(of: connection.endpoint)
        let pending = sessions.values.filter { !$0.isAuthenticated }
        guard pending.count < Self.maxPending, pending.count(where: { $0.host == host }) < Self.maxPendingPerHost else {
            Self.logger.info("Refused a phone connection: too many waiting to sign in")
            connection.cancel()
            return
        }
        let id = nextSessionID
        nextSessionID += 1
        sessions[id] = Session(connection: connection, host: host)
        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            MainActor.assumeIsolated {
                switch newState {
                case .ready:
                    if let connection, Self.wasRefused(connection) { self?.endSession(id) }
                case .failed, .cancelled:
                    self?.endSession(id)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        Self.logger.info("Phone connected (\(self.sessions.count) open)")
        receiveMessage(for: id)
        Task { [weak self, signInTimeout] in
            try? await Task.sleep(for: .seconds(signInTimeout))
            guard let self, let session = self.sessions[id], !session.isAuthenticated else { return }
            Self.logger.info("Closed a phone connection that didn't sign in")
            self.endSession(id)
        }
    }

    /// The endpoint's host as text (the session's address key).
    private static func host(of endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        return "\(host)"
    }

    /// Re-armed after each message. Ends the session on an error, a close frame or EOF.
    private func receiveMessage(for id: RemoteSessionID) {
        guard let connection = sessions[id]?.connection else { return }
        connection.receiveMessage { [weak self] data, context, _, error in
            MainActor.assumeIsolated {
                guard let self, self.sessions[id] != nil else { return }
                guard error == nil else {
                    self.endSession(id)
                    return
                }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                switch metadata?.opcode {
                case .close:
                    self.endSession(id)
                    return
                case .ping, .pong:
                    break
                case .text:
                    if let data { self.onMessage?(id, data) }
                case .binary, .cont:
                    break
                default:
                    if data == nil {
                        self.endSession(id)
                        return
                    }
                }
                self.receiveMessage(for: id)
            }
        }
    }

    /// Only once per session.
    private func endSession(_ id: RemoteSessionID) {
        guard let connection = sessions.removeValue(forKey: id)?.connection else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        Self.logger.info("Phone disconnected (\(self.sessions.count) open)")
        onSessionClosed?(id)
    }
}

/// Security (pre-release review, high): which WebSocket upgrades may open a session. No Origin (a native client):
/// allowed. Else it must be exactly `http://<Host>:<HTTP port>`, the phone page's own origin, with the Host header's
/// host an IP address, `localhost` or a `.local` name, so a page on another site (including a DNS-rebinding name
/// that points at this Mac) is refused.
nonisolated enum WebSocketOrigin {
    static func isAllowed(headers: [(name: String, value: String)], httpPort: UInt16?) -> Bool {
        let origins = headers.filter { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }
        guard let origin = origins.first?.value else { return true }
        guard origins.count == 1, let httpPort,
              let hostHeader = headers.first(where: { $0.name.caseInsensitiveCompare("Host") == .orderedSame })?.value,
              let host = hostName(hostHeader), isLocalName(host)
        else { return false }
        return origin.lowercased() == "http://\(host):\(httpPort)"
    }

    /// The host part of a Host header, lowercased ("[::1]" keeps its brackets); nil when empty.
    static func hostName(_ header: String) -> String? {
        let value = header.trimmingCharacters(in: .whitespaces).lowercased()
        let host: Substring
        if value.hasPrefix("[") {
            guard let end = value.firstIndex(of: "]") else { return nil }
            host = value[...end]
        } else {
            host = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        }
        return host.isEmpty ? nil : String(host)
    }

    /// An IPv4 address, a bracketed IPv6 address, `localhost` or a Bonjour `.local` name.
    static func isLocalName(_ host: String) -> Bool {
        if host == "localhost" || (host.hasSuffix(".local") && host.count > 6) { return true }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return host.dropFirst().dropLast().allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber)
                && (Int(part) ?? 256) <= 255
        }
    }
}
