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
