import Foundation
import Testing
@testable import MMTVL

struct YouTubeConfigTests {
    @Test func blankOverrideUsesDefaultUserAgent() {
        #expect(YouTubeConfig.userAgent(override: nil) == YouTubeConfig.defaultUserAgent)
        #expect(YouTubeConfig.userAgent(override: "") == YouTubeConfig.defaultUserAgent)
        #expect(YouTubeConfig.userAgent(override: "  ") == YouTubeConfig.defaultUserAgent)
    }

    @Test func customOverrideIsUsed() {
        #expect(YouTubeConfig.userAgent(override: "Custom/1.0") == "Custom/1.0")
    }

    @Test(arguments: [
        ("https://www.youtube.com/tv", true),
        ("https://accounts.google.com/x", true),
        ("https://youtube.com/tv", true),
        ("https://evil.com", false),
        ("http://www.youtube.com", false),
        ("https://notyoutube.com", false),
        ("about:blank", true),
    ])
    func mainFrameNavigation(url: String, allowed: Bool) {
        #expect(YouTubeConfig.allowsNavigation(to: URL(string: url)!, isMainFrame: true) == allowed)
    }

    @Test func subframesAreUnrestricted() {
        #expect(YouTubeConfig.allowsNavigation(to: URL(string: "https://evil.com")!, isMainFrame: false))
        #expect(YouTubeConfig.allowsNavigation(to: URL(string: "http://ads.example")!, isMainFrame: false))
    }

    @Test func launchURL() {
        #expect(YouTubeConfig.launchURL(query: "") == YouTubeConfig.startURL)
        #expect(YouTubeConfig.launchURL(query: "pairingCode=abc-123&theme=cl").absoluteString
                == "https://www.youtube.com/tv?pairingCode=abc-123&theme=cl")
    }
}
