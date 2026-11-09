import Foundation
import Observation

/// M7f L12: Live TV search. The on-screen keyboard (L11) on the left, channels and programmes on the right.
/// `LiveTVModel` keeps one while search is open and sends it every command but Home.
@Observable
final class LiveSearchModel {
    enum Focus: Equatable { case keyboard, results(Int) }

    enum Result: Equatable, Identifiable {
        case channel(Channel)
        case programme(Channel, Programme)

        var id: String {
            switch self {
            case .channel(let channel): "channel:\(channel.id)"
            case .programme(let channel, let programme):
                "programme:\(channel.id):\(programme.start.timeIntervalSinceReferenceDate):\(programme.title)"
            }
        }

        var channel: Channel {
            switch self {
            case .channel(let channel), .programme(let channel, _): channel
            }
        }
    }

    enum Outcome: Equatable { case none, close, choose(Result) }

    /// Results show from this many typed characters (spaces aside).
    static let minimumCharacters = 2
    static let maxChannelResults = 8
    static let maxProgrammeResults = 40
    static let programmeHorizon: TimeInterval = 24 * 3600
    static let visibleResults = 8

    private(set) var keyboard: OnScreenKeyboard
    private(set) var focus: Focus = .keyboard
    private(set) var channelResults: [Result] = []
    private(set) var programmeResults: [Result] = []
    private(set) var firstVisibleResult = 0
    var results: [Result] { channelResults + programmeResults }
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
            case .select: return results.indices.contains(index) ? .choose(results[index]) : .none
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

    /// Phone Return: the first result, if any.
    var firstResult: Result? { results.first }

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

    /// Channels at once; programmes after the debounce (the previous query is cancelled).
    private func textChanged() {
        queryTask?.cancel()
        guard isSearching else {
            channelResults = []
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
