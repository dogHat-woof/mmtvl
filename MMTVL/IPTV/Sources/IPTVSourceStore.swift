import Foundation
import os

/// The playlist and guide URLs (L2, D23). They carry account tokens, so they live in the Keychain (D9)
/// and are never logged; only their hosts are. Closures, like `PINStore`, so tests can fake it.
struct IPTVSourceStore {
    static let playlistAccount = "iptv-playlist-url"
    static let guideAccount = "iptv-guide-url"
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    /// Keychain errors are logged and read as nil.
    var playlistURL: () -> URL?
    var setPlaylistURL: (URL) throws -> Void
    var guideURL: () -> URL?
    /// nil removes.
    var setGuideURL: (URL?) throws -> Void
    var removeAll: () throws -> Void

    static let keychain = keychain(service: Keychain.service)

    /// Tests use a separate service.
    static func keychain(service: String) -> IPTVSourceStore {
        func read(_ account: String) -> URL? {
            do {
                return try Keychain.string(account: account, service: service).flatMap(URL.init(string:))
            } catch {
                logger.error("Failed to read \(account, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return IPTVSourceStore(
            playlistURL: { read(playlistAccount) },
            setPlaylistURL: { try Keychain.set($0.absoluteString, account: playlistAccount, service: service) },
            guideURL: { read(guideAccount) },
            setGuideURL: { url in
                if let url {
                    try Keychain.set(url.absoluteString, account: guideAccount, service: service)
                } else {
                    try Keychain.remove(account: guideAccount, service: service)
                }
            },
            removeAll: {
                try Keychain.remove(account: playlistAccount, service: service)
                try Keychain.remove(account: guideAccount, service: service)
            }
        )
    }

    /// Tests.
    static func inMemory(playlist: URL? = nil, guide: URL? = nil) -> IPTVSourceStore {
        let box = Box(playlist: playlist, guide: guide)
        return IPTVSourceStore(
            playlistURL: { box.playlist },
            setPlaylistURL: { box.playlist = $0 },
            guideURL: { box.guide },
            setGuideURL: { box.guide = $0 },
            removeAll: { box.playlist = nil; box.guide = nil }
        )
    }

    private final class Box {
        var playlist: URL?
        var guide: URL?
        init(playlist: URL?, guide: URL?) {
            self.playlist = playlist
            self.guide = guide
        }
    }
}
