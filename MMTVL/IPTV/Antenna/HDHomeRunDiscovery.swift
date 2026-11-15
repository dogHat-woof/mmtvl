import Darwin
import Foundation
import os

// M7j step 2 (L4): finding HDHomeRun tuners. A discover request to each LAN interface's directed broadcast (UDP
// 65001; 255.255.255.255 fails on a Mac with several interfaces), sent twice, replies collected for 1 s and
// de-duplicated by DeviceID (a tuner answers twice), then each device's `discover.json`. Only LAN interfaces are
// searched: never a VPN, tunnel, bridge or overlay network (WakeOnLAN's names), and only those with a private or
// link-local address (L4 keeps 169.254, which a tuner on a direct cable uses). A device is kept only when the reply
// came from a private IPv4 address on the subnet of an interface the request went out on, not the Mac's own; its
// BaseURL is the bare origin `http://<that address>` (port 80 at most); its LineupURL is http on the same address;
// `TunerCount` is 1…16; and `discover.json` decodes. `discover.json` is always fetched from `http://<source>/`, never
// from a path or port a reply names. Only when UDP finds nothing, `hdhomerun.local` is resolved (mDNS, IPv4) and each
// address that passes the same checks is asked by IP literal. Logs counts and interface names only: never a
// DeviceID, DeviceAuth, address or URL (L15).

/// One UDP datagram and the IPv4 address it came from (`recvfrom`). Its descriptions and mirror show the size
/// only, never the address or the bytes (which hold the DeviceID).
nonisolated struct HDHomeRunDatagram: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    var data: Data
    var sourceAddress: String

    var description: String { "HDHomeRunDatagram(\(data.count) bytes)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["byteCount": data.count], displayStyle: .struct) }
}

/// Main actor. The interfaces, `send` (broadcast and collect), `resolve` (the mDNS fallback) and `fetch` (the
/// tuner's HTTP) are injected for tests.
enum HDHomeRunDiscovery {
    /// Sends `request` to each target's broadcast address and returns the datagrams that came back within `duration`.
    typealias Send = (_ request: Data, _ targets: [HDHomeRunBroadcaster.Target], _ duration: Duration) async
        -> [HDHomeRunDatagram]
    /// A host name's IPv4 addresses, as dotted quads.
    typealias Resolve = @Sendable (_ host: String) async -> [String]

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Antenna")

    static let fallbackHost = "hdhomerun.local"
    /// At most this many of the fallback name's addresses are asked.
    static let maximumFallbackAddresses = 4
    static let tunerCountRange = 1...16
    /// At most this many devices are fetched per search (a flood of forged replies can't make more requests).
    static let maximumDevices = 16
    /// FriendlyName and ModelNumber are cut to this many characters (security L4).
    nonisolated static let maximumNameLength = 64
    /// Host-only virtual machine networks (VirtualBox, Parallels) that have `IFF_BROADCAST` and a private /24 but are
    /// never the tuner's LAN; skipped by discovery on top of `WakeOnLAN.excludedInterfacePrefixes` (security L-c).
    static let excludedInterfacePrefixes = WakeOnLAN.excludedInterfacePrefixes + ["vboxnet", "vnic"]
    static let resendInterval: Duration = .milliseconds(300)

