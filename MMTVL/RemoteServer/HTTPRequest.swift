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

/// One extra response header (M7b).
nonisolated struct HTTPHeader: Equatable, Sendable {
    var name: String
    var value: String
}

nonisolated enum HTTPResponse {
    /// Status line, Content-Type (if any), Content-Length, the extra `headers`, Connection: close,
    /// Cache-Control: no-store, X-Content-Type-Options: nosniff, blank line, body (omitted for HEAD).
    static func make(status: Int, reason: String, contentType: String?, headers: [HTTPHeader] = [],
                     body: Data, includeBody: Bool) -> Data {
        var lines = ["HTTP/1.1 \(status) \(reason)"]
        if let contentType { lines.append("Content-Type: \(contentType)") }
        lines.append("Content-Length: \(body.count)")
        lines += headers.map { "\($0.name): \($0.value)" }
        lines += [
            "Connection: close",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "",
            "",
        ]
        var data = Data(lines.joined(separator: "\r\n").utf8)
        if includeBody { data.append(body) }
        return data
    }

    /// The reason phrase for the statuses MMTVL sends; anything else "Status".
    static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 302: "Found"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Content Too Large"
        case 431: "Request Header Fields Too Large"
        case 501: "Not Implemented"
        case 503: "Service Unavailable"
        default: "Status"
        }
    }

    /// text/plain body "<status> <reason>".
    static func error(_ status: Int, _ reason: String) -> Data {
        make(status: status, reason: reason, contentType: "text/plain; charset=utf-8",
             body: Data("\(status) \(reason)".utf8), includeBody: true)
    }
}
