import Darwin
import Foundation
import Network
import os

// M7h L18: the TV over the network (Panasonic VIERA). On or off is whether port 55000 accepts a connection within
// 1 s (its network is down in standby); off is the power key over SOAP, only when on (the key toggles); on is
// Wake-on-LAN every 2 s until the port answers, at most 30 s. Find TV is an SSDP search for the VIERA remote
// controller. Only LAN hosts: the user's `tvHost` (a LAN IP, a `.local` name or a DNS name) is connected to first,
// and only the LAN IPv4 address that connection reached gets the SOAP request. Logs show the host, never the MAC.
// Nothing is sent to the TV at launch. Power (step 12) and Settings (step 11) call this.
// Step 9c, only with Volume Buttons Change TV Volume on: the volume buttons read GetVolume/GetMute, then SetVolume
// (±1, clamped 0…100) or SetMute (toggled). Ready for volume = the last connection check reached the TV.

/// `settings.json` `tvBrand` (L18; `cec` from step 9, reopened: `HDMICEC`). Unknown values read as `none`.
nonisolated enum TVBrand: String, Codable, CaseIterable, Sendable {
    case none, panasonic, cec
}

/// Test TV's read-only answer.
nonisolated struct TVTestResult: Equatable, Sendable {
    var isOn: Bool
    /// 0…100; nil when off or it didn't answer.
    var volume: Int?
    var isMuted: Bool?
    /// A MAC is set, so MMTVL can turn the TV on.
    var canTurnOn: Bool
}

/// A TV that answered Find TV.
nonisolated struct FoundTV: Hashable, Sendable {
    /// The `LOCATION` host, a LAN IP literal.
    var host: String
    /// The description's `friendlyName` ("VIERA VT50").
    var name: String?
    /// From the UDN; nil when it doesn't hold one (Settings then says the TV can't be turned on).
    var mac: MACAddress?
}

/// One connection check's outcome.
nonisolated enum TVReach: Equatable, Sendable {
    /// The port answered; the LAN IPv4 address it reached.
    case reached(String)
    /// No answer within the timeout, or refused: the TV is off (or not there).
    case noAnswer
    /// The host resolved to an address MMTVL never connects to (off the LAN, loopback). Security S4: latched.
    case notOnLAN
}

