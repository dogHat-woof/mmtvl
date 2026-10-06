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

    @Test func extraHeadersAndNoContentType() {
        let data = HTTPResponse.make(status: 201, reason: "Created", contentType: nil,
                                     headers: [HTTPHeader(name: "Location", value: "http://x/run")],
                                     body: Data(), includeBody: true)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\r\nContent-Type:"))
        #expect(text.hasPrefix("HTTP/1.1 201 Created\r\nContent-Length: 0\r\nLocation: http://x/run\r\nConnection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    @Test func reasons() {
        #expect(HTTPResponse.reason(for: 200) == "OK")
        #expect(HTTPResponse.reason(for: 201) == "Created")
        #expect(HTTPResponse.reason(for: 302) == "Found")
        #expect(HTTPResponse.reason(for: 403) == "Forbidden")
        #expect(HTTPResponse.reason(for: 413) == "Content Too Large")
        #expect(HTTPResponse.reason(for: 431) == "Request Header Fields Too Large")
        #expect(HTTPResponse.reason(for: 501) == "Not Implemented")
        #expect(HTTPResponse.reason(for: 299) == "Status")
    }

    @Test func generatedAssets() {
        for path in ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"] {
            #expect(RemoteWebAssets.asset(forPath: path)?.generated == .icon(size: 180))
            #expect(RemoteWebAssets.asset(forPath: path)?.contentType == "image/png")
        }
        #expect(RemoteWebAssets.asset(forPath: "/icon-192.png")?.generated == .icon(size: 192))
        #expect(RemoteWebAssets.asset(forPath: "/icon-512.png")?.generated == .icon(size: 512))
        let manifest = RemoteWebAssets.asset(forPath: "/remote.webmanifest")
        #expect(manifest?.generated == .manifest)
        #expect(manifest?.contentType == "application/manifest+json; charset=utf-8")
        #expect(RemoteWebAssets.asset(forPath: "/")?.generated == nil)
        // Generated assets never come from the bundle.
        if let manifest { #expect(RemoteWebAssets.data(for: manifest) == nil) }
    }

    @Test func manifestDecodes() throws {
        let object = try JSONSerialization.jsonObject(with: Data(RemoteWebManifest.json.utf8)) as? [String: Any]
        #expect(object?["short_name"] as? String == "MMTVL")
        #expect(object?["display"] as? String == "standalone")
        let icons = try #require(object?["icons"] as? [[String: Any]])
        #expect(icons.count == 2)
        #expect(icons.map { $0["sizes"] as? String } == ["192x192", "512x512"])
    }
}
