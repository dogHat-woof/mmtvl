import Darwin
import Foundation
import Network
import os
import SystemConfiguration

typealias RemoteSessionID = Int

/// What `PhoneRemote` needs from the server; tests use a fake.
protocol RemoteTransport: AnyObject {
    func send(_ message: ServerMessage, to session: RemoteSessionID)
    func close(_ session: RemoteSessionID)
    /// Security (pre-release review, low): a hello or pair succeeded; the session no longer times out and counts
    /// toward `RemoteServer.maxSessions`.
    func sessionAuthenticated(_ session: RemoteSessionID)
    /// The phone's address key (`PeerAddress.key`: an IPv6 address by its /64), for the pairing throttle; nil when
    /// unknown. Never logged.
    func peerHost(of session: RemoteSessionID) -> String?
}

/// L1: a plain-TCP HTTP listener for the phone page and a WebSocket listener for the remote. Main queue throughout.
final class RemoteServer: RemoteTransport {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")
    /// Authenticated sessions (security, pre-release review, low: sockets that haven't signed in don't count).
    static let maxSessions = 8
    /// Sessions that haven't sent a good hello or pair yet: at most this many per address, and in all (re-review L3: a
    /// full pool closes a pending session for a new one; pre-release lows (b): the oldest of the address with the most
    /// waiting, an IPv6 address counting by its /64 there; `PendingPool`). Security lows L-4: the per-address limit is
    /// by the full address (`PeerAddress.full`), so phones sharing a /64 don't share it, and an address at the limit
    /// has its own oldest waiting socket closed for the new one.
    static let maxPendingPerHost = 3
    static let maxPending = 16
    /// Pre-release lows (b): new sockets per address (IPv6: per /64) per second; more are closed before anything else.
    static let maxNewConnectionsPerSecond = 10
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
    private let maxPending: Int
    private let maxPendingPerHost: Int
    private var connectionRate: ConnectionRate

    private struct Session {
        var connection: NWConnection
        /// The peer's address key (`PeerAddress.key`); nil when the endpoint isn't host and port. Never logged.
        var host: String?
        /// Security lows L-4: the peer's full address (`PeerAddress.full`), for the per-address pending limit.
        var address: String?
        var isAuthenticated = false
    }

    /// `signInTimeout`, the pending limits and the connection rate: tests pass small ones.
    init(signInTimeout: TimeInterval = RemoteServer.defaultSignInTimeout, maxPending: Int = RemoteServer.maxPending,
         maxPendingPerHost: Int = RemoteServer.maxPendingPerHost,
         maxNewConnectionsPerSecond: Int = RemoteServer.maxNewConnectionsPerSecond) {
        self.signInTimeout = signInTimeout
        self.maxPending = maxPending
        self.maxPendingPerHost = maxPendingPerHost
        connectionRate = ConnectionRate(limit: maxNewConnectionsPerSecond)
    }