/// Main actor. Every effect is injected so tests use fakes.
final class TVController {
    typealias Connect = (_ host: String, _ port: UInt16, _ timeout: Duration) async -> TVReach
    /// One SOAP request to a LAN IPv4 address: the HTTP status and the body.
    typealias SOAP = (_ request: VieraRequest, _ address: String) async throws -> (status: Int, body: Data)
    /// One round of magic packets; `tvAddress` is the TV's IPv4 address when known.
    typealias Wake = (_ mac: MACAddress, _ tvAddress: String?) -> Void

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "TV")

    static let connectTimeout: Duration = .seconds(1)
    static let wakeInterval: Duration = .seconds(2)
    static let wakeLimit: Duration = .seconds(30)
    static let searchDuration: Duration = .seconds(3)

    private(set) var brand: TVBrand = .none
    /// Normalized, and a LAN address or host name; nil otherwise.
    private(set) var host: String?
    private(set) var mac: MACAddress?
    /// The IPv4 address `host` last reached (a name's address, for Wake-on-LAN while the TV is off).
    private var lastAddress: String?
    /// Bumped by `configure` and `powerOff`, so a running `powerOn` stops.
    private var generation = 0
    /// Security S4: `host` reached an address MMTVL doesn't connect to (off the LAN, loopback, the Mac itself);
    /// nothing more is tried until `configure`, like `ReceiverTCPTransport.closedForConfiguration`.
    private(set) var refusedHost = false
    /// Step 9c: the last connection check reached the TV (the volume route's cached readiness; the event tap never
    /// waits). Cleared by `configure` and a failed volume request.
    private(set) var lastCheckAnswered = false

    private let clock: any ReceiverClock
    private let connect: Connect
    private let soap: SOAP
    private let wake: Wake
    private let search: ReceiverDiscovery.Search
    private let fetch: ReceiverDiscovery.Fetch
    private let ownAddresses: () -> [String]
    private let interfaces: () -> [WakeOnLAN.Interface]

    init(clock: any ReceiverClock = SystemReceiverClock(),
         connect: @escaping Connect = { await TVConnectProbe.connect(host: $0, port: $1, timeout: $2) },
         soap: @escaping SOAP = { try await VieraHTTP.send($0, to: $1) },
         wake: @escaping Wake = { WakeOnLANSender.send(mac: $0, tvAddress: $1) },
         search: @escaping ReceiverDiscovery.Search = { await SSDPSearcher.search(target: $0, duration: $1) },
         fetch: @escaping ReceiverDiscovery.Fetch = { await DeviceDescriptionFetcher.fetch($0) },
         ownAddresses: @escaping () -> [String] = LANAddress.ownAddresses,
         interfaces: @escaping () -> [WakeOnLAN.Interface] = WakeOnLAN.interfaces) {
        self.clock = clock
        self.connect = connect
        self.soap = soap
        self.wake = wake
        self.search = search
        self.fetch = fetch
        self.ownAddresses = ownAddresses
        self.interfaces = interfaces
    }

    /// From `settings.json`: `tvHost` must be a LAN IPv4 address or a host name (the same rule as `receiverHost`,
    /// L17; a name must reach a LAN address), not an IPv6 literal (QA Q2: control and Wake-on-LAN are IPv4),
    /// `localhost` or one of the Mac's own addresses (Security S4, S5); `tvMAC` a unicast MAC. Sends nothing.
    func configure(brand: TVBrand, host: String?, mac: String?) {
        generation += 1
        self.brand = brand
        lastAddress = nil
        refusedHost = false
        lastCheckAnswered = false
        let normalized = host.flatMap(LANAddress.normalized)
        let isIPv6 = normalized?.contains(":") == true
        self.host = normalized.flatMap { Self.isAllowedHost($0, ownAddresses: ownAddresses()) ? $0 : nil }
        self.mac = mac.flatMap(MACAddress.init(parsing:))
        // HDMI-CEC (step 9) isn't over the network: `HDMICEC`.
        guard brand == .panasonic else { return }
        if isIPv6 {
            Self.logger.notice("TV: an IPv4 address or name is needed")
        } else if let normalized, self.host == nil {
            // Never the value itself: a pasted URL could carry credentials.
            Self.logger.notice("TV: tvHost (\(normalized.count, privacy: .public) characters) isn't a LAN address or host name")
        }
        if mac != nil, self.mac == nil { Self.logger.notice("TV: tvMAC isn't a MAC address; can't turn the TV on") }
    }

    /// Set up enough to talk to: a network brand and an address (never for HDMI-CEC, which is `HDMICEC`).
    var isConfigured: Bool { brand == .panasonic && host != nil }

    /// A normalized `tvHost` MMTVL may connect to: a LAN IPv4 literal or a host name (`isAllowedReceiverHost`), not
    /// an IPv6 literal, `localhost` (or a name under it) or one of `ownAddresses`. Pure.
    static func isAllowedHost(_ host: String, ownAddresses: [String]) -> Bool {
        guard LANAddress.isAllowedReceiverHost(host), !host.contains(":"),
              host != "localhost", !host.hasSuffix(".localhost"),
              !ownAddresses.contains(where: { LANAddress.sameAddress($0, host) })
        else { return false }
        return true
    }

    /// L18: port 55000 accepts a connection within 1 s.
    func isOn() async -> Bool {
        await reach() != nil
    }

    /// L18: the power key, only when the TV answers. True when the TV accepted it.
    @discardableResult
    func powerOff() async -> Bool {
        generation += 1
        guard isConfigured, let host else { return false }
        guard let address = await reach() else {
            Self.logger.notice("TV: \(host, privacy: .public) doesn't answer; not sending Power")
            return false
        }
        do {
            let reply = try await soap(PanasonicViera.sendKey(.power), address)
            try PanasonicViera.parseSendKey(status: reply.status, body: reply.body)
            Self.logger.notice("TV: Power sent to \(host, privacy: .public)")
            return true
        } catch {
            Self.logger.notice("TV: Power to \(host, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
            return false
        }
    }

    /// L18: Wake-on-LAN every 2 s until the TV answers; false after 30 s, without a MAC, or when `configure` or
    /// `powerOff` comes first.
    func powerOn() async -> Bool {
        generation += 1
        let current = generation
        guard isConfigured, !refusedHost, let host else { return false }
        guard let mac else {
            Self.logger.notice("TV: no MAC address set; can't turn the TV on")
            return false
        }
        let start = clock.now
        let deadline = start + Self.wakeLimit
        var nextWake = start
        var rounds = 0
        while clock.now < deadline, current == generation {
            if clock.now >= nextWake {
                wake(mac, tvAddress)
                rounds += 1
                nextWake += Self.wakeInterval
            }
            if await reach() != nil, current == generation {
                Self.logger.notice("TV: \(host, privacy: .public) is on after \(rounds, privacy: .public) Wake-on-LAN rounds")
                return true
            }
            let wait = min(nextWake, deadline) - clock.now
            if wait > .zero { await clock.sleep(for: wait) }
        }
        if current == generation {
            Self.logger.notice("TV: \(host, privacy: .public) didn't answer within \(Self.wakeLimit.components.seconds, privacy: .public) s of Wake-on-LAN (is it wired, with Wake on LAN on?)")
        }
        return false
    }

    /// Test TV (read-only): on or off, then volume and mute.
    func test() async -> TVTestResult {
        var result = TVTestResult(isOn: false, canTurnOn: mac != nil)
        guard isConfigured, let host, let address = await reach() else { return result }
        result.isOn = true
        do {
            let reply = try await soap(PanasonicViera.getVolume, address)
            result.volume = try PanasonicViera.parseVolume(status: reply.status, body: reply.body)
        } catch {
            Self.logger.notice("TV: GetVolume from \(host, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
        }
        do {
            let reply = try await soap(PanasonicViera.getMute, address)
            result.isMuted = try PanasonicViera.parseMute(status: reply.status, body: reply.body)
        } catch {
            Self.logger.notice("TV: GetMute from \(host, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
        }
        return result
    }

    /// Step 9c: one volume press on the TV's own volume. Reads the volume and mute, then steps the volume by one
    /// (clamped 0…100; mute is left as it is) or toggles mute. The TV's level and mute afterwards; nil when the TV
    /// didn't answer or a request failed (it's then not ready until the next check reaches it).
    func stepVolume(_ action: VolumeAction) async -> (volume: Int, muted: Bool)? {
        guard isConfigured, let host, let address = await reach() else { return nil }
        // Security L3: `configure` (or a power sequence) during the press stops it between requests, so no SetVolume
        // or SetMute goes to an address the settings no longer name.
        let current = generation
        do {
            let volumeReply = try await soap(PanasonicViera.getVolume, address)
            guard current == generation else { return stopped(host) }
            let volume = try PanasonicViera.parseVolume(status: volumeReply.status, body: volumeReply.body)
            let muteReply = try await soap(PanasonicViera.getMute, address)
            guard current == generation else { return stopped(host) }
            let muted = try PanasonicViera.parseMute(status: muteReply.status, body: muteReply.body)
            switch action {
            case .up, .down:
                let target = min(PanasonicViera.volumeRange.upperBound,
                                 max(PanasonicViera.volumeRange.lowerBound, volume + (action == .up ? 1 : -1)))
                guard target != volume else { return (volume, muted) }
                let reply = try await soap(PanasonicViera.setVolume(target), address)
                try PanasonicViera.parseSet(status: reply.status, body: reply.body)
                return (target, muted)
            case .mute:
                let reply = try await soap(PanasonicViera.setMute(!muted), address)
                try PanasonicViera.parseSet(status: reply.status, body: reply.body)
                return (volume, !muted)
            }
        } catch {
            Self.logger.notice("TV: volume on \(host, privacy: .public) failed: \(Self.describe(error), privacy: .public); volume takes the next route until it answers")
            if current == generation { lastCheckAnswered = false }
            return nil
        }
    }

    private func stopped(_ host: String) -> (volume: Int, muted: Bool)? {
        Self.logger.notice("TV: the TV settings changed during a volume press on \(host, privacy: .public); stopped")
        return nil
    }

    /// L18: Find TV. Each VIERA that answered the search, by `LOCATION` host (a LAN IP literal that sent the reply,
    /// not the Mac's own), with its description's name and the MAC in its UDN.
    func find() async -> [FoundTV] {
        let responses = await search(PanasonicViera.searchTarget, Self.searchDuration)
        let matching = responses.filter { $0.searchTarget?.lowercased() == PanasonicViera.searchTarget.lowercased() }
        let urls = ReceiverDiscovery.descriptionURLs(matching, ownAddresses: ownAddresses(), interfaces: interfaces())
        let fetches = urls.map { url in Task { (url, await self.fetch(url)) } }
        var found: [FoundTV] = []
        for fetch in fetches {
            let (url, data) = await fetch.value
            guard let data, let description = UPnPDeviceDescription.parse(data),
                  let tv = Self.foundTV(location: url, description: description),
                  !found.contains(where: { $0.host == tv.host })
            else { continue }
            found.append(tv)
        }
        Self.logger.notice("Find TV: \(responses.count, privacy: .public) SSDP replies, \(found.count, privacy: .public) TVs")
        return found
    }

    /// A found TV from its description. Pure.
    static func foundTV(location: URL, description: UPnPDeviceDescription) -> FoundTV? {
        // IPv4 only (QA Q2).
        guard let host = SSDPSearch.host(of: location), LANAddress.isLANIPLiteral(host), WakeOnLAN.ipv4(host) != nil
        else { return nil }
        return FoundTV(host: host, name: description.friendlyName, mac: description.udn.flatMap(MACAddress.init(udn:)))
    }

    // MARK: Private

    /// The IPv4 address to aim Wake-on-LAN at: `host` when it's one, else the address a name last reached.
    private var tvAddress: String? {
        if let host, WakeOnLAN.ipv4(host) != nil { return host }
        return lastAddress
    }

    /// Connects to the TV's port; the LAN IPv4 address it reached. After a refusal (off the LAN, loopback, the
    /// Mac's own address) nothing is tried until `configure` (Security S4, S5).
    private func reach() async -> String? {
        guard isConfigured, !refusedHost, let host else { return nil }
        let current = generation
        switch await connect(host, PanasonicViera.port, Self.connectTimeout) {
        case .reached(let address):
            guard WakeOnLAN.ipv4(address) != nil, LANAddress.isLANIPLiteral(address),
                  !ownAddresses().contains(where: { LANAddress.sameAddress($0, address) })
            else { return refuse(host) }
            lastAddress = address
            // Not after `configure` changed the TV meanwhile.
            if current == generation { lastCheckAnswered = true }
            return address
        case .noAnswer:
            lastCheckAnswered = false
            return nil
        case .notOnLAN:
            return refuse(host)
        }
    }

    private func refuse(_ host: String) -> String? {
        lastCheckAnswered = false
        if !refusedHost {
            Self.logger.notice("TV: \(host, privacy: .public) isn't a LAN address MMTVL connects to; not trying again until the TV settings change")
        }
        refusedHost = true
        generation += 1
        return nil
    }

    /// For logs. Security S3: a fault's code only when it's all digits (UPnP's), never its description or a
    /// non-numeric code, which come from the network.
    static func describe(_ error: any Error) -> String {
        switch error {
        case VieraError.fault(let code, _):
            if let code, !code.isEmpty, code.count <= 8, code.allSatisfy({ $0.isASCII && $0.isNumber }) {
                "SOAP fault \(code)"
            } else {
                "SOAP fault"
            }
        case VieraError.badResponse: "unexpected reply"
        case VieraError.status(let status): "HTTP \(status)"
        case VieraError.unreachable: "no LAN address"
        default: error.localizedDescription
        }
    }
}

// MARK: Live effects

/// L18: is the TV's port open? A TCP connection (Network.framework, IPv4, never over loopback) within `timeout`;
/// the address it reached must be a LAN IP (`ReceiverTCPTransport.isLANRemote`), else it counts as closed. Nothing is
/// written; the connection is closed at once.
enum TVConnectProbe {
    private final class Once {
        private var continuation: CheckedContinuation<TVReach, Never>?
        private var connection: NWConnection?

        init(_ continuation: CheckedContinuation<TVReach, Never>, connection: NWConnection) {
            self.continuation = continuation
            self.connection = connection
        }

        func finish(_ address: TVReach) {
            connection?.stateUpdateHandler = nil
            connection?.cancel()
            connection = nil
            continuation?.resume(returning: address)
            continuation = nil
        }
    }

    static func connect(host: String, port: UInt16, timeout: Duration) async -> TVReach {
        guard let host = LANAddress.normalized(host), TVController.isAllowedHost(host, ownAddresses: [])
        else { return .notOnLAN }
        guard let endpointPort = NWEndpoint.Port(rawValue: port), port != 0 else { return .noAnswer }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort,
                                      using: Self.parameters(timeout: timeout))
        return await withCheckedContinuation { continuation in
            let once = Once(continuation, connection: connection)
            connection.stateUpdateHandler = { state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        let path = connection.currentPath
                        guard path?.usesInterfaceType(.loopback) != true, let remote = path?.remoteEndpoint,
                              ReceiverTCPTransport.isLANRemote(remote), let address = ipv4String(remote)
                        else {
                            Logger(subsystem: "dev.mmtvl.launcher", category: "TV")
                                .notice("TV: \(host, privacy: .public) isn't on the LAN; not connecting")
                            once.finish(.notOnLAN)
                            return
                        }
                        once.finish(.reached(address))
                    case .waiting, .failed:
                        once.finish(.noAnswer)
                    default:
                        break
                    }
                }
            }
            connection.start(queue: .main)
            Task {
                try? await Task.sleep(for: timeout)
                once.finish(.noAnswer)
            }
        }
    }

    /// TCP over IPv4 only, never over loopback, never through a proxy (Security S2).
    static func parameters(timeout: Duration) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = max(1, Int(timeout.components.seconds))
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.prohibitedInterfaceTypes = [.loopback]
        parameters.preferNoProxies = true
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        return parameters
    }

    /// The endpoint's IPv4 address as a dotted quad (IPv4-mapped IPv6 included).
    nonisolated static func ipv4String(_ endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        let bytes: [UInt8]
        switch host {
        case .ipv4(let address): bytes = Array(address.rawValue)
        case .ipv6(let address):
            guard address.isIPv4Mapped, let v4 = address.asIPv4 else { return nil }
            bytes = Array(v4.rawValue)
        default: return nil
        }
        guard bytes.count == 4 else { return nil }
        return bytes.map(String.init).joined(separator: ".")
    }
}

