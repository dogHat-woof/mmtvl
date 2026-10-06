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
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
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

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

/// A library with an in-memory guide store and sources, and its files in a temporary directory.
func makeLibrary(playlist: URL? = nil, guides: [URL] = [],
                 texts: [URL: String] = [IPTVFixtures.playlistURL: IPTVFixtures.playlist],
                 files: [URL: String]? = nil,
                 state: IPTVState? = nil, overrides: [String: String]? = nil, preferences: ChannelPreferences? = nil,
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
    let library = IPTVLibrary(sources: sources, store: store, network: network, stateFile: stateFile,
                              overridesFile: overridesFile, preferencesFile: preferencesFile, now: { clock.now })
    return LibraryFixture(library: library, network: networkState, sources: sources, store: store, clock: clock,
                          directory: directory, stateFile: stateFile, overridesFile: overridesFile,
                          preferencesFile: preferencesFile)
}
