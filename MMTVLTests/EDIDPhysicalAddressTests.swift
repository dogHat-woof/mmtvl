import Testing
@testable import MMTVL

/// M7h step 9 (reopened): the physical address from an EDID's HDMI vendor-specific block. Synthetic EDIDs only.
struct EDIDPhysicalAddressTests {
    /// A base block (header, `extensions` at byte 126) and the given 128-byte extensions.
    private static func edid(extensions: [[UInt8]], count: UInt8? = nil) -> [UInt8] {
        var base = [UInt8](repeating: 0, count: 128)
        base.replaceSubrange(0..<8, with: [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
        base[126] = count ?? UInt8(extensions.count)
        return base + extensions.flatMap { $0 }
    }

    /// A CEA-861 extension with these data blocks (each with its header byte); the detailed timings start after them.
    private static func cea(_ blocks: [[UInt8]], dataEnd: Int? = nil) -> [UInt8] {
        var block = [UInt8](repeating: 0, count: 128)
        let data = blocks.flatMap { $0 }
        block[0] = 0x02
        block[1] = 0x03
        block[2] = UInt8(dataEnd ?? (4 + data.count))
        block.replaceSubrange(4..<(4 + data.count), with: data)
        return block
    }

    private static let video: [UInt8] = [0x43, 0x10, 0x04, 0x03]          // tag 2, 3 bytes
    private static let audio: [UInt8] = [0x23, 0x09, 0x07, 0x07]          // tag 1, 3 bytes
    private static let hdmi23: [UInt8] = [0x65, 0x03, 0x0C, 0x00, 0x23, 0x00]   // tag 3, OUI 00-0C-03, 2.3.0.0
    private static let hdmiForum: [UInt8] = [0x67, 0xD8, 0x5D, 0xC4, 0x01, 0x78, 0x80, 0x00]   // tag 3, another OUI

    @Test func vsdbGivesTheMinisAddress() {
        let edid = Self.edid(extensions: [Self.cea([Self.video, Self.audio, Self.hdmi23])])
        #expect(EDIDPhysicalAddress.parse(edid)?.description == "2.3.0.0")
    }

    @Test func otherBlocksAndOtherOUIsAreSkipped() {
        let edid = Self.edid(extensions: [Self.cea([Self.hdmiForum, Self.video, [0x65, 0x03, 0x0C, 0x00, 0x10, 0x00]])])
        #expect(EDIDPhysicalAddress.parse(edid)?.description == "1.0.0.0")
        // A non-CEA extension first (a block map), then the CEA one.
        var blockMap = [UInt8](repeating: 0, count: 128)
        blockMap[0] = 0xF0
        let two = Self.edid(extensions: [blockMap, Self.cea([Self.hdmi23])])
        #expect(EDIDPhysicalAddress.parse(two)?.description == "2.3.0.0")
    }

    @Test func noExtensionGivesNil() {
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [])) == nil)
        #expect(EDIDPhysicalAddress.parse([]) == nil)
        #expect(EDIDPhysicalAddress.parse([UInt8](repeating: 0, count: 256)) == nil)   // no header
    }

    @Test func noVSDBGivesNil() {
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [Self.cea([Self.video, Self.audio])])) == nil)
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [Self.cea([Self.hdmiForum])])) == nil)
        // No data blocks at all (offset 0 or 4).
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [Self.cea([], dataEnd: 0)])) == nil)
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [Self.cea([], dataEnd: 4)])) == nil)
    }

    @Test func truncatedGivesNil() {
        // The base block says one extension, but there isn't one.
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [], count: 1)) == nil)
        // The extension cut short.
        let full = Self.edid(extensions: [Self.cea([Self.hdmi23])])
        #expect(EDIDPhysicalAddress.parse(Array(full.prefix(200))) == nil)
        // The VSDB runs past the data block collection.
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [Self.cea([Self.video, Self.hdmi23], dataEnd: 12)])) == nil)
        // A VSDB too short for the address.
        #expect(EDIDPhysicalAddress.parse(Self.edid(extensions: [Self.cea([[0x63, 0x03, 0x0C, 0x00]])])) == nil)
    }

    @Test func noAddressValuesGiveNil() {
        let unset = Self.edid(extensions: [Self.cea([[0x65, 0x03, 0x0C, 0x00, 0xFF, 0xFF]])])
        #expect(EDIDPhysicalAddress.parse(unset) == nil)
        let tvsOwn = Self.edid(extensions: [Self.cea([[0x65, 0x03, 0x0C, 0x00, 0x00, 0x00]])])
        #expect(EDIDPhysicalAddress.parse(tvsOwn) == nil)
    }
}
