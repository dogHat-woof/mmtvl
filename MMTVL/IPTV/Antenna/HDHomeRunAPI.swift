import Foundation

// M7j: the tuner's HTTP API (info.hdhomerun.com/info/http_api). Step 2: `discover.json`, the device it describes,
// and the capped, timed fetch every tuner request goes through. Step 3: `lineup.json`, `status.json` and
// `lineup_status.json`. Step 9b: the channel scan's `lineup.post` (L18). DeviceID, DeviceAuth, addresses and URLs are never
// logged, shown or stored on disk (L4, L15).

/// `discover.json`. DeviceID, BaseURL, LineupURL and TunerCount are required; the other keys may be missing or of
/// an unexpected type on other firmware (then nil). `deviceAuth` is a token: never log, show or store it. Its
/// descriptions and mirror show the name, model and tuner count only (security L3).
nonisolated struct HDHomeRunDiscover: Decodable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var friendlyName: String?
    var modelNumber: String?
    var firmwareName: String?
    var firmwareVersion: String?
    var deviceID: String
    var deviceAuth: String?
    var upgradeAvailable: String?
    var baseURL: String
    var lineupURL: String
    var tunerCount: Int

    enum CodingKeys: String, CodingKey {
        case friendlyName = "FriendlyName"
        case modelNumber = "ModelNumber"
        case firmwareName = "FirmwareName"
        case firmwareVersion = "FirmwareVersion"
        case deviceID = "DeviceID"
        case deviceAuth = "DeviceAuth"
        case upgradeAvailable = "UpgradeAvailable"
        case baseURL = "BaseURL"
        case lineupURL = "LineupURL"
        case tunerCount = "TunerCount"
    }

    init(friendlyName: String? = nil, modelNumber: String? = nil, firmwareName: String? = nil,
         firmwareVersion: String? = nil, deviceID: String, deviceAuth: String? = nil, upgradeAvailable: String? = nil,
         baseURL: String, lineupURL: String, tunerCount: Int) {
        self.friendlyName = friendlyName
        self.modelNumber = modelNumber
        self.firmwareName = firmwareName
        self.firmwareVersion = firmwareVersion
        self.deviceID = deviceID
        self.deviceAuth = deviceAuth
        self.upgradeAvailable = upgradeAvailable
        self.baseURL = baseURL
        self.lineupURL = lineupURL
        self.tunerCount = tunerCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friendlyName = Self.text(container, .friendlyName)
        modelNumber = Self.text(container, .modelNumber)
        firmwareName = Self.text(container, .firmwareName)
        firmwareVersion = Self.text(container, .firmwareVersion)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        deviceAuth = Self.text(container, .deviceAuth)
        upgradeAvailable = Self.text(container, .upgradeAvailable)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        lineupURL = try container.decode(String.self, forKey: .lineupURL)
        tunerCount = try container.decode(Int.self, forKey: .tunerCount)
    }

    /// A string, or a number written as one ("20261107" or 20261107); nil when missing or anything else.
    private static func text(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    static func decode(_ data: Data) -> HDHomeRunDiscover? {
        try? JSONDecoder().decode(HDHomeRunDiscover.self, from: data)
    }

    var description: String {
        "HDHomeRunDiscover(name: \(friendlyName ?? "nil"), model: \(modelNumber ?? "nil"), tunerCount: \(tunerCount))"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["friendlyName": friendlyName as Any, "modelNumber": modelNumber as Any,
                                "tunerCount": tunerCount], displayStyle: .struct)
    }
}

