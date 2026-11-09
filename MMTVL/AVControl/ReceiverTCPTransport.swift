import Foundation
import Network
import os

/// L17: received TCP bytes → reply lines, through the brand's network framing (eISCP for Onkyo), then the same line
/// splitting as serial. Pure.
nonisolated struct ReceiverStreamDecoder: Sendable {
    let framing: ReceiverNetworkFraming
    private var splitter: SerialLineSplitter
    private var deframer = EISCP.Deframer()
    /// Ends each eISCP message's data, so a message without its own delimiter is still a whole line.
    private let endOfMessage: UInt8

    init(framing: ReceiverNetworkFraming, delimiters: Set<UInt8>) {
        self.framing = framing
        endOfMessage = delimiters.min() ?? ReceiverLine.cr
        splitter = SerialLineSplitter(delimiters: delimiters.union([endOfMessage]))
    }

    mutating func append(_ bytes: some Sequence<UInt8>) -> [String] {
        switch framing {
        case .plain:
            return splitter.append(bytes)
        case .eISCP:
            return deframer.append(bytes).flatMap { splitter.append($0 + [endOfMessage]) }
        }
    }

    /// One command's bytes as they go on the wire.
    func frame(_ bytes: [UInt8]) -> [UInt8] {
        switch framing {
        case .plain: bytes
        case .eISCP: EISCP.frame(bytes)
        }
    }
}

/// M7h L17: a receiver's control port over TCP (Network.framework), carrying the same `ReceiverProtocol` bytes as
/// serial, framed per `networkFraming`. Keep-alive on. Tries each port in turn until one accepts (Pioneer: 23, then
/// 8102); `onReady` once one does, `onClose` once when none does or the connection ends. `ReceiverController` owns
/// the reconnect backoff and the idle close. Never over loopback, and a connection whose resolved remote address
/// isn't on the LAN (`isLANRemote`; a name that resolved elsewhere) is closed before anything is written. Logs show
/// host and port only. **Untested on a real networked receiver.**
final class ReceiverTCPTransport: ReceiverTransport {
    nonisolated private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Receiver")

    /// Per port: a connection that isn't up by then counts as refused.
    static let connectTimeout: Duration = .seconds(2)
    /// TCP keep-alive: first probe after this long idle (seconds).
    static let keepAliveIdle = 30
    static let readSize = 4096

    /// "host:port", for logs.
    private(set) var name: String
    var onLine: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onReady: (() -> Void)?
    private(set) var isReady = false
    /// The connection reached an address outside the LAN (a name that resolved there); see `ReceiverTransport`.
    private(set) var closedForConfiguration = false
    /// M7h step 11: the last port's failure in plain words (`plainReason`), for Test Connection.
    private(set) var failureReason: String?

    private let host: String
    private var remainingPorts: [UInt16]
    private var connection: NWConnection?
    private var decoder: ReceiverStreamDecoder
    /// Bumped for each connection attempt, so a replaced connection's late callbacks are ignored.
    private var attempt = 0
    private var timeoutTask: Task<Void, Never>?
    private var isClosed = false
    /// Off only in tests against a loopback listener.
    private let requiresLAN: Bool

    /// Starts connecting to `host` on the first of `ports` at once. `ports` must hold a port other than 0.
    /// `requiresLAN: false` is for tests only (it allows loopback).
    init(host: String, ports: [UInt16], framing: ReceiverNetworkFraming, delimiters: Set<UInt8>,
         requiresLAN: Bool = true) {
        let ports = ports.filter { $0 != 0 }
        precondition(!ports.isEmpty, "ReceiverTCPTransport needs a port")
        self.host = host
        self.requiresLAN = requiresLAN
        remainingPorts = ports
        name = LANAddress.display(host: host, port: ports[0])
        decoder = ReceiverStreamDecoder(framing: framing, delimiters: delimiters)
        startNextPort()
    }

    isolated deinit {
        close()
    }

    /// Sends one command's bytes (framed). False before the connection is up or after it closed.
    @discardableResult
    func write(_ bytes: [UInt8]) -> Bool {
        guard isReady, !isClosed, let connection else { return false }
        let name = name
        connection.send(content: Data(decoder.frame(bytes)), completion: .contentProcessed { error in
            if let error {
                Self.logger.notice("Receiver: send to \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        })
        return true
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        isReady = false
        attempt += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: Connecting

    private func startNextPort() {
        guard !isClosed else { return }
        guard !remainingPorts.isEmpty else {
            closeAndNotify()
            return
        }
        let port = remainingPorts.removeFirst()
        name = LANAddress.display(host: host, port: port)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            startNextPort()
            return
        }
        attempt += 1
        let current = attempt
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = Self.keepAliveIdle
        tcp.noDelay = true
        tcp.connectionTimeout = Int(Self.connectTimeout.components.seconds)
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if requiresLAN { parameters.prohibitedInterfaceTypes = [.loopback] }
        // Security S2 (step 9b): straight to the receiver, never through a system proxy.
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.stateChanged(state, attempt: current) }
        }
        connection.start(queue: .main)
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.connectTimeout)
            guard !Task.isCancelled, let self, attempt == current, !isReady else { return }
            portFailed("timed out", plain: "No answer")
        }
    }

