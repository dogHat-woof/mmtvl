import AppKit
import OSLog

/// M7m L20 (D51, burn-in): macOS's screen saver, which MMTVL starts after a still screen has been dimmed for
/// `Theme.screenSaverAfterDim`, and ends on a press macOS doesn't see itself (the phone's buttons and text; the Siri
/// Remote's presses end it by themselves, step 1 (b)). `isRunning` follows macOS's `com.apple.screensaver.didstart`
/// and `didstop` (`AppDelegate.observeScreensSleep`), whoever started it. Terminating the engine posts no `didstop`
/// (checked on this Mac, 2026-11-09), so `end()` reports that stop itself through `onStop`.
final class ScreenSaver {
    nonisolated static let bundleID = "com.apple.ScreenSaver.Engine"
    /// A fixed path, never looked up by name.
    nonisolated static let engineURL = URL(filePath: "/System/Library/CoreServices/ScreenSaverEngine.app")
    nonisolated private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Idle")

    /// What the screen saver needs from the system; tests fake it.
    struct System {
        /// The running engines' process ids: bundle id `bundleID` at `engineURL` only.
        var runningEnginePIDs: () -> [pid_t]
        /// Terminates that process, if it's still the engine.
        var terminate: (pid_t) -> Void
        /// `SystemPower.declareUserActivity()`.
        var declareUserActivity: () -> Void
        /// Opens `engineURL`; calls back on the main actor with whether it opened.
        var open: (_ done: @escaping @MainActor (Bool) -> Void) -> Void

        static let live = System(
            runningEnginePIDs: { ScreenSaver.runningEngines().map(\.processIdentifier) },
            terminate: { pid in
                guard let app = NSRunningApplication(processIdentifier: pid), ScreenSaver.isEngine(app) else { return }
                app.terminate()
            },
            declareUserActivity: { SystemPower.declareUserActivity() },
            open: { done in
                NSWorkspace.shared.openApplication(at: ScreenSaver.engineURL,
                                                   configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error {
                        ScreenSaver.logger.error("Couldn't start the screen saver: \(error.localizedDescription, privacy: .public)")
                    }
                    let opened = error == nil
                    Task { @MainActor in done(opened) }
                }
            }
        )
    }

    private let system: System
    private let endCheckDelay: Duration
    /// macOS said the screen saver started and hasn't said it stopped (or `end()` found it gone).
    private(set) var isRunning = false
    /// MMTVL started the screen saver that's running, so it comes back in front after. Cleared when MMTVL is
    /// active again (`appDidBecomeActive`).
    private(set) var startedByMMTVL = false
    private var endTask: Task<Void, Never>?
    /// Counts reported stops, so `end()`'s check reports one only if none came since it began (QA: a slow engine
    /// still listed after `didstop` mustn't be reported stopped twice).
    private var stopCount = 0
    /// The screen saver stopped (`didstop`, or `end()` terminated it or found it gone); `wasOurs`: MMTVL had started it.
    var onStop: (_ wasOurs: Bool) -> Void = { _ in }

    init(system: System = .live, endCheckDelay: Duration = Theme.screenSaverEndCheckDelay) {
        self.system = system
        self.endCheckDelay = endCheckDelay
    }

    /// An engine runs (the security check behind `AppRouter.isScreenSaverShowing`: a `didstart` alone, which any
    /// local process can post, isn't enough).
    var isEngineRunning: Bool { !system.runningEnginePIDs().isEmpty }

    func start() {
        // QA minor: ours only if it opened and no screen saver was running already.
        let alreadyRunning = isRunning || isEngineRunning
        system.open { [weak self] opened in
            guard opened else { return }
            ScreenSaver.logger.info("Started the screen saver")
            if !alreadyRunning { self?.startedByMMTVL = true }
        }
    }

    /// Step 1 (b): declare user activity (as a key press would); the engines running now that still run
    /// `endCheckDelay` later are terminated (a new session started meanwhile is never touched). With none left, the
    /// screen saver counts as stopped even without a `didstop` (security: a stuck `didstart`). A press while it's
    /// already ending changes nothing. Returns the check's task (tests await it).
    @discardableResult
    func end() -> Task<Void, Never>? {
        guard endTask == nil else { return endTask }
        let engines = system.runningEnginePIDs()
        let stopsAtStart = stopCount
        system.declareUserActivity()
        let task = Task { [weak self] in
            guard let self else { return }
            if endCheckDelay > .zero { try? await Task.sleep(for: endCheckDelay) }
            endTask = nil
            let running = Set(system.runningEnginePIDs())
            let left = engines.filter(running.contains)
            if !left.isEmpty {
                left.forEach(system.terminate)
                Self.logger.info("Ended the screen saver (terminate)")
            } else if engines.isEmpty {
                Self.logger.info("Ended the screen saver (none was running)")
            } else {
                Self.logger.info("Ended the screen saver (user activity)")
            }
            // Stopped, unless another engine (a new session) runs, or a stop (`didstop`) was reported meanwhile.
            let others = running.subtracting(left)
            if isRunning || !left.isEmpty, others.isEmpty, stopCount == stopsAtStart { stopped() }
        }
        endTask = task
        return task
    }

    /// `com.apple.screensaver.didstart`.
    func didStart() {
        isRunning = true
    }

    /// `com.apple.screensaver.didstop` (reported even without a `didstart` before it).
    func didStop() {
        stopped()
    }

    /// MMTVL is active again: a later stop isn't one MMTVL must come back from.
    func appDidBecomeActive() {
        startedByMMTVL = false
    }

    private func stopped() {
        let wasOurs = startedByMMTVL
        stopCount += 1
        isRunning = false
        startedByMMTVL = false
        onStop(wasOurs)
    }

    // MARK: System

    nonisolated private static func runningEngines() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter(isEngine)
    }

    /// The engine at the fixed path, still running.
    nonisolated private static func isEngine(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, app.bundleIdentifier == bundleID, let url = app.bundleURL else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
            == engineURL.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
