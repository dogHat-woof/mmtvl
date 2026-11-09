import Darwin
import Foundation
import os

// M7h L18: turning the TV on. Its network is down in standby, so the only way in is a Wake-on-LAN magic packet
// (6 × 0xFF, then the MAC 16 times) by UDP to port 9, at the subnet broadcast of the Mac's interface on the TV's
// subnet and at the TV's own address. Needs the TV wired (over Wi-Fi it never woke, step 1). **Never log a MAC.**

/// A unicast Ethernet address (6 bytes; not all zero, not a group address). `description` is "02:00:5e:00:10:ab".
/// Pure.
nonisolated struct MACAddress: Hashable, Sendable, CustomStringConvertible {
    let bytes: [UInt8]

    /// nil unless 6 bytes of a unicast address (the group bit, which also covers ff:ff:ff:ff:ff:ff, is clear) that
    /// isn't all zero.
    init?(bytes: [UInt8]) {
        guard bytes.count == 6, bytes[0] & 0x01 == 0, bytes.contains(where: { $0 != 0 }) else { return nil }
        self.bytes = bytes
    }

    /// "02:00:5e:00:10:ab", "02-00-5E-00-10-AB" or "02005e0010ab" (any case, trimmed). One separator throughout,
    /// two hex digits per byte.
    init?(parsing text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups: [Substring]
        if text.contains(":") {
            groups = text.split(separator: ":", omittingEmptySubsequences: false)
        } else if text.contains("-") {
            groups = text.split(separator: "-", omittingEmptySubsequences: false)
        } else {
            guard text.count == 12 else { return nil }
            groups = stride(from: 0, to: 12, by: 2).map { offset in
                let start = text.index(text.startIndex, offsetBy: offset)
                return text[start..<text.index(start, offsetBy: 2)]
            }
        }
        guard groups.count == 6 else { return nil }
        var bytes: [UInt8] = []
        for group in groups {
            guard group.count == 2, group.allSatisfy(\.isHexDigit), let byte = UInt8(group, radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes: bytes)
    }

    /// L18: the MAC in a UPnP UDN, the node field of a time-based (version 1) UUID, as Panasonic's
    /// `uuid:4D454930-0200-1000-8001-<MAC>` is (RFC 4122: a version 1 node is the MAC unless its group bit is set).
    /// nil for any other UUID or text. **Unverified** beyond the VT50.
    init?(udn: String) {
        var text = udn.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("uuid:") { text = String(text.dropFirst(5)) }
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12], groups.allSatisfy({ $0.allSatisfy(\.isHexDigit) }),
              groups[2].first == "1"
        else { return nil }
        self.init(parsing: String(groups[4]))
    }

    var description: String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

/// The magic packet and where it goes. Pure, apart from `interfaces()`.
nonisolated enum WakeOnLAN {
    static let port: UInt16 = 9
    static let packetSize = 102

    /// 6 × 0xFF, then the MAC 16 times (102 bytes).
    static func packet(mac: MACAddress) -> [UInt8] {
        [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: mac.bytes, count: 16).joined())
    }

    /// An IPv4 interface of the Mac.
    struct Interface: Equatable, Sendable {
        var name: String
        var address: [UInt8]
        var netmask: [UInt8]
        var isUp: Bool
        var isLoopback: Bool
        /// `IFF_BROADCAST`: a LAN (Ethernet, Wi-Fi); VPN tunnels don't have it.
        var isBroadcast = true
        /// `IFF_POINTOPOINT`: a tunnel (utun, ppp, ipsec).
        var isPointToPoint = false
    }

    /// Security S1: names that are never the TV's LAN even when they look like one (VPNs, virtual machine and
    /// Internet Sharing bridges). A backstop to the flags.
    static let excludedInterfacePrefixes = ["utun", "ipsec", "ppp", "bridge", "vmnet", "gif", "stf", "awdl", "llw",
                                                  // ZeroTier and OpenVPN-style tap adapters have IFF_BROADCAST.
                                                  "feth", "tap", "zt"]

    /// Up, broadcast-capable, not loopback or point-to-point, not a VPN or bridge by name, with a private address
    /// that isn't link-local.
    static func isUsable(_ interface: Interface) -> Bool {
        interface.isUp && !interface.isLoopback && interface.isBroadcast && !interface.isPointToPoint
            && !excludedInterfacePrefixes.contains(where: { interface.name.hasPrefix($0) })
            && interface.address.count == 4 && LANAddress.isPrivate(ipv4: interface.address)
            && !(interface.address[0] == 169 && interface.address[1] == 254)
    }

    /// The subnet's broadcast address (`address | ~netmask`); nil for /31 and /32, which have none.
    static func broadcast(address: [UInt8], netmask: [UInt8]) -> [UInt8]? {
        guard address.count == 4, netmask.count == 4 else { return nil }
        let hostBits = netmask.map { ~$0 }
        guard hostBits.reduce(0, { $0 + $1.nonzeroBitCount }) >= 2 else { return nil }
        return zip(address, hostBits).map { $0 | $1 }
    }

    /// Where the packet goes, as IPv4 literals: the subnet broadcast of each Mac interface on the TV's subnet and the
    /// TV's address (`tvAddress`, a private IPv4 literal). Without a usable `tvAddress` (a name not resolved yet):
    /// the broadcast of every LAN interface. Only `isUsable` interfaces (never a VPN, bridge or loopback); only
    /// private addresses are returned.
    static func targets(tvAddress: String?, interfaces: [Interface]) -> [String] {
        let usable = interfaces.filter(isUsable)
        let tv = tvAddress.flatMap(ipv4).flatMap { LANAddress.isPrivate(ipv4: $0) ? $0 : nil }
        let chosen = tv.map { tv in usable.filter { isOnSubnet(tv, of: $0) } } ?? usable
        var result: [String] = []
        for interface in chosen {
            guard let broadcast = broadcast(address: interface.address, netmask: interface.netmask),
                  LANAddress.isPrivate(ipv4: broadcast) else { continue }
            let text = broadcast.map(String.init).joined(separator: ".")
            if !result.contains(text) { result.append(text) }
        }
        if let tv {
            let text = tv.map(String.init).joined(separator: ".")
            if !result.contains(text) { result.append(text) }
        }
        return result
    }

    /// `address` (IPv4 bytes) is on `interface`'s subnet.
    static func isOnSubnet(_ address: [UInt8], of interface: Interface) -> Bool {
        address.count == 4 && interface.address.count == 4 && interface.netmask.count == 4
            && zip(zip(interface.address, interface.netmask), address)
                .allSatisfy { pair, byte in pair.0 & pair.1 == byte & pair.1 }
    }

    /// Pre-build 2 security low: an SSDP reply counts only from the subnet of an `isUsable` interface (not a VPN,
    /// bridge or tunnel; the same rule as Wake-on-LAN). `address` is an IPv4 literal; anything else is refused.
    static func isOnUsableSubnet(_ address: String, interfaces: [Interface]) -> Bool {
        guard let bytes = ipv4(address) else { return false }
        return interfaces.contains { isUsable($0) && isOnSubnet(bytes, of: $0) }
    }

    /// The Mac's IPv4 interfaces with their netmasks (getifaddrs).
    static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }
        var result: [Interface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_INET,
                  let netmask = entry.pointee.ifa_netmask
            else { continue }
            let flags = Int32(entry.pointee.ifa_flags)
            result.append(Interface(name: String(cString: entry.pointee.ifa_name), address: ipv4Bytes(address),
                                    netmask: ipv4Bytes(netmask),
                                    isUp: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0,
                                    isLoopback: flags & IFF_LOOPBACK != 0,
                                    isBroadcast: flags & IFF_BROADCAST != 0,
                                    isPointToPoint: flags & IFF_POINTOPOINT != 0))
        }
        return result
    }

    private static func ipv4Bytes(_ address: UnsafeMutablePointer<sockaddr>) -> [UInt8] {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            var addr = sin.pointee.sin_addr
            return withUnsafeBytes(of: &addr.s_addr) { Array($0) }
        }
    }

    /// A strict dotted quad's bytes.
    static func ipv4(_ text: String) -> [UInt8]? {
        var address = in_addr()
        guard inet_pton(AF_INET, text.trimmingCharacters(in: .whitespaces), &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address.s_addr) { Array($0) }
    }
}

