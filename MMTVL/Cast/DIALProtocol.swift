import Foundation

/// SSDP discovery for DIAL (D30): which datagrams are DIAL searches, and the unicast reply.
nonisolated enum SSDP {
    static let multicastAddress = "239.255.255.250"
    static let port: UInt16 = 1900
    static let dialSearchTarget = "urn:dial-multiscreen-org:service:dial:1"

    /// True for "M-SEARCH * HTTP/1.1" with MAN "ssdp:discover" (quotes optional) and ST == dialSearchTarget
    /// (header names case-insensitive; ST compared case-sensitively after trimming).
    static func isDIALSearch(_ datagram: Data) -> Bool {
        guard let text = String(data: datagram, encoding: .utf8) else { return false }
        // "\r\n" is one Character, so split on any newline.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "M-SEARCH * HTTP/1.1" else { return false }
        var man: String?
        var st: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch name {
            case "man": man = value
            case "st": st = value
            default: break
            }
        }
        let discover = man.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        return discover == "ssdp:discover" && st == dialSearchTarget
    }

    /// The unicast reply (CRLF lines, ends with an empty line).
    static func searchReply(location: String, deviceID: String, server: String, date: Date) -> Data {
        let lines = [
            "HTTP/1.1 200 OK",
            "CACHE-CONTROL: max-age=1800",
            "DATE: \(httpDate(date))",
            "EXT:",
            "LOCATION: \(location)",
            "SERVER: \(server)",
            "ST: \(dialSearchTarget)",
            "USN: uuid:\(deviceID)::\(dialSearchTarget)",
            "",
            "",
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    /// RFC 1123 in GMT, e.g. "Tue, 06 Oct 2026 17:00:00 GMT".
    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

/// One HTTP request to the DIAL server (head and body).
nonisolated struct DIALRequest: Equatable, Sendable {
    var method: String
    /// Without the query; repeated slashes collapsed.
    var path: String
    /// Lowercased names.
    var headers: [String: String]
    var body: String

    /// `tooLarge` carries 413 (body) or 431 (head).
    enum Parse: Equatable { case incomplete, tooLarge(Int), invalid, complete(DIALRequest) }

    static let maxHeadSize = 16_384
    static let maxBodySize = 4_096

    static func parse(_ data: Data) -> Parse {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeadSize ? .tooLarge(431) : .incomplete
        }
        guard end.lowerBound - data.startIndex <= maxHeadSize else { return .tooLarge(431) }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isLetter && $0.isUppercase }),
              parts[1].hasPrefix("/"),
              parts[2].hasPrefix("HTTP/1.")
        else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        var length = 0
        if let value = headers["content-length"] {
            guard let parsed = Int(value), parsed >= 0 else { return .invalid }
            length = parsed
        }
        guard length <= maxBodySize else { return .tooLarge(413) }
        let bodyStart = end.upperBound
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let body = String(decoding: data[bodyStart..<(bodyStart + length)], as: UTF8.self)

        let target = parts[1]
        let rawPath = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? target
        return .complete(DIALRequest(method: String(parts[0]), path: collapseSlashes(String(rawPath)),
                                     headers: headers, body: body))
    }

    private static func collapseSlashes(_ path: String) -> String {
        var result = ""
        for character in path where !(character == "/" && result.hasSuffix("/")) {
            result.append(character)
        }
        return result
    }
}

/// A reply the DIAL server sends as is.
nonisolated struct DIALReply: Equatable, Sendable {
    var status: Int
    var contentType: String?
    var headers: [HTTPHeader] = []
    var body: Data = Data()

    func encoded(includeBody: Bool = true) -> Data {
        HTTPResponse.make(status: status, reason: HTTPResponse.reason(for: status), contentType: contentType,
                          headers: headers, body: body, includeBody: includeBody)
    }

    /// A text/plain "<status> <reason>" reply.
    static func error(_ status: Int) -> DIALReply {
        DIALReply(status: status, contentType: "text/plain; charset=utf-8",
                  body: Data("\(status) \(HTTPResponse.reason(for: status))".utf8))
    }
}

/// A request handed to leanback's own DIAL handlers (L1).
nonisolated struct DIALAppRequest: Equatable, Sendable {
    var app: String
    var method: String
    /// Relative to /apps/YouTube: "/" or "/run".
    var path: String
    var body: String
    /// "IP:port".
    var host: String
}

/// Leanback's answer to a forwarded request.
nonisolated struct DIALAppResponse: Equatable, Sendable {
    var handled: Bool
    var status: Int
    var body: String
    var mimeType: String?
    var headers: [HTTPHeader]
}

nonisolated struct DIALContext: Equatable, Sendable {
    /// "IP:port" as the phone reached us.
    var host: String
    var deviceID: String
    var friendlyName: String
    var appReady: Bool
    /// L9.
    var isLaunching: Bool
}

nonisolated enum DIALDecision: Equatable, Sendable {
    case reply(DIALReply)
    case forward(DIALAppRequest)
    /// Native cold launch (L2); nil = no parameters. The server replies 201 itself.
    case launch(query: String?)
}