    func start(httpPort: NWEndpoint.Port, socketPort: NWEndpoint.Port) {
        // Pre-release lows (d): the Mac's own names, for `WebSocketOrigin` (the slow ones are read off the main queue).
        MacHostNames.refresh()
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
        let host = Self.host(of: connection.endpoint)
        let address = Self.address(of: connection.endpoint)
        // Pre-release lows (b): an address opening sockets faster than a phone ever would is refused before it can
        // take a pending slot.
        guard connectionRate.allows(host, now: Date()) else {
            Self.logger.info("Refused a phone connection: too many new ones from its address")
            connection.cancel()
            return
        }
        guard authenticatedCount < Self.maxSessions else {
            Self.logger.info("Refused a phone connection: \(Self.maxSessions) already open")
            connection.cancel()
            return
        }
        let entries = sessions.map {
            PendingPool.Entry(id: $0.key, host: $0.value.host, address: $0.value.address,
                              isAuthenticated: $0.value.isAuthenticated)
        }
        switch PendingPool.admit(host: host, address: address, sessions: entries, maxPending: maxPending,
                                 maxPendingPerHost: maxPendingPerHost) {
        case .acceptReplacing(let oldest):
            // Security lows L-4: the address's own oldest waiting socket makes way, so a phone that left sockets
            // behind (or one sharing nothing but a /64 with a flooder) still gets in.
            Self.logger.info("Closed a phone connection waiting to sign in: \(self.maxPendingPerHost) waiting from its address")
            endSession(oldest)
        case .acceptEvicting(let oldest):
            // Re-review L3, pre-release lows (b): a peer with many addresses can't hold every pending slot and keep a
            // phone out; the one closed is from the address with the most waiting, not the phone's.
            Self.logger.info("Closed a phone connection waiting to sign in: \(self.maxPending) waiting")
            endSession(oldest)
        case .accept:
            break
        }
        let id = nextSessionID
        nextSessionID += 1
        sessions[id] = Session(connection: connection, host: host, address: address)
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

    /// The endpoint's address key (`PeerAddress.key`: IPv4 as is, IPv6 by its /64).
    private static func host(of endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        return PeerAddress.key("\(host)")
    }

    /// Security lows L-4: the endpoint's full address (`PeerAddress.full`).
    private static func address(of endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        return PeerAddress.full("\(host)")
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

/// Which sockets that haven't signed in yet are kept (security, pre-release review, low; re-review L3; pre-release
/// lows (b); security lows L-4). `host` is the address key (`PeerAddress.key`, an IPv6 address by its /64) and
/// `address` the full address (`PeerAddress.full`). Pure.
nonisolated enum PendingPool {
    struct Entry: Equatable, Sendable {
        var id: RemoteSessionID
        var host: String?
        /// The full address; nil: the same as `host`.
        var address: String?
        var isAuthenticated: Bool

        init(id: RemoteSessionID, host: String?, address: String? = nil, isAuthenticated: Bool) {
            self.id = id
            self.host = host
            self.address = address ?? host
            self.isAuthenticated = isAuthenticated
        }
    }

    enum Decision: Equatable, Sendable {
        case accept
        /// The pool is full: close this pending session and take the new one.
        case acceptEvicting(RemoteSessionID)
        /// Security lows L-4: the new socket's address already has `maxPendingPerHost` waiting: close its oldest
        /// waiting session and take the new one.
        case acceptReplacing(RemoteSessionID)
    }

    /// Authenticated sessions are never evicted (they don't count here; `RemoteServer.maxSessions` limits them).
    /// Security lows L-4: an address (in full; `address` nil: `host`) with `maxPendingPerHost` waiting has its oldest
    /// one closed for the new one, never another address's. Pre-release lows (b): else a full pool closes the oldest
    /// pending session (the lowest id) of the address key with the most waiting (ties: the oldest of those keys'
    /// sessions), so addresses flooding the pool churn among themselves and a phone with one socket waiting keeps it.
    static func admit(host: String?, address: String? = nil, sessions: [Entry], maxPending: Int,
                      maxPendingPerHost: Int) -> Decision {
        let pending = sessions.filter { !$0.isAuthenticated }
        let address = address ?? host
        let fromAddress = pending.filter { $0.address == address }
        if fromAddress.count >= maxPendingPerHost, let oldest = fromAddress.map(\.id).min() {
            return .acceptReplacing(oldest)
        }
        guard pending.count >= maxPending else { return .accept }
        var counts: [String?: Int] = [:]
        for entry in pending { counts[entry.host, default: 0] += 1 }
        guard let most = counts.values.max(),
              let victim = pending.filter({ counts[$0.host] == most }).map(\.id).min()
        else { return .accept }
        return .acceptEvicting(victim)
    }
}

/// Pre-release lows (b): new sockets per address key in fixed one-second windows. Pure (the caller passes the time).
nonisolated struct ConnectionRate: Sendable {
    let limit: Int
    static let window: TimeInterval = 1
    /// More keys than this: windows that are over are dropped.
    static let maxKeys = 1024
    private var windows: [String: (start: Date, count: Int)] = [:]

    init(limit: Int) { self.limit = limit }

    /// Whether a new socket from `host` (an address key; nil counts as one unknown address) is let in; counts it.
    mutating func allows(_ host: String?, now: Date) -> Bool {
        let key = host ?? ""
        if windows.count > Self.maxKeys {
            windows = windows.filter { now.timeIntervalSince($0.value.start) < Self.window }
        }
        if let current = windows[key], now >= current.start, now.timeIntervalSince(current.start) < Self.window {
            guard current.count < limit else { return false }
            windows[key] = (current.start, current.count + 1)
            return true
        }
        windows[key] = (now, 1)
        return limit > 0
    }
}

/// Pre-release lows (b): the key a peer's address counts under for the pending pool's eviction, the connection rate
/// and the pairing throttle. IPv4 as is; an IPv4-mapped IPv6 address as its IPv4; any other IPv6 address by its /64
/// (one host can use any address in its /64, so it counts once; all link-local peers share fe80::/64). Security lows
/// L-4: `full`, the whole address, for the per-address pending limit. Never logged.
nonisolated enum PeerAddress {
    static func key(_ host: String) -> String {
        guard let bytes = parse(host)?.bytes else { return plain(host) }
        if let v4 = embeddedIPv4(bytes) { return v4 }
        let groups = stride(from: 0, to: 8, by: 2).map { String(format: "%x", UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])) }
        return groups.joined(separator: ":") + "::/64"
    }

    /// Security lows L-4: the whole address, one spelling per address: IPv4 as is, IPv4-mapped IPv6 as its IPv4, any
    /// other IPv6 address in all 8 groups, with its zone ("fe80:0:0:0:0:0:0:1%en0").
    static func full(_ host: String) -> String {
        guard let parsed = parse(host) else { return plain(host) }
        let bytes = parsed.bytes
        if let v4 = embeddedIPv4(bytes) { return v4 }
        let groups = stride(from: 0, to: 16, by: 2).map { String(format: "%x", UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])) }
        let zone = parsed.text.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first
        return groups.joined(separator: ":") + (zone.map { "%\($0)" } ?? "")
    }

    /// Lowercased, without brackets.
    private static func plain(_ host: String) -> String {
        var text = host.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("["), text.hasSuffix("]") { text = String(text.dropFirst().dropLast()) }
        return text
    }

    /// An IPv6 literal: its plain text (zone kept) and its 16 bytes.
    private static func parse(_ host: String) -> (text: String, bytes: [UInt8])? {
        let text = plain(host)
        let address = text.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        var v6 = in6_addr()
        guard address.contains(":"), inet_pton(AF_INET6, address, &v6) == 1 else { return nil }
        return (text, withUnsafeBytes(of: &v6) { Array($0) })
    }

    private static func embeddedIPv4(_ bytes: [UInt8]) -> String? {
        guard bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF else { return nil }
        return bytes[12..<16].map(String.init).joined(separator: ".")
    }
}

