import Foundation
import Testing
@testable import MMTVL

struct DIALProtocolTests {
    // MARK: SSDP

    private func search(_ text: String) -> Bool {
        SSDP.isDIALSearch(Data(text.utf8))
    }

    @Test func acceptsDIALSearches() {
        #expect(search("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"))
        #expect(search("M-SEARCH * HTTP/1.1\nHost: 239.255.255.250:1900\nman: ssdp:discover\nst:  urn:dial-multiscreen-org:service:dial:1 \n\n"))
        #expect(search("M-SEARCH * HTTP/1.1\r\nMan: \"ssdp:discover\"\r\nSt: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"))
    }

    @Test func rejectsOtherDatagrams() {
        #expect(!search("NOTIFY * HTTP/1.1\r\nNT: urn:dial-multiscreen-org:service:dial:1\r\nNTS: ssdp:alive\r\n\r\n"))
        #expect(!search("M-SEARCH * HTTP/1.1\r\nMAN: \"ssdp:discover\"\r\nST: urn:dial-multiscreen-org:service:other:1\r\n\r\n"))
        #expect(!search("M-SEARCH * HTTP/1.1\r\nMAN: \"ssdp:discover\"\r\nST: ssdp:all\r\n\r\n"))
        #expect(!search("M-SEARCH * HTTP/1.1\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"))
        #expect(!search(""))
        #expect(!SSDP.isDIALSearch(Data([0xFF, 0xFE, 0x00, 0x81])))
    }

    @Test func searchReplyLines() {
        let date = Date(timeIntervalSince1970: 0)
        let reply = String(decoding: SSDP.searchReply(location: "http://10.0.0.5:8770/dd.xml", deviceID: "abc",
                                                      server: "macOS/27 UPnP/1.1 MMTVL/1.0", date: date), as: UTF8.self)
        let expected = [
            "HTTP/1.1 200 OK",
            "CACHE-CONTROL: max-age=1800",
            "DATE: Thu, 01 Jan 1970 00:00:00 GMT",
            "EXT:",
            "LOCATION: http://10.0.0.5:8770/dd.xml",
            "SERVER: macOS/27 UPnP/1.1 MMTVL/1.0",
            "ST: urn:dial-multiscreen-org:service:dial:1",
            "USN: uuid:abc::urn:dial-multiscreen-org:service:dial:1",
            "",
            "",
        ].joined(separator: "\r\n")
        #expect(reply == expected)
        #expect(reply.hasSuffix("\r\n\r\n"))
    }

    // MARK: Request parsing

    private func parse(_ text: String) -> DIALRequest.Parse {
        DIALRequest.parse(Data(text.utf8))
    }

