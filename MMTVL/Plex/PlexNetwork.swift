import Foundation

/// Injectable transport for Plex (like `IPTVNetwork`); tests use a fake.
nonisolated struct PlexNetwork: Sendable {
    /// Returns the body and the HTTP status (no throw on non-2xx). Throws on transport errors.
    var send: @Sendable (URLRequest) async throws -> (Data, Int)

    static let live: PlexNetwork = {
        // Ephemeral: no cookies or cache on disk.
        let session = URLSession(configuration: .ephemeral)
        return PlexNetwork { request in
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }()
}
