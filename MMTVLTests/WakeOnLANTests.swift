import Foundation
import Testing
@testable import MMTVL

/// M7h L18: the magic packet, MAC parsing (typed and from a UDN) and where the packet goes. Made-up MACs only.
struct WakeOnLANTests {
    private static let mac = MACAddress(bytes: [0x02, 0x00, 0x5E, 0x00, 0x10, 0xAB])!

    @Test func packetIsSixFFsThenTheMACSixteenTimes() throws {
        let packet = WakeOnLAN.packet(mac: Self.mac)
        #expect(packet.count == 102)
        #expect(packet.count == WakeOnLAN.packetSize)
        #expect(Array(packet[0..<6]) == [UInt8](repeating: 0xFF, count: 6))
        for copy in 0..<16 {
            let start = 6 + copy * 6
            #expect(Array(packet[start..<start + 6]) == [0x02, 0x00, 0x5E, 0x00, 0x10, 0xAB], "copy \(copy)")
        }
        #expect(packet == [UInt8](repeating: 0xFF, count: 6)
            + (0..<16).flatMap { _ in [UInt8]([0x02, 0x00, 0x5E, 0x00, 0x10, 0xAB]) })
    }

    @Test func macParsesInEachForm() {
        for text in ["02:00:5e:00:10:ab", "02-00-5E-00-10-AB", "02005e0010ab", "02005E0010AB", " 02:00:5E:00:10:aB\n"] {
            #expect(MACAddress(parsing: text) == Self.mac, "\(text)")
        }
        #expect(Self.mac.description == "02:00:5e:00:10:ab")
    }

    @Test func badMACsAreRejected() {
        for text in ["", "02:00:5e:00:10", "02:00:5e:00:10:ab:cd", "02005e0010a", "02005e0010abc", "02:00-5e:00:10:ab",
                     "2:0:5e:0:10:ab", "02:00:5e:00:10:zz", "0200.5e00.10ab", "02 00 5e 00 10 ab", "02::5e:00:10:ab",
                     "00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "01:00:5e:00:00:01", "+2:00:5e:00:10:ab"] {
            #expect(MACAddress(parsing: text) == nil, "\(text)")
        }
        #expect(MACAddress(bytes: [0x02, 0x00, 0x5E, 0x00, 0x10]) == nil)
    }

    @Test func udnGivesTheMAC() {
        #expect(MACAddress(udn: "uuid:4D454930-0200-1000-8001-02005E0010AB") == Self.mac)
        #expect(MACAddress(udn: "UUID:4d454930-0200-1000-8001-02005e0010ab") == Self.mac)
        #expect(MACAddress(udn: "4D454930-0200-1000-8001-02005E0010AB") == Self.mac)
    }

    @Test func udnWithoutAMACIsNil() {
        for udn in ["", "uuid:", "uuid:4D454930-0200-1000-8001", "uuid:not-a-mac",
                    // A random (version 4) UUID's last group isn't a MAC.
                    "uuid:f47ac10b-58cc-4372-a567-0e02b2c3d479",
                    // A version 1 UUID with a random node (group bit set) or no node.
                    "uuid:4D454930-0200-1000-8001-03005E0010AB", "uuid:4D454930-0200-1000-8001-000000000000",
                    "uuid:4D454930-0200-1000-8001-02005E0010AB::upnp:rootdevice", "uuid:4D454930-0200-1000-8001-02005E0010AG"] {
            #expect(MACAddress(udn: udn) == nil, "\(udn)")
        }
    }

    // MARK: Where it goes

    private static func interface(_ name: String, _ address: [UInt8], _ netmask: [UInt8], up: Bool = true,
                                  loopback: Bool = false, broadcast: Bool = true,
                                  pointToPoint: Bool = false) -> WakeOnLAN.Interface {
        WakeOnLAN.Interface(name: name, address: address, netmask: netmask, isUp: up, isLoopback: loopback,
                            isBroadcast: broadcast, isPointToPoint: pointToPoint)
    }

    @Test func broadcastOfASubnet() {
        #expect(WakeOnLAN.broadcast(address: [192, 168, 1, 10], netmask: [255, 255, 255, 0]) == [192, 168, 1, 255])
        #expect(WakeOnLAN.broadcast(address: [10, 1, 2, 3], netmask: [255, 255, 240, 0]) == [10, 1, 15, 255])
        #expect(WakeOnLAN.broadcast(address: [10, 1, 2, 3], netmask: [255, 255, 255, 254]) == nil)
        #expect(WakeOnLAN.broadcast(address: [10, 1, 2, 3], netmask: [255, 255, 255, 255]) == nil)
    }

    @Test func targetsAreTheTVsSubnetBroadcastAndTheTV() {
        let interfaces = [
            Self.interface("lo0", [127, 0, 0, 1], [255, 0, 0, 0], loopback: true),
            Self.interface("en0", [192, 168, 1, 10], [255, 255, 255, 0]),
            Self.interface("en1", [10, 0, 0, 5], [255, 255, 255, 0]),
            Self.interface("en2", [192, 168, 2, 10], [255, 255, 255, 0], up: false),
            Self.interface("en3", [169, 254, 3, 4], [255, 255, 0, 0]),
            Self.interface("utun0", [100, 64, 0, 2], [255, 255, 255, 0]),
        ]
        #expect(WakeOnLAN.targets(tvAddress: "192.168.1.30", interfaces: interfaces) == ["192.168.1.255", "192.168.1.30"])
        // On none of the Mac's subnets: the TV's address only.
        #expect(WakeOnLAN.targets(tvAddress: "192.168.9.30", interfaces: interfaces) == ["192.168.9.30"])
        // Not known yet (a name): every LAN interface's broadcast, never loopback, down, link-local or public ones.
        #expect(WakeOnLAN.targets(tvAddress: nil, interfaces: interfaces) == ["192.168.1.255", "10.0.0.255"])
        #expect(WakeOnLAN.targets(tvAddress: "tv.local", interfaces: interfaces) == ["192.168.1.255", "10.0.0.255"])
        // A public address isn't sent to.
        #expect(WakeOnLAN.targets(tvAddress: "8.8.8.8", interfaces: interfaces) == ["192.168.1.255", "10.0.0.255"])
        #expect(WakeOnLAN.targets(tvAddress: "192.168.1.30", interfaces: []) == ["192.168.1.30"])
    }

    @Test func aBroadcastOutsideTheLANIsDropped() {
        // A mask so short its broadcast leaves the private range.
        let wide = [Self.interface("en0", [10, 0, 0, 5], [240, 0, 0, 0])]
        #expect(WakeOnLAN.targets(tvAddress: nil, interfaces: wide).isEmpty)
    }

    /// Security S1: never out through a VPN tunnel or a virtual machine / Internet Sharing bridge.
    @Test func vpnsAndBridgesAreNeverUsed() {
        let en0 = Self.interface("en0", [192, 168, 1, 10], [255, 255, 255, 0])
        let utun = Self.interface("utun0", [10, 8, 0, 2], [255, 255, 255, 0], broadcast: false, pointToPoint: true)
        #expect(WakeOnLAN.targets(tvAddress: nil, interfaces: [en0, utun]) == ["192.168.1.255"])
        // By flag alone, and by name alone (the backstop).
        let pointToPoint = Self.interface("en5", [10, 8, 1, 2], [255, 255, 255, 0], pointToPoint: true)
        let noBroadcast = Self.interface("en6", [10, 8, 2, 2], [255, 255, 255, 0], broadcast: false)
        let named = ["bridge100", "vmnet8", "utun3", "ipsec0", "ppp0"].enumerated().map { index, name in
            Self.interface(name, [10, 9, UInt8(index), 1], [255, 255, 255, 0])
        }
        #expect(WakeOnLAN.targets(tvAddress: nil, interfaces: [en0, pointToPoint, noBroadcast] + named) == ["192.168.1.255"])
        // A VPN route overlapping the home subnet isn't chosen for a known address.
        let overlapping = Self.interface("utun4", [192, 168, 1, 200], [255, 255, 255, 0], broadcast: false,
                                         pointToPoint: true)
        #expect(WakeOnLAN.targets(tvAddress: "192.168.1.30", interfaces: [overlapping]) == ["192.168.1.30"])
        #expect(WakeOnLAN.targets(tvAddress: "192.168.1.30", interfaces: [overlapping, en0])
            == ["192.168.1.255", "192.168.1.30"])
    }

    /// Security low (after 9b): ZeroTier (`feth*`, `zt*`) and tap adapters are broadcast-capable but never the TV's LAN.
    @Test func zeroTierAndTapAdaptersAreNeverUsed() {
        let en0 = Self.interface("en0", [192, 168, 1, 10], [255, 255, 255, 0])
        for name in ["feth1234", "tap0", "zt5u4abc"] {
            let virtual = Self.interface(name, [10, 147, 17, 5], [255, 255, 255, 0])
            #expect(WakeOnLAN.targets(tvAddress: nil, interfaces: [en0, virtual]) == ["192.168.1.255"], "\(name)")
        }
    }
}
