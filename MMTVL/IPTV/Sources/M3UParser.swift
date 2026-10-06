import Foundation

/// One `#EXTINF` entry of an M3U playlist.
nonisolated struct M3UEntry: Equatable, Sendable {
    /// After the first comma outside quotes, trimmed; "" if missing.
    var name: String
    /// Keys lowercased, e.g. "tvg-id".
    var attributes: [String: String]
    /// group-title, else the current #EXTGRP, else nil.
    var group: String?
    /// The URL line, trimmed.
    var url: String

    var tvgID: String? { nonEmpty("tvg-id") }
    var tvgName: String? { nonEmpty("tvg-name") }
    var logo: String? { nonEmpty("tvg-logo") }

    private func nonEmpty(_ key: String) -> String? {
        guard let value = attributes[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}

nonisolated struct M3UPlaylist: Equatable, Sendable {
    /// Header url-tvg / x-tvg-url, split on ",", http(s) only.
    var guideURLs: [URL]
    var entries: [M3UEntry]
}

/// Pure M3U / M3U8 playlist parser (plain M3U sources, L1).
nonisolated enum M3UParser {
    enum ParseError: Error, Equatable { case notAPlaylist }

    static func parse(_ text: String) throws -> M3UPlaylist {
        var text = Substring(text)
        if text.first == "\u{FEFF}" { text = text.dropFirst() }

        var sawHeader = false
        var sawEntry = false
        var guideURLs: [URL] = []
        var entries: [M3UEntry] = []
        var currentGroup: String?
        var pending: (name: String, attributes: [String: String])?

        // Split on "\n" by scalars: Swift treats "\r\n" as one Character, so splitting Characters on "\n" would miss CRLF.
        for rawLine in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(String.UnicodeScalarView(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTM3U") {
                sawHeader = true
                let attributes = parseAttributes(line)
                for key in ["url-tvg", "x-tvg-url"] {
                    guard let value = attributes[key] else { continue }
                    for part in value.split(separator: ",") {
                        let trimmed = part.trimmingCharacters(in: .whitespaces)
                        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
                           scheme == "http" || scheme == "https", !guideURLs.contains(url) {
                            guideURLs.append(url)
                        }
                    }
                }
            } else if line.hasPrefix("#EXTINF:") {
                sawEntry = true
                pending = (name: displayName(line), attributes: parseAttributes(line))
            } else if line.hasPrefix("#EXTGRP:") {
                let group = line.dropFirst("#EXTGRP:".count).trimmingCharacters(in: .whitespaces)
                currentGroup = group.isEmpty ? nil : group
            } else if line.hasPrefix("#") {
                continue
            } else if let entry = pending {
                let groupTitle = entry.attributes["group-title"].flatMap { $0.isEmpty ? nil : $0 }
                entries.append(M3UEntry(
                    name: entry.name,
                    attributes: entry.attributes,
                    group: groupTitle ?? currentGroup,
                    url: line
                ))
                pending = nil
            }
        }

        guard sawHeader || sawEntry else { throw ParseError.notAPlaylist }
        return M3UPlaylist(guideURLs: guideURLs, entries: entries)
    }

    private static func parseAttributes(_ line: String) -> [String: String] {
        var attributes: [String: String] = [:]
        for match in line.matches(of: /([A-Za-z0-9_-]+)="([^"]*)"/) {
            let key = String(match.1).lowercased()
            if attributes[key] == nil { attributes[key] = String(match.2) }
        }
        return attributes
    }

    /// The text after the first comma outside double quotes, trimmed.
    private static func displayName(_ line: String) -> String {
        var inQuotes = false
        for index in line.indices {
            switch line[index] {
            case "\"": inQuotes.toggle()
            case "," where !inQuotes:
                return line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
            default: break
            }
        }
        return ""
    }
}
