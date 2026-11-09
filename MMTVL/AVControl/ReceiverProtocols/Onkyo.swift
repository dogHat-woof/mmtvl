import Foundation

/// Onkyo / Integra / Pioneer 2016+ (ISCP, M7h *Receiver protocols*; **unverified** on hardware). 9600 8N1, straight
/// cable. Sent: `!1` + command + CR. Replies `!1…` end in EOF (0x1A), some with CR/LF too. Volume `MVLhh` is hex
/// (00–64 on most models), a level rather than dB.
nonisolated struct OnkyoProtocol: ReceiverProtocol {
    var brand: ReceiverBrand { .onkyo }
    var serial: SerialSettings { .baud9600 }
    var terminator: [UInt8] { [ReceiverLine.cr] }
    var lineDelimiters: Set<UInt8> { [ReceiverLine.eof, ReceiverLine.cr, ReceiverLine.lf] }
    /// L17, *Receiver protocols* "Network port".
    var networkPort: UInt16 { 60128 }
    /// eISCP: each message in a 16-byte header (`EISCP` below); one client at a time.
    var networkFraming: ReceiverNetworkFraming { .eISCP }
    /// "More than 50 ms between messages."
    var minimumGap: Duration { .milliseconds(60) }

    func encode(_ command: ReceiverCommand) -> [UInt8] {
        switch command {
        case .powerOn: frame("!1PWR01")
        case .powerOff: frame("!1PWR00")
        case .queryPower: frame("!1PWRQSTN")
        case .volumeUp: frame("!1MVLUP")
        case .volumeDown: frame("!1MVLDOWN")
        case .queryVolume: frame("!1MVLQSTN")
        case .mute(let on): frame(on ? "!1AMT01" : "!1AMT00")
        case .queryMute: frame("!1AMTQSTN")
        }
    }

    func parse(line: String) -> ReceiverStatus? {
        let line = ReceiverLine.trimmed(line)
        // The start marker can follow garbage bytes.
        guard let start = line.range(of: "!1", options: .backwards) else { return nil }
        let message = String(line[start.upperBound...])
        if let value = ReceiverLine.value(after: "PWR", in: message) {
            switch value {
            case "01": return .power(true)
            case "00": return .power(false)
            default: return nil
            }
        }
        if let value = ReceiverLine.value(after: "AMT", in: message) {
            switch value {
            case "01": return .muted(true)
            case "00": return .muted(false)
            default: return nil
            }
        }
        if let value = ReceiverLine.value(after: "MVL", in: message), value.count == 2,
           value.allSatisfy(\.isHexDigit), let raw = Int(value, radix: 16) {
            return .volume(raw: raw, dB: nil)
        }
        return nil
    }
}

/// L17: Onkyo's eISCP, ISCP over TCP (Onkyo ISCP v1.15). Each message travels in a 16-byte header: `ISCP`, the
/// header size (16) and the data size, both 32-bit big-endian, the version (0x01) and 3 reserved bytes; the data is
/// the ISCP message as sent over serial (`!1` + command + CR; some receivers want CR LF or EOF, we keep CR).
/// **Unverified** on hardware (no networked receiver here).
nonisolated enum EISCP {
    static let magic: [UInt8] = Array("ISCP".utf8)
    static let headerSize = 16
    static let version: UInt8 = 0x01
    /// A larger data size is noise: the deframer skips the header and looks for the next one.
    static let maximumDataSize = 4096
    /// Headers larger than this are noise too (the header size field is 16 in practice).
    static let maximumHeaderSize = 64

    /// `message` behind the header.
    static func frame(_ message: [UInt8]) -> [UInt8] {
        magic + bigEndian(UInt32(headerSize)) + bigEndian(UInt32(message.count)) + [version, 0, 0, 0] + message
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// Takes received bytes, in any pieces, and returns each whole message's data (a reply split across reads waits
    /// for the rest; several in one read come out in order). Bytes before a header are dropped. Pure.
    struct Deframer: Sendable {
        private var buffer: [UInt8] = []

        init() {}

        mutating func append(_ bytes: some Sequence<UInt8>) -> [[UInt8]] {
            buffer.append(contentsOf: bytes)
            var messages: [[UInt8]] = []
            while true {
                guard let start = Self.find(magic, in: buffer) else {
                    // Keep a possible partial "ISCP" at the end.
                    buffer = Array(buffer.suffix(magic.count - 1))
                    return messages
                }
                if start > 0 { buffer.removeFirst(start) }
                guard buffer.count >= EISCP.headerSize else { return messages }
                let header = Self.uint32(buffer, at: 4)
                let data = Self.uint32(buffer, at: 8)
                guard header >= EISCP.headerSize, header <= EISCP.maximumHeaderSize, data <= EISCP.maximumDataSize else {
                    buffer.removeFirst()   // not a real header: look for the next one
                    continue
                }
                guard buffer.count >= header + data else { return messages }
                messages.append(Array(buffer[header..<(header + data)]))
                buffer.removeFirst(header + data)
            }
        }

        private static func uint32(_ bytes: [UInt8], at offset: Int) -> Int {
            bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
        }

        private static func find(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
            guard haystack.count >= needle.count else { return nil }
            for index in 0...(haystack.count - needle.count) where haystack[index] == needle[0] {
                if haystack[index..<(index + needle.count)].elementsEqual(needle) { return index }
            }
            return nil
        }
    }
}
