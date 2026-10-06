import Foundation
import Testing
@testable import MMTVL

struct GuideTimelineTests {
    static func utc(_ hour: Int, _ minute: Int, day: Int = 5) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func halfHourFloor() {
        #expect(GuideTimeline.halfHourFloor(Self.utc(14, 47)) == Self.utc(14, 30))
        #expect(GuideTimeline.halfHourFloor(Self.utc(14, 30)) == Self.utc(14, 30))
        #expect(GuideTimeline.halfHourFloor(Self.utc(14, 29)) == Self.utc(14, 0))
        #expect(GuideTimeline(now: Self.utc(14, 47)).windowStart == Self.utc(14, 30))
    }

    @Test func spans() throws {
        let timeline = GuideTimeline(now: Self.utc(14, 47))   // 14:30–16:30
        let clipped = try #require(timeline.span(start: Self.utc(14, 0), stop: Self.utc(15, 0), width: 1200))
        #expect(clipped.x == 0)
        #expect(clipped.width == 300)

        let halfHour = try #require(timeline.span(start: Self.utc(15, 0), stop: Self.utc(15, 30), width: 1200))
        #expect(abs(halfHour.x - 300) < 0.001)
        #expect(abs(halfHour.width - 1200 / 4) < 0.001)

        #expect(timeline.span(start: Self.utc(16, 30), stop: Self.utc(17, 0), width: 1200) == nil)
        #expect(timeline.span(start: Self.utc(13, 0), stop: Self.utc(14, 30), width: 1200) == nil)
    }

    @Test func revealMovesForwardAndNeverIntoThePast() {
        let now = Self.utc(14, 47)
        var timeline = GuideTimeline(now: now)
        timeline.reveal(Self.utc(15, 30), now: now)          // inside [14:30, 16:00)
        #expect(timeline.windowStart == Self.utc(14, 30))
        timeline.reveal(Self.utc(16, 0), now: now)           // window + 1.5 h
        #expect(timeline.windowStart == Self.utc(16, 0))
        timeline.reveal(now, now: now)                       // back before the window
        #expect(timeline.windowStart == Self.utc(14, 30))
        timeline.reveal(Self.utc(13, 0), now: now)           // never before halfHourFloor(now)
        #expect(timeline.windowStart == Self.utc(14, 30))
    }

    @Test func ticks() {
        let timeline = GuideTimeline(now: Self.utc(14, 47))
        let ticks = timeline.ticks(width: 1200)
        #expect(ticks.count == 4)
        #expect(ticks.map(\.x) == [0, 300, 600, 900])
        #expect(ticks.map(\.date) == [Self.utc(14, 30), Self.utc(15, 0), Self.utc(15, 30), Self.utc(16, 0)])
    }
}
