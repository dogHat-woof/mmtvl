import Foundation

/// An sRGB color, 0…1 per channel. Pure, so the catalog and palette are testable off the main actor.
nonisolated struct ArtColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 0xRRGGBB.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// The same hue and saturation at `brightness` (HSB).
    func withBrightness(_ brightness: Double) -> ArtColor {
        let maximum = max(red, green, blue)
        guard maximum > 0 else { return ArtColor(red: brightness, green: brightness, blue: brightness) }
        let scale = brightness / maximum
        return ArtColor(red: min(red * scale, 1), green: min(green * scale, 1), blue: min(blue * scale, 1))
    }
}

/// A designed tile's look (M7 L24): a diagonal two-color gradient, an optional glow behind the icon.
nonisolated struct ArtStyle: Equatable, Sendable {
    var top: ArtColor
    var bottom: ArtColor
    var accent: ArtColor?

    init(top: ArtColor, bottom: ArtColor, accent: ArtColor? = nil) {
        self.top = top
        self.bottom = bottom
        self.accent = accent
    }

    init(_ top: UInt32, _ bottom: UInt32, accent: UInt32? = nil) {
        self.init(top: ArtColor(hex: top), bottom: ArtColor(hex: bottom), accent: accent.map(ArtColor.init(hex:)))
    }
}

/// Brand styles for known apps (M7 L24). The art is drawn by MMTVL from these and the app's own icon; no logo files.
nonisolated enum AppArtCatalog {
    /// Keys: bundle ids, or `webapp:<CrAppModeShortcutID>` for a Chromium web app in any browser.
    static let styles: [String: ArtStyle] = [
        "tv.plex.htpc": ArtStyle(0x2D2A26, 0x0B0A09, accent: 0xE5A00D),
        "com.amazon.aiv.AIVApp": ArtStyle(0x00A8E1, 0x0F171E),
        "com.brave.Browser": ArtStyle(0xFB542B, 0x2B0F0A),
        "com.apple.Safari": ArtStyle(0x1E90FF, 0x0A2A5C),
        "com.google.Chrome": ArtStyle(0x4285F4, 0x0D2B6B),
        "com.apple.FaceTime": ArtStyle(0x34C759, 0x0B4D22),
        "webapp:cinhimbnkkaeohfgghhklpknlkffjgod": ArtStyle(0xFF0033, 0x1A0006),   // YouTube Music
        "webapp:ncmjhecbjeaamljdfahankockkkdmedg": ArtStyle(0x4285F4, 0x0F9D58),   // Google Photos
        "webapp:kjgfgldnnfoeklkmfkjfagphfepbbdan": ArtStyle(0x00897B, 0x0B3D35),   // Google Meet
    ]

    /// Exact bundle id first; a Chromium web app shim (`<browser>.app.<app id>`) by its app id.
    static func style(forBundleID bundleID: String) -> ArtStyle? {
        if let style = styles[bundleID] { return style }
        guard let range = bundleID.range(of: ".app.", options: .backwards) else { return nil }
        let appID = bundleID[range.upperBound...]
        guard !appID.isEmpty else { return nil }
        return styles["webapp:\(appID)"]
    }
}

/// Colors for apps the catalog doesn't know, from their icon (M7 L24).
nonisolated enum IconPalette {
    /// Side of the square the icon is sampled at.
    static let sampleSize = 32

    /// The average of opaque pixels that are neither near-white nor near-black; nil when there are none.
    /// `rgba`: 8-bit RGBA rows, premultiplied or not (only opaque pixels count).
    static func averageColor(fromRGBA rgba: [UInt8], width: Int, height: Int) -> ArtColor? {
        var sum = (red: 0.0, green: 0.0, blue: 0.0)
        var count = 0
        for pixel in 0..<(width * height) where pixel * 4 + 3 < rgba.count {
            let offset = pixel * 4
            let (red, green, blue, alpha) = (rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3])
            guard alpha > 200 else { continue }
            if red > 235 && green > 235 && blue > 235 { continue }
            if red < 20 && green < 20 && blue < 20 { continue }
            sum.red += Double(red)
            sum.green += Double(green)
            sum.blue += Double(blue)
            count += 1
        }
        guard count > 0 else { return nil }
        return ArtColor(red: sum.red / Double(count) / 255, green: sum.green / Double(count) / 255,
                        blue: sum.blue / Double(count) / 255)
    }

    /// L24: top at 0.9 brightness, bottom at 0.25.
    static func style(fromRGBA rgba: [UInt8], width: Int, height: Int) -> ArtStyle? {
        guard let color = averageColor(fromRGBA: rgba, width: width, height: height) else { return nil }
        return ArtStyle(top: color.withBrightness(0.9), bottom: color.withBrightness(0.25))
    }
}

