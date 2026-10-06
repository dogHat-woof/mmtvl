import Foundation

/// The request line of a minimal HTTP/1.1 request (L11).
nonisolated struct HTTPRequestHead: Equatable, Sendable {
    static let maxSize = 16_384

    var method: String
    /// Without the query string; percent-decoding not needed (allow-list match).
    var path: String

    enum ParseResult: Equatable { case incomplete, tooLarge, invalid, complete(HTTPRequestHead) }

    /// Looks for "\r\n\r\n" in `data` (max 16 KB, else .tooLarge), parses "METHOD SP target SP HTTP/1.x".
    static func parse(_ data: Data) -> ParseResult {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxSize ? .tooLarge : .incomplete
        }
        guard end.lowerBound <= maxSize else { return .tooLarge }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let requestLine = head.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isLetter && $0.isUppercase }),
              parts[1].hasPrefix("/"),
              parts[2].hasPrefix("HTTP/1.")
        else { return .invalid }
        let target = parts[1]
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? target
        return .complete(HTTPRequestHead(method: String(parts[0]), path: String(path)))
    }
}

nonisolated enum HTTPResponse {
    /// Status line, Content-Type, Content-Length, Connection: close, Cache-Control: no-store,
    /// X-Content-Type-Options: nosniff, blank line, body (omitted for HEAD).
    static func make(status: Int, reason: String, contentType: String, body: Data, includeBody: Bool) -> Data {
        let head = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "",
            "",
        ].joined(separator: "\r\n")
        var data = Data(head.utf8)
        if includeBody { data.append(body) }
        return data
    }

    /// text/plain body "<status> <reason>".
    static func error(_ status: Int, _ reason: String) -> Data {
        make(status: status, reason: reason, contentType: "text/plain; charset=utf-8",
             body: Data("\(status) \(reason)".utf8), includeBody: true)
    }
}
