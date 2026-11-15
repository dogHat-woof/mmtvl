import Foundation
import Observation

/// M7f L12: Live TV search. The on-screen keyboard (L11) on the left, channels and programmes on the right;
/// M7l L12: teams between them.
/// `LiveTVModel` keeps one while search is open and sends it every command but Home.
@Observable
final class LiveSearchModel {
    enum Focus: Equatable { case keyboard, results(Int) }

    enum Result: Equatable, Identifiable {
        case channel(Channel)
        case programme(Channel, Programme)
        /// M7l L12: Select adds it to My Teams or removes it.
        case team(Team)

        var id: String {
            switch self {
            case .channel(let channel): "channel:\(channel.id)"
            case .programme(let channel, let programme):
                "programme:\(channel.id):\(programme.start.timeIntervalSinceReferenceDate):\(programme.title)"
            case .team(let team): "team:\(team.id)"
            }
        }

        /// Nil for a team.
        var channel: Channel? {
            switch self {
            case .channel(let channel), .programme(let channel, _): channel
            case .team: nil
            }
        }
    }

    /// `.toggleTeam` (M7l L12): search stays open.
    enum Outcome: Equatable { case none, close, choose(Result), toggleTeam(Team.ID) }

    /// Results show from this many typed characters (spaces aside).
    static let minimumCharacters = 2
    static let maxChannelResults = 8
    static let maxTeamResults = 12
    static let maxProgrammeResults = 40
    static let programmeHorizon: TimeInterval = 24 * 3600
    static let visibleResults = 8

    private(set) var keyboard: OnScreenKeyboard
    private(set) var focus: Focus = .keyboard
    private(set) var channelResults: [Result] = []
    private(set) var teamResults: [Result] = []
    private(set) var programmeResults: [Result] = []
    private(set) var firstVisibleResult = 0
    var results: [Result] { channelResults + teamResults + programmeResults }
    /// Enough is typed to search.
    var isSearching: Bool { Self.words(in: keyboard.text).joined().count >= Self.minimumCharacters }

    /// The running programme query (after the debounce); tests await it.
    @ObservationIgnored private(set) var queryTask: Task<Void, Never>?
    @ObservationIgnored private let library: IPTVLibrary
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let debounce: Duration

    init(library: IPTVLibrary, now: @escaping () -> Date = Date.init, debounce: Duration = .milliseconds(300),
         text: String = "") {
        self.library = library
        self.now = now
        self.debounce = debounce
        keyboard = OnScreenKeyboard(text: text)
        if !text.isEmpty { textChanged() }
    }

    func handle(_ command: RemoteCommand) -> Outcome {
        switch focus {
        case .keyboard:
            switch keyboard.handle(command) {
            case .changed: textChanged()
            case .leaveRight: if !results.isEmpty { focusResult(0) }
            case .back: return .close
            case .none, .leaveUp: break
            }
            return .none
        case .results(let index):
            switch command {
            case .up: focusResult(max(index - 1, 0))
            case .down: focusResult(min(index + 1, results.count - 1))
            case .channelUp: focusResult(max(index - Self.visibleResults, 0))
            case .channelDown: focusResult(min(index + Self.visibleResults, results.count - 1))
            case .left, .back: focus = .keyboard
            case .select:
                guard results.indices.contains(index) else { return .none }
                if case .team(let team) = results[index] { return .toggleTeam(team.id) }
                return .choose(results[index])
            case .right, .playPause, .home, .fastForward, .rewind, .menu,
                 .volumeUp, .volumeDown, .mute, .power, .powerMenu: break
            }
            return .none
        }
    }

    /// Phone text (L11).
    func apply(_ edit: TextEdit) {
        let before = keyboard.text
        keyboard.apply(edit)
        if keyboard.text != before { textChanged() }
    }

    /// Phone Return: the first channel or programme result, if any (never a team, M7l L12).
    var firstResult: Result? {
        results.first { if case .team = $0 { false } else { true } }
    }

    /// M7l L12: a team result's "In My Teams".
    func isTeamPicked(_ team: Team) -> Bool {
        library.isTeamPicked(team.id)
    }

    func cancel() {
        queryTask?.cancel()
    }

    var visibleResultRange: Range<Int> {
        firstVisibleResult..<min(firstVisibleResult + Self.visibleResults, results.count)
    }

    /// Is `programme` airing now?
    func isOnNow(_ programme: Programme) -> Bool {
        let date = now()
        return programme.start <= date && date < programme.stop
    }

    // MARK: - Private

