import Foundation

/// One XMLTV guide in use (M6b L1, L2): pasted, or from the playlist's url-tvg.
nonisolated struct GuideSource: Identifiable, Equatable, Sendable {
    let url: URL
    let isFromPlaylist: Bool
    /// SHA-256 of the URL: the database and state file never hold a URL.
    let id: String
    /// "<host> · <file name>" when the URL names a guide file, else the host (L2). Never the query.
    let label: String
    /// The file name without its guide extension, else the host.
    let shortLabel: String

    private static let extensions = [".xml.gz", ".xml", ".gz"]

    init(url: URL, isFromPlaylist: Bool) {
        self.url = url
        self.isFromPlaylist = isFromPlaylist
        id = IPTVLibrary.hash(url)
        let host = url.host() ?? "?"
        if let file = Self.fileName(of: url) {
            label = "\(host) · \(file)"
            let lower = file.lowercased()
            let suffix = Self.extensions.first { lower.hasSuffix($0) }?.count ?? 0
            shortLabel = String(file.dropLast(suffix))
        } else {
            label = host
            shortLabel = host
        }
    }

    /// L2: the file name when it looks like a guide file (.xml, .xml.gz or .gz, at most 64 characters), else nil.
    static func fileName(of url: URL) -> String? {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        guard name.count <= 64, extensions.contains(where: { lower.hasSuffix($0) }),
              extensions.allSatisfy({ lower != $0 }) else { return nil }
        return name
    }
}
