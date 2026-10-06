import Foundation

/// A bundled phone-page file. Synchronized groups copy resources flat into Contents/Resources (L11).
nonisolated struct RemoteWebAsset: Equatable, Sendable {
    var resource: String
    var ext: String
    var contentType: String
}

nonisolated enum RemoteWebAssets {
    /// The allow-list: "/" and "/index.html" → remote.html; "/remote.css"; "/remote.js". Anything else → nil (404).
    static func asset(forPath path: String) -> RemoteWebAsset? {
        switch path {
        case "/", "/index.html":
            RemoteWebAsset(resource: "remote", ext: "html", contentType: "text/html; charset=utf-8")
        case "/remote.css":
            RemoteWebAsset(resource: "remote", ext: "css", contentType: "text/css; charset=utf-8")
        case "/remote.js":
            RemoteWebAsset(resource: "remote", ext: "js", contentType: "text/javascript; charset=utf-8")
        default:
            nil
        }
    }

    /// Read per request (tiny files; no caching needed).
    static func data(for asset: RemoteWebAsset, bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: asset.resource, withExtension: asset.ext) else { return nil }
        return try? Data(contentsOf: url)
    }
}
