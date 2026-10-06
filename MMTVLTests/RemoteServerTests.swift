import Foundation
import Network
import Testing
@testable import MMTVL

@MainActor
@Suite(.serialized)
struct RemoteServerTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func servesThePageAndEchoesOverTheSocket() async throws {
        let server = RemoteServer()
        var closed: [RemoteSessionID] = []
        server.onMessage = { [weak server] id, _ in server?.send(.toast("echo"), to: id) }
        server.onSessionClosed = { closed.append($0) }
        server.start(httpPort: .any, socketPort: .any)
        defer { server.stop() }

        try await waitUntil { server.state == .running }
        #expect(server.state == .running)
        let httpPort = try #require(server.httpPort)
        let socketPort = try #require(server.socketPort)

        // HTTP
        let (body, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(httpPort)/")!)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/html") == true)
        #expect(String(decoding: body, as: UTF8.self).contains("MMTVL Remote"))

        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(httpPort)/nope")!)
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)

        // WebSocket round trip
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://localhost:\(socketPort)/")!)
        task.resume()
        try await task.send(.string(#"{"type":"textBegin"}"#))
        let reply = try await task.receive()
        guard case .string(let json) = reply else {
            Issue.record("Expected a text frame, got \(reply)")
            return
        }
        #expect(json == #"{"message":"echo","type":"toast"}"#)

        server.stop()
        #expect(server.state == .stopped)
        #expect(closed.count == 1)
        task.cancel(with: .goingAway, reason: nil)
    }
}
