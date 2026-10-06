import Foundation
import Testing
@testable import MMTVL

struct ClipboardURLTests {
    @Test func emptyClipboard() {
        #expect(ClipboardURL.parse(nil) == .failure(.empty))
        #expect(ClipboardURL.parse("") == .failure(.empty))
        #expect(ClipboardURL.parse("  \n \n") == .failure(.empty))
    }

    @Test func trimsAWebAddress() {
        #expect(ClipboardURL.parse("  https://iptv.example/app2/abc\n") == .success(URL(string: "https://iptv.example/app2/abc")!))
    }

    @Test func rejectsNonWebText() {
        #expect(ClipboardURL.parse("hello") == .failure(.notAWebAddress))
        #expect(ClipboardURL.parse("ftp://x") == .failure(.notAWebAddress))
        #expect(ClipboardURL.parse("https://") == .failure(.notAWebAddress))
    }

    @Test func usesFirstNonEmptyLine() {
        #expect(ClipboardURL.parse("\n  http://a.example/list.m3u \nhttps://b.example/other") == .success(URL(string: "http://a.example/list.m3u")!))
    }

    @Test func messages() {
        #expect(ClipboardURL.message(for: .empty) == "The clipboard is empty. Copy the URL first.")
        #expect(ClipboardURL.message(for: .notAWebAddress) == "The clipboard doesn't hold a web address.")
    }
}