    private func stateChanged(_ state: NWConnection.State, attempt current: Int) {
        guard current == attempt, !isClosed else { return }
        switch state {
        case .ready:
            timeoutTask?.cancel()
            timeoutTask = nil
            if requiresLAN {
                let path = connection?.currentPath
                guard path?.usesInterfaceType(.loopback) != true,
                      let remote = path?.remoteEndpoint, Self.isLANRemote(remote) else {
                    Self.logger.notice("Receiver: \(self.host, privacy: .public) isn't on the LAN; not connecting")
                    closedForConfiguration = true
                    failureReason = "The address isn't on this network"
                    closeAndNotify()
                    return
                }
            }
            isReady = true
            Self.logger.info("Receiver: connected to \(self.name, privacy: .public)")
            if let connection { receive(on: connection, attempt: current) }
            onReady?()
        case .waiting(let error), .failed(let error):
            // `waiting` would retry on its own (refused, no route); the controller owns the backoff instead.
            if isReady {
                Self.logger.notice("Receiver: \(self.name, privacy: .public) closed: \(error.localizedDescription, privacy: .public)")
                failureReason = "The receiver closed the connection"
                closeAndNotify()
            } else {
                portFailed(error.localizedDescription, plain: Self.plainReason(error))
            }
        case .cancelled, .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    /// This port didn't accept: the next one, or `onClose`. `plain`: Settings' words for it (`failureReason`).
    private func portFailed(_ reason: String, plain: String) {
        failureReason = plain
        Self.logger.notice("Receiver: can't connect to \(self.name, privacy: .public): \(reason, privacy: .public)")
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        startNextPort()
    }

    private func receive(on connection: NWConnection, attempt current: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.readSize) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                self?.received(data, isComplete: isComplete, failed: error != nil, attempt: current)
            }
        }
    }

    private func received(_ data: Data?, isComplete: Bool, failed: Bool, attempt current: Int) {
        guard current == attempt, !isClosed else { return }
        if let data, !data.isEmpty {
            for line in decoder.append(data) {
                onLine?(line)
                // `onLine` may have closed this transport.
                guard current == attempt, !isClosed else { return }
            }
        }
        if isComplete || failed {
            Self.logger.notice("Receiver: \(self.name, privacy: .public) closed the connection")
            closeAndNotify()
            return
        }
        if let connection { receive(on: connection, attempt: current) }
    }

    private func closeAndNotify() {
        close()
        let onClose = self.onClose
        self.onClose = nil
        onClose?()
    }

    /// M7h step 11: a connection error in plain words for Settings → Test Connection. Pure.
    nonisolated static func plainReason(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: "Connection refused"
            case .ETIMEDOUT: "No answer"
            case .EHOSTUNREACH, .EHOSTDOWN: "Can't reach the address"
            case .ENETUNREACH, .ENETDOWN: "No network connection"
            default: "Can't connect"
            }
        case .dns: "Can't find that name"
        default: "Can't connect"
        }
    }

    /// The address a connection reached is a LAN IP (`LANAddress`): never a name, loopback, or an IPv6 address on a
    /// loopback interface. Pure.
    nonisolated static func isLANRemote(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return LANAddress.isPrivate(ipv4: Array(address.rawValue))
        case .ipv6(let address):
            if address.interface?.type == .loopback { return false }
            if address.isIPv4Mapped, let v4 = address.asIPv4 { return LANAddress.isPrivate(ipv4: Array(v4.rawValue)) }
            return LANAddress.isLAN(ipv6: Array(address.rawValue))
        case .name:
            return false
        @unknown default:
            return false
        }
    }

    /// L17: `ReceiverController`'s factory for `.network`: `host` (`LANAddress.isAllowedReceiverHost`; a name must
    /// resolve to a LAN address) on `port`, or the brand's control ports.
    static func receiverTransport(host: String, port: UInt16?, codec: any ReceiverProtocol) -> (any ReceiverTransport)? {
        guard let host = LANAddress.normalized(host), LANAddress.isAllowedReceiverHost(host) else {
            logger.debug("Receiver: the address isn't a LAN address or host name")
            return nil
        }
        let ports = codec.networkPorts(override: port).filter { $0 != 0 }
        guard !ports.isEmpty else { return nil }
        return ReceiverTCPTransport(host: host, ports: ports, framing: codec.networkFraming,
                                    delimiters: codec.lineDelimiters)
    }
}
