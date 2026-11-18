import CryptoKit
import Foundation
import os
import Security

/// The 4-digit code shown on Settings → Phone Remote → Pair a Phone (L3), and the QR code's secret.
nonisolated struct PairingCode: Equatable, Sendable {
    static let lifetime: TimeInterval = 600
    /// Wrong codes before the code changes (the TV shows the new one).
    static let maxFailures = 5
    /// Security (pre-release review, high): wrong codes in one pairing, whichever code they were for; at this many,
    /// pairing ends and Pair a Phone must be opened again. A guesser gets at most this many tries at 1 in 10,000.
    static let maxTotalFailures = 10

    /// 4 digits, "0000"…"9999".
    var code: String
    /// Security (pre-release review, high): 128 random bits, hex, in the QR code's link (`#pair=<secret>`); the page
    /// sends it like a typed code. The typed code is the fallback, under `maxTotalFailures`.
    var secret: String
    var expires: Date
    /// Wrong codes since the code last changed.
    var failures = 0
    /// Wrong codes in this pairing.
    var totalFailures = 0

    init(code: String, secret: String = PairingCode.makeSecret(), expires: Date, failures: Int = 0, totalFailures: Int = 0) {
        self.code = code
        self.secret = secret
        self.expires = expires
        self.failures = failures
        self.totalFailures = totalFailures
    }

    enum Check: Equatable { case accepted, rejected, rotated(PairingCode), expired, ended }

    /// The code or the secret: accepted. Else a failure (`fail`).
    mutating func check(_ attempt: String, now: Date, makeCode: () -> String) -> Check {
        guard now < expires else { return .expired }
        if attempt == code || Self.constantTimeEqual(attempt, secret) { return .accepted }
        return fail(now: now, makeCode: makeCode)
    }

    /// A wrong code, or an attempt not checked (too soon after the last one): failures += 1. At `maxTotalFailures`
    /// returns .ended (the caller ends pairing); at `maxFailures` returns (and becomes) a fresh code from makeCode,
    /// same secret, expiry and total.
    mutating func fail(now: Date, makeCode: () -> String) -> Check {
        guard now < expires else { return .expired }
        failures += 1
        totalFailures += 1
        if totalFailures >= Self.maxTotalFailures { return .ended }
        guard failures >= Self.maxFailures else { return .rejected }
        self = PairingCode(code: makeCode(), secret: secret, expires: expires, totalFailures: totalFailures)
        return .rotated(self)
    }

    /// `SystemRandomNumberGenerator`, the system's cryptographic generator.
    static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// Tests pass a seeded generator.
    static func random<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String(format: "%04d", Int.random(in: 0...9999, using: &generator))
    }

    /// 16 bytes from SecRandomCopyBytes, lowercase hex (32 characters).
    static func makeSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Doesn't stop at the first difference. An empty `b` never matches.
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard !y.isEmpty, x.count == y.count else { return false }
        var difference: UInt8 = 0
        for index in x.indices { difference |= x[index] ^ y[index] }
        return difference == 0
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
