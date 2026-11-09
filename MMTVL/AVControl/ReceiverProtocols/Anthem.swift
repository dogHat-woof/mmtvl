import Foundation

/// Anthem MRX/AVM (M7h *Receiver protocols*; **unverified**, from the RTI driver page). 115200 8N1 (**unverified**).
/// Commands end in `;` (so do replies). Zone 1 only. Volume in dB. Errors `!R…` are ignored.
nonisolated struct AnthemProtocol: ReceiverProtocol {
    var brand: ReceiverBrand { .anthem }
    var serial: SerialSettings { .baud115200 }
    var terminator: [UInt8] { Array(";".utf8) }
    var lineDelimiters: Set<UInt8> { [UInt8(ascii: ";"), ReceiverLine.cr, ReceiverLine.lf] }
    /// L17, *Receiver protocols* "Network port".
    var networkPort: UInt16 { 14999 }
    /// **Unverified** (the source names no gap).
    var minimumGap: Duration { .milliseconds(50) }

    func encode(_ command: ReceiverCommand) -> [UInt8] {
        switch command {
        case .powerOn: frame("Z1POW1")
        case .powerOff: frame("Z1POW0")
        case .queryPower: frame("Z1POW?")
        case .volumeUp: frame("Z1VUP")
        case .volumeDown: frame("Z1VDN")
        case .queryVolume: frame("Z1VOL?")
        case .mute(let on): frame(on ? "Z1MUT1" : "Z1MUT0")
        case .queryMute: frame("Z1MUT?")
        }
    }

    func parse(line: String) -> ReceiverStatus? {
        let line = ReceiverLine.trimmed(line).trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        if let value = ReceiverLine.value(after: "Z1POW", in: line) {
            switch value {
            case "1": return .power(true)
            case "0": return .power(false)
            default: return nil
            }
        }
        if let value = ReceiverLine.value(after: "Z1MUT", in: line) {
            switch value {
            case "1": return .muted(true)
            case "0": return .muted(false)
            default: return nil
            }
        }
        if let value = ReceiverLine.value(after: "Z1VOL", in: line) {
            return ReceiverLine.decibels(value)
        }
        return nil
    }
}
