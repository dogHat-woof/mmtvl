import Foundation

/// Denon / Marantz 2010+ (M7h *Receiver protocols*; **unverified** on hardware). 9600 8N1, straight cable, CR.
/// Volume `MVnn` (80 = 0 dB, 00 = −∞) or `MVnnn` (half dB: `MV805` = +0.5 dB). Other lines (`MVMAX 98`, zones) are
/// ignored. Wait 1 s after `PWON`.
nonisolated struct DenonProtocol: ReceiverProtocol {
    var brand: ReceiverBrand { .denon }
    var serial: SerialSettings { .baud9600 }
    var terminator: [UInt8] { [ReceiverLine.cr] }
    var lineDelimiters: Set<UInt8> { [ReceiverLine.cr, ReceiverLine.lf] }
    /// L17, *Receiver protocols* "Network port".
    var networkPort: UInt16 { 23 }
    /// **Unverified.**
    var minimumGap: Duration { .milliseconds(50) }
    var wakeRule: ReceiverWakeRule { ReceiverWakeRule(pauseAfterPowerOn: .seconds(1)) }

    func encode(_ command: ReceiverCommand) -> [UInt8] {
        switch command {
        case .powerOn: frame("PWON")
        case .powerOff: frame("PWSTANDBY")
        case .queryPower: frame("PW?")
        case .volumeUp: frame("MVUP")
        case .volumeDown: frame("MVDOWN")
        case .queryVolume: frame("MV?")
        case .mute(let on): frame(on ? "MUON" : "MUOFF")
        case .queryMute: frame("MU?")
        }
    }

    func parse(line: String) -> ReceiverStatus? {
        switch ReceiverLine.trimmed(line) {
        case "PWON": return .power(true)
        case "PWSTANDBY": return .power(false)
        case "MUON": return .muted(true)
        case "MUOFF": return .muted(false)
        case let line:
            guard let digits = ReceiverLine.value(after: "MV", in: line), ReceiverLine.isDigits(digits),
                  let raw = Int(digits) else { return nil }
            switch digits.count {
            case 2: return .volume(raw: raw, dB: raw == 0 ? ReceiverLine.minimumDB : Double(raw - 80))
            case 3: return .volume(raw: raw, dB: raw == 0 ? ReceiverLine.minimumDB : Double(raw) / 10 - 80)
            default: return nil
            }
        }
    }
}
