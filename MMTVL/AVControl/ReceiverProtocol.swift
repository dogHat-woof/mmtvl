import Foundation

/// `settings.json` `receiverBrand` (M7h D44, L11). Unknown values read as `.none`.
nonisolated enum ReceiverBrand: String, Codable, CaseIterable, Sendable {
    case none, pioneer, onkyo, denon, yamaha, anthem, nad

    /// The brand's codec; nil for `.none`.
    var codec: (any ReceiverProtocol)? {
        switch self {
        case .none: nil
        case .pioneer: PioneerProtocol()
        case .onkyo: OnkyoProtocol()
        case .denon: DenonProtocol()
        case .yamaha: YamahaProtocol()
        case .anthem: AnthemProtocol()
        case .nad: NADProtocol()
        }
    }

    /// Every brand with a codec, in the order Find Receiver tries them (L12).
    static var supported: [ReceiverBrand] { allCases.filter { $0 != .none } }
}

/// `settings.json` `receiverConnection` (D44). Unknown values read as `.serial`. Step 9c: `cec` is a receiver
/// reached over HDMI-CEC (`CECAudioSystem`, logical address 5); `receiverBrand` and the serial and network settings
/// aren't used then.
nonisolated enum ReceiverConnection: String, Codable, CaseIterable, Sendable {
    case serial, network, cec
}

/// Where `ReceiverController` reaches the receiver (D44, L11, L17).
nonisolated enum ReceiverLink: Equatable, Sendable {
    /// `receiverSerialPort`: a `/dev/cu.*` path, nil = the first USB serial port.
    case serial(path: String?)
    /// `receiverHost`, and `receiverNetworkPort` (nil = the brand's control ports, L17).
    case network(host: String, port: UInt16?)

    var isNetwork: Bool {
        if case .network = self { true } else { false }
    }

    /// L17: the waits between reconnect attempts; the last repeats. Serial: every 5 s (L11); network: 1, 2, 5, 10 s.
    var reconnectDelays: [Duration] {
        switch self {
        case .serial: [.seconds(5)]
        case .network: [.seconds(1), .seconds(2), .seconds(5), .seconds(10)]
        }
    }
}

/// L17: how a brand's bytes travel over TCP.
nonisolated enum ReceiverNetworkFraming: Equatable, Sendable {
    /// The serial bytes as they are.
    case plain
    /// Onkyo's eISCP: each message in a 16-byte header (`EISCP`, in `Onkyo.swift`).
    case eISCP
}

/// L11: what MMTVL asks a receiver to do. Queries change nothing (L12).
nonisolated enum ReceiverCommand: Hashable, Sendable {
    case powerOn, powerOff, queryPower
    case volumeUp, volumeDown, queryVolume
    case mute(Bool), queryMute

    var isQuery: Bool {
        switch self {
        case .queryPower, .queryVolume, .queryMute: true
        default: false
        }
    }

    var isPower: Bool { self == .powerOn || self == .powerOff }
}

/// L11: one fact a reply line (asked for or unsolicited) tells.
nonisolated enum ReceiverStatus: Equatable, Sendable {
    case power(Bool)
    /// `raw` is private to the brand: its own number as it sent it (Pioneer and Onkyo steps; Denon's `MVnn` or
    /// half-dB `MVnnn`, mixed; tenths of a dB for brands that report dB). It isn't comparable across brands, or
    /// even within one, and isn't a level: use `dB`. `dB` is nil when the brand doesn't report dB (Onkyo);
    /// `-.infinity` (`ReceiverLine.minimumDB`) at the bottom of the scale (Pioneer `VOL00`/`VOL000`, Denon `MV00`);
    /// otherwise finite and within `ReceiverLine.plausibleDB`.
    case volume(raw: Int, dB: Double?)
    case muted(Bool)

    enum Kind: Hashable, Sendable { case power, volume, muted }

    var kind: Kind {
        switch self {
        case .power: .power
        case .volume: .volume
        case .muted: .muted
        }
    }
}

/// L11: the serial line settings a brand uses (no flow control for any of them).
nonisolated struct SerialSettings: Equatable, Sendable {
    enum Parity: Sendable { case none, even, odd }

    var baud: Int
    var dataBits = 8
    var parity = Parity.none
    var stopBits = 1

    static let baud9600 = SerialSettings(baud: 9600)
    static let baud115200 = SerialSettings(baud: 115_200)
}

