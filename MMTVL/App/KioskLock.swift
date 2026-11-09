import Carbon.HIToolbox
import Foundation
import os

/// M7c L8a (D36): shortcuts the event tap consumes while another app is in front and the kiosk lock is on.
/// A static list, not in `key-bindings.json`.
nonisolated enum KioskLock {
    enum Modifiers: Equatable, Sendable {
        /// These must be held; others may be too.
        case including(Set<KeyModifier>)
        /// Exactly these.
        case exactly(Set<KeyModifier>)

        func matches(_ modifiers: Set<KeyModifier>) -> Bool {
            switch self {
            case .including(let required): required.isSubset(of: modifiers)
            case .exactly(let required): modifiers == required
            }
        }
    }

    /// ⌘Tab/⌘⇧Tab, ⌘`, ⌘Space (Spotlight), ⌥⌘Esc (Force Quit), ⌃arrows (Mission Control and Spaces).
    static let blockedShortcuts: [(keyCode: UInt16, modifiers: Modifiers)] = [
        (UInt16(kVK_Tab), .including([.command])),
        (UInt16(kVK_ANSI_Grave), .including([.command])),
        (UInt16(kVK_Space), .exactly([.command])),
        (UInt16(kVK_Escape), .exactly([.command, .option])),
        (UInt16(kVK_LeftArrow), .exactly([.control])),
        (UInt16(kVK_RightArrow), .exactly([.control])),
        (UInt16(kVK_UpArrow), .exactly([.control])),
        (UInt16(kVK_DownArrow), .exactly([.control])),
    ]

    static func blocks(keyCode: UInt16, modifiers: Set<KeyModifier>) -> Bool {
        blockedShortcuts.contains { $0.keyCode == keyCode && $0.modifiers.matches(modifiers) }
    }
}

/// M7c L8b (D36): when a regular app MMTVL didn't open comes forward, MMTVL takes the screen back like Home.
/// Rate-limited, so it can never fight an app forever. Logs bundle ids only.
final class KioskGuard {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "KioskGuard")

    enum Decision: Equatable { case ignore, takeBack }

    static let maxTakebacks = 3
    static let takebackWindow: TimeInterval = 10
    static let systemSettingsBundleID = "com.apple.systempreferences"
    /// Always allowed: Reflector's mirroring sessions (D32).
    static let alwaysAllowed: Set<String> = [ReflectorMonitor.bundleID]

    /// L6, set by AppDelegate.
    var isEnabled = false
    /// The apps MMTVL opened since the last Home (the tile's app, a web app's browser, System Settings).
    private(set) var sessionApps: Set<String> = []
    private var takebacks: [Date] = []
    /// After `maxTakebacks` in `takebackWindow`, the guard stops until the next Home.
    private(set) var isSuspended = false
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Clears the session apps and the rate limit.
    func homePressed() {
        sessionApps = []
        takebacks = []
        isSuspended = false
    }

    func opened(bundleIDs: [String]) {
        sessionApps.formUnion(bundleIDs)
    }

    /// Accessibility onboarding, Settings → Casting → AirPlay, Login Items: allowed until the next Home.
    func openedSystemSettings() {
        sessionApps.insert(Self.systemSettingsBundleID)
    }

    /// The guard's "may this app be in front" rule: MMTVL, Reflector (`alwaysAllowed`) and the session apps
    /// (System Settings only when MMTVL opened it). Whether the guard is on or suspended doesn't change it.
    func allows(bundleID: String?, isSelf: Bool) -> Bool {
        if isSelf { return true }
        guard let bundleID else { return false }
        return Self.alwaysAllowed.contains(bundleID) || sessionApps.contains(bundleID)
    }

    /// Whether the Siri Remote's trackpad pointer may act in the app in front (M7h security M1).
    enum PointerGate: Equatable {
        case allowed
        /// The app in front isn't one the guard allows (bundle id, or "?" without one).
        case blocked(bundleID: String)
    }

    /// M7h security M1: while the kiosk lock is in force, the remote's pointer moves, clicks and scrolls act only
    /// in an app the guard allows, even while the guard is suspended (a suspended guard must not open every app
    /// to the pointer). With the lock not in force, always allowed.
    func pointerGate(isLockInForce: Bool, frontBundleID: String?, isSelf: Bool) -> PointerGate {
        guard isLockInForce, !allows(bundleID: frontBundleID, isSelf: isSelf) else { return .allowed }
        return .blocked(bundleID: frontBundleID ?? "?")
    }

    func appDidActivate(bundleID: String?, isRegular: Bool, isSelf: Bool) -> Decision {
        guard isEnabled, isRegular, !isSelf, !isSuspended else { return .ignore }
        if allows(bundleID: bundleID, isSelf: false) { return .ignore }
        let time = now()
        takebacks.removeAll { time.timeIntervalSince($0) >= Self.takebackWindow }
        guard takebacks.count < Self.maxTakebacks else {
            isSuspended = true
            Self.logger.error("\(bundleID ?? "?", privacy: .public) keeps coming forward; the guard stops until Home")
            return .ignore
        }
        takebacks.append(time)
        Self.logger.notice("\(bundleID ?? "?", privacy: .public) came forward; taking the screen back")
        return .takeBack
    }
}
