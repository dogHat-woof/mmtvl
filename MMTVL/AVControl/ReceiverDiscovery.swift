import Darwin
import Foundation
import os

// M7h L17: Find on Network. An SSDP M-SEARCH (`ssdp:all`, 3 s), each `LOCATION`'s device description (http, LAN
// hosts only, 2 s, 64 KB cap), its `manufacturer` mapped to brands, then each candidate checked with that brand's
// read-only `probeQueries` on its control port. The SSDP sender and parsing, `LANAddress` and the description fetch
// are shared with step 9b's TV search (another search target). Logs show hosts and ports only, never a URL or a
// description body. **Untested on a real networked receiver.**

/// Which hosts MMTVL connects to on the LAN (L17, L18): private IPv4 (10/8, 172.16/12, 192.168/16), IPv4
/// link-local (169.254/16), IPv6 link-local (fe80::/10, with no zone or a zone that isn't a loopback interface) and
/// unique local (fc00::/7), and `.local` names. No public addresses, no loopback. Names resolve later, so a
/// connection also checks the address it reached (`ReceiverTCPTransport.isLANRemote`); SSDP `LOCATION`s must be
/// IP literals (`isLANIPLiteral`). Pure, apart from looking up a zone's interface.
nonisolated enum LANAddress {
    /// Trimmed and lowercased, without IPv6 brackets or a trailing dot; nil when empty.
    static func normalized(_ host: String) -> String? {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host = String(host.dropLast()) }
        return host.isEmpty ? nil : host
    }

    static func isLAN(_ host: String) -> Bool {
        guard let host = normalized(host) else { return false }
        return isLANIPLiteral(host, allowsZone: true) || isLocalName(host)
    }

    /// A LAN IP literal (no name). `allowsZone`: an IPv6 zone ("fe80::1%en0") is accepted unless it names a loopback
    /// interface (`fe80::1%lo0` is the Mac's own lo0) or no interface at all.
    static func isLANIPLiteral(_ host: String, allowsZone: Bool = false) -> Bool {
        guard let host = normalized(host) else { return false }
        if let bytes = ipv4(host) { return isPrivate(ipv4: bytes) }
        guard host.contains(":") else { return false }
        let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2 {
            guard allowsZone, !isLoopbackOrUnknown(zone: parts[1]) else { return false }
        }
        guard let bytes = ipv6(parts[0]) else { return false }
        return isLAN(ipv6: bytes)
    }

    /// The user's `receiverHost` (L17): a LAN address or `.local` name, or any other DNS name ("receiver.lan"), which
    /// is only used if it resolves to a LAN address (checked when the connection is up).
    static func isAllowedReceiverHost(_ host: String) -> Bool {
        guard let host = normalized(host) else { return false }
        return isLAN(host) || isDNSName(host)
    }

    /// Both literals of the same address ("192.168.1.20" and its inet_ntop form), or equal names.
    static func sameAddress(_ a: String, _ b: String) -> Bool {
        guard let a = normalized(a), let b = normalized(b) else { return false }
        if let x = ipv4(a), let y = ipv4(b) { return x == y }
        if let x = ipv6(a), let y = ipv6(b) { return x == y }
        return a == b
    }

    /// The Mac's own interface addresses, IPv4 and IPv6 (getifaddrs; KAME's embedded link-local scope cleared).
    static func ownAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }
        var result: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                let ok = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    var addr = sin.pointee.sin_addr
                    return inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count)) != nil
                }
                guard ok else { continue }
            case AF_INET6:
                let ok = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                    var addr = sin6.pointee.sin6_addr
                    withUnsafeMutableBytes(of: &addr) { bytes in
                        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { bytes[2] = 0; bytes[3] = 0 }
                    }
                    return inet_ntop(AF_INET6, &addr, &buffer, socklen_t(buffer.count)) != nil
                }
                guard ok else { continue }
            default:
                continue
            }
            result.append(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return result
    }

    /// "192.168.1.20:23", "[fe80::1]:23" (for logs and transport names).
    static func display(host: String, port: UInt16) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    static func isPrivate(ipv4 bytes: [UInt8]) -> Bool {
        switch (bytes[0], bytes[1]) {
        case (10, _): true
        case (172, 16...31): true
        case (192, 168): true
        case (169, 254): true
        default: false
        }
    }

    /// fe80::/10 (link-local) or fc00::/7 (unique local).
    static func isLAN(ipv6 bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        let linkLocal = bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80
        let uniqueLocal = bytes[0] & 0xFE == 0xFC
        return linkLocal || uniqueLocal
    }

    /// A zone by name ("lo0", "en0") or index ("1"): true for a loopback interface, or one that doesn't exist.
    private static func isLoopbackOrUnknown(zone: String) -> Bool {
        var name = zone
        if let index = UInt32(zone) {
            var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
            guard if_indextoname(index, &buffer) != nil else { return true }
            name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        guard !name.isEmpty, if_nametoindex(name) != 0 else { return true }
        if name.hasPrefix("lo") { return true }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return true }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            if String(cString: entry.pointee.ifa_name) == name, Int32(entry.pointee.ifa_flags) & IFF_LOOPBACK != 0 {
                return true
            }
            cursor = entry.pointee.ifa_next
        }
        return false
    }

    /// "receiver.local", "Living-Room-AVR.local": DNS labels ending in `.local`.
    private static func isLocalName(_ host: String) -> Bool {
        host.hasSuffix(".local") && isDNSName(host) && host.split(separator: ".").count >= 2
    }

    /// Letters, digits and hyphens in labels of 1–63 characters, at most 253 in all; the last label isn't all digits
    /// (so "10.1" isn't a name).
    private static func isDNSName(_ host: String) -> Bool {
        guard host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard let last = labels.last, !last.allSatisfy(\.isNumber) else { return false }
        return labels.allSatisfy { label in
            (1...63).contains(label.count) && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// Strict dotted quad ("10.1" and "010.0.0.1" style shorthands are refused by inet_pton).
    private static func ipv4(_ text: String) -> [UInt8]? {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address.s_addr) { Array($0) }
    }

    private static func ipv6(_ text: String) -> [UInt8]? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
}

