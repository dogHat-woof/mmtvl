import Foundation
import Testing
@testable import MMTVL

/// Security review item 6: logs name a URL's host, never its path, query or credentials.
struct LogURLTests {
    @Test func hostOnly() {
        let url = URL(string: "https://user:secret@meet.google.com/home?calling=1&token=abc#frag")!
        #expect(LogURL.host(url) == "meet.google.com")
        #expect(LogURL.host(URL(string: "http://10.0.0.5:8080/live/x.m3u8?u=a&p=b")!) == "10.0.0.5")
    }

    @Test func noHost() {
        #expect(LogURL.host(nil) == "no host")
        #expect(LogURL.host(URL(string: "about:blank")!) == "no host")
        #expect(LogURL.host(URL(string: "file:///Users/someone/secret.txt")!) == "no host")
    }
}
