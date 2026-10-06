import Foundation

/// A phone-page file. Synchronized groups copy resources flat into Contents/Resources (L11).
nonisolated struct RemoteWebAsset: Equatable, Sendable {
    /// Assets built in code instead of read from the bundle (M7b L10).
    enum Generated: Equatable, Sendable { case icon(size: Int), manifest }

    var resource: String
    var ext: String
    var contentType: String
    /// Non-nil: built in code (L10); `resource`/`ext` are empty.
    var generated: Generated? = nil
}

nonisolated enum RemoteWebAssets {
    /// The allow-list: "/" and "/index.html" → remote.html; "/remote.css"; "/remote.js"; the generated icons and
    /// web manifest (M7b L10). Anything else → nil (404).
    static func asset(forPath path: String) -> RemoteWebAsset? {
        switch path {
        case "/", "/index.html":
            RemoteWebAsset(resource: "remote", ext: "html", contentType: "text/html; charset=utf-8")
        case "/remote.css":
            RemoteWebAsset(resource: "remote", ext: "css", contentType: "text/css; charset=utf-8")
        case "/remote.js":
            RemoteWebAsset(resource: "remote", ext: "js", contentType: "text/javascript; charset=utf-8")
        case "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png":
            generated(.icon(size: 180), contentType: "image/png")
        case "/icon-192.png":
            generated(.icon(size: 192), contentType: "image/png")
        case "/icon-512.png":
            generated(.icon(size: 512), contentType: "image/png")
        case "/remote.webmanifest":
            generated(.manifest, contentType: "application/manifest+json; charset=utf-8")
        default:
            nil
        }
    }

    private static func generated(_ kind: RemoteWebAsset.Generated, contentType: String) -> RemoteWebAsset {
        RemoteWebAsset(resource: "", ext: "", contentType: contentType, generated: kind)
    }

    /// Bundle files only (nil for generated assets). Read per request (tiny files; no caching needed).
    static func data(for asset: RemoteWebAsset, bundle: Bundle = .main) -> Data? {
        guard asset.generated == nil,
              let url = bundle.url(forResource: asset.resource, withExtension: asset.ext)
        else { return nil }
        return try? Data(contentsOf: url)
    }
}

/// The phone remote's web manifest (M7b L10).
nonisolated enum RemoteWebManifest {
    static let json = """
        {"name":"MMTVL Remote","short_name":"MMTVL","start_url":"/","display":"standalone",\
        "background_color":"#000000","theme_color":"#000000",\
        "icons":[{"src":"/icon-192.png","sizes":"192x192","type":"image/png"},\
        {"src":"/icon-512.png","sizes":"512x512","type":"image/png"}]}
        """
}
