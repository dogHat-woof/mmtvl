import Darwin
import Foundation

/// Which URLs the HLS relay registers, rewrites into a playlist and fetches, and which redirects it and the stream
/// resolver follow (pre-release security review, item 5). Only http and https URLs with a host. A host on the Mac or
/// the LAN (loopback, link-local, private or shared IPv4, IPv6 loopback, link-local or unique local, "localhost",
/// ".local" and dotless names) only when the stream's own URL is on that same host, so a LAN IPTV server still plays
/// but a playlist can't make MMTVL fetch from the Mac or other LAN devices. Pre-release lows (c): a stream whose own
/// host is itself on the LAN (an RFC 1918 or unique local address, or a LAN name: ".local", ".lan", ".home.arpa",
/// dotless) may also reach another LAN device by its private address (RFC 1918 or unique local; never loopback,
/// link-local, 0/8, a name, or one of the Mac's own addresses), e.g. a Threadfin/xTeVe proxy redirecting to a tuner.
/// A public stream still never reaches an internal host. Names are judged as written: a public name that resolves to
/// a LAN address isn't caught. Pure, apart from reading the Mac's own addresses (injectable).
nonisolated enum RelayURLPolicy {
    /// http or https with a non-empty host.
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return host(of: url) != nil
    }

    /// `url` may be fetched for the stream whose original (first registered) URL is `stream`. `ownAddresses`: the
    /// Mac's interface addresses (read only when a LAN stream reaches another LAN address).
    static func allows(_ url: URL, stream: URL,
                       ownAddresses: () -> [String] = LANAddress.ownAddresses) -> Bool {
        guard isWebURL(url), isWebURL(stream), let urlHost = host(of: url) else { return false }
        guard isInternal(urlHost) else { return true }
        guard let streamHost = host(of: stream) else { return false }
        if sameHost(urlHost, streamHost) { return true }
        // Pre-release lows (c): LAN to LAN, by private address only, never to the Mac itself.
        guard isLANStreamHost(streamHost), isPrivateLANAddress(urlHost) else { return false }
        return !ownAddresses().contains { sameHost($0, urlHost) }
    }

    /// Pre-release lows (c): a stream host on the LAN: an RFC 1918 or unique local address (not loopback, link-local
    /// or shared), or a LAN name (".local", ".lan", ".home.arpa", dotless; not "localhost").
    static func isLANStreamHost(_ host: String) -> Bool {
        guard let host = LANAddress.normalized(host) else { return false }
        if isPrivateLANAddress(host) { return true }
        let address = withoutZone(host)
        guard ipv4(address) == nil, ipv6(address) == nil, host != "localhost", !host.hasSuffix(".localhost") else {
            return false
        }
        return host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa") || !host.contains(".")
    }

    /// Pre-release lows (c): an RFC 1918 IPv4 address (10/8, 172.16/12, 192.168/16) or an IPv6 unique local one
    /// (fc00::/7), or an IPv4-mapped form of an RFC 1918 one, as a literal. Not loopback, link-local, 0/8, shared
    /// (100.64/10) or broadcast, and never a name.
    static func isPrivateLANAddress(_ host: String) -> Bool {
        guard let host = LANAddress.normalized(host) else { return false }
        if let bytes = ipv4(host) { return isRFC1918(bytes) }
        let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        // A zone only means something on a link-local address, which isn't allowed.
        guard parts.count == 1, let bytes = ipv6(host) else { return false }
        if bytes[0] & 0xFE == 0xFC { return true }
        let mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        return mapped && isRFC1918(Array(bytes[12..<16]))
    }

    /// Loopback, link-local, private or unspecified addresses, and names that only resolve on the Mac or the LAN.
    static func isInternal(_ host: String) -> Bool {
        guard let host = LANAddress.normalized(host) else { return true }
        let address = withoutZone(host)
        if let bytes = ipv4(address) { return isInternal(ipv4: bytes) }
        if let bytes = ipv6(address) { return isInternal(ipv6: bytes) }
        return host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || !host.contains(".")
    }

    // MARK: - Private

    private static func host(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        return host
    }

    /// The same address in any literal form, or the same name.
    private static func sameHost(_ a: String, _ b: String) -> Bool {
        guard let a = LANAddress.normalized(a), let b = LANAddress.normalized(b) else { return false }
        if let x = ipv4(withoutZone(a)), let y = ipv4(withoutZone(b)) { return x == y }
        if let x = ipv6(withoutZone(a)), let y = ipv6(withoutZone(b)) { return x == y && zone(a) == zone(b) }
        return a == b
    }

    private static func isRFC1918(_ bytes: [UInt8]) -> Bool {
        switch (bytes[0], bytes[1]) {
        case (10, _), (172, 16...31), (192, 168): true
        default: false
        }
    }

    /// 0/8, 10/8, 100.64/10 (shared), 127/8, 169.254/16, 172.16/12, 192.168/16, and broadcast.
    private static func isInternal(ipv4 bytes: [UInt8]) -> Bool {
        switch (bytes[0], bytes[1]) {
        case (0, _), (127, _): return true
        case (100, 64...127): return true
        case (255, 255): return true
        default: return LANAddress.isPrivate(ipv4: bytes)
        }
    }

    /// ::, ::1, fe80::/10, fec0::/10, fc00::/7, and IPv4-mapped or -compatible forms of an internal IPv4 address.
    private static func isInternal(ipv6 bytes: [UInt8]) -> Bool {
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] <= 1 { return true }
        if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0xC0 { return true }
        if LANAddress.isLAN(ipv6: bytes) { return true }
        let embedsIPv4 = bytes[0..<10].allSatisfy { $0 == 0 }
            && ((bytes[10] == 0xFF && bytes[11] == 0xFF) || (bytes[10] == 0 && bytes[11] == 0))
        return embedsIPv4 && isInternal(ipv4: Array(bytes[12..<16]))
    }

    private static func withoutZone(_ host: String) -> String {
        host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? host
    }

    private static func zone(_ host: String) -> String? {
        let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[1]) : nil
    }

    /// inet_aton, not inet_pton: the resolver also takes "127.1", "0x7f.0.0.1" and "2130706433" as addresses.
    private static func ipv4(_ text: String) -> [UInt8]? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == "." || $0 == "x" || $0 == "X") })
        else { return nil }
        var address = in_addr()
        guard inet_aton(text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address.s_addr) { Array($0) }
    }

    private static func ipv6(_ text: String) -> [UInt8]? {
        guard text.contains(":") else { return nil }
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
}