/// L11: how a brand wakes up.
nonisolated struct ReceiverWakeRule: Equatable, Sendable {
    /// Sent once after the port opens, before the first command (Pioneer: a bare CR wakes its CPU, reply `R`).
    var onOpen: [UInt8] = []
    /// `powerOn` is sent this many times, `powerOnRepeatGap` apart (Pioneer: twice, 100 ms; from standby the first
    /// only wakes the CPU).
    var powerOnCount = 1
    var powerOnRepeatGap: Duration = .zero
    /// Nothing else is sent for this long after `powerOn` (Denon: 1 s).
    var pauseAfterPowerOn: Duration = .zero
}

/// L11: a vendor's codec. Pure; `ReceiverController` owns the transport, the queue and the gap.
nonisolated protocol ReceiverProtocol: Sendable {
    var brand: ReceiverBrand { get }
    var serial: SerialSettings { get }
    /// Ends every command sent.
    var terminator: [UInt8] { get }
    /// Bytes that end a reply line (any of them; empty lines are dropped).
    var lineDelimiters: Set<UInt8> { get }
    /// The least time between two commands.
    var minimumGap: Duration { get }
    var wakeRule: ReceiverWakeRule { get }
    /// L12: the read-only queries Test Connection and Find Receiver send (only queries, never a change).
    var probeQueries: [ReceiverCommand] { get }
    /// L17: the TCP control port, and ports tried after it when it refuses (Pioneer: 23, then 8102).
    var networkPort: UInt16 { get }
    var networkFallbackPorts: [UInt16] { get }
    /// L17: how commands and replies are framed over TCP (Onkyo: eISCP).
    var networkFraming: ReceiverNetworkFraming { get }
    func encode(_ command: ReceiverCommand) -> [UInt8]
    /// A status from one reply line, or nil for lines it doesn't know (errors, other zones, unsolicited extras).
    func parse(line: String) -> ReceiverStatus?
}

nonisolated extension ReceiverProtocol {
    var probeQueries: [ReceiverCommand] { [.queryPower, .queryVolume, .queryMute] }

    var wakeRule: ReceiverWakeRule { ReceiverWakeRule() }

    var networkFallbackPorts: [UInt16] { [] }

    var networkFraming: ReceiverNetworkFraming { .plain }

    /// L17: the ports to try, in order: `override` (`receiverNetworkPort`) alone, else the brand's.
    func networkPorts(override: UInt16?) -> [UInt16] {
        if let override { return [override] }
        return [networkPort] + networkFallbackPorts.filter { $0 != networkPort }
    }

    /// `text` + the terminator, as bytes.
    func frame(_ text: String) -> [UInt8] { Array(text.utf8) + terminator }
}

/// Shared parsing helpers.
nonisolated enum ReceiverLine {
    static let cr: UInt8 = 0x0D
    static let lf: UInt8 = 0x0A
    static let eof: UInt8 = 0x1A

    /// The line without surrounding whitespace, CR, LF, EOF (0x1A) or NUL.
    static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{1A}\u{0}")))
    }

    /// The rest of the line after `prefix`, when the line starts with it.
    static func value(after prefix: String, in line: String) -> Substring? {
        line.hasPrefix(prefix) ? line.dropFirst(prefix.count) : nil
    }

    static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "On"/"Off" (case-insensitive).
    static func onOff(_ text: Substring) -> Bool? {
        switch text.lowercased() {
        case "on": true
        case "off": false
        default: nil
        }
    }

    /// Step 10 security: dB a receiver can report (every brand's scale is within −100…+30). A reply outside it is
    /// ignored, so a hostile or garbled value (`Main.Volume=1e18`) never reaches an `Int` conversion.
    static let plausibleDB: ClosedRange<Double> = -100...30
    /// The bottom of the scale, where the receiver is silent (−∞ dB).
    static let minimumDB = -Double.infinity

    /// A dB value as `.volume(raw: tenths of a dB, dB:)`; nil when it isn't a number within `plausibleDB`.
    static func decibels(_ text: Substring) -> ReceiverStatus? {
        guard let dB = Double(text.trimmingCharacters(in: .whitespaces)), plausibleDB.contains(dB) else { return nil }
        return .volume(raw: Int((dB * 10).rounded()), dB: dB)
    }
}
