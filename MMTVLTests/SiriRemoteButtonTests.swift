import Foundation
import Testing
@testable import MMTVL

/// M7h L2: the probe's usage table (M7e, confirmed seized on the mini in step 1).
struct SiriRemoteButtonTests {
    @Test(arguments: [
        (UInt32(0x0C), UInt32(0x60), SiriRemoteButton.tv),
        (0x01, 0x86, .back),
        (0x0C, 0xCD, .playPause),
        (0x0C, 0xE9, .volumeUp),
        (0x0C, 0xEA, .volumeDown),
        (0x0C, 0xE2, .mute),
        (0x0C, 0x30, .power),
        (0x0C, 0x42, .up),
        (0x0C, 0x43, .down),
        (0x0C, 0x44, .left),
        (0x0C, 0x45, .right),
        (0x0C, 0x80, .select),
    ])
    func probeUsageMapsToItsButton(usagePage: UInt32, usage: UInt32, button: SiriRemoteButton) {
        #expect(SiriRemoteButton.from(usagePage: usagePage, usage: usage) == button)
        #expect(!SiriRemoteButton.isSiri(usagePage: usagePage, usage: usage))
    }

    @Test func everyButtonHasAUsage() {
        let mapped: [SiriRemoteButton?] = [(0x0C, 0x60), (0x01, 0x86), (0x0C, 0xCD), (0x0C, 0xE9), (0x0C, 0xEA),
                                           (0x0C, 0xE2), (0x0C, 0x30), (0x0C, 0x42), (0x0C, 0x43), (0x0C, 0x44),
                                           (0x0C, 0x45), (0x0C, 0x80)]
            .map { SiriRemoteButton.from(usagePage: $0.0, usage: $0.1) }
        #expect(Set(mapped.compactMap { $0 }) == Set(SiriRemoteButton.allCases))
    }

    @Test func unknownUsagesAreNil() {
        // Wrong page for a known usage, unknown usages, and Siri (reserved, not a button).
        let unknown: [(UInt32, UInt32)] = [(0x01, 0x60), (0x0C, 0x86), (0x0C, 0x00), (0x0C, 0x01), (0x0C, 0x46),
                                           (0x0D, 0x80), (0xFF00, 0x0B), (0x0C, 0x04)]
        for (page, usage) in unknown {
            #expect(SiriRemoteButton.from(usagePage: page, usage: usage) == nil)
        }
    }

    @Test func siriIsConsumer04Only() {
        #expect(SiriRemoteButton.isSiri(usagePage: 0x0C, usage: 0x04))
        #expect(!SiriRemoteButton.isSiri(usagePage: 0x01, usage: 0x04))
        #expect(!SiriRemoteButton.isSiri(usagePage: 0x0C, usage: 0x60))
    }

    @Test func rawValuesAreTheJSONNames() {
        #expect(SiriRemoteButton.allCases.map(\.rawValue) == [
            "tv", "back", "playPause", "volumeUp", "volumeDown", "mute", "power", "up", "down", "left", "right", "select",
        ])
    }
}
