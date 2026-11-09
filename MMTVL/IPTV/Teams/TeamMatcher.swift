import Foundation

/// M7f L13: which channels show the picked teams now. Game entries by name, network channels by the programme on now.
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
    static func isGameEntry(_ channel: Channel, index: Index = .bundled) -> Bool {
        gameEntry(channel, index: index) != nil
    }

    /// The game a channel is the entry of (see `isGameEntry`), else nil.
    static func gameEntry(_ channel: Channel, index: Index = .bundled) -> Game? {
        guard !channel.group.lowercased().contains("replay"), let game = game(from: channel.name) else { return nil }
        func isKnown(_ side: String) -> Bool {
            team(named: side, index: index) != nil || index.collegeSchools[normalized(side)] != nil
        }
        return isKnown(game.away) || isKnown(game.home) ? game : nil
    }

    /// "Miami Heat @ Los Angeles Lakers (Home Feed)" → away "Miami Heat", home "Los Angeles Lakers", feed home.
    static func game(from name: String) -> Game? {
        var base = name
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
    static func team(named name: String, index: Index = .bundled) -> Team? {
        index.proFullNames[normalized(name)]
    }

    /// The away team, then the home team, of a game entry (only pro teams found; a college entry doesn't say its
    /// sport).
    static func teams(inGame channel: Channel, index: Index = .bundled) -> [Team] {
        guard let game = gameEntry(channel, index: index) else { return [] }
        return [team(named: game.away, index: index), team(named: game.home, index: index)].compactMap { $0 }
    }

    /// Teams a programme is about, among every catalog team (the channel menu).
    static func teams(in programme: Programme, index: Index = .bundled) -> [Team] {
        teams(in: programme, among: index.teams, index: index)
    }

    /// Teams of `candidates` a programme is about. College (M7l L10): the sport from the title and category, the two
    /// sides of the subtitle matched exactly against that league's names. Pro: a full name or alias in its title or
    /// subtitle, or (outside college programmes) a nickname there with a league word in its title, subtitle or
    /// category.
    static func teams(in programme: Programme, among candidates: [Team], index: Index = .bundled) -> [Team] {
        var found: [Team] = []
        let league = collegeLeague(of: programme)
        if let league, let names = index.collegeNames[league] {
            let ids = Set(candidates.map(\.id))
            found += collegeSides(of: programme).compactMap { names[$0] }.filter { ids.contains($0.id) }
        }
        let text = normalized([programme.title, programme.subtitle ?? ""].joined(separator: " "))
        let leagueText = normalized([programme.title, programme.subtitle ?? "", programme.category ?? ""].joined(separator: " "))
        let title = normalized(programme.title)
        // "basketball" in "College Basketball" isn't the NBA's.
        let isCollegeProgramme = league != nil || title.contains(" college ") || title.contains(" ncaa")
        found += candidates.filter { team in
            guard !team.league.isCollege else { return false }
            // A one-word full name ("Athletics") is only a nickname: it needs a league word too.
            let nickname = normalized(team.nickname)
            if team.fullNames.contains(where: { normalized($0) != nickname && text.contains(normalized($0)) }) { return true }
            return !isCollegeProgramme && text.contains(nickname)
                && team.league.words.contains { leagueText.contains(" \($0) ") }
        }
        return found
    }

    /// M7l L10: the college sport a programme's title and category name, or nil.
    static func collegeLeague(of programme: Programme) -> TeamLeague? {
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
    /// Empty unless there are exactly two.
    static func collegeSides(of programme: Programme) -> [String] {
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

    /// A normalized text with no words.
    static func isBlank(_ normalized: String) -> Bool {
        normalized.allSatisfy { $0 == " " }
    }

    /// Whether a programme on now counts for the Teams group (not a pregame show, a replay…).
    static func isLiveGame(_ programme: Programme) -> Bool {
        let title = normalized(programme.title)
        return !excludedTitleWords.contains { title.contains(" \($0) ") }
    }

    /// The Teams group: game entries first (playlist order; per game, the picked team's feed first), then network
    /// channels whose programme on now is about a picked team (playlist order).
    static func channelIDs(channels: [Channel], nowPlaying: [Channel.ID: Programme], picked: Set<Team.ID>,
                           index: Index = .bundled) -> [Channel.ID] {
        guard !picked.isEmpty else { return [] }
        return gameChannelIDs(channels: channels, picked: picked, index: index)
            + networkChannelIDs(channels: channels, nowPlaying: nowPlaying, picked: picked, index: index)
    }

    /// Each side of a game entry is a pro team by its full name, else (M7l L10) a college school, which counts when
    /// that school is picked in any college sport.
    static func gameChannelIDs(channels: [Channel], picked: Set<Team.ID>, index: Index = .bundled) -> [Channel.ID] {
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
                                  picked: Set<Team.ID>, index: Index = .bundled) -> [Channel.ID] {
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
    /// Each distinct title, subtitle and category is matched once.
    static func upcomingGames(channels: [Channel], programmes: [Channel.ID: [Programme]], picked: Set<Team.ID>,
                              now: Date, index: Index = .bundled) -> [UpcomingTeamGame] {
        let candidates = picked.compactMap { index.byID[$0] }
        guard !candidates.isEmpty else { return [] }
        let end = now + upcomingWindow
        var matches: [String: Bool] = [:]
        func isAboutPicked(_ programme: Programme) -> Bool {
            let key = [programme.title, programme.subtitle ?? "", programme.category ?? ""].joined(separator: "\u{1F}")
            if let known = matches[key] { return known }
            let found = isLiveGame(programme) && !teams(in: programme, among: candidates, index: index).isEmpty
            matches[key] = found
            return found
        }
        var games: [(order: Int, game: UpcomingTeamGame)] = []
        for (order, channel) in channels.enumerated() where !isGameEntry(channel, index: index) {
            var seen: Set<Date> = []
            for programme in programmes[channel.id] ?? []
            where programme.start > now && programme.start < end && isAboutPicked(programme) && seen.insert(programme.start).inserted {
                games.append((order, UpcomingTeamGame(channel: channel, programme: programme)))
            }
        }
        return games.sorted { ($0.game.programme.start, $0.order) < ($1.game.programme.start, $1.order) }.map(\.game)
    }

    /// The names the matcher looks teams up by, built once from a catalog (tests build their own).
    nonisolated struct Index: Sendable {
        let teams: [Team]
        let byID: [Team.ID: Team]
        /// Pro: every full name and alias, normalized → its team.
        let proFullNames: [String: Team]
        /// College, per league: `name`, `school` and aliases, normalized → the one team with it (a name two teams
        /// of a league share is left out).
        let collegeNames: [TeamLeague: [String: Team]]
        /// College, any league: a name, normalized → the normalized school it names (game entries, L10).
        let collegeSchools: [String: Set<String>]

        static let bundled = Index(teams: TeamCatalog.teams)

        init(teams: [Team]) {
            self.teams = teams
            byID = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var proFullNames: [String: Team] = [:]
            var named: [TeamLeague: [String: [Team]]] = [:]
            var schools: [String: Set<String>] = [:]
            for team in teams {
                if team.league.isCollege {
                    let school = TeamMatcher.normalized(team.school ?? team.name)
                    let keys = Set(([team.name, team.school ?? ""] + team.aliases).map(TeamMatcher.normalized))
                        .filter { !TeamMatcher.isBlank($0) }
                    for key in keys {
                        named[team.league, default: [:]][key, default: []].append(team)
                        schools[key, default: []].insert(school)
                    }
                } else {
                    for name in team.fullNames { proFullNames[TeamMatcher.normalized(name)] = team }
                }
            }
            self.proFullNames = proFullNames
            collegeNames = named.mapValues { names in
                names.compactMapValues { teams in teams.count == 1 ? teams[0] : nil }
            }
            // A name that could be two schools names neither.
            collegeSchools = schools.filter { $0.value.count == 1 }
        }
    }
}
