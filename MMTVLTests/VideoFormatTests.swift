import Foundation
import Testing
@testable import MMTVL

struct VideoFormatTests {
    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        var width: String
        var height: String
        var fps: String?
        var interlaced: String?
        var label: String
        var testDescription: String { label }
    }

    nonisolated static let cases: [Case] = [
        Case(width: "720", height: "480", fps: "29.97", interlaced: "yes", label: "480i \u{00B7} 29.97 fps"),
        Case(width: "720", height: "576", fps: "25", interlaced: "no", label: "576p \u{00B7} 25 fps"),
        Case(width: "1280", height: "720", fps: "59.94", interlaced: "no", label: "720p \u{00B7} 59.94 fps"),
        Case(width: "1920", height: "1080", fps: "29.97", interlaced: "yes", label: "1080i \u{00B7} 29.97 fps"),
        Case(width: "1920", height: "1080", fps: "60", interlaced: "no", label: "1080p \u{00B7} 60 fps"),
        Case(width: "2560", height: "1440", fps: nil, interlaced: "no", label: "1440p"),
        Case(width: "3840", height: "2160", fps: "23.976", interlaced: "no", label: "4K \u{00B7} 23.98 fps"),
        Case(width: "4096", height: "2160", fps: nil, interlaced: "no", label: "4K"),
        Case(width: "1920", height: "1080", fps: "29.97", interlaced: nil, label: "1080 \u{00B7} 29.97 fps"),
        Case(width: "640", height: "360", fps: nil, interlaced: "no", label: "360p"),
    ]

    @Test(arguments: cases)
    func labels(_ test: Case) throws {
        let format = try #require(VideoFormat.parse(width: test.width, height: test.height,
                                                    fps: test.fps, interlaced: test.interlaced))
        #expect(format.label == test.label)
    }

    @Test func badSizesGiveNil() {
        #expect(VideoFormat.parse(width: nil, height: "1080", fps: "30", interlaced: "no") == nil)
        #expect(VideoFormat.parse(width: "1920", height: nil, fps: "30", interlaced: "no") == nil)
        #expect(VideoFormat.parse(width: "0", height: "1080", fps: "30", interlaced: "no") == nil)
        #expect(VideoFormat.parse(width: "1920", height: "0", fps: "30", interlaced: "no") == nil)
        #expect(VideoFormat.parse(width: "wide", height: "tall", fps: "30", interlaced: "no") == nil)
    }

    @Test func zeroFpsHasNoFpsLabel() throws {
        let format = try #require(VideoFormat.parse(width: "1280", height: "720", fps: "0", interlaced: "no"))
        #expect(format.fps == nil)
        #expect(format.fpsLabel == nil)
        #expect(format.label == "720p")
    }

    @Test func unknownInterlacedValueIsNil() throws {
        let format = try #require(VideoFormat.parse(width: "1280", height: "720", fps: nil, interlaced: "maybe"))
        #expect(format.interlaced == nil)
        #expect(format.label == "720")
    }
}
