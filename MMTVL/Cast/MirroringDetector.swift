import CoreGraphics
import Foundation

/// One on-screen window from `CGWindowListCopyWindowInfo` (no Screen Recording needed for these fields).
nonisolated struct WindowSnapshot: Equatable, Sendable {
    var pid: pid_t
    var layer: Int
    var alpha: Double
    /// CGWindowList coordinates (top-left origin).
    var bounds: CGRect

    /// The on-screen windows of `pid`, all layers (M7f L1; moved out of `ReflectorMonitor.poll()`).
    static func onScreen(pid: pid_t) -> [WindowSnapshot] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { info -> WindowSnapshot? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { return nil }
            return WindowSnapshot(pid: pid,
                                  layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                  alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                                  bounds: bounds)
        }
    }
}

/// Turns Reflector's windows into mirroring sessions (D32, L19). Pure; one `update` per poll.
nonisolated struct MirroringDetector {
    /// L19: a session window is at least this fraction of the main screen's width and height (confirmed in step 7).
    static let minimumFraction: CGFloat = 0.25
    static let endAfterMissedPolls = 2
    /// L20: a window within this many points of every screen edge counts as full screen.
    static let fullScreenTolerance: CGFloat = 2

    enum Event: Equatable, Sendable { case none, began, ended }

    private(set) var isActive = false
    /// The session windows last seen (kept through a missed poll).
    private(set) var sessionWindows: [WindowSnapshot] = []
    private var missedPolls = 0

    /// The smallest size a session window has on `screen`.
    static func minimumSize(for screen: CGRect) -> CGSize {
        CGSize(width: screen.width * minimumFraction, height: screen.height * minimumFraction)
    }

    /// One poll: Reflector's windows (already filtered by pid) and the main screen's frame.
    mutating func update(windows: [WindowSnapshot], screen: CGRect) -> Event {
        let minimum = Self.minimumSize(for: screen)
        let session = windows.filter {
            $0.alpha > 0 && $0.bounds.width >= minimum.width && $0.bounds.height >= minimum.height
        }
        if !session.isEmpty {
            sessionWindows = session
            missedPolls = 0
            guard !isActive else { return .none }
            isActive = true
            return .began
        }
        guard isActive else { return .none }
        missedPolls += 1
        guard missedPolls >= Self.endAfterMissedPolls else { return .none }
        isActive = false
        sessionWindows = []
        missedPolls = 0
        return .ended
    }

    /// L20: true while active and no session window covers `screen` (within 2 points on each edge).
    func needsFullScreen(screen: CGRect) -> Bool {
        guard isActive else { return false }
        let tolerance = Self.fullScreenTolerance
        return !sessionWindows.contains { window in
            window.bounds.minX <= screen.minX + tolerance
                && window.bounds.minY <= screen.minY + tolerance
                && window.bounds.maxX >= screen.maxX - tolerance
                && window.bounds.maxY >= screen.maxY - tolerance
        }
    }
}

/// L18: at most 3 restarts of Reflector in 10 minutes.
nonisolated struct RestartLimiter {
    static let maxRestarts = 3
    static let period: TimeInterval = 600

    private var restarts: [Date] = []

    /// Records and allows a restart, or refuses a 4th within 10 minutes.
    mutating func allowRestart(at date: Date) -> Bool {
        restarts.removeAll { date.timeIntervalSince($0) >= Self.period }
        guard restarts.count < Self.maxRestarts else { return false }
        restarts.append(date)
        return true
    }

    mutating func reset() {
        restarts = []
    }
}
