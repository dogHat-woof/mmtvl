import Foundation
import Testing
@testable import MMTVL

struct TimeshiftTests {
    /// The spike's sample (see the plan's Research).
    static let sample = """
    {"cache-end":92.053667,"reader-pts":21.397334,"cache-duration":70.656333,"eof":false,"underrun":false,"idle":false,
     "total-bytes":28251520,"fw-bytes":23299120,"raw-input-rate":248030,"bof-cached":true,"eof-cached":false,
     "seekable-ranges":[{"start":0.000000,"end":91.437667}], "ts-per-stream":[]}
    """

    @Test func parsesSpikeSample() throws {
        let timeshift = try #require(Timeshift.parse(cacheStateJSON: Self.sample, timePos: 18.1))
        #expect(timeshift.cacheEnd == 92.053667)
        #expect(timeshift.rangeStart == 0)
        #expect(abs(timeshift.behindLive - 58.95) < 0.01)
        #expect(timeshift.isLive == false)
        #expect(timeshift.label == "\u{2212}0:59")
        #expect(abs(timeshift.buffered - 92.05) < 0.01)
    }

    @Test func nearCacheEndIsLive() throws {
        let timeshift = try #require(Timeshift.parse(cacheStateJSON: Self.sample, timePos: 78))
        #expect(timeshift.isLive)
        #expect(timeshift.label == "LIVE")
    }

    @Test func seekTargetsAreClamped() throws {
        let timeshift = try #require(Timeshift.parse(cacheStateJSON: Self.sample, timePos: 50))
        #expect(timeshift.target(seekingBy: -1000) == 1)
        #expect(abs(timeshift.target(seekingBy: 1000) - 82.053667) < 0.0001)
        #expect(timeshift.target(seekingBy: -10) == 40)
        #expect(timeshift.livePosition == timeshift.cacheEnd - 10)
    }

    @Test func emptyClampRangeUsesLivePosition() {
        let timeshift = Timeshift(position: 5, rangeStart: 0, cacheEnd: 8)
        #expect(timeshift.target(seekingBy: -10) == timeshift.livePosition)
    }

    @Test func missingRangesIsNil() {
        #expect(Timeshift.parse(cacheStateJSON: #"{"cache-end":10}"#, timePos: 1) == nil)
        #expect(Timeshift.parse(cacheStateJSON: #"{"cache-end":10,"seekable-ranges":[]}"#, timePos: 1) == nil)
        #expect(Timeshift.parse(cacheStateJSON: #"{"seekable-ranges":[{"start":0,"end":5}]}"#, timePos: 1) == nil)
        #expect(Timeshift.parse(cacheStateJSON: "not json", timePos: 1) == nil)
    }

    @Test func picksTheRangeContainingThePosition() throws {
        let json = #"{"cache-end":300,"seekable-ranges":[{"start":0,"end":100},{"start":150,"end":299}]}"#
        #expect(try #require(Timeshift.parse(cacheStateJSON: json, timePos: 200)).rangeStart == 150)
        #expect(try #require(Timeshift.parse(cacheStateJSON: json, timePos: 50)).rangeStart == 0)
        // Outside every range → the smallest start.
        #expect(try #require(Timeshift.parse(cacheStateJSON: json, timePos: 120)).rangeStart == 0)
    }

    @Test func longLabels() {
        let timeshift = Timeshift(position: 0, rangeStart: 0, cacheEnd: 3725 + Timeshift.liveSlack)
        #expect(timeshift.label == "\u{2212}1:02:05")
    }
}

struct LiveEdgeSmootherTests {
    /// HLS-like: cache-end jumps by a 4 s segment every 4 s, playback advances smoothly 14 s behind the last jump.
    private func cacheEnd(at t: Double) -> Double { 100 + (t / 4).rounded(.down) * 4 }

    @Test func behindLiveIsSteadyWhilePlaying() {
        var smoother = LiveEdgeSmoother()
        var labels = Set<String>()
        var t = 0.0
        while t < 40 {
            let position = 100 + t - 14 - 300          // 5 minutes behind
            let edge = smoother.liveEdge(cacheEnd: cacheEnd(at: t), position: position, now: t, steady: true)
            if t >= 4 {                                 // after the first full segment
                labels.insert(Timeshift(position: position, rangeStart: 0, cacheEnd: cacheEnd(at: t), liveEdge: edge).label)
            }
            t += 0.5
        }
        #expect(labels.count == 1)
        // The raw sawtooth would have shown several values.
        let raw = Set(stride(from: 4.0, to: 40, by: 0.5).map { t in
            Timeshift(position: 100 + t - 14 - 300, rangeStart: 0, cacheEnd: cacheEnd(at: t)).label
        })
        #expect(raw.count > 1)
    }

    @Test func naturalLagReadsAsLive() {
        var smoother = LiveEdgeSmoother()
        var t = 0.0
        var allLive = true
        while t < 40 {
            let position = 100 + t - 14
            let edge = smoother.liveEdge(cacheEnd: cacheEnd(at: t), position: position, now: t, steady: true)
            if t >= 4 {
                allLive = allLive && Timeshift(position: position, rangeStart: 0, cacheEnd: cacheEnd(at: t), liveEdge: edge).isLive
            }
            t += 0.5
        }
        #expect(allLive)
    }

    @Test func pausedLagGrowsEverySecond() {
        var smoother = LiveEdgeSmoother()
        let position = 50.0
        var behind: [Int] = []
        for t in stride(from: 0.0, through: 20, by: 1) {
            let edge = smoother.liveEdge(cacheEnd: cacheEnd(at: t), position: position, now: t, steady: false)
            behind.append(Int(Timeshift(position: position, rangeStart: 0, cacheEnd: cacheEnd(at: t), liveEdge: edge).behindLive.rounded()))
        }
        #expect(behind.suffix(12) == Array(behind.suffix(12).first!...(behind.suffix(12).first! + 11)))
    }

    @Test func seekingMovesTheReportedLag() {
        var smoother = LiveEdgeSmoother()
        _ = smoother.liveEdge(cacheEnd: 104, position: 90, now: 4, steady: true)
        let edge = smoother.liveEdge(cacheEnd: 104, position: 80, now: 4.5, steady: true)
        #expect(abs(edge - 104.5) < 0.001)
    }

    @Test func seekTargetsStillUseTheRawCacheEnd() {
        let timeshift = Timeshift(position: 50, rangeStart: 0, cacheEnd: 100, liveEdge: 103)
        #expect(timeshift.livePosition == 90)
        #expect(timeshift.target(seekingBy: 1000) == 90)
    }
}
