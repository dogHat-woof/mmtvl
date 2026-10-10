import AppKit
import Foundation
import Testing
@testable import MMTVL

struct TileArtTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "mmtvl-tile-art-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func writePNG(to url: URL, width: Int = 50, height: Int = 30) throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    @Test func fileChoicePriorityAndCase() {
        #expect(TileArtStore.fileName(for: "plex", in: ["plex.jpg", "plex.png", "other.png"]) == "plex.png")
        #expect(TileArtStore.fileName(for: "plex", in: ["Plex.JPEG", "plex.heic"]) == "Plex.JPEG")
        #expect(TileArtStore.fileName(for: "plex", in: ["plex.heic"]) == "plex.heic")
        #expect(TileArtStore.fileName(for: "plex", in: ["plex.gif", "plexx.png"]) == nil)
        #expect(TileArtStore.fileName(for: "app.com.brave.Browser", in: ["app.com.brave.browser.png"])
            == "app.com.brave.browser.png")
    }

    @Test func theFolderIsCreated() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = TileArtStore(directory: folder)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func reloadPicksUpAddedAndRemovedPictures() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TileArtStore(directory: folder)
        let plex = LaunchItem.defaults[0]
        #expect(store.customFileName(for: "plex") == nil)

        try writePNG(to: folder.appending(path: "plex.png"))
        #expect(store.customFileName(for: "plex") == nil)   // not before a reload
        store.reloadIfChanged()
        #expect(store.customFileName(for: "plex") == "plex.png")
        guard case .picture(let image, _) = store.art(for: plex, icon: nil) else {
            Issue.record("No picture art")
            return
        }
        #expect(image.size == CGSize(width: 50, height: 30))

        try FileManager.default.removeItem(at: folder.appending(path: "plex.png"))
        store.reloadIfChanged()
        #expect(store.customFileName(for: "plex") == nil)
        if case .picture = store.art(for: plex, icon: nil) { Issue.record("Still a picture") }
    }

    @Test func largePicturesAreDownsampled() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writePNG(to: folder.appending(path: "youtube.png"), width: 3000, height: 1800)
        let store = TileArtStore(directory: folder)
        guard case .picture(let image, _) = store.art(for: LaunchItem.defaults[1], icon: nil) else {
            Issue.record("No picture art")
            return
        }
        #expect(image.size == CGSize(width: 1500, height: 900))
    }

    @Test func builtInTilesGetGradients() {
        let store = makeTestTileArt()
        let byID = Dictionary(uniqueKeysWithValues: LaunchItem.defaults.map { ($0.id, $0) })
        #expect(store.art(for: byID["youtube"]!, icon: nil)
            == .gradient(top: Theme.youtubeArtTop, bottom: Theme.youtubeArtBottom, symbol: "play.rectangle.fill"))
        #expect(store.art(for: byID["iptv"]!, icon: nil)
            == .gradient(top: Theme.liveTVArtTop, bottom: Theme.liveTVArtBottom, symbol: "tv"))
        #expect(store.art(for: byID["settings"]!, icon: nil)
            == .gradient(top: Theme.settingsArtTop, bottom: Theme.settingsArtBottom, symbol: "gearshape.fill"))
        #expect(store.art(for: byID["exit"]!, icon: nil)
            == .gradient(top: Theme.neutralArtTop, bottom: Theme.neutralArtBottom, symbol: "rectangle.portrait.and.arrow.right"))
    }

    /// A 64-point icon: `color` in the middle, transparent around it (an icon that doesn't fill its shape).
    private func icon(_ color: NSColor) -> NSImage {
        NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
            color.setFill()
            rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3).fill()
            return true
        }
    }

    /// A 64-point icon on a plain background, `background` at the top and `bottomColor` at the bottom, with a glyph.
    private func plainIcon(_ background: NSColor, bottom bottomColor: NSColor? = nil) -> NSImage {
        NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
            (bottomColor ?? background).setFill()
            rect.fill()
            background.setFill()
            NSRect(x: 0, y: rect.midY, width: rect.width, height: rect.height / 2).fill()
            NSColor.white.setFill()
            rect.insetBy(dx: rect.width * 0.35, dy: rect.height * 0.35).fill()
            return true
        }
    }

    @Test func knownAppsGetTheirDesignedArt() {
        let store = makeTestTileArt()
        let plexIcon = icon(.orange)
        let plex = LaunchItem.defaults[0]
        guard case .designed(_, _, let accent, let artIcon, _) = store.art(for: plex, icon: plexIcon, bundleID: "tv.plex.htpc") else {
            Issue.record("No designed art")
            return
        }
        #expect(accent != nil)
        #expect(artIcon === plexIcon)
        // The icon style asks for the blurred-icon look.
        let iconStyle = [plex].settingArtStyle(.icon, id: "plex")[0]
        #expect(store.art(for: iconStyle, icon: plexIcon, bundleID: "tv.plex.htpc") == .icon(plexIcon))
    }

    @Test func unknownAppsTakeColorsFromTheirIcon() {
        let store = makeTestTileArt()
        let app = LaunchItem(id: "app.x", title: "X", kind: .application(bundleID: "com.example.x"))
        guard case .designed(let top, let bottom, nil, _, _) = store.art(for: app, icon: icon(.systemBlue), bundleID: "com.example.x")
        else {
            Issue.record("No designed art")
            return
        }
        #expect(top != bottom)
        #expect(top != Theme.neutralArtTop)
    }

    @Test func appsWithoutAnIconAreNeutral() {
        let store = makeTestTileArt()
        let app = LaunchItem(id: "app.x", title: "X", kind: .application(bundleID: "com.example.x"))
        #expect(store.art(for: app, icon: nil, bundleID: "com.example.x")
            == .gradient(top: Theme.neutralArtTop, bottom: Theme.neutralArtBottom, symbol: "globe"))
        let web = LaunchItem(id: "web", title: "Web", kind: .url(URL(string: "https://example.com")!, browserBundleID: nil))
        #expect(store.art(for: web, icon: nil)
            == .gradient(top: Theme.neutralArtTop, bottom: Theme.neutralArtBottom, symbol: "globe"))
        // A known app that isn't installed keeps its colors, with a symbol.
        guard case .designed(_, _, _, nil, "globe") = store.art(for: LaunchItem.defaults[0], icon: nil, bundleID: "tv.plex.htpc") else {
            Issue.record("No designed art")
            return
        }
    }

    // MARK: Glyph art and logo pictures (M7c L33)

    @Test func plainIconsGetGlyphArtOnTheirBackground() {
        let store = makeTestTileArt()
        let app = LaunchItem(id: "app.x", title: "X", kind: .application(bundleID: "com.example.x"))
        let appIcon = plainIcon(NSColor(srgbRed: 0.2, green: 0.8, blue: 0.3, alpha: 1),
                                bottom: NSColor(srgbRed: 0.05, green: 0.3, blue: 0.1, alpha: 1))
        guard case .glyph(let top, let bottom, let artIcon) = store.art(for: app, icon: appIcon, bundleID: "com.example.x")
        else {
            Issue.record("No glyph art")
            return
        }
        #expect(artIcon.size == CGSize(width: Theme.glyphArtIconPixels, height: Theme.glyphArtIconPixels))
        #expect(top != bottom)
        // Known apps too: their own background beats the catalog's colors.
        guard case .glyph = store.art(for: LaunchItem.defaults[0], icon: plainIcon(.black), bundleID: "tv.plex.htpc") else {
            Issue.record("No glyph art for Plex")
            return
        }
        // The App Icon style is unchanged.
        let iconStyle = [app].settingArtStyle(.icon, id: "app.x")[0]
        #expect(store.art(for: iconStyle, icon: appIcon, bundleID: "com.example.x") == .icon(appIcon))
    }

    /// 8-bit RGBA, top row first, filled by `color(x, y)`.
    private func buffer(width: Int, height: Int, _ color: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        var rgba: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let (red, green, blue, alpha) = color(x, y)
                rgba += [red, green, blue, alpha]
            }
        }
        return rgba
    }

    @Test func iconBackgroundNeedsPlainOpaqueBands() throws {
        let side = 64
        let graded = buffer(width: side, height: side) { _, y in (0, UInt8(255 - y * 3), 0, 255) }
        let style = try #require(IconBackground.style(fromRGBA: graded, width: side, height: side))
        #expect(style.top.green > style.bottom.green)
        // A glyph crossing the top band.
        let crossed = buffer(width: side, height: side) { x, _ in x < 32 ? (255, 255, 255, 255) : (0, 0, 0, 255) }
        #expect(IconBackground.style(fromRGBA: crossed, width: side, height: side) == nil)
        // An icon that doesn't fill its shape.
        let small = buffer(width: side, height: side) { x, y in
            (16..<48).contains(x) && (16..<48).contains(y) ? (255, 0, 0, 255) : (0, 0, 0, 0)
        }
        #expect(IconBackground.style(fromRGBA: small, width: side, height: side) == nil)
    }

    @Test func pictureEdgesTellLogosFromPhotos() {
        let side = 64
        let inside = { (x: Int, y: Int) in (16..<48).contains(x) && (16..<48).contains(y) }
        let lightLogo = buffer(width: side, height: side) { x, y in inside(x, y) ? (240, 240, 240, 255) : (0, 0, 0, 0) }
        #expect(PictureEdges.classify(rgba: lightLogo, width: side, height: side) == .transparent(lightContent: true))
        let darkLogo = buffer(width: side, height: side) { x, y in inside(x, y) ? (20, 20, 20, 255) : (0, 0, 0, 0) }
        #expect(PictureEdges.classify(rgba: darkLogo, width: side, height: side) == .transparent(lightContent: false))
        let onWhite = buffer(width: side, height: side) { x, y in inside(x, y) ? (255, 0, 0, 255) : (255, 255, 255, 255) }
        #expect(PictureEdges.classify(rgba: onWhite, width: side, height: side) == .solid(ArtColor(red: 1, green: 1, blue: 1)))
        let photo = buffer(width: side, height: side) { x, y in (UInt8(x * 4), UInt8(y * 4), 128, 255) }
        #expect(PictureEdges.classify(rgba: photo, width: side, height: side) == .busy)
    }

    @Test func logoPicturesGetASolidBackdrop() {
        let lightLogo = NSImage(size: CGSize(width: 90, height: 20), flipped: false) { rect in
            NSColor.white.setFill()
            rect.insetBy(dx: 10, dy: 5).fill()
            return true
        }
        #expect(TileArtStore.pictureArt(lightLogo) == .picture(lightLogo, backdrop: .solid(Theme.tileLogoDarkBackdrop)))
        let photo = NSImage(size: CGSize(width: 50, height: 30), flipped: false) { rect in
            NSGradient(starting: .red, ending: .blue)?.draw(in: rect, angle: 30)
            return true
        }
        #expect(TileArtStore.pictureArt(photo) == .picture(photo, backdrop: .blurred))
    }

    @Test func artStyleIsStoredOnlyWhenNotTheDefault() throws {
        let items = LaunchItem.defaults.settingArtStyle(.icon, id: "plex")
        #expect(items[0].artStyle == "icon")
        #expect(items.settingArtStyle(.designed, id: "plex")[0].artStyle == nil)
        let odd = try JSONDecoder().decode(LaunchItem.self, from: Data(#"{"id":"a","title":"A","kind":{"application":{"bundleID":"x"}},"artStyle":"sparkly"}"#.utf8))
        #expect(odd.tileArtStyle == .designed)
    }

    @Test func settingsTilePageShowsTheArtRow() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.homeScreen))
        model.perform(.push(.tile(id: "plex")))
        #expect(model.row(id: "tile.art")?.title == "Tile Art")
        #expect(model.row(id: "tile.art")?.value == "Designed")
        #expect(model.row(id: "tile.art")?.action == .push(.tileArt(id: "plex")))
        recorder.tileArtNames["plex"] = "plex.png"
        model.press(.back)
        model.perform(.push(.tile(id: "plex")))
        #expect(model.row(id: "tile.art")?.value == "plex.png")
    }

    // MARK: Choosing pictures (L25)

    @Test func setAndRemoveAPicture() throws {
        let folder = temporaryFolder()
        let source = temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: source)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let store = TileArtStore(directory: folder)
        try writePNG(to: folder.appending(path: "plex.jpg"))
        try writePNG(to: folder.appending(path: "Plex.HEIC"))
        try writePNG(to: folder.appending(path: "youtube.png"))
        let picked = source.appending(path: "Poster.PNG")
        try writePNG(to: picked)

        try store.setPicture(from: picked, for: "plex")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path()).sorted()
        #expect(names == ["plex.png", "youtube.png"])
        #expect(store.customFileName(for: "plex") == "plex.png")
        #expect(FileManager.default.fileExists(atPath: picked.path()))

        store.removePicture(for: "plex")
        #expect(store.customFileName(for: "plex") == nil)
        #expect(store.customFileName(for: "youtube") == "youtube.png")
    }

    /// M7c L33: the real folder is under "Application Support"; removing listed nothing in a path with a space.
    @Test func removeWorksInAFolderWithASpace() throws {
        let parent = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appending(path: "Application Support/tile-art", directoryHint: .isDirectory)
        let store = TileArtStore(directory: folder)
        try writePNG(to: folder.appending(path: "facetime.png"))
        store.reloadIfChanged()
        #expect(store.customFileName(for: "facetime") == "facetime.png")

        store.removePicture(for: "facetime")
        #expect(store.customFileName(for: "facetime") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty)
    }

    /// M7c L33: a replacement with the same name and modification date is still read.
    @Test func replacingAPictureShowsTheNewOne() throws {
        let folder = temporaryFolder()
        let source = temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: source)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let store = TileArtStore(directory: folder)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let first = source.appending(path: "a.png"), second = source.appending(path: "b.png")
        try writePNG(to: first, width: 50, height: 30)
        try writePNG(to: second, width: 40, height: 40)
        for url in [first, second] {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
        }

        try store.setPicture(from: first, for: "plex")
        try store.setPicture(from: second, for: "plex")
        guard case .picture(let image, _) = store.art(for: LaunchItem.defaults[0], icon: nil) else {
            Issue.record("No picture art")
            return
        }
        #expect(image.size == CGSize(width: 40, height: 40))
    }

    @Test func previewsAreSmall() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "big.png")
        try writePNG(to: url, width: 2000, height: 1000)
        let store = makeTestTileArt()
        #expect(store.preview(of: url)?.size == CGSize(width: 600, height: 300))
        #expect(store.preview(of: folder.appending(path: "missing.png")) == nil)
    }
}
