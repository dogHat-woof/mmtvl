import Foundation

/// The playing stream's resolution and frame rate for the Live TV banner (M7f L2), from mpv's properties.
nonisolated struct VideoFormat: Equatable, Sendable {
    var width: Int
    var height: Int
    var fps: Double?
    /// nil when mpv doesn't say (unverified with VideoToolbox).
    var interlaced: Bool?

    /// Raw mpv property strings (`video-params/w`, `video-params/h`, `container-fps` or `estimated-vf-fps`,
    /// `video-frame-info/interlaced`); nil without a positive size.
    static func parse(width: String?, height: String?, fps: String?, interlaced: String?) -> VideoFormat? {
        guard let width = width.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), width > 0,
              let height = height.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), height > 0
        else { return nil }
        let rate = fps.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let flag: Bool? = switch interlaced {
        case "yes": true
        case "no": false
        default: nil
        }
        return VideoFormat(width: width, height: height, fps: rate, interlaced: flag)
    }

    /// "480i", "720p", "1080i", "4K"; no letter when `interlaced` is nil ("1080").
    var resolutionLabel: String {
        if width >= 3200 || height > 1600 { return "4K" }
        let name = switch height {
        case ..<400: "\(height)"
        case 400...500: "480"
        case 501...600: "576"
        case 601...800: "720"
        case 801...1200: "1080"
        default: "1440"
        }
        return switch interlaced {
        case true?: name + "i"
        case false?: name + "p"
        case nil: name
        }
    }

    /// "29.97 fps", "60 fps", "23.98 fps"; nil without a frame rate.
    var fpsLabel: String? {
        guard let fps else { return nil }
        var text = String(format: "%.2f", fps)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + " fps"
    }

    /// "1080i · 29.97 fps", or `resolutionLabel` alone.
    var label: String {
        guard let fpsLabel else { return resolutionLabel }
        return "\(resolutionLabel) \u{00B7} \(fpsLabel)"
    }
}
