import CoreGraphics
import Testing
@testable import MMTVL

struct SyntheticInputTests {
    @Test func emptyTextHasNoChunks() {
        #expect(SyntheticInput.chunks("") == [])
    }

    @Test func asciiChunksAtTwenty() {
        let text = String(repeating: "a", count: 45)
        #expect(SyntheticInput.chunks(text).map(\.count) == [20, 20, 5])
    }

    @Test func emojiAreNeverSplit() {
        let emoji = "👍🏽"
        #expect(emoji.utf16.count == 4)
        let chunks = SyntheticInput.chunks(String(repeating: emoji, count: 15))
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk == String(repeating: emoji, count: 5))
        }
    }

    @Test func composedCharacterStaysWhole() {
        let composed = "e\u{301}"
        #expect(SyntheticInput.chunks(composed, maxUTF16: 1) == [composed])
    }

    @Test func externalKeyMap() {
        #expect(ExternalKeyMap.key(for: .up) == .key(126))
        #expect(ExternalKeyMap.key(for: .down) == .key(125))
        #expect(ExternalKeyMap.key(for: .left) == .key(123))
        #expect(ExternalKeyMap.key(for: .right) == .key(124))
        #expect(ExternalKeyMap.key(for: .select) == .key(36))
        #expect(ExternalKeyMap.key(for: .back) == .key(53))
        #expect(ExternalKeyMap.key(for: .playPause) == .media(16))
        #expect(ExternalKeyMap.key(for: .fastForward) == .media(17))
        #expect(ExternalKeyMap.key(for: .rewind) == .media(18))
        #expect(ExternalKeyMap.key(for: .home) == nil)
    }

    @Test func isOwnReadsTheMarker() throws {
        let tagged = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        tagged.setIntegerValueField(.eventSourceUserData, value: SyntheticInput.marker)
        #expect(SyntheticInput.isOwn(tagged))

        // An event created in-process carries our PID, which `isOwn` also accepts; fake another process.
        let plain = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        #expect(SyntheticInput.isOwn(plain))
        plain.setIntegerValueField(.eventSourceUnixProcessID, value: 1)
        #expect(!SyntheticInput.isOwn(plain))
    }
}
