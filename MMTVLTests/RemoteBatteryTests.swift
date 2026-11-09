import Testing
@testable import MMTVL

/// M7f L8: picking the Siri Remote's level out of the accessory power sources.
struct RemoteBatteryTests {
    private func source(type: String = "Accessory Source", vendor: Int = 76, product: Int = 789,
                        current: Int? = 88, max: Int? = 100) -> [String: Any] {
        var description: [String: Any] = ["Type": type, "Vendor ID": vendor, "Product ID": product,
                                          "Name": "C08S29062330", "Transport Type": "Bluetooth"]
        if let current { description["Current Capacity"] = current }
        if let max { description["Max Capacity"] = max }
        return description
    }

    @Test func siriRemoteGivesItsPercent() {
        #expect(RemoteBattery.level(from: [source()]) == 88)
    }

    @Test func magicTrackpadIsIgnored() {
        #expect(RemoteBattery.level(from: [source(product: 804, current: 85)]) == nil)
        #expect(RemoteBattery.level(from: [source(product: 804, current: 85), source(current: 60)]) == 60)
    }

    @Test func twoRemotesGiveTheLowerLevel() {
        #expect(RemoteBattery.level(from: [source(product: 789, current: 88), source(product: 614, current: 12)]) == 12)
    }

    @Test func missingOrZeroMaxCapacityIsIgnored() {
        #expect(RemoteBattery.level(from: [source(max: nil)]) == nil)
        #expect(RemoteBattery.level(from: [source(max: 0)]) == nil)
        #expect(RemoteBattery.level(from: [source(current: nil)]) == nil)
    }

    @Test func percentIsRoundedAndClamped() {
        #expect(RemoteBattery.level(from: [source(current: 1, max: 3)]) == 33)
        #expect(RemoteBattery.level(from: [source(current: 120, max: 100)]) == 100)
    }

    @Test func nonAccessorySourcesAreIgnored() {
        #expect(RemoteBattery.level(from: [source(type: "InternalBattery")]) == nil)
        #expect(RemoteBattery.level(from: [source(vendor: 2007)]) == nil)
    }

    @Test func nothingGivesNil() {
        #expect(RemoteBattery.level(from: []) == nil)
    }

    /// The dev Mac has no Siri Remote: the real read returns nil without crashing.
    @Test func currentReadsWithoutCrashing() {
        let level = RemoteBattery.current()
        #expect(level == nil || (0...100).contains(level!))
    }
}
