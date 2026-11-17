import Foundation
@testable import MMTVL

enum IPTVFixtures {
    static let playlistURL = URL(string: "https://provider.example/app2/token")!
    static let otherPlaylistURL = URL(string: "https://provider.example/app2/other")!
    static let playlistGuideURL = URL(string: "https://guide.example/from-playlist.xml")!
    static let customGuideURL = URL(string: "https://guide.example/custom.xml")!
    static let secondGuideURL = URL(string: "https://guide.example/second.xml.gz")!

    static func streamURL(_ n: Int) -> URL { URL(string: "https://cdn.example/t/channel/\(n)/chunks.m3u8")! }

    /// Three live channels and two games, in two groups.
    static let playlist = """
    #EXTM3U
    #EXTINF:0 tvg-id="nflnetwork.us" tvg-name="NFL Network" group-title="Live Channels",NFL Network
    \(streamURL(1))
    #EXTINF:0 tvg-id="nbatv.us" tvg-name="NBA TV" group-title="Live Channels",NBA TV
    \(streamURL(2))
    #EXTINF:0 tvg-id="" tvg-name="Red Zone" group-title="Live Channels",Red Zone
    \(streamURL(3))
    #EXTINF:0 tvg-type="movie" tvg-id="Lakers @ Celtics" group-title="NBA Games",Lakers @ Celtics
    \(streamURL(4))
    #EXTINF:0 tvg-type="movie" tvg-id="Knicks @ Heat" group-title="NBA Games",Knicks @ Heat
    \(streamURL(5))
    """

    static let playlistWithGuide = playlist.replacingOccurrences(
        of: "#EXTM3U", with: "#EXTM3U url-tvg=\"\(playlistGuideURL)\"")

    /// XMLTV timestamp for `date`.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date) + " +0000"
    }

    /// NFL Network matches by name, NBA TV by id; "NFL.RedZone.HD.us2" only through an override.
    /// Each channel gets hour-long programmes from now − 1 h to now + 3 h.
    static func guide(now: Date) -> String {
        xmltv(now: now, channels: [("NFL.Network.HD.us2", "NFL Network HD"), ("nbatv.us", "NBA TV"),
                                   ("NFL.RedZone.HD.us2", "NFL RedZone"), ("Unrelated.us2", "Unrelated")])
    }

    /// M6b: Red Zone matches here by name, NBA TV by name (custom has it by id). Titles "<name> alt <hour>".
    static func secondGuide(now: Date) -> String {
        xmltv(now: now, channels: [("RedZone.Alt.us", "Red Zone"), ("NBA.TV.Alt.us", "NBA TV")], titleSuffix: " alt")
    }

    private static func xmltv(now: Date, channels: [(String, String)], titleSuffix: String = "") -> String {
        var xml = "<?xml version=\"1.0\"?>\n<!DOCTYPE tv SYSTEM \"xmltv.dtd\">\n<tv>\n"
        for (id, name) in channels {
            xml += "<channel id=\"\(id)\"><display-name>\(name)</display-name></channel>\n"
        }
        let base = now.addingTimeInterval(-3600)
        for (id, name) in channels {
            for hour in 0..<4 {
                let start = base.addingTimeInterval(Double(hour) * 3600)
                xml += "<programme start=\"\(stamp(start))\" stop=\"\(stamp(start.addingTimeInterval(3600)))\" channel=\"\(id)\">"
                xml += "<title>\(name)\(titleSuffix) \(hour)</title></programme>\n"
            }
        }
        return xml + "</tv>\n"
    }
}

