import AppKit
import ImageIO
import Observation
import SwiftUI
import os

/// What a tile shows (M7 L3, L4).
enum TileArt: Equatable {
    /// A custom picture from the `tile-art` folder.
    case picture(NSImage, backdrop: PictureBackdrop)
    /// Built-in destinations, `.url` tiles and apps without an icon.
    case gradient(top: Color, bottom: Color, symbol: String)
    /// Apps: the icon on a blurred backdrop of itself.
    case icon(NSImage)
    /// M7 L24: apps' designed art: a brand (or icon-derived) gradient with the app icon, else a symbol.
    case designed(top: Color, bottom: Color, accent: Color?, icon: NSImage?, symbol: String)
    /// M7c L33: the app icon's glyph on its own background, which fills the tile (tvOS's flat brand tiles).
    /// `top`/`bottom`: the icon's background just inside its shape's top and bottom edges.
    case glyph(top: Color, bottom: Color, icon: NSImage)
}

/// M7c L33: what is behind a custom picture.
enum PictureBackdrop: Equatable {
    /// A photo: shown whole over a blurred copy of itself (step 16).
    case blurred
    /// A logo (transparent or plain edges): inset by `Theme.tileLogoInset` on this color.
    case solid(Color)
}

/// Custom tile pictures: `<tile id>.png|.jpg|.jpeg|.heic` in `~/Library/Application Support/MMTVL/tile-art/` (L3).
@Observable
final class TileArtStore {
    static var defaultDirectory: URL {
        LaunchItemStore.defaultDirectory.appending(path: "tile-art", directoryHint: .isDirectory)
    }

    nonisolated static let extensions = ["png", "jpg", "jpeg", "heic"]

