import Darwin
import Foundation
import Testing
@testable import MMTVL

/// M7j step 2 (L4): discovery with injected interfaces, UDP send, mDNS resolver and HTTP fetch. Never touches the
/// network or a real tuner; fake LAN addresses, ids and tokens only.
struct HDHomeRunDiscoveryTests {
    /// Serves canned bodies by URL and records what was asked for.
    nonisolated final class FakeTuners: @unchecked Sendable {
        private let lock = NSLock()
        private let bodies: [String: Data]
        private var requested: [String] = []

        init(_ bodies: [String: Data]) { self.bodies = bodies }

        var requests: [String] { lock.withLock { requested } }

        var fetch: HDHomeRunHTTP.Fetch {
            { [self] url, maxBytes, _ in
                lock.withLock { () -> Data? in
                    requested.append(url.absoluteString)
                    #expect(maxBytes == HDHomeRunHTTP.smallMaxBytes)
                    return bodies[url.absoluteString]
                }
            }
        }
    }

    /// Answers every name with `addresses` and records the names asked.
    nonisolated final class FakeResolver: @unchecked Sendable {
        private let lock = NSLock()
        private let addresses: [String]
        private var asked: [String] = []

        init(_ addresses: [String] = []) { self.addresses = addresses }

        var names: [String] { lock.withLock { asked } }

        var resolve: HDHomeRunDiscovery.Resolve {
            { [self] host in
                lock.withLock {
                    asked.append(host)
                    return addresses
                }
            }
        }
    }

    /// What `send` was asked to broadcast on.
    final class SentTargets {
        var targets: [HDHomeRunBroadcaster.Target]?
    }

    static func interface(_ name: String, _ address: [UInt8], netmask: [UInt8] = [255, 255, 255, 0],
                          isUp: Bool = true, isLoopback: Bool = false, isBroadcast: Bool = true,
                          isPointToPoint: Bool = false) -> WakeOnLAN.Interface {
        WakeOnLAN.Interface(name: name, address: address, netmask: netmask, isUp: isUp, isLoopback: isLoopback,
                            isBroadcast: isBroadcast, isPointToPoint: isPointToPoint)
    }

    /// The Mac: en0 at 10.0.0.2/24.
    static let lan = [interface("en0", [10, 0, 0, 2])]

