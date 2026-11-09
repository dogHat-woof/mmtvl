import Foundation

// M7h step 9 (reopened), L13: the only HDMI-CEC frames MMTVL sends, through the DisplayPort AUX tunnel
// (`CECTunnel`). Every frame comes from logical address 4 (playback 1, the address macOS's corercd already holds in
// the tunnel's mask); there's no public way to build another one. Step 14b's probe 2 sent each of these on the mini.
// Step 9c adds volume, power and the detection queries for an audio system (address 5, the receiver), and volume
// for the TV (address 0).

/// A CEC physical address, "2.3.0.0" (four nibbles). Pure.
nonisolated struct CECPhysicalAddress: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The two bytes as sent: 0x23, 0x00 for 2.3.0.0.
    let high: UInt8
    let low: UInt8

    /// nil for F.F.F.F (no address) and 0.0.0.0 (the TV's own; a source never has it).
    init?(high: UInt8, low: UInt8) {
        guard !(high == 0xFF && low == 0xFF), !(high == 0 && low == 0) else { return nil }
        self.high = high
        self.low = low
    }

    var description: String {
        "\(high >> 4).\(high & 0xF).\(low >> 4).\(low & 0xF)"
    }
}

/// A device MMTVL talks to directly (its logical address). Pure.
nonisolated enum CECDevice: UInt8, Equatable, Sendable {
    case tv = 0
    /// The receiver (an HDMI-CEC audio system).
    case audioSystem = 5

    /// For logs ("the TV", "the receiver").
    var logName: String {
        switch self {
        case .tv: "the TV"
        case .audioSystem: "the receiver"
        }
    }
}

/// The User Control Pressed keys MMTVL sends for volume (CEC 1.4, UI command codes). Pure.
nonisolated enum CECVolumeKey: UInt8, Equatable, Sendable {
    case volumeUp = 0x41
    case volumeDown = 0x42
    case mute = 0x43
}