    let directory: URL
    /// Loaded pictures by file name, as art.
    private var pictures: [String: TileArt] = [:]
    /// The last listing: file name → modification date.
    @ObservationIgnored private var scanned: [String: Date]?
    /// L24: colors derived from icons, by bundle id (nil = the icon had no usable color).
    @ObservationIgnored private var paletteCache: [String: ArtStyle?] = [:]
    /// L33: glyph art's background and sharp icon, by bundle id (nil = the icon has no plain background).
    @ObservationIgnored private var glyphCache: [String: (background: ArtStyle, icon: NSImage)?] = [:]
    @ObservationIgnored private var previews: [URL: NSImage?] = [:]
    @ObservationIgnored private var previewArts: [URL: TileArt?] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "TileArt")

    init(directory: URL = TileArtStore.defaultDirectory) {
        self.directory = directory
        reloadIfChanged()
    }

    /// The custom picture's file name for the Settings row, e.g. "plex.png"; nil when none.
    func customFileName(for itemID: String) -> String? {
        Self.fileName(for: itemID, in: Array(pictures.keys))
    }

    /// L3/L24: the custom picture, else the tile's art style. `bundleID` is the app's (the default browser's for that tile).
    func art(for item: LaunchItem, icon: NSImage?, bundleID: String? = nil) -> TileArt {
        if let name = customFileName(for: item.id), let picture = pictures[name] {
            return picture
        }
        return styledArt(for: item, icon: icon, bundleID: bundleID, style: item.tileArtStyle)
    }

    /// The art of `style`, ignoring any custom picture (Settings → Tile Art previews).
    func styledArt(for item: LaunchItem, icon: NSImage?, bundleID: String?, style: TileArtStyle) -> TileArt {
        switch item.kind {
        case .internalDestination(.youtube):
            return .gradient(top: Theme.youtubeArtTop, bottom: Theme.youtubeArtBottom,
                             symbol: item.iconSymbol ?? "play.rectangle.fill")
        case .internalDestination(.iptv):
            return .gradient(top: Theme.liveTVArtTop, bottom: Theme.liveTVArtBottom, symbol: item.iconSymbol ?? "tv")
        case .internalDestination(.settings):
            return .gradient(top: Theme.settingsArtTop, bottom: Theme.settingsArtBottom,
                             symbol: item.iconSymbol ?? "gearshape.fill")
        case .system(.exitToDesktop):
            return .gradient(top: Theme.neutralArtTop, bottom: Theme.neutralArtBottom,
                             symbol: item.iconSymbol ?? "rectangle.portrait.and.arrow.right")
        case .application, .defaultBrowser, .url:
            if style == .icon, let icon { return .icon(icon) }
            // L33: the icon's glyph on its own background when it has a plain one, else L24's designed art.
            if let icon, let glyph = glyph(of: icon, key: bundleID ?? item.id) {
                return .glyph(top: glyph.background.top.color, bottom: glyph.background.bottom.color, icon: glyph.icon)
            }
            let symbol = item.iconSymbol ?? "globe"
            guard let artStyle = bundleID.flatMap(AppArtCatalog.style(forBundleID:)) ?? palette(icon, key: bundleID ?? item.id)
            else {
                return icon.map { .designed(top: Theme.neutralArtTop, bottom: Theme.neutralArtBottom, accent: nil, icon: $0,
                                            symbol: symbol) }
                    ?? .gradient(top: Theme.neutralArtTop, bottom: Theme.neutralArtBottom, symbol: symbol)
            }
            return .designed(top: artStyle.top.color, bottom: artStyle.bottom.color, accent: artStyle.accent?.color,
                             icon: icon, symbol: symbol)
        }
    }

    /// L24: an unknown app's colors from its icon, cached.
    private func palette(_ icon: NSImage?, key: String) -> ArtStyle? {
        if let cached = paletteCache[key] { return cached }
        guard let icon else { return nil }
        let side = IconPalette.sampleSize
        let style = Self.sample(icon, side: side).flatMap { IconPalette.style(fromRGBA: $0, width: side, height: side) }
        paletteCache[key] = style
        return style
    }

    /// L33: the icon's plain background and the icon rasterized at `Theme.glyphArtIconPixels` (SwiftUI draws
    /// NSWorkspace's multi-size icons from a small representation, which looks soft at glyph art's size); cached.
    private func glyph(of icon: NSImage, key: String) -> (background: ArtStyle, icon: NSImage)? {
        if let cached = glyphCache[key] { return cached }
        let pixels = Theme.glyphArtIconPixels
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        let side = IconBackground.sampleSize
        let glyph = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil).flatMap { image in
            Self.sample(image, width: side, height: side)
                .flatMap { IconBackground.style(fromRGBA: $0, width: side, height: side) }
                .map { (background: $0, icon: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))) }
        }
        glyphCache[key] = glyph
        return glyph
    }

    /// The icon drawn into a small square RGBA buffer, top row first.
    private static func sample(_ icon: NSImage, side: Int) -> [UInt8]? {
        guard let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return sample(cgImage, width: side, height: side)
    }

    /// An image drawn into a `width` × `height` RGBA buffer, top row first.
    private static func sample(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// L33: a picture as tile art: a logo (transparent or plain edges) gets a solid backdrop and padding,
    /// anything else the blurred fill.
    static func pictureArt(_ image: NSImage) -> TileArt {
        let side = PictureEdges.sampleSize
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rgba = sample(cgImage, width: side, height: side)
        else { return .picture(image, backdrop: .blurred) }
        switch PictureEdges.classify(rgba: rgba, width: side, height: side) {
        case .transparent(let lightContent):
            return .picture(image, backdrop: .solid(lightContent ? Theme.tileLogoDarkBackdrop : Theme.tileLogoLightBackdrop))
        case .solid(let color):
            return .picture(image, backdrop: .solid(color.color))
        case .busy:
            return .picture(image, backdrop: .blurred)
        }
    }

    /// L3: one directory listing; reloads only added or changed pictures. Creates the folder if missing.
    func reloadIfChanged() {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Can't create the tile-art folder: \(error.localizedDescription, privacy: .public)")
        }
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles])) ?? []
        var listing: [String: Date] = [:]
        for url in urls where Self.extensions.contains(url.pathExtension.lowercased()) {
            listing[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
        }
        guard listing != scanned else { return }
        let previous = scanned ?? [:]
        scanned = listing

        var updated = pictures.filter { listing[$0.key] != nil }
        for (name, date) in listing where previous[name] != date || updated[name] == nil {
            if let image = Self.loadPicture(directory.appending(path: name), maxPixels: Theme.tileArtMaxPixels) {
                updated[name] = Self.pictureArt(image)
            } else {
                updated[name] = nil
                logger.error("Can't read tile picture \(name, privacy: .public)")
            }
        }
        pictures = updated
    }

    /// L25: copies `source` to `<id>.<ext>` after removing the tile's other pictures, then reloads.
    func setPicture(from source: URL, for itemID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removePictureFiles(for: itemID)
        let destination = directory.appending(path: "\(itemID).\(source.pathExtension.lowercased())")
        try FileManager.default.copyItem(at: source, to: destination)
        logger.info("Tile art for \(itemID, privacy: .public) set from a picture")
        // L33: the copy keeps the source's modification date, which may match the replaced file's; read it regardless.
        scanned?[destination.lastPathComponent] = nil
        reloadIfChanged()
    }

    /// L25: deletes every picture of the tile, then reloads.
    func removePicture(for itemID: String) {
        removePictureFiles(for: itemID)
        reloadIfChanged()
    }

    /// L33: lists URLs, not `directory.path()`, which is percent-encoded ("Application%20Support") and listed nothing.
    private func removePictureFiles(for itemID: String) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls {
            guard Self.extensions.contains(url.pathExtension.lowercased()),
                  url.deletingPathExtension().lastPathComponent.lowercased() == itemID.lowercased()
            else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Can't remove tile picture \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// L25: a downsampled preview of any picture file (Settings rows and side column), cached by URL.
    func preview(of url: URL) -> NSImage? {
        if let cached = previews[url] { return cached }
        let image = Self.loadPicture(url, maxPixels: Theme.tileArtPreviewPixels)
        previews[url] = image
        return image
    }

    /// L33: the preview as tile art (Settings' side column), cached by URL.
    func previewArt(of url: URL) -> TileArt? {
        if let cached = previewArts[url] { return cached }
        let art = preview(of: url).map(Self.pictureArt)
        previewArts[url] = art
        return art
    }

    /// Pure, for tests: the file chosen for an id among names in the folder. Case-insensitive; png, jpg, jpeg, heic in that order.
    nonisolated static func fileName(for itemID: String, in names: [String]) -> String? {
        for ext in extensions {
            let wanted = "\(itemID).\(ext)".lowercased()
            if let name = names.first(where: { $0.lowercased() == wanted }) { return name }
        }
        return nil
    }

    /// Downsampled to at most `Theme.tileArtMaxPixels` on the long side.
    private static func loadPicture(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
}

extension ArtColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}