    static func discoverJSON(id: String = "1234ABCD", name: String = "HDHomeRun CONNECT",
                             model: String = "HDHR4-2US", baseURL: String = "http://10.0.0.9:80",
                             lineupURL: String = "http://10.0.0.9/lineup.json", tunerCount: Int = 2) -> Data {
        let json: [String: Any] = [
            "FriendlyName": name, "ModelNumber": model, "FirmwareName": "hdhomerun4_atsc",
            "FirmwareVersion": "20250623", "DeviceID": id, "DeviceAuth": "fakeDeviceAuth+token/0123456789ab",
            "UpgradeAvailable": "20261107", "BaseURL": baseURL, "LineupURL": lineupURL, "TunerCount": tunerCount,
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    static func reply(id: UInt32 = 0x1234_ABCD, baseURL: String = "http://10.0.0.9:80",
                      extra: [(tag: UInt8, value: [UInt8])] = []) -> Data {
        HDHomeRunPacketTests.reply(id: id, extra: [(0x2A, Array(baseURL.utf8))] + extra)
    }

    static func datagram(_ data: Data, from source: String = "10.0.0.9") -> HDHomeRunDatagram {
        HDHomeRunDatagram(data: data, sourceAddress: source)
    }

    static func find(_ datagrams: [HDHomeRunDatagram], tuners: FakeTuners,
                     interfaces: [WakeOnLAN.Interface] = lan, resolver: FakeResolver = FakeResolver(),
                     sent: SentTargets = SentTargets(),
                     ownAddresses: [String] = ["10.0.0.2"]) async -> [HDHomeRunDevice] {
        await HDHomeRunDiscovery.find(interfaces: { interfaces }, send: { request, targets, _ in
            #expect(request == HDHomeRunPacket.discoverRequest)
            sent.targets = targets
            return datagrams
        }, resolve: resolver.resolve, fetch: tuners.fetch, ownAddresses: { ownAddresses })
    }

    @Test func discoverJSONDecodes() throws {
        let discover = try #require(HDHomeRunDiscover.decode(Self.discoverJSON()))
        #expect(discover.friendlyName == "HDHomeRun CONNECT")
        #expect(discover.modelNumber == "HDHR4-2US")
        #expect(discover.firmwareName == "hdhomerun4_atsc")
        #expect(discover.firmwareVersion == "20250623")
        #expect(discover.deviceID == "1234ABCD")
        #expect(discover.deviceAuth == "fakeDeviceAuth+token/0123456789ab")
        #expect(discover.upgradeAvailable == "20261107")
        #expect(discover.baseURL == "http://10.0.0.9:80")
        #expect(discover.lineupURL == "http://10.0.0.9/lineup.json")
        #expect(discover.tunerCount == 2)

        // DeviceAuth is decoded but isn't part of the device.
        let device = try #require(HDHomeRunDiscovery.device(discover, expectedHost: "10.0.0.9", ownAddresses: []))
        #expect(device == HDHomeRunDevice(id: "1234ABCD", name: "HDHomeRun CONNECT", model: "HDHR4-2US",
                                          tunerCount: 2, baseURL: URL(string: "http://10.0.0.9:80")!,
                                          lineupURL: URL(string: "http://10.0.0.9/lineup.json")!))

        // Optional keys missing or of another type; numbers written as numbers.
        let sparse = Data(#"{"DeviceID":"1","BaseURL":"http://10.0.0.9","LineupURL":"http://10.0.0.9/lineup.json","TunerCount":1,"UpgradeAvailable":20261107,"FriendlyName":["x"]}"#.utf8)
        let decoded = try #require(HDHomeRunDiscover.decode(sparse))
        #expect(decoded.upgradeAvailable == "20261107")
        #expect(decoded.friendlyName == nil)
        #expect(decoded.deviceAuth == nil)
    }

    /// Security L3: no description, debug description or mirror shows the DeviceID, the DeviceAuth or the address.
    @Test func descriptionsHideIDAuthAndHost() throws {
        let discover = try #require(HDHomeRunDiscover.decode(Self.discoverJSON()))
        let device = try #require(HDHomeRunDiscovery.device(discover, expectedHost: "10.0.0.9", ownAddresses: []))
        var dumpedDevice = ""
        dump(device, to: &dumpedDevice)
        var dumpedDiscover = ""
        dump(discover, to: &dumpedDiscover)
        let texts = ["\(device)", String(describing: device), String(reflecting: device), dumpedDevice,
                     "\(discover)", String(describing: discover), String(reflecting: discover), dumpedDiscover]
        for text in texts {
            #expect(!text.contains("1234ABCD"))
            #expect(!text.contains("fakeDeviceAuth"))
            #expect(!text.contains("10.0.0.9"))
            #expect(text.contains("HDHomeRun CONNECT"))
            #expect(text.contains("HDHR4-2US"))
        }
        #expect("\(device)" == "HDHomeRunDevice(name: HDHomeRun CONNECT, model: HDHR4-2US, tunerCount: 2)")

        // The UDP side too (QA minor): the reply, the datagram and the candidate show no id, address or URL.
        let datagram = Self.datagram(Self.reply(baseURL: "http://10.0.0.9:80", extra: [(0x27, Array("http://10.0.0.9/lineup.json".utf8))]))
        let reply = try #require(HDHomeRunPacket.parseDiscoverReply(datagram.data))
        let candidate = try #require(HDHomeRunDiscovery.candidates([datagram], subnets: Self.lan,
                                                                   ownAddresses: []).first)
        var dumped: [String] = []
        for value in [reply, datagram, candidate] as [Any] {
            var text = ""
            dump(value, to: &text)
            dumped.append(text)
        }
        let udpTexts = ["\(reply)", String(reflecting: reply), "\(datagram)", String(reflecting: datagram),
                        "\(candidate)", String(reflecting: candidate)] + dumped
        for text in udpTexts {
            #expect(!text.contains("1234ABCD") && !text.lowercased().contains("1234abcd"), "\(text)")
            #expect(!text.contains("\(UInt32(0x1234_ABCD))"), "\(text)")
            #expect(!text.contains("10.0.0.9"), "\(text)")
            #expect(!text.contains("http"), "\(text)")
        }
        #expect("\(reply)" == "HDHomeRunReply(tunerCount: 2, hasBaseURL: true, hasLineupURL: true)")
        #expect("\(datagram)" == "HDHomeRunDatagram(\(datagram.data.count) bytes)")
    }

    /// Security L4: control and format characters removed, 64 characters at most, an empty name is "HDHomeRun".
    @Test func namesAreCleanedAndCapped() throws {
        let cases: [(name: String, model: String, expectedName: String, expectedModel: String)] = [
            ("\u{202E}Living\u{0007} Room\u{200B} ", "HDHR4\u{2066}-2US\u{0000}", "Living Room", "HDHR4-2US"),
            (String(repeating: "A", count: 100), String(repeating: "B", count: 65),
             String(repeating: "A", count: 64), String(repeating: "B", count: 64)),
            ("\u{202E}\u{0007}\u{200F}  ", "", "HDHomeRun", ""),
            ("", "\u{FEFF}", "HDHomeRun", ""),
        ]
        for testCase in cases {
            let discover = try #require(HDHomeRunDiscover.decode(Self.discoverJSON(name: testCase.name,
                                                                                    model: testCase.model)))
            let device = try #require(HDHomeRunDiscovery.device(discover, expectedHost: "10.0.0.9", ownAddresses: []))
            #expect(device.name == testCase.expectedName)
            #expect(device.model == testCase.expectedModel)
        }

        // Security L-a: the cap counts Unicode scalars (500 combining marks are one Character), and line and
        // paragraph separators (Zl, Zp) are removed.
        let stacked = "A" + String(repeating: "\u{0301}", count: 500)
        let living = "Living\u{2028}Room\u{2029}"
        let discover = try #require(HDHomeRunDiscover.decode(Self.discoverJSON(name: stacked, model: living)))
        let device = try #require(HDHomeRunDiscovery.device(discover, expectedHost: "10.0.0.9", ownAddresses: []))
        #expect(device.name.unicodeScalars.count <= HDHomeRunDiscovery.maximumNameLength)
        #expect(device.name.unicodeScalars.first == "A")
        #expect(device.model == "LivingRoom")
        #expect(!device.model.unicodeScalars.contains { ["\u{2028}", "\u{2029}"].contains($0) })
        #expect(HDHomeRunDiscovery.displayText(String(repeating: "B", count: 65) + "\u{0301}")
                == String(repeating: "B", count: 64))
    }

    /// Security L-d: discover.json's DeviceID is 8 hex digits and, on the UDP path, the reply's id.
    @Test func deviceIDMustMatchTheReply() async {
        for id in ["DEADBEEF", "1234ABCG", "1234ABCD0", "1234ABC", "+234ABCD", " 234ABCD", "１234ABCD"] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(id: id)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: tuners).isEmpty, "\(id)")
        }
        let lower = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(id: "1234abcd")])
        #expect(await Self.find([Self.datagram(Self.reply())], tuners: lower).map(\.id) == ["1234abcd"])
        // The fallback has no UDP id: 8 hex digits are enough, anything else is dropped.
        for (id, found) in [("DEADBEEF", true), ("1234abcd", true), ("XYZ", false), ("123456789", false)] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(id: id)])
            let devices = await Self.find([], tuners: tuners, resolver: FakeResolver(["10.0.0.9"]))
            #expect(devices.isEmpty == !found, "\(id)")
        }
        #expect(HDHomeRunDiscovery.deviceIDValue("1234ABCD") == 0x1234_ABCD)
        #expect(HDHomeRunDiscovery.deviceIDValue("1234abcd") == 0x1234_ABCD)
    }

    @Test func duplicateRepliesBecomeOneDevice() async {
        let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
        // The tuner answers twice per request (the second adds the multi type), and the request goes out twice.
        let first = Self.reply()
        let second = Self.reply(extra: [(0x2D, [0, 0, 0, 1])])
        let devices = await Self.find([first, second, first, second].map { Self.datagram($0) }, tuners: tuners)
        #expect(devices.map(\.id) == ["1234ABCD"])
        #expect(devices.first?.tunerCount == 2)
        #expect(tuners.requests == ["http://10.0.0.9/discover.json"])
    }

    @Test func devicesAreInDeviceIDOrder() async {
        let tuners = FakeTuners([
            "http://10.0.0.9/discover.json": Self.discoverJSON(id: "2000AAAA"),
            "http://10.0.0.10/discover.json": Self.discoverJSON(id: "1000BBBB", baseURL: "http://10.0.0.10",
                                                                lineupURL: "http://10.0.0.10/lineup.json"),
        ])
        let devices = await Self.find([
            Self.datagram(Self.reply(id: 0x2000_AAAA)),
            Self.datagram(Self.reply(id: 0x1000_BBBB, baseURL: "http://10.0.0.10/"), from: "10.0.0.10"),
        ], tuners: tuners)
        #expect(devices.map(\.id) == ["1000BBBB", "2000AAAA"])
    }

    @Test func baseURLOnAnotherHostIsRejected() async {
        // The UDP reply's BaseURL names another host: never fetched.
        let pointing = FakeTuners(["http://10.0.0.50/discover.json": Self.discoverJSON(baseURL: "http://10.0.0.50:80")])
        let none = await Self.find([Self.datagram(Self.reply(baseURL: "http://10.0.0.50:80"))], tuners: pointing)
        #expect(none.isEmpty)
        #expect(pointing.requests.isEmpty)

        // discover.json's BaseURL or LineupURL names another host, or isn't http.
        for (baseURL, lineupURL) in [("http://10.0.0.50:80", "http://10.0.0.9/lineup.json"),
                                     ("http://10.0.0.9:80", "http://10.0.0.50/lineup.json"),
                                     ("https://10.0.0.9:80", "http://10.0.0.9/lineup.json"),
                                     ("http://10.0.0.9:80", "file:///etc/passwd"),
                                     ("http://user@10.0.0.9:80", "http://10.0.0.9/lineup.json"),
                                     ("http://10.0.0.9.", "http://10.0.0.9/lineup.json"),
                                     ("http://hdhomerun.local", "http://hdhomerun.local/lineup.json")] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(baseURL: baseURL,
                                                                                     lineupURL: lineupURL)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: tuners).isEmpty, "\(baseURL) \(lineupURL)")
        }

        // A UDP BaseURL that isn't http, or has no BaseURL at all.
        let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
        let noBase = Self.datagram(HDHomeRunPacketTests.reply())
        let https = Self.datagram(Self.reply(baseURL: "https://10.0.0.9:80"))
        #expect(await Self.find([noBase, https], tuners: tuners).isEmpty)
        #expect(tuners.requests.isEmpty)
    }

    /// Security M3: the BaseURL is only an origin (port 80 at most), and `discover.json` is asked at the source.
    @Test func baseURLWithPathOrPortIsRejected() async {
        for baseURL in ["http://10.0.0.9:8080/x?y=1", "http://10.0.0.9:8080", "http://10.0.0.9/cgi-bin/admin.cgi",
                        "http://10.0.0.9/?action=reboot", "http://10.0.0.9#top", "http://010.0.0.9",
                        "http://10.0.0.9:80/discover.json"] {
            // In the UDP reply: never fetched, at any URL.
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
            #expect(await Self.find([Self.datagram(Self.reply(baseURL: baseURL))], tuners: tuners).isEmpty, "\(baseURL)")
            #expect(tuners.requests.isEmpty, "\(baseURL)")
            // In discover.json: no device.
            let listed = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(baseURL: baseURL)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: listed).isEmpty, "\(baseURL)")
        }
        // The origin with or without "/" or ":80" is fine, and discover.json is always http://<source>/discover.json.
        for baseURL in ["http://10.0.0.9", "http://10.0.0.9/", "http://10.0.0.9:80/", "HTTP://10.0.0.9"] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(baseURL: baseURL)])
            #expect(await Self.find([Self.datagram(Self.reply(baseURL: baseURL))], tuners: tuners).count == 1,
                    "\(baseURL)")
            #expect(tuners.requests == ["http://10.0.0.9/discover.json"])
        }
    }

    /// Step 10 (step 3's port low): BaseURL's and LineupURL's ports are read from the string. Foundation reads
    /// `:99999999999999999999` and an empty `:` as no port (ffmpeg and URLSession would not); both are refused, and
    /// so is `:0`. `:080` is 80 to Foundation and ffmpeg alike, so it passes the origin rule (port 80 or none).
    @Test func baseAndLineupPortsAreReadAsWritten() async {
        for port in [":99999999999999999999", ":", ":0", ":00000", ":65536", ":5004"] {
            let baseURL = "http://10.0.0.9\(port)"
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
            #expect(await Self.find([Self.datagram(Self.reply(baseURL: baseURL))], tuners: tuners).isEmpty, "\(baseURL)")
            #expect(tuners.requests.isEmpty, "\(baseURL)")
            let listed = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(baseURL: baseURL)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: listed).isEmpty, "\(baseURL)")
            let lineupURL = "http://10.0.0.9\(port)/lineup.json"
            let lineup = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(lineupURL: lineupURL)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: lineup).isEmpty, "\(lineupURL)")
        }
        for port in ["", ":80", ":080"] {
            let baseURL = "http://10.0.0.9\(port)"
            let lineupURL = "http://10.0.0.9\(port)/lineup.json"
            let tuners = FakeTuners(["http://10.0.0.9/discover.json":
                                        Self.discoverJSON(baseURL: baseURL, lineupURL: lineupURL)])
            #expect(await Self.find([Self.datagram(Self.reply(baseURL: baseURL))], tuners: tuners).count == 1,
                    "\(baseURL)")
        }
        // The check itself.
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://10.0.0.9:/x")!) == .invalid)
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://10.0.0.9:99999999999999999999/x")!) == .invalid)
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://10.0.0.9:0/x")!) == .invalid)
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://10.0.0.9/x")!) == HDHomeRunDiscovery.WrittenPort.none)
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://10.0.0.9:5004/x?y=1:2")!) == .valid(5004))
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://10.0.0.9/x:99999999999999999999")!)
                == HDHomeRunDiscovery.WrittenPort.none)
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://10.0.0.9:080")!) == .valid(80))
        #expect(HDHomeRunDiscovery.writtenPort(of: URL(string: "http://u:p@10.0.0.9:5004/")!) == .valid(5004))
    }

    /// Security M3: a LineupURL with a query, a fragment or another port drops the device.
    @Test func lineupURLWithQueryIsDropped() async {
        for lineupURL in ["http://10.0.0.9/lineup.json?show=found", "http://10.0.0.9/lineup.json#x",
                          "http://10.0.0.9:5004/lineup.json"] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(lineupURL: lineupURL)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: tuners).isEmpty, "\(lineupURL)")
        }
        let tuners = FakeTuners(["http://10.0.0.9/discover.json":
                                    Self.discoverJSON(lineupURL: "http://10.0.0.9:80/lineup.json")])
        #expect(await Self.find([Self.datagram(Self.reply())], tuners: tuners).first?.lineupURL
                == URL(string: "http://10.0.0.9:80/lineup.json"))
    }

    @Test func nonLANSourceIsRejected() async {
        let tuners = FakeTuners([
            "http://203.0.113.5/discover.json": Self.discoverJSON(baseURL: "http://203.0.113.5:80",
                                                                 lineupURL: "http://203.0.113.5/lineup.json"),
            "http://127.0.0.1/discover.json": Self.discoverJSON(baseURL: "http://127.0.0.1:80",
                                                               lineupURL: "http://127.0.0.1/lineup.json"),
            "http://10.0.0.2/discover.json": Self.discoverJSON(baseURL: "http://10.0.0.2:80",
                                                              lineupURL: "http://10.0.0.2/lineup.json"),
        ])
        let interfaces = Self.lan + [Self.interface("en1", [203, 0, 113, 2])]
        let devices = await Self.find([
            Self.datagram(Self.reply(baseURL: "http://203.0.113.5:80"), from: "203.0.113.5"),
            Self.datagram(Self.reply(baseURL: "http://127.0.0.1:80"), from: "127.0.0.1"),
            // The Mac's own address (a forged reply aiming at MMTVL's listeners).
            Self.datagram(Self.reply(baseURL: "http://10.0.0.2:80"), from: "10.0.0.2"),
            Self.datagram(Self.reply(baseURL: "http://[fd00::9]:80"), from: "fd00::9"),
        ], tuners: tuners, interfaces: interfaces)
        #expect(devices.isEmpty)
        #expect(tuners.requests.isEmpty)
    }

    /// Security M1: an overlay network (ZeroTier) isn't searched, and a reply from its subnet isn't taken.
    @Test func overlayInterfaceReplyIsRejected() async {
        let interfaces = [Self.interface("en0", [10, 0, 0, 2]), Self.interface("zt0", [10, 147, 17, 2])]
        let sent = SentTargets()
        let tuners = FakeTuners(["http://10.147.17.5/discover.json":
                                    Self.discoverJSON(baseURL: "http://10.147.17.5",
                                                      lineupURL: "http://10.147.17.5/lineup.json")])
        let devices = await Self.find([Self.datagram(Self.reply(baseURL: "http://10.147.17.5"), from: "10.147.17.5")],
                                      tuners: tuners, interfaces: interfaces, sent: sent)
        #expect(sent.targets == [HDHomeRunBroadcaster.Target(interface: "en0", broadcast: [10, 0, 0, 255])])
        #expect(devices.isEmpty)
        #expect(tuners.requests.isEmpty)
    }

    /// Security M1: a private source that is on no searched interface's subnet is refused.
    @Test func replyFromAnotherSubnetIsRejected() async {
        let tuners = FakeTuners(["http://192.168.5.9/discover.json":
                                    Self.discoverJSON(baseURL: "http://192.168.5.9",
                                                      lineupURL: "http://192.168.5.9/lineup.json")])
        let devices = await Self.find([Self.datagram(Self.reply(baseURL: "http://192.168.5.9"), from: "192.168.5.9")],
                                      tuners: tuners)
        #expect(devices.isEmpty)
        #expect(tuners.requests.isEmpty)
    }

    /// L4 keeps link-local: a tuner on a direct cable (169.254/16) is found.
    @Test func linkLocalInterfaceAndReplyWork() async {
        let interfaces = [Self.interface("en0", [169, 254, 10, 2], netmask: [255, 255, 0, 0])]
        let sent = SentTargets()
        let tuners = FakeTuners(["http://169.254.20.9/discover.json":
                                    Self.discoverJSON(baseURL: "http://169.254.20.9:80",
                                                      lineupURL: "http://169.254.20.9/lineup.json")])
        let devices = await Self.find([Self.datagram(Self.reply(baseURL: "http://169.254.20.9:80"),
                                                     from: "169.254.20.9")],
                                      tuners: tuners, interfaces: interfaces, sent: sent,
                                      ownAddresses: ["169.254.10.2"])
        #expect(sent.targets == [HDHomeRunBroadcaster.Target(interface: "en0", broadcast: [169, 254, 255, 255])])
        #expect(devices.map(\.id) == ["1234ABCD"])
        #expect(HDHomeRunHTTP.isAllowed(URL(string: "http://169.254.20.9/lineup.json")!))
    }

    /// Security M1: which interfaces are searched.
    @Test func onlyLANInterfacesAreSearched() {
        let skipped = [
            "utun3", "ipsec0", "ppp0", "bridge100", "vmnet8", "gif0", "stf0", "awdl0", "llw0", "feth1", "tap0", "zt0",
        ].map { Self.interface($0, [10, 1, 2, 3]) } + [
            Self.interface("en5", [203, 0, 113, 2]),                       // a public address of its own
            Self.interface("lo0", [10, 0, 0, 2], isLoopback: true),
            Self.interface("en2", [10, 0, 0, 2], isUp: false),
            Self.interface("en3", [10, 0, 0, 2], isBroadcast: false),
            Self.interface("en4", [10, 0, 0, 2], isPointToPoint: true),
            Self.interface("en6", [10, 0, 0, 2], netmask: [255, 255, 255, 255]),   // /32: no broadcast
            // Security L-c: VirtualBox and Parallels host-only networks.
            Self.interface("vboxnet0", [192, 168, 56, 1]),
            Self.interface("vnic0", [10, 211, 55, 2]),
        ]
        let kept = [Self.interface("en0", [192, 168, 1, 2]), Self.interface("en1", [172, 16, 4, 2]),
                    Self.interface("en7", [169, 254, 3, 4], netmask: [255, 255, 0, 0])]
        let searched = HDHomeRunDiscovery.searchInterfaces(skipped + kept + kept)
        #expect(searched == kept)
        #expect(HDHomeRunDiscovery.targets(searched).map(\.broadcast)
                == [[192, 168, 1, 255], [172, 16, 4, 255], [169, 254, 255, 255]])
        // Host-only networks alone give no targets; Wake-on-LAN's own list is unchanged.
        let hostOnly = [Self.interface("vboxnet0", [192, 168, 56, 1]), Self.interface("vnic0", [10, 211, 55, 2])]
        #expect(HDHomeRunDiscovery.targets(HDHomeRunDiscovery.searchInterfaces(hostOnly)).isEmpty)
        #expect(!WakeOnLAN.excludedInterfacePrefixes.contains("vboxnet"))
        #expect(!WakeOnLAN.excludedInterfacePrefixes.contains("vnic"))
    }

    @Test func noLANInterfaceMeansNoSearch() async {
        let tuners = FakeTuners([:])
        let resolver = FakeResolver(["10.0.0.9"])
        let sent = SentTargets()
        let devices = await Self.find([Self.datagram(Self.reply())], tuners: tuners,
                                      interfaces: [Self.interface("utun0", [10, 0, 0, 2])], resolver: resolver,
                                      sent: sent)
        #expect(devices.isEmpty)
        #expect(sent.targets == nil)
        #expect(resolver.names.isEmpty)
        #expect(tuners.requests.isEmpty)
    }

    @Test func badDiscoverJSONIsRejected() async {
        for body in [Data("not json".utf8), Data("{}".utf8), Data(#"{"DeviceID":"1234ABCD"}"#.utf8),
                     Self.discoverJSON(tunerCount: 0), Self.discoverJSON(tunerCount: 17),
                     Self.discoverJSON(id: "")] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": body])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: tuners).isEmpty)
        }
        // A reply with a bad CRC is never fetched.
        var bytes = [UInt8](Self.reply())
        bytes[bytes.count - 1] ^= 0xFF
        let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
        #expect(await Self.find([Self.datagram(Data(bytes))], tuners: tuners).isEmpty)
        #expect(tuners.requests.isEmpty)
        // 16 tuners is the most.
        let sixteen = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(tunerCount: 16)])
        #expect(await Self.find([Self.datagram(Self.reply())], tuners: sixteen).first?.tunerCount == 16)
    }

    @Test func fallsBackToHdhomerunLocalWhenNothingAnswers() async {
        let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
        let resolver = FakeResolver(["10.0.0.9"])
        let devices = await Self.find([], tuners: tuners, resolver: resolver)
        #expect(devices.map(\.id) == ["1234ABCD"])
        #expect(devices.first?.baseURL == URL(string: "http://10.0.0.9:80"))
        #expect(resolver.names == ["hdhomerun.local"])
        #expect(tuners.requests == ["http://10.0.0.9/discover.json"])

        // Not used when UDP found a tuner.
        let both = FakeTuners([
            "http://10.0.0.9/discover.json": Self.discoverJSON(),
            "http://10.0.0.10/discover.json": Self.discoverJSON(id: "FFFF0000", baseURL: "http://10.0.0.10",
                                                                lineupURL: "http://10.0.0.10/lineup.json"),
        ])
        let unused = FakeResolver(["10.0.0.10"])
        #expect(await Self.find([Self.datagram(Self.reply())], tuners: both, resolver: unused).map(\.id) == ["1234ABCD"])
        #expect(both.requests == ["http://10.0.0.9/discover.json"])
        #expect(unused.names.isEmpty)
    }

    /// Security M2: the fallback asks only an address that passes the UDP source checks, by IP literal, and the
    /// answer's BaseURL must be that address.
    @Test func localFallbackNeedsALANBaseURL() async {
        // Resolved to a public, loopback, own or off-subnet address: nothing is fetched.
        for address in ["203.0.113.5", "127.0.0.1", "10.0.0.2", "192.168.5.9", "fd00::9", "010.0.0.9"] {
            let tuners = FakeTuners(["http://\(address)/discover.json": Self.discoverJSON(baseURL: "http://\(address)")])
            #expect(await Self.find([], tuners: tuners, resolver: FakeResolver([address])).isEmpty, "\(address)")
            #expect(tuners.requests.isEmpty, "\(address)")
        }
        // Resolved to the tuner, but its discover.json points elsewhere or isn't an origin.
        for (baseURL, lineupURL) in [("http://10.0.0.50", "http://10.0.0.50/lineup.json"),
                                     ("http://10.0.0.9", "http://10.0.0.50/lineup.json"),
                                     ("http://hdhomerun.local", "http://hdhomerun.local/lineup.json"),
                                     ("http://10.0.0.9:8080/x", "http://10.0.0.9/lineup.json")] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json":
                                        Self.discoverJSON(baseURL: baseURL, lineupURL: lineupURL)])
            #expect(await Self.find([], tuners: tuners, resolver: FakeResolver(["10.0.0.9"])).isEmpty, "\(baseURL)")
            #expect(tuners.requests == ["http://10.0.0.9/discover.json"])
        }
        // Only the acceptable addresses of several are asked, each once.
        let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
        let devices = await Self.find([], tuners: tuners,
                                      resolver: FakeResolver(["203.0.113.5", "10.0.0.7", "10.0.0.7", "10.0.0.9"]))
        #expect(devices.map(\.id) == ["1234ABCD"])
        #expect(tuners.requests == ["http://10.0.0.7/discover.json", "http://10.0.0.9/discover.json"])
    }

    @Test func liveFetchOnlyGoesToLANHTTP() {
        #expect(HDHomeRunHTTP.isAllowed(URL(string: "http://10.0.0.9/discover.json")!))
        #expect(HDHomeRunHTTP.isAllowed(URL(string: "http://192.168.1.20:5004/auto/v5.1")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://hdhomerun.local/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "https://10.0.0.9/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://203.0.113.5/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://example.com/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://user:pw@10.0.0.9/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://127.0.0.1/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://[fd00::9]/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://010.0.0.9/discover.json")!))
        // Step 3 security M1: Foundation decodes these to 10.0.0.9, but the raw host isn't the literal.
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://10.0.0%2E9/discover.json")!))
        #expect(!HDHomeRunHTTP.isAllowed(URL(string: "http://%31%30.0.0.9/discover.json")!))
    }

    /// Step 3 security M1: a percent-encoded host in the BaseURL (UDP or discover.json) or the LineupURL is
    /// refused, though Foundation decodes it to the tuner's own address.
    @Test func percentEncodedHostsAreRejected() async {
        for baseURL in ["http://10.0.0%2E9", "http://%31%30.0.0.9:80"] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON()])
            #expect(await Self.find([Self.datagram(Self.reply(baseURL: baseURL))], tuners: tuners).isEmpty, "\(baseURL)")
            #expect(tuners.requests.isEmpty, "\(baseURL)")
            let listed = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(baseURL: baseURL)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: listed).isEmpty, "\(baseURL)")
        }
        for lineupURL in ["http://10.0.0%2E9/lineup.json", "http://%31%30.0.0.9/lineup.json"] {
            let tuners = FakeTuners(["http://10.0.0.9/discover.json": Self.discoverJSON(lineupURL: lineupURL)])
            #expect(await Self.find([Self.datagram(Self.reply())], tuners: tuners).isEmpty, "\(lineupURL)")
        }
        #expect(HDHomeRunDiscovery.literalHost(of: URL(string: "http://10.0.0.9:5004/x")!) == "10.0.0.9")
        #expect(HDHomeRunDiscovery.literalHost(of: URL(string: "http://10.0.0%2E9/x")!) == nil)
        #expect(!HDHomeRunDiscovery.isHTTP(URL(string: "http://10.0.0%2E9/")!, on: "10.0.0.9"))
    }

    // MARK: The UDP collector (security L1, L2)

    /// L1: only parsed tuner replies are kept, and reading stops for good after 256 datagrams of any kind.
    @Test func collectorStopsAtTheHardCap() {
        let collector = HDHomeRunBroadcaster.Collector()
        for index in 0..<300 {
            collector.receive(Data([UInt8(index & 0xFF), 1, 2, 3]), from: "10.0.0.\(index % 200 + 3)")
        }
        #expect(collector.datagramsRead == HDHomeRunBroadcaster.Collector.maximumDatagrams)
        #expect(collector.datagrams.isEmpty)
        #expect(collector.isFinished)
        // After the cap, even a good reply isn't taken.
        collector.receive(Self.reply(), from: "10.0.0.9")
        #expect(collector.datagrams.isEmpty)
    }

    /// L1: copies from one address are kept once, at most 4 per address, nothing without an IPv4 source.
    @Test func collectorCapsEachSource() {
        let collector = HDHomeRunBroadcaster.Collector()
        for _ in 0..<10 { collector.receive(Self.reply(), from: "10.0.0.9") }
        #expect(collector.datagrams.count == 1)
        for id in UInt32(1)...10 { collector.receive(Self.reply(id: id), from: "10.0.0.9") }
        #expect(collector.datagrams.count == HDHomeRunBroadcaster.Collector.maximumPerSource)
        collector.receive(Self.reply(), from: nil)
        collector.receive(Self.reply(), from: "10.0.0.10")
        #expect(collector.datagrams.map(\.sourceAddress) == ["10.0.0.9", "10.0.0.9", "10.0.0.9", "10.0.0.9",
                                                             "10.0.0.10"])
        #expect(!collector.isFinished)
    }

    /// L1: 64 parsed replies end the collection.
    @Test func collectorStopsAt64Replies() {
        let collector = HDHomeRunBroadcaster.Collector()
        for index in 0..<70 {
            collector.receive(Data("junk".utf8), from: "10.0.1.\(index)")
            collector.receive(Self.reply(id: UInt32(index)), from: "10.0.1.\(index)")
        }
        #expect(collector.datagrams.count == HDHomeRunBroadcaster.Collector.maximumReplies)
        #expect(collector.isFinished)
    }

    /// L2: one read event takes at most 32 datagrams; the rest wait for the next event.
    @Test func readTakesAtMost32DatagramsPerEvent() throws {
        var pair: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_DGRAM, 0, &pair) == 0)
        defer { pair.forEach { Darwin.close($0) } }
        var size: Int32 = 256 * 1024
        for fd in pair {
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        }
        try #require(HDHomeRunBroadcaster.setNonBlocking(pair[0]))
        let datagram: [UInt8] = [1, 2, 3, 4]
        for _ in 0..<40 {
            try #require(Darwin.send(pair[1], datagram, datagram.count, 0) == datagram.count)
        }
        let collector = HDHomeRunBroadcaster.Collector()
        collector.read(pair[0])
        #expect(collector.datagramsRead == HDHomeRunBroadcaster.Collector.readsPerEvent)
        collector.read(pair[0])
        #expect(collector.datagramsRead == 40)
        collector.read(pair[0])   // nothing waiting: returns at once
        #expect(collector.datagramsRead == 40)
        #expect(collector.datagrams.isEmpty)   // not from an IPv4 address
    }

    /// L2: a failed `fcntl` is reported (the socket is then closed and the search finds nothing).
    @Test func setNonBlockingReportsFailure() {
        #expect(!HDHomeRunBroadcaster.setNonBlocking(-1))
    }
}
