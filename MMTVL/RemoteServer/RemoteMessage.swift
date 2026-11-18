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
    /// M7b L11: the trackpad.
    case pointer(PointerAction)

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
        case "pointer":
            return wire.delta.map { .pointer(.move(dx: $0.dx, dy: $0.dy)) }
        case "scroll":
            return wire.delta.map { .pointer(.scroll(dx: $0.dx, dy: $0.dy)) }
        case "click":
            return wire.button.flatMap(PointerButton.init(rawValue:)).map { .pointer(.click($0)) }
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
    /// Re-review L1: `codeLocked`, the typed code is off for this pairing (too many wrong codes); the page says to scan
    /// the QR code and hides the code form.
    case pairFailed(String, codeLocked: Bool = false)
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
        case .pairFailed(let message, let codeLocked):
            wire = RemoteWireMessage(type: "pairFailed")
            wire.message = message
            if codeLocked { wire.codeLocked = true }
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
    /// M7b L11: trackpad deltas (CSS pixels) and click button.
    var dx: Double?
    var dy: Double?
    var button: String?
    /// Re-review L1: in pairFailed, only when true.
    var codeLocked: Bool?

    /// Both deltas present, finite and at most `PointerMath.maxDelta` in magnitude.
    var delta: (dx: Double, dy: Double)? {
        guard let dx, let dy,
              dx.isFinite, dy.isFinite,
              abs(dx) <= PointerMath.maxDelta, abs(dy) <= PointerMath.maxDelta
        else { return nil }
        return (dx, dy)
    }
}