    /// The tuners that passed L4's checks, in DeviceID order (L1). `ownAddresses`: a reply from the Mac itself is
    /// refused, so a forged one can't aim the fetch at MMTVL's own listeners.
    static func find(duration: Duration = .seconds(1),
                     interfaces: () -> [WakeOnLAN.Interface] = WakeOnLAN.interfaces,
                     send: Send = { await HDHomeRunBroadcaster.search($0, to: $1, duration: $2) },
                     resolve: @escaping Resolve = { await HDHomeRunResolver.resolve($0) },
                     fetch: @escaping HDHomeRunHTTP.Fetch = HDHomeRunHTTP.live,
                     ownAddresses: () -> [String] = LANAddress.ownAddresses) async -> [HDHomeRunDevice] {
        let http = HDHomeRunHTTP(fetch: fetch)
        let own = ownAddresses()
        let searched = searchInterfaces(interfaces())
        guard !searched.isEmpty else {
            logger.notice("Antenna discovery: no LAN interface to search on")
            return []
        }
        let datagrams = await send(HDHomeRunPacket.discoverRequest, targets(searched), duration)
        let candidates = Self.candidates(datagrams, subnets: searched, ownAddresses: own)
        let fetches = candidates.map { candidate in
            Task { (candidate, await http.discover(candidate.discoverURL)) }
        }
        var devices: [HDHomeRunDevice] = []
        for fetch in fetches {
            let (candidate, discover) = await fetch.value
            guard let discover,
                  let device = Self.device(discover, expectedHost: candidate.sourceAddress,
                                           deviceID: candidate.deviceID, ownAddresses: own),
                  !devices.contains(where: { $0.id == device.id })
            else { continue }
            devices.append(device)
        }
        if devices.isEmpty,
           let device = await fallback(resolve: resolve, http: http, subnets: searched, ownAddresses: own) {
            devices.append(device)
        }
        devices.sort { $0.id < $1.id }
        let slots = devices.reduce(0) { $0 + $1.tunerCount }
        logger.notice("Found \(devices.count, privacy: .public) tuners (\(slots, privacy: .public) tuner slots)")
        return devices
    }

    // MARK: Interfaces (security M1)

    /// An interface discovery searches on: up, broadcast-capable, not loopback or point-to-point, not a VPN, tunnel,
    /// bridge, overlay or host-only network by name (`excludedInterfacePrefixes`), with a private or link-local IPv4
    /// address of its own. Unlike `WakeOnLAN.isUsable`, 169.254 is allowed (L4).
    static func isSearchable(_ interface: WakeOnLAN.Interface) -> Bool {
        interface.isUp && !interface.isLoopback && interface.isBroadcast && !interface.isPointToPoint
            && !excludedInterfacePrefixes.contains(where: { interface.name.hasPrefix($0) })
            && interface.address.count == 4 && LANAddress.isPrivate(ipv4: interface.address)
    }

    /// The searchable interfaces that have a subnet broadcast address (not /31 or /32), one per address.
    static func searchInterfaces(_ interfaces: [WakeOnLAN.Interface]) -> [WakeOnLAN.Interface] {
        var result: [WakeOnLAN.Interface] = []
        for interface in interfaces where isSearchable(interface) {
            guard WakeOnLAN.broadcast(address: interface.address, netmask: interface.netmask) != nil,
                  !result.contains(where: { $0.name == interface.name && $0.address == interface.address })
            else { continue }
            result.append(interface)
        }
        return result
    }

    /// Where the request goes: each search interface's subnet broadcast, once per interface and address.
    static func targets(_ interfaces: [WakeOnLAN.Interface]) -> [HDHomeRunBroadcaster.Target] {
        var result: [HDHomeRunBroadcaster.Target] = []
        for interface in interfaces {
            guard let broadcast = WakeOnLAN.broadcast(address: interface.address, netmask: interface.netmask)
            else { continue }
            let target = HDHomeRunBroadcaster.Target(interface: interface.name, broadcast: broadcast)
            if !result.contains(target) { result.append(target) }
        }
        return result
    }

    /// `address` as its canonical dotted quad when it is a private (or link-local) IPv4 address on the subnet of one
    /// of `subnets` (the interfaces the request went out on) and not one of the Mac's own addresses; nil otherwise.
    static func acceptableSource(_ address: String, subnets: [WakeOnLAN.Interface], ownAddresses: [String]) -> String? {
        guard let canonical = canonicalIPv4(address), let bytes = WakeOnLAN.ipv4(canonical),
              LANAddress.isPrivate(ipv4: bytes),
              subnets.contains(where: { WakeOnLAN.isOnSubnet(bytes, of: $0) }),
              !ownAddresses.contains(where: { LANAddress.sameAddress($0, canonical) })
        else { return nil }
        return canonical
    }

    // MARK: Replies

    /// A reply worth fetching `discover.json` for. Its descriptions and mirror show nothing of the id, the address
    /// or the URL.
    nonisolated struct Candidate: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        var deviceID: UInt32
        var sourceAddress: String
        var discoverURL: URL