/// A tuner that passed L4's checks. Memory only: no file holds a device, so no id or address is on disk. Its
/// descriptions and mirror show the name, model and tuner count only (security L3).
nonisolated struct HDHomeRunDevice: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// DeviceID: never logged or shown.
    var id: String
    /// FriendlyName ("HDHomeRun CONNECT").
    var name: String
    /// ModelNumber ("HDHR4-2US").
    var model: String
    var tunerCount: Int
    var baseURL: URL
    var lineupURL: URL

    /// A lineup entry's stream `URL` (L5): http, without a user name or password, its raw host exactly this
    /// device's BaseURL host (both canonical dotted quads, never percent-encoded: security M1), and any port in
    /// 1…65535 (streams are on 5004) or none, read from the string (step 10: `HDHomeRunDiscovery.writtenPort`, so
    /// `:99999999999999999999` or an empty `:`, which Foundation reads as no port, are refused).
    func isHTTPOnDevice(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", url.user == nil, url.password == nil,
              HDHomeRunDiscovery.writtenPort(of: url) != .invalid,
              let host = HDHomeRunDiscovery.literalHost(of: url),
              let deviceHost = HDHomeRunDiscovery.literalHost(of: baseURL)
        else { return false }
        return host == deviceHost
    }

    /// The LineupURL passes discovery's rule again (L5, security low 2): http on the BaseURL's raw host, port 80 or
    /// none, no query or fragment.
    var hasValidLineupURL: Bool {
        guard let host = HDHomeRunDiscovery.literalHost(of: baseURL) else { return false }
        return HDHomeRunDiscovery.isLineupURL(lineupURL, on: host)
    }

    var description: String { "HDHomeRunDevice(name: \(name), model: \(model), tunerCount: \(tunerCount))" }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["name": name, "model": model, "tunerCount": tunerCount], displayStyle: .struct)
    }
}

// MARK: lineup.json (step 3)

/// One entry of `lineup.json` (or `lineup.json?show=found`). Decoded leniently: `GuideNumber` and `URL` are required
/// (an entry without either is dropped by `decodeLineup`); every other key may be missing or of another type (then
/// nil); `HD`, `Favorite`, `DRM`, `Enabled` and `Subscribed` are an Int (0/1) or a Bool; `Tags` is a comma string
/// ("favorite,drm"), lowercased. `url` is the stream address on the tuner: its descriptions and mirror show the
/// GuideNumber and GuideName only (L15).
nonisolated struct HDHomeRunLineupEntry: Decodable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// "5.1".
    var guideNumber: String
    /// "WAGA-HD"; repeats across the lineup.
    var guideName: String?
    var videoCodec: String?
    var audioCodec: String?
    /// `http://<tuner>:5004/auto/v5.1`. Never logged.
    var url: String
    var hd: Bool?
    /// The tuner's own favorite flag: ignored by MMTVL (L5).
    var favorite: Bool?
    /// Older firmware's `"DRM": 1`.
    var drm: Bool?
    /// `lineup.json?show=found`: `Enabled: 0` is disabled in the tuner's web page.
    var enabled: Bool?
    /// `lineup.json?show=found`: `Subscribed: 0` (cable).
    var subscribed: Bool?
    var tags: [String]
    var signalStrength: Int?
    var signalQuality: Int?

    enum CodingKeys: String, CodingKey {
        case guideNumber = "GuideNumber"
        case guideName = "GuideName"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
        case url = "URL"
        case hd = "HD"
        case favorite = "Favorite"
        case drm = "DRM"
        case enabled = "Enabled"
        case subscribed = "Subscribed"
        case tags = "Tags"
        case signalStrength = "SignalStrength"
        case signalQuality = "SignalQuality"
    }

    init(guideNumber: String, guideName: String? = nil, videoCodec: String? = nil, audioCodec: String? = nil,
         url: String, hd: Bool? = nil, favorite: Bool? = nil, drm: Bool? = nil, enabled: Bool? = nil,
         subscribed: Bool? = nil, tags: [String] = [], signalStrength: Int? = nil, signalQuality: Int? = nil) {
        self.guideNumber = guideNumber
        self.guideName = guideName
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.url = url
        self.hd = hd
        self.favorite = favorite
        self.drm = drm
        self.enabled = enabled
        self.subscribed = subscribed
        self.tags = tags
        self.signalStrength = signalStrength
        self.signalQuality = signalQuality
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let guideNumber = HDHomeRunJSON.text(container, .guideNumber) else {
            throw DecodingError.keyNotFound(CodingKeys.guideNumber, .init(codingPath: container.codingPath,
                                                                         debugDescription: "No GuideNumber"))
        }
        self.guideNumber = guideNumber
        // Required, and only a string: a URL is never made from a number.
        url = try container.decode(String.self, forKey: .url)
        guideName = HDHomeRunJSON.text(container, .guideName)
        videoCodec = HDHomeRunJSON.text(container, .videoCodec)
        audioCodec = HDHomeRunJSON.text(container, .audioCodec)
        hd = HDHomeRunJSON.flag(container, .hd)
        favorite = HDHomeRunJSON.flag(container, .favorite)
        drm = HDHomeRunJSON.flag(container, .drm)
        enabled = HDHomeRunJSON.flag(container, .enabled)
        subscribed = HDHomeRunJSON.flag(container, .subscribed)
        tags = (HDHomeRunJSON.text(container, .tags) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        signalStrength = try? container.decodeIfPresent(Int.self, forKey: .signalStrength)
        signalQuality = try? container.decodeIfPresent(Int.self, forKey: .signalQuality)
    }

    /// Copy protected (L5): `Tags` contains `drm`, or `DRM` is 1/true.
    var isDRM: Bool { drm == true || tags.contains("drm") }

    /// Not disabled in the tuner's web page and not unsubscribed (L5: left out without counting as protected).
    var isAvailable: Bool { enabled != false && subscribed != false }

    /// The lineup's entries; an entry that doesn't decode (no GuideNumber or URL) is dropped. nil when the body
    /// isn't a JSON array.
    static func decodeLineup(_ data: Data) -> [HDHomeRunLineupEntry]? {
        (try? JSONDecoder().decode([HDHomeRunLossy<HDHomeRunLineupEntry>].self, from: data))?.compactMap(\.value)
    }

    /// The description's GuideNumber is cut to this many scalars.
    static let maximumDescribedNumberLength = 16

    /// GuideNumber and GuideName as descriptions show them: control and format characters removed, capped
    /// (security low 4), so a hostile lineup can't put bidi overrides or line breaks into a log line.
    private var describedNumber: String {
        String(String.UnicodeScalarView(HDHomeRunDiscovery.displayText(guideNumber).unicodeScalars
            .prefix(Self.maximumDescribedNumberLength)))
    }

    private var describedName: String { guideName.map { HDHomeRunDiscovery.displayText($0) } ?? "nil" }

    var description: String { "HDHomeRunLineupEntry(\(describedNumber) \(describedName))" }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["guideNumber": describedNumber, "guideName": describedName], displayStyle: .struct)
    }
}