/// Sends the magic packet once to each of `WakeOnLAN.targets` (UDP, `SO_BROADCAST`). Logs counts only, never the MAC.
nonisolated enum WakeOnLANSender {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "TV")

    /// The number of addresses the packet went to.
    @discardableResult
    static func send(mac: MACAddress, tvAddress: String?) -> Int {
        let targets = WakeOnLAN.targets(tvAddress: tvAddress, interfaces: WakeOnLAN.interfaces())
        guard !targets.isEmpty else {
            logger.notice("TV: Wake-on-LAN has no LAN interface to send on")
            return 0
        }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            logger.error("TV: Wake-on-LAN can't open a socket: \(String(cString: strerror(errno)), privacy: .public)")
            return 0
        }
        defer { Darwin.close(fd) }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        let packet = WakeOnLAN.packet(mac: mac)
        var sent = 0
        for target in targets {
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = WakeOnLAN.port.bigEndian
            guard inet_pton(AF_INET, target, &destination.sin_addr) == 1 else { continue }
            let result = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if result == packet.count {
                sent += 1
            } else {
                let code = errno
                if code == EHOSTUNREACH || code == EPERM {
                    logger.error("TV: Wake-on-LAN: allow Local Network for MMTVL in System Settings → Privacy & Security")
                } else {
                    logger.notice("TV: Wake-on-LAN to \(target, privacy: .public) failed: \(String(cString: strerror(code)), privacy: .public)")
                }
            }
        }
        return sent
    }
}
