import Foundation
import Testing
@testable import MMTVL

/// M7m L20: `ScreenSaver` against a faked system (engines by pid, terminate, user activity, open).
struct ScreenSaverTests {
    final class FakeSystem {
        var pids: [pid_t] = []
        var terminated: [pid_t] = []
        var activityDeclarations = 0
        var opens = 0
        var openSucceeds = true

        var system: ScreenSaver.System {
            ScreenSaver.System(
                runningEnginePIDs: { self.pids },
                terminate: { pid in
                    self.terminated.append(pid)
                    self.pids.removeAll { $0 == pid }
                },
                declareUserActivity: { self.activityDeclarations += 1 },
                open: { done in
                    self.opens += 1
                    let opened = self.openSucceeds
                    if opened { self.pids.append(100 + pid_t(self.opens)) }
                    MainActor.assumeIsolated { done(opened) }
                }
            )
        }
    }

    private func make(_ fake: FakeSystem) -> (ScreenSaver, () -> [Bool]) {
        let saver = ScreenSaver(system: fake.system, endCheckDelay: .zero)
        var stops: [Bool] = []
        saver.onStop = { stops.append($0) }
        return (saver, { stops })
    }

    /// Security medium: a `didstart` with no screen saver behind it is cleared by the next `end()`.
    @Test func endWithNoEngineReportsTheStopOnce() async {
        let fake = FakeSystem()
        let (saver, stops) = make(fake)
        saver.didStart()
        #expect(saver.isRunning)
        #expect(!saver.isEngineRunning)
        await saver.end()?.value
        #expect(stops() == [false])
        #expect(!saver.isRunning)
        #expect(fake.terminated.isEmpty)
        #expect(fake.activityDeclarations == 1)
        await saver.end()?.value
        #expect(stops() == [false])
    }

    /// QA minor: the engines running at the press that still run at the check are terminated, and the stop reported.
    @Test func anEngineStillRunningAtTheCheckIsTerminated() async {
        let fake = FakeSystem()
        fake.pids = [10]
        let (saver, stops) = make(fake)
        saver.didStart()
        let task = saver.end()
        #expect(saver.end() == task)
        await task?.value
        #expect(fake.terminated == [10])
        #expect(stops() == [false])
        #expect(!saver.isRunning)
        #expect(fake.activityDeclarations == 1)
    }

    /// The declared activity ended it: `didstop` reported the stop; nothing is terminated or reported again.
    @Test func userActivityEndsItWithoutTerminating() async {
        let fake = FakeSystem()
        fake.pids = [10]
        let (saver, stops) = make(fake)
        saver.didStart()
        let task = saver.end()
        fake.pids = []
        saver.didStop()
        await task?.value
        #expect(fake.terminated.isEmpty)
        #expect(stops() == [false])
    }

    /// QA step 7 (minor): a slow engine still listed after `didstop` is terminated at the check, but the stop isn't
    /// reported again, so the router opens no second grace window.
    @Test func aSlowEngineAfterDidstopIsntReportedStoppedTwice() async {
        let fake = FakeSystem()
        fake.pids = [10]
        let saver = ScreenSaver(system: fake.system, endCheckDelay: .zero)
        let (settings, _) = makeSettingsModel()
        let router = AppRouter(items: LaunchItem.defaults, launcher: AppLauncher(), settings: settings,
                               youtube: FakeYouTube(), liveTV: FakeLiveTV(), pinStore: .inMemory(nil),
                               tileArt: makeTestTileArt())
        var stops: [Bool] = []
        var routerStops = 0
        saver.onStop = { wasOurs in
            stops.append(wasOurs)
            routerStops += 1
            router.screenSaverDidStop()
        }
        var endTask: Task<Void, Never>?
        router.endScreenSaver = { endTask = saver.end() }
        router.isScreenSaverEngineRunning = { saver.isEngineRunning }
        router.isAppActive = false
        saver.didStart()
        router.screenSaverDidStart()
        // A press ends it; `didstop` comes while the engine is still listed.
        #expect(router.endScreenSaverIfShowing(by: "select"))
        saver.didStop()
        await endTask?.value
        #expect(fake.terminated == [10])
        #expect(stops == [false])
        #expect(routerStops == 1)
        // No grace window: the next press goes through.
        #expect(!router.endScreenSaverIfShowing(by: "select"))
    }

    /// QA minor: a new session that started within the check is never terminated, and isn't reported stopped.
    @Test func aNewSessionIsNeverTerminated() async {
        let fake = FakeSystem()
        fake.pids = [10]
        let (saver, stops) = make(fake)
        saver.didStart()
        let task = saver.end()
        fake.pids = [11]
        await task?.value
        #expect(fake.terminated.isEmpty)
        #expect(stops().isEmpty)
        #expect(saver.isRunning)
        // Both the old engine (still there) and a new one: only the old one goes.
        fake.pids = [11]
        let second = saver.end()
        fake.pids = [11, 12]
        await second?.value
        #expect(fake.terminated == [11])
        #expect(stops().isEmpty)
    }

    /// QA minor: MMTVL's own only when it opened and none was running; cleared once MMTVL is active again.
    @Test func startedByMMTVLOnlyWhenItStartedOne() {
        let fake = FakeSystem()
        let (saver, stops) = make(fake)
        saver.start()
        #expect(saver.startedByMMTVL)
        saver.didStart()
        saver.didStop()
        #expect(stops() == [true])

        // Already running (macOS's own): not ours.
        saver.didStart()
        saver.start()
        #expect(!saver.startedByMMTVL)
        saver.didStop()
        #expect(stops() == [true, false])

        // Couldn't open: not ours.
        fake.pids = []
        fake.openSucceeds = false
        saver.start()
        #expect(!saver.startedByMMTVL)

        // MMTVL active again before the stop: not one to come back from.
        fake.openSucceeds = true
        saver.start()
        #expect(saver.startedByMMTVL)
        saver.appDidBecomeActive()
        #expect(!saver.startedByMMTVL)
    }
}
