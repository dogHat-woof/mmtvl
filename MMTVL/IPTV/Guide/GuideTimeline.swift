import CoreGraphics
import Foundation

/// The guide's 2-hour time window and its geometry (L12).
nonisolated struct GuideTimeline: Equatable, Sendable {
    static let windowDuration: TimeInterval = 2 * 3600
    static let horizon: TimeInterval = 24 * 3600
    private static let halfHour: TimeInterval = 30 * 60

    /// Always on a :00/:30 boundary.
    var windowStart: Date
    var windowEnd: Date { windowStart + Self.windowDuration }

    static func halfHourFloor(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / halfHour).rounded(.down) * halfHour)
    }

    /// windowStart = halfHourFloor(now).
    init(now: Date) {
        windowStart = Self.halfHourFloor(now)
    }

    /// If `focusStart` (≥ now) isn't in [windowStart, windowStart + 1.5 h), windowStart = halfHourFloor(focusStart),
    /// never earlier than halfHourFloor(now).
    mutating func reveal(_ focusStart: Date, now: Date) {
        let visibleEnd = windowStart + Self.windowDuration - Self.halfHour
        guard focusStart < windowStart || focusStart >= visibleEnd else { return }
        windowStart = max(Self.halfHourFloor(focusStart), Self.halfHourFloor(now))
    }

    /// Horizontal span of [start, stop) clipped to the window, in points for `width`; nil if outside.
    func span(start: Date, stop: Date, width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        let clippedStart = max(start, windowStart)
        let clippedStop = min(stop, windowEnd)
        guard clippedStop > clippedStart else { return nil }
        let scale = width / Self.windowDuration
        return (CGFloat(clippedStart.timeIntervalSince(windowStart)) * scale,
                CGFloat(clippedStop.timeIntervalSince(clippedStart)) * scale)
    }

    /// Labels every 30 min across the window: [(x, Date)].
    func ticks(width: CGFloat) -> [(x: CGFloat, date: Date)] {
        let count = Int(Self.windowDuration / Self.halfHour)
        return (0..<count).map { index in
            (width * CGFloat(index) / CGFloat(count), windowStart + Double(index) * Self.halfHour)
        }
    }
}