/// M7c L33: the background an app icon's glyph sits on, so the tile can continue it (tvOS's flat brand tiles).
nonisolated enum IconBackground {
    /// Side of the square the icon is sampled at.
    static let sampleSize = 64
    /// Where the bands are sampled, as fractions of the icon's height: just inside the icon shape's top and bottom
    /// edges (macOS 26 icons fill about 10…90 %), clear of the rim and of most glyphs.
    static let topBand: ClosedRange<Double> = 0.125...0.155
    static let bottomBand: ClosedRange<Double> = 0.845...0.875
    /// The bands' horizontal extent.
    static let bandWidth: ClosedRange<Double> = 0.3...0.7
    /// Largest mean distance of a band's pixels from its average (0…1 per channel) that still counts as one color.
    static let maxSpread = 0.05

    /// The icon's background at the top and bottom bands; nil when a band isn't opaque or isn't one color
    /// (an icon that doesn't fill its shape, or a glyph or picture reaching the edge). `rgba`: 8-bit RGBA rows, top first.
    static func style(fromRGBA rgba: [UInt8], width: Int, height: Int) -> ArtStyle? {
        guard let top = bandColor(rgba, width: width, height: height, rows: topBand),
              let bottom = bandColor(rgba, width: width, height: height, rows: bottomBand)
        else { return nil }
        return ArtStyle(top: top, bottom: bottom)
    }

    private static func bandColor(_ rgba: [UInt8], width: Int, height: Int, rows: ClosedRange<Double>) -> ArtColor? {
        let pixels = PixelSampler.pixels(rgba, width: width, height: height, rows: rows, columns: bandWidth)
        guard !pixels.isEmpty, pixels.allSatisfy({ $0.alpha > 0.94 }) else { return nil }
        return PixelSampler.uniformColor(pixels, maxSpread: maxSpread)
    }
}

/// M7c L33: what surrounds a custom picture, to decide whether it's a logo (padded) or a photo (fills).
nonisolated enum PictureEdges: Equatable, Sendable {
    /// Mostly transparent edges (at least `clearFraction` of the ring; a logo may touch the edges): a cut-out logo. `lightContent`: its visible pixels are mostly light (it needs a dark tile).
    case transparent(lightContent: Bool)
    /// One opaque color all around: a logo on a plain background.
    case solid(ArtColor)
    /// Anything else (a photo or poster): shown as before.
    case busy

    static let sampleSize = 64
    /// The ring that is checked, as a fraction of each side.
    static let ringFraction = 0.04
    static let maxSpread = 0.06
    static let clearFraction = 0.3

    /// `rgba`: 8-bit RGBA rows, top first, premultiplied or not (only opaque pixels' colors are compared).
    static func classify(rgba: [UInt8], width: Int, height: Int) -> PictureEdges {
        let ringX = max(1, Int((Double(width) * ringFraction).rounded()))
        let ringY = max(1, Int((Double(height) * ringFraction).rounded()))
        var ring: [PixelSampler.Pixel] = []
        var inside: [PixelSampler.Pixel] = []
        for y in 0..<height {
            for x in 0..<width {
                let pixel = PixelSampler.pixel(rgba, width: width, x: x, y: y)
                if x < ringX || x >= width - ringX || y < ringY || y >= height - ringY {
                    ring.append(pixel)
                } else {
                    inside.append(pixel)
                }
            }
        }
        guard !ring.isEmpty else { return .busy }
        let clear = ring.filter { $0.alpha < 0.12 }.count
        if Double(clear) >= Double(ring.count) * clearFraction {
            let visible = inside.filter { $0.alpha > 0.5 }
            guard !visible.isEmpty else { return .transparent(lightContent: true) }
            let luminance = visible.reduce(0.0) { $0 + $1.luminance } / Double(visible.count)
            return .transparent(lightContent: luminance > 0.5)
        }
        guard ring.allSatisfy({ $0.alpha > 0.94 }), let color = PixelSampler.uniformColor(ring, maxSpread: maxSpread)
        else { return .busy }
        return .solid(color)
    }
}

/// Reading 8-bit RGBA buffers (M7c L33).
nonisolated enum PixelSampler {
    struct Pixel {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        /// Un-premultiplied color (premultiplied buffers), Rec. 709 luminance.
        var luminance: Double {
            let scale = alpha > 0 ? 1 / alpha : 0
            return min(1, (0.2126 * red + 0.7152 * green + 0.0722 * blue) * scale)
        }
    }

    static func pixel(_ rgba: [UInt8], width: Int, x: Int, y: Int) -> Pixel {
        let offset = (y * width + x) * 4
        guard offset + 3 < rgba.count else { return Pixel(red: 0, green: 0, blue: 0, alpha: 0) }
        return Pixel(red: Double(rgba[offset]) / 255, green: Double(rgba[offset + 1]) / 255,
                     blue: Double(rgba[offset + 2]) / 255, alpha: Double(rgba[offset + 3]) / 255)
    }

    /// The pixels in a band given as fractions of the height (`rows`) and width (`columns`).
    static func pixels(_ rgba: [UInt8], width: Int, height: Int, rows: ClosedRange<Double>,
                       columns: ClosedRange<Double>) -> [Pixel] {
        let firstRow = Int(Double(height) * rows.lowerBound), lastRow = max(firstRow, Int(Double(height) * rows.upperBound) - 1)
        let firstColumn = Int(Double(width) * columns.lowerBound)
        let lastColumn = max(firstColumn, Int(Double(width) * columns.upperBound) - 1)
        guard firstRow >= 0, lastRow < height, firstColumn >= 0, lastColumn < width else { return [] }
        var result: [Pixel] = []
        for y in firstRow...lastRow {
            for x in firstColumn...lastColumn { result.append(pixel(rgba, width: width, x: x, y: y)) }
        }
        return result
    }

    /// The average color when the pixels are one color (mean distance from the average at most `maxSpread`), else nil.
    static func uniformColor(_ pixels: [Pixel], maxSpread: Double) -> ArtColor? {
        guard !pixels.isEmpty else { return nil }
        let count = Double(pixels.count)
        let mean = ArtColor(red: pixels.reduce(0) { $0 + $1.red } / count, green: pixels.reduce(0) { $0 + $1.green } / count,
                            blue: pixels.reduce(0) { $0 + $1.blue } / count)
        let spread = pixels.reduce(0.0) {
            $0 + max(abs($1.red - mean.red), abs($1.green - mean.green), abs($1.blue - mean.blue))
        } / count
        return spread <= maxSpread ? mean : nil
    }
}