// MARK: SSDP search

/// One answer to an M-SEARCH. `location` may carry a path and query: never log it, only its host.
nonisolated struct SSDPSearchResponse: Equatable, Sendable {
    var location: String
    var searchTarget: String?
    var usn: String?
    var server: String?
    /// The address the reply came from (`recvfrom`); the `LOCATION` host must be the same.
    var sourceAddress: String?
}

/// Sending an M-SEARCH and reading the answers (`Cast/DIALProtocol`'s `SSDP` answers searches; this sends one).
/// Pure.
nonisolated enum SSDPSearch {
    static let allTarget = "ssdp:all"

    /// The M-SEARCH datagram (CRLF lines, ends with an empty line). Devices answer within `mx` seconds.
    static func request(searchTarget: String, mx: Int) -> Data {
        let lines = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(SSDP.multicastAddress):\(SSDP.port)",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(searchTarget)",
            "USER-AGENT: macOS/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) UPnP/1.1 MMTVL/1.0",
            "",
            "",
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    /// "HTTP/1.1 200 OK" with a `LOCATION` header (names case-insensitive); nil for anything else (NOTIFYs, other
    /// searches, errors).
    static func parseResponse(_ datagram: Data) -> SSDPSearchResponse? {
        guard let text = String(data: datagram, encoding: .utf8) else { return nil }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let status = lines.first?.trimmingCharacters(in: .whitespaces).uppercased(),
              status.hasPrefix("HTTP/1."), status.split(separator: " ").dropFirst().first == "200"
        else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[name] == nil { headers[name] = value }
        }
        guard let location = headers["location"], !location.isEmpty else { return nil }
        return SSDPSearchResponse(location: location, searchTarget: headers["st"], usn: headers["usn"],
                                  server: headers["server"])
    }

    /// The description URL in `location` when MMTVL may fetch it: http (not https, no other scheme), no user name,
    /// and a LAN IP literal host (no names, which resolve later, and no IPv6 zones). nil otherwise.
    static func descriptionURL(_ location: String) -> URL? {
        guard let url = URL(string: location.trimmingCharacters(in: .whitespaces)),
              url.scheme?.lowercased() == "http", url.user == nil, url.password == nil,
              let host = url.host(percentEncoded: false), LANAddress.isLANIPLiteral(host)
        else { return nil }
        return url
    }

    /// `descriptionURL` of the reply's `LOCATION`, only when its host is the address the reply came from (a device
    /// can't point MMTVL at another host) and isn't one of the Mac's own (`ownAddresses`, by default
    /// `LANAddress.ownAddresses()`): a spoofed reply could otherwise aim the fetch at MMTVL's own listeners. MMTVL's
    /// own DIAL reply drops out too.
    static func descriptionURL(for response: SSDPSearchResponse, ownAddresses: [String]? = nil) -> URL? {
        guard let source = response.sourceAddress, let url = descriptionURL(response.location),
              let host = url.host(percentEncoded: false), LANAddress.sameAddress(host, source)
        else { return nil }
        let own = ownAddresses ?? LANAddress.ownAddresses()
        guard !own.contains(where: { LANAddress.sameAddress($0, host) }) else { return nil }
        return url
    }

    /// The URL's host, normalized (for logs and connections).
    static func host(of url: URL) -> String? {
        url.host(percentEncoded: false).flatMap(LANAddress.normalized)
    }
}