// MARK: status.json, lineup_status.json (step 3)

/// One tuner of `status.json`: `{"Resource":"tuner0"}` when idle; a tuner in use adds `VctNumber`, `VctName`,
/// `Frequency`, the signal percentages, `TargetIP` and `NetworkRate`. Only the resource name and whether it's busy
/// are kept: `TargetIP` (a LAN address) is never decoded, stored or logged (L15).
nonisolated struct HDHomeRunTunerStatus: Decodable, Equatable, Sendable {
    /// "tuner0".
    var resource: String?
    /// Busy when the object has any key besides `Resource`.
    var isBusy: Bool

    init(resource: String?, isBusy: Bool) {
        self.resource = resource
        self.isBusy = isBusy
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: HDHomeRunJSON.AnyKey.self)
        resource = try? container.decodeIfPresent(String.self, forKey: HDHomeRunJSON.AnyKey("Resource"))
        isBusy = container.allKeys.contains { $0.stringValue != "Resource" }
    }

    /// `status.json`'s tuners; nil when the body isn't a JSON array of objects.
    static func decode(_ data: Data) -> [HDHomeRunTunerStatus]? {
        try? JSONDecoder().decode([HDHomeRunTunerStatus].self, from: data)
    }

    /// How many of `tuners` are busy.
    static func busyCount(_ tuners: [HDHomeRunTunerStatus]) -> Int {
        tuners.count(where: \.isBusy)
    }
}