        var description: String { "HDHomeRunDiscovery.Candidate" }
        var debugDescription: String { description }
        var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
    }

    /// The tuner replies from an `acceptableSource` whose BaseURL is the bare origin on that same address; one per
    /// DeviceID (the first), at most `maximumDevices`. `discover.json` is asked at `http://<source>/discover.json`.
    static func candidates(_ datagrams: [HDHomeRunDatagram], subnets: [WakeOnLAN.Interface],
                           ownAddresses: [String]) -> [Candidate] {
        var result: [Candidate] = []
        for datagram in datagrams {
            guard result.count < maximumDevices,
                  let source = acceptableSource(datagram.sourceAddress, subnets: subnets, ownAddresses: ownAddresses),
                  let reply = HDHomeRunPacket.parseDiscoverReply(datagram.data),
                  !result.contains(where: { $0.deviceID == reply.deviceID }),
                  let baseURL = reply.baseURL, isOrigin(baseURL, of: source),
                  let discoverURL = discoverURL(for: source)
            else { continue }
            result.append(Candidate(deviceID: reply.deviceID, sourceAddress: source, discoverURL: discoverURL))
        }
        return result
    }

    /// `http://<address>/discover.json`, built from the address itself (security M3).
    static func discoverURL(for address: String) -> URL? {
        guard let canonical = canonicalIPv4(address) else { return nil }
        return URL(string: "http://\(canonical)/discover.json")
    }

    /// The device `discover` describes, when its DeviceID is 8 hex digits (and, given the UDP reply's `deviceID`,
    /// that same id, ignoring case; security L-d), its BaseURL is the bare origin on `expectedHost` (the address that
    /// answered), its LineupURL is http on the same address, and `TunerCount` is 1…16. An `expectedHost` that isn't
    /// a private IPv4 literal, or is one of the Mac's own addresses, is refused.
    static func device(_ discover: HDHomeRunDiscover, expectedHost: String, deviceID: UInt32? = nil,
                       ownAddresses: [String]) -> HDHomeRunDevice? {
        guard tunerCountRange.contains(discover.tunerCount), let id = deviceIDValue(discover.deviceID),
              deviceID.map({ $0 == id }) ?? true,
              let host = canonicalIPv4(expectedHost), let bytes = WakeOnLAN.ipv4(host),
              LANAddress.isPrivate(ipv4: bytes),
              !ownAddresses.contains(where: { LANAddress.sameAddress($0, host) }),
              let baseURL = URL(string: discover.baseURL), isOrigin(baseURL, of: host),
              let lineupURL = URL(string: discover.lineupURL), isLineupURL(lineupURL, on: host)
        else { return nil }
        let name = displayText(discover.friendlyName)
        return HDHomeRunDevice(id: discover.deviceID, name: name.isEmpty ? "HDHomeRun" : name,
                               model: displayText(discover.modelNumber), tunerCount: discover.tunerCount,
                               baseURL: baseURL, lineupURL: lineupURL)
    }

    // MARK: URL checks (security M3)

    /// `url`'s host **as written** (Foundation's percent-encoded form) when that is a canonical dotted quad; nil for
    /// a name, a percent-encoded literal (`10.0.0%2E9`, which Foundation decodes but ffmpeg wouldn't), leading zeros
    /// and the like. Step 3 security M1: every URL check compares this, never the decoded host.
    nonisolated static func literalHost(of url: URL) -> String? {
        guard let raw = url.host(percentEncoded: true) else { return nil }
        return canonicalIPv4(raw)
    }

    /// http, no user name or password, the raw host exactly `address` (a canonical dotted quad), port 80 or none, as
    /// written (`writtenPort`).
    nonisolated static func isHTTP(_ url: URL, on address: String) -> Bool {
        guard url.scheme?.lowercased() == "http", url.user == nil, url.password == nil,
              let host = literalHost(of: url), let canonical = canonicalIPv4(address)
        else { return false }
        return host == canonical && (writtenPort(of: url) == .none || writtenPort(of: url) == .valid(80))
    }

    /// The port in a URL's string, as `writtenPort(of:)` reads it.
    nonisolated enum WrittenPort: Equatable, Sendable {
        /// No `:` after the host.
        case none
        /// 1–5 ASCII digits with a value in 1…65535.
        case valid(Int)
        /// Anything else after a `:`, an empty `:` included.
        case invalid
    }

    /// Step 10 (step 3's port low): the port **as written** in `url`'s authority (after `://`, up to the first `/`,
    /// `?` or `#`, after the last `@`). Foundation reads an unparseable port (`:99999999999999999999`, an empty `:`)
    /// as no port while keeping the string, which ffmpeg then loads on port 80 or 0. Leading zeros are allowed
    /// (`:080` is 80 to both Foundation and ffmpeg's `strtol`), as long as the text is at most 5 digits. A written
    /// port that Foundation reads differently, or a port Foundation sees where none is written, is `.invalid`.
    nonisolated static func writtenPort(of url: URL) -> WrittenPort {
        let text = url.absoluteString
        guard let schemeEnd = text.range(of: "://") else { return .invalid }
        var authority = text[schemeEnd.upperBound...]
        if let end = authority.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            authority = authority[..<end]
        }
        if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
        var afterHost = authority
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return .invalid }
            afterHost = authority[authority.index(after: close)...]
        }
        guard let colon = afterHost.firstIndex(of: ":") else { return url.port == nil ? .none : .invalid }
        let digits = afterHost[afterHost.index(after: colon)...].utf8
        guard (1...5).contains(digits.count), digits.allSatisfy({ (0x30...0x39).contains($0) }),
              let value = Int(Substring(digits)), (1...65535).contains(value), url.port == value
        else { return .invalid }
        return .valid(value)
    }

    /// A BaseURL: `isHTTP` and nothing after the origin (no path but "/", no query, no fragment).
    nonisolated static func isOrigin(_ url: URL, of address: String) -> Bool {
        let path = url.path(percentEncoded: true)
        return isHTTP(url, on: address) && (path.isEmpty || path == "/")
            && url.query(percentEncoded: true) == nil && url.fragment(percentEncoded: true) == nil
    }

    /// A LineupURL: `isHTTP` (any path) with no query or fragment.
    nonisolated static func isLineupURL(_ url: URL, on address: String) -> Bool {
        isHTTP(url, on: address) && url.query(percentEncoded: true) == nil && url.fragment(percentEncoded: true) == nil
    }

    /// The dotted quad `inet_ntop` writes for `address`, when `address` is exactly that (no leading zeros, spaces or
    /// trailing dot); nil otherwise.
    nonisolated static func canonicalIPv4(_ address: String) -> String? {
        guard let bytes = WakeOnLAN.ipv4(address) else { return nil }
        let text = bytes.map(String.init).joined(separator: ".")
        return text == address ? text : nil
    }

    private static let hexDigits = Set("0123456789abcdefABCDEF".utf8)

    /// A DeviceID's value: exactly 8 ASCII hex digits, either case; nil otherwise (security L-d).
    static func deviceIDValue(_ id: String) -> UInt32? {
        guard id.utf8.count == 8, id.utf8.allSatisfy({ hexDigits.contains($0) }) else { return nil }
        return UInt32(id, radix: 16)
    }

    /// FriendlyName or ModelNumber for display (security L4, L-a): control, format, line and paragraph separator
    /// characters (Unicode Cc, Cf, Zl, Zp: bidi overrides, zero-width marks, U+2028/U+2029) removed, trimmed, at most
    /// `maximumNameLength` Unicode scalars (so a pile of combining marks can't make one huge character); "" when
    /// nothing is left.
    nonisolated static func displayText(_ text: String?) -> String {
        guard let text else { return "" }
        let scalars = text.unicodeScalars.filter {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: false
            default: true
            }
        }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(String.UnicodeScalarView(cleaned.unicodeScalars.prefix(maximumNameLength)))
        return capped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: The hdhomerun.local fallback (security M2)

    /// `hdhomerun.local`'s IPv4 addresses that pass `acceptableSource`, each asked `http://<ip>/discover.json` by IP
    /// literal; the first that describes a device on that same address.
    private static func fallback(resolve: Resolve, http: HDHomeRunHTTP, subnets: [WakeOnLAN.Interface],
                                 ownAddresses: [String]) async -> HDHomeRunDevice? {
        var asked: [String] = []
        for address in await resolve(fallbackHost) {
            guard asked.count < maximumFallbackAddresses,
                  let source = acceptableSource(address, subnets: subnets, ownAddresses: ownAddresses),
                  !asked.contains(source), let url = discoverURL(for: source)
            else { continue }
            asked.append(source)
            if let discover = await http.discover(url),
               let device = device(discover, expectedHost: source, ownAddresses: ownAddresses) {
                return device
            }
        }
        return nil
    }
}

