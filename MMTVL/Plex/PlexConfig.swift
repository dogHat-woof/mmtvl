import Foundation
import os

/// `plex.json` (D10, M7 L15): non-secret Plex state. Tokens are Keychain items (`PlexTokenStore`).
nonisolated struct PlexConfig: Codable, Equatable, Sendable {
    static let fileName = "plex.json"

    /// A UUID created once; plex.tv lists it under Authorized Devices as "MMTVL".
    var clientIdentifier: String
    /// The chosen server's machine identifier.
    var serverID: String?
    var serverName: String?
    /// The chosen server's https, non-relay connection URIs, local first (L16).
    var connections: [String]
    /// The URI that answered last; tried first.
    var lastConnection: String?

    init(clientIdentifier: String = "", serverID: String? = nil, serverName: String? = nil, connections: [String] = [],
         lastConnection: String? = nil) {
        self.clientIdentifier = clientIdentifier
        self.serverID = serverID
        self.serverName = serverName
        self.connections = connections
        self.lastConnection = lastConnection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientIdentifier = (try? container.decodeIfPresent(String.self, forKey: .clientIdentifier)) ?? ""
        serverID = try? container.decodeIfPresent(String.self, forKey: .serverID)
        serverName = try? container.decodeIfPresent(String.self, forKey: .serverName)
        connections = (try? container.decodeIfPresent([String].self, forKey: .connections)) ?? []
        lastConnection = try? container.decodeIfPresent(String.self, forKey: .lastConnection)
    }
}

/// The Plex tokens (D9): Keychain accounts `plex-token` (user) and `plex-server-token` (the chosen server's).
nonisolated struct PlexTokenStore: Sendable {
    static let userAccount = "plex-token"
    static let serverAccount = "plex-server-token"
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Plex")

    var userToken: @Sendable () -> String?
    var setUserToken: @Sendable (String?) -> Void
    var serverToken: @Sendable () -> String?
    var setServerToken: @Sendable (String?) -> Void

    static let keychain = PlexTokenStore(
        userToken: { read(userAccount) },
        setUserToken: { write($0, userAccount) },
        serverToken: { read(serverAccount) },
        setServerToken: { write($0, serverAccount) }
    )

    /// Tests.
    static func inMemory(user: String? = nil, server: String? = nil) -> PlexTokenStore {
        let box = Box(user: user, server: server)
        return PlexTokenStore(
            userToken: { box.get(\.user) },
            setUserToken: { box.set(\.user, $0) },
            serverToken: { box.get(\.server) },
            setServerToken: { box.set(\.server, $0) }
        )
    }

    private static func read(_ account: String) -> String? {
        do {
            return try Keychain.string(account: account)
        } catch {
            logger.error("Failed to read a Plex token: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func write(_ value: String?, _ account: String) {
        do {
            if let value {
                try Keychain.set(value, account: account)
            } else {
                try Keychain.remove(account: account)
            }
        } catch {
            logger.error("Failed to save a Plex token: \(error.localizedDescription, privacy: .public)")
        }
    }

    private final class Box: @unchecked Sendable {
        struct Values {
            var user: String?
            var server: String?
        }
        private let lock = NSLock()
        private var values: Values

        init(user: String?, server: String?) { values = Values(user: user, server: server) }

        func get(_ key: KeyPath<Values, String?>) -> String? { lock.withLock { values[keyPath: key] } }
        func set(_ key: WritableKeyPath<Values, String?>, _ value: String?) { lock.withLock { values[keyPath: key] = value } }
    }
}
