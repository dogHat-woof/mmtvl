import Foundation
import Testing
@testable import MMTVL

struct AppLauncherTests {
    @Test func chromiumBrowsersStartFullScreen() {
        #expect(AppLauncher.launchArguments(browserBundleID: "com.brave.Browser", fullScreen: true) == ["--start-fullscreen"])
        #expect(AppLauncher.launchArguments(browserBundleID: "com.google.Chrome", fullScreen: true) == ["--start-fullscreen"])
    }

    @Test func noArgumentsWhenFullScreenIsOff() {
        #expect(AppLauncher.launchArguments(browserBundleID: "com.brave.Browser", fullScreen: false).isEmpty)
    }

    @Test func nonChromiumBrowsersGetNoArguments() {
        #expect(AppLauncher.launchArguments(browserBundleID: "com.apple.Safari", fullScreen: true).isEmpty)
        #expect(AppLauncher.launchArguments(browserBundleID: nil, fullScreen: true).isEmpty)
    }
}

struct LaunchCancellationTests {
    private let start = Date(timeIntervalSince1970: 1_791_200_000)

    @Test func homeDuringALaunchSendsTheAppBack() {
        var cancellation = LaunchCancellation()
        cancellation.began("tv.plex.htpc", at: start)
        #expect(cancellation.homePressed(at: start + 3) == "tv.plex.htpc")
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 8))
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 22))
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 23) == false)
        #expect(cancellation.shouldReturn(activated: "com.apple.Safari", at: start + 8) == false)
        #expect(cancellation.shouldReturn(activated: nil, at: start + 8) == false)
    }

    @Test func homeLongAfterALaunchCancelsNothing() {
        var cancellation = LaunchCancellation()
        cancellation.began("tv.plex.htpc", at: start)
        #expect(cancellation.homePressed(at: start + 20) == nil)
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 21) == false)
    }

    @Test func withoutALaunchNothingIsCancelled() {
        var cancellation = LaunchCancellation()
        #expect(cancellation.homePressed(at: start) == nil)
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start) == false)
    }

    @Test func aNewLaunchClearsTheCancellation() {
        var cancellation = LaunchCancellation()
        cancellation.began("tv.plex.htpc", at: start)
        _ = cancellation.homePressed(at: start + 2)
        cancellation.began("tv.plex.htpc", at: start + 5)
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 8) == false)
    }
}

struct WantsFullScreenTests {
    private func app(_ launchFullScreen: Bool?) -> LaunchItem {
        LaunchItem(id: "a", title: "App", kind: .application(bundleID: "com.example.app"), launchFullScreen: launchFullScreen)
    }

    private func browser(_ launchFullScreen: Bool?) -> LaunchItem {
        LaunchItem(id: "b", title: "Browser", kind: .defaultBrowser(fullScreen: true), launchFullScreen: launchFullScreen)
    }

    @Test func applicationDefaultsToWindowed() {
        #expect(!app(nil).wantsFullScreen)
        #expect(app(true).wantsFullScreen)
        #expect(!app(false).wantsFullScreen)
    }

    @Test func defaultBrowserFollowsKindUnlessOverridden() {
        #expect(browser(nil).wantsFullScreen)
        #expect(!browser(false).wantsFullScreen)
    }

    @Test func primeDefaultIsFullScreen() {
        #expect(LaunchItem.defaults.first { $0.id == "prime" }?.wantsFullScreen == true)
    }

    @Test func oldJSONWithoutLaunchFullScreenDecodes() throws {
        let json = #"{ "id" : "plex", "title" : "Plex", "kind" : { "application" : { "bundleID" : "tv.plex.htpc" } } }"#
        let item = try JSONDecoder().decode(LaunchItem.self, from: Data(json.utf8))
        #expect(item.launchFullScreen == nil)
        #expect(!item.wantsFullScreen)
    }
}

