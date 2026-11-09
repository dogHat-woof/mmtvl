import CoreGraphics
import Foundation
import Testing
@testable import MMTVL

/// M7h L16 (D45): CoreGraphics' display changes reduce to `HotplugEvent`s, and each marks Plex HTPC (running, not in
/// front) to restart on its next open; MMTVL turning the TV on does too.
struct DisplayHotplugTests {
    static let mmtvl = "dev.mmtvl.launcher"
    let fake = FakeLauncherWorkspace()

    // MARK: HotplugEvent

    @Test func addAndRemoveBecomeEvents() {
        #expect(HotplugEvent(displayID: 2, flags: .addFlag) == HotplugEvent(displayID: 2, change: .added))
        #expect(HotplugEvent(displayID: 3, flags: .removeFlag) == HotplugEvent(displayID: 3, change: .removed))
        #expect(HotplugEvent(displayID: 3, flags: [.removeFlag, .disabledFlag]) == HotplugEvent(displayID: 3, change: .removed))
    }

    @Test func otherChangesAreIgnored() {
        #expect(HotplugEvent(displayID: 1, flags: .beginConfigurationFlag) == nil)
        #expect(HotplugEvent(displayID: 1, flags: [.beginConfigurationFlag, .addFlag]) == nil)
        #expect(HotplugEvent(displayID: 1, flags: .setModeFlag) == nil)
        #expect(HotplugEvent(displayID: 1, flags: .movedFlag) == nil)
        #expect(HotplugEvent(displayID: 1, flags: .mirrorFlag) == nil)
        #expect(HotplugEvent(displayID: 1, flags: []) == nil)
    }

    // MARK: The monitor marks Plex

    private func monitor(_ launcher: AppLauncher, frontmost: String?) -> DisplayHotplugMonitor {
        let monitor = DisplayHotplugMonitor()
        monitor.onEvent = { _ in launcher.noteDisplayChange(frontmostBundleID: frontmost) }
        return monitor
    }

    @Test func aRemoveWhilePlexRunsInTheBackgroundMarksIt() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        monitor(launcher, frontmost: Self.mmtvl).handle(HotplugEvent(displayID: 2, change: .removed))
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
    }

    @Test func anAddWhilePlexRunsInTheBackgroundMarksIt() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        monitor(launcher, frontmost: "com.apple.finder").handle(HotplugEvent(displayID: 4, change: .added))
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
    }

    @Test func aTVPowerCycleBurstMarksItOnce() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        let monitor = monitor(launcher, frontmost: Self.mmtvl)
        for id: CGDirectDisplayID in [2, 3, 4, 5] {
            monitor.handle(HotplugEvent(displayID: id, change: .removed))
            monitor.handle(HotplugEvent(displayID: id + 1, change: .added))
        }
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
    }

    @Test func aDisplayChangeWhilePlexIsInFrontDoesNotMarkIt() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        let monitor = monitor(launcher, frontmost: "tv.plex.htpc")
        monitor.handle(HotplugEvent(displayID: 2, change: .removed))
        monitor.handle(HotplugEvent(displayID: 3, change: .added))
        #expect(launcher.restartOnNextOpen.isEmpty)
    }

    @Test func anotherAppInTheBackgroundIsNeverMarked() {
        fake.start("com.apple.Safari")
        fake.start("com.example.app")
        let launcher = AppLauncher(workspace: fake.workspace)
        monitor(launcher, frontmost: Self.mmtvl).handle(HotplugEvent(displayID: 2, change: .removed))
        #expect(launcher.restartOnNextOpen.isEmpty)
    }

    // MARK: Power on (L14)

    @Test func turningTheTVOnMarksPlex() async {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        let log = PowerLog()
        let power = PowerController(tv: FakePowerTV(log: log, on: true), receiver: FakePowerReceiver(log: log),
                                    effects: log.effects)
        var powerOns = 0
        power.onPowerOn = {
            powerOns += 1
            launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        }

        // Off: nothing marked.
        #expect(power.powerButton())
        await power.task?.value
        #expect(powerOns == 0)
        #expect(launcher.restartOnNextOpen.isEmpty)

        // On: marked, right after the displays wake.
        #expect(power.powerButton())
        await power.task?.value
        await power.outputLogTask?.value
        #expect(powerOns == 1)
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
    }

    @Test func turningOnWithoutATVStillMarksPlex() async {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        let log = PowerLog()
        let power = PowerController(tv: nil, receiver: FakePowerReceiver(log: log), effects: log.effects)
        power.onPowerOn = { launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl) }
        power.powerButton()
        await power.task?.value
        power.powerButton()
        await power.task?.value
        await power.outputLogTask?.value
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
    }

    // MARK: Registration (QA minor 3)

    /// Serialized with nothing else touching `DisplayHotplugMonitor.active` (only these tests start a monitor).
    @Test func startRegistersAndStopOrReleaseUnregisters() {
        var monitor: DisplayHotplugMonitor? = DisplayHotplugMonitor()
        monitor?.start()
        #expect(DisplayHotplugMonitor.active === monitor)
        monitor?.stop()
        #expect(DisplayHotplugMonitor.active == nil)

        monitor?.start()
        weak let released = monitor
        monitor = nil
        // deinit stopped it: nothing is left registered or active, and a new monitor can start.
        #expect(released == nil)
        #expect(DisplayHotplugMonitor.active == nil)
        let next = DisplayHotplugMonitor()
        next.start()
        #expect(DisplayHotplugMonitor.active === next)
        next.stop()
    }
}
