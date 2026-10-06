import Foundation
import Network
import Testing
@testable import MMTVL

@MainActor
@Suite(.serialized)
struct DIALServerTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func servesTheDescriptionAndLaunchesCold() async throws {
        var launches: [String?] = []
        let bridge = CastBridge(isAppReady: { false }, forward: { _ in nil },
                                launch: { launches.append($0) }, didConnect: {})
        let server = DIALServer(deviceID: "test-id", friendlyName: "MMTVL", bridge: bridge)
        server.start(port: .any)
        defer { server.stop() }
        try await waitUntil { server.state == .running }
        let port = try #require(server.port)

        let (body, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/dd.xml")!)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Application-URL")?.hasSuffix(":\(port)/apps") == true)
        #expect(String(decoding: body, as: UTF8.self).contains("<UDN>uuid:test-id</UDN>"))

        var post = URLRequest(url: URL(string: "http://localhost:\(port)/apps/YouTube")!)
        post.httpMethod = "POST"
        post.httpBody = Data("pairingCode=x".utf8)
        let (_, created) = try await URLSession.shared.data(for: post)
        let createdHTTP = try #require(created as? HTTPURLResponse)
        #expect(createdHTTP.statusCode == 201)
        #expect(createdHTTP.value(forHTTPHeaderField: "Location")?.hasSuffix(":\(port)/apps/YouTube/run") == true)
        #expect(launches == ["pairingCode=x"])

        let (status, _) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/apps/YouTube")!)
        #expect(String(decoding: status, as: UTF8.self).contains("<state>running</state>"))
    }
}
