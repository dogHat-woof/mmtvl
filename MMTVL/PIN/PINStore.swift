import os

/// The launcher PIN (D20, L7), stored as-is in the Keychain. Closures, like `SettingsEnvironment`, so tests can fake it.
struct PINStore {
    static let account = "launcher-pin"
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "PIN")

    /// nil when no PIN is set. Keychain errors are logged and read as "no PIN".
    var load: () -> String?
    var save: (String) throws -> Void
    var remove: () throws -> Void

    static let keychain = PINStore(
        load: {
            do {
                return try Keychain.string(account: account)
            } catch {
                logger.error("Failed to read the PIN: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        },
        save: { try Keychain.set($0, account: account) },
        remove: { try Keychain.remove(account: account) }
    )

    /// Tests.
    static func inMemory(_ initial: String? = nil) -> PINStore {
        let box = Box(initial)
        return PINStore(
            load: { box.value },
            save: { box.value = $0 },
            remove: { box.value = nil }
        )
    }

    private final class Box {
        var value: String?
        init(_ value: String?) { self.value = value }
    }
}