/// Sends an M-SEARCH from an ephemeral UDP port (`SO_REUSEADDR`/`SO_REUSEPORT` like `SSDPResponder`) and collects
/// the unicast answers for a while. Main queue.
enum SSDPSearcher {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Receiver")
    /// More answers than this are dropped (a busy LAN answers `ssdp:all` once per service).
    static let maximumResponses = 256
    static let datagramSize = 2048

    private final class Collector {
        var responses: [SSDPSearchResponse] = []
        var locations: Set<String> = []

        func read(_ fd: Int32) {
            var buffer = [UInt8](repeating: 0, count: SSDPSearcher.datagramSize)
            while true {
                var sender = sockaddr_in()
                var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &sender) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, &buffer, buffer.count, 0, $0, &senderLength)
                    }
                }
                guard count > 0 else { return }
                guard responses.count < SSDPSearcher.maximumResponses,
                      sender.sin_family == sa_family_t(AF_INET),
                      var response = SSDPSearch.parseResponse(Data(buffer[0..<count])),
                      locations.insert(response.location).inserted
                else { continue }
                var address = sender.sin_addr
                var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
                response.sourceAddress = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                                                as: UTF8.self)
                responses.append(response)
            }
        }
    }

    /// Every distinct answer (by `LOCATION`) to a search for `target` within `duration`. The search is sent twice
    /// (UDP can drop it), the second time half a second after the first.
    static func search(target: String, duration: Duration) async -> [SSDPSearchResponse] {
        guard let fd = openSocket() else { return [] }
        let collector = Collector()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { collector.read(fd) }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        let mx = max(1, Int(duration.components.seconds) - 1)
        let request = SSDPSearch.request(searchTarget: target, mx: mx)
        let resend: Duration = .milliseconds(500)
        if send(request, on: fd) {
            try? await Task.sleep(for: min(resend, duration))
            _ = send(request, on: fd)
            if duration > resend { try? await Task.sleep(for: duration - resend) }
        }
        source.cancel()
        return collector.responses
    }

    private static func openSocket() -> Int32? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            logger.error("SSDP search: can't open a socket: \(String(cString: strerror(errno)), privacy: .public)")
            return nil
        }
        var yes: Int32 = 1
        let size = socklen_t(MemoryLayout<Int32>.size)
        var ttl: UInt8 = 2
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0   // any free port; answers come back to it by unicast
        address.sin_addr.s_addr = INADDR_ANY
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, size) == 0,
              setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, size) == 0,
              setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size)) == 0,
              withUnsafePointer(to: &address, {
                  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                      bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                  }
              }) == 0
        else {
            logger.error("SSDP search: socket setup failed: \(String(cString: strerror(errno)), privacy: .public)")
            Darwin.close(fd)
            return nil
        }
        // Send on the LAN interface the phone remote and casting use (en0 first), when there is one.
        if let ip = LocalAddress.primaryIPv4() {
            var interface = in_addr(s_addr: inet_addr(ip))
            _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &interface, socklen_t(MemoryLayout<in_addr>.size))
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    private static func send(_ request: Data, on fd: Int32) -> Bool {
        var group = sockaddr_in()
        group.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        group.sin_family = sa_family_t(AF_INET)
        group.sin_port = SSDP.port.bigEndian
        group.sin_addr.s_addr = inet_addr(SSDP.multicastAddress)
        let sent = request.withUnsafeBytes { bytes in
            withUnsafePointer(to: &group) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent < 0 else { return true }
        let code = errno
        if code == EHOSTUNREACH || code == EPERM {
            logger.error("SSDP search: allow Local Network for MMTVL in System Settings → Privacy & Security")
        } else {
            logger.error("SSDP search: can't send: \(String(cString: strerror(code)), privacy: .public)")
        }
        return false
    }
}

