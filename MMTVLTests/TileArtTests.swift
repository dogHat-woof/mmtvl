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
        guard case .picture(let image) = store.art(for: plex, icon: nil) else {
            Issue.record("No picture art")
            return
        }
        #expect(image.size == CGSize(width: 50, height: 30))

        try FileManager.default.removeItem(at: folder.appending(path: "plex.png"))
        store.reloadIfChanged()
        #expect(store.customFileName(for: "plex") == nil)
        #expect(store.art(for: plex, icon: nil) != .picture(image))
    }

    @Test func largePicturesAreDownsampled() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writePNG(to: folder.appending(path: "youtube.png"), width: 3000, height: 1800)
        let store = TileArtStore(directory: folder)
        guard case .picture(let image) = store.art(for: LaunchItem.defaults[1], icon: nil) else {
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

    /// A 16-point icon filled with one color.
    private func icon(_ color: NSColor) -> NSImage {
        NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            rect.fill()
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
