import Foundation
import Testing
@testable import MMTVL

/// Security review item 8: the page's native messages count only from the main frame of an https YouTube/Google page.
struct YouTubeMessageTests {
    @Test(arguments: [
        (true, "https", "www.youtube.com", true),
        (true, "HTTPS", "YouTube.com", true),
        (true, "https", "accounts.google.com", true),
        (false, "https", "www.youtube.com", false),
        (false, "https", "googleads.g.doubleclick.net", false),
        (true, "http", "www.youtube.com", false),
        (true, "https", "evil.example", false),
        (true, "https", "notyoutube.com", false),
        (true, "file", "", false),
        (true, "", "", false),
    ])
    func acceptsMessage(isMainFrame: Bool, scheme: String, host: String, accepted: Bool) {
        #expect(YouTubeConfig.acceptsMessage(isMainFrame: isMainFrame, scheme: scheme, host: host) == accepted)
    }

    @Test func exitOnlyFromTheMainFrame() {
        let controller = YouTubeController(userAgent: "Test")
        var exits = 0
        controller.onExit = { exits += 1 }
        let exit = YouTubeKeyMap.messageHandlerName

        controller.receiveMessage(name: exit, body: "close", isMainFrame: false, scheme: "https", host: "www.youtube.com")
        controller.receiveMessage(name: exit, body: "close", isMainFrame: false, scheme: "https", host: "ads.example")
        controller.receiveMessage(name: exit, body: "close", isMainFrame: true, scheme: "https", host: "evil.example")
        controller.receiveMessage(name: exit, body: "close", isMainFrame: true, scheme: "http", host: "www.youtube.com")
        #expect(exits == 0)

        controller.receiveMessage(name: exit, body: "close", isMainFrame: true, scheme: "https", host: "www.youtube.com")
        #expect(exits == 1)
    }

    @Test func dialReadyOnlyFromTheMainFrame() {
        let controller = YouTubeController(userAgent: "Test")
        let ready: [String: Any] = ["type": "ready", "app": DIALRouting.appName]
        let dial = YouTubeDIAL.messageHandlerName

        controller.receiveMessage(name: dial, body: ready, isMainFrame: false, scheme: "https", host: "www.youtube.com")
        controller.receiveMessage(name: dial, body: ready, isMainFrame: true, scheme: "https", host: "evil.example")
        #expect(!controller.isDIALReady)

        controller.receiveMessage(name: dial, body: ready, isMainFrame: true, scheme: "https", host: "www.youtube.com")
        #expect(controller.isDIALReady)
    }
}