    /// Words of `text`, folded for case and diacritics.
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    /// M7l L12: at most `maxTeamResults` teams whose name, school, league and conference (M7m L29: or aliases and
    /// abbreviations, whatever the matching options say: typing "ULM" asks for UL Monroe) hold every word. Teams
    /// whose school, an alias or an abbreviation is exactly the words come first ("michigan": Michigan, not Michigan
    /// State), then those whose name or school has every word as a whole word ("duke": Duke's teams), then those
    /// where every word starts a word of the name or school (Duquesne and James Madison "Dukes"), then the rest;
    /// catalog order within each.
    /// Words found in the team's league title or conference ("basketball", "big") don't count for the rank.
    static func teams(matching words: [String]) -> [Team] {
        teamSearchTexts.enumerated()
            .filter { _, entry in words.allSatisfy { entry.text.contains($0) } }
            .map { index, entry in
                let nameWords = words.filter { !entry.groupText.contains($0) }.map(tokens(in:))
                return (rank: rank(nameWords, nameWords: entry.nameWords, schoolNames: entry.schoolNames),
                        index: index, team: entry.team)
            }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .prefix(Self.maxTeamResults)
            .map(\.team)
    }

    /// 0: the words are the school or one of its aliases ("michigan": Michigan, not Michigan State); 1: every word
    /// is a whole word of the name or school; 2: every word starts one; 3: otherwise.
    private static func rank(_ wordTokens: [[String]], nameWords: Set<String>, schoolNames: Set<String>) -> Int {
        let parts = Array(wordTokens.joined())
        if !parts.isEmpty, schoolNames.contains(parts.joined(separator: " ")) { return 0 }
        if parts.allSatisfy(nameWords.contains) { return 1 }
        if parts.allSatisfy({ part in nameWords.contains { $0.hasPrefix(part) } }) { return 2 }
        return 3
    }

    /// Folded letters and digits, split at everything else ("Texas A&M" → texas, a, m).
    private static func tokens(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Each team with its folded search text (name, school, league, conference, aliases, abbreviations), its folded
    /// league title and conference, the words of its name and school, and its school, aliases and abbreviations
    /// (words joined by one space), made once.
    private static let teamSearchTexts:
        [(team: Team, text: String, groupText: String, nameWords: Set<String>, schoolNames: Set<String>)] =
        TeamCatalog.teams.map { team in
            let fold = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            let text = fold(([team.name, team.school ?? "", team.league.title, team.conference ?? ""]
                + team.aliases + team.abbreviations).joined(separator: " "))
            let groupText = fold(team.league.title + " " + (team.conference ?? ""))
            let schoolNames = Set(([team.school].compactMap { $0 } + team.aliases + team.abbreviations)
                .map { tokens(in: $0).joined(separator: " ") }.filter { !$0.isEmpty })
            return (team, text, groupText, Set(tokens(in: team.name + " " + (team.school ?? ""))), schoolNames)
        }

    /// Channels at once; programmes after the debounce (the previous query is cancelled).
    private func textChanged() {
        queryTask?.cancel()
        guard isSearching else {
            channelResults = []
            teamResults = []
            programmeResults = []
            resetFocus()
            return
        }
        let words = Self.words(in: keyboard.text)
        let visible = library.lineup.visibleChannels
        channelResults = visible
            .filter { channel in
                let name = channel.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                return words.allSatisfy { name.contains($0) }
            }
            .prefix(Self.maxChannelResults)
            .map(Result.channel)
        // M7l L12: teams at once; the catalog is in memory.
        teamResults = Self.teams(matching: words).map(Result.team)
        // Programmes already found narrow at once; new ones come after the debounce.
        programmeResults = programmeResults.filter { result in
            guard case .programme(_, let programme) = result else { return false }
            let title = programme.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.allSatisfy { title.contains($0) }
        }
        resetFocus()
        let library = library
        let debounce = debounce
        let date = now()
        queryTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let found = await library.searchProgrammes(
                words: words, channels: visible, in: DateInterval(start: date, duration: Self.programmeHorizon),
                limit: Self.maxProgrammeResults)
            guard !Task.isCancelled, let self else { return }
            self.programmeResults = found.map { Result.programme($0.channel, $0.programme) }
            self.resetFocus()
        }
    }

    /// Results changed: a result focus stays in range, or goes back to the keyboard when there are none.
    private func resetFocus() {
        guard case .results(let index) = focus else {
            firstVisibleResult = 0
            return
        }
        if results.isEmpty {
            focus = .keyboard
            firstVisibleResult = 0
        } else {
            focusResult(min(index, results.count - 1))
        }
    }

    private func focusResult(_ index: Int) {
        guard results.indices.contains(index) else { return }
        focus = .results(index)
        if index < firstVisibleResult {
            firstVisibleResult = index
        } else if index >= firstVisibleResult + Self.visibleResults {
            firstVisibleResult = index - Self.visibleResults + 1
        }
        firstVisibleResult = min(firstVisibleResult, max(0, results.count - Self.visibleResults))
    }
}
