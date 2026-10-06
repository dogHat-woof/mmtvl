import Foundation

nonisolated enum VolumeAction: String, Codable, Sendable { case up, down, mute }

/// Phone → Mac. One JSON object per WebSocket text frame, discriminated by `"type"`.
nonisolated enum ClientMessage: Equatable, Sendable {
    case hello(token: String)
    case pair(code: String, name: String)
    case command(RemoteCommand)
    case textBegin
    case text(String)
    case submit
    case volume(VolumeAction)

    /// nil for malformed JSON, an unknown type, a missing field or an unknown command/action.
    static func decode(_ data: Data) -> ClientMessage? {
        guard let wire = try? JSONDecoder().decode(RemoteWireMessage.self, from: data) else { return nil }
        switch wire.type {
        case "hello":
            return wire.token.map { .hello(token: $0) }
        case "pair":
            guard let code = wire.code, let name = wire.name else { return nil }
            return .pair(code: code, name: name)
        case "command":
            return wire.command.flatMap(RemoteCommand.init(rawValue:)).map { .command($0) }
        case "textBegin":
            return .textBegin
        case "text":
            return wire.value.map { .text($0) }
        case "submit":
            return .submit
        case "volume":
            return wire.action.flatMap(VolumeAction.init(rawValue:)).map { .volume($0) }
        default:
            return nil
        }
    }
}

/// Mac → phone.
nonisolated enum ServerMessage: Equatable, Sendable {
    case welcome
    case authFailed
    case paired(token: String)
    case pairFailed(String)
    case status(frontApp: String, launcherActive: Bool)
    case toast(String)
    /// level 0…1; nil level = unknown (volume keys were sent).
    case volume(level: Double?, muted: Bool?)

    /// One JSON object, sorted keys, nil fields omitted.
    func encoded() -> Data {
        var wire: RemoteWireMessage
        switch self {
        case .welcome:
            wire = RemoteWireMessage(type: "welcome")
        case .authFailed:
            wire = RemoteWireMessage(type: "authFailed")
        case .paired(let token):
            wire = RemoteWireMessage(type: "paired")
            wire.token = token
        case .pairFailed(let message):
            wire = RemoteWireMessage(type: "pairFailed")
            wire.message = message
        case .status(let frontApp, let launcherActive):
            wire = RemoteWireMessage(type: "status")
            wire.frontApp = frontApp
            wire.launcherActive = launcherActive
        case .toast(let message):
            wire = RemoteWireMessage(type: "toast")
            wire.message = message
        case .volume(let level, let muted):
            wire = RemoteWireMessage(type: "volume")
            wire.level = level
            wire.muted = muted
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(wire)) ?? Data()
    }
}

/// The wire format for both directions. Synthesized `Codable` omits nil optionals.
nonisolated private struct RemoteWireMessage: Codable {
    var type: String
    var token: String?
    var code: String?
    var name: String?
    var command: String?
    var value: String?
    var action: String?
    var message: String?
    var frontApp: String?
    var launcherActive: Bool?
    var level: Double?
    var muted: Bool?
}
