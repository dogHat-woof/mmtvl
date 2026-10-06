import Testing
@testable import MMTVL

struct MPVOptionsTests {
    private func value(_ name: String) -> String? {
        MPVOptions.all.first { $0.name == name }?.value
    }

    @Test func renderCallsDontWaitForFrameTiming() {
        #expect(value("video-timing-offset") == "0")
        #expect(MPVOptions.all.last?.name == "video-timing-offset")
    }

    @Test func keepsTheM4Buffers() {
        #expect(value("cache") == "yes")
        #expect(value("demuxer-max-back-bytes") == "512MiB")
        #expect(value("demuxer-max-bytes") == "256MiB")
    }

    @Test func bufferProfiles() {
        #expect(BufferProfile.tile.backBytes == "160MiB")
        #expect(BufferProfile.tile.forwardBytes == "64MiB")
        #expect(BufferProfile.full.backBytes == MPVOptions.backBuffer)
        #expect(BufferProfile.full.forwardBytes == MPVOptions.forwardBuffer)
    }
}