/// L18: the SOAP requests. An ephemeral session (no cookies, no cache), 2 s per request, no redirects, at most
/// `PanasonicViera.maximumResponseSize` bytes read. Only to a LAN IPv4 literal (`VieraRequest.urlRequest`).
nonisolated enum VieraHTTP {
    static let timeout: TimeInterval = 2

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 1
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 1
        // Security S2: never through a system proxy.
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    static func send(_ request: VieraRequest, to address: String) async throws -> (status: Int, body: Data) {
        try await send(request, to: address, session: session)
    }

    static func send(_ request: VieraRequest, to address: String,
                     session: URLSession) async throws -> (status: Int, body: Data) {
        guard let urlRequest = request.urlRequest(address: address, timeout: timeout) else {
            throw VieraError.unreachable
        }
        let (bytes, response) = try await session.bytes(for: urlRequest, delegate: RedirectBlocker())
        guard let http = response as? HTTPURLResponse,
              response.expectedContentLength <= Int64(PanasonicViera.maximumResponseSize)
        else {
            bytes.task.cancel()
            throw VieraError.badResponse
        }
        guard let body = try await DeviceDescriptionFetcher.collect(bytes, limit: PanasonicViera.maximumResponseSize)
        else {
            bytes.task.cancel()
            throw VieraError.badResponse
        }
        return (http.statusCode, body)
    }

    /// A redirect could point anywhere: none are followed (a 3xx comes back as its status).
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
        // The completion-handler form: the async one crashes Swift 6.4's SILGen (ObjC thunk).
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
