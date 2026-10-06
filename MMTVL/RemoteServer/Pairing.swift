import CryptoKit
import Foundation
import os
import Security

/// The 4-digit code shown on Settings → Phone Remote → Pair a Phone (L3).
nonisolated struct PairingCode: Equatable, Sendable {
    static let lifetime: TimeInterval = 600
    static let maxFailures = 5

    /// 4 digits, "0000"…"9999".
    var code: String
    var expires: Date
    var failures = 0

    enum Check: Equatable { case accepted, rejected, rotated(PairingCode), expired }

    /// Wrong code: failures += 1; at maxFailures returns (and becomes) a fresh code from makeCode, same expiry.
    mutating func check(_ attempt: String, now: Date, makeCode: () -> String) -> Check {
        guard now < expires else { return .expired }
        if attempt == code { return .accepted }
        failures += 1
        guard failures >= Self.maxFailures else { return .rejected }
        self = PairingCode(code: makeCode(), expires: expires)
        return .rotated(self)
    }

    static func random() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}

nonisolated struct PairedPhone: Codable, Equatable, Sendable {
    /// UUID string.
    var id: String
    /// From the page ("iPhone", "Android phone"), trimmed to 40 chars.
    var name: String
    /// SHA-256 hex of the token (L4).
    var tokenHash: String
    var pairedAt: Date
}

nonisolated enum PhoneToken {
    /// 32 bytes from SecRandomCopyBytes, base64url without padding.
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// CryptoKit SHA256, lowercase hex.
    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The paired phones (L4), a JSON array in one Keychain item. Closures like `PINStore`, so tests can use `.inMemory()`.
struct PairedPhoneStore {
    static let account = "phone-remote-phones"
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")

    /// Keychain errors / bad JSON → logged, [].
    var load: () -> [PairedPhone]
    var save: ([PairedPhone]) throws -> Void

    static let keychain = keychain(account: account)

    static func keychain(account: String, service: String = Keychain.service) -> PairedPhoneStore {
        PairedPhoneStore(
            load: {
                do {
                    guard let json = try Keychain.string(account: account, service: service) else { return [] }
                    return try decoder.decode([PairedPhone].self, from: Data(json.utf8))
                } catch {
                    logger.error("Failed to read paired phones: \(error.localizedDescription, privacy: .public)")
                    return []
                }
            },
            save: { phones in
                let data = try encoder.encode(phones)
                try Keychain.set(String(decoding: data, as: UTF8.self), account: account, service: service)
            }
        )
    }

    /// Tests.
    static func inMemory(_ initial: [PairedPhone] = []) -> PairedPhoneStore {
        let box = Box(initial)
        return PairedPhoneStore(load: { box.value }, save: { box.value = $0 })
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private final class Box {
        var value: [PairedPhone]
        init(_ value: [PairedPhone]) { self.value = value }
    }
}
