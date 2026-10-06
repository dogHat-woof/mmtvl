import Testing
@testable import MMTVL

struct VolumeTests {
    private func choose(_ mode: VolumeMode, soundSource: Bool = false, settable: Bool = false, active: Bool = false) -> VolumeRoute {
        VolumeRoute.choose(mode: mode, soundSourceRunning: soundSource, systemSettable: settable, launcherActive: active)
    }

    @Test func autoRoute() {
        #expect(choose(.auto, soundSource: true, settable: true, active: true) == .keys)
        #expect(choose(.auto, settable: true, active: true) == .system)
        #expect(choose(.auto, active: true) == .app)
        #expect(choose(.auto) == .unavailable)
    }

    @Test func forcedRoutes() {
        #expect(choose(.keys) == .keys)
        #expect(choose(.system, soundSource: true, settable: true) == .system)
        #expect(choose(.system, soundSource: true, active: true) == .unavailable)
        #expect(choose(.app, soundSource: true, settable: true, active: true) == .app)
        #expect(choose(.app, soundSource: true, settable: true) == .unavailable)
    }

    @Test func appVolume() {
        var volume = AppVolume()
        volume.apply(.up)
        #expect(volume.level == 100)
        for _ in 0..<3 { volume.apply(.down) }
        #expect(volume.level == 85)
        volume.apply(.mute)
        #expect(volume.muted)
        volume.apply(.mute)
        #expect(!volume.muted)
        volume.apply(.mute)
        volume.apply(.up)
        #expect(!volume.muted)
        #expect(volume.level == 90)

        var silent = AppVolume(level: 0, muted: false)
        silent.apply(.down)
        #expect(silent.level == 0)
    }

    @Test func systemVolumeStep() {
        #expect(SystemVolume.step(0.5, .up) == 0.5625)
        #expect(SystemVolume.step(0, .down) == 0)
        #expect(SystemVolume.step(0.97, .up) == 1)
        #expect(SystemVolume.step(0.51, .up) == 0.5625)
        #expect(SystemVolume.step(0.5, .down) == 0.4375)
    }

    @Test func volumeModeParsing() {
        #expect(VolumeMode(rawValue: "keys") == .keys)
        #expect(VolumeMode(rawValue: "bogus") == nil)
    }
}
