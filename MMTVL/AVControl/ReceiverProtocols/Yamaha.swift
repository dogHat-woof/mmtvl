import Foundation

/// Yamaha 2010–2020 (YNCA, M7h *Receiver protocols*; **unverified**: the spec is dealer-only, from the ynca
/// library's notes). 9600 8N1 (**unverified**), CR LF. `@SUBUNIT:FUNC=VALUE`, queries `=?`. Volume in dB.
/// `@UNDEFINED` and `@RESTRICTED` are errors (ignored).
nonisolated struct YamahaProtocol: ReceiverProtocol {
    var brand: ReceiverBrand { .yamaha }
    var serial: SerialSettings { .baud9600 }
    var terminator: [UInt8] { [ReceiverLine.cr, ReceiverLine.lf] }
    var lineDelimiters: Set<UInt8> { [ReceiverLine.cr, ReceiverLine.lf] }
    /// L17, *Receiver protocols* "Network port".
    var networkPort: UInt16 { 50000 }
    /// **Unverified.**
    var minimumGap: Duration { .milliseconds(100) }

    func encode(_ command: ReceiverCommand) -> [UInt8] {
        switch command {
        case .powerOn: frame("@MAIN:PWR=On")
        case .powerOff: frame("@MAIN:PWR=Standby")
        case .queryPower: frame("@MAIN:PWR=?")
        case .volumeUp: frame("@MAIN:VOL=Up")
        case .volumeDown: frame("@MAIN:VOL=Down")
        case .queryVolume: frame("@MAIN:VOL=?")
        case .mute(let on): frame(on ? "@MAIN:MUTE=On" : "@MAIN:MUTE=Off")
        case .queryMute: frame("@MAIN:MUTE=?")
        }
    }

    func parse(line: String) -> ReceiverStatus? {
        let line = ReceiverLine.trimmed(line)
        if let value = ReceiverLine.value(after: "@MAIN:PWR=", in: line) {
            switch value {
            case "On": return .power(true)
            case "Standby": return .power(false)
            default: return nil
            }
        }
        if let value = ReceiverLine.value(after: "@MAIN:MUTE=", in: line) {
            // "Att -20 dB" / "Att -40 dB" are partial mutes: still muted.
            if value == "Off" { return .muted(false) }
            return value == "On" || value.hasPrefix("Att") ? .muted(true) : nil
        }
        if let value = ReceiverLine.value(after: "@MAIN:VOL=", in: line) {
            return ReceiverLine.decibels(value)
        }
        return nil
    }
}
