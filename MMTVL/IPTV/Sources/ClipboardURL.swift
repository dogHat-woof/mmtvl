import Foundation

/// Validates a source URL pasted from the clipboard (L2).
nonisolated enum ClipboardURL {
    enum Problem: Error, Equatable { case empty, notAWebAddress }

    /// First non-empty line, trimmed; must be http/https with a non-empty host.
    static func parse(_ text: String?) -> Result<URL, Problem> {
        let line = (text ?? "")
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return .failure(.empty) }
        guard let url = URL(string: line),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return .failure(.notAWebAddress) }
        return .success(url)
    }

    static func message(for problem: Problem) -> String {
        switch problem {
        case .empty: "The clipboard is empty. Copy the URL first."
        case .notAWebAddress: "The clipboard doesn't hold a web address."
        }
    }
}
