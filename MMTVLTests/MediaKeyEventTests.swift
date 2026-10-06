import Testing
@testable import MMTVL

struct MediaKeyEventTests {
    @Test func playKeyDown() {
        let parsed = MediaKeyEvent.parse(subtype: 8, data1: (16 << 16) | (0xA << 8))
        #expect(parsed == .init(key: .playPause, isKeyDown: true, isRepeat: false))
    }

    @Test func keyUp() {
        let parsed = MediaKeyEvent.parse(subtype: 8, data1: (16 << 16) | (0xB << 8))
        #expect(parsed == .init(key: .playPause, isKeyDown: false, isRepeat: false))
    }

    @Test func repeatBit() {
        let parsed = MediaKeyEvent.parse(subtype: 8, data1: (17 << 16) | (0xA << 8) | 1)
        #expect(parsed == .init(key: .next, isKeyDown: true, isRepeat: true))
    }

    @Test func otherSubtypeIsNil() {
        #expect(MediaKeyEvent.parse(subtype: 7, data1: (16 << 16) | (0xA << 8)) == nil)
    }

    @Test func volumeUpIsNil() {
        #expect(MediaKeyEvent.parse(subtype: 8, data1: (0 << 16) | (0xA << 8)) == nil)
    }
}