/// `lineup_status.json`. Idle: `{"ScanInProgress":0,"ScanPossible":1,"Source":"Antenna","SourceList":[…]}`; during
/// a scan: `{"ScanInProgress":1,"Progress":45,"Found":120}` (the *Channel scan* research). `ScanInProgress` and
/// `ScanPossible` are an Int or a Bool (missing: not scanning, unknown); `Progress` is clamped to 0…100, `Found` to
/// 0…`maximumFound`; `SourceList` keeps its strings only, at most `maximumSources` (M7j L18, step 9b).
nonisolated struct HDHomeRunLineupStatus: Decodable, Equatable, Sendable {
    /// More `SourceList` entries than this are ignored.
    static let maximumSources = 16
    /// `Found` is clamped to this (step 9b security M1: a hostile Int.max must not overflow the sum over devices).
    static let maximumFound = 100_000

    var scanInProgress: Bool
    /// Percent done, during a scan.
    var progress: Int?
    /// Programmes found so far, during a scan.
    var found: Int?
    /// Whether a scan can start now; nil when the tuner doesn't say.
    var scanPossible: Bool?
    /// The source a scan runs on ("Antenna").
    var source: String?
    /// The sources the tuner offers (`["Antenna","Cable"]`).
    var sourceList: [String]

    enum CodingKeys: String, CodingKey {
        case scanInProgress = "ScanInProgress"
        case progress = "Progress"
        case found = "Found"
        case scanPossible = "ScanPossible"
        case source = "Source"
        case sourceList = "SourceList"
    }

    init(scanInProgress: Bool, progress: Int? = nil, found: Int? = nil, scanPossible: Bool? = nil,
         source: String? = nil, sourceList: [String] = []) {
        self.scanInProgress = scanInProgress
        self.progress = progress
        self.found = found
        self.scanPossible = scanPossible
        self.source = source
        self.sourceList = sourceList
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanInProgress = HDHomeRunJSON.flag(container, .scanInProgress) ?? false
        progress = (try? container.decodeIfPresent(Int.self, forKey: .progress)).flatMap { $0 }.map { min(max($0, 0), 100) }
        found = (try? container.decodeIfPresent(Int.self, forKey: .found)).flatMap { $0 }.map { min(max($0, 0), Self.maximumFound) }
        scanPossible = HDHomeRunJSON.flag(container, .scanPossible)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        let list = (try? container.decodeIfPresent([HDHomeRunLossy<String>].self, forKey: .sourceList)) ?? nil
        sourceList = Array((list ?? []).compactMap(\.value).prefix(Self.maximumSources))
    }

    /// nil when the body isn't a JSON object.
    static func decode(_ data: Data) -> HDHomeRunLineupStatus? {
        try? JSONDecoder().decode(HDHomeRunLineupStatus.self, from: data)
    }
}

/// M7j L18: the two `lineup.post` requests MMTVL ever sends, `scan=start&source=<Source>` and `scan=abort`, on the
/// device's own BaseURL (http, its raw host a canonical IPv4 literal, port 80 or none, nothing after the origin).
/// No other `lineup.post` parameter is ever built, so MMTVL can't change the tuner's favorites, disabled channels or
/// source.
nonisolated enum HDHomeRunScan {
    static let maximumSourceLength = 32

    /// `^[A-Za-z0-9 ]{1,32}$`, ASCII only.
    static func isValidSource(_ source: String) -> Bool {
        let bytes = Array(source.utf8)
        guard (1...maximumSourceLength).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x20
        }
    }

    /// The source a scan may run on: the status's current `Source`, when it's in its `SourceList` and valid. MMTVL
    /// never picks another one (Cable).
    static func source(of status: HDHomeRunLineupStatus) -> String? {
        guard let source = status.source, isValidSource(source), status.sourceList.contains(source) else { return nil }
        return source
    }

    /// `POST /lineup.post?scan=start&source=<Source>` (a space percent-encoded), from the device's current status.
    static func startURL(device: HDHomeRunDevice, status: HDHomeRunLineupStatus) -> URL? {
        source(of: status).flatMap { startURL(device: device, source: $0) }
    }

    /// `POST /lineup.post?scan=start&source=<source>`; nil when `source` isn't valid or the BaseURL isn't an origin.
    static func startURL(device: HDHomeRunDevice, source: String) -> URL? {
        guard isValidSource(source) else { return nil }
        return lineupPostURL(device: device,
                             query: "scan=start&source=" + source.replacingOccurrences(of: " ", with: "%20"))
    }

    /// `POST /lineup.post?scan=abort`.
    static func abortURL(device: HDHomeRunDevice) -> URL? {
        lineupPostURL(device: device, query: "scan=abort")
    }

    private static func lineupPostURL(device: HDHomeRunDevice, query: String) -> URL? {
        guard let host = HDHomeRunDiscovery.literalHost(of: device.baseURL),
              HDHomeRunDiscovery.isOrigin(device.baseURL, of: host)
        else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = device.baseURL.port
        components.path = "/lineup.post"
        components.percentEncodedQuery = query
        return components.url
    }
}