/// Chromium web app tiles (M7 L18, L23).
struct WebAppTests {
    private func makeBundle(_ plist: [String: Any]) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory.appending(path: "WebAppTests-\(UUID().uuidString)/Meet.app")
        let contents = bundle.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }

    @Test func readsAWebAppShim() throws {
        let bundle = try makeBundle([
            "CFBundleIdentifier": "com.brave.Browser.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
            "CrAppModeShortcutID": "kjgfgldnnfoeklkmfkjfagphfepbbdan",
            "CrAppModeShortcutName": "Google Meet",
            "CrAppModeShortcutURL": "https://meet.google.com/landing?lfhs=2",
            "CrBundleIdentifier": "com.brave.Browser",
        ])
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        #expect(WebApp.info(bundleURL: bundle) == WebAppInfo(
            appID: "kjgfgldnnfoeklkmfkjfagphfepbbdan", name: "Google Meet",
            startURL: URL(string: "https://meet.google.com/landing?lfhs=2"), browserBundleID: "com.brave.Browser"))
    }

    @Test func aNormalAppIsNoWebApp() throws {
        let bundle = try makeBundle(["CFBundleIdentifier": "tv.plex.htpc", "CFBundleName": "Plex HTPC"])
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        #expect(WebApp.info(bundleURL: bundle) == nil)
        #expect(WebApp.info(bundleURL: URL(fileURLWithPath: "/nonexistent/App.app")) == nil)
    }

    @Test func launchArguments() {
        let url = URL(string: "https://meet.google.com/home?calling=1")!
        #expect(WebApp.launchArguments(appID: "kjg", startURL: url)
            == ["--app-id=kjg", "--app-launch-url-for-shortcuts-menu-item=https://meet.google.com/home?calling=1"])
    }

    @Test func handoffBoundaries() {
        let launch = Date(timeIntervalSince1970: 1000)
        #expect(WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch + 0.3))
        #expect(WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch + 5))
        #expect(!WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch + 5.1))
        #expect(!WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch - 1))
    }
}

// MARK: M7h L16: restart after a hot-plug

/// A fake running app. Pids start above 99 998 (macOS's highest), so none is ever a real process.
final class FakeRunningApp: LauncherRunningApp {
    let processIdentifier: pid_t
    var isTerminated = false
    /// False: `terminate()` is ignored, only a force quit ends it.
    var quitsWhenAsked = true
    /// True: a force quit is ignored too (a stuck process).
    var ignoresForceQuit = false
    /// Runs inside `terminate()`, before it quits (tests look at the launcher there).
    var onTerminate: () -> Void = {}
    private let log: (String) -> Void

    init(pid: pid_t, log: @escaping (String) -> Void) {
        processIdentifier = pid
        self.log = log
    }

    func terminate() -> Bool {
        log("terminate \(processIdentifier)")
        onTerminate()
        if quitsWhenAsked { isTerminated = true }
        return true
    }

    func forceTerminate() -> Bool {
        log("forceTerminate \(processIdentifier)")
        if !ignoresForceQuit { isTerminated = true }
        return true
    }
}

/// Fakes `LauncherWorkspace`: nothing real is opened, found or quit, and sleeping returns at once (a fake clock).
final class FakeLauncherWorkspace {
    var events: [String] = []
    var running: [String: [FakeRunningApp]] = [:]
    var sleeps: [Duration] = []
    private var nextPID: pid_t = 100_001

    var slept: Duration { sleeps.reduce(.zero, +) }

    var workspace: LauncherWorkspace {
        LauncherWorkspace(
            appURL: { URL(filePath: "/nonexistent/\($0).app") },
            runningApps: { self.running[$0, default: []].filter { !$0.isTerminated } },
            openApplication: { url, _ in
                let bundleID = url.deletingPathExtension().lastPathComponent
                // Like NSWorkspace: a running app is brought forward, else a new process starts.
                let app = self.running[bundleID, default: []].first { !$0.isTerminated } ?? self.start(bundleID)
                self.events.append("open \(bundleID) \(app.processIdentifier)")
                return app.processIdentifier
            },
            sleep: { self.sleeps.append($0) }
        )
    }