/// One frame MMTVL may send. Pure.
nonisolated struct CECFrame: Equatable, Sendable, CustomStringConvertible {
    /// Playback device 1: the address MMTVL sends from (never claimed by MMTVL; corercd holds it).
    static let initiator: UInt8 = 4

    let bytes: [UInt8]
    /// For logs ("Standby to all").
    let name: String

    private init(_ bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    /// `4F:36`: Standby to all. Turns off the TV and a receiver that follows CEC (a TV-only `40:36` left the receiver
    /// on, and a receiver left on re-routes away from the Mac when CEC wakes the TV; probe 2).
    static let standbyAll = CECFrame([0x4F, 0x36], name: "Standby to all")
    /// `40:04`: Image View On, to the TV.
    static let imageViewOn = CECFrame([0x40, 0x04], name: "Image View On")
    /// `40:8F`: Give Device Power Status, to the TV (it answers `04:90:<status>`).
    static let givePowerStatus = CECFrame([0x40, 0x8F], name: "Give Device Power Status")

    /// `4F:82:<PA>`: Active Source, to all.
    static func activeSource(_ address: CECPhysicalAddress) -> CECFrame {
        CECFrame([0x4F, 0x82, address.high, address.low], name: "Active Source \(address)")
    }

    // MARK: Step 9c: volume, the receiver's power, detection

    /// `x5:8F` (Give Device Power Status) to `device`: the TV's (`givePowerStatus`) or the receiver's (`45:8F` →
    /// `54:90:<s>`, probe 2).
    static func givePowerStatus(to device: CECDevice) -> CECFrame {
        switch device {
        case .tv: givePowerStatus
        case .audioSystem: CECFrame([0x45, 0x8F], name: "Give Device Power Status to the receiver")
        }
    }

    /// `45:44:<key>` / `40:44:<key>`: User Control Pressed, Volume Up, Volume Down or Mute. Always followed by
    /// `released(to:)` (probe 2: one press steps the Pioneer one notch).
    static func volumeKey(_ key: CECVolumeKey, to device: CECDevice) -> CECFrame {
        let name = switch key {
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        }
        return CECFrame([0x40 | device.rawValue, 0x44, key.rawValue], name: "\(name) to \(device.logName)")
    }

    /// `45:45` / `40:45`: User Control Released.
    static func released(to device: CECDevice) -> CECFrame {
        CECFrame([0x40 | device.rawValue, 0x45], name: "Released to \(device.logName)")
    }

    /// `45:36`: Standby to the receiver alone (with a TV that isn't on HDMI-CEC; a CEC TV's `4F:36` covers it).
    static let audioSystemStandby = CECFrame([0x45, 0x36], name: "Standby to the receiver")
    /// `45:44:6D`: User Control Pressed, Power On Function (then `released(to: .audioSystem)`). Unverified on the
    /// Pioneer, which followed the TV on in probe 2.
    static let audioSystemPowerOn = CECFrame([0x45, 0x44, 0x6D], name: "Power On Function to the receiver")
    /// `45:71`: Give Audio Status (`x:7A:<status>` back; the Pioneer doesn't answer).
    static let giveAudioStatus = CECFrame([0x45, 0x71], name: "Give Audio Status")
    /// `45:46`: Give OSD Name (`54:47:<name>`, "VSX-01TXH" in probe 2).
    static let giveOSDName = CECFrame([0x45, 0x46], name: "Give OSD Name")

    /// One kind of frame the tunnel may send: from address 4 to `destination`, with `opcode` and exactly
    /// `operandCount` operand bytes; with `firstOperands`, the first operand must be one of them.
    struct Allowed: Equatable, Sendable {
        var destination: UInt8
        var opcode: UInt8
        var operandCount: Int
        /// nil: any value (Active Source's physical address).
        var firstOperands: Set<UInt8>? = nil

        func matches(_ bytes: [UInt8]) -> Bool {
            guard bytes.count >= 2, destination == bytes[0] & 0x0F, opcode == bytes[1],
                  operandCount == bytes.count - 2
            else { return false }
            guard let firstOperands else { return true }
            return bytes.count >= 3 && firstOperands.contains(bytes[2])
        }
    }

    /// The tunnel sends nothing else (`CECTunnel` checks every frame against it).
    static let allowed: [Allowed] = [
        Allowed(destination: 0xF, opcode: 0x36, operandCount: 0),   // Standby to all
        Allowed(destination: 0x0, opcode: 0x04, operandCount: 0),   // Image View On
        Allowed(destination: 0x0, opcode: 0x8F, operandCount: 0),   // Give Device Power Status
        Allowed(destination: 0xF, opcode: 0x82, operandCount: 2),   // Active Source <PA>
        // Step 9c, the receiver (audio system, 5).
        Allowed(destination: 0x5, opcode: 0x44, operandCount: 1, firstOperands: [0x41, 0x42, 0x43, 0x6D]),   // Pressed
        Allowed(destination: 0x5, opcode: 0x45, operandCount: 0),   // Released
        Allowed(destination: 0x5, opcode: 0x36, operandCount: 0),   // Standby
        Allowed(destination: 0x5, opcode: 0x71, operandCount: 0),   // Give Audio Status
        Allowed(destination: 0x5, opcode: 0x8F, operandCount: 0),   // Give Device Power Status
        Allowed(destination: 0x5, opcode: 0x46, operandCount: 0),   // Give OSD Name
        // Step 9c, the TV's volume (0).
        Allowed(destination: 0x0, opcode: 0x44, operandCount: 1, firstOperands: [0x41, 0x42, 0x43]),   // Pressed
        Allowed(destination: 0x0, opcode: 0x45, operandCount: 0),   // Released
    ]

    /// From address 4 and in `allowed`. Pure.
    static func isAllowed(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2, bytes[0] >> 4 == initiator else { return false }
        return allowed.contains { $0.matches(bytes) }
    }

    /// The sending logical address (the header's high nibble).
    var initiatorAddress: UInt8 { bytes[0] >> 4 }

    /// `0x3003`'s value that sends this frame: length − 1, the retries, and the send bit.
    func txInfo(retries: UInt8) -> UInt8 {
        UInt8(bytes.count - 1) | ((retries & 0x7) << 4) | 0x80
    }

    /// "4F:36"
    var hex: String { Self.hex(bytes) }

    var description: String { "\(hex) (\(name))" }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// The answer a query waits for: a frame from `initiator` to us (address 4) with `opcode` (or, with
/// `acceptsBroadcast`, to all). Pure.
nonisolated struct CECReplyPattern: Equatable, Sendable {
    var initiator: UInt8
    var opcode: UInt8
    var acceptsBroadcast = false

    /// Report Power Status from the TV, the answer to Give Device Power Status.
    static let reportPowerStatus = CECReplyPattern(initiator: 0x0, opcode: 0x90)
    /// Step 9c: Report Power Status from the receiver (`54:90:<s>`).
    static let audioSystemPowerStatus = CECReplyPattern(initiator: 0x5, opcode: 0x90)
    /// Step 9c: Set OSD Name from the receiver (`54:47:<name>`).
    static let audioSystemOSDName = CECReplyPattern(initiator: 0x5, opcode: 0x47)
    /// Step 9c: Report Audio Status from the receiver, to us or to all (`54:7A` / `5F:7A`).
    static let reportAudioStatus = CECReplyPattern(initiator: 0x5, opcode: 0x7A, acceptsBroadcast: true)

    /// The Report Power Status a Give Device Power Status to `device` waits for.
    static func powerStatus(from device: CECDevice) -> CECReplyPattern {
        switch device {
        case .tv: reportPowerStatus
        case .audioSystem: audioSystemPowerStatus
        }
    }

    func matches(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2, bytes[0] >> 4 == initiator, bytes[1] == opcode else { return false }
        let destination = bytes[0] & 0x0F
        return destination == CECFrame.initiator || (acceptsBroadcast && destination == 0xF)
    }
}

/// `Report Power Status` (`<TV>4:90:<s>`, `54:90:<s>`). Pure.
nonisolated enum CECPowerStatus: UInt8, Equatable, Sendable {
    case on = 0
    case standby = 1
    case standbyToOn = 2
    case onToStandby = 3

    /// 2 (standby → on) counts as on; 3 (on → standby) as off.
    var isOn: Bool { self == .on || self == .standbyToOn }

    /// The answer to our query: from `pattern`'s device (the TV by default) to us (4), opcode 0x90, a known
    /// status. nil for anything else.
    static func parseReply(_ bytes: [UInt8], pattern: CECReplyPattern = .reportPowerStatus) -> CECPowerStatus? {
        guard bytes.count >= 3, pattern.opcode == 0x90, pattern.matches(bytes) else { return nil }
        return CECPowerStatus(rawValue: bytes[2])
    }
}

/// Step 9c: `Report Audio Status` (`x:7A:<status>`): bit 7 mute, bits 0–6 the volume 0…100 (0x7F unknown). Pure.
nonisolated struct CECAudioStatus: Equatable, Sendable {
    var muted: Bool
    /// 0…100; nil when the receiver says it's unknown (0x7F) or sends a reserved value (101…126).
    var volume: Int?

    init(muted: Bool, volume: Int?) {
        self.muted = muted
        self.volume = volume
    }

    init(byte: UInt8) {
        muted = byte & 0x80 != 0
        let level = Int(byte & 0x7F)
        volume = level <= 100 ? level : nil
    }

    /// The receiver's Report Audio Status, to us or to all; nil for anything else.
    static func parseReply(_ bytes: [UInt8]) -> CECAudioStatus? {
        guard bytes.count == 3, CECReplyPattern.reportAudioStatus.matches(bytes) else { return nil }
        return CECAudioStatus(byte: bytes[2])
    }
}

/// Step 9c: `Set OSD Name` (`54:47:<name>`). Pure.
nonisolated enum CECOSDName {
    /// The name's printable ASCII characters (at most 14, the spec's limit), trimmed; nil when none or not the
    /// receiver's Set OSD Name to us.
    static func parseReply(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 3, CECReplyPattern.audioSystemOSDName.matches(bytes) else { return nil }
        let printable = bytes.dropFirst(2).prefix(14).filter { (0x20...0x7E).contains($0) }
        let name = String(decoding: printable, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
