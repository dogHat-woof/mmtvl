import AppKit
import Testing
@testable import MMTVL

struct PhoneRemoteIconTests {
    @Test func rendersAPNGOfTheRequestedSize() throws {
        let data = try #require(PhoneRemoteIcon.png(size: 180))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let image = try #require(NSBitmapImageRep(data: data))
        #expect(image.pixelsWide == 180)
        #expect(image.pixelsHigh == 180)
        // Cached: the same bytes come back.
        #expect(PhoneRemoteIcon.png(size: 180) == data)
    }
}