    /// An app already running (started outside MMTVL, or by an earlier open).
    @discardableResult
    func start(_ bundleID: String) -> FakeRunningApp {
        let app = FakeRunningApp(pid: nextPID) { [weak self] in self?.events.append($0) }
        nextPID += 1
        running[bundleID, default: []].append(app)
        return app
    }
}

struct AppLauncherRestartTests {
    static let plex = LaunchItem(id: "plex", title: "Plex", kind: .application(bundleID: "tv.plex.htpc"))
    static let other = LaunchItem(id: "other", title: "Other", kind: .application(bundleID: "com.example.app"))
    static let mmtvl = "dev.mmtvl.launcher"

    let fake = FakeLauncherWorkspace()

    @Test func onlyPlexIsListed() {
        #expect(AppLauncher.restartAfterHotplug == ["tv.plex.htpc"])
    }

    @Test func aDisplayChangeMarksPlexRunningInTheBackground() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
        // A burst of changes (a TV power cycle) marks it once.
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        launcher.noteDisplayChange(frontmostBundleID: nil)
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
    }

    @Test func plexInFrontIsNotMarked() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: "tv.plex.htpc")
        #expect(launcher.restartOnNextOpen.isEmpty)
    }

    /// M7h user decision (2026-11-06): a power-on marks Plex even when it's in front (MMTVL's home screen is about to
    /// cover it); a display change still doesn't (L16).
    @Test func powerOnMarksPlexEvenInFront() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: "tv.plex.htpc")
        #expect(launcher.restartOnNextOpen.isEmpty)
        launcher.notePowerOn()
        #expect(launcher.restartOnNextOpen == ["tv.plex.htpc"])
        #expect(launcher.willRestart(Self.plex))
        // Not running: nothing to mark.
        let empty = AppLauncher(workspace: FakeLauncherWorkspace().workspace)
        empty.notePowerOn()
        #expect(empty.restartOnNextOpen.isEmpty)
    }

    /// The app's power-on: Plex marked first (while it may still be in front), then home like a global Home.
    @Test func powerOnHandlerMarksThenGoesHome() {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        var marksAtHome: [Set<String>] = []
        let handler = PowerController.powerOnHandler(launcher: launcher, goHome: {
            marksAtHome.append(launcher.restartOnNextOpen)
        })
        handler()
        #expect(marksAtHome == [["tv.plex.htpc"]])
    }

    @Test func plexNotRunningIsNotMarked() {
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        #expect(launcher.restartOnNextOpen.isEmpty)
    }

    @Test func anAppNotListedIsNeverMarkedOrQuit() async throws {
        fake.start("com.example.app")
        fake.start("com.apple.Safari")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        #expect(launcher.restartOnNextOpen.isEmpty)
        try await launcher.launch(Self.other)
        #expect(fake.events == ["open com.example.app 100001"])
    }

    @Test func openingAMarkedPlexQuitsItThenLaunchesItAgain() async throws {
        let launcher = AppLauncher(workspace: fake.workspace)
        // Opened from its tile earlier: MMTVL goes Home when that pid quits.
        try await launcher.launch(Self.plex)
        let old = try #require(fake.running["tv.plex.htpc"]?.first)
        #expect(launcher.launchedPIDs == [old.processIdentifier])

        var trackedWhenQuitting: Bool?
        old.onTerminate = { trackedWhenQuitting = launcher.launchedPIDs.contains(old.processIdentifier) }
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        fake.events = []
        try await launcher.launch(Self.plex)

        // The pid left launchedPIDs before terminate(), so its quit doesn't bring the launcher back.
        #expect(trackedWhenQuitting == false)
        #expect(fake.events == ["terminate 100001", "open tv.plex.htpc 100002"])
        #expect(launcher.launchedPIDs == [100_002])
        #expect(launcher.restartOnNextOpen.isEmpty)
        #expect(fake.sleeps.isEmpty)

        // The old process's quit notification is ignored (not a launched pid any more).
        launcher.applicationDidTerminate(pid: old.processIdentifier)
        #expect(launcher.launchedPIDs == [100_002])
    }

    @Test func aPlexThatDoesNotQuitIsForceQuitAfterFiveSeconds() async throws {
        let old = fake.start("tv.plex.htpc")
        old.quitsWhenAsked = false
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["terminate 100001", "forceTerminate 100001", "open tv.plex.htpc 100002"])
        #expect(fake.slept == .seconds(5))
        #expect(fake.sleeps.allSatisfy { $0 == AppLauncher.restartPoll })
    }

    @Test func aPlexThatQuitsSlowlyIsNotForceQuit() async throws {
        let old = fake.start("tv.plex.htpc")
        old.quitsWhenAsked = false
        // It quits on its own after 1 s of the fake clock.
        let base = fake.workspace
        let fake = fake
        let workspace = LauncherWorkspace(appURL: base.appURL, runningApps: base.runningApps,
                                          openApplication: base.openApplication) { duration in
            await base.sleep(duration)
            if fake.slept >= .seconds(1) { old.isTerminated = true }
        }
        let launcher = AppLauncher(workspace: workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["terminate 100001", "open tv.plex.htpc 100002"])
        #expect(fake.slept == .seconds(1))
    }

    @Test func anUnmarkedPlexOpensAsBefore() async throws {
        let running = fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["open tv.plex.htpc 100001"])
        #expect(!running.isTerminated)
        #expect(launcher.launchedPIDs == [100_001])
    }

    @Test func aMarkIsUsedOnce() async throws {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        try await launcher.launch(Self.plex)
        fake.events = []
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["open tv.plex.htpc 100002"])
    }

    @Test func aMarkedPlexThatQuitMeanwhileJustOpens() async throws {
        let old = fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        old.isTerminated = true
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["open tv.plex.htpc 100002"])
        #expect(launcher.restartOnNextOpen.isEmpty)
    }

    @Test func theRestartedPlexIsStillAnOpenedApp() async throws {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        var opened: [[String]] = []
        launcher.onOpened = { opened.append($0) }
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        try await launcher.launch(Self.plex)
        // The kiosk guard is told before the restart, so the new process is allowed (D36).
        #expect(opened == [["tv.plex.htpc"]])
    }

    // MARK: Review fixes

    /// QA major (security low 1): a second open while the first waits for the old Plex to quit opens nothing; the
    /// running restart opens the new process, and the old pid is never tracked again.
    @Test func overlappingOpensOfAMarkedPlexQuitAndOpenItOnce() async throws {
        let old = fake.start("tv.plex.htpc")
        old.quitsWhenAsked = false
        let base = fake.workspace
        var launcher: AppLauncher?
        var trackedDuringRestart: [Bool] = []
        var secondOpened = false
        // The first poll of the restart: the second Select arrives, then the old Plex quits.
        let workspace = LauncherWorkspace(appURL: base.appURL, runningApps: base.runningApps,
                                          openApplication: base.openApplication) { duration in
            await base.sleep(duration)
            guard let launcher, !secondOpened else { return }
            secondOpened = true
            #expect(launcher.restarting == ["tv.plex.htpc"])
            try? await launcher.launch(Self.plex)
            trackedDuringRestart.append(launcher.launchedPIDs.contains(old.processIdentifier))
            old.isTerminated = true
        }
        let restartingLauncher = AppLauncher(workspace: workspace)
        launcher = restartingLauncher
        restartingLauncher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        #expect(restartingLauncher.willRestart(Self.plex))
        try await restartingLauncher.launch(Self.plex)

        #expect(secondOpened)
        #expect(fake.events == ["terminate 100001", "open tv.plex.htpc 100002"])
        #expect(trackedDuringRestart == [false])
        #expect(restartingLauncher.launchedPIDs == [100_002])
        #expect(restartingLauncher.restarting.isEmpty)
        #expect(!restartingLauncher.willRestart(Self.plex))
    }

    /// Security low 2: the marked Plex quit and Plex started again; the new one is healthy and isn't quit.
    @Test func aStaleMarkDoesNotQuitALaterInstance() async throws {
        let old = fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        old.isTerminated = true
        let later = fake.start("tv.plex.htpc")
        #expect(!launcher.willRestart(Self.plex))
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["open tv.plex.htpc 100002"])
        #expect(!later.isTerminated)
        #expect(launcher.restartOnNextOpen.isEmpty)
    }

    /// The later instance is marked too when another display change happens while it runs.
    @Test func aLaterDisplayChangeMarksTheNewInstance() async throws {
        let old = fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        old.isTerminated = true
        fake.start("tv.plex.htpc")
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["terminate 100002", "open tv.plex.htpc 100003"])
    }

    /// QA minor 1: a process that outlives the force quit is opened (it's what's there) but never tracked, so its
    /// eventual quit doesn't bring the launcher back over the app.
    @Test func aStuckProcessIsNotTracked() async throws {
        let old = fake.start("tv.plex.htpc")
        old.quitsWhenAsked = false
        old.ignoresForceQuit = true
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: Self.mmtvl)
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["terminate 100001", "forceTerminate 100001", "open tv.plex.htpc 100001"])
        #expect(fake.slept == .seconds(6))
        #expect(launcher.launchedPIDs.isEmpty)
        #expect(launcher.restarting.isEmpty)
    }
}