/// What the fake network serves and how often it was asked.
nonisolated final class FakeNetworkState: @unchecked Sendable {
    private let lock = NSLock()
    private var _texts: [URL: String]
    private var _files: [URL: String]
    private var _errors: [URL: any Error] = [:]
    private var _fetchCount = 0
    private var _downloadCount = 0

    init(texts: [URL: String], files: [URL: String]) {
        _texts = texts
        _files = files
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var fetchCount: Int { locked { _fetchCount } }
    var downloadCount: Int { locked { _downloadCount } }
    func setText(_ text: String?, for url: URL) { locked { _texts[url] = text } }
    func setFile(_ text: String?, for url: URL) { locked { _files[url] = text } }
    func setError(_ error: (any Error)?, for url: URL) { locked { _errors[url] = error } }

    fileprivate func text(_ url: URL) throws -> String {
        let (text, error) = locked { () -> (String?, (any Error)?) in
            _fetchCount += 1
            return (_texts[url], _errors[url])
        }
        if let error { throw error }
        guard let text else { throw IPTVNetworkError.http(404) }
        return text
    }

    fileprivate func file(_ url: URL) throws -> URL {
        let (text, error) = locked { () -> (String?, (any Error)?) in
            _downloadCount += 1
            return (_files[url], _errors[url])
        }
        if let error { throw error }
        guard let text else { throw IPTVNetworkError.http(404) }
        let destination = FileManager.default.temporaryDirectory.appending(path: "fake-download-\(UUID().uuidString)")
        try Data(text.utf8).write(to: destination)
        return destination
    }
}

extension IPTVNetwork {
    static func fake(_ state: FakeNetworkState) -> IPTVNetwork {
        IPTVNetwork(fetchText: { try state.text($0) }, download: { try state.file($0) })
    }

    static func fake(texts: [URL: String] = [:], files: [URL: String] = [:]) -> (IPTVNetwork, FakeNetworkState) {
        let state = FakeNetworkState(texts: texts, files: files)
        return (.fake(state), state)
    }
}

/// A mutable clock for refresh-policy tests.
final class TestClock {
    var now: Date
    /// M7j L18 (security L4): the elapsed-time clock the channel scan's limit uses; `advance` moves both.
    var instant = ContinuousClock.now
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        instant = instant.advanced(by: .seconds(seconds))
    }
}

struct LibraryFixture {
    let library: IPTVLibrary
    let network: FakeNetworkState
    let sources: IPTVSourceStore
    let store: EPGStore
    let clock: TestClock
    let directory: URL
    let stateFile: JSONConfigFile<IPTVState>
    let overridesFile: JSONConfigFile<[String: String]>
    let preferencesFile: JSONConfigFile<ChannelPreferences>
    /// M7j: the fake tuner behind `library.antenna`, when one was asked for.
    var tuner: FakeTuner? = nil

