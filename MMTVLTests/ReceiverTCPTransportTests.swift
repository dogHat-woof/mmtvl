import Foundation
import Network
import Testing
@testable import MMTVL

/// M7h L17: the real `ReceiverTCPTransport` against an in-process loopback listener playing an eISCP receiver
/// (`requiresLAN: false`, for tests only; the app never connects over loopback). Untested on a real receiver.
struct ReceiverTCPTransportTests {
    /// M7h step 11: Test Connection's words for connection errors.
    @Test func plainReasons() {
        #expect(ReceiverTCPTransport.plainReason(.posix(.ECONNREFUSED)) == "Connection refused")
        #expect(ReceiverTCPTransport.plainReason(.posix(.ETIMEDOUT)) == "No answer")
        #expect(ReceiverTCPTransport.plainReason(.posix(.EHOSTUNREACH)) == "Can't reach the address")
        #expect(ReceiverTCPTransport.plainReason(.posix(.ENETDOWN)) == "No network connection")
        #expect(ReceiverTCPTransport.plainReason(.posix(.EPERM)) == "Can't connect")
        #expect(ReceiverTCPTransport.plainReason(.dns(DNSServiceErrorType(-65554))) == "Can't find that name")
    }

    /// Accepts one connection, records what it receives and answers each eISCP query with `reply`.
    final class FakeReceiverServer {
        let listener: NWListener
        private(set) var received: [UInt8] = []
        private var connection: NWConnection?
        var reply: [UInt8] = []

        init() throws {
            listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
        }

        /// Once the listener is up (0 before).
        var port: UInt16? { listener.port.map(\.rawValue).flatMap { $0 == 0 ? nil : $0 } }

        private func accept(_ connection: NWConnection) {
            self.connection = connection
            connection.start(queue: .main)
            receive(on: connection)
        }

        private func receive(on connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let data {
                        self.received.append(contentsOf: data)
                        if !self.reply.isEmpty { connection.send(content: Data(self.reply), completion: .idempotent) }
                    }
                    if !isComplete { self.receive(on: connection) }
                }
            }
        }

        func hangUp() { connection?.cancel() }

        func stop() {
            connection?.cancel()
            listener.cancel()
        }
    }

    private func wait(until condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func connectsFramesAndUnframesOverLoopback() async throws {
        let server = try FakeReceiverServer()
        await wait { server.port != nil }
        let port = try #require(server.port)
        server.reply = EISCP.frame(Array("!1PWR01\u{1A}\r\n".utf8))
        let codec = OnkyoProtocol()
        // Port 1 refuses: the transport moves on to the next port.
        let transport = ReceiverTCPTransport(host: "127.0.0.1", ports: [1, port], framing: codec.networkFraming,
                                             delimiters: codec.lineDelimiters, requiresLAN: false)
        var lines: [String] = []
        var readyCalls = 0
        var closed = false
        transport.onLine = { lines.append($0) }
        transport.onReady = { readyCalls += 1 }
        transport.onClose = { closed = true }
        #expect(!transport.write(codec.encode(.queryPower)))   // not up yet
        await wait { transport.isReady || closed }
        #expect(transport.isReady)
        #expect(readyCalls == 1)
        #expect(transport.name == "127.0.0.1:\(port)")
        #expect(transport.write(codec.encode(.queryPower)))
        await wait { !lines.isEmpty }
        #expect(server.received == EISCP.frame(Array("!1PWRQSTN\r".utf8)))
        #expect(lines == ["!1PWR01"])
        #expect(lines.first.flatMap(codec.parse(line:)) == .power(true))
        server.hangUp()
        await wait { closed }
        #expect(closed)
        #expect(!transport.isReady)
        #expect(!transport.write(codec.encode(.queryPower)))
        server.stop()
    }

    @Test func noPortAcceptingCloses() async {
        let codec = DenonProtocol()
        let transport = ReceiverTCPTransport(host: "127.0.0.1", ports: [1], framing: codec.networkFraming,
                                             delimiters: codec.lineDelimiters, requiresLAN: false)
        var closed = false
        transport.onClose = { closed = true }
        await wait { closed }
        #expect(closed)
        #expect(!transport.isReady)
    }

    @Test func probeOverLoopbackAnswers() async throws {
        let server = try FakeReceiverServer()
        await wait { server.port != nil }
        let port = try #require(server.port)
        server.reply = Array("PWON\r".utf8)
        let codec = DenonProtocol()
        let transport = ReceiverTCPTransport(host: "127.0.0.1", ports: [port], framing: codec.networkFraming,
                                             delimiters: codec.lineDelimiters, requiresLAN: false)
        let answered = await ReceiverController.probe(transport, codec: codec, clock: SystemReceiverClock())
        #expect(answered)
        await wait { !server.received.isEmpty }
        #expect(server.received.starts(with: Array("PW?\r".utf8)))
        server.stop()
    }

    /// Security M1: with the app's settings, a loopback listener is never reached and nothing is written.
    @Test func loopbackIsRefused() async throws {
        let server = try FakeReceiverServer()
        await wait { server.port != nil }
        let port = try #require(server.port)
        let codec = DenonProtocol()
        for host in ["127.0.0.1", "::1"] {
            let transport = ReceiverTCPTransport(host: host, ports: [port], framing: codec.networkFraming,
                                                 delimiters: codec.lineDelimiters)
            var closed = false
            transport.onClose = { closed = true }
            await wait { closed || transport.isReady }
            #expect(closed, "\(host)")
            #expect(!transport.isReady, "\(host)")
            #expect(!transport.write(codec.encode(.queryPower)))
        }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(server.received.isEmpty)
        server.stop()
    }
}
