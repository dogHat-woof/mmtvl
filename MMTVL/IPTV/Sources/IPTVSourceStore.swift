import Foundation
import os

/// The playlist and guide URLs (L2, D23). They carry account tokens, so they live in the Keychain (D9)
/// and are never logged; only their hosts are. Closures, like `PINStore`, so tests can fake it.
struct IPTVSourceStore {
    static let playlistAccount = "iptv-playlist-url"
    /// The pasted guides, a JSON array of URL strings in paste order (M6b L1).
    static let guideListAccount = "iptv-guide-urls"
    /// M4's single pasted guide; read when the list is missing, removed on the next save (M6b L1).
    static let legacyGuideAccount = "iptv-guide-url"
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    /// Keychain errors are logged and read as nil.
    var playlistURL: () -> URL?
    var setPlaylistURL: (URL) throws -> Void
    /// Keychain errors and undecodable values are logged and read as [].
    var guideURLs: () -> [URL]
    /// [] removes the list. Always removes the legacy account.
    var setGuideURLs: ([URL]) throws -> Void
    var removeAll: () throws -> Void

    static let keychain = keychain(service: Keychain.service)

    /// Tests use a separate service.
    static func keychain(service: String) -> IPTVSourceStore {
        func read(_ account: String) -> String? {
            do {
                return try Keychain.string(account: account, service: service)
            } catch {
                logger.error("Failed to read \(account, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return IPTVSourceStore(
            playlistURL: { read(playlistAccount).flatMap(URL.init(string:)) },
            setPlaylistURL: { try Keychain.set($0.absoluteString, account: playlistAccount, service: service) },
            guideURLs: {
                guard let list = read(guideListAccount) else {
                    return read(legacyGuideAccount).flatMap(URL.init(string:)).map { [$0] } ?? []
                }
                guard let strings = try? JSONDecoder().decode([String].self, from: Data(list.utf8)) else {
                    logger.error("\(guideListAccount, privacy: .public) couldn't be read; ignoring it")
                    return []
                }
                return strings.compactMap(URL.init(string:))
            },
            setGuideURLs: { urls in
                if urls.isEmpty {
                    try Keychain.remove(account: guideListAccount, service: service)
                } else {
                    let json = String(decoding: try JSONEncoder().encode(urls.map(\.absoluteString)), as: UTF8.self)
                    try Keychain.set(json, account: guideListAccount, service: service)
                }
                try Keychain.remove(account: legacyGuideAccount, service: service)
            },
            removeAll: {
                try Keychain.remove(account: playlistAccount, service: service)
                try Keychain.remove(account: guideListAccount, service: service)
                try Keychain.remove(account: legacyGuideAccount, service: service)
            }
        )
    }

    /// Tests.
    static func inMemory(playlist: URL? = nil, guides: [URL] = []) -> IPTVSourceStore {
        let box = Box(playlist: playlist, guides: guides)
        return IPTVSourceStore(
            playlistURL: { box.playlist },
            setPlaylistURL: { box.playlist = $0 },
            guideURLs: { box.guides },
            setGuideURLs: { box.guides = $0 },
            removeAll: { box.playlist = nil; box.guides = [] }
        )
    }

    private final class Box {
        var playlist: URL?
        var guides: [URL]
        init(playlist: URL?, guides: [URL]) {
            self.playlist = playlist
            self.guides = guides
        }
    }
}
