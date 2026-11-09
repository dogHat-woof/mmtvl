import CoreGraphics
import Foundation
import Testing
@testable import MMTVL

struct MirroringDetectorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func window(_ rect: CGRect, alpha: Double = 1) -> WindowSnapshot {
        WindowSnapshot(pid: 42, layer: 0, alpha: alpha, bounds: rect)
    }

    private var big: WindowSnapshot { window(CGRect(x: 480, y: 270, width: 960, height: 540)) }

    @Test func noWindowsNoSession() {
        var detector = MirroringDetector()
        do { let event = detector.update(windows: [], screen: screen); #expect(event == .none) }
        #expect(!detector.isActive)
    }

    @Test func smallOrInvisibleWindowsAreIgnored() {
        var detector = MirroringDetector()
        let small = window(CGRect(x: 0, y: 0, width: 400, height: 900))
        do { let event = detector.update(windows: [small], screen: screen); #expect(event == .none) }
        do { let event = detector.update(windows: [window(screen, alpha: 0)], screen: screen); #expect(event == .none) }
        #expect(!detector.isActive)
    }

    @Test func bigWindowBeginsOnce() {
        var detector = MirroringDetector()
        do { let event = detector.update(windows: [big], screen: screen); #expect(event == .began) }
        #expect(detector.isActive)
        #expect(detector.sessionWindows == [big])
        for _ in 0..<3 {
            do { let event = detector.update(windows: [big], screen: screen); #expect(event == .none) }
        }
    }

    @Test func endsAfterTwoMissedPolls() {
        var detector = MirroringDetector()
        _ = detector.update(windows: [big], screen: screen)
        do { let event = detector.update(windows: [], screen: screen); #expect(event == .none) }
        #expect(detector.isActive)
        #expect(detector.sessionWindows == [big])
        do { let event = detector.update(windows: [], screen: screen); #expect(event == .ended) }
        #expect(!detector.isActive)
        #expect(detector.sessionWindows.isEmpty)
    }

    @Test func oneMissedPollThenBackStaysActive() {
        var detector = MirroringDetector()
        _ = detector.update(windows: [big], screen: screen)
        _ = detector.update(windows: [], screen: screen)
        do { let event = detector.update(windows: [big], screen: screen); #expect(event == .none) }
        do { let event = detector.update(windows: [], screen: screen); #expect(event == .none) }
        #expect(detector.isActive)
    }

    @Test func twoDevicesThenOne() {
        var detector = MirroringDetector()
        let left = window(CGRect(x: 0, y: 0, width: 960, height: 1080))
        let right = window(CGRect(x: 960, y: 0, width: 960, height: 1080))
        do { let event = detector.update(windows: [left, right], screen: screen); #expect(event == .began) }
        do { let event = detector.update(windows: [left], screen: screen); #expect(event == .none) }
        #expect(detector.isActive)
        #expect(detector.sessionWindows == [left])
    }

    @Test func needsFullScreen() {
        var detector = MirroringDetector()
        #expect(!detector.needsFullScreen(screen: screen))
        _ = detector.update(windows: [big], screen: screen)
        #expect(detector.needsFullScreen(screen: screen))
        _ = detector.update(windows: [window(CGRect(x: 1, y: 0, width: 1918, height: 1080))], screen: screen)
        #expect(!detector.needsFullScreen(screen: screen))
    }

    @Test func restartLimiter() {
        var limiter = RestartLimiter()
        let start = Date(timeIntervalSince1970: 1_000)
        do { let allowed = limiter.allowRestart(at: start); #expect(allowed) }
        do { let allowed = limiter.allowRestart(at: start.addingTimeInterval(10)); #expect(allowed) }
        do { let allowed = limiter.allowRestart(at: start.addingTimeInterval(20)); #expect(allowed) }
        do { let allowed = limiter.allowRestart(at: start.addingTimeInterval(30)); #expect(!allowed) }
        do { let allowed = limiter.allowRestart(at: start.addingTimeInterval(601)); #expect(allowed) }
        limiter.reset()
        do { let allowed = limiter.allowRestart(at: start.addingTimeInterval(602)); #expect(allowed) }
        do { let allowed = limiter.allowRestart(at: start.addingTimeInterval(603)); #expect(allowed) }
    }
}

/// L22, M7h QA Q1: whether a session end shows MMTVL's home screen.
struct MirroringSessionEndTests {
    @Test func homeUnlessAnotherAppOrThePowerMenu() {
        let reflector = ReflectorMonitor.bundleID
        #expect(ReflectorMonitor.showsHomeAfterSession(frontBundleID: reflector, frontIsSelf: false, hasFrontApp: true,
                                                       isPowerMenuOpen: false))
        #expect(ReflectorMonitor.showsHomeAfterSession(frontBundleID: nil, frontIsSelf: false, hasFrontApp: false,
                                                       isPowerMenuOpen: false))
        #expect(ReflectorMonitor.showsHomeAfterSession(frontBundleID: "dev.mmtvl.launcher", frontIsSelf: true,
                                                       hasFrontApp: true, isPowerMenuOpen: false))
        #expect(!ReflectorMonitor.showsHomeAfterSession(frontBundleID: "tv.plex.htpc", frontIsSelf: false,
                                                        hasFrontApp: true, isPowerMenuOpen: false))
        // The power menu brought MMTVL over the mirrored window: the menu stays open.
        #expect(!ReflectorMonitor.showsHomeAfterSession(frontBundleID: "dev.mmtvl.launcher", frontIsSelf: true,
                                                        hasFrontApp: true, isPowerMenuOpen: true))
        #expect(!ReflectorMonitor.showsHomeAfterSession(frontBundleID: reflector, frontIsSelf: false, hasFrontApp: true,
                                                        isPowerMenuOpen: true))
    }
}
