import Foundation

/// Fixed settings for the built-in YouTube TV experience (D5, D21).
nonisolated enum YouTubeConfig {
    static let startURL = URL(string: "https://www.youtube.com/tv")!

    /// Verified 2026-10-05 (see M3 research). Don't move to Cobalt/26: reported to stop playback after ~45 s.
    static let defaultUserAgent = "Mozilla/5.0 (PS4; Leanback Shell) Cobalt/25.lts.40.1035033; compatible"

    /// Top-level pages may only come from these domains or their subdomains (L5). Sign-in needs google.com.
    static let allowedDomains = ["youtube.com", "google.com", "gstatic.com"]

    /// `settings.json` `youtubeUserAgent` if it isn't blank (L6), else the default.
    static func userAgent(override: String?) -> String {
        let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultUserAgent : trimmed
    }

    /// L5: subframes are unrestricted (ads, sign-in iframes); the main frame stays on YouTube/Google over https.
    static func allowsNavigation(to url: URL, isMainFrame: Bool) -> Bool {
        guard isMainFrame else { return true }
        if url.absoluteString == "about:blank" { return true }
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        return allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