    @Test func parsesHeadAndBody() {
        let parsed = parse("POST /apps/YouTube?x=1 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\nOrigin: package:x\r\n\r\npairs")
        #expect(parsed == .complete(DIALRequest(method: "POST", path: "/apps/YouTube",
                                                headers: ["host": "a", "content-length": "5", "origin": "package:x"],
                                                body: "pairs")))
        #expect(parse("GET //apps//YouTube HTTP/1.1\r\n\r\n")
                == .complete(DIALRequest(method: "GET", path: "/apps/YouTube", headers: [:], body: "")))
    }

    @Test func incompleteRequests() {
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\n") == .incomplete)
        #expect(parse("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc") == .incomplete)
    }

    @Test func sizeLimits() {
        let exact = "POST /apps/YouTube HTTP/1.1\r\nContent-Length: 4096\r\n\r\n" + String(repeating: "a", count: 4096)
        if case .complete(let request) = parse(exact) {
            #expect(request.body.count == 4096)
        } else {
            Issue.record("4096-byte body should parse")
        }
        #expect(parse("POST /apps/YouTube HTTP/1.1\r\nContent-Length: 4097\r\n\r\n") == .tooLarge(413))
        #expect(parse("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: 17 * 1024)) == .tooLarge(431))
        #expect(parse("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: 17 * 1024) + "\r\n\r\n") == .tooLarge(431))
    }

    @Test func invalidRequests() {
        #expect(parse("GET / HTTP/1.1\r\nno colon here\r\n\r\n") == .invalid)
        #expect(parse("GET / HTTP/1.1\r\nContent-Length: ten\r\n\r\n") == .invalid)
        #expect(parse("garbage\r\n\r\n") == .invalid)
    }

    // MARK: Routing

    private let context = DIALContext(host: "10.0.0.5:8770", deviceID: "dev-1", friendlyName: "MMTVL",
                                      appReady: false, isLaunching: false)

    private func request(_ method: String, _ path: String, body: String = "", headers: [String: String] = [:]) -> DIALRequest {
        DIALRequest(method: method, path: path, headers: headers, body: body)
    }

    private func reply(_ decision: DIALDecision) -> DIALReply? {
        if case .reply(let reply) = decision { reply } else { nil }
    }

    @Test func deviceDescription() throws {
        for path in ["/", "/dd.xml"] {
            let result = try #require(reply(DIALRouting.decide(request("GET", path), context: context)))
            #expect(result.status == 200)
            #expect(result.contentType == "text/xml; charset=\"utf-8\"")
            #expect(result.headers == [HTTPHeader(name: "Application-URL", value: "http://10.0.0.5:8770/apps")])
            let body = String(decoding: result.body, as: UTF8.self)
            #expect(body.contains("<friendlyName>MMTVL</friendlyName>"))
            #expect(body.contains("<UDN>uuid:dev-1</UDN>"))
            #expect(body.contains("<deviceType>urn:dial-multiscreen-org:device:dial:1</deviceType>"))
        }
        #expect(reply(DIALRouting.decide(request("POST", "/dd.xml"), context: context))?.status == 405)
        #expect(reply(DIALRouting.decide(request("DELETE", "/"), context: context))?.status == 405)
    }

    @Test func descriptionEscapesXML() {
        let xml = DIALRouting.deviceDescription(host: "h", deviceID: "a\"b", friendlyName: "Tom & <Jerry>'s")
        #expect(xml.contains("<friendlyName>Tom &amp; &lt;Jerry&gt;&apos;s</friendlyName>"))
        #expect(xml.contains("<UDN>uuid:a&quot;b</UDN>"))
    }

    @Test func appsRedirects() {
        for path in ["/apps", "/apps/"] {
            let result = reply(DIALRouting.decide(request("GET", path), context: context))
            #expect(result?.status == 302)
            #expect(result?.headers == [HTTPHeader(name: "Location", value: "http://10.0.0.5:8770/apps/YouTube")])
        }
    }

    @Test func unknownPathsAndApps() {
        #expect(reply(DIALRouting.decide(request("GET", "/apps/Netflix"), context: context))?.status == 404)
        #expect(reply(DIALRouting.decide(request("GET", "/other"), context: context))?.status == 404)
        #expect(reply(DIALRouting.decide(request("GET", "/apps/YouTubeX"), context: context))?.status == 404)
    }

    @Test func originRule() {
        let evil = request("POST", "/apps/YouTube", body: "pairingCode=x", headers: ["origin": "https://evil.example"])
        #expect(reply(DIALRouting.decide(evil, context: context))?.status == 403)
        let app = request("POST", "/apps/YouTube", body: "pairingCode=x", headers: ["origin": "package:com.google.ios.youtube"])
        #expect(DIALRouting.decide(app, context: context) == .launch(query: "pairingCode=x"))
        #expect(DIALRouting.isForbiddenOrigin("HTTP://LAN.local"))
        #expect(!DIALRouting.isForbiddenOrigin(nil))
        #expect(!DIALRouting.isForbiddenOrigin(""))
        #expect(!DIALRouting.isForbiddenOrigin("null"))
    }

    @Test func otherMethodsAreNotAllowed() {
        #expect(reply(DIALRouting.decide(request("PUT", "/apps/YouTube"), context: context))?.status == 405)
    }

    @Test func forwardsWhenLeanbackIsReady() {
        var ready = context
        ready.appReady = true
        #expect(DIALRouting.decide(request("POST", "/apps/YouTube", body: "pairingCode=x"), context: ready)
                == .forward(DIALAppRequest(app: "YouTube", method: "POST", path: "/", body: "pairingCode=x", host: "10.0.0.5:8770")))
        #expect(DIALRouting.decide(request("DELETE", "/apps/YouTube/run/"), context: ready)
                == .forward(DIALAppRequest(app: "YouTube", method: "DELETE", path: "/run", body: "", host: "10.0.0.5:8770")))
    }

    @Test func nativeStatus() throws {
        let stopped = try #require(reply(DIALRouting.decide(request("GET", "/apps/YouTube"), context: context)))
        #expect(stopped.status == 200)
        let stoppedBody = String(decoding: stopped.body, as: UTF8.self)
        #expect(stoppedBody.contains("<state>stopped</state>"))
        #expect(!stoppedBody.contains("rel=\"run\""))

        var launching = context
        launching.isLaunching = true
        let running = try #require(reply(DIALRouting.decide(request("GET", "/apps/YouTube/"), context: launching)))
        let runningBody = String(decoding: running.body, as: UTF8.self)
        #expect(runningBody.contains("<state>running</state><link rel=\"run\" href=\"run\"/>"))
    }

    @Test func nativeLaunch() {
        #expect(DIALRouting.decide(request("POST", "/apps/YouTube", body: "pairingCode=abc-123&theme=cl&foo=bar"), context: context)
                == .launch(query: "pairingCode=abc-123&theme=cl"))
        #expect(DIALRouting.decide(request("POST", "/apps/YouTube"), context: context) == .launch(query: nil))
        #expect(reply(DIALRouting.decide(request("POST", "/apps/YouTube", body: "a b"), context: context))?.status == 400)
        #expect(reply(DIALRouting.decide(request("DELETE", "/apps/YouTube/run"), context: context))?.status == 404)
        #expect(reply(DIALRouting.decide(request("POST", "/apps/YouTube/run"), context: context))?.status == 404)
    }

    @Test func launchQuerySanitizer() {
        #expect(DIALRouting.sanitizedLaunchQuery("v=dQw4w9WgXcQ&t=30") == "v=dQw4w9WgXcQ&t=30")
        #expect(DIALRouting.sanitizedLaunchQuery("foo=bar") == "")
        #expect(DIALRouting.sanitizedLaunchQuery("v=<script>") == nil)
        #expect(DIALRouting.sanitizedLaunchQuery("v=%3Cscript%3E") == "")
        #expect(DIALRouting.sanitizedLaunchQuery("v=" + String(repeating: "a", count: 201)) == "")
        #expect(DIALRouting.sanitizedLaunchQuery("v=") == "")
        #expect(DIALRouting.sanitizedLaunchQuery("v=%zz") == nil)
        #expect(DIALRouting.sanitizedLaunchQuery("") == "")
    }

    @Test func leanbackReplies() {
        let handled = DIALAppResponse(handled: true, status: 0, body: "<x/>", mimeType: "text/xml",
                                      headers: [HTTPHeader(name: "LOCATION", value: "http://h/run")])
        #expect(DIALRouting.reply(for: handled)
                == DIALReply(status: 200, contentType: "text/xml", headers: [HTTPHeader(name: "LOCATION", value: "http://h/run")],
                             body: Data("<x/>".utf8)))
        var created = handled
        created.status = 201
        #expect(DIALRouting.reply(for: created).status == 201)
        var refused = handled
        refused.handled = false
        #expect(DIALRouting.reply(for: refused).status == 400)
    }
}
