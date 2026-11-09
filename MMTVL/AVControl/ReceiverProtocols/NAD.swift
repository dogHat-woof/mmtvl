import Foundation

/// NAD, protocol v2 (M7h *Receiver protocols*; **unverified**, from nad-serial). 115200 8N1, no flow control
/// (**unverified**). Each command is sent between CRs (a leading CR); replies end in CR LF. Volume in dB.
nonisolated struct NADProtocol: ReceiverProtocol {
    var brand: ReceiverBrand { .nad }
    var serial: SerialSettings { .baud115200 }
    var terminator: [UInt8] { [ReceiverLine.cr] }
    var lineDelimiters: Set<UInt8> { [ReceiverLine.cr, ReceiverLine.lf] }
    /// L17, *Receiver protocols* "Network port" (**unverified**).
    var networkPort: UInt16 { 23 }
    /// **Unverified** (the source names no gap).
    var minimumGap: Duration { .milliseconds(50) }

    func encode(_ command: ReceiverCommand) -> [UInt8] {
        let text = switch command {
        case .powerOn: "Main.Power=On"
        case .powerOff: "Main.Power=Off"
        case .queryPower: "Main.Power?"
        case .volumeUp: "Main.Volume+"
        case .volumeDown: "Main.Volume-"
        case .queryVolume: "Main.Volume?"
        case .mute(let on): on ? "Main.Mute=On" : "Main.Mute=Off"
        case .queryMute: "Main.Mute?"
        }
        return [ReceiverLine.cr] + frame(text)
    }

    func parse(line: String) -> ReceiverStatus? {
        let line = ReceiverLine.trimmed(line)
        if let value = ReceiverLine.value(after: "Main.Power=", in: line) {
            return ReceiverLine.onOff(value).map { .power($0) }
        }
        if let value = ReceiverLine.value(after: "Main.Mute=", in: line) {
            return ReceiverLine.onOff(value).map { .muted($0) }
        }
        if let value = ReceiverLine.value(after: "Main.Volume=", in: line) {
            return ReceiverLine.decibels(value)
        }
        return nil
    }
}
