import Foundation

/// plex.tv sign-in, server discovery and Continue Watching (M7 D28, L14–L16): request building and JSON decoding.
/// Pure; `PlexAccount` sends the requests. Never log a token, a PIN code or a full connection URI.
nonisolated enum PlexAPI {
    struct ClientInfo: Equatable, Sendable {
        /// A stable UUID (`plex.json`).
        var identifier: String
        var version: String
        var deviceName: String
        var platformVersion: String
    }

    struct PIN: Decodable, Equatable, Sendable {
        var id: Int
        var code: String
        /// nil when missing or unparseable.
        var expiresAt: Date?
        /// nil until the user enters the code at plex.tv/link.
        var authToken: String?

        enum CodingKeys: String, CodingKey { case id, code, expiresAt, authToken }

        init(id: Int, code: String, expiresAt: Date? = nil, authToken: String? = nil) {
            self.id = id
            self.code = code
            self.expiresAt = expiresAt
            self.authToken = authToken
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            code = try container.decode(String.self, forKey: .code)
            expiresAt = (try? container.decodeIfPresent(String.self, forKey: .expiresAt)).flatMap(PlexAPI.parseDate)
            authToken = try container.decodeIfPresent(String.self, forKey: .authToken)
        }
    }

    struct Resource: Decodable, Equatable, Sendable {
        struct Connection: Decodable, Equatable, Sendable {
            var uri: String
            var local: Bool
            var relay: Bool
            var `protocol`: String

            enum CodingKeys: String, CodingKey { case uri, local, relay, `protocol` }

            init(uri: String, local: Bool, relay: Bool, protocol: String) {
                self.uri = uri
                self.local = local
                self.relay = relay
                self.protocol = `protocol`
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                uri = try container.decode(String.self, forKey: .uri)
                local = try container.decodeIfPresent(Bool.self, forKey: .local) ?? false
                relay = try container.decodeIfPresent(Bool.self, forKey: .relay) ?? false
                `protocol` = try container.decodeIfPresent(String.self, forKey: .protocol) ?? ""
            }
        }

        var name: String
        var provides: String
        /// The server's machine identifier.
        var clientIdentifier: String
        /// Use this for the server, not the user token.
        var accessToken: String?
        var owned: Bool?
        var presence: Bool?
        var connections: [Connection]

        var isServer: Bool { provides.split(separator: ",").contains("server") }

        enum CodingKeys: String, CodingKey { case name, provides, clientIdentifier, accessToken, owned, presence, connections }

        init(name: String, provides: String, clientIdentifier: String, accessToken: String? = nil, owned: Bool? = nil,
             presence: Bool? = nil, connections: [Connection] = []) {
            self.name = name
            self.provides = provides
            self.clientIdentifier = clientIdentifier
            self.accessToken = accessToken
            self.owned = owned
            self.presence = presence
            self.connections = connections
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            provides = try container.decodeIfPresent(String.self, forKey: .provides) ?? ""
            clientIdentifier = try container.decode(String.self, forKey: .clientIdentifier)
            accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
            owned = try container.decodeIfPresent(Bool.self, forKey: .owned)
            presence = try container.decodeIfPresent(Bool.self, forKey: .presence)
            connections = (try? container.decodeIfPresent([Connection].self, forKey: .connections)) ?? []
        }
    }

    /// Every field optional (confirm against a live response, step 11).
    struct Metadata: Decodable, Equatable, Sendable {
        var ratingKey: String?
        var type: String?
        var title: String?
        var grandparentTitle: String?
        var parentIndex: Int?
        var index: Int?
        var year: Int?
        var thumb: String?
        var art: String?
        var grandparentThumb: String?
        var grandparentArt: String?
        var viewOffset: Int?
        var duration: Int?

        enum CodingKeys: String, CodingKey {
            case ratingKey, type, title, grandparentTitle, parentIndex, index, year, thumb, art, grandparentThumb,
                 grandparentArt, viewOffset, duration
        }

        init(ratingKey: String? = nil, type: String? = nil, title: String? = nil, grandparentTitle: String? = nil,
             parentIndex: Int? = nil, index: Int? = nil, year: Int? = nil, thumb: String? = nil, art: String? = nil,
             grandparentThumb: String? = nil, grandparentArt: String? = nil, viewOffset: Int? = nil, duration: Int? = nil) {
            self.ratingKey = ratingKey
            self.type = type
            self.title = title
            self.grandparentTitle = grandparentTitle
            self.parentIndex = parentIndex
            self.index = index
            self.year = year
            self.thumb = thumb
            self.art = art
            self.grandparentThumb = grandparentThumb
            self.grandparentArt = grandparentArt
            self.viewOffset = viewOffset
            self.duration = duration
        }

        /// Lenient: a field of an unexpected type reads as nil instead of failing the item.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func string(_ key: CodingKeys) -> String? {
                if let value = try? c.decodeIfPresent(String.self, forKey: key) { return value }
                return (try? c.decodeIfPresent(Int.self, forKey: key)).flatMap { $0.map(String.init) }
            }
            func int(_ key: CodingKeys) -> Int? {
                if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
                return (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0.flatMap { Int($0) } }
            }
            ratingKey = string(.ratingKey)
            type = string(.type)
            title = string(.title)
            grandparentTitle = string(.grandparentTitle)
            parentIndex = int(.parentIndex)
            index = int(.index)
            year = int(.year)
            thumb = string(.thumb)
            art = string(.art)
            grandparentThumb = string(.grandparentThumb)
            grandparentArt = string(.grandparentArt)
            viewOffset = int(.viewOffset)
            duration = int(.duration)
        }
    }

    static let product = "MMTVL"
    static let requestTimeout: TimeInterval = 10
    static let identityTimeout: TimeInterval = 4
    static let continueWatchingCount = 12
    static let imageSize = (width: 704, height: 396)

    // MARK: Requests

    /// The `X-Plex-*` headers, plus `Accept: application/json` and `X-Plex-Token` when a token is given.
    static func headers(_ client: ClientInfo, token: String?) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-Plex-Client-Identifier": client.identifier,
            "X-Plex-Product": product,
            "X-Plex-Version": client.version,
            "X-Plex-Platform": "macOS",
            "X-Plex-Platform-Version": client.platformVersion,
            "X-Plex-Device": "Mac",
            "X-Plex-Device-Name": client.deviceName,
        ]
        if let token { headers["X-Plex-Token"] = token }
        return headers
    }

    /// POST, no body, no `strong=true`: a 4-character code for plex.tv/link.
    static func createPINRequest(_ client: ClientInfo) -> URLRequest {
        request(URL(string: "https://plex.tv/api/v2/pins")!, method: "POST", headers: headers(client, token: nil))
    }

    static func checkPINRequest(id: Int, _ client: ClientInfo) -> URLRequest {
        request(URL(string: "https://plex.tv/api/v2/pins/\(id)")!, headers: headers(client, token: nil))
    }

    /// 200 = the token is valid, 401 = not.
    static func userRequest(token: String, _ client: ClientInfo) -> URLRequest {
        request(URL(string: "https://plex.tv/api/v2/user")!, headers: headers(client, token: token))
    }

    static func resourcesRequest(token: String, _ client: ClientInfo) -> URLRequest {
        request(URL(string: "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=0")!,
                headers: headers(client, token: token))
    }

    /// No auth; `machineIdentifier` must equal the resource's `clientIdentifier`.
    static func identityRequest(connection: URL) -> URLRequest {
        var request = request(connection.appending(path: "identity"), headers: ["Accept": "application/json"])
        request.timeoutInterval = identityTimeout
        return request
    }

    /// `flat: false`: the documented hubs form; `flat: true`: the `/items` fallback (on 404).
    static func continueWatchingRequest(server: URL, token: String, _ client: ClientInfo, flat: Bool) -> URLRequest {
        var headers = headers(client, token: token)
        let url: URL
        if flat {
            url = server.appending(path: "hubs/continueWatching/items")
            headers["X-Plex-Container-Start"] = "0"
            headers["X-Plex-Container-Size"] = "\(continueWatchingCount)"
        } else {
            var components = URLComponents(url: server.appending(path: "hubs/continueWatching"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "count", value: "\(continueWatchingCount)")]
            url = components.url!
        }
        return request(url, headers: headers)
    }

    /// The token goes in a header (`X-Plex-Token`), never in this URL.
    static func imageURL(server: URL, path: String, width: Int, height: Int) -> URL {
        var components = URLComponents(url: server.appending(path: "photo/:/transcode"), resolvingAgainstBaseURL: false)!
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "width", value: "\(width)"),
            URLQueryItem(name: "height", value: "\(height)"),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
            URLQueryItem(name: "url", value: path.addingPercentEncoding(withAllowedCharacters: unreserved)),
        ]
        return components.url!
    }

    static func linkURL(code: String) -> String {
        "https://plex.tv/link/?pin=\(code)"
    }

    private static func request(_ url: URL, method: String = "GET", headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    // MARK: Decoding

    static func decodePIN(_ data: Data) throws -> PIN {
        try JSONDecoder().decode(PIN.self, from: data)
    }

    static func decodeResources(_ data: Data) throws -> [Resource] {
        try JSONDecoder().decode([Resource].self, from: data)
    }

    static func decodeIdentity(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Container: Decodable { var machineIdentifier: String }
            var MediaContainer: Container
        }
        return try JSONDecoder().decode(Response.self, from: data).MediaContainer.machineIdentifier
    }

    /// Hub form (`home.continue`, else the first hub) or flat form.
    static func decodeContinueWatching(_ data: Data) throws -> [Metadata] {
        struct Response: Decodable {
            struct Hub: Decodable {
                var hubIdentifier: String?
                var Metadata: [PlexAPI.Metadata]?
            }
            struct Container: Decodable {
                var Hub: [Hub]?
                var Metadata: [PlexAPI.Metadata]?
            }
            var MediaContainer: Container
        }
        let container = try JSONDecoder().decode(Response.self, from: data).MediaContainer
        if let hubs = container.Hub, !hubs.isEmpty {
            let hub = hubs.first { $0.hubIdentifier == "home.continue" } ?? hubs[0]
            return hub.Metadata ?? []
        }
        return container.Metadata ?? []
    }

    /// L14: the card's lines, image path and progress.
    static func card(_ item: Metadata) -> (title: String, subtitle: String, imagePath: String?, progress: Double?) {
        var progress: Double?
        if let offset = item.viewOffset, let duration = item.duration, duration > 0 {
            progress = min(max(Double(offset) / Double(duration), 0), 1)
        }
        if item.type == "episode" {
            var subtitle = item.title ?? ""
            if let season = item.parentIndex, let episode = item.index {
                subtitle = subtitle.isEmpty ? "S\(season) E\(episode)" : "S\(season) E\(episode) · \(subtitle)"
            }
            return (item.grandparentTitle ?? item.title ?? "", subtitle,
                    item.grandparentArt ?? item.art ?? item.thumb, progress)
        }
        return (item.title ?? "", item.year.map(String.init) ?? "", item.art ?? item.thumb, progress)
    }

    /// ISO 8601, with or without fractional seconds.
    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
