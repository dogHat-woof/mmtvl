import Foundation
import Network
import os

/// YouTube casting by DIAL (D30): owns the DIAL server and the SSDP responder, and restarts discovery when the
/// network changes or the Mac wakes.
final class CastReceiver {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Cast")

    enum State: Equatable { case off, starting, ready, failed(String) }

    private(set) var state: State = .off {
        didSet {
            guard state != oldValue else { return }
            Self.logger.info("Casting \(String(describing: self.state), privacy: .public)")
            onStateChange?()
        }
    }
    var onStateChange: (() -> Void)?

    private let deviceID: String
    private let server: DIALServer
    private let responder = SSDPResponder()
    private var isStarted = false
    private var noAddress = false
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?

    init(deviceID: String, friendlyName: String, bridge: CastBridge) {
        self.deviceID = deviceID
        server = DIALServer(deviceID: deviceID, friendlyName: friendlyName, bridge: bridge)
        server.onStateChange = { [weak self] in self?.serverChanged() }
        responder.onStateChange = { [weak self] in self?.updateState() }
    }

    /// The DIAL server first (SSDP needs its port), then the responder.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        state = .starting
        server.start()
        monitorPath()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pathMonitor?.cancel()
        pathMonitor = nil
        lastPathSignature = nil
        responder.stop()
        server.stop()
        noAddress = false
        state = .off
    }

    /// Wake or network change: re-join multicast with the current address.
    func restart() {
        guard isStarted else { return }
        Self.logger.info("Restarting discovery")
        if case .failed = server.state {
            server.start()
        } else {
            startResponder()
        }
    }

    private func serverChanged() {
        if server.state == .running && responder.state != .running {
            startResponder()
        }
        updateState()
    }

    private func startResponder() {
        responder.stop()
        guard server.state == .running, let port = server.port else {
            updateState()
            return
        }
        guard let ip = LocalAddress.primaryIPv4() else {
            noAddress = true
            updateState()
            return
        }
        noAddress = false
        responder.start(interfaceIPv4: ip, location: "http://\(ip):\(port)/dd.xml", deviceID: deviceID)
        updateState()
    }

    private func updateState() {
        guard isStarted else {
            state = .off
            return
        }
        if case .failed(let message) = server.state {
            state = .failed(message)
        } else if noAddress {
            state = .failed("No network connection")
        } else if case .failed(let message) = responder.state {
            state = .failed(message)
        } else if server.state == .running && responder.state == .running {
            state = .ready
        } else {
            state = .starting
        }
    }

    /// Restarts discovery when the path's status or interfaces change (the first update only records them).
    private func monitorPath() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = "\(path.status)|" + path.availableInterfaces.map(\.name).joined(separator: ",")
            MainActor.assumeIsolated {
                guard let self else { return }
                defer { self.lastPathSignature = signature }
                guard let last = self.lastPathSignature, last != signature else { return }
                self.restart()
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }
}