// MARK: Device description

/// The root device's fields from a UPnP device description (`<root><device>…`); embedded devices are ignored.
/// Values are trimmed and at most 256 characters. Pure.
nonisolated struct UPnPDeviceDescription: Equatable, Sendable {
    /// L17: a description larger than this is refused (fetch and parse).
    static let maximumSize = 64 * 1024
    static let maximumValueLength = 256

    var manufacturer: String?
    var modelName: String?
    var friendlyName: String?
    /// For step 9b (the TV's MAC).
    var udn: String?

    /// nil when `data` is over `maximumSize`, isn't XML, or has no root device fields.
    static func parse(_ data: Data) -> UPnPDeviceDescription? {
        guard data.count <= maximumSize else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        let delegate = DescriptionParserDelegate()
        parser.delegate = delegate
        _ = parser.parse()
        let result = delegate.result
        guard result.manufacturer != nil || result.modelName != nil || result.friendlyName != nil || result.udn != nil
        else { return nil }
        return result
    }
}

nonisolated private final class DescriptionParserDelegate: NSObject, XMLParserDelegate {
    private static let fields: Set<String> = ["manufacturer", "modelName", "friendlyName", "UDN"]

    var result = UPnPDeviceDescription()
    private var path: [String] = []
    private var text = ""

    /// `root/device/<field>`, the root device's own fields.
    private var currentField: String? {
        guard path.count == 3, path[0] == "root", path[1] == "device", Self.fields.contains(path[2]) else { return nil }
        return path[2]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        path.append(Self.localName(elementName))
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentField != nil, text.count < UPnPDeviceDescription.maximumValueLength else { return }
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if let field = currentField {
            let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(UPnPDeviceDescription.maximumValueLength))
            if !value.isEmpty {
                switch field {
                case "manufacturer": result.manufacturer = result.manufacturer ?? value
                case "modelName": result.modelName = result.modelName ?? value
                case "friendlyName": result.friendlyName = result.friendlyName ?? value
                default: result.udn = result.udn ?? value
                }
            }
        }
        text = ""
        if !path.isEmpty { path.removeLast() }
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

/// Fetches a device description: http to a LAN host only (`SSDPSearch.descriptionURL`), 2 s in all, at most
/// `UPnPDeviceDescription.maximumSize` bytes (a bigger `Content-Length` isn't read; a longer body is cut off and
/// refused), no redirects, no cookies, no cache (an ephemeral session).
nonisolated enum DeviceDescriptionFetcher {
    static let timeout: TimeInterval = 2

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        // Security S2 (step 9b): never through a system proxy.
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    static func fetch(_ url: URL) async -> Data? {
        await fetch(url, session: session)
    }

    static func fetch(_ url: URL, session: URLSession) async -> Data? {
        guard let url = SSDPSearch.descriptionURL(url.absoluteString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectBlocker())
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= Int64(UPnPDeviceDescription.maximumSize)
            else {
                bytes.task.cancel()
                return nil
            }
            let data = try await collect(bytes, limit: UPnPDeviceDescription.maximumSize)
            if data == nil { bytes.task.cancel() }
            return data
        } catch {
            return nil
        }
    }

    /// The bytes, or nil as soon as there are more than `limit`.
    static func collect(_ bytes: some AsyncSequence<UInt8, any Error>, limit: Int) async throws -> Data? {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { return nil }
            data.append(byte)
        }
        return data
    }

    /// A redirect could point anywhere: none are followed.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
        // The completion-handler form: the async one crashes Swift 6.4's SILGen (ObjC thunk).
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

