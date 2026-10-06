import Testing
@testable import MMTVL

struct YouTubeKeyMapTests {
    @Test func keyCodes() {
        let expected: [RemoteCommand: Int?] = [
            .up: 38, .down: 40, .left: 37, .right: 39, .select: 13, .back: 27,
            .playPause: 179, .fastForward: 228, .rewind: 227, .home: nil,
        ]
        #expect(expected.count == RemoteCommand.allCases.count)
        for command in RemoteCommand.allCases {
            #expect(YouTubeKeyMap.keyCode(for: command) == expected[command]!, "\(command)")
        }
    }

    @Test func dispatchScriptShape() {
        let script = YouTubeKeyMap.dispatchScript(keyCode: 179)
        #expect(script.contains("keydown"))
        #expect(script.contains("keyup"))
        #expect(script.contains("179"))
        #expect(script.hasSuffix("'ok'"))
    }

    @Test func exitHookUsesMessageHandler() {
        #expect(YouTubeKeyMap.exitHookScript.contains("messageHandlers.\(YouTubeKeyMap.messageHandlerName)"))
    }

    @Test func alwaysVisibleScriptCoversVisibilityAPIs() {
        let script = YouTubeKeyMap.alwaysVisibleScript
        #expect(script.contains("visibilityState"))
        #expect(script.contains("'hidden'"))
        #expect(script.contains("visibilitychange"))
    }

    @Test func volumeScripts() {
        #expect(YouTubeKeyMap.volumeScript.contains("window.__mmtvlSetVolume ="))
        #expect(YouTubeKeyMap.setVolumeScript(level: 85, muted: true)
            == "window.__mmtvlSetVolume && window.__mmtvlSetVolume(0.85, true); 'ok'")
        #expect(YouTubeKeyMap.setVolumeScript(level: 100, muted: false)
            == "window.__mmtvlSetVolume && window.__mmtvlSetVolume(1.0, false); 'ok'")
    }
}
