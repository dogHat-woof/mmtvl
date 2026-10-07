import Darwin
import Foundation
import os

/// Answers DIAL M-SEARCHes on UDP 1900 by unicast (D30, L3). A BSD socket on the main queue.
final class SSDPResponder {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Cast")

    enum State: Equatable { case stopped, running, failed(String) }

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            onStateChange?()
        }
    }
    var onStateChange: (() -> Void)?

    private var source: DispatchSourceRead?
    private var location = ""
    private var deviceID = ""
    private var reportedSendFailure = false
    private let server = "macOS/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) UPnP/1.1 MMTVL/1.0"

    /// Binds UDP 1900 (shared with other SSDP users) and joins the multicast group on `interfaceIPv4`.
    func start(interfaceIPv4: String, location: String, deviceID: String) {
        stop()
        self.location = location
        self.deviceID = deviceID
        reportedSendFailure = false

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            fail(errno, fd: nil)
            return
        }
        var yes: Int32 = 1
        let size = socklen_t(MemoryLayout<Int32>.size)
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, size) == 0,
              setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, size) == 0
        else {
            fail(errno, fd: fd)
            return
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = SSDP.port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            fail(errno, fd: fd)
            return
        }

        var request = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(SSDP.multicastAddress)),
                              imr_interface: in_addr(s_addr: inet_addr(interfaceIPv4)))
        guard setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size)) == 0 else {
            fail(errno, fd: fd)
            return
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readDatagrams(fd) }
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
        state = .running
        Self.logger.info("Answering DIAL searches on \(interfaceIPv4, privacy: .public)")
    }

    func stop() {
        source?.cancel()
        source = nil
        state = .stopped
    }

    private func fail(_ code: Int32, fd: Int32?) {
        if let fd { close(fd) }
        let message = code == EADDRINUSE ? "Port 1900 is in use" : String(cString: strerror(code))
        Self.logger.error("SSDP failed: \(message, privacy: .public)")
        state = .failed(message)
    }

    private func readDatagrams(_ fd: Int32) {
        let capacity = 2048
        var buffer = [UInt8](repeating: 0, count: capacity)
        while true {
            var sender = sockaddr_storage()
            var senderLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, capacity, 0, $0, &senderLength)
                }
            }
            guard count > 0 else { return }
            guard SSDP.isDIALSearch(Data(buffer[0..<count])) else { continue }
            answer(fd: fd, sender: &sender, senderLength: senderLength)
        }
    }

    private func answer(fd: Int32, sender: inout sockaddr_storage, senderLength: socklen_t) {
        let reply = SSDP.searchReply(location: location, deviceID: deviceID, server: server, date: Date())
        let client = Self.describe(&sender)
        let sent = reply.withUnsafeBytes { bytes in
            withUnsafePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, senderLength)
                }
            }
        }
        if sent < 0 {
            let code = errno
            guard !reportedSendFailure else { return }
            reportedSendFailure = true
            if code == EHOSTUNREACH || code == EPERM {
                Self.logger.error("Can't answer phones: allow Local Network for MMTVL in System Settings → Privacy & Security")
                state = .failed("Allow Local Network for MMTVL in System Settings")
            } else {
                Self.logger.error("Can't answer a DIAL search: \(String(cString: strerror(code)), privacy: .public)")
            }
            return
        }
        Self.logger.info("Answered a DIAL search from \(client, privacy: .public)")
    }

    private static func describe(_ address: inout sockaddr_storage) -> String {
        guard address.ss_family == sa_family_t(AF_INET) else { return "?" }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                String(cString: inet_ntoa(sin.pointee.sin_addr))
            }
        }
    }
}
