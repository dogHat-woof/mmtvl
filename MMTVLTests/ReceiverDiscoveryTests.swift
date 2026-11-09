import Foundation
import Network
import Testing
@testable import MMTVL

/// Serves canned description responses by URL, and records every request (URLSession stub, no network).
nonisolated final class StubDescriptionProtocol: URLProtocol, @unchecked Sendable {
    struct Canned: Sendable {
        var headers: [String: String]
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var canned: [String: Canned] = [:]
    nonisolated(unsafe) private static var requested: [String] = []

    static func serve(_ url: String, headers: [String: String] = [:], body: Data) {
        lock.withLock { canned[url] = Canned(headers: headers, body: body) }
    }

    static func wasRequested(_ url: String) -> Bool {
        lock.withLock { requested.contains(url) }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubDescriptionProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let key = url.absoluteString
        let response = Self.lock.withLock { () -> Canned? in
            Self.requested.append(key)
            return Self.canned[key]
        }
        guard let response,
              let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: response.headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        // In pieces, like a real body.
        var offset = 0
        while offset < response.body.count {
            let end = min(offset + 8192, response.body.count)
            client?.urlProtocol(self, didLoad: response.body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// M7h L17: Find on Network's SSDP, description and LAN parts, and the search pipeline with fakes.
struct ReceiverDiscoveryTests {
    private static let onkyoResponse = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        EXT:\r
        Location: http://192.168.1.20:8080/description.xml\r
        SERVER: Linux/2.6 UPnP/1.0 Onkyo/1.0\r
        ST: upnp:rootdevice\r
        USN: uuid:00000000-0000-1000-8000-0009B0123456::upnp:rootdevice\r
        \r

        """

    private static func description(manufacturer: String, model: String, name: String,
                                    udn: String = "uuid:00000000-0000-1000-8000-0009B0123456") -> Data {
        Data("""
            <?xml version="1.0"?>
            <root xmlns="urn:schemas-upnp-org:device-1-0">
              <specVersion><major>1</major><minor>0</minor></specVersion>
              <device>
                <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
                <friendlyName>\(name)</friendlyName>
                <manufacturer>\(manufacturer)</manufacturer>
                <modelName>\(model)</modelName>
                <UDN>\(udn)</UDN>
                <deviceList>
                  <device>
                    <friendlyName>Embedded</friendlyName>
                    <manufacturer>Someone Else</manufacturer>
                    <modelName>Inner</modelName>
                  </device>
                </deviceList>
              </device>
            </root>
            """.utf8)
    }

    // MARK: SSDP

    @Test func searchRequestAsksForEverything() {
        let request = String(decoding: SSDPSearch.request(searchTarget: SSDPSearch.allTarget, mx: 2), as: UTF8.self)
        #expect(request.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        #expect(request.contains("HOST: 239.255.255.250:1900\r\n"))
        #expect(request.contains("MAN: \"ssdp:discover\"\r\n"))
        #expect(request.contains("MX: 2\r\n"))
        #expect(request.contains("ST: ssdp:all\r\n"))
        #expect(request.hasSuffix("\r\n\r\n"))
        // Step 9b searches for the TV with another target.
        let tv = String(decoding: SSDPSearch.request(searchTarget: "urn:panasonic-com:device:p00RemoteController:1",
                                                     mx: 2), as: UTF8.self)
        #expect(tv.contains("ST: urn:panasonic-com:device:p00RemoteController:1\r\n"))
    }

    @Test func searchResponseParses() throws {
        let response = try #require(SSDPSearch.parseResponse(Data(Self.onkyoResponse.utf8)))
        #expect(response.location == "http://192.168.1.20:8080/description.xml")
        #expect(response.searchTarget == "upnp:rootdevice")
        #expect(response.usn?.hasPrefix("uuid:") == true)
        #expect(response.server == "Linux/2.6 UPnP/1.0 Onkyo/1.0")
    }

    @Test func otherDatagramsAreNotResponses() {
        let notify = "NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nLOCATION: http://192.168.1.5/d.xml\r\n\r\n"
        let search = String(decoding: SSDPSearch.request(searchTarget: "ssdp:all", mx: 1), as: UTF8.self)
        let error = "HTTP/1.1 404 Not Found\r\nLOCATION: http://192.168.1.5/d.xml\r\n\r\n"
        let noLocation = "HTTP/1.1 200 OK\r\nST: upnp:rootdevice\r\n\r\n"
        for text in [notify, search, error, noLocation, ""] {
            #expect(SSDPSearch.parseResponse(Data(text.utf8)) == nil, "\(text)")
        }
        #expect(SSDPSearch.parseResponse(Data([0xFF, 0xFE, 0x00])) == nil)
    }

    /// An SSDP response and its description → (brand, model, host).
    @Test func responseAndDescriptionGiveACandidate() throws {
        let response = try #require(SSDPSearch.parseResponse(Data(Self.onkyoResponse.utf8)))
        let url = try #require(SSDPSearch.descriptionURL(response.location))
        let description = try #require(UPnPDeviceDescription.parse(
            Self.description(manufacturer: "ONKYO", model: "TX-NR686", name: "Living Room AVR")))
        #expect(description.manufacturer == "ONKYO")
        #expect(description.modelName == "TX-NR686")
        #expect(description.friendlyName == "Living Room AVR")
        #expect(description.udn == "uuid:00000000-0000-1000-8000-0009B0123456")
        let candidate = try #require(ReceiverDiscovery.candidate(location: url, description: description))
        #expect(candidate == ReceiverCandidate(host: "192.168.1.20", brands: [.onkyo], model: "TX-NR686",
                                               name: "Living Room AVR"))
    }

    @Test func descriptionWithoutDeviceFieldsIsNil() {
        #expect(UPnPDeviceDescription.parse(Data("<root><specVersion/></root>".utf8)) == nil)
        #expect(UPnPDeviceDescription.parse(Data("not xml".utf8)) == nil)
        #expect(UPnPDeviceDescription.parse(Data()) == nil)
    }

    @Test func manufacturersMapToBrands() {
        let cases: [(String, [ReceiverBrand])] = [
            ("ONKYO", [.onkyo]), ("Onkyo Corporation", [.onkyo]), ("Integra", [.onkyo]),
            ("Pioneer Corporation", [.pioneer, .onkyo]), ("PIONEER", [.pioneer, .onkyo]),
            ("Denon", [.denon]), ("Marantz", [.denon]), ("D&M Holdings Inc.", [.denon]),
            ("Yamaha Corporation", [.yamaha]), ("Anthem Electronics", [.anthem]), ("NAD Electronics", [.nad]),
            ("Samsung Electronics", []), ("Canada Lighting", []), ("Panasonic", []), ("", []),
        ]
        for (manufacturer, brands) in cases {
            #expect(ReceiverBrand.candidates(forManufacturer: manufacturer) == brands, "\(manufacturer)")
        }
    }

    @Test func otherMakersAreNoCandidate() throws {
        let url = try #require(URL(string: "http://192.168.1.30:55000/nrc/ddd.xml"))
        let tv = try #require(UPnPDeviceDescription.parse(
            Self.description(manufacturer: "Panasonic", model: "VIERA", name: "VIERA VT50")))
        #expect(ReceiverDiscovery.candidate(location: url, description: tv) == nil)
    }

    // MARK: The 64 KB cap

    @Test func descriptionOverTheCapIsRejected() {
        let valid = Self.description(manufacturer: "Denon", model: "AVR-X2000", name: "AVR")
        #expect(UPnPDeviceDescription.parse(valid) != nil)
        var padded = valid
        padded.append(Data(repeating: 0x20, count: UPnPDeviceDescription.maximumSize - valid.count))
        #expect(padded.count == UPnPDeviceDescription.maximumSize)
        #expect(UPnPDeviceDescription.parse(padded) != nil)
        padded.append(0x20)
        #expect(UPnPDeviceDescription.parse(padded) == nil)
    }

    @Test func collectStopsPastTheLimit() async throws {
        func bytes(_ count: Int) -> AsyncThrowingStream<UInt8, any Error> {
            AsyncThrowingStream { continuation in
                for _ in 0..<count { continuation.yield(0x41) }
                continuation.finish()
            }
        }
        #expect(try await DeviceDescriptionFetcher.collect(bytes(10), limit: 10)?.count == 10)
        #expect(try await DeviceDescriptionFetcher.collect(bytes(11), limit: 10) == nil)
    }

    @Test func fetchReadsADescription() async {
        let url = "http://192.168.77.10:8080/desc.xml"
        let body = Self.description(manufacturer: "Yamaha Corporation", model: "RX-V683", name: "Yamaha")
        StubDescriptionProtocol.serve(url, headers: ["Content-Length": "\(body.count)"], body: body)
        let data = await DeviceDescriptionFetcher.fetch(URL(string: url)!, session: StubDescriptionProtocol.session())
        #expect(data == body)
    }

    @Test func fetchRefusesALargeContentLength() async {
        let url = "http://192.168.77.11/desc.xml"
        StubDescriptionProtocol.serve(url, headers: ["Content-Length": "\(UPnPDeviceDescription.maximumSize + 1)"],
                                      body: Data(repeating: 0x20, count: UPnPDeviceDescription.maximumSize + 1))
        let data = await DeviceDescriptionFetcher.fetch(URL(string: url)!, session: StubDescriptionProtocol.session())
        #expect(data == nil)
    }

    @Test func fetchCutsOffALongBodyWithoutALength() async {
        let url = "http://192.168.77.12/desc.xml"
        StubDescriptionProtocol.serve(url, body: Data(repeating: 0x20, count: UPnPDeviceDescription.maximumSize * 2))
        let data = await DeviceDescriptionFetcher.fetch(URL(string: url)!, session: StubDescriptionProtocol.session())
        #expect(data == nil)
    }

    @Test func fetchNeverRequestsNonLANOrNonHTTP() async {
        let urls = ["http://8.8.8.8/desc.xml", "https://192.168.77.13/desc.xml", "http://example.com/desc.xml"]
        for url in urls {
            StubDescriptionProtocol.serve(url, body: Self.description(manufacturer: "Denon", model: "X", name: "X"))
            let data = await DeviceDescriptionFetcher.fetch(URL(string: url)!, session: StubDescriptionProtocol.session())
            #expect(data == nil, "\(url)")
            #expect(!StubDescriptionProtocol.wasRequested(url), "\(url)")
        }
    }

    // MARK: LAN only

    @Test func nonLANLocationsAreIgnored() {
        let locations = [
            "http://8.8.8.8/desc.xml", "http://example.com/desc.xml", "https://192.168.1.5/desc.xml",
            "http://127.0.0.1:8080/desc.xml", "http://100.64.0.1/desc.xml", "http://172.32.0.1/desc.xml",
            "ftp://192.168.1.5/desc.xml", "http://user:pw@192.168.1.6/desc.xml", "file:///etc/passwd",
            "http://receiver/desc.xml", "not a url",
            "http://192.168.1.5:8080/desc.xml", "http://10.0.0.7/d.xml", "http://172.20.1.2/d.xml",
            "http://169.254.10.20/d.xml", "http://avr.local:60006/d.xml", "http://[fe80::1]/d.xml",
            "http://192.168.1.5:8080/desc.xml",   // a duplicate
        ]
        // Each reply comes from its LOCATION's own host.
        let responses = locations.map { location in
            SSDPSearchResponse(location: location, sourceAddress: URL(string: location)?.host(percentEncoded: false))
        }
        let urls = ReceiverDiscovery.descriptionURLs(responses, ownAddresses: [], interfaces: LANFixture.interfaces)
            .map(\.absoluteString)
        // Pre-build 2 security low: only from the subnet of a usable interface (so no link-local IPv4 or IPv6).
        #expect(urls == [
            "http://192.168.1.5:8080/desc.xml", "http://10.0.0.7/d.xml", "http://172.20.1.2/d.xml",
        ])
    }

    /// Security M1: names (resolved later, mDNS can point anywhere) and IPv6 zones (`%lo0` is the Mac's own
    /// loopback) are never fetched.
    @Test func descriptionURLsAreLANIPLiteralsOnly() {
        #expect(SSDPSearch.descriptionURL("http://[fe80::1%25lo0]:8770/dd.xml") == nil)
        #expect(SSDPSearch.descriptionURL("http://[fe80::1%25en0]:8770/dd.xml") == nil)
        #expect(SSDPSearch.descriptionURL("http://avr.local/d.xml") == nil)
        #expect(SSDPSearch.descriptionURL("http://receiver.lan/d.xml") == nil)
        #expect(SSDPSearch.descriptionURL("http://192.168.1.20:8080/d.xml") != nil)
        #expect(SSDPSearch.descriptionURL("http://[fd00::20]/d.xml") != nil)
    }

    /// Security M1: a reply can't point MMTVL at another host.
    @Test func aReplyWhoseLocationIsAnotherHostIsIgnored() {
        let elsewhere = SSDPSearchResponse(location: "http://192.168.1.50/d.xml", sourceAddress: "192.168.1.20")
        let unknownSource = SSDPSearchResponse(location: "http://192.168.1.21/d.xml")
        let own = SSDPSearchResponse(location: "http://192.168.1.22:49152/d.xml", sourceAddress: "192.168.1.22")
        #expect(SSDPSearch.descriptionURL(for: elsewhere, ownAddresses: []) == nil)
        #expect(SSDPSearch.descriptionURL(for: unknownSource, ownAddresses: []) == nil)
        #expect(SSDPSearch.descriptionURL(for: own, ownAddresses: [])?.absoluteString == "http://192.168.1.22:49152/d.xml")
        #expect(ReceiverDiscovery.descriptionURLs([elsewhere, unknownSource, own], ownAddresses: [],
                                                  interfaces: LANFixture.interfaces).map(\.absoluteString)
            == ["http://192.168.1.22:49152/d.xml"])
    }

    /// Security follow-up 2: a (spoofed) reply naming one of the Mac's own addresses is never fetched.
    @Test func theMacsOwnAddressesAreNeverFetched() async {
        let own = ["192.168.1.9", "fe80::1c2b:3a4d:5e6f:7081", "127.0.0.1"]
        let mine = SSDPSearchResponse(location: "http://192.168.1.9:8770/dd.xml", sourceAddress: "192.168.1.9")
        let mineV6 = SSDPSearchResponse(location: "http://[fe80::1c2b:3a4d:5e6f:7081]:8770/dd.xml",
                                        sourceAddress: "fe80::1c2b:3a4d:5e6f:7081")
        let other = SSDPSearchResponse(location: "http://192.168.1.20/d.xml", sourceAddress: "192.168.1.20")
        #expect(SSDPSearch.descriptionURL(for: mine, ownAddresses: own) == nil)
        #expect(SSDPSearch.descriptionURL(for: mineV6, ownAddresses: own) == nil)
        #expect(SSDPSearch.descriptionURL(for: mine, ownAddresses: []) != nil)
        #expect(ReceiverDiscovery.descriptionURLs([mine, mineV6, other], ownAddresses: own,
                                                  interfaces: LANFixture.interfaces).map(\.absoluteString)
            == ["http://192.168.1.20/d.xml"])
        // The search never fetches them.
        var fetched: [String] = []
        let discovery = ReceiverDiscovery(
            search: { _, _ in [mine, other] },
            fetch: { url in
                fetched.append(url.absoluteString)
                return nil
            },
            probe: { _, _, _ in false },
            ownAddresses: { own }, interfaces: { LANFixture.interfaces })
        _ = await discovery.find()
        #expect(fetched == ["http://192.168.1.20/d.xml"])
    }

    @Test func ownAddressesListTheMacsInterfaces() {
        let own = LANAddress.ownAddresses()
        #expect(own.contains("127.0.0.1"))
        #expect(own.contains("::1"))
        // Link-local addresses come without KAME's embedded scope.
        #expect(own.filter { $0.hasPrefix("fe80:") }.allSatisfy { $0.hasPrefix("fe80::") })
    }

    /// Security M1: the address a TCP connection reached must be a LAN IP.
    @Test func resolvedRemoteMustBeOnTheLAN() throws {
        func endpoint(_ host: NWEndpoint.Host) -> NWEndpoint { .hostPort(host: host, port: 23) }
        let lan: [NWEndpoint.Host] = [
            .ipv4(try #require(IPv4Address("192.168.1.20"))), .ipv4(try #require(IPv4Address("10.0.0.5"))),
            .ipv4(try #require(IPv4Address("169.254.3.4"))), .ipv6(try #require(IPv6Address("fe80::20"))),
            .ipv6(try #require(IPv6Address("fd00::5"))), .ipv6(try #require(IPv6Address("::ffff:192.168.1.20"))),
        ]
        for host in lan { #expect(ReceiverTCPTransport.isLANRemote(endpoint(host)), "\(host)") }
        let other: [NWEndpoint.Host] = [
            .ipv4(try #require(IPv4Address("127.0.0.1"))), .ipv4(try #require(IPv4Address("8.8.8.8"))),
            .ipv6(try #require(IPv6Address("::1"))), .ipv6(try #require(IPv6Address("2001:db8::1"))),
            .ipv6(try #require(IPv6Address("::ffff:127.0.0.1"))), .name("receiver.lan", nil),
        ]
        for host in other { #expect(!ReceiverTCPTransport.isLANRemote(endpoint(host)), "\(host)") }
        if let loopback = IPv6Address("fe80::1%lo0"), loopback.interface?.type == .loopback {
            #expect(!ReceiverTCPTransport.isLANRemote(endpoint(.ipv6(loopback))))
        }
        #expect(!ReceiverTCPTransport.isLANRemote(.service(name: "x", type: "_x._tcp", domain: "local", interface: nil)))
    }

    /// QA minor 3: the user may type a LAN address, a `.local` name or another DNS name (checked once resolved).
    @Test func receiverHostsTheUserMayType() {
        for host in ["192.168.1.20", "avr.local", "receiver.lan", "receiver", "AVR-1.home.arpa", "fe80::1%en0"] {
            #expect(LANAddress.isAllowedReceiverHost(host), "\(host)")
        }
        for host in ["8.8.8.8", "127.0.0.1", "::1", "fe80::1%lo0", "10.1", "a b", "-x.lan", "", "http://x",
                     "192.168.1.20:23"] {
            #expect(!LANAddress.isAllowedReceiverHost(host), "\(host)")
        }
    }

    /// QA minor 5.
    @Test func endpointNamesBracketIPv6() {
        #expect(LANAddress.display(host: "192.168.1.20", port: 23) == "192.168.1.20:23")
        #expect(LANAddress.display(host: "fe80::1%en0", port: 60128) == "[fe80::1%en0]:60128")
        #expect(LANAddress.display(host: "avr.local", port: 23) == "avr.local:23")
    }

    @Test func lanAddresses() {
        for host in ["10.1.2.3", "172.16.0.1", "172.31.255.254", "192.168.0.10", "169.254.1.1", "avr.local",
                     "Living-Room-AVR.local", "AVR.LOCAL.", " 192.168.1.20 ", "fe80::1", "fe80::1%en0", "[fe80::1]",
                     "fd12:3456::1", "fd00::1"] {
            #expect(LANAddress.isLAN(host), "\(host)")
        }
        for host in ["8.8.8.8", "172.15.0.1", "172.32.0.1", "127.0.0.1", "0.0.0.0", "255.255.255.255",
                     "100.64.0.1", "192.168.1", "10.1", "example.com", "receiver", "local", ".local", "-x.local",
                     "a b.local", "2001:db8::1", "::1", "", "192.168.1.20:23",
                     // Security M1: zones naming a loopback interface (or none) are the Mac itself.
                     "fe80::1%lo0", "[fe80::1%lo0]", "fe80::1%nosuch9", "fe80::1%", "::ffff:127.0.0.1",
                     "fe80::1%\(if_nametoindex("lo0"))"] {
            #expect(!LANAddress.isLAN(host), "\(host)")
        }
    }

    @Test func tcpTransportRefusesNonLANHosts() {
        #expect(ReceiverTCPTransport.receiverTransport(host: "8.8.8.8", port: nil, codec: DenonProtocol()) == nil)
        #expect(ReceiverTCPTransport.receiverTransport(host: "127.0.0.1", port: 23, codec: DenonProtocol()) == nil)
        #expect(ReceiverTCPTransport.receiverTransport(host: "fe80::1%lo0", port: 23, codec: DenonProtocol()) == nil)
        #expect(ReceiverController.systemTransport(link: .network(host: "1.1.1.1", port: nil), codec: NADProtocol()) == nil)
    }

    // MARK: The search, with fakes

    @Test func findChecksEachCandidateOnItsControlPorts() async {
        let descriptions: [String: Data] = [
            "http://192.168.1.20:8080/desc.xml": Self.description(manufacturer: "ONKYO", model: "TX-NR686", name: "Onkyo"),
            "http://192.168.1.21/desc.xml": Self.description(manufacturer: "Pioneer", model: "VSX-1021", name: "Pioneer"),
            "http://192.168.1.21/other.xml": Self.description(manufacturer: "Pioneer", model: "dup", name: "dup"),
            "http://192.168.1.30:55000/nrc/ddd.xml": Self.description(manufacturer: "Panasonic", model: "VIERA", name: "TV"),
            "http://192.168.1.40/desc.xml": Self.description(manufacturer: "Denon", model: "AVR-X2000", name: "Silent"),
            "http://8.8.8.8/desc.xml": Self.description(manufacturer: "Denon", model: "Remote", name: "Remote"),
        ]
        var searched: [String] = []
        var fetched: [String] = []
        var probed: [String] = []
        let discovery = ReceiverDiscovery(
            search: { target, _ in
                searched.append(target)
                return descriptions.keys.sorted().map {
                    SSDPSearchResponse(location: $0, sourceAddress: URL(string: $0)?.host(percentEncoded: false))
                }
            },
            fetch: { url in
                fetched.append(url.absoluteString)
                return descriptions[url.absoluteString]
            },
            probe: { host, port, codec in
                probed.append("\(codec.brand.rawValue)@\(host):\(port)")
                // The Onkyo answers on eISCP; the Pioneer only on its fallback port.
                return (host == "192.168.1.20" && port == 60128 && codec.brand == .onkyo)
                    || (host == "192.168.1.21" && port == 8102 && codec.brand == .pioneer)
            }, ownAddresses: { [] }, interfaces: { LANFixture.interfaces })
        let found = await discovery.find()
        #expect(searched == ["ssdp:all"])
        #expect(!fetched.contains("http://8.8.8.8/desc.xml"))
        #expect(Set(found) == [
            FoundReceiver(brand: .onkyo, model: "TX-NR686", name: "Onkyo", host: "192.168.1.20", port: 60128),
            FoundReceiver(brand: .pioneer, model: "VSX-1021", name: "Pioneer", host: "192.168.1.21", port: 8102),
        ])
        #expect(Set(probed) == [
            "onkyo@192.168.1.20:60128", "pioneer@192.168.1.21:23", "pioneer@192.168.1.21:8102",
            "denon@192.168.1.40:23",
        ])
    }

    @Test func findUsesThePortOverride() async {
        var probed: [UInt16] = []
        let discovery = ReceiverDiscovery(
            search: { _, _ in [SSDPSearchResponse(location: "http://192.168.1.21/desc.xml", sourceAddress: "192.168.1.21")] },
            fetch: { _ in Self.description(manufacturer: "Pioneer", model: "VSX", name: "P") },
            probe: { _, port, _ in
                probed.append(port)
                return false
            }, ownAddresses: { [] }, interfaces: { LANFixture.interfaces })
        let found = await discovery.find(portOverride: 2323)
        #expect(found.isEmpty)
        #expect(probed == [2323, 2323])   // Pioneer, then Onkyo's ISCP, both on the override
    }
}

/// The Mac's interfaces in tests: Ethernet 192.168.1.10/24, Wi-Fi 10.0.0.2/24, a second LAN 172.20.0.1/16.
enum LANFixture {
    static func interface(_ name: String, _ address: String, _ netmask: String, isBroadcast: Bool = true,
                          isPointToPoint: Bool = false, isUp: Bool = true) -> WakeOnLAN.Interface {
        WakeOnLAN.Interface(name: name, address: WakeOnLAN.ipv4(address)!, netmask: WakeOnLAN.ipv4(netmask)!,
                            isUp: isUp, isLoopback: false, isBroadcast: isBroadcast, isPointToPoint: isPointToPoint)
    }

    static let interfaces = [
        interface("en0", "192.168.1.10", "255.255.255.0"),
        interface("en1", "10.0.0.2", "255.255.255.0"),
        interface("en2", "172.20.0.1", "255.255.0.0"),
    ]
}

/// Pre-build 2 security low: SSDP replies count only from the subnet of an interface Wake-on-LAN would use.
struct SSDPInterfaceTests {
    private func reply(_ host: String) -> SSDPSearchResponse {
        SSDPSearchResponse(location: "http://\(host)/d.xml", sourceAddress: host)
    }

    @Test func repliesOverAVPNOrBridgeAreIgnored() {
        let interfaces = [
            LANFixture.interface("en0", "192.168.1.10", "255.255.255.0"),
            // A broadcast-capable VPN adapter on 10/8 (ZeroTier), an OpenVPN tap, a bridge, a utun tunnel.
            LANFixture.interface("zt3jnr2", "10.147.17.5", "255.255.255.0"),
            LANFixture.interface("tap0", "10.8.0.6", "255.255.255.0"),
            LANFixture.interface("bridge100", "192.168.2.1", "255.255.255.0"),
            LANFixture.interface("utun4", "10.9.0.2", "255.255.255.0", isBroadcast: false, isPointToPoint: true),
            // An interface without broadcast, a point-to-point one, and one that's down.
            LANFixture.interface("en5", "10.20.0.2", "255.255.255.0", isBroadcast: false),
            LANFixture.interface("en6", "10.30.0.2", "255.255.255.0", isPointToPoint: true),
            LANFixture.interface("en7", "10.40.0.2", "255.255.255.0", isUp: false),
        ]
        let hosts = ["192.168.1.20", "10.147.17.9", "10.8.0.1", "192.168.2.5", "10.9.0.1", "10.20.0.9", "10.30.0.9",
                     "10.40.0.9", "10.50.0.9"]
        let urls = ReceiverDiscovery.descriptionURLs(hosts.map(reply), ownAddresses: [], interfaces: interfaces)
        #expect(urls.map(\.absoluteString) == ["http://192.168.1.20/d.xml"])
        // No usable interface: nothing.
        #expect(ReceiverDiscovery.descriptionURLs([reply("192.168.1.20")], ownAddresses: [], interfaces: []).isEmpty)
    }

    @Test func isOnUsableSubnet() {
        let lan = LANFixture.interfaces
        #expect(WakeOnLAN.isOnUsableSubnet("192.168.1.200", interfaces: lan))
        #expect(WakeOnLAN.isOnUsableSubnet("172.20.9.9", interfaces: lan))
        #expect(!WakeOnLAN.isOnUsableSubnet("192.168.3.1", interfaces: lan))
        #expect(!WakeOnLAN.isOnUsableSubnet("10.0.1.7", interfaces: lan))
        #expect(!WakeOnLAN.isOnUsableSubnet("fe80::1", interfaces: lan))
        #expect(!WakeOnLAN.isOnUsableSubnet("not an address", interfaces: lan))
    }

    /// Find TV and Find on Network both use it.
    @Test func findTVIgnoresRepliesOverAVPN() async {
        let network = FakeTVNetwork()
        var fetched: [String] = []
        let tv = network.controller(
            search: { target, _ in
                [SSDPSearchResponse(location: "http://10.147.17.9:55000/nrc/ddd.xml", searchTarget: target,
                                    sourceAddress: "10.147.17.9")]
            },
            fetch: { url in
                fetched.append(url.absoluteString)
                return nil
            },
            interfaces: { [LANFixture.interface("en0", "192.168.1.10", "255.255.255.0"),
                           LANFixture.interface("zt3jnr2", "10.147.17.5", "255.255.255.0")] })
        #expect(await tv.find().isEmpty)
        #expect(fetched.isEmpty)

        var probed = 0
        let discovery = ReceiverDiscovery(
            search: { _, _ in [SSDPSearchResponse(location: "http://10.147.17.9/d.xml", sourceAddress: "10.147.17.9")] },
            fetch: { url in
                fetched.append(url.absoluteString)
                return nil
            },
            probe: { _, _, _ in
                probed += 1
                return false
            },
            ownAddresses: { [] },
            interfaces: { [LANFixture.interface("zt3jnr2", "10.147.17.5", "255.255.255.0")] })
        #expect(await discovery.find().isEmpty)
        #expect(fetched.isEmpty)
        #expect(probed == 0)
    }
}
