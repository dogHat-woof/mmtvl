import AppKit
import Carbon.HIToolbox
import os

/// Android screen mirroring through Reflector 4 (D32): keeps Reflector running hidden (L18), detects mirroring
/// sessions from its windows (L19) and ends them (L21). Never logs window titles.
final class ReflectorMonitor {
    /// Confirmed in step 7 (`mdls -name kMDItemCFBundleIdentifier "/Applications/Reflector 4.app"`).
    nonisolated static let bundleID = "com.squirrels.Reflector-4"
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Reflector")
    private static let pollInterval: TimeInterval = 1
    private static let restartDelay: Duration = .seconds(5)
    /// L20: full screen is retried at most this often.
    private static let fullScreenInterval: TimeInterval = 3
    /// L21: the ⌘W fallback's spacing.
    private static let closeKeyInterval: TimeInterval = 0.15

    /// settings.reflectorAutoStart; turning it on starts Reflector now (off doesn't quit it).
    var autoStart: Bool {
        didSet {
            if autoStart && !oldValue { launchIfWanted() }
        }
    }
    private(set) var isMirroring = false
    var isInstalled: Bool { applicationURL != nil }
    var isRunning: Bool { runningApplication != nil }
    /// AppDelegate: L20 takeover.
    var onSessionBegan: (() -> Void)?
    /// AppDelegate: L22 return.
    var onSessionEnded: (() -> Void)?
    /// Settings refresh.
    var onStatusChange: (() -> Void)?

    private var detector = MirroringDetector()
    private var limiter = RestartLimiter()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let fullScreener = WindowFullScreener()
    private var lastFullScreenAttempt: Date?
    private var fullScreenTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?

    init(autoStart: Bool) {
        self.autoStart = autoStart
    }

    private var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID)
    }

    private var runningApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first { !$0.isTerminated }
    }

    /// Observes Reflector's launch/terminate, starts it if wanted, and polls while it runs.
    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                            queue: .main) { [weak self] notification in
            let isReflector = Self.isReflector(notification)
            MainActor.assumeIsolated {
                if isReflector { self?.reflectorLaunched() }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] notification in
            let isReflector = Self.isReflector(notification)
            MainActor.assumeIsolated {
                if isReflector { self?.reflectorTerminated() }
            }
        })
        if isRunning {
            startPolling()
        } else {
            launchIfWanted()
        }
    }

    /// L18: after wake (AppDelegate already waited 2 s), restarts are allowed again.
    func systemDidWake() {
        limiter.reset()
        launchIfWanted()
    }

    /// L21: closes every session window (AX close button, else ⌘W). Returns at once; the poll reports the end.
    func endMirroring() {
        guard isMirroring, let app = runningApplication else { return }
        let pid = app.processIdentifier
        let pressed = fullScreener.closeWindows(pid: pid, minimumSize: MirroringDetector.minimumSize(for: Self.mainScreen))
        Self.logger.info("Ending mirroring (\(pressed) window(s) closed)")
        guard pressed == 0 else { return }
        app.activate()
        for index in detector.sessionWindows.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeKeyInterval * Double(index + 1)) {
                // Sent to Reflector itself, so it can't reach MMTVL once Home brings MMTVL forward.
                SyntheticInput.postKey(CGKeyCode(kVK_ANSI_W), flags: .maskCommand, toPid: pid)
            }
        }
    }

    // MARK: Running Reflector (L18)

    private nonisolated static func isReflector(_ notification: Notification) -> Bool {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == bundleID
    }

    private func launchIfWanted() {
        guard autoStart, !isRunning, let url = applicationURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Self.logger.error("Couldn't start Reflector: \(error.localizedDescription, privacy: .public)")
            }
        }
        Self.logger.info("Started Reflector in the background")
    }

    private func reflectorLaunched() {
        restartTask?.cancel()
        restartTask = nil
        startPolling()
        onStatusChange?()
    }

    private func reflectorTerminated() {
        stopPolling()
        if detector.isActive {
            detector = MirroringDetector()
            sessionEnded()
        }
        onStatusChange?()
        guard autoStart, isInstalled else { return }
        guard limiter.allowRestart(at: Date()) else {
            Self.logger.error("Reflector keeps quitting; not restarting")
            return
        }
        Self.logger.info("Reflector quit; restarting")
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: Self.restartDelay)
            guard !Task.isCancelled else { return }
            self?.launchIfWanted()
        }
    }

    // MARK: Sessions (L19, L20)

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        fullScreenTask?.cancel()
        fullScreenTask = nil
    }

    /// The main screen in CGWindowList coordinates (top-left origin at the main screen's corner).
    private static var mainScreen: CGRect {
        CGRect(origin: .zero, size: NSScreen.screens.first?.frame.size ?? .zero)
    }

    private func poll() {
        guard let app = runningApplication else { return }
        let pid = app.processIdentifier
        let windows = WindowSnapshot.onScreen(pid: pid)
        let screen = Self.mainScreen
        switch detector.update(windows: windows, screen: screen) {
        case .began:
            isMirroring = true
            Self.logger.info("Mirroring session began")
            onSessionBegan?()
            onStatusChange?()
        case .ended:
            sessionEnded()
            onStatusChange?()
        case .none:
            if detector.needsFullScreen(screen: screen) { makeFullScreen(pid: pid) }
        }
    }

    /// L22: after a session ends, MMTVL shows its home screen unless the user switched to another app on purpose, or
    /// (M7h QA Q1) the power menu is open: opening it brought MMTVL forward over the mirrored window. Pure.
    nonisolated static func showsHomeAfterSession(frontBundleID: String?, frontIsSelf: Bool, hasFrontApp: Bool,
                                                  isPowerMenuOpen: Bool) -> Bool {
        guard !isPowerMenuOpen else { return false }
        return !hasFrontApp || frontBundleID == bundleID || frontIsSelf
    }

    private func sessionEnded() {
        isMirroring = false
        lastFullScreenAttempt = nil
        Self.logger.info("Mirroring session ended")
        onSessionEnded?()
    }

    /// L20: AXFullScreen, at most once every 3 s.
    private func makeFullScreen(pid: pid_t) {
        let now = Date()
        if let last = lastFullScreenAttempt, now.timeIntervalSince(last) < Self.fullScreenInterval { return }
        guard fullScreenTask == nil else { return }
        lastFullScreenAttempt = now
        fullScreenTask = Task { [weak self, fullScreener] in
            await fullScreener.makeFullScreen(pid: pid, timeout: .seconds(Self.fullScreenInterval))
            self?.fullScreenTask = nil
        }
    }
}
