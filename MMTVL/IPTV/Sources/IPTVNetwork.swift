import Foundation

nonisolated enum IPTVNetworkError: Error, Equatable {
    case http(Int)
    /// M7j step 8 (security L3): a download bigger than its limit.
    case tooLarge
}

/// Injectable network access for the playlist and guide; tests use a fake.
nonisolated struct IPTVNetwork: Sendable {
    /// GET as text (UTF-8, lossy). Throws IPTVNetworkError.http(status) for non-2xx. Timeout 30 s.
    var fetchText: @Sendable (URL) async throws -> String
    /// Downloads to a temporary file that the caller then owns. Throws for non-2xx. Timeout 120 s.
    var download: @Sendable (URL) async throws -> URL

    static let live: IPTVNetwork = {
        // Ephemeral: no cookies or cache on disk.
        let session = URLSession(configuration: .ephemeral)
        return IPTVNetwork(
            fetchText: { url in
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                let (data, response) = try await session.data(for: request)
                try checkStatus(response)
                return String(decoding: data, as: UTF8.self)
            },
            download: { url in
                var request = URLRequest(url: url)
                request.timeoutInterval = 120
                let (location, response) = try await session.download(for: request)
                do {
                    try checkStatus(response)
                } catch {
                    try? FileManager.default.removeItem(at: location)
                    throw error
                }
                let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try FileManager.default.moveItem(at: location, to: destination)
                return destination
            }
        )
    }()

    /// `download(url)`, refused (the file deleted, `IPTVNetworkError.tooLarge`) when it's bigger than `maxBytes` (nil: no
    /// limit). Checked once the download is on disk: URLSession has already undone any `Content-Encoding: gzip`, so
    /// this limits the body as served. M7j step 8 (security L3): the antenna guide only; pasted guides pass nil.
    func download(_ url: URL, maxBytes: Int?) async throws -> URL {
        let file = try await download(url)
        guard let maxBytes else { return file }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
        guard size <= maxBytes else {
            try? FileManager.default.removeItem(at: file)
            throw IPTVNetworkError.tooLarge
        }
        return file
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw IPTVNetworkError.http(http.statusCode) }
    }
}
