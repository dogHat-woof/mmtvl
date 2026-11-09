import AppKit
import SwiftUI
import os

/// Owns the launcher window (D1): a borderless window covering the menu-bar screen,
/// with the Dock and menu bar hidden while the launcher is active.
final class KioskWindowController {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "KioskWindowController")
    private static let kioskOptions: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar]
    /// M7c L7 (D36): only while MMTVL is active. `.disableProcessSwitching`/`.disableForceQuit` need `.hideDock`.
    private static let lockedOptions: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit, .disableHideApplication,
    ]

    let window: NSWindow
    private let windowed: Bool
    /// Settings can change this live.
    var hidesCursor: Bool
    private var screenObserver: NSObjectProtocol?
    /// D35: every show checks that MMTVL really came forward.
    private let foregrounder: Foregrounder
    /// L6: whether the kiosk lock applies, set by AppDelegate (`kioskLock`, global input running). Exit to Desktop
    /// turns it off until the next show.
    var lockOptions = false {
        didSet { if lockOptions != oldValue && NSApp.isActive { applyPresentationOptions() } }
    }
    /// Set by Exit to Desktop, cleared by `show` (not the power menu's).
    private(set) var isExitedToDesktop = false

    init(rootView: some View, windowed: Bool = AppEnvironment.windowedMode, hidesCursor: Bool = false) {
        self.windowed = windowed
        self.hidesCursor = hidesCursor
        foregrounder = Foregrounder(windowed: windowed)
        if windowed {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MMTVL"
            window.center()
        } else {
            window = KioskWindow(
                contentRect: Self.kioskFrame(),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .normal
            window.collectionBehavior = [.fullScreenNone]
        }
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView
        window.initialFirstResponder = hostingView

        if !windowed {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refit() }
            }
        }
    }

    /// The menu-bar screen's full frame (not `visibleFrame`), so the window covers the Dock and menu-bar strip.
    private static func kioskFrame() -> NSRect {
        (NSScreen.screens.first ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func refit() {
        let frame = Self.kioskFrame()
        Self.logger.info("Screen parameters changed; refitting to \(frame.debugDescription, privacy: .public)")
        window.setFrame(frame, display: true)
    }

    /// M7h step 12: the power menu's show. It isn't a Home, so it doesn't end Exit to Desktop.
    nonisolated static let powerMenuReason = "powerMenu"

    /// Whether a show with `reason` ends Exit to Desktop (re-arms the kiosk lock): every show but the power menu's
    /// (QA minor: Home, wake, a cast… still do). Pure.
    nonisolated static func endsExitToDesktop(reason: String) -> Bool {
        reason != powerMenuReason
    }

    /// `reason` names the caller in the `Foreground` log (L2): home, wake, appQuit, mirroringEnded, cast, guard, …
    func show(reason: String) {
        if !windowed {
            refit()
        }
        if Self.endsExitToDesktop(reason: reason) { isExitedToDesktop = false }
        // After Exit to Desktop the app is hidden; global Home must bring it back.
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        if hidesCursor {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        Task {
            // Item 20 (build 11): the presentation options follow from `appDidBecomeActive`, once the screen settled.
            await foregrounder.bringForward(reason: reason)
            await ensureOnScreen(reason: reason)
        }
    }

    // MARK: Presentation options and a stuck Space (item 20)

    /// How long MMTVL must have been active before it hides the Dock and locks again. macOS activates MMTVL by
    /// itself when a full-screen app in front quits, and would apply stored options during the Space's exit
    /// animation, which may be what leaves the Dock stuck on the dead Space.
    static let presentationSettleDelay: Duration = .seconds(1)
    /// How long after a show the window must be on screen; a full-screen exit animation takes about 0.7 s.
    static let spaceSettleDelay: Duration = .milliseconds(500)
    private var presentationTask: Task<Void, Never>?

    /// Clears the options while MMTVL is in the background, so macOS has none to apply when it activates MMTVL.
    func appDidResignActive() {
        presentationTask?.cancel()
        presentationTask = nil
        guard !windowed else { return }
        NSApp.presentationOptions = []
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        Self.logger.notice("In the background (front: \(front, privacy: .public)); presentation options cleared")
    }

    func appDidBecomeActive() {
        guard !windowed else { return }
        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.presentationSettleDelay)
            guard !Task.isCancelled, let self, NSApp.isActive else { return }
            applyPresentationOptions()
            Self.logger.notice("Active and settled; presentation options set")
        }
    }


    /// MMTVL can be frontmost while the Dock still shows a full-screen Space another app left behind (Plex HTPC
    /// after Exit), with the window on the desktop Space behind it. Restarting the Dock is the only cure found.
    private func ensureOnScreen(reason: String) async {
        guard !windowed else { return }
        try? await Task.sleep(for: Self.spaceSettleDelay)
        guard window.isVisible, !isExitedToDesktop, NSApp.isActive else { return }
        let onActiveSpace = window.isOnActiveSpace
        let visible = window.occlusionState.contains(.visible)
        Self.logger.notice("\(reason, privacy: .public): window on the active Space \(onActiveSpace), visible \(visible)")
        guard !onActiveSpace || !visible else { return }
        await restartDock(reason: reason)
    }

    /// The Dock owns Spaces; restarting it (launchd relaunches it at once) clears a dead full-screen Space, as
    /// `killall Dock` did on the mini. At most once a minute.
    static let dockRestartInterval: TimeInterval = 60
    static let dockRelaunchTimeout: Duration = .seconds(5)
    private var lastDockRestart: Date?

    private func restartDock(reason: String) async {
        if let lastDockRestart, Date().timeIntervalSince(lastDockRestart) < Self.dockRestartInterval { return }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        lastDockRestart = Date()
        Self.logger.error("\(reason, privacy: .public): the window is off screen; restarting the Dock")
        let start = ContinuousClock.now
        let oldPID = dock.processIdentifier
        kill(oldPID, SIGTERM)
        // launchd relaunches the Dock; it forgets the options, so they're set again as soon as it's up, and once more
        // a moment later in case it wasn't listening yet.
        let deadline = start + Self.dockRelaunchTimeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            let relaunched = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                .contains { $0.processIdentifier != oldPID }
            if relaunched { break }
        }
        window.makeKeyAndOrderFront(nil)
        _ = await foregrounder.bringForward(reason: "\(reason)-dock")
        applyPresentationOptions(force: true)
        try? await Task.sleep(for: .seconds(1))
        if NSApp.isActive { applyPresentationOptions(force: true) }
        let onScreen = window.isOnActiveSpace && window.occlusionState.contains(.visible)
        Self.logger.notice("\(reason, privacy: .public): after the Dock restart, on screen \(onScreen), \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
    }

    /// L3: brings MMTVL forward without reordering the window (it's already on screen).
    func bringForward(reason: String) async -> Bool {
        await foregrounder.bringForward(reason: reason)
    }

    /// M7h re-review medium: Home while MMTVL is in front after Exit to Desktop (⌘Tab, or the power menu over a
    /// desktop app) ends the exit, so the lock and presentation options come back.
    func endExitToDesktop() {
        guard isExitedToDesktop else { return }
        show(reason: "home")
        if NSApp.isActive { applyPresentationOptions() }
    }

    func exitToDesktop() {
        isExitedToDesktop = true
        presentationTask?.cancel()
        if !windowed {
            NSApp.presentationOptions = []
        }
        window.orderOut(nil)
        NSApp.hide(nil)
    }

    /// Set after the window is shown; `.hideMenuBar` must always be paired with `.hideDock`.
    /// Item 20: `force` after the Dock restarted and forgot them.
    func applyPresentationOptions(force: Bool = false) {
        guard !windowed else { return }
        if force { NSApp.presentationOptions = [] }
        NSApp.presentationOptions = lockOptions && !isExitedToDesktop ? Self.lockedOptions : Self.kioskOptions
    }
}
