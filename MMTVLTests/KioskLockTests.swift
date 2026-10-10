import Carbon.HIToolbox
import Foundation
import Testing
@testable import MMTVL

struct KioskLockShortcutTests {
    private func blocks(_ keyCode: Int, _ modifiers: Set<KeyModifier>) -> Bool {
        KioskLock.blocks(keyCode: UInt16(keyCode), modifiers: modifiers)
    }

    @Test func blockedShortcuts() {
        #expect(blocks(kVK_Tab, [.command]))
        #expect(blocks(kVK_Tab, [.command, .shift]))
        #expect(blocks(kVK_ANSI_Grave, [.command]))
        #expect(blocks(kVK_Space, [.command]))
        #expect(blocks(kVK_Escape, [.command, .option]))
        #expect(blocks(kVK_LeftArrow, [.control]))
        #expect(blocks(kVK_RightArrow, [.control]))
        #expect(blocks(kVK_UpArrow, [.control]))
        #expect(blocks(kVK_DownArrow, [.control]))
    }

    @Test func otherKeysPass() {
        #expect(!blocks(kVK_Tab, []))
        #expect(!blocks(kVK_Tab, [.shift]))
        #expect(!blocks(kVK_Space, []))
        #expect(!blocks(kVK_Space, [.option]))
        #expect(!blocks(kVK_Escape, []))
        #expect(!blocks(kVK_LeftArrow, []))
        #expect(!blocks(kVK_ANSI_Q, [.command]))
        #expect(!blocks(kVK_Home, []))
    }
}

struct KioskGuardTests {
    final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 0)
    }

    private func makeGuard(_ clock: Clock = Clock()) -> KioskGuard {
        let kioskGuard = KioskGuard(now: { clock.now })
        kioskGuard.isEnabled = true
        return kioskGuard
    }

    private func activate(_ kioskGuard: KioskGuard, _ bundleID: String?, isRegular: Bool = true,
                          isSelf: Bool = false) -> KioskGuard.Decision {
        kioskGuard.appDidActivate(bundleID: bundleID, isRegular: isRegular, isSelf: isSelf)
    }

    @Test func allowedAppsAreIgnored() {
        let kioskGuard = makeGuard()
        kioskGuard.opened(bundleIDs: ["com.apple.FaceTime"])
        kioskGuard.opened(bundleIDs: ["com.brave.Browser.app.meet", "com.brave.Browser"])
        #expect(activate(kioskGuard, "com.apple.FaceTime") == .ignore)
        #expect(activate(kioskGuard, "com.brave.Browser") == .ignore)
        #expect(activate(kioskGuard, ReflectorMonitor.bundleID) == .ignore)
        #expect(activate(kioskGuard, "dev.mmtvl.launcher", isSelf: true) == .ignore)
        #expect(activate(kioskGuard, "com.apple.notificationcenterui", isRegular: false) == .ignore)
    }

    @Test func unopenedAppsAreTakenBack() {
        let kioskGuard = makeGuard()
        #expect(activate(kioskGuard, "com.apple.finder") == .takeBack)
        kioskGuard.opened(bundleIDs: ["tv.plex.htpc"])
        #expect(activate(kioskGuard, "com.apple.Safari") == .takeBack)
        #expect(activate(kioskGuard, nil) == .takeBack)
    }

    @Test func homeClearsTheSessionApps() {
        let kioskGuard = makeGuard()
        kioskGuard.opened(bundleIDs: ["tv.plex.htpc"])
        kioskGuard.homePressed()
        #expect(activate(kioskGuard, "tv.plex.htpc") == .takeBack)
    }

    @Test func systemSettingsOnlyWhileMMTVLOpenedIt() {
        let kioskGuard = makeGuard()
        #expect(activate(kioskGuard, KioskGuard.systemSettingsBundleID) == .takeBack)
        kioskGuard.openedSystemSettings()
        #expect(activate(kioskGuard, KioskGuard.systemSettingsBundleID) == .ignore)
        kioskGuard.homePressed()
        #expect(activate(kioskGuard, KioskGuard.systemSettingsBundleID) == .takeBack)
    }

    @Test func rateLimitStopsUntilHome() {
        let clock = Clock()
        let kioskGuard = makeGuard(clock)
        for _ in 0..<3 {
            #expect(activate(kioskGuard, "com.apple.finder") == .takeBack)
            clock.now += 2
        }
        #expect(activate(kioskGuard, "com.apple.finder") == .ignore)
        // Stays stopped, even after the window passes, until Home.
        clock.now += 60
        #expect(activate(kioskGuard, "com.apple.finder") == .ignore)
        kioskGuard.homePressed()
        #expect(activate(kioskGuard, "com.apple.finder") == .takeBack)
    }

    @Test func takebacksSpreadOutAreFine() {
        let clock = Clock()
        let kioskGuard = makeGuard(clock)
        for _ in 0..<6 {
            #expect(activate(kioskGuard, "com.apple.finder") == .takeBack)
            clock.now += 5
        }
    }

    @Test func disabledIgnoresEverything() {
        let kioskGuard = makeGuard()
        kioskGuard.isEnabled = false
        #expect(activate(kioskGuard, "com.apple.finder") == .ignore)
    }
}
