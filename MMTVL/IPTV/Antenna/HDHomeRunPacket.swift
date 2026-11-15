import Foundation
import zlib

// M7j step 2: SiliconDust's UDP discovery packet format (documented in libhdhomerun's `hdhomerun_pkt.h`; MMTVL
// implements the format itself and copies no code). A packet is `uint16 type`, `uint16 payload length`, the payload,
// then a `uint32` Ethernet CRC-32 (zlib's `crc32`) of everything before it, little-endian; everything else is
// big-endian. The payload is TLVs: `uint8 tag`, a length of 1 byte (≤ 127) or 2 bytes (the low 7 bits with the high
// bit set, then the rest `>> 7`), the value.

/// One tuner's answer to a discover request. DeviceAuth (tag 0x2B) is ignored: `discover.json` gives it fresh.
/// The device id, its URLs and the address it came from are never logged (L15); its descriptions and mirror show
/// the tuner count and whether the URLs are there, nothing else.
nonisolated struct HDHomeRunReply: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    var deviceID: UInt32
    var tunerCount: Int?
    var baseURL: URL?
    var lineupURL: URL?

    var description: String {
        "HDHomeRunReply(tunerCount: \(tunerCount.map(String.init) ?? "nil"), hasBaseURL: \(baseURL != nil), "
            + "hasLineupURL: \(lineupURL != nil))"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["tunerCount": tunerCount as Any, "hasBaseURL": baseURL != nil,
                                "hasLineupURL": lineupURL != nil], displayStyle: .struct)
    }
}

/// Building the discover request and reading replies. Pure.
nonisolated enum HDHomeRunPacket {
    static let port: UInt16 = 65001

    static let typeDiscoverRequest: UInt16 = 0x0002
    static let typeDiscoverReply: UInt16 = 0x0003

    enum Tag {
        static let deviceType: UInt8 = 0x01
        static let deviceID: UInt8 = 0x02
        static let tunerCount: UInt8 = 0x10
        static let lineupURL: UInt8 = 0x27
        static let baseURL: UInt8 = 0x2A
        static let deviceAuth: UInt8 = 0x2B
        static let multiType: UInt8 = 0x2D
    }

    static let deviceTypeTuner: UInt32 = 0x0000_0001
    static let wildcard: UInt32 = 0xFFFF_FFFF

    /// The largest TLV value the 2-byte length can carry (7 + 8 bits).
    static let maximumValueLength = 0x7FFF
    /// URLs in a reply longer than this are ignored.
    static let maximumURLLength = 256

    /// `00 02 00 0c 01 04 ff ff ff ff 02 04 ff ff ff ff 73 cc 7d 8f`: any device type, any device id.
    static let discoverRequest: Data = encode(type: typeDiscoverRequest, tlvs: [
        (Tag.deviceType, bigEndian(wildcard)),
        (Tag.deviceID, bigEndian(wildcard)),
    ])

    /// A whole packet: header, the TLVs, the CRC.
    static func encode(type: UInt16, tlvs: [(tag: UInt8, value: [UInt8])]) -> Data {
        var payload: [UInt8] = []
        for tlv in tlvs {
            payload.append(tlv.tag)
            payload += lengthBytes(min(tlv.value.count, maximumValueLength))
            payload += tlv.value.prefix(maximumValueLength)
        }
        var bytes = bigEndian(type) + bigEndian(UInt16(payload.count)) + payload
        let crc = crc32(bytes)
        bytes += [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8((crc >> 16) & 0xFF), UInt8(crc >> 24)]
        return Data(bytes)
    }

    /// A TLV length: 1 byte up to 127, else the low 7 bits with the high bit set, then the rest.
    static func lengthBytes(_ length: Int) -> [UInt8] {
        length <= 0x7F ? [UInt8(length)] : [UInt8(0x80 | (length & 0x7F)), UInt8((length >> 7) & 0xFF)]
    }

    /// A tuner's reply: type 3, the length matching the datagram, the CRC right, every TLV whole, device type 1
    /// (tuner) and a 4-byte device id. Unknown tags are skipped. nil otherwise.
    static func parseDiscoverReply(_ data: Data) -> HDHomeRunReply? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, uint16(bytes, at: 0) == typeDiscoverReply else { return nil }
        let length = Int(uint16(bytes, at: 2))
        guard bytes.count == 4 + length + 4 else { return nil }
        let crc = UInt32(bytes[4 + length]) | UInt32(bytes[5 + length]) << 8
            | UInt32(bytes[6 + length]) << 16 | UInt32(bytes[7 + length]) << 24
        guard crc32(Array(bytes[0..<(4 + length)])) == crc else { return nil }

        var deviceType: UInt32?
        var deviceID: UInt32?
        var tunerCount: Int?
        var baseURL: URL?
        var lineupURL: URL?
        var index = 4
        let end = 4 + length
        while index < end {
            let tag = bytes[index]
            index += 1
            guard index < end else { return nil }
            var valueLength = Int(bytes[index])
            index += 1
            if valueLength & 0x80 != 0 {
                guard index < end else { return nil }
                valueLength = (valueLength & 0x7F) | Int(bytes[index]) << 7
                index += 1
            }
            guard valueLength <= end - index else { return nil }
            let value = Array(bytes[index..<(index + valueLength)])
            index += valueLength
            switch tag {
            case Tag.deviceType:
                guard value.count == 4 else { return nil }
                deviceType = deviceType ?? uint32(value)
            case Tag.deviceID:
                guard value.count == 4 else { return nil }
                deviceID = deviceID ?? uint32(value)
            case Tag.tunerCount:
                guard value.count == 1 else { return nil }
                tunerCount = tunerCount ?? Int(value[0])
            case Tag.baseURL:
                baseURL = baseURL ?? url(value)
            case Tag.lineupURL:
                lineupURL = lineupURL ?? url(value)
            default:
                continue   // DeviceAuth, multi type and anything newer
            }
        }
        guard deviceType == deviceTypeTuner, let deviceID else { return nil }
        return HDHomeRunReply(deviceID: deviceID, tunerCount: tunerCount, baseURL: baseURL, lineupURL: lineupURL)
    }

    // MARK: Helpers

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBufferPointer { buffer in
            UInt32(zlib.crc32(0, buffer.baseAddress, uInt(buffer.count)))
        }
    }

    static func bigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func uint16(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
    }

    private static func uint32(_ value: [UInt8]) -> UInt32 {
        value.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// UTF-8 text without trailing NULs, at most `maximumURLLength` bytes; nil if it isn't a URL.
    private static func url(_ value: [UInt8]) -> URL? {
        var value = value[...]
        while value.last == 0 { value = value.dropLast() }
        guard !value.isEmpty, value.count <= maximumURLLength,
              let text = String(bytes: value, encoding: .utf8) else { return nil }
        return URL(string: text)
    }
}
