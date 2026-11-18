import Foundation

/// M7c L30: the parts of an HLS playlist (RFC 8216) the relay needs: its URIs (lines that aren't tags, and `URI="…"`
/// attributes), rewritten to the relay, and the ones worth fetching early. Pure.
nonisolated enum HLSPlaylist {
    enum Kind: Equatable { case master, media, unknown }

    /// ffmpeg's `live_start_index` default: a live stream starts this many segments from the end.
    static let liveStartOffset = 3

    static func kind(of text: String) -> Kind {
        if text.contains("#EXT-X-STREAM-INF") || text.contains("#EXT-X-MEDIA:") { return .master }
        if text.contains("#EXTINF") { return .media }
        return .unknown
    }

    /// An HLS playlist by its content type or its first line.
    static func isPlaylist(_ data: Data, contentType: String?) -> Bool {
        if let contentType = contentType?.lowercased(), contentType.contains("mpegurl") { return true }
        return data.prefix(7) == Data("#EXTM3U".utf8)
            || data.prefix(10) == Data("\u{FEFF}#EXTM3U".utf8)
    }

    /// `text` with every URI replaced by `map(<the URI resolved against base>)`; other lines unchanged. A line whose
    /// URI isn't http(s) (`file:`, `data:`, …), doesn't parse, or `map` refuses (nil) is left out, so neither the
    /// relay nor mpv fetches it (security review item 5).
    static func rewrite(_ text: String, base: URL, map: (URL) -> String?) -> String {
        lines(of: text).compactMap { line in
            if line.hasPrefix("#") {
                return rewriteAttributes(line, base: base, map: map)
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return line }
            guard let url = resolve(trimmed, base: base) else { return nil }
            return map(url)
        }.joined(separator: "\n")
    }

    /// A master playlist's media playlists: its variants and its renditions (`#EXT-X-MEDIA` URIs).
    static func mediaPlaylists(in text: String, base: URL) -> [URL] {
        guard kind(of: text) == .master else { return [] }
        var urls: [URL] = []
        for line in lines(of: text) {
            if line.hasPrefix("#") {
                if line.hasPrefix("#EXT-X-MEDIA:"), let uri = attributeURI(line), let url = resolve(uri, base: base) {
                    urls.append(url)
                }
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, let url = resolve(trimmed, base: base) { urls.append(url) }
            }
        }
        return unique(urls)
    }

    /// A media playlist's segment where ffmpeg starts playing (`liveStartOffset` from the end of a live playlist, the
    /// first of a finished one), after its `#EXT-X-MAP` initialization section if any.
    static func startSegments(in text: String, base: URL) -> [URL] {
        guard kind(of: text) == .media else { return [] }
        var segments: [URL] = []
        var map: URL?
        for line in lines(of: text) {
            if line.hasPrefix("#EXT-X-MAP:"), map == nil, let uri = attributeURI(line) {
                map = resolve(uri, base: base)
            } else if !line.hasPrefix("#") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, let url = resolve(trimmed, base: base) { segments.append(url) }
            }
        }
        guard !segments.isEmpty else { return map.map { [$0] } ?? [] }
        let isLive = !text.contains("#EXT-X-ENDLIST")
        let start = isLive ? max(segments.count - liveStartOffset, 0) : 0
        return (map.map { [$0] } ?? []) + [segments[start]]
    }

    // MARK: - Private

    /// "\r\n" is one `Character` in Swift, so it's a separator of its own.
    private static func lines(of text: String) -> [String] {
        text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }.map(String.init)
    }

    /// http(s) URLs only (security review item 5): a playlist can't name a `file:` or other local resource.
    private static func resolve(_ uri: String, base: URL) -> URL? {
        guard let url = URL(string: uri, relativeTo: base)?.absoluteURL, RelayURLPolicy.isWebURL(url) else { return nil }
        return url
    }

    /// A computed property: `Regex` isn't Sendable, so it can't be a stored static.
    private static var uriAttribute: Regex<(Substring, Substring)> { /URI="([^"]*)"/ }

    private static func attributeURI(_ line: String) -> String? {
        line.firstMatch(of: uriAttribute).map { String($0.1) }
    }

    /// nil (the tag is left out) when one of its URIs is refused.
    private static func rewriteAttributes(_ line: String, base: URL, map: (URL) -> String?) -> String? {
        var refused = false
        let rewritten = line.replacing(uriAttribute) { match in
            guard let url = resolve(String(match.1), base: base), let mapped = map(url) else {
                refused = true
                return String(match.0)
            }
            return "URI=\"\(mapped)\""
        }
        return refused ? nil : rewritten
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        return urls.filter { seen.insert($0).inserted }
    }
}
