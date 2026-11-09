import AppKit
import os

/// An app MMTVL may hand the screen back to: its pid and bundle id (both must still match).
nonisolated struct FrontApp: Equatable, Sendable {
    var pid: pid_t
    var bundleID: String?
}

/// Exit to Desktop (M7c), as the power menu needs it: `KioskWindowController`.
protocol DesktopExitControl: AnyObject {
    var isExitedToDesktop: Bool { get }
    /// Hides MMTVL again, out of the way (`exitToDesktop()`).
    func exitToDesktop()
    /// Ends it while MMTVL is in front: the kiosk lock comes back, as after Home.
    func endExitToDesktop()
}

extension KioskWindowController: DesktopExitControl {}

/// M7h D45, L15: Power and Power Menu from any app (the Siri Remote, a key bound with Work in Other Apps).
/// Power Menu brings MMTVL forward (D35) and remembers the app that was in front; Cancel or Back on the menu hands the
/// screen back to it (user decision U1, 2026-11-06). The kiosk guard's allowed apps aren't touched: it isn't Home.
/// A menu opened while MMTVL was in front just closes. Security (re-review medium): only an app the kiosk guard
/// allows gets the screen back while the lock is in force (`mayReturn`); otherwise Cancel stays in MMTVL. The system
/// calls are injected so tests use fakes.
/// After Exit to Desktop (the menu doesn't end it, so Cancel can go back to a desktop app), MMTVL is never left in
/// front with the exit still on (re-review medium): Home ends the exit; any other close that doesn't hand the screen
/// back hides MMTVL again, except when Relaunch or Restart asks for the PIN, which ends the exit (MMTVL is in use).
final class PowerMenuPresenter {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Power")

    /// The app the menu opened over; nil when MMTVL was in front.
    private(set) var previousApp: FrontApp?

    private let router: AppRouter
    private let isLauncherActive: () -> Bool
    /// The frontmost app other than MMTVL.
    private let frontApp: () -> FrontApp?
    private let bringForward: () -> Void
    private let returnToApp: (FrontApp) -> Void
    /// Asked at Cancel: `mayReturn(to:isLockInForce:kioskGuard:)` in the app.
    private let mayReturn: (FrontApp) -> Bool
    private weak var desktopExit: (any DesktopExitControl)?

    init(router: AppRouter,
         isLauncherActive: @escaping () -> Bool,
         frontApp: @escaping () -> FrontApp?,
         bringForward: @escaping () -> Void,
         returnToApp: @escaping (FrontApp) -> Void,
         mayReturn: @escaping (FrontApp) -> Bool,
         desktopExit: (any DesktopExitControl)?) {
        self.router = router
        self.isLauncherActive = isLauncherActive
        self.frontApp = frontApp
        self.bringForward = bringForward
        self.returnToApp = returnToApp
        self.mayReturn = mayReturn
        self.desktopExit = desktopExit
        router.onPowerMenuClose = { [weak self] reason in self?.menuClosed(reason) }
    }

    /// `.power` and `.powerMenu`; anything else is ignored.
    func handle(_ command: RemoteCommand) {
        switch command {
        case .power:
            router.pressPower()
        case .powerMenu:
            guard router.powerMenu == nil else { return }
            let active = isLauncherActive()
            previousApp = active ? nil : frontApp()
            router.openPowerMenu()
            if !active { bringForward() }
        default:
            break
        }
    }

    /// `InputRouter.onGlobalCommand` (a key with Work in Other Apps, another app in front): Power and Power Menu
    /// are handled here; false for any other command.
    func handleGlobal(_ command: RemoteCommand) -> Bool {
        guard command == .power || command == .powerMenu else { return false }
        handle(command)
        return true
    }

    /// Every close forgets the app; only a cancel goes back to it.
    private func menuClosed(_ reason: PowerMenuCloseReason) {
        let app = previousApp
        previousApp = nil
        let exited = desktopExit?.isExitedToDesktop == true
        switch reason {
        case .cancelled:
            if let app {
                if mayReturn(app) {
                    Self.logger.notice("Power menu cancelled; back to \(app.bundleID ?? "the app", privacy: .public)")
                    returnToApp(app)
                } else {
                    Self.logger.notice("Power menu cancelled; \(app.bundleID ?? "?", privacy: .public) isn't allowed, staying in MMTVL")
                }
            }
            if exited { hideAgain() }
        case .home:
            if exited { desktopExit?.endExitToDesktop() }
        case .other:
            guard exited else { return }
            if case .pin = router.screen {
                Self.logger.notice("Power menu: the PIN screen ends Exit to Desktop")
                desktopExit?.endExitToDesktop()
            } else {
                hideAgain()
            }
        }
    }

    private func hideAgain() {
        Self.logger.notice("Power menu closed after Exit to Desktop; MMTVL hides again")
        desktopExit?.exitToDesktop()
    }

    /// The kiosk guard's rule (as M1's `pointerGate`): with the lock not in force, any app; else only one the guard
    /// allows (the tile's app and a web app's browser until Home, Reflector). Pure apart from reading the guard.
    static func mayReturn(to app: FrontApp, isLockInForce: Bool, kioskGuard: KioskGuard) -> Bool {
        !isLockInForce || kioskGuard.allows(bundleID: app.bundleID, isSelf: false)
    }

    /// Security low: the pid must still be the same app, with a bundle id (a reused pid of a bundle-less process
    /// never matches). Pure.
    nonisolated static func isSameApp(_ frontApp: FrontApp, runningBundleID: String?, isTerminated: Bool) -> Bool {
        guard !isTerminated, let bundleID = frontApp.bundleID else { return false }
        return runningBundleID == bundleID
    }

    // MARK: The real calls

    static func systemFrontApp() -> FrontApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return FrontApp(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
    }

    /// Unhides (Foregrounder's last rung may have hidden it) and activates the app, if it's still the same one.
    static func systemReturn(to frontApp: FrontApp) {
        guard let app = NSRunningApplication(processIdentifier: frontApp.pid),
              isSameApp(frontApp, runningBundleID: app.bundleIdentifier, isTerminated: app.isTerminated)
        else {
            logger.notice("Power menu: the app it opened over is gone")
            return
        }
        app.unhide()
        NSApp.yieldActivation(to: app)
        app.activate()
    }
}
