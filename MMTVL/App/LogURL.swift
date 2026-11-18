import Foundation

/// What a log line may say about a URL: its host only (CLAUDE.md: never a full URL, which can carry tokens, paths or
/// queries). "no host" for URLs without one (`file:`, `about:blank`) or nil. Pure.
nonisolated enum LogURL {
    static func host(_ url: URL?) -> String {
        guard let host = url?.host(), !host.isEmpty else { return "no host" }
        return host
    }
}
