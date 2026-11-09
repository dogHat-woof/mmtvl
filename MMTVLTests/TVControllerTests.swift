import Foundation
import Network
import Testing
@testable import MMTVL

/// Scripted network for `TVController`: whether the port answers, SOAP replies, and every effect with the fake time.
final class FakeTVNetwork {
    let clock = FakeReceiverClock()
    /// Called for each connection check (1-based); the address it reached, or nil (which takes the whole timeout).
    var answers: (Int) -> String? = { _ in nil }
    /// Overrides `answers` when it returns a value (e.g. `.notOnLAN`).
    var outcome: (Int) -> TVReach? = { _ in nil }
    var replies: [String: (status: Int, body: Data)] = [:]
    private(set) var connects: [(host: String, port: UInt16, at: Duration)] = []
    private(set) var requests: [(action: String, address: String)] = []
    private(set) var wakes: [(mac: MACAddress, tvAddress: String?, at: Duration)] = []
    var onWake: ((Int) -> Void)?
    /// Step 9c: called with each SOAP action as it's requested (before its reply).
    var onSOAP: ((String) -> Void)?

    func controller(search: @escaping ReceiverDiscovery.Search = { _, _ in [] },
                    fetch: @escaping ReceiverDiscovery.Fetch = { _ in nil },
                    ownAddresses: @escaping () -> [String] = { [] },
                    interfaces: @escaping () -> [WakeOnLAN.Interface] = { LANFixture.interfaces }) -> TVController {
        TVController(
            clock: clock,
            connect: { host, port, timeout in
                self.connects.append((host, port, self.clock.now))
                if let outcome = self.outcome(self.connects.count) { return outcome }
                guard let address = self.answers(self.connects.count) else {
                    self.clock.now += timeout
                    return .noAnswer
                }
                return .reached(address)
            },
            soap: { request, address in
                self.requests.append((request.soapAction, address))
                self.onSOAP?(request.soapAction)
                guard let reply = self.replies[request.soapAction] else { throw URLError(.timedOut) }
                return reply
            },
            wake: { mac, tvAddress in
                self.wakes.append((mac, tvAddress, self.clock.now))
                self.onWake?(self.wakes.count)
            },
            search: search, fetch: fetch, ownAddresses: ownAddresses, interfaces: interfaces)
    }
}

/// M7h L18: on/off by port 55000, Power only when on, Wake-on-LAN until the TV answers, Test and Find TV.
struct TVControllerTests {
    private static let sendKey = "urn:panasonic-com:service:p00NetworkControl:1#X_SendKey"
    private static let getVolume = "urn:schemas-upnp-org:service:RenderingControl:1#GetVolume"
    private static let getMute = "urn:schemas-upnp-org:service:RenderingControl:1#GetMute"
    private static let mac = MACAddress(parsing: "02005e0010ab")!