    /// M7n L1: also ends a launch/wake retry loop left waiting.
    func cleanUp() {
        library.channelRetryTask?.cancel()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// M7n L1: the retry loop's wait for tests that don't drive it: parked until cancelled (`LibraryFixture.cleanUp`), so
/// a launch with no tuner or a failed playlist never tries again behind a test's back.
let parkedRetrySleep: @MainActor (Duration) async -> Void = { _ in try? await Task.sleep(for: .seconds(86_400)) }

/// A library with an in-memory guide store and sources, and its files in a temporary directory.
/// M7n L1: `retryWait` drives the launch/wake retry loop's waits on the test clock (it should advance it by the
/// wait); nil parks the loop (`parkedRetrySleep`).
func makeLibrary(playlist: URL? = nil, guides: [URL] = [],
                 texts: [URL: String] = [IPTVFixtures.playlistURL: IPTVFixtures.playlist],
                 files: [URL: String]? = nil,
                 state: IPTVState? = nil, overrides: [String: String]? = nil, preferences: ChannelPreferences? = nil,
                 tuner: FakeTuner? = nil, antenna: AntennaSource? = nil,
                 retryWait: (@MainActor (TestClock, Duration) async -> Void)? = nil,
                 now: Date = Date(timeIntervalSince1970: 1_791_200_000)) throws -> LibraryFixture {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "IPTVLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let stateFile = JSONConfigFile(url: directory.appending(path: IPTVState.fileName), defaultValue: IPTVState())
    let overridesFile = JSONConfigFile(url: directory.appending(path: IPTVState.overridesFileName), defaultValue: [String: String]())
    if let state { try stateFile.save(state) }
    let preferencesFile = JSONConfigFile(url: directory.appending(path: ChannelPreferences.fileName),
                                         defaultValue: ChannelPreferences())
    if let overrides { try overridesFile.save(overrides) }
    if let preferences { try preferencesFile.save(preferences) }

    let clock = TestClock(now)
    let guideText = IPTVFixtures.guide(now: now)
    let (network, networkState) = IPTVNetwork.fake(
        texts: texts,
        files: files ?? [IPTVFixtures.playlistGuideURL: guideText, IPTVFixtures.customGuideURL: guideText,
                         IPTVFixtures.secondGuideURL: IPTVFixtures.secondGuide(now: now)])
    let sources = IPTVSourceStore.inMemory(playlist: playlist, guides: guides)
    let store = try EPGStore.inMemory()
    // M7j: without a fake tuner the antenna is off (the default), so no test reaches the network.
    // `antenna`: a source the test built itself (it wins over `tuner`).
    // M7j L18: a scan's polling waits on the test clock (each wait moves it on), never in real time.
    let antenna = antenna ?? tuner.map {
        AntennaSource.fake($0, now: { clock.now }, sleep: { clock.advance(TimeInterval($0.components.seconds)) },
                           scanClock: { clock.instant })
    } ?? AntennaSource()
    var retrySleep = parkedRetrySleep
    if let retryWait { retrySleep = { @MainActor delay in await retryWait(clock, delay) } }
    let library = IPTVLibrary(sources: sources, store: store, network: network, stateFile: stateFile,
                              overridesFile: overridesFile, preferencesFile: preferencesFile, antenna: antenna,
                              now: { clock.now },
                              retrySleep: retrySleep,
                              retryClock: { clock.instant })
    return LibraryFixture(library: library, network: networkState, sources: sources, store: store, clock: clock,
                          directory: directory, stateFile: stateFile, overridesFile: overridesFile,
                          preferencesFile: preferencesFile, tuner: tuner)
}

// MARK: - M7j: a fake HDHomeRun tuner (fake LAN addresses and ids only)

nonisolated enum AntennaFixtures {
    static let host = "10.0.0.9"
    static let deviceID = "1234ABCD"

    static func device(id: String = deviceID, host: String = host, tuners: Int = 2) -> HDHomeRunDevice {
        HDHomeRunDevice(id: id, name: "HDHomeRun CONNECT", model: "HDHR4-2US", tunerCount: tuners,
                        baseURL: URL(string: "http://\(host)")!, lineupURL: URL(string: "http://\(host)/lineup.json")!)
    }

    static func streamURL(_ number: String, host: String = host) -> URL {
        URL(string: "http://\(host):5004/auto/v\(number)")!
    }

    /// `lineup.json` for `(GuideNumber, GuideName)` pairs on `host`.
    static func lineupJSON(_ channels: [(String, String)], host: String = host) -> String {
        "[" + channels.map { number, name in
            #"{"GuideNumber":"\#(number)","GuideName":"\#(name)","VideoCodec":"MPEG2","AudioCodec":"AC3","HD":1,"# +
                #""URL":"\#(streamURL(number, host: host))"}"#
        }.joined(separator: ",") + "]"
    }

    static let channels = [("2.1", "WSB-HD"), ("5.1", "WAGA-HD"), ("11.1", "WXIA-HD")]

    /// M7j L9: `status.json` with `busy` of `tuners` tuners in use (fake values, no `TargetIP`).
    static func statusJSON(busy: Int, of tuners: Int = 2) -> String {
        "[" + (0..<tuners).map { index in
            index < busy
                ? #"{"Resource":"tuner\#(index)","VctNumber":"5.1","VctName":"WAGA-HD","Frequency":521000000,"SignalStrengthPercent":100}"#
                : #"{"Resource":"tuner\#(index)"}"#
        }.joined(separator: ",") + "]"
    }

    /// M7j L9: `lineup_status.json`.
    static func lineupStatusJSON(scanning: Bool) -> String {
        #"{"ScanInProgress":\#(scanning ? 1 : 0),"ScanPossible":1,"Source":"Antenna","SourceList":["Antenna","Cable"]}"#
    }

    /// M7j L18: `lineup_status.json` while idle, with `ScanPossible`.
    static func idleLineupStatusJSON(scanPossible: Bool = true) -> String {
        #"{"ScanInProgress":0,"ScanPossible":\#(scanPossible ? 1 : 0),"Source":"Antenna","SourceList":["Antenna","Cable"]}"#
    }

    /// M7j L18: `lineup_status.json` during a scan (`found` as written, so a test can send Int.max).
    static func scanningLineupStatusJSON(progress: Int, found: Int) -> String {
        #"{"ScanInProgress":1,"Progress":\#(progress),"Found":\#(found)}"#
    }

    /// M7j L10: a made-up DeviceAuth (base64 characters, with `+`, `/` and `=` to be percent-encoded). Never a real one.
    static let fakeDeviceAuth = "FAKEauth+0123/abcdXYZ="

    /// M7j L10: `discover.json` for `device`, with `auth` as its DeviceAuth (none when nil).
    static func discoverJSON(device: HDHomeRunDevice = device(), auth: String? = fakeDeviceAuth) -> String {
        let host = device.baseURL.host() ?? host
        let authPart = auth.map { #""DeviceAuth":"\#($0)","# } ?? ""
        return #"{"FriendlyName":"HDHomeRun CONNECT","ModelNumber":"HDHR4-2US","DeviceID":"\#(device.id)",\#(authPart)"#
            + #""BaseURL":"http://\#(host):80","LineupURL":"http://\#(host)/lineup.json","TunerCount":\#(device.tunerCount)}"#
    }

    /// M7j L10: SiliconDust's guide URL for the fake DeviceAuth.
    static var guideURL: URL { AntennaGuide.url(deviceAuths: [fakeDeviceAuth])! }

    /// M7j L10: an XMLTV shaped like SiliconDust's (station ids, the bare GuideNumber among the display-names) for
    /// 2.1, 5.1 and 11.1, plus a playlist channel's id (`nbatv.us`). Hour-long programmes "<call sign> <n>" from
    /// now − 1 h to now + 3 h; `extra` is appended inside `<tv>` (more programmes).
    @MainActor static func guideXML(now: Date, extra: String = "") -> String {
        let channels = [("US10001.hdhomerun.com", ["WSBDT", "2.1 WSBDT", "2.1 WSB-HD", "2.1", "WSB-HD", "ABC"]),
                        ("US10002.hdhomerun.com", ["WAGADT", "5.1 WAGADT", "5.1 WAGA-HD", "5.1", "WAGA-HD", "FOX"]),
                        ("US10003.hdhomerun.com", ["WXIADT", "11.1 WXIADT", "11.1 WXIA-TV", "11.1", "WXIA-TV", "NBC"]),
                        ("nbatv.us", ["NBA TV"])]
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<tv source-info-name=\"HDHomeRun\">\n"
        for (id, names) in channels {
            xml += "<channel id=\"\(id)\">" + names.map { "<display-name>\($0)</display-name>" }.joined()
                + "<lcn>\(names[3 % names.count])</lcn></channel>\n"
        }
        let base = now.addingTimeInterval(-3600)
        for (id, names) in channels {
            for hour in 0..<4 {
                let start = base.addingTimeInterval(Double(hour) * 3600)
                xml += "<programme start=\"\(IPTVFixtures.stamp(start))\" stop=\"\(IPTVFixtures.stamp(start.addingTimeInterval(3600)))\" channel=\"\(id)\">"
                xml += "<title>\(names[0]) \(hour)</title></programme>\n"
            }
        }
        return xml + extra + "</tv>\n"
    }

    /// `channels` as Live TV channels from `device()`, numbered from `firstNumber`.
    static func liveChannels(firstNumber: Int = 1) -> [Channel] {
        let entries = channels.map {
            HDHomeRunLineupEntry(guideNumber: $0.0, guideName: $0.1, url: streamURL($0.0).absoluteString)
        }
        return AntennaLineup.channels(devices: [(device(), entries)], firstNumber: firstNumber).channels
    }
}

/// What the fake tuner answers: the devices a search finds, and each device's lineup (nil = no answer); M7j L9:
/// `status.json` and `lineup_status.json` (none unless set). Counts the searches, lineup and status fetches.
nonisolated final class FakeTuner: @unchecked Sendable {
    private let lock = NSLock()
    private var _devices: [HDHomeRunDevice]
    private var _lineups: [URL: String]
    private var _searchCount = 0
    private var _lineupFetchCount = 0
    private var _answers: [URL: String] = [:]
    private var _statusFetchCount = 0
    private var _discoverFetchCount = 0

    init(devices: [HDHomeRunDevice] = [AntennaFixtures.device()],
         lineups: [URL: String]? = nil) {
        _devices = devices
        _lineups = lineups ?? Dictionary(uniqueKeysWithValues: devices.map {
            ($0.lineupURL, AntennaFixtures.lineupJSON(AntennaFixtures.channels,
                                                      host: $0.baseURL.host() ?? AntennaFixtures.host))
        })
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var searchCount: Int { locked { _searchCount } }
    var lineupFetchCount: Int { locked { _lineupFetchCount } }
    func setDevices(_ devices: [HDHomeRunDevice]) { locked { _devices = devices } }
    func setLineup(_ json: String?, for device: HDHomeRunDevice) { locked { _lineups[device.lineupURL] = json } }
    var statusFetchCount: Int { locked { _statusFetchCount } }
    func setStatus(_ json: String?, for device: HDHomeRunDevice = AntennaFixtures.device()) {
        locked { _answers[device.baseURL.appending(path: "status.json")] = json }
    }
    func setLineupStatus(_ json: String?, for device: HDHomeRunDevice = AntennaFixtures.device()) {
        locked { _answers[device.baseURL.appending(path: "lineup_status.json")] = json }
    }
    /// M7j L10: `discover.json` (the DeviceAuth for the guide).
    func setDiscover(_ json: String?, for device: HDHomeRunDevice = AntennaFixtures.device()) {
        locked { _answers[device.baseURL.appending(path: "discover.json")] = json }
    }
    var discoverFetchCount: Int { locked { _discoverFetchCount } }

    // M7j L18: the channel scan. Never a real tuner: `post` only records.
    private var _lineupStatusSequences: [URL: [String]] = [:]
    private var _lineupStatusFetchCount = 0
    private var _posts: [String] = []
    private var _postStatus: Int? = 200
    private var _lineupsAfterScan: [URL: String] = [:]

    /// `lineup_status.json` answers in turn, one per fetch; the last one repeats.
    func setLineupStatusSequence(_ jsons: [String], for device: HDHomeRunDevice = AntennaFixtures.device()) {
        locked { _lineupStatusSequences[device.baseURL.appending(path: "lineup_status.json")] = jsons }
    }
    var lineupStatusFetchCount: Int { locked { _lineupStatusFetchCount } }
    /// Every POST's URL, in order.
    var posts: [String] { locked { _posts } }
    /// What a POST answers (nil: no answer).
    func setPostStatus(_ status: Int?) { locked { _postStatus = status } }
    /// The lineup `device` serves once it accepted `scan=start`.
    func setLineupAfterScan(_ json: String, for device: HDHomeRunDevice = AntennaFixtures.device()) {
        locked { _lineupsAfterScan[device.lineupURL] = json }
    }

    func post(_ url: URL) -> Int? {
        locked {
            _posts.append(url.absoluteString)
            if _postStatus == 200, url.query()?.hasPrefix("scan=start") == true {
                for (lineupURL, json) in _lineupsAfterScan where lineupURL.host() == url.host() {
                    _lineups[lineupURL] = json
                }
            }
            return _postStatus
        }
    }

    func search() -> [HDHomeRunDevice] {
        locked {
            _searchCount += 1
            return _devices
        }
    }

    func fetch(_ url: URL) -> Data? {
        locked {
            if url.lastPathComponent == "lineup.json" { _lineupFetchCount += 1 }
            if url.lastPathComponent == "status.json" { _statusFetchCount += 1 }
            if url.lastPathComponent == "discover.json" { _discoverFetchCount += 1 }
            if url.lastPathComponent == "lineup_status.json" {
                _lineupStatusFetchCount += 1
                if var sequence = _lineupStatusSequences[url], let first = sequence.first {
                    if sequence.count > 1 {
                        sequence.removeFirst()
                        _lineupStatusSequences[url] = sequence
                    }
                    return Data(first.utf8)
                }
            }
            return (_lineups[url] ?? _answers[url]).map { Data($0.utf8) }
        }
    }
}

extension AntennaSource {
    /// Turned on, finding and asking `tuner`.
    /// L18: POSTs go to the fake tuner only.
    static func fake(_ tuner: FakeTuner, enabled: Bool = true, now: @escaping () -> Date = Date.init,
                     sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                     scanClock: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
                     post: HDHomeRunHTTP.Post? = nil) -> AntennaSource {
        let source = AntennaSource(find: { tuner.search() },
                                   http: HDHomeRunHTTP(fetch: { url, _, _ in tuner.fetch(url) },
                                                       post: post ?? { url, _ in tuner.post(url) }),
                                   now: now, sleep: sleep, scanClock: scanClock)
        source.isEnabled = enabled
        return source
    }
}