/// What the DIAL server does with a request (Request flow step 3).
nonisolated enum DIALRouting {
    static let appName = "YouTube"
    static let xmlContentType = "text/xml; charset=\"utf-8\""
    /// L6.
    static let allowedLaunchParameters: Set<String> = [
        "pairingCode", "reversePairingCode", "v", "t", "list", "index", "theme", "dialLaunch",
    ]

    static func decide(_ request: DIALRequest, context: DIALContext) -> DIALDecision {
        let path = request.path
        switch path {
        case "/", "/dd.xml":
            guard request.method == "GET" else { return .reply(.error(405)) }
            let body = deviceDescription(host: context.host, deviceID: context.deviceID,
                                         friendlyName: context.friendlyName)
            return .reply(DIALReply(status: 200, contentType: xmlContentType,
                                    headers: [HTTPHeader(name: "Application-URL", value: "http://\(context.host)/apps")],
                                    body: Data(body.utf8)))
        case "/apps", "/apps/":
            guard request.method == "GET" else { return .reply(.error(404)) }
            return .reply(DIALReply(status: 302, contentType: nil,
                                    headers: [HTTPHeader(name: "Location", value: "http://\(context.host)/apps/\(appName)")]))
        default:
            break
        }

        guard path.hasPrefix("/apps/") else { return .reply(.error(404)) }
        let rest = path.dropFirst("/apps/".count)
        let name = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard name == appName else { return .reply(.error(404)) }
        guard !isForbiddenOrigin(request.headers["origin"]) else { return .reply(.error(403)) }
        guard ["GET", "POST", "DELETE"].contains(request.method) else { return .reply(.error(405)) }

        var subpath = String(rest.dropFirst(name.count))
        while subpath.hasSuffix("/") { subpath.removeLast() }
        if subpath.isEmpty { subpath = "/" }

        if context.appReady {
            return .forward(DIALAppRequest(app: appName, method: request.method, path: subpath,
                                           body: request.body, host: context.host))
        }
        return nativeAppDecision(request, subpath: subpath, context: context)
    }

    /// The native answer when leanback can't answer (also used after a forward times out).
    static func nativeAppDecision(_ request: DIALRequest, subpath: String, context: DIALContext) -> DIALDecision {
        switch (request.method, subpath) {
        case ("GET", "/"):
            return .reply(DIALReply(status: 200, contentType: xmlContentType,
                                    body: Data(appStatus(running: context.isLaunching).utf8)))
        case ("POST", "/"):
            guard let query = sanitizedLaunchQuery(request.body) else { return .reply(.error(400)) }
            return .launch(query: query.isEmpty ? nil : query)
        default:
            return .reply(.error(404))
        }
    }

    /// A leanback answer → reply. handled false → 400. status 0 → 200.
    static func reply(for response: DIALAppResponse) -> DIALReply {
        guard response.handled else { return .error(400) }
        return DIALReply(status: response.status == 0 ? 200 : response.status,
                         contentType: response.mimeType,
                         headers: response.headers,
                         body: Data(response.body.utf8))
    }

    static func deviceDescription(host: String, deviceID: String, friendlyName: String) -> String {
        "<?xml version=\"1.0\"?><root xmlns=\"urn:schemas-upnp-org:device-1-0\">"
            + "<specVersion><major>1</major><minor>0</minor></specVersion>"
            + "<URLBase>http://\(xmlEscaped(host))</URLBase>"
            + "<device><deviceType>urn:dial-multiscreen-org:device:dial:1</deviceType>"
            + "<friendlyName>\(xmlEscaped(friendlyName))</friendlyName>"
            + "<manufacturer>MMTVL</manufacturer><modelName>MMTVL</modelName>"
            + "<UDN>uuid:\(xmlEscaped(deviceID))</UDN></device></root>"
    }

    static func appStatus(running: Bool) -> String {
        let state = running ? "<state>running</state><link rel=\"run\" href=\"run\"/>" : "<state>stopped</state>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<service xmlns=\"urn:dial-multiscreen-org:schemas:dial\" dialVer=\"2.1\">"
            + "<name>\(appName)</name><options allowStop=\"false\"/>\(state)</service>"
    }

    /// The Origin schemes real DIAL clients send (the YouTube apps send `package:<app id>`); never a web page's.
    static let allowedOriginSchemes = ["package:", "android-app:", "app:"]

    /// L7, and the pre-release security review (item 4): no Origin header is allowed (native clients); otherwise only
    /// an allowed non-web scheme with something after it. Web pages (http, https), opaque origins (`null`, from
    /// sandboxed iframes and data: or file: pages) and anything else are forbidden.
    static func isForbiddenOrigin(_ origin: String?) -> Bool {
        guard let origin else { return false }
        let value = origin.trimmingCharacters(in: .whitespaces).lowercased()
        return !allowedOriginSchemes.contains { value.hasPrefix($0) && value.count > $0.count }
    }

    /// L6. nil = not a query string; "" = nothing allowed.
    static func sanitizedLaunchQuery(_ body: String) -> String? {
        guard isWellFormedQuery(body) else { return nil }
        var components = URLComponents()
        components.percentEncodedQuery = body
        let kept = (components.queryItems ?? []).filter { item in
            guard allowedLaunchParameters.contains(item.name), let value = item.value else { return false }
            return (1...200).contains(value.count) && value.allSatisfy(isAllowedValueCharacter)
        }
        guard !kept.isEmpty else { return "" }
        var output = URLComponents()
        output.queryItems = kept
        return output.percentEncodedQuery ?? ""
    }

    /// Only URL query characters, and every "%" starts a two-digit hex escape (URLComponents traps otherwise).
    private static func isWellFormedQuery(_ body: String) -> Bool {
        let allowed = CharacterSet.urlQueryAllowed
        let scalars = Array(body.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "%" {
                guard index + 2 < scalars.count,
                      scalars[index + 1].properties.isASCIIHexDigit,
                      scalars[index + 2].properties.isASCIIHexDigit
                else { return false }
                index += 3
                continue
            }
            guard allowed.contains(scalar) else { return false }
            index += 1
        }
        return true
    }

    private static func isAllowedValueCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || "._~-".contains(character)
    }

    private static func xmlEscaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}
