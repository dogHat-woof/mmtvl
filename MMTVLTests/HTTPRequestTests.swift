import Foundation
import Testing
@testable import MMTVL

struct HTTPRequestTests {
    private func parse(_ text: String) -> HTTPRequestHead.ParseResult {
        HTTPRequestHead.parse(Data(text.utf8))
    }

    @Test func parsesAFullHead() {
        #expect(parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n") == .complete(HTTPRequestHead(method: "GET", path: "/")))
        #expect(parse("HEAD /remote.js?v=1 HTTP/1.1\r\nHost: x\r\n\r\n") == .complete(HTTPRequestHead(method: "HEAD", path: "/remote.js")))
    }

    @Test func partialAndOversizedHeads() {
        #expect(parse("GET / HTTP/1.1\r\nHost: x\r\n") == .incomplete)
        #expect(parse("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: 17 * 1024)) == .tooLarge)
    }

    @Test func invalidHead() {
        #expect(parse("garbage\r\n\r\n") == .invalid)
        #expect(parse("GET nothing HTTP/1.1\r\n\r\n") == .invalid)
    }

    @Test func assetAllowList() {
        #expect(RemoteWebAssets.asset(forPath: "/")?.ext == "html")
        #expect(RemoteWebAssets.asset(forPath: "/index.html")?.ext == "html")
        #expect(RemoteWebAssets.asset(forPath: "/remote.css")?.ext == "css")
        #expect(RemoteWebAssets.asset(forPath: "/remote.js")?.ext == "js")
        #expect(RemoteWebAssets.asset(forPath: "/../Info.plist") == nil)
        #expect(RemoteWebAssets.asset(forPath: "/remote.swift") == nil)
        #expect(RemoteWebAssets.asset(forPath: "/favicon.ico") == nil)
    }

    @Test func bundleHasEveryAsset() throws {
        for path in ["/", "/remote.css", "/remote.js"] {
            let asset = try #require(RemoteWebAssets.asset(forPath: path))
            #expect(RemoteWebAssets.data(for: asset) != nil)
        }
    }

    @Test func responseBytes() {
        let body = Data("hello".utf8)
        let get = String(decoding: HTTPResponse.make(status: 200, reason: "OK", contentType: "text/plain", body: body, includeBody: true), as: UTF8.self)
        #expect(get.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(get.contains("Content-Length: 5\r\n"))
        #expect(get.contains("Connection: close\r\n"))
        #expect(get.contains("Cache-Control: no-store\r\n"))
        #expect(get.contains("X-Content-Type-Options: nosniff\r\n"))
        #expect(get.hasSuffix("\r\n\r\nhello"))

        let head = String(decoding: HTTPResponse.make(status: 200, reason: "OK", contentType: "text/plain", body: body, includeBody: false), as: UTF8.self)
        #expect(head.contains("Content-Length: 5\r\n"))
        #expect(head.hasSuffix("\r\n\r\n"))

        let error = String(decoding: HTTPResponse.error(404, "Not Found"), as: UTF8.self)
        #expect(error.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        #expect(error.hasSuffix("404 Not Found"))
    }
}
