import Foundation
import Testing
@testable import MMTVL

/// M7j step 2: the discovery packet format. Vectors from the plan's *Research & findings* (fake id and address).
struct HDHomeRunPacketTests {
    static let requestVector: [UInt8] = [
        0x00, 0x02, 0x00, 0x0c, 0x01, 0x04, 0xff, 0xff, 0xff, 0xff, 0x02, 0x04, 0xff, 0xff, 0xff, 0xff,
        0x73, 0xcc, 0x7d, 0x8f,
    ]

    /// Type 3; device type 1; id 0x1234ABCD; tuner count 2; BaseURL http://192.168.1.20:80.
    static let replyVector: [UInt8] = [
        0x00, 0x03, 0x00, 0x27, 0x01, 0x04, 0x00, 0x00, 0x00, 0x01, 0x02, 0x04, 0x12, 0x34, 0xab, 0xcd,
        0x10, 0x01, 0x02, 0x2a, 0x16, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x31, 0x39, 0x32, 0x2e,
        0x31, 0x36, 0x38, 0x2e, 0x31, 0x2e, 0x32, 0x30, 0x3a, 0x38, 0x30, 0x7a, 0xf8, 0x5b, 0x30,
    ]

    /// A reply framed by `HDHomeRunPacket.encode` (the framing and CRC are pinned by the vectors above).
    static func reply(deviceType: UInt32 = 1, id: UInt32 = 0x1234_ABCD, extra: [(tag: UInt8, value: [UInt8])] = [])
        -> Data {
        HDHomeRunPacket.encode(type: HDHomeRunPacket.typeDiscoverReply, tlvs: [
            (0x01, HDHomeRunPacket.bigEndian(deviceType)),
            (0x02, HDHomeRunPacket.bigEndian(id)),
            (0x10, [2]),
        ] + extra)
    }

    /// Header + raw payload + a correct CRC (for payloads `encode` wouldn't write).
    static func frame(type: UInt16 = 3, payload: [UInt8]) -> Data {
        var bytes = HDHomeRunPacket.bigEndian(type) + HDHomeRunPacket.bigEndian(UInt16(payload.count)) + payload
        let crc = HDHomeRunPacket.crc32(bytes)
        bytes += [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8((crc >> 16) & 0xFF), UInt8(crc >> 24)]
        return Data(bytes)
    }

    @Test func discoverRequestBytes() {
        #expect([UInt8](HDHomeRunPacket.discoverRequest) == Self.requestVector)
        #expect(HDHomeRunPacket.port == 65001)
    }

    @Test func replyVectorEncodesTheSame() {
        let encoded = HDHomeRunPacket.encode(type: 3, tlvs: [
            (0x01, [0, 0, 0, 1]), (0x02, [0x12, 0x34, 0xab, 0xcd]), (0x10, [2]),
            (0x2a, Array("http://192.168.1.20:80".utf8)),
        ])
        #expect([UInt8](encoded) == Self.replyVector)
    }

    @Test func parsesTheReplyVector() throws {
        let reply = try #require(HDHomeRunPacket.parseDiscoverReply(Data(Self.replyVector)))
        #expect(reply.deviceID == 0x1234_ABCD)
        #expect(reply.tunerCount == 2)
        #expect(reply.baseURL == URL(string: "http://192.168.1.20:80"))
        #expect(reply.lineupURL == nil)
    }

    @Test func unknownTagsAreSkipped() throws {
        let data = Self.reply(extra: [
            (0x2B, Array(repeating: 0x41, count: 24)),   // DeviceAuth: ignored
            (0x2D, [0, 0, 0, 1]),                        // multi type
            (0x7E, [1, 2, 3]),                           // unknown
            (0x27, Array("http://10.0.0.9/lineup.json".utf8)),
        ])
        let reply = try #require(HDHomeRunPacket.parseDiscoverReply(data))
        #expect(reply.deviceID == 0x1234_ABCD)
        #expect(reply.lineupURL == URL(string: "http://10.0.0.9/lineup.json"))
    }

    @Test func twoByteLengthsParse() throws {
        #expect(HDHomeRunPacket.lengthBytes(127) == [0x7F])
        #expect(HDHomeRunPacket.lengthBytes(128) == [0x80, 0x01])
        #expect(HDHomeRunPacket.lengthBytes(200) == [0xC8, 0x01])
        let url = "http://10.0.0.9/" + String(repeating: "a", count: 200 - 16)
        #expect(url.utf8.count == 200)
        let payload: [UInt8] = [0x01, 0x04, 0, 0, 0, 1, 0x02, 0x04, 0x12, 0x34, 0xab, 0xcd]
            + [0x27, 0xC8, 0x01] + Array(url.utf8)
            + [0x2A, 0x10] + Array("http://10.0.0.9/".utf8)
        let reply = try #require(HDHomeRunPacket.parseDiscoverReply(Self.frame(payload: payload)))
        #expect(reply.lineupURL?.absoluteString == url)
        #expect(reply.baseURL?.absoluteString == "http://10.0.0.9/")
        #expect([UInt8](Self.reply(extra: [(0x27, Array(url.utf8))])).count == 4 + 15 + 3 + 200 + 4)
    }

    @Test func badCRCIsRejected() {
        var lastByte = Self.replyVector
        lastByte[lastByte.count - 1] ^= 0x01
        #expect(HDHomeRunPacket.parseDiscoverReply(Data(lastByte)) == nil)
        var payloadByte = Self.replyVector
        payloadByte[14] ^= 0x01   // the device id
        #expect(HDHomeRunPacket.parseDiscoverReply(Data(payloadByte)) == nil)
    }

    @Test func nonTunerDeviceTypeIsIgnored() {
        #expect(HDHomeRunPacket.parseDiscoverReply(Self.reply(deviceType: 5)) == nil)
        #expect(HDHomeRunPacket.parseDiscoverReply(Self.reply(deviceType: HDHomeRunPacket.wildcard)) == nil)
        // No device type at all.
        #expect(HDHomeRunPacket.parseDiscoverReply(Self.frame(payload: [0x02, 0x04, 1, 2, 3, 4])) == nil)
        // A request, not a reply.
        #expect(HDHomeRunPacket.parseDiscoverReply(HDHomeRunPacket.discoverRequest) == nil)
    }

    @Test func truncatedPacketIsRejected() {
        for count in [0, 3, 7, Self.replyVector.count - 1] {
            #expect(HDHomeRunPacket.parseDiscoverReply(Data(Self.replyVector.prefix(count))) == nil)
        }
        // Extra bytes after the CRC.
        #expect(HDHomeRunPacket.parseDiscoverReply(Data(Self.replyVector + [0])) == nil)
        let tuner: [UInt8] = [0x01, 0x04, 0, 0, 0, 1, 0x02, 0x04, 1, 2, 3, 4]
        // A TLV whose value runs past the payload, with a correct CRC.
        #expect(HDHomeRunPacket.parseDiscoverReply(Self.frame(payload: tuner + [0x2A, 0x10, 0x68])) == nil)
        // A tag with no length, and a 2-byte length cut short.
        #expect(HDHomeRunPacket.parseDiscoverReply(Self.frame(payload: tuner + [0x2A])) == nil)
        #expect(HDHomeRunPacket.parseDiscoverReply(Self.frame(payload: tuner + [0x2A, 0x80])) == nil)
        // A device id of the wrong size.
        #expect(HDHomeRunPacket.parseDiscoverReply(Self.frame(payload: [0x01, 0x04, 0, 0, 0, 1, 0x02, 0x02, 1, 2]))
            == nil)
    }
}