/// Resolves a name to IPv4 addresses (`getaddrinfo`, `AF_INET`; mDNS for `.local`) off the main thread, giving up
/// after `timeout`. Never logs the name's addresses.
nonisolated enum HDHomeRunResolver {
    static let timeout: TimeInterval = 2
    /// At most this many addresses are returned.
    static let maximumAddresses = 16

    static func resolve(_ host: String, timeout: TimeInterval = timeout) async -> [String] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async { once.resume(lookup(host)) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { once.resume([]) }
        }
    }

    /// The blocking lookup: IPv4 addresses as dotted quads, de-duplicated.
    static func lookup(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &head) == 0, let head else { return [] }
        defer { freeaddrinfo(head) }
        var result: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let entry = cursor, result.count < maximumAddresses {
            cursor = entry.pointee.ai_next
            guard entry.pointee.ai_family == AF_INET, let address = entry.pointee.ai_addr,
                  Int(entry.pointee.ai_addrlen) >= MemoryLayout<sockaddr_in>.size
            else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let ok = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var addr = sin.pointee.sin_addr
                return inet_ntop(AF_INET, &addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil
            }
            guard ok else { continue }
            let dotted = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !result.contains(dotted) { result.append(dotted) }
        }
        return result
    }

    /// Resumes the continuation with the first answer (the lookup or the timeout).
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String], Never>?

        init(_ continuation: CheckedContinuation<[String], Never>) { self.continuation = continuation }

        func resume(_ value: [String]) {
            let pending = lock.withLock { () -> CheckedContinuation<[String], Never>? in
                defer { continuation = nil }
                return continuation
            }
            pending?.resume(returning: value)
        }
    }
}