// MARK: M7m L7: Quit and Restart from the tile menu

struct AppLauncherQuitTests {
    static let plex = AppLauncherRestartTests.plex
    static let other = AppLauncherRestartTests.other

    let fake = FakeLauncherWorkspace()

    @Test func isRunningForAnAppTileAndNotForInternalTiles() {
        let launcher = AppLauncher(workspace: fake.workspace)
        #expect(!launcher.isRunning(Self.plex))
        fake.start("tv.plex.htpc")
        #expect(launcher.isRunning(Self.plex))
        #expect(!launcher.isRunning(Self.other))
        let browser = LaunchItem(id: "web", title: "Web",
                                 kind: .url(URL(string: "https://example.com")!, browserBundleID: "com.brave.Browser"))
        #expect(!launcher.isRunning(browser))
        fake.start("com.brave.Browser")
        #expect(launcher.isRunning(browser))
        let youtube = LaunchItem(id: "youtube", title: "YouTube", kind: .internalDestination(.youtube))
        let settings = LaunchItem(id: "settings", title: "Settings", kind: .internalDestination(.settings))
        #expect(!launcher.isRunning(youtube))
        #expect(!launcher.isRunning(settings))
    }

    @Test func quitTerminatesAndForgetsThePid() async throws {
        let launcher = AppLauncher(workspace: fake.workspace)
        try await launcher.launch(Self.plex)
        let app = try #require(fake.running["tv.plex.htpc"]?.first)
        #expect(launcher.launchedPIDs == [app.processIdentifier])
        var returns = 0
        launcher.onReturnToLauncher = { returns += 1 }
        var trackedWhenQuitting: Bool?
        app.onTerminate = { trackedWhenQuitting = launcher.launchedPIDs.contains(app.processIdentifier) }
        fake.events = []

        await launcher.quit(Self.plex)

        #expect(trackedWhenQuitting == false)
        #expect(fake.events == ["terminate 100001"])
        #expect(app.isTerminated)
        #expect(launcher.launchedPIDs.isEmpty)
        #expect(!launcher.isRunning(Self.plex))
        #expect(fake.sleeps.isEmpty)
        // The quit notification arrives: no return to the launcher, even after the settle delay.
        launcher.applicationDidTerminate(pid: app.processIdentifier)
        try await Task.sleep(for: AppLauncher.quitSettleDelay + .milliseconds(300))
        #expect(returns == 0)
    }