// MARK: Receivers

extension ReceiverBrand {
    /// L17: the brands a UPnP `manufacturer` may be, in the order Find on Network tries them (Pioneer: the legacy
    /// protocol, then ISCP for 2016 and later). Empty for other makers. Matched by whole words, ignoring case.
    nonisolated static func candidates(forManufacturer manufacturer: String) -> [ReceiverBrand] {
        let lowered = manufacturer.lowercased()
        let words = Set(lowered.split { !($0.isLetter || $0.isNumber) }.map(String.init))
        if words.contains("onkyo") || words.contains("integra") { return [.onkyo] }
        if words.contains("pioneer") { return [.pioneer, .onkyo] }
        if words.contains("denon") || words.contains("marantz") || lowered.hasPrefix("d&m") { return [.denon] }
        if words.contains("yamaha") { return [.yamaha] }
        if words.contains("anthem") { return [.anthem] }
        if words.contains("nad") { return [.nad] }
        return []
    }
}

/// A LAN device whose description names a supported brand, before its control port is checked.
nonisolated struct ReceiverCandidate: Equatable, Sendable {
    var host: String
    var brands: [ReceiverBrand]
    var model: String?
    var name: String?
}

/// L17: a receiver that answered its brand's read-only queries.
nonisolated struct FoundReceiver: Hashable, Sendable {
    var brand: ReceiverBrand
    var model: String?
    /// The description's `friendlyName`.
    var name: String?
    var host: String
    /// The control port that answered.
    var port: UInt16
}

/// M7h L17: Find on Network. Main actor; the search, fetch and probe are injected for tests.
final class ReceiverDiscovery {
    typealias Search = (_ target: String, _ duration: Duration) async -> [SSDPSearchResponse]
    typealias Fetch = (_ url: URL) async -> Data?
    typealias Probe = (_ host: String, _ port: UInt16, _ codec: any ReceiverProtocol) async -> Bool

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Receiver")
    static let searchDuration: Duration = .seconds(3)
    /// At most this many descriptions are fetched per search.
    static let maximumDescriptions = 32

    private let search: Search
    private let fetch: Fetch
    private let probe: Probe
    private let ownAddresses: () -> [String]
    private let interfaces: () -> [WakeOnLAN.Interface]

    init(search: @escaping Search = { await SSDPSearcher.search(target: $0, duration: $1) },
         fetch: @escaping Fetch = { await DeviceDescriptionFetcher.fetch($0) },
         probe: @escaping Probe = ReceiverDiscovery.liveProbe,
         ownAddresses: @escaping () -> [String] = LANAddress.ownAddresses,
         interfaces: @escaping () -> [WakeOnLAN.Interface] = WakeOnLAN.interfaces) {
        self.search = search
        self.fetch = fetch
        self.probe = probe
        self.ownAddresses = ownAddresses
        self.interfaces = interfaces
    }

