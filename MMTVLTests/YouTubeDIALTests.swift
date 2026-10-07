import Foundation
import Testing
@testable import MMTVL

struct YouTubeDIALTests {
    @Test func fullResponse() {
        let value: [String: Any] = [
            "found": true, "handled": true, "status": NSNumber(value: 201), "body": "<x/>",
            "mimeType": "text/xml", "headers": [["LOCATION", "http://h/run"]],
        ]
        #expect(YouTubeDIAL.response(fromJavaScript: value)
                == DIALAppResponse(handled: true, status: 201, body: "<x/>", mimeType: "text/xml",
                                   headers: [HTTPHeader(name: "LOCATION", value: "http://h/run")]))
    }

    @Test func notFoundIsNil() {
        #expect(YouTubeDIAL.response(fromJavaScript: ["found": false]) == nil)
        #expect(YouTubeDIAL.response(fromJavaScript: [String: Any]()) == nil)
    }

    @Test func missingFieldsUseDefaults() {
        #expect(YouTubeDIAL.response(fromJavaScript: ["found": true])
                == DIALAppResponse(handled: false, status: 0, body: "", mimeType: nil, headers: []))
        #expect(YouTubeDIAL.response(fromJavaScript: ["found": true, "mimeType": "", "status": 200])?.mimeType == nil)
        #expect(YouTubeDIAL.response(fromJavaScript: ["found": true, "status": 200])?.status == 200)
    }

    @Test func badHeadersAreSkipped() {
        let value: [String: Any] = ["found": true, "headers": [["A", "1"], ["only"], "string", ["B", 2], ["C", "3"]]]
        #expect(YouTubeDIAL.response(fromJavaScript: value)?.headers
                == [HTTPHeader(name: "A", value: "1"), HTTPHeader(name: "C", value: "3")])
    }

    @Test func garbageIsNil() {
        #expect(YouTubeDIAL.response(fromJavaScript: nil) == nil)
        #expect(YouTubeDIAL.response(fromJavaScript: NSNull()) == nil)
        #expect(YouTubeDIAL.response(fromJavaScript: "found") == nil)
    }

    @Test func shimShape() {
        let script = YouTubeDIAL.shimScript
        #expect(script.contains("h5vcc"))
        #expect(script.contains("DialServer"))
        #expect(script.contains("mmtvlDial"))
        #expect(!script.contains("system"))
        #expect(!script.contains("runtime"))
        #expect(script.contains(#"p.replace(/\/+$/, '')"#))
    }
}
