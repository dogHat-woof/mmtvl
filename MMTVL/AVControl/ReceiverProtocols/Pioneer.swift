import Foundation

/// Pioneer before 2016 (M7h, *Receiver protocols*; verified on the VSX-01TXH, 2026-11-06). 9600 8N1, null-modem,
/// CR-terminated; replies end in CR LF. Volume `VOLnn` (00–93, 81 = 0 dB) or, on newer models, `VOLnnn` (000–185,
/// 161 = 0 dB, half-dB steps). Power `PWR0` = on, `PWR1` = off; mute `MUT0` = muted, `MUT1` = not.
/// Step 1: a reply can come after garbage bytes (`P\xff\xff\xff\xffPWR0`), and the receiver sends lines not in the
/// protocol (`SR0219`, `LM219`): the parser looks for a known prefix inside the line and ignores the rest.
nonisolated struct PioneerProtocol: ReceiverProtocol {
    var brand: ReceiverBrand { .pioneer }
    var serial: SerialSettings { .baud9600 }
    var terminator: [UInt8] { [ReceiverLine.cr] }
    var lineDelimiters: Set<UInt8> { [ReceiverLine.cr, ReceiverLine.lf] }
    /// L17, *Receiver protocols* "Network port" (**unverified**).
    var networkPort: UInt16 { 23 }
    var networkFallbackPorts: [UInt16] { [8102] }
    var minimumGap: Duration { .milliseconds(100) }
    var wakeRule: ReceiverWakeRule {
        ReceiverWakeRule(onOpen: [ReceiverLine.cr], powerOnCount: 2, powerOnRepeatGap: .milliseconds(100))
    }

    func encode(_ command: ReceiverCommand) -> [UInt8] {
        switch command {
        case .powerOn: frame("PO")
        case .powerOff: frame("PF")
        case .queryPower: frame("?P")
        case .volumeUp: frame("VU")
        case .volumeDown: frame("VD")
        case .queryVolume: frame("?V")
        case .mute(let on): frame(on ? "MO" : "MF")
        case .queryMute: frame("?M")
        }
    }

    func parse(line: String) -> ReceiverStatus? {
        let line = ReceiverLine.trimmed(line)
        if let digits = Self.digits(after: "PWR", in: line), digits.count == 1 {
            return .power(digits == "0")
        }
        if let digits = Self.digits(after: "MUT", in: line), digits.count == 1 {
            return .muted(digits == "0")
        }
        if let digits = Self.digits(after: "VOL", in: line), let raw = Int(digits) {
            switch digits.count {
            case 2: return .volume(raw: raw, dB: raw == 0 ? ReceiverLine.minimumDB : Double(raw - 81))
            case 3: return .volume(raw: raw, dB: raw == 0 ? ReceiverLine.minimumDB : Double(raw - 161) / 2)
            default: return nil
            }
        }
        return nil
    }

    /// The digits that end the line right after the last `prefix` in it (nil if anything else follows).
    private static func digits(after prefix: String, in line: String) -> Substring? {
        guard let range = line.range(of: prefix, options: .backwards) else { return nil }
        let rest = line[range.upperBound...]
        return ReceiverLine.isDigits(rest) ? rest : nil
    }
}