    /// The receivers on the LAN that answered, in the order SSDP found them. `portOverride` is
    /// `receiverNetworkPort`.
    func find(portOverride: UInt16? = nil) async -> [FoundReceiver] {
        let responses = await search(SSDPSearch.allTarget, Self.searchDuration)
        let urls = Self.descriptionURLs(responses, ownAddresses: ownAddresses(), interfaces: interfaces())
        let fetches = urls.map { url in Task { (url, await self.fetch(url)) } }
        var candidates: [ReceiverCandidate] = []
        for fetch in fetches {
            let (url, data) = await fetch.value
            guard let data, let description = UPnPDeviceDescription.parse(data),
                  let candidate = Self.candidate(location: url, description: description),
                  !candidates.contains(where: { $0.host == candidate.host })
            else { continue }
            candidates.append(candidate)
        }
        Self.logger.notice("Find on Network: \(responses.count, privacy: .public) SSDP replies, \(urls.count, privacy: .public) LAN descriptions, \(candidates.count, privacy: .public) possible receivers")
        let checks = candidates.map { candidate in Task { await self.check(candidate, portOverride: portOverride) } }
        var found: [FoundReceiver] = []
        for check in checks {
            if let receiver = await check.value { found.append(receiver) }
        }
        if found.isEmpty { Self.logger.notice("Find on Network: no receiver answered") }
        return found
    }

    /// Each distinct description URL MMTVL may fetch (http, a LAN IP literal that is the reply's own source and not
    /// one of the Mac's own addresses), at most `maximumDescriptions`. Pre-build 2 security low: the reply's source
    /// must be on the subnet of a usable interface (`WakeOnLAN.isOnUsableSubnet`: never over a VPN, bridge or tunnel;
    /// IPv4 only, as the search is). `ownAddresses` / `interfaces` nil = the Mac's, read once.
    static func descriptionURLs(_ responses: [SSDPSearchResponse], ownAddresses: [String]? = nil,
                                interfaces: [WakeOnLAN.Interface]? = nil) -> [URL] {
        let own = ownAddresses ?? LANAddress.ownAddresses()
        let lan = interfaces ?? WakeOnLAN.interfaces()
        var seen: Set<String> = []
        var urls: [URL] = []
        for response in responses {
            guard urls.count < maximumDescriptions,
                  let source = response.sourceAddress, WakeOnLAN.isOnUsableSubnet(source, interfaces: lan),
                  let url = SSDPSearch.descriptionURL(for: response, ownAddresses: own),
                  seen.insert(url.absoluteString).inserted
            else { continue }
            urls.append(url)
        }
        return urls
    }

    /// A candidate when the description's manufacturer is a supported brand. Pure.
    static func candidate(location: URL, description: UPnPDeviceDescription) -> ReceiverCandidate? {
        guard let host = SSDPSearch.host(of: location), LANAddress.isLANIPLiteral(host),
              let manufacturer = description.manufacturer else { return nil }
        let brands = ReceiverBrand.candidates(forManufacturer: manufacturer)
        guard !brands.isEmpty else { return nil }
        return ReceiverCandidate(host: host, brands: brands, model: description.modelName,
                                 name: description.friendlyName)
    }

    /// Each brand's ports in turn until one answers.
    private func check(_ candidate: ReceiverCandidate, portOverride: UInt16?) async -> FoundReceiver? {
        for brand in candidate.brands {
            guard let codec = brand.codec else { continue }
            for port in codec.networkPorts(override: portOverride) where await probe(candidate.host, port, codec) {
                Self.logger.notice("Find on Network: \(brand.rawValue, privacy: .public) answered at \(LANAddress.display(host: candidate.host, port: port), privacy: .public)")
                return FoundReceiver(brand: brand, model: candidate.model, name: candidate.name, host: candidate.host,
                                     port: port)
            }
        }
        return nil
    }

    /// The brand's read-only queries over TCP (`ReceiverController.probe`).
    static func liveProbe(host: String, port: UInt16, codec: any ReceiverProtocol) async -> Bool {
        guard LANAddress.isLANIPLiteral(host) else { return false }
        let transport = ReceiverTCPTransport(host: host, ports: [port], framing: codec.networkFraming,
                                             delimiters: codec.lineDelimiters)
        return await ReceiverController.probe(transport, codec: codec, clock: SystemReceiverClock())
    }
}
