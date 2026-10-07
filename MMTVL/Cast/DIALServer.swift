import Foundation
import Network
import os

/// What the cast receiver needs from YouTube and the app (AppDelegate wires it; tests can fake it).
struct CastBridge {
    /// YouTubeController.isDIALReady.
    var isAppReady: () -> Bool
    /// YouTubeController.handleDIAL; nil = leanback can't answer (L8).
    var forward: (DIALAppRequest) async -> DIALAppResponse?
    /// Cold launch (L2) → AppDelegate.castToTV(query:).
    var launch: (String?) -> Void
    /// Leanback answered a POST with 201 → castToTV(query: nil).
    var didConnect: () -> Void
}

/// The DIAL REST server (D30): device description natively, `/apps/YouTube` forwarded to leanback or
/// answered natively (L1, L2). Main queue throughout.
final class DIALServer {
    static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Cast")
    static let preferredPort: NWEndpoint.Port = 8770
    private static let requestTimeout: TimeInterval = 10
    /// L9.
    private static let launchingWindow: TimeInterval = 30

    enum State: Equatable { case stopped, starting, running, failed(String) }

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            onStateChange?()
        }
    }
    var onStateChange: (() -> Void)?
    var port: UInt16? { listener?.port?.rawValue }
    /// Injectable clock (tests).
    var now: () -> Date = Date.init

    private let deviceID: String
    private let friendlyName: String
    private let bridge: CastBridge
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var launchingUntil: Date?

    init(deviceID: String, friendlyName: String, bridge: CastBridge) {
        self.deviceID = deviceID
        self.friendlyName = friendlyName
        self.bridge = bridge
    }

    /// L3: `port`, else any free port if it's in use.
    func start(port: NWEndpoint.Port = preferredPort) {
        cancelListener()
        state = .starting
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                MainActor.assumeIsolated {
                    guard let self, let listener, listener === self.listener else { return }
                    self.listenerChanged(to: newState, port: port)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    guard let self else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection)
                }
            }
            listener.start(queue: .main)
        } catch {
            failed(error, port: port)
        }
    }

    func stop() {
        cancelListener()
        for connection in connections.values { connection.cancel() }
        connections = [:]
        launchingUntil = nil
        state = .stopped
    }

    private func listenerChanged(to newState: NWListener.State, port: NWEndpoint.Port) {
        switch newState {
        case .ready:
            Self.logger.info("DIAL server on port \(self.port ?? 0)")
            state = .running
        case .waiting(let error):
            if case .posix(.EADDRINUSE) = error {
                failed(error, port: port)
            } else {
                state = .starting
            }
        case .failed(let error):
            failed(error, port: port)
        case .setup, .cancelled:
            break
        @unknown default:
            break
        }
    }

    private func failed(_ error: Error, port: NWEndpoint.Port) {
        if case .posix(let code) = error as? NWError, code == .EADDRINUSE, port != .any {
            Self.logger.info("Port \(port.rawValue) is in use; using any free port")
            start(port: .any)
            return
        }
        cancelListener()
        Self.logger.error("DIAL server failed: \(error.localizedDescription, privacy: .public)")
        state = .failed(error.localizedDescription)
    }

    private func cancelListener() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: Requests (Request flow)

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                switch newState {
                case .failed:
                    self?.connections[key]?.cancel()
                case .cancelled:
                    self?.connections[key] = nil
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        read(on: connection, buffer: Data())
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak connection] in
            connection?.cancel()
        }
    }

    private func read(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch DIALRequest.parse(buffer) {
                case .incomplete:
                    if error != nil || isComplete {
                        connection.cancel()
                    } else {
                        self.read(on: connection, buffer: buffer)
                    }
                case .tooLarge(let status):
                    self.send(.error(status), for: nil, on: connection)
                case .invalid:
                    self.send(.error(400), for: nil, on: connection)
                case .complete(let request):
                    self.handle(request, on: connection)
                }
            }
        }
    }

    private func handle(_ request: DIALRequest, on connection: NWConnection) {
        let context = makeContext(for: connection)
        execute(DIALRouting.decide(request, context: context), request: request, context: context, on: connection)
    }

    private func makeContext(for connection: NWConnection) -> DIALContext {
        let ip = Self.localIPv4(of: connection) ?? LocalAddress.primaryIPv4() ?? "127.0.0.1"
        let appReady = bridge.isAppReady()
        let isLaunching = launchingUntil.map { now() < $0 } == true && !appReady
        return DIALContext(host: "\(ip):\(port ?? 0)", deviceID: deviceID, friendlyName: friendlyName,
                           appReady: appReady, isLaunching: isLaunching)
    }

    private func execute(_ decision: DIALDecision, request: DIALRequest, context: DIALContext, on connection: NWConnection) {
        switch decision {
        case .reply(let reply):
            send(reply, for: request, on: connection)
        case .launch(let query):
            launchingUntil = now().addingTimeInterval(Self.launchingWindow)
            let location = HTTPHeader(name: "LOCATION", value: "http://\(context.host)/apps/\(DIALRouting.appName)/run")
            send(DIALReply(status: 201, contentType: nil, headers: [location]), for: request, on: connection)
            Self.logger.info("Opening YouTube for a cast (cold)")
            bridge.launch(query)
        case .forward(let appRequest):
            Task {
                let response = await bridge.forward(appRequest)
                guard let response else {
                    var cold = context
                    cold.appReady = false
                    let fallback = DIALRouting.nativeAppDecision(request, subpath: appRequest.path, context: cold)
                    execute(fallback, request: request, context: cold, on: connection)
                    return
                }
                let reply = DIALRouting.reply(for: response)
                send(reply, for: request, on: connection)
                if request.method == "POST" && reply.status == 201 {
                    Self.logger.info("A phone connected through leanback")
                    bridge.didConnect()
                }
            }
        }
    }

    /// L7: logs method, path (no query), status and the client's IP; never bodies.
    private func send(_ reply: DIALReply, for request: DIALRequest?, on connection: NWConnection) {
        let client = Self.remoteHost(of: connection) ?? "?"
        Self.logger.info("\(request?.method ?? "?", privacy: .public) \(request?.path ?? "?", privacy: .public) → \(reply.status) from \(client, privacy: .public)")
        connection.send(content: reply.encoded(), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func localIPv4(of connection: NWConnection) -> String? {
        guard case .hostPort(let host, _) = connection.currentPath?.localEndpoint,
              case .ipv4(let address) = host else { return nil }
        return address.rawValue.map(String.init).joined(separator: ".")
    }

    private static func remoteHost(of connection: NWConnection) -> String? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        switch host {
        case .ipv4(let address): return address.rawValue.map(String.init).joined(separator: ".")
        case .ipv6(let address): return "\(address)"
        case .name(let name, _): return name
        @unknown default: return nil
        }
    }
}