    private static func reply(_ inner: String) -> (status: Int, body: Data) {
        (200, Data(#"<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>\#(inner)</s:Body></s:Envelope>"#.utf8))
    }

    private func configured(_ network: FakeTVNetwork, host: String = "192.168.1.30",
                            mac: String? = "02:00:5e:00:10:ab") -> TVController {
        let tv = network.controller()
        tv.configure(brand: .panasonic, host: host, mac: mac)
        return tv
    }

    // MARK: Configuration

    @Test func configureKeepsOnlyLANHostsAndRealMACs() {
        let tv = FakeTVNetwork().controller()
        tv.configure(brand: .panasonic, host: " 192.168.1.30 ", mac: "02-00-5E-00-10-AB")
        #expect(tv.host == "192.168.1.30")
        #expect(tv.mac == Self.mac)
        #expect(tv.isConfigured)
        tv.configure(brand: .panasonic, host: "tv.local", mac: nil)
        #expect(tv.host == "tv.local")
        #expect(tv.mac == nil)
        for bad in ["8.8.8.8", "127.0.0.1", "http://192.168.1.30/", "fe80::1%lo0", ""] {
            tv.configure(brand: .panasonic, host: bad, mac: "nope")
            #expect(tv.host == nil, "\(bad)")
            #expect(tv.mac == nil)
            #expect(!tv.isConfigured)
        }
        tv.configure(brand: .none, host: "192.168.1.30", mac: nil)
        #expect(!tv.isConfigured)
    }

    @Test func notSetUpSendsNothing() async {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.30" }
        let tv = network.controller()
        tv.configure(brand: .none, host: "192.168.1.30", mac: "02005e0010ab")
        #expect(await !tv.isOn())
        #expect(await !tv.powerOff())
        #expect(await !tv.powerOn())
        #expect(await tv.test() == TVTestResult(isOn: false, volume: nil, isMuted: nil, canTurnOn: true))
        #expect(network.connects.isEmpty)
        #expect(network.requests.isEmpty)
        #expect(network.wakes.isEmpty)
    }

    // MARK: On and off

    @Test func isOnConnectsToPort55000() async {
        let network = FakeTVNetwork()
        let tv = configured(network)
        #expect(await !tv.isOn())
        network.answers = { _ in "192.168.1.30" }
        #expect(await tv.isOn())
        #expect(network.connects.map(\.port) == [55000, 55000])
        #expect(network.connects.map(\.host) == ["192.168.1.30", "192.168.1.30"])
        #expect(network.requests.isEmpty)
    }

    @Test func powerOffDoesNotSendWhenTheTVIsOff() async {
        let network = FakeTVNetwork()
        let tv = configured(network)
        #expect(await !tv.powerOff())
        #expect(network.connects.count == 1)
        #expect(network.requests.isEmpty)
    }

    @Test func powerOffSendsThePowerKeyToTheAddressReached() async {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.30" }
        network.replies[Self.sendKey] = Self.reply("<u:X_SendKeyResponse/>")
        let tv = configured(network, host: "tv.local")
        #expect(await tv.powerOff())
        #expect(network.requests.map(\.action) == [Self.sendKey])
        #expect(network.requests.map(\.address) == ["192.168.1.30"])
    }

    @Test func powerOffReportsAFault() async {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.30" }
        network.replies[Self.sendKey] = (500, Data(#"<s:Envelope xmlns:s="x"><s:Body><s:Fault><faultcode>s:Client</faultcode></s:Fault></s:Body></s:Envelope>"#.utf8))
        #expect(await !configured(network).powerOff())
    }

    // MARK: Wake-on-LAN

    @Test func powerOnWakesEveryTwoSecondsUntilTheTVAnswers() async {
        let network = FakeTVNetwork()
        network.answers = { $0 >= 3 ? "192.168.1.30" : nil }
        let tv = configured(network)
        #expect(await tv.powerOn())
        #expect(network.wakes.map(\.at) == [.zero, .seconds(2), .seconds(4)])
        #expect(network.wakes.allSatisfy { $0.mac == Self.mac && $0.tvAddress == "192.168.1.30" })
        #expect(network.connects.count == 3)
        #expect(network.clock.now == .seconds(4))
    }

    @Test func powerOnGivesUpAtThirtySeconds() async {
        let network = FakeTVNetwork()
        let tv = configured(network)
        #expect(await !tv.powerOn())
        #expect(network.clock.now == .seconds(30))
        #expect(network.wakes.map(\.at) == stride(from: 0, to: 30, by: 2).map { Duration.seconds($0) })
        #expect(network.connects.allSatisfy { $0.at < .seconds(30) })
    }

    @Test func powerOnNeedsAMAC() async {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.30" }
        let tv = configured(network, mac: nil)
        #expect(await !tv.powerOn())
        #expect(network.wakes.isEmpty)
        #expect(network.connects.isEmpty)
    }

    /// A name: the packet goes to the address it last reached (or every LAN broadcast before that).
    @Test func powerOnAimsAtTheAddressANameReached() async {
        let network = FakeTVNetwork()
        let tv = configured(network, host: "tv.local")
        network.answers = { _ in "192.168.1.30" }
        #expect(await tv.isOn())
        network.answers = { _ in nil }
        network.onWake = { if $0 == 2 { network.answers = { _ in "192.168.1.30" } } }
        #expect(await tv.powerOn())
        #expect(network.wakes.map(\.tvAddress) == ["192.168.1.30", "192.168.1.30"])
    }

    @Test func powerOnBeforeANameResolvedBroadcastsOnly() async {
        let network = FakeTVNetwork()
        let tv = configured(network, host: "tv.local")
        network.onWake = { if $0 == 1 { network.answers = { _ in "192.168.1.30" } } }
        #expect(await tv.powerOn())
        #expect(network.wakes.map(\.tvAddress) == [nil])
    }

    @Test func powerOffStopsARunningPowerOn() async {
        let network = FakeTVNetwork()
        let tv = configured(network)
        network.onWake = { count in
            if count == 2 { Task { await tv.powerOff() } }
        }
        #expect(await !tv.powerOn())
        #expect(network.wakes.count <= 3)
        #expect(network.clock.now < .seconds(30))
    }

    // MARK: Test TV

    @Test func testReadsVolumeAndMute() async {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.30" }
        network.replies[Self.getVolume] = Self.reply("<u:GetVolumeResponse><CurrentVolume>12</CurrentVolume></u:GetVolumeResponse>")
        network.replies[Self.getMute] = Self.reply("<u:GetMuteResponse><CurrentMute>0</CurrentMute></u:GetMuteResponse>")
        let tv = configured(network)
        #expect(await tv.test() == TVTestResult(isOn: true, volume: 12, isMuted: false, canTurnOn: true))
        // Read-only: never the power key.
        #expect(network.requests.map(\.action) == [Self.getVolume, Self.getMute])
    }

    // MARK: Step 9c: TV volume

    private static let setVolume = "urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"
    private static let setMute = "urn:schemas-upnp-org:service:RenderingControl:1#SetMute"

    private func volumeNetwork(volume: Int = 12, muted: Bool = false) -> FakeTVNetwork {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.30" }
        network.replies[Self.getVolume] = Self.reply("<u:GetVolumeResponse><CurrentVolume>\(volume)</CurrentVolume></u:GetVolumeResponse>")
        network.replies[Self.getMute] = Self.reply("<u:GetMuteResponse><CurrentMute>\(muted ? 1 : 0)</CurrentMute></u:GetMuteResponse>")
        network.replies[Self.setVolume] = Self.reply("<u:SetVolumeResponse/>")
        network.replies[Self.setMute] = Self.reply("<u:SetMuteResponse/>")
        return network
    }

    @Test func volumeReadsThenSetsOneStep() async {
        let network = volumeNetwork()
        let tv = configured(network)
        #expect(!tv.isAnsweringForVolume)
        #expect(await tv.changeVolume(.up) == .level(13, muted: false))
        #expect(network.requests.map(\.action) == [Self.getVolume, Self.getMute, Self.setVolume])
        #expect(network.requests.allSatisfy { $0.address == "192.168.1.30" })
        #expect(tv.isAnsweringForVolume)
        #expect(await tv.changeVolume(.down) == .level(11, muted: false))
        #expect(network.requests.last?.action == Self.setVolume)
    }

    @Test func volumeAtTheEndsSendsNoSet() async {
        for (volume, action) in [(100, VolumeAction.up), (0, .down)] {
            let network = volumeNetwork(volume: volume)
            let tv = configured(network)
            #expect(await tv.changeVolume(action) == .level(volume, muted: false))
            #expect(network.requests.map(\.action) == [Self.getVolume, Self.getMute])
        }
    }

    @Test func muteToggles() async {
        let network = volumeNetwork(muted: true)
        let tv = configured(network)
        #expect(await tv.changeVolume(.mute) == .level(12, muted: false))
        #expect(network.requests.map(\.action) == [Self.getVolume, Self.getMute, Self.setMute])
    }

    @Test func aFailedVolumeRequestIsNotReady() async {
        let network = volumeNetwork()
        network.replies[Self.setVolume] = nil
        let tv = configured(network)
        #expect(await tv.changeVolume(.up) == .failed)
        #expect(!tv.isAnsweringForVolume)
        // An off TV: no SOAP at all.
        let off = FakeTVNetwork()
        let offTV = configured(off)
        #expect(await offTV.changeVolume(.up) == .failed)
        #expect(off.requests.isEmpty)
        // The readiness check is the connection check.
        await offTV.checkVolumeReadiness()
        #expect(!offTV.isAnsweringForVolume)
        await tv.checkVolumeReadiness()
        #expect(tv.isAnsweringForVolume)
        // Another TV setting: not ready until checked again.
        tv.configure(brand: .panasonic, host: "192.168.1.31", mac: nil)
        #expect(!tv.isAnsweringForVolume)
        // HDMI-CEC isn't this controller's: it never sends SOAP for it.
        tv.configure(brand: .cec, host: "192.168.1.30", mac: nil)
        #expect(!tv.canChangeVolume)
    }

    /// Security L3: `configure` during a volume press stops it before the next request (no SetVolume or SetMute).
    @Test func aSettingsChangeDuringAVolumePressStopsIt() async {
        for (changeAt, sent) in [(Self.getVolume, [Self.getVolume]), (Self.getMute, [Self.getVolume, Self.getMute])] {
            let network = volumeNetwork()
            let tv = configured(network)
            network.onSOAP = { action in
                if action == changeAt { tv.configure(brand: .panasonic, host: "192.168.1.31", mac: nil) }
            }
            #expect(await tv.changeVolume(.up) == .failed)
            #expect(network.requests.map(\.action) == sent)
            let mute = volumeNetwork()
            let muteTV = configured(mute)
            mute.onSOAP = { action in
                if action == changeAt { muteTV.configure(brand: .none, host: nil, mac: nil) }
            }
            #expect(await muteTV.changeVolume(.mute) == .failed)
            #expect(!mute.requests.contains { $0.action == Self.setMute })
        }
    }

    @Test func testOfAnOffTVSendsNoSOAP() async {
        let network = FakeTVNetwork()
        let tv = configured(network, mac: nil)
        #expect(await tv.test() == TVTestResult(isOn: false, volume: nil, isMuted: nil, canTurnOn: false))
        #expect(network.requests.isEmpty)
    }

    @Test func testWithoutStatusRepliesIsStillOn() async {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.30" }
        let tv = configured(network)
        #expect(await tv.test() == TVTestResult(isOn: true, volume: nil, isMuted: nil, canTurnOn: true))
    }

    // MARK: Find TV

    private static let vieraResponse = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        EXT:\r
        LOCATION: http://192.168.1.30:55000/nrc/ddd.xml\r
        SERVER: Linux/2.6 UPnP/1.0 Panasonic-UPnP-MW/1.0\r
        ST: urn:panasonic-com:device:p00RemoteController:1\r
        USN: uuid:4D454930-0200-1000-8001-02005E0010AB::urn:panasonic-com:device:p00RemoteController:1\r
        \r

        """

    private static func description(name: String, udn: String) -> Data {
        Data("""
            <?xml version="1.0"?>
            <root xmlns="urn:schemas-upnp-org:device-1-0">
              <device>
                <deviceType>urn:panasonic-com:device:p00RemoteController:1</deviceType>
                <friendlyName>\(name)</friendlyName>
                <manufacturer>Panasonic</manufacturer>
                <modelName>Panasonic VIERA</modelName>
                <UDN>\(udn)</UDN>
              </device>
            </root>
            """.utf8)
    }

    @Test func responseAndDescriptionGiveATV() throws {
        let response = try #require(SSDPSearch.parseResponse(Data(Self.vieraResponse.utf8)))
        #expect(response.searchTarget == PanasonicViera.searchTarget)
        let url = try #require(SSDPSearch.descriptionURL(response.location))
        let description = try #require(UPnPDeviceDescription.parse(
            Self.description(name: "VIERA VT50", udn: "uuid:4D454930-0200-1000-8001-02005E0010AB")))
        #expect(TVController.foundTV(location: url, description: description)
            == FoundTV(host: "192.168.1.30", name: "VIERA VT50", mac: Self.mac))
        let noMAC = try #require(UPnPDeviceDescription.parse(
            Self.description(name: "VIERA", udn: "uuid:f47ac10b-58cc-4372-a567-0e02b2c3d479")))
        #expect(TVController.foundTV(location: url, description: noMAC)?.mac == nil)
    }

    @Test func findSearchesForTheVIERARemoteControllerOnTheLAN() async {
        let target = PanasonicViera.searchTarget
        let responses = [
            SSDPSearchResponse(location: "http://192.168.1.30:55000/nrc/ddd.xml", searchTarget: target,
                               sourceAddress: "192.168.1.30"),
            // Another device answering a search it wasn't asked.
            SSDPSearchResponse(location: "http://192.168.1.20/desc.xml", searchTarget: "upnp:rootdevice",
                               sourceAddress: "192.168.1.20"),
            // Not on the LAN, or not where the reply came from, or the Mac itself.
            SSDPSearchResponse(location: "http://8.8.8.8:55000/nrc/ddd.xml", searchTarget: target, sourceAddress: "8.8.8.8"),
            SSDPSearchResponse(location: "http://tv.local:55000/nrc/ddd.xml", searchTarget: target,
                               sourceAddress: "192.168.1.31"),
            SSDPSearchResponse(location: "http://192.168.1.32:55000/nrc/ddd.xml", searchTarget: target,
                               sourceAddress: "192.168.1.33"),
            SSDPSearchResponse(location: "http://192.168.1.10:55000/nrc/ddd.xml", searchTarget: target,
                               sourceAddress: "192.168.1.10"),
            // The same TV again on another path.
            SSDPSearchResponse(location: "http://192.168.1.30:55000/dmr/ddd.xml", searchTarget: target,
                               sourceAddress: "192.168.1.30"),
        ]
        var searched: [String] = []
        var fetched: [String] = []
        let network = FakeTVNetwork()
        let tv = network.controller(
            search: { target, duration in
                searched.append("\(target) \(duration)")
                return responses
            },
            fetch: { url in
                fetched.append(url.absoluteString)
                return Self.description(name: "VIERA VT50", udn: "uuid:4D454930-0200-1000-8001-02005E0010AB")
            },
            ownAddresses: { ["192.168.1.10"] })
        let found = await tv.find()
        #expect(searched == ["urn:panasonic-com:device:p00RemoteController:1 3.0 seconds"])
        #expect(Set(fetched) == ["http://192.168.1.30:55000/nrc/ddd.xml", "http://192.168.1.30:55000/dmr/ddd.xml"])
        #expect(found == [FoundTV(host: "192.168.1.30", name: "VIERA VT50", mac: Self.mac)])
        // Find sends nothing to a TV.
        #expect(network.connects.isEmpty)
        #expect(network.requests.isEmpty)
        #expect(network.wakes.isEmpty)
    }

    @Test func nonLANLocationIsIgnored() async {
        let network = FakeTVNetwork()
        var fetched = 0
        let tv = network.controller(
            search: { target, _ in
                [SSDPSearchResponse(location: "http://203.0.113.9:55000/nrc/ddd.xml", searchTarget: target,
                                    sourceAddress: "203.0.113.9")]
            },
            fetch: { _ in
                fetched += 1
                return nil
            })
        #expect(await tv.find().isEmpty)
        #expect(fetched == 0)
    }

    // MARK: Live probe guards

    /// Refused before any connection: loopback, public and malformed hosts.
    @Test func connectProbeRefusesNonLANHosts() async {
        for host in ["127.0.0.1", "localhost", "tv.localhost", "8.8.8.8", "fe80::1%lo0", "fd00::5", "", "http://192.168.1.30/"] {
            #expect(await TVConnectProbe.connect(host: host, port: 55000, timeout: .seconds(1)) == .notOnLAN, "\(host)")
        }
    }

    @Test func connectProbeReportsIPv4Addresses() {
        #expect(TVConnectProbe.ipv4String(.hostPort(host: "192.168.1.30", port: 55000)) == "192.168.1.30")
        #expect(TVConnectProbe.ipv4String(.hostPort(host: "::ffff:192.168.1.30", port: 55000)) == "192.168.1.30")
        #expect(TVConnectProbe.ipv4String(.hostPort(host: "fe80::1", port: 55000)) == nil)
        #expect(TVConnectProbe.ipv4String(.hostPort(host: .name("tv.local", nil), port: 55000)) == nil)
    }

    // MARK: Review fixes

    /// Security S2: straight to the TV, never through a system proxy.
    @Test func noProxies() throws {
        #expect(VieraHTTP.session.configuration.connectionProxyDictionary?.isEmpty == true)
        #expect(DeviceDescriptionFetcher.session.configuration.connectionProxyDictionary?.isEmpty == true)
        let parameters = TVConnectProbe.parameters(timeout: .seconds(1))
        #expect(parameters.preferNoProxies)
        #expect(parameters.prohibitedInterfaceTypes == [.loopback])
        let ip = try #require(parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)
        #expect(ip.version == .v4)
    }

    /// Security S3: nothing from the network but a numeric fault code reaches the log.
    @Test func faultsAreDescribedByNumericCodeOnly() {
        let injected = TVController.describe(VieraError.fault(code: "1\nTV: Power sent", description: "x"))
        #expect(!injected.contains("\n"))
        #expect(!injected.contains("Power sent"))
        #expect(!injected.contains("x"))
        #expect(injected == "SOAP fault")
        #expect(TVController.describe(VieraError.fault(code: "401", description: "Invalid\nAction")) == "SOAP fault 401")
        #expect(TVController.describe(VieraError.fault(code: nil, description: "Busy")) == "SOAP fault")
        #expect(TVController.describe(VieraError.fault(code: "s:Client", description: nil)) == "SOAP fault")
    }

    /// Security S4: once the host reached an address off the LAN, nothing more is tried until `configure`.
    @Test func anOffLANRefusalIsLatched() async {
        let network = FakeTVNetwork()
        network.outcome = { $0 == 1 ? .notOnLAN : nil }
        network.answers = { _ in "192.168.1.30" }
        let tv = configured(network, host: "tv.example")
        #expect(await !tv.powerOn())
        #expect(network.connects.count == 1)
        #expect(tv.refusedHost)
        #expect(await !tv.isOn())
        #expect(await tv.test().isOn == false)
        #expect(await !tv.powerOff())
        #expect(await !tv.powerOn())
        #expect(network.connects.count == 1)
        #expect(network.requests.isEmpty)
        #expect(network.wakes.count <= 1)
        tv.configure(brand: .panasonic, host: "tv.example", mac: "02005e0010ab")
        #expect(!tv.refusedHost)
        #expect(await tv.isOn())
        #expect(network.connects.count == 2)
    }

    /// Security S4, S5: `localhost` and the Mac's own addresses are refused up front, and a name that reaches one
    /// of the Mac's addresses is refused (and latched).
    @Test func localhostAndOwnAddressesAreRefused() async {
        let network = FakeTVNetwork()
        network.answers = { _ in "192.168.1.10" }
        let tv = network.controller(ownAddresses: { ["192.168.1.10", "fe80::1"] })
        for host in ["localhost", "LocalHost.", "tv.localhost", "192.168.1.10"] {
            tv.configure(brand: .panasonic, host: host, mac: nil)
            #expect(tv.host == nil, "\(host)")
        }
        #expect(network.connects.isEmpty)
        tv.configure(brand: .panasonic, host: "tv.local", mac: nil)
        #expect(tv.host == "tv.local")
        #expect(await !tv.isOn())
        #expect(tv.refusedHost)
        #expect(await !tv.isOn())
        #expect(network.connects.count == 1)
        #expect(TVController.isAllowedHost("192.168.1.30", ownAddresses: ["192.168.1.10"]))
    }

    /// QA Q2: control and Wake-on-LAN are IPv4 only.
    @Test func ipv6IsRefused() throws {
        let tv = FakeTVNetwork().controller()
        for host in ["fd00::5", "[fd00::5]", "fe80::1%en0", "::ffff:192.168.1.30"] {
            tv.configure(brand: .panasonic, host: host, mac: nil)
            #expect(tv.host == nil, "\(host)")
        }
        let url = try #require(URL(string: "http://[fd00::5]:55000/nrc/ddd.xml"))
        let description = UPnPDeviceDescription(friendlyName: "VIERA", udn: "uuid:4D454930-0200-1000-8001-02005E0010AB")
        #expect(TVController.foundTV(location: url, description: description) == nil)
    }
}
