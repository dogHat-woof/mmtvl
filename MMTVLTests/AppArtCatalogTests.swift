import Foundation
import Testing
@testable import MMTVL

/// Designed app art (M7 L24).
struct AppArtCatalogTests {
    @Test func knownAppsByBundleID() {
        #expect(AppArtCatalog.style(forBundleID: "tv.plex.htpc") == ArtStyle(0x2D2A26, 0x0B0A09, accent: 0xE5A00D))
        #expect(AppArtCatalog.style(forBundleID: "com.amazon.aiv.AIVApp")?.top == ArtColor(hex: 0x00A8E1))
        #expect(AppArtCatalog.style(forBundleID: "com.example.unknown") == nil)
    }

    @Test func webAppsMatchInAnyBrowser() {
        let meet = AppArtCatalog.styles["webapp:kjgfgldnnfoeklkmfkjfagphfepbbdan"]
        #expect(AppArtCatalog.style(forBundleID: "com.brave.Browser.app.kjgfgldnnfoeklkmfkjfagphfepbbdan") == meet)
        #expect(AppArtCatalog.style(forBundleID: "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan") == meet)
        #expect(AppArtCatalog.style(forBundleID: "com.brave.Browser.app.unknownapp") == nil)
        #expect(AppArtCatalog.style(forBundleID: "com.brave.Browser.app.") == nil)
    }

    @Test func hexColors() {
        let color = ArtColor(hex: 0xFF8000)
        #expect(color == ArtColor(red: 1, green: 128.0 / 255, blue: 0))
        let dark = color.withBrightness(0.25)
        #expect(abs(dark.red - 0.25) < 0.0001)
        #expect(abs(dark.green - 0.25 * 128 / 255) < 0.0001)
        #expect(ArtColor(hex: 0).withBrightness(0.5) == ArtColor(red: 0.5, green: 0.5, blue: 0.5))
    }

    /// Two red pixels, one white, one black, one transparent blue.
    @Test func paletteIgnoresWhiteBlackAndTransparentPixels() {
        let rgba: [UInt8] = [200, 0, 0, 255, 100, 0, 0, 255, 250, 250, 250, 255, 5, 5, 5, 255, 0, 0, 255, 0, 0, 0, 0, 0]
        let average = IconPalette.averageColor(fromRGBA: rgba, width: 3, height: 2)
        #expect(average == ArtColor(red: 150.0 / 255, green: 0, blue: 0))
        let style = IconPalette.style(fromRGBA: rgba, width: 3, height: 2)
        #expect(style?.top == ArtColor(red: 0.9, green: 0, blue: 0))
        #expect(style?.bottom == ArtColor(red: 0.25, green: 0, blue: 0))
        #expect(IconPalette.averageColor(fromRGBA: [255, 255, 255, 255], width: 1, height: 1) == nil)
    }
}
