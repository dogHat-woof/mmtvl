import Foundation

/// M7m L29: the matcher's two looser rules, Settings → Live TV → My Teams → Matching (`settings.json`
/// `teamMatchInitials`, `teamMatchNicknames`); both off by default. Either way, a college team matches by its name,
/// school and aliases (ESPN's short name and location even when they're initials, BYU, LSU; the spelled-out and
/// generated forms), each also followed by the nickname, without apostrophes too, and a key teams share matches all
/// of them (L27).
nonisolated struct TeamMatchOptions: Hashable, Sendable {
    /// Its abbreviations (`Team.abbreviations`: "ULM", "BUF") count as names too, alone and followed by the nickname,
    /// in programmes and game entries. Off: "ULM Warhawks" and "NE @ BUF" name no team.
    var initials: Bool
    /// L28's nickname fallback runs for a side that is no key ("The Cougars meet the Bearcats"). Off: such a side
    /// matches nothing, as before M7m.
    var nicknames: Bool

    init(initials: Bool = false, nicknames: Bool = false) {
        self.initials = initials
        self.nicknames = nicknames
    }

    /// Both off: the settings' defaults, and every `index:` parameter's default (`Index.bundled(.off)`).
    static let off = TeamMatchOptions()
}

/// M7f L13: which channels show the picked teams now. Game entries by name, network channels by the programme on now.
/// Every function taking an `index:` defaults to `Index.bundled(.off)`, the bundled catalog with both of L29's options
/// off (the settings' defaults); callers that follow the settings pass `Index.bundled(options)`.
nonisolated enum TeamMatcher {
    enum Feed: Equatable, Sendable { case home, away }

    /// A game entry: "Away @ Home", from a name with or without its feed.
    struct Game: Equatable, Sendable {
        var away: String
        var home: String
        var feed: Feed?
    }

    static let homeFeedSuffix = " (Home Feed)"
    static let awayFeedSuffix = " (Away Feed)"
    /// A programme with one of these in its title isn't the game itself.
    static let excludedTitleWords = ["pregame", "postgame", "highlights", "classic", "replay"]

    /// Lowercased, without diacritics, punctuation as spaces, single spaces, padded with a space at each end,
    /// so `contains(" lakers ")` matches whole words.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var cleaned = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            cleaned.append(CharacterSet.alphanumerics.contains(scalar) ? scalar : " ")
        }
        let words = String(cleaned).split(separator: " ")
        return " " + words.joined(separator: " ") + " "
    }

    /// M7l step 8a: a game entry, in any group but a Replays one ("Live-Games", "NFL"; never "NBA-Replays"): its
    /// name is "Away @ Home" (feed aside) with at least one side a pro team by full name or alias, or a college
    /// school. Never a network channel ("NFL Network" in "NFL").
    static func isGameEntry(_ channel: Channel, index: Index = .bundled(.off)) -> Bool {
        gameEntry(channel, index: index) != nil
    }

    /// The game a channel is the entry of (see `isGameEntry`), else nil.
    static func gameEntry(_ channel: Channel, index: Index = .bundled(.off)) -> Game? {
        guard !channel.group.lowercased().contains("replay"), let game = game(from: channel.name) else { return nil }
        func isKnown(_ side: String) -> Bool {
            team(named: side, index: index) != nil || index.collegeSchools[normalized(side)] != nil
        }
        return isKnown(game.away) || isKnown(game.home) ? game : nil
    }

    /// "Miami Heat @ Los Angeles Lakers (Home Feed)" → away "Miami Heat", home "Los Angeles Lakers", feed home.
    /// Only the name's first `headingReadLength` UTF-16 units are read (the security review for build 34: a
    /// playlist's names are unbounded; real ones are far shorter).
    static func game(from name: String) -> Game? {
        var base = prefix(name, utf16: headingReadLength)
        var feed: Feed?
        if base.hasSuffix(homeFeedSuffix) {
            base.removeLast(homeFeedSuffix.count)
            feed = .home
        } else if base.hasSuffix(awayFeedSuffix) {
            base.removeLast(awayFeedSuffix.count)
            feed = .away
        }
        let sides = base.components(separatedBy: " @ ")
        guard sides.count == 2 else { return nil }
        let away = sides[0].trimmingCharacters(in: .whitespaces)
        let home = sides[1].trimmingCharacters(in: .whitespaces)
        guard !away.isEmpty, !home.isEmpty else { return nil }
        return Game(away: away, home: home, feed: feed)
    }

    /// The pro team whose full name or an alias is exactly `name` (case and punctuation aside).
    static func team(named name: String, index: Index = .bundled(.off)) -> Team? {
        index.proFullNames[normalized(name)]
    }

    /// The away team, then the home team, of a game entry (only pro teams found; a college entry doesn't say its
    /// sport).
    static func teams(inGame channel: Channel, index: Index = .bundled(.off)) -> [Team] {
        guard let game = gameEntry(channel, index: index) else { return [] }
        return [team(named: game.away, index: index), team(named: game.home, index: index)].compactMap { $0 }
    }

    /// Teams a programme is about, among every catalog team (the channel menu).
    static func teams(in programme: Programme, index: Index = .bundled(.off)) -> [Team] {
        teams(in: programme, among: index.teams, index: index)
    }

    /// Teams of `candidates` a programme is about, each once: `teamsBySide` flattened, college sides first.
    static func teams(in programme: Programme, among candidates: [Team], index: Index = .bundled(.off)) -> [Team] {
        var seen: Set<Team.ID> = []
        return teamsBySide(in: programme, among: candidates, index: index).joined()
            .filter { seen.insert($0.id).inserted }
    }

    /// M7m L31: `teamsBySide(in:among:index:)` among every catalog team (the channel menu).
    static func teamsBySide(in programme: Programme, index: Index = .bundled(.off)) -> [[Team]] {
        teamsBySide(in: programme, among: index.teams, index: index)
    }

    /// M7m L31: the teams of `candidates` a programme is about, one array per side that names any, in the order the
    /// programme names them. Each team is in one side only: a side that names it exactly (a key) claims it first (the
    /// first such side), so a nickname-only side never takes a team a later side names ("The Tigers host the LSU
    /// Tigers": LSU is the second side's, not one of the first side's Tigers); else the first fallback side that
    /// names it. Title, subtitle and category are read to `headingReadLength`. College (M7l L10): the sport from the
    /// title and category, the two sides of the subtitle (else the title, else (M7m L25) the summary's lead) looked up
    /// exactly in that league's keys (`Index.collegeNames`; M7m L27: a key several teams share gives all of them, in
    /// catalog order); (M7m L28, with `TeamMatchOptions.nicknames`) a side that is no key of the league falls back to
    /// its nickname (`nicknameTeams`), which may give several teams. Pro, one team per side: a full name or alias in
    /// its title or subtitle, or (outside college programmes) a nickname there with a league word in its title,
    /// subtitle or category; in catalog order (pro teams aren't matched by side).
    static func teamsBySide(in fullProgramme: Programme, among candidates: [Team],
                            index: Index = .bundled(.off)) -> [[Team]] {
        let programme = bounded(fullProgramme)
        var sides: [[Team]] = []
        let league = collegeLeague(of: programme)
        if let league, let names = index.collegeNames[league] {
            let ids = Set(candidates.map(\.id))
            var seen: Set<Team.ID> = []
            // The text a conference is looked for in (L28, L30), made at most once, only for a fallback.
            var conferenceText: String?
            func programmeText() -> String {
                if let conferenceText { return conferenceText }
                let text = conferenceSearchText(of: programme)
                conferenceText = text
                return text
            }
            // Each side's teams, and whether a key named them exactly.
            var named: [(teams: [Team], isExact: Bool)] = []
            for side in collegeSides(of: programme) {
                if let exact = names[side] {
                    named.append((exact, true))
                } else if index.options.nicknames {
                    named.append((nicknameTeams(side: side, league: league, index: index, programmeText: programmeText),
                                  false))
                } else {
                    named.append(([], false))
                }
            }
            // Exact sides claim their teams first, then the fallback sides take what's left.
            func claim(_ teams: [Team]) -> [Team] { teams.filter { ids.contains($0.id) && seen.insert($0.id).inserted } }
            var found: [Int: [Team]] = [:]
            for (n, side) in named.enumerated() where side.isExact { found[n] = claim(side.teams) }
            for (n, side) in named.enumerated() where !side.isExact { found[n] = claim(side.teams) }
            sides = named.indices.compactMap { found[$0].flatMap { $0.isEmpty ? nil : $0 } }
        }
        let text = normalized([programme.title, programme.subtitle ?? ""].joined(separator: " "))
        let leagueText = normalized([programme.title, programme.subtitle ?? "", programme.category ?? ""].joined(separator: " "))
        let title = normalized(programme.title)
        // "basketball" in "College Basketball" isn't the NBA's.
        let isCollegeProgramme = league != nil || title.contains(" college ") || title.contains(" ncaa")
        sides += candidates.filter { team in
            guard !team.league.isCollege else { return false }
            // A one-word full name ("Athletics") is only a nickname: it needs a league word too.
            let nickname = normalized(team.nickname)
            if team.fullNames.contains(where: { normalized($0) != nickname && text.contains(normalized($0)) }) { return true }
            return !isCollegeProgramme && text.contains(nickname)
                && team.league.words.contains { leagueText.contains(" \($0) ") }
        }.map { [$0] }
        return sides
    }

    /// M7m L30: the text the nickname fallback looks for a conference in: the title, the subtitle and the summary's
    /// first `summaryLeadLength` UTF-16 units (real conference mentions are in the lead), normalized.
    static func conferenceSearchText(of fullProgramme: Programme) -> String {
        let programme = bounded(fullProgramme)
        let summary = prefix(programme.summary ?? "", utf16: summaryLeadLength)
        return normalized([programme.title, programme.subtitle ?? "", summary].joined(separator: " "))
    }

    /// M7m L28: the teams of `league` a side that is no key names by its nickname. The side's last words are a
    /// nickname of the league's teams (whole words, the longest nickname first); of those teams, the ones whose school
    /// words (`Index.collegeSchoolWords`) share a word with the side's words before the nickname, else (L30) the ones
    /// whose conference `programmeText` (`conferenceSearchText`) names by one of its phrases
    /// (`Index.collegeConferences`, whole words), else all of them. Empty when the side ends with no nickname, or when
    /// `index` wasn't built with `TeamMatchOptions.nicknames` (it has no nicknames). A few dictionary lookups per side,
    /// and at most a few phrase searches per candidate: no scan of the catalog.
    static func nicknameTeams(side: String, league: TeamLeague, index: Index,
                              programmeText: () -> String) -> [Team] {
        guard let nicknames = index.collegeNicknames[league] else { return [] }
        let words = side.split(separator: " ")
        for count in stride(from: min(words.count, index.maxNicknameWords), through: 1, by: -1) {
            guard let teams = nicknames[" " + words.suffix(count).joined(separator: " ") + " "] else { continue }
            let before = Set(words.dropLast(count).map(String.init))
            if !before.isEmpty {
                let sharing = teams.filter { !(index.collegeSchoolWords[$0.id] ?? []).isDisjoint(with: before) }
                if !sharing.isEmpty { return sharing }
            }
            let text = programmeText()
            let named = teams.filter { team in
                (index.collegeConferences[team.id] ?? []).contains { text.contains($0) }
            }
            return named.isEmpty ? teams : named
        }
        return []
    }

    /// M7l L10: the college sport a programme's title and category name, or nil.
    static func collegeLeague(of fullProgramme: Programme) -> TeamLeague? {
        let programme = bounded(fullProgramme)
        let text = normalized([programme.title, programme.category ?? ""].joined(separator: " "))
        func has(_ words: String...) -> Bool { words.contains { text.contains(" \($0) ") } }
        if has("women s college basketball", "ncaaw") { return .ncaaw }
        if has("college basketball", "ncaab", "ncaam") { return .ncaam }
        if has("college football", "ncaaf") { return .ncaaf }
        if has("college baseball") { return .ncaabase }
        return nil
    }

    static let sideSeparators = [" at ", " vs. ", " vs ", " @ "]

    /// M7l L10: the two sides of a college programme, normalized: from the subtitle, else the title after its first
    /// ":" (not after a leading "Live:"); a leading "<event>: " and rankings ("No. 5 ", "#5 ", "(5) ") dropped.
    /// M7m L25: else from the summary's lead (`summarySides`). Empty unless there are exactly two.
    static func collegeSides(of fullProgramme: Programme) -> [String] {
        let programme = bounded(fullProgramme)
        let sides = headingSides(of: programme)
        return sides.isEmpty ? summarySides(of: programme.summary ?? "") : sides
    }

    /// The sides from the subtitle, else the title after its first ":" (see `collegeSides`).
    private static func headingSides(of programme: Programme) -> [String] {
        var text: String
        if let subtitle = programme.subtitle?.trimmingCharacters(in: .whitespaces), !subtitle.isEmpty {
            text = subtitle
        } else {
            var title = programme.title.trimmingCharacters(in: .whitespaces)
            if title.lowercased().hasPrefix("live:") { title = String(title.dropFirst(5)) }
            guard let colon = title.firstIndex(of: ":") else { return [] }
            text = String(title[title.index(after: colon)...])
        }
        // "SEC Tournament: Georgia vs. Oklahoma" → "Georgia vs. Oklahoma".
        if let colon = text.firstIndex(of: ":") { text = String(text[text.index(after: colon)...]) }
        let lowered = text.lowercased()
        for separator in sideSeparators {
            let parts = lowered.components(separatedBy: separator)
            guard parts.count > 1 else { continue }
            guard parts.count == 2 else { return [] }
            let sides = parts.map { side in
                normalized(side.replacingOccurrences(of: #"^\s*(no\.?\s*\d+|#\s*\d+|\(\s*\d+\s*\))\s+"#, with: "",
                                                     options: .regularExpression))
            }
            return sides.contains(where: isBlank) ? [] : sides
        }
        return []
    }

    /// M7m L25 (the security review for build 34: a scan, not a regex, which backtracked within its 400-unit cap):
    /// "The [No. N] <A> [(record)] <verb> the [No. N] <B> [(record)]" at the start of a summary, then
    /// for/at/in/on/to or "." "," ";". A side may contain parentheses ("Miami (OH) RedHawks"); only a trailing one
    /// that starts with a digit is a record and dropped. "." after "St"/"Mt"/"No" or an initial doesn't end a side
    /// ("St. John's", "Stephen F. Austin"). Run only on `summaryLeadLength`, whitespace collapsed.
    nonisolated enum SummaryLead {
        /// L25's verbs, each a list of words; a trailing "s" (or "es" for clash) is optional.
        static let verbs: [[String]] = [["visit"], ["face"], ["meet"], ["host"], ["clash", "with"], ["take", "on"],
                                        ["play"], ["battle"], ["square", "off", "against"]]
        static let ends = ["for", "at", "in", "on", "to"]

        /// The two sides, as written (not normalized), else nil. Side A runs to the first verb followed by "the"; a
        /// leading rank is dropped from each side (kept when nothing else follows it), a trailing record too. Side B
        /// runs to the first end. Linear in the text, apart from at most four passes (with and without each rank).
        static func sides(of text: String) -> (String, String)? {
            let u = Array(text.unicodeScalars)
            var i = skipSpaces(u, 0)
            guard let afterThe = word("the", in: u, at: i), afterThe < u.count, u[afterThe] == " " else { return nil }
            i = skipSpaces(u, afterThe)
            let nextClose = closingParentheses(u)
            for aStart in starts(u, i) {
                guard let (aEnd, bFrom) = firstVerb(u, from: aStart, nextClose: nextClose) else { continue }
                for bStart in starts(u, bFrom) {
                    guard let bEnd = firstEnd(u, from: bStart, nextClose: nextClose) else { continue }
                    return (string(u, aStart, aEnd), string(u, bStart, bEnd))
                }
            }
            return nil
        }

        /// Where a side may start: after its rank, if it has one, then at `i` itself.
        private static func starts(_ u: [Unicode.Scalar], _ i: Int) -> [Int] {
            rankEnd(u, i).map { [$0, i] } ?? [i]
        }

        /// The first `p > from` where a side can end before (a record and) a verb and "the": the side's end and where
        /// side B starts.
        private static func firstVerb(_ u: [Unicode.Scalar], from: Int, nextClose: [Int]) -> (Int, Int)? {
            var p = from + 1
            while p < u.count {
                let afterRecord = recordEnd(u, p, nextClose: nextClose).flatMap { verbPhraseEnd(u, $0) }
                if let after = afterRecord ?? verbPhraseEnd(u, p) {
                    return (p, after)
                }
                p += 1
            }
            return nil
        }

        /// The first `p > from` where side B can end before (a record and) an end.
        private static func firstEnd(_ u: [Unicode.Scalar], from: Int, nextClose: [Int]) -> Int? {
            var p = from + 1
            while p <= u.count {
                if let record = recordEnd(u, p, nextClose: nextClose), isEnd(u, record) { return p }
                if isEnd(u, p) { return p }
                p += 1
            }
            return nil
        }

        /// `\s+ <verb> \s+ the \s+` at `p`: the index after it.
        private static func verbPhraseEnd(_ u: [Unicode.Scalar], _ p: Int) -> Int? {
            guard p < u.count, u[p] == " " else { return nil }
            let start = skipSpaces(u, p)
            for verb in verbs {
                var i = start
                var matched = true
                for (n, part) in verb.enumerated() {
                    if n > 0 {
                        guard i < u.count, u[i] == " " else { matched = false; break }
                        i = skipSpaces(u, i)
                    }
                    guard let end = word(part, in: u, at: i) else { matched = false; break }
                    i = end
                    // "visits", "clashes": an optional ending on the first word.
                    if n == 0 {
                        let ending = part == "clash" ? "es" : "s"
                        if let longer = word(ending, in: u, at: i), longer < u.count, u[longer] == " " { i = longer }
                    }
                }
                guard matched, i < u.count, u[i] == " " else { continue }
                let theStart = skipSpaces(u, i)
                guard let afterThe = word("the", in: u, at: theStart), afterThe < u.count, u[afterThe] == " " else {
                    continue
                }
                return skipSpaces(u, afterThe)
            }
            return nil
        }

        /// An end at `p`: `\s+(for|at|in|on|to)\b`, or `\s*[.,;]` not right after "St", "Mt", "No" or one letter.
        private static func isEnd(_ u: [Unicode.Scalar], _ p: Int) -> Bool {
            if p < u.count, u[p] == " " {
                let q = skipSpaces(u, p)
                for end in ends {
                    if let after = word(end, in: u, at: q), after == u.count || !isWord(u[after]) { return true }
                }
            }
            let q = skipSpaces(u, p)
            guard q < u.count, u[q] == "." || u[q] == "," || u[q] == ";" else { return false }
            for short in ["st", "mt", "no"] where q >= 2 && word(short, in: u, at: q - 2) != nil
                && (q == 2 || !isWord(u[q - 3])) {
                return false
            }
            if q >= 1, isWord(u[q - 1]), q == 1 || !isWord(u[q - 2]) { return false }
            return true
        }

        /// A record at `p`, `\s*\(\d[^)]*\)`: the index after its ")".
        private static func recordEnd(_ u: [Unicode.Scalar], _ p: Int, nextClose: [Int]) -> Int? {
            let q = skipSpaces(u, p)
            guard q + 1 < u.count, u[q] == "(", isDigit(u[q + 1]) else { return nil }
            let close = nextClose[q + 1]
            return close < u.count ? close + 1 : nil
        }

        /// A rank at `i`, `(no\.?\s*\d+|#\s*\d+|\(\s*\d+\s*\))\s+`: the index after its spaces.
        private static func rankEnd(_ u: [Unicode.Scalar], _ i: Int) -> Int? {
            var j: Int
            if let after = word("no", in: u, at: i) {
                j = after
                if j < u.count, u[j] == "." { j += 1 }
                j = skipSpaces(u, j)
                j = skipDigits(u, j, atLeastOne: true) ?? -1
            } else if i < u.count, u[i] == "#" {
                j = skipDigits(u, skipSpaces(u, i + 1), atLeastOne: true) ?? -1
            } else if i < u.count, u[i] == "(" {
                j = skipDigits(u, skipSpaces(u, i + 1), atLeastOne: true).map { skipSpaces(u, $0) } ?? -1
                if j >= 0 { j = j < u.count && u[j] == ")" ? j + 1 : -1 }
            } else {
                return nil
            }
            guard j >= 0, j < u.count, u[j] == " " else { return nil }
            return skipSpaces(u, j)
        }

        /// `literal` (lowercase ASCII) at `i`, ignoring case: the index after it. Not a whole-word check.
        private static func word(_ literal: String, in u: [Unicode.Scalar], at i: Int) -> Int? {
            var j = i
            for c in literal.unicodeScalars {
                guard j < u.count, lowercased(u[j]) == c else { return nil }
                j += 1
            }
            return j
        }

        private static func lowercased(_ c: Unicode.Scalar) -> Unicode.Scalar {
            ("A"..."Z").contains(c) ? Unicode.Scalar(c.value + 32)! : c
        }

        private static func skipSpaces(_ u: [Unicode.Scalar], _ i: Int) -> Int {
            var j = i
            while j < u.count, u[j] == " " { j += 1 }
            return j
        }

        private static func skipDigits(_ u: [Unicode.Scalar], _ i: Int, atLeastOne: Bool) -> Int? {
            var j = i
            while j < u.count, isDigit(u[j]) { j += 1 }
            return atLeastOne && j == i ? nil : j
        }

        /// For each index, the index of the first ")" at or after it (`u.count` when none).
        private static func closingParentheses(_ u: [Unicode.Scalar]) -> [Int] {
            var result = [Int](repeating: u.count, count: u.count + 1)
            var i = u.count - 1
            while i >= 0 {
                result[i] = u[i] == ")" ? i : result[i + 1]
                i -= 1
            }
            return result
        }

        /// ICU's `\d`: a decimal digit of any script.
        private static func isDigit(_ c: Unicode.Scalar) -> Bool {
            c.properties.numericType == .decimal
        }

        /// ICU's `\w`: letters, marks, decimal digits, connector punctuation, ZWNJ and ZWJ.
        private static func isWord(_ c: Unicode.Scalar) -> Bool {
            if c.value < 0x80 {
                return ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "_"
            }
            let properties = c.properties
            switch properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark, .connectorPunctuation, .decimalNumber: return true
            default: return properties.isAlphabetic || c.value == 0x200C || c.value == 0x200D
            }
        }

        private static func string(_ u: [Unicode.Scalar], _ start: Int, _ end: Int) -> String {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: u[start..<end])
            return String(view)
        }
    }

    /// How much of a summary `SummaryLead` reads, in UTF-16 units after runs of whitespace are collapsed: real leads
    /// are under 150 characters, and a guide's description is unbounded (the scan is linear, but it runs on the main
    /// actor per channel). Characters aren't counted: one letter can carry any number of combining marks.
    static let summaryLeadLength = 400
    /// The summary is first cut to this many UTF-16 units, so collapsing its whitespace stays cheap.
    static let summaryReadLength = 4096
    /// How much of a title, subtitle and category the matcher reads, in UTF-16 units: real ones are far shorter, and
    /// a guide's are unbounded (a 1 MB title cost seconds in the pro full-name scan on the main actor).
    static let headingReadLength = 400

    /// `programme` with its title, subtitle and category cut to `headingReadLength` (the summary is cut where read).
    static func bounded(_ programme: Programme) -> Programme {
        var bounded = programme
        bounded.title = prefix(programme.title, utf16: headingReadLength)
        bounded.subtitle = programme.subtitle.map { prefix($0, utf16: headingReadLength) }
        bounded.category = programme.category.map { prefix($0, utf16: headingReadLength) }
        return bounded
    }

    /// `text` cut to at most `length` UTF-16 units, at the start of the composed character sequence there.
    private static func prefix(_ text: String, utf16 length: Int) -> String {
        let string = text as NSString
        guard string.length > length else { return text }
        return string.substring(to: string.rangeOfComposedCharacterSequence(at: length).location)
    }

    /// M7m L25: the two sides a summary's lead names (`SummaryLead`), normalized; else empty.
    static func summarySides(of fullSummary: String) -> [String] {
        let collapsed = prefix(fullSummary, utf16: summaryReadLength)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let summary = prefix(collapsed, utf16: summaryLeadLength)
        guard let (a, b) = SummaryLead.sides(of: summary) else { return [] }
        let sides = [normalized(a), normalized(b)]
        return sides.contains(where: isBlank) ? [] : sides
    }

    /// A normalized text with no words.
    static func isBlank(_ normalized: String) -> Bool {
        normalized.allSatisfy { $0 == " " }
    }

    /// Whether a programme on now counts for the Teams group (not a pregame show, a replay…).
    static func isLiveGame(_ programme: Programme) -> Bool {
        let title = normalized(prefix(programme.title, utf16: headingReadLength))
        return !excludedTitleWords.contains { title.contains(" \($0) ") }
    }

    /// The Teams group: game entries first (playlist order; per game, the picked team's feed first), then network
    /// channels whose programme on now is about a picked team (playlist order).
    static func channelIDs(channels: [Channel], nowPlaying: [Channel.ID: Programme], picked: Set<Team.ID>,
                           index: Index = .bundled(.off)) -> [Channel.ID] {
        guard !picked.isEmpty else { return [] }
        return gameChannelIDs(channels: channels, picked: picked, index: index)
            + networkChannelIDs(channels: channels, nowPlaying: nowPlaying, picked: picked, index: index)
    }

    /// Each side of a game entry is a pro team by its full name, else (M7l L10) a college school by any of its keys
    /// (M7m L27: also a school form with the nickname, "Louisiana-Monroe Warhawks"; L29: its abbreviations only with
    /// `TeamMatchOptions.initials`, "NE @ BUF"), which counts when that school is picked in any college sport; a key
    /// several schools share counts for each of them. Never the nickname fallback (L28): entries are written with
    /// full names.
    static func gameChannelIDs(channels: [Channel], picked: Set<Team.ID>, index: Index = .bundled(.off)) -> [Channel.ID] {
        let pickedSchools = Set(picked.compactMap { index.byID[$0] }.filter(\.league.isCollege)
            .map { normalized($0.school ?? $0.name) })
        func isPicked(_ side: String) -> Bool {
            if let team = team(named: side, index: index) { return picked.contains(team.id) }
            return !(index.collegeSchools[normalized(side)] ?? []).isDisjoint(with: pickedSchools)
        }
        // Feeds of one game, grouped by "away @ home", in order of the game's first entry.
        var order: [String] = []
        var feeds: [String: [(channel: Channel, preferred: Bool)]] = [:]
        for channel in channels {
            guard let game = gameEntry(channel, index: index) else { continue }
            let away = isPicked(game.away)
            let home = isPicked(game.home)
            guard away || home else { continue }
            let key = normalized(game.away) + "@" + normalized(game.home)
            if feeds[key] == nil { order.append(key) }
            // The picked team's own broadcast first; with both teams picked, playlist order.
            let preferred = switch game.feed {
            case .home?: home && !away
            case .away?: away && !home
            case nil: false
            }
            feeds[key, default: []].append((channel, preferred))
        }
        return order.flatMap { key in
            let entries = feeds[key] ?? []
            return (entries.filter(\.preferred) + entries.filter { !$0.preferred }).map(\.channel.id)
        }
    }

    /// Network channels whose programme on now is about a picked team. Only the picked teams are tested (M7l L10).
    static func networkChannelIDs(channels: [Channel], nowPlaying: [Channel.ID: Programme],
                                  picked: Set<Team.ID>, index: Index = .bundled(.off)) -> [Channel.ID] {
        let candidates = picked.compactMap { index.byID[$0] }
        guard !candidates.isEmpty else { return [] }
        return channels.compactMap { channel in
            guard !isGameEntry(channel, index: index), let programme = nowPlaying[channel.id], isLiveGame(programme),
                  !teams(in: programme, among: candidates, index: index).isEmpty
            else { return nil }
            return channel.id
        }
    }

    /// M7l 8c: how far ahead My Teams lists upcoming games.
    static let upcomingWindow: TimeInterval = 72 * 3600

    /// M7l 8c: My Teams' upcoming games: programmes starting after `now` and before `now + upcomingWindow` on
    /// `channels` (not game entries) about a picked team, by the live-game rules (no pregame, replay…). Soonest first,
    /// then playlist order; one per programme and channel. Pure and nonisolated: the library runs it off the main actor.
    /// Each distinct title, subtitle, category and summary is matched once. A cancelled task gets what was found so
    /// far (`finishedUpcomingGames` says whether it finished).
    static func upcomingGames(channels: [Channel], programmes: [Channel.ID: [Programme]], picked: Set<Team.ID>,
                              now: Date, index: Index = .bundled(.off)) -> [UpcomingTeamGame] {
        finishedUpcomingGames(channels: channels, programmes: programmes, picked: picked, now: now, index: index) ?? []
    }

    /// `upcomingGames`, or nil when `isCancelled` (the current task's cancellation) turned true before it finished:
    /// it's checked before each programme, so a cancelled update stops matching at once (the security review for
    /// build 34) and its partial result is never used.
    static func finishedUpcomingGames(channels: [Channel], programmes: [Channel.ID: [Programme]],
                                      picked: Set<Team.ID>, now: Date, index: Index = .bundled(.off),
                                      isCancelled: () -> Bool = { Task.isCancelled }) -> [UpcomingTeamGame]? {
        let candidates = picked.compactMap { index.byID[$0] }
        guard !candidates.isEmpty else { return [] }
        let end = now + upcomingWindow
        var matches: [String: Bool] = [:]
        func isAboutPicked(_ programme: Programme) -> Bool {
            // M7m L25: the summary too, since college sides may come from it (subtitle-less games share a title).
            let key = [programme.title, programme.subtitle ?? "", programme.category ?? "", programme.summary ?? ""]
                .joined(separator: "\u{1F}")
            if let known = matches[key] { return known }
            let found = isLiveGame(programme) && !teams(in: programme, among: candidates, index: index).isEmpty
            matches[key] = found
            return found
        }
        var games: [(order: Int, game: UpcomingTeamGame)] = []
        for (order, channel) in channels.enumerated() where !isGameEntry(channel, index: index) {
            var seen: Set<Date> = []
            for programme in programmes[channel.id] ?? [] {
                if isCancelled() { return nil }
                guard programme.start > now && programme.start < end && isAboutPicked(programme)
                    && seen.insert(programme.start).inserted else { continue }
                games.append((order, UpcomingTeamGame(channel: channel, programme: programme)))
            }
        }
        return games.sorted { ($0.game.programme.start, $0.order) < ($1.game.programme.start, $1.order) }.map(\.game)
    }

    /// The names the matcher looks teams up by, built once from a catalog and the options (tests build their own).
    nonisolated struct Index: Sendable {
        let teams: [Team]
        /// M7m L29: what the index was built with: abbreviations as keys (`initials`), the fallback's tables
        /// (`nicknames`; empty without it).
        let options: TeamMatchOptions
        let byID: [Team.ID: Team]
        /// Pro: every full name and alias, normalized → its team.
        let proFullNames: [String: Team]
        /// College, per league: each key, normalized → every team with it, in catalog order (M7m L27: a key several
        /// teams of a league share matches all of them). A team's keys: its `name`, `school` and aliases, (L29, with
        /// `TeamMatchOptions.initials`) its abbreviations, and each school form (the school, every alias and those
        /// abbreviations) followed by its nickname ("Louisiana-Monroe Warhawks", "ULM Warhawks"); each also without
        /// apostrophes ("Hawai'i" → `hawaii`, beside `hawai i`).
        let collegeNames: [TeamLeague: [String: [Team]]]
        /// College, any league: a key (as in `collegeNames`) → the normalized schools it names (game entries, L10;
        /// M7m L27: every school, not only an unshared key's).
        let collegeSchools: [String: Set<String>]
        /// M7m L28, per league: a nickname, normalized (and without apostrophes) → its teams, in catalog order. Empty
        /// without `TeamMatchOptions.nicknames`, as are `collegeSchoolWords` and `collegeConferences`.
        let collegeNicknames: [TeamLeague: [String: [Team]]]
        /// The most words a college nickname has ("Rainbow Warriors": 2): how many of a side's last words L28 tries.
        let maxNicknameWords: Int
        /// M7m L28: a college team's school words: the words of its `school` and of its multi-word aliases (one-word
        /// aliases are mostly abbreviations, some English words: "MAN", "LONG"), normalized, with and without
        /// apostrophes; 3 letters or more, never `schoolStopWords`.
        let collegeSchoolWords: [Team.ID: Set<String>]
        /// M7m L28, L30: the phrases that name a college team's conference, normalized (`conferencePhrases`):
        /// `[" sun belt "]`, `[" american athletic ", " aac "]`; none for the independents.
        let collegeConferences: [Team.ID: [String]]

        static let schoolStopWords: Set<String> = ["state", "university", "college", "the"]

        /// M7m L30: how guides name a conference, by its catalog name without the "(FCS)"-style label, where that
        /// name alone isn't enough. "American", "Southern" and "Northeast" are ordinary words ("All-American",
        /// "Southern Miss", "Mid-American"), so only their long forms count; "West Coast" likewise ("on the West
        /// Coast"); the independents are no conference. Every other conference: its name. Network names ("SEC
        /// Network") name their conference too (accepted).
        static let conferencePhrases: [String: [String]] = [
            "American": ["American Athletic", "AAC"],
            "Southern": ["Southern Conference", "SoCon"],
            "Northeast": ["Northeast Conference", "NEC"],
            "West Coast": ["West Coast Conference", "WCC"],
            "Mid-American": ["Mid-American", "MAC"],
            "Atlantic Sun": ["Atlantic Sun", "ASUN"],
            "Conference USA": ["Conference USA", "C-USA", "CUSA"],
            "Mountain West": ["Mountain West", "MWC"],
            "Big Ten": ["Big Ten", "B1G"],
            "Missouri Valley Football": ["Missouri Valley Football", "MVFC"],
            "Pioneer Football League": ["Pioneer Football League", "Pioneer League"],
            "UAC": ["UAC", "United Athletic Conference"],
            "CAA": ["CAA", "Coastal Athletic"],
            "FBS Independents": [],
            "FCS Independents": [],
        ]

        /// The normalized phrases that name `conference` ("Big Sky (FCS)" → `[" big sky "]`).
        static func phrases(naming conference: String) -> [String] {
            let label = (conference.firstIndex(of: "(").map { String(conference[..<$0]) } ?? conference)
                .trimmingCharacters(in: .whitespaces)
            return (conferencePhrases[label] ?? [label]).map(TeamMatcher.normalized).filter { !TeamMatcher.isBlank($0) }
        }

        /// M7m L29: the bundled catalog's index for `options`, built on first use (about 40 ms with the fallback's
        /// tables, -O) and kept; one per combination of the options, thread-safe.
        static func bundled(_ options: TeamMatchOptions) -> Index {
            switch (options.initials, options.nicknames) {
            case (false, false): bundledOff
            case (true, false): bundledInitials
            case (false, true): bundledNicknames
            case (true, true): bundledBoth
            }
        }

        private static let bundledOff = Index(teams: TeamCatalog.teams, options: .off)
        private static let bundledInitials = Index(teams: TeamCatalog.teams, options: .init(initials: true))
        private static let bundledNicknames = Index(teams: TeamCatalog.teams, options: .init(nicknames: true))
        private static let bundledBoth = Index(teams: TeamCatalog.teams,
                                               options: .init(initials: true, nicknames: true))

        /// M7m L29: builds `bundled(options)` off the main actor (at launch, and when an option changes), so the
        /// first match on the main actor doesn't pay for it.
        static func prepareBundled(_ options: TeamMatchOptions) {
            Task.detached(priority: .utility) { _ = bundled(options) }
        }

        static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BB}"]

        /// `text` without apostrophes, normalized: "Hawai'i" → `hawaii`, "St. John's" → `st johns`.
        static func normalizedWithoutApostrophes(_ text: String) -> String {
            TeamMatcher.normalized(String(text.filter { !apostrophes.contains($0) }))
        }

        /// Each text normalized, and normalized without apostrophes; blank ones left out.
        static func keys(_ texts: [String]) -> Set<String> {
            Set(texts.flatMap { [TeamMatcher.normalized($0), normalizedWithoutApostrophes($0)] })
                .filter { !TeamMatcher.isBlank($0) }
        }

        init(teams: [Team], options: TeamMatchOptions = .off) {
            self.teams = teams
            self.options = options
            byID = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var proFullNames: [String: Team] = [:]
            var named: [TeamLeague: [String: [Team]]] = [:]
            var schools: [String: Set<String>] = [:]
            var nicknames: [TeamLeague: [String: [Team]]] = [:]
            var maxNicknameWords = 0
            var schoolWords: [Team.ID: Set<String>] = [:]
            var conferences: [Team.ID: [String]] = [:]
            for team in teams {
                if team.league.isCollege {
                    let school = TeamMatcher.normalized(team.school ?? team.name)
                    let forms = [team.school].compactMap { $0 } + team.aliases
                        + (options.initials ? team.abbreviations : [])
                    let combined = team.nickname.isEmpty ? [] : forms.map { "\($0) \(team.nickname)" }
                    for key in Index.keys([team.name] + forms + combined) {
                        named[team.league, default: [:]][key, default: []].append(team)
                        schools[key, default: []].insert(school)
                    }
                    guard options.nicknames else { continue }
                    for nickname in Index.keys([team.nickname]) {
                        nicknames[team.league, default: [:]][nickname, default: []].append(team)
                        maxNicknameWords = max(maxNicknameWords, nickname.split(separator: " ").count)
                    }
                    // "Louisiana-Monroe" is two words; "Hawai'i" is one.
                    let multiWord = team.aliases.filter {
                        Index.normalizedWithoutApostrophes($0).split(separator: " ").count > 1
                    }
                    schoolWords[team.id] = Set(Index.keys([team.school].compactMap { $0 } + multiWord)
                        .flatMap { $0.split(separator: " ").map(String.init) }
                        .filter { $0.count >= 3 && !Index.schoolStopWords.contains($0) })
                    if let conference = team.conference {
                        let phrases = Index.phrases(naming: conference)
                        if !phrases.isEmpty { conferences[team.id] = phrases }
                    }
                } else {
                    for name in team.fullNames { proFullNames[TeamMatcher.normalized(name)] = team }
                }
            }
            self.proFullNames = proFullNames
            collegeNames = named
            collegeSchools = schools
            collegeNicknames = nicknames
            self.maxNicknameWords = maxNicknameWords
            collegeSchoolWords = schoolWords
            collegeConferences = conferences
        }
    }
}
