import Foundation
import os

/// Streaming XMLTV parser (D8). `nonisolated` because it runs off main: a MainActor delegate doesn't compile there.
nonisolated final class XMLTVParser: NSObject, XMLParserDelegate {
    struct Result: Sendable {
        var channels: [EPGChannel]
        var programmes: [Programme]
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    /// `wantedIDs` is called once, at the first <programme> (the DTD puts every <channel> first), with the
    /// channels read so far. It returns the lowercased EPG ids to keep programmes for.
    /// Keeps programmes overlapping `window`. Fills a missing stop with the next programme's start on the same
    /// channel, or start + 30 min for the last one. Throws the parser's error when parse() fails.
    static func parse(fileURL: URL, window: DateInterval, wantedIDs: ([EPGChannel]) -> Set<String>) throws -> Result {
        guard let parser = XMLParser(contentsOf: fileURL) else { throw CocoaError(.fileReadUnknown) }
        return try withoutActuallyEscaping(wantedIDs) { wantedIDs in
            let delegate = XMLTVParser(window: window, wantedIDs: wantedIDs)
            parser.delegate = delegate
            parser.shouldResolveExternalEntities = false
            guard parser.parse() else {
                throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
            }
            return delegate.finish()
        }
    }

    // MARK: - State

    private let window: DateInterval
    private let wantedIDsProvider: ([EPGChannel]) -> Set<String>
    private var wanted: Set<String>?
    private var loggedLateChannel = false

    private var channels: [EPGChannel] = []
    /// Kept programmes; a nil stop is filled in `finish()`.
    private var pending: [(programme: Programme, hasStop: Bool)] = []

    private var text = ""
    private var currentChannel: EPGChannel?
    private var currentProgramme: Programme?
    private var programmeHasStop = false
    private var programmeKept = false
    private var onscreenEpisode: String?
    private var nsEpisode: String?
    private var episodeSystem: String?

    private init(window: DateInterval, wantedIDs: @escaping ([EPGChannel]) -> Set<String>) {
        self.window = window
        self.wantedIDsProvider = wantedIDs
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "channel":
            currentChannel = EPGChannel(id: (attributes["id"] ?? "").lowercased(), names: [])
        case "programme":
            startProgramme(attributes)
        case "episode-num":
            episodeSystem = attributes["system"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        if currentProgramme != nil {
            endProgrammeElement(elementName, value: value)
        } else if currentChannel != nil {
            switch elementName {
            case "display-name":
                if !value.isEmpty { currentChannel?.names.append(value) }
            case "channel":
                if let channel = currentChannel, !channel.id.isEmpty {
                    if wanted != nil, !loggedLateChannel {
                        loggedLateChannel = true
                        Self.logger.info("XMLTV has <channel> elements after programmes; not re-matching")
                    }
                    channels.append(channel)
                }
                currentChannel = nil
            default:
                break
            }
        }
    }

    // MARK: - Programmes

    private func startProgramme(_ attributes: [String: String]) {
        if wanted == nil { wanted = wantedIDsProvider(channels) }
        programmeKept = false
        programmeHasStop = false
        onscreenEpisode = nil
        nsEpisode = nil
        guard let channelID = attributes["channel"]?.lowercased(), !channelID.isEmpty,
              wanted?.contains(channelID) == true,
              let startText = attributes["start"], let start = XMLTVDate.parse(startText)
        else {
            // Still track the element so its children aren't read as channel data.
            currentProgramme = Programme(channelID: "", start: .distantPast, stop: .distantPast, title: "")
            return
        }
        let stop = attributes["stop"].flatMap(XMLTVDate.parse)
        programmeHasStop = stop != nil
        programmeKept = true
        currentProgramme = Programme(channelID: channelID, start: start, stop: stop ?? start, title: "")
    }

    private func endProgrammeElement(_ elementName: String, value: String) {
        switch elementName {
        case "title":
            if currentProgramme?.title.isEmpty == true { currentProgramme?.title = value }
        case "sub-title":
            if currentProgramme?.subtitle == nil, !value.isEmpty { currentProgramme?.subtitle = value }
        case "desc":
            if currentProgramme?.summary == nil, !value.isEmpty { currentProgramme?.summary = value }
        case "category":
            if currentProgramme?.category == nil, !value.isEmpty { currentProgramme?.category = value }
        case "episode-num":
            switch episodeSystem {
            case "onscreen": if onscreenEpisode == nil, !value.isEmpty { onscreenEpisode = value }
            case "xmltv_ns": if nsEpisode == nil { nsEpisode = Self.episodeText(xmltvNS: value) }
            default: break
            }
            episodeSystem = nil
        case "programme":
            if programmeKept, var programme = currentProgramme {
                programme.episode = onscreenEpisode ?? nsEpisode
                pending.append((programme, programmeHasStop))
            }
            currentProgramme = nil
        default:
            break
        }
    }

    /// `"1.0.0/1"` → "S2 E1"; `".4."` → "E5". Zero-based; `/total` parts ignored.
    static func episodeText(xmltvNS: String) -> String? {
        let parts = xmltvNS.split(separator: ".", omittingEmptySubsequences: false)
        func value(_ index: Int) -> Int? {
            guard index < parts.count else { return nil }
            let field = parts[index].split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            return Int(field).map { $0 + 1 }
        }
        let text = [value(0).map { "S\($0)" }, value(1).map { "E\($0)" }].compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private func finish() -> Result {
        // Fill missing stops from the next programme on the same channel, then keep those overlapping the window.
        var byChannel: [String: [Int]] = [:]
        for (index, item) in pending.enumerated() {
            byChannel[item.programme.channelID, default: []].append(index)
        }
        for indices in byChannel.values {
            let sorted = indices.sorted { pending[$0].programme.start < pending[$1].programme.start }
            for (position, index) in sorted.enumerated() where !pending[index].hasStop {
                let start = pending[index].programme.start
                let next = sorted[(position + 1)...].lazy.map { self.pending[$0].programme.start }.first { $0 > start }
                pending[index].programme.stop = next ?? start.addingTimeInterval(30 * 60)
            }
        }
        let programmes = pending.map(\.programme).filter {
            $0.stop > $0.start && $0.start < window.end && $0.stop > window.start
        }
        return Result(channels: channels, programmes: programmes)
    }
}
