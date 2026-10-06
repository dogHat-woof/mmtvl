import Foundation
import Security

/// Generic passwords in the legacy (file-based) login keychain (D9).
/// Never set `kSecUseDataProtectionKeychain`: without a provisioning profile it fails with -34018.
nonisolated enum Keychain {
    static let service = "dev.mmtvl.launcher"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    /// nil when there is no item.
    static func string(account: String, service: String = service) throws -> String? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Updates the item if it exists, else adds it.
    static func set(_ value: String, account: String, service: String = service) throws {
        let query = baseQuery(account: account, service: service)
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// No error when there is no item.
    static func remove(account: String, service: String = service) throws {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