/// Lenient value readers shared by the tuner's JSON models.
nonisolated enum HDHomeRunJSON {
    /// A string, or an integer written as one; nil when missing or anything else.
    static func text<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    /// A Bool, or an integer (0 = false, anything else = true); nil when missing or anything else.
    static func flag<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        return nil
    }

    /// Any key, for objects whose keys are read as a set (`status.json`).
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// An array element that may fail to decode: `value` is nil then, and the rest of the array still decodes.
nonisolated struct HDHomeRunLossy<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Every request to a tuner: http to a LAN host only, an ephemeral session (no cookies, cache or proxy), no
/// redirects, a size cap and a total time limit. `fetch` is injected for tests.
nonisolated struct HDHomeRunHTTP: Sendable {
    typealias Fetch = @Sendable (_ url: URL, _ maxBytes: Int, _ timeout: TimeInterval) async -> Data?
    /// M7j L18: a POST with an empty body; the answer's HTTP status, nil when nothing answered (or it wasn't sent).
    typealias Post = @Sendable (_ url: URL, _ timeout: TimeInterval) async -> Int?

    /// `discover.json`, `status.json`, `lineup_status.json`.
    static let smallMaxBytes = 16 * 1024
    static let lineupMaxBytes = 1024 * 1024
    static let timeout: TimeInterval = 2
    static let lineupTimeout: TimeInterval = 5
    /// M7j L18: `lineup.post`.
    static let postTimeout: TimeInterval = 5

    var fetch: Fetch
    /// M7j L18: `lineup.post` only (`startScan`, `abortScan`). `noPost` unless the caller passes `livePost`.
    var post: Post

    init(fetch: @escaping Fetch = HDHomeRunHTTP.live, post: @escaping Post = HDHomeRunHTTP.noPost) {
        self.fetch = fetch
        self.post = post
    }

    /// `discover.json` at `url`, decoded; nil when the fetch fails or it doesn't decode.
    func discover(_ url: URL) async -> HDHomeRunDiscover? {
        guard let data = await fetch(url, Self.smallMaxBytes, Self.timeout) else { return nil }
        return HDHomeRunDiscover.decode(data)
    }

    /// The device's `lineup.json` (its LineupURL, which must pass `hasValidLineupURL`, L5), decoded; nil when
    /// that check, the fetch or the decoding fails.
    func lineup(of device: HDHomeRunDevice) async -> [HDHomeRunLineupEntry]? {
        guard device.hasValidLineupURL,
              let data = await fetch(device.lineupURL, Self.lineupMaxBytes, Self.lineupTimeout) else { return nil }
        return HDHomeRunLineupEntry.decodeLineup(data)
    }

    /// M7j L10: the device's DeviceAuth, read fresh from its `discover.json` (at its BaseURL, 16 KB, 2 s) when that
    /// answers for the same DeviceID; nil otherwise. A token: the caller holds it in a local only and never logs,
    /// stores or shows it. `AntennaGuide.url` checks its characters and length.
    func deviceAuth(of device: HDHomeRunDevice) async -> String? {
        guard let discover = await discover(device.baseURL.appending(path: "discover.json")),
              discover.deviceID.caseInsensitiveCompare(device.id) == .orderedSame
        else { return nil }
        return discover.deviceAuth
    }

    /// The device's `status.json` (takes no tuner), decoded; nil when the fetch or the decoding fails.
    func tunerStatus(of device: HDHomeRunDevice) async -> [HDHomeRunTunerStatus]? {
        guard let data = await fetch(device.baseURL.appending(path: "status.json"), Self.smallMaxBytes, Self.timeout)
        else { return nil }
        return HDHomeRunTunerStatus.decode(data)
    }

    /// The device's `lineup_status.json`, decoded; nil when the fetch or the decoding fails.
    func lineupStatus(of device: HDHomeRunDevice) async -> HDHomeRunLineupStatus? {
        guard let data = await fetch(device.baseURL.appending(path: "lineup_status.json"), Self.smallMaxBytes,
                                     Self.timeout)
        else { return nil }
        return HDHomeRunLineupStatus.decode(data)
    }

    /// M7j L18: starts a channel scan on the device's current source (`HDHomeRunScan.startURL(device:status:)`, from
    /// `status`, its fresh `lineup_status.json`). The HTTP status (200 = accepted); nil when the source isn't valid,
    /// or nothing answered.
    func startScan(on device: HDHomeRunDevice, status: HDHomeRunLineupStatus) async -> Int? {
        guard let url = HDHomeRunScan.startURL(device: device, status: status) else { return nil }
        return await post(url, Self.postTimeout)
    }

    /// M7j L18: stops the device's channel scan. The HTTP status; nil when nothing answered.
    func abortScan(on device: HDHomeRunDevice) async -> Int? {
        guard let url = HDHomeRunScan.abortURL(device: device) else { return nil }
        return await post(url, Self.postTimeout)
    }

    // MARK: Live POST (M7j L18)

    /// Sends nothing: what every `HDHomeRunHTTP` posts with unless `livePost` is passed in (only `AppDelegate` does),
    /// so no test and no other caller can start or stop a scan on a real tuner.
    static let noPost: Post = { _, _ in nil }

    /// `livePost` as a `Post`.
    static let livePost: Post = { url, timeout in
        await livePost(url, timeout: timeout, session: session)
    }

    /// POST `url` with an empty body: `isAllowed` (http, a private IPv4 literal), no redirects, within `timeout`
    /// seconds. The answer's status code; its body is read up to `smallMaxBytes` and ignored. nil when the URL isn't
    /// allowed or nothing answered in time.
    static func livePost(_ url: URL, timeout: TimeInterval, session: URLSession) async -> Int? {
        guard isAllowed(url) else { return nil }
        return await withTaskGroup(of: Int?.self) { group in
            group.addTask { await postOnce(url, timeout: timeout, session: session) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func postOnce(_ url: URL, timeout: TimeInterval, session: URLSession) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectBlocker())
            guard let http = response as? HTTPURLResponse else {
                bytes.task.cancel()
                return nil
            }
            // The body is never used: read a little (so the connection ends cleanly), then stop.
            var read: Data?
            if response.expectedContentLength <= Int64(smallMaxBytes) {
                read = try? await DeviceDescriptionFetcher.collect(bytes, limit: smallMaxBytes)
            }
            if read == nil { bytes.task.cancel() }
            return http.statusCode
        } catch {
            return nil
        }
    }

    // MARK: Live fetch

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = lineupTimeout
        configuration.timeoutIntervalForResource = lineupTimeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.connectionProxyDictionary = [:]   // never through a system proxy
        return URLSession(configuration: configuration)
    }()

    /// The URL MMTVL may fetch from a tuner: http, no user name, the host a private (or link-local) IPv4 literal.
    /// Never a name: the `hdhomerun.local` fallback resolves it itself and asks by IP (security M2).
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", url.user == nil, url.password == nil,
              let canonical = HDHomeRunDiscovery.literalHost(of: url),   // the raw host (security M1)
              let bytes = WakeOnLAN.ipv4(canonical) else { return false }
        return LANAddress.isPrivate(ipv4: bytes)
    }

    /// GET `url`: status 200 and at most `maxBytes`, all within `timeout` seconds; nil otherwise.
    static func liveFetch(_ url: URL, maxBytes: Int, timeout: TimeInterval) async -> Data? {
        await liveFetch(url, maxBytes: maxBytes, timeout: timeout, session: session)
    }

    /// `liveFetch` as a `Fetch`.
    static let live: Fetch = { url, maxBytes, timeout in
        await liveFetch(url, maxBytes: maxBytes, timeout: timeout)
    }

    static func liveFetch(_ url: URL, maxBytes: Int, timeout: TimeInterval, session: URLSession) async -> Data? {
        guard isAllowed(url) else { return nil }
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask { await get(url, maxBytes: maxBytes, timeout: timeout, session: session) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func get(_ url: URL, maxBytes: Int, timeout: TimeInterval, session: URLSession) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectBlocker())
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= Int64(maxBytes)
            else {
                bytes.task.cancel()
                return nil
            }
            let data = try await DeviceDescriptionFetcher.collect(bytes, limit: maxBytes)
            if data == nil { bytes.task.cancel() }
            return data
        } catch {
            return nil
        }
    }

    /// A redirect could point anywhere: none are followed.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
        // The completion-handler form, like `DeviceDescriptionFetcher`'s (the async one crashes Swift 6.4's SILGen).
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