/// Pre-release lows (d): this Mac's own host names, lowercased first labels, for `WebSocketOrigin`: the kernel host
/// name (`gethostname`, which macOS sets from the network's DNS name for the Mac when none is set by hand), the
/// Bonjour local host name (`SCDynamicStoreCopyLocalHostName`, the `<name>.local` one), and `ProcessInfo.hostName`
/// (which may wait on DNS, so `refresh` reads it off the main queue and `current` uses the last value).
nonisolated enum MacHostNames {
    private static let slowNames = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    static func current() -> Set<String> {
        var names = slowNames.withLock { $0 }
        var buffer = [CChar](repeating: 0, count: 256)
        if gethostname(&buffer, buffer.count) == 0 {
            names.formUnion(firstLabel(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)))
        }
        if let local = SCDynamicStoreCopyLocalHostName(nil) as String? { names.formUnion(firstLabel(local)) }
        return names
    }

    /// Reads `ProcessInfo.hostName` in the background for `current`.
    static func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let names = firstLabel(ProcessInfo.processInfo.hostName)
            slowNames.withLock { $0 = names }
        }
    }

    /// "Mac-mini.lan" → ["mac-mini"]; empty, "localhost" or an IP literal → [].
    static func firstLabel(_ name: String) -> Set<String> {
        let lowered = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lowered.contains(":"), let label = lowered.split(separator: ".").first, !label.isEmpty,
              label != "localhost", !label.allSatisfy(\.isNumber)
        else { return [] }
        return [String(label)]
    }
}

/// Security (pre-release review, high): which WebSocket upgrades may open a session. No Origin (a native client):
/// allowed. Else it must be exactly `http://<Host>:<HTTP port>`, the phone page's own origin, with the Host header's
/// host an IP address, `localhost`, or a name for this Mac: a `.local` name, or (re-review L4) a router's name for the
/// Mac: a dotless name, `.lan` or `.home.arpa`. Pre-release lows (d): a name's first label must be one of the Mac's
/// own names (`MacHostNames`), since `.lan` and dotless names aren't reserved and a rebinding name there could point
/// at this Mac; the page still works by IP address, which the QR code uses. A page on any other site, including a
/// DNS-rebinding name that points at this Mac, is refused.
nonisolated enum WebSocketOrigin {
    /// `ownNames`: the Mac's names (lowercased first labels); tests pass their own.
    static func isAllowed(headers: [(name: String, value: String)], httpPort: UInt16?,
                          ownNames: @autoclosure () -> Set<String> = MacHostNames.current()) -> Bool {
        let origins = headers.filter { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }
        guard let origin = origins.first?.value else { return true }
        guard origins.count == 1, let httpPort,
              let hostHeader = headers.first(where: { $0.name.caseInsensitiveCompare("Host") == .orderedSame })?.value,
              let host = hostName(hostHeader), isLocalName(host, ownNames: ownNames())
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

    /// An IPv4 address, a bracketed IPv6 address, `localhost`, a Bonjour `.local` name, or (re-review L4) a name the
    /// router's DNS gives: dotless ("mm") or under `.lan` or `.home.arpa` (RFC 8375), each label letters, digits and
    /// hyphens. Never another dotted name: anyone can register one and point it at this Mac. Pre-release lows (d): a
    /// `.local`, `.lan`, `.home.arpa` or dotless name only when its first label is in `ownNames` (the Mac's own names,
    /// lowercased first labels; `MacHostNames`), so "other.lan" is refused.
    static func isLocalName(_ host: String, ownNames: Set<String>) -> Bool {
        if host == "localhost" { return true }
        func isOwn(_ labels: [Substring]) -> Bool {
            guard let first = labels.first else { return false }
            return labels.allSatisfy(isHostLabel) && ownNames.contains(first.lowercased())
        }
        for suffix in [".local", ".lan", ".home.arpa"] where host.hasSuffix(suffix) {
            return isOwn(host.dropLast(suffix.count).split(separator: ".", omittingEmptySubsequences: false))
        }
        if !host.contains("."), !host.contains(":"), !host.hasPrefix("[") { return isOwn([Substring(host)]) }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return host.dropFirst().dropLast().allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber)
                && (Int(part) ?? 256) <= 255
        }
    }

    /// 1…63 ASCII letters, digits and hyphens, not starting or ending with a hyphen.
    private static func isHostLabel(_ label: Substring) -> Bool {
        (1...63).contains(label.count) && label.first != "-" && label.last != "-"
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