/// The UDP side of discovery: one socket on an ephemeral port (`SO_BROADCAST`, non-blocking), the request sent to
/// each target's broadcast address twice 300 ms apart, replies read on the main queue (`DispatchSource`, like
/// `SSDPSearcher`) for `duration`, then the socket closed. Main queue.
enum HDHomeRunBroadcaster {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Antenna")
    /// Longer datagrams are cut short, so their CRC fails.
    static let datagramSize = 1500

    /// An interface's name (for logs) and its IPv4 broadcast address (network byte order; never logged).
    struct Target: Equatable {
        var interface: String
        var broadcast: [UInt8]
    }

    /// Keeps the datagrams worth parsing (security L1, L2). Only parsed tuner replies count toward
    /// `maximumReplies`; an identical datagram from the same address is kept once, and at most `maximumPerSource`
    /// per address (a tuner sends two replies to each of the two requests). Reading stops for good after
    /// `maximumDatagrams` datagrams of any kind, and each read event takes at most `readsPerEvent`, so a flood can't
    /// hold the main queue.
    final class Collector {
        static let maximumReplies = 64
        static let maximumDatagrams = 256
        static let maximumPerSource = 4
        static let readsPerEvent = 32

        private(set) var datagrams: [HDHomeRunDatagram] = []
        /// Every datagram read, kept or not.
        private(set) var datagramsRead = 0

        /// No more reading: the hard cap, or enough replies.
        var isFinished: Bool {
            datagramsRead >= Self.maximumDatagrams || datagrams.count >= Self.maximumReplies
        }