    @Test func quitForceQuitsAfterFiveSeconds() async {
        let app = fake.start("tv.plex.htpc")
        app.quitsWhenAsked = false
        let launcher = AppLauncher(workspace: fake.workspace)
        await launcher.quit(Self.plex)
        #expect(fake.events == ["terminate 100001", "forceTerminate 100001"])
        #expect(fake.slept == .seconds(5))
        #expect(app.isTerminated)
    }

    @Test func quitClearsThePlexHotplugMark() async throws {
        fake.start("tv.plex.htpc")
        let launcher = AppLauncher(workspace: fake.workspace)
        launcher.noteDisplayChange(frontmostBundleID: AppLauncherRestartTests.mmtvl)
        #expect(launcher.willRestart(Self.plex))
        await launcher.quit(Self.plex)
        #expect(launcher.restartOnNextOpen.isEmpty)
        #expect(!launcher.willRestart(Self.plex))
        // Restart = quit, then open: a fresh launch, not a second quit.
        fake.events = []
        try await launcher.launch(Self.plex)
        #expect(fake.events == ["open tv.plex.htpc 100002"])
    }

    /// QA minor: a Select on the tile while the quit waits opens nothing (the old process is on its way out and its
    /// death would send the user home); after the quit the tile opens a fresh process.
    @Test func selectDuringAQuitDoesntOpenTheOldProcess() async throws {
        let old = fake.start("tv.plex.htpc")
        old.quitsWhenAsked = false
        let base = fake.workspace
        var launcher: AppLauncher?
        var restartingDuringQuit: Set<String>?
        // The quit's first poll: the Select arrives while the old Plex is still running.
        let workspace = LauncherWorkspace(appURL: base.appURL, runningApps: base.runningApps,
                                          openApplication: base.openApplication) { duration in
            await base.sleep(duration)
            guard let launcher, restartingDuringQuit == nil else { return }
            restartingDuringQuit = launcher.restarting
            try? await launcher.launch(Self.plex)
        }
        let quitting = AppLauncher(workspace: workspace)
        launcher = quitting
        await quitting.quit(Self.plex)

        #expect(restartingDuringQuit == ["tv.plex.htpc"])
        #expect(fake.events == ["terminate 100001", "forceTerminate 100001"])
        #expect(!quitting.launchedPIDs.contains(old.processIdentifier))
        #expect(quitting.restarting.isEmpty)
        fake.events = []
        try await quitting.launch(Self.plex)
        #expect(fake.events == ["open tv.plex.htpc 100002"])
    }

    /// QA minor: a process that ignores the force quit too: the quit gives up after 5 + 1 s and returns.
    @Test func quitOfAStuckAppGivesUpAfterSixSeconds() async {
        let app = fake.start("tv.plex.htpc")
        app.quitsWhenAsked = false
        app.ignoresForceQuit = true
        let launcher = AppLauncher(workspace: fake.workspace)
        await launcher.quit(Self.plex)
        #expect(fake.events == ["terminate 100001", "forceTerminate 100001"])
        #expect(fake.slept == .seconds(6))
        #expect(!app.isTerminated)
        #expect(launcher.restarting.isEmpty)
        #expect(launcher.launchedPIDs.isEmpty)
    }

    @Test func quitOfAStoppedAppDoesNothing() async {
        let launcher = AppLauncher(workspace: fake.workspace)
        await launcher.quit(Self.plex)
        await launcher.quit(LaunchItem(id: "settings", title: "Settings", kind: .internalDestination(.settings)))
        #expect(fake.events.isEmpty)
        #expect(fake.sleeps.isEmpty)
    }
}
