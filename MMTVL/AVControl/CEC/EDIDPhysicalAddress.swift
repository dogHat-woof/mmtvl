import Foundation
import IOKit

// M7h step 9 (reopened): the Mac's CEC physical address, for Active Source. `IOAVServiceCopyPhysicalAddress` returns
// an empty CFData on both Macs (probe 1), so it comes from the display's EDID: the `"EDID"` property of
// `IOPortTransportStateDisplayPort` (read-only), its CEA-861 extension's HDMI vendor-specific data block (tag 3, OUI
// 00-0C-03), bytes 4–5. 2.3.0.0 on the mini, matching what corercd sends (probe 2). The EDID is never logged.

nonisolated enum EDIDPhysicalAddress {
    private static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    private static let hdmiOUI: [UInt8] = [0x03, 0x0C, 0x00]   // 00-0C-03, little-endian in the block

    /// The physical address in an EDID's HDMI vendor-specific block; nil without a CEA-861 extension, without the
    /// block, for a block or extension cut short, and for F.F.F.F or 0.0.0.0. Pure.
    static func parse(_ edid: [UInt8]) -> CECPhysicalAddress? {
        guard edid.count >= 128, Array(edid[0..<8]) == header else { return nil }
        let extensions = Int(edid[126])
        guard extensions > 0 else { return nil }
        for index in 1...extensions {
            let start = index * 128
            guard start + 128 <= edid.count else { return nil }
            let block = Array(edid[start..<(start + 128)])
            // CEA-861: tag 0x02; byte 2 is where the detailed timings start, so the data blocks are 4..<offset.
            guard block[0] == 0x02 else { continue }
            let dataEnd = Int(block[2])
            guard dataEnd > 4, dataEnd <= 127 else { continue }
            var position = 4
            while position < dataEnd {
                let tag = block[position] >> 5
                let length = Int(block[position] & 0x1F)
                // The block's last byte must still be in the data block collection.
                guard position + length < dataEnd else { return nil }
                if tag == 3, length >= 5, Array(block[(position + 1)...(position + 3)]) == hdmiOUI {
                    return CECPhysicalAddress(high: block[position + 4], low: block[position + 5])
                }
                position += 1 + length
            }
        }
        return nil
    }

    /// The first `IOPortTransportStateDisplayPort` EDID that holds a physical address. Read-only.
    static func current() -> CECPhysicalAddress? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportStateDisplayPort"),
                                           &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var found: CECPhysicalAddress?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if found == nil, let data = IOKitDPCD.property(service, "EDID") as? Data {
                found = parse([UInt8](data))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return found
    }
}