        /// One datagram read from the socket; `source` is nil when it didn't come from an IPv4 address.
        func receive(_ data: Data, from source: String?) {
            guard !isFinished else { return }
            datagramsRead += 1
            guard let source else { return }
            let datagram = HDHomeRunDatagram(data: data, sourceAddress: source)
            guard !datagrams.contains(datagram),
                  datagrams.count(where: { $0.sourceAddress == source }) < Self.maximumPerSource,
                  HDHomeRunPacket.parseDiscoverReply(data) != nil
            else { return }
            datagrams.append(datagram)
        }

        /// Reads what is waiting on the non-blocking `fd`, at most `readsPerEvent` datagrams.
        func read(_ fd: Int32) {
            var buffer = [UInt8](repeating: 0, count: HDHomeRunBroadcaster.datagramSize)
            for _ in 0..<Self.readsPerEvent {
                guard !isFinished else { return }
                var sender = sockaddr_in()
                var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &sender) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, &buffer, buffer.count, 0, $0, &senderLength)
                    }
                }
                guard count >= 0 else { return }   // EAGAIN: nothing more waiting
                receive(Data(buffer[0..<count]), from: Self.ipv4Source(sender, length: senderLength))
            }
        }

        private static func ipv4Source(_ sender: sockaddr_in, length: socklen_t) -> String? {
            guard Int(length) >= MemoryLayout<sockaddr_in>.size, sender.sin_family == sa_family_t(AF_INET)
            else { return nil }
            var address = sender.sin_addr
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    /// The datagrams worth parsing that came back within `duration`.
    static func search(_ request: Data, to targets: [Target], duration: Duration) async -> [HDHomeRunDatagram] {
        guard !targets.isEmpty, let fd = openSocket() else { return [] }
        let collector = Collector()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak source] in
            MainActor.assumeIsolated {
                collector.read(fd)
                if collector.isFinished { source?.cancel() }
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        var failed: Set<String> = []
        send(request, on: fd, to: targets, failed: &failed)
        try? await Task.sleep(for: min(HDHomeRunDiscovery.resendInterval, duration))
        // Once the collector is finished the source is cancelled and `fd` closed (or reused): never send on it.
        if !collector.isFinished, !source.isCancelled {
            send(request, on: fd, to: targets, failed: &failed)
        }
        if duration > HDHomeRunDiscovery.resendInterval, !collector.isFinished {
            try? await Task.sleep(for: duration - HDHomeRunDiscovery.resendInterval)
        }
        source.cancel()
        return collector.datagrams
    }

    /// Sets `O_NONBLOCK` on `fd`; false when either `fcntl` fails (security L2).
    static func setNonBlocking(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
    }

    private static func openSocket() -> Int32? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            logger.error("Antenna discovery: can't open a socket: \(String(cString: strerror(errno)), privacy: .public)")
            return nil
        }
        var yes: Int32 = 1
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0   // any free port; replies come back to it by unicast
        address.sin_addr.s_addr = INADDR_ANY
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0,
              withUnsafePointer(to: &address, {
                  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                      bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                  }
              }) == 0,
              setNonBlocking(fd)
        else {
            logger.error("Antenna discovery: socket setup failed: \(String(cString: strerror(errno)), privacy: .public)")
            Darwin.close(fd)
            return nil
        }
        return fd
    }

    /// Sends to each target; a failure is logged once per interface per search (its name only).
    private static func send(_ request: Data, on fd: Int32, to targets: [Target], failed: inout Set<String>) {
        for target in targets where target.broadcast.count == 4 {
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = HDHomeRunPacket.port.bigEndian
            withUnsafeMutableBytes(of: &destination.sin_addr.s_addr) { $0.copyBytes(from: target.broadcast) }
            let sent = request.withUnsafeBytes { bytes in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent < 0 else { continue }
            let code = errno
            guard failed.insert(target.interface).inserted else { continue }
            if code == EHOSTUNREACH || code == EPERM {
                logger.error("Can't send on \(target.interface, privacy: .public): allow Local Network for MMTVL")
            } else {
                logger.error("Antenna discovery: can't send on \(target.interface, privacy: .public): \(String(cString: strerror(code)), privacy: .public)")
            }
        }
    }
}
