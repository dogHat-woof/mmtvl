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

    /// Game groups: "Live-Games", "NBA Games"; never a Replays group.
    static func isGameGroup(_ group: String) -> Bool {
        let lowered = group.lowercased()
        return lowered.contains("games") && !lowered.contains("replay")
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

    /// The team whose full name or an alias is exactly `name` (case and punctuation aside).
    static func team(named name: String) -> Team? {
        let key = normalized(name)
        return fullNameIndex[key]
    }

    /// The away team, then the home team, of a game entry (only those found).
    static func teams(inGame channel: Channel) -> [Team] {
        guard isGameGroup(channel.group), let game = game(from: channel.name) else { return [] }
        return [team(named: game.away), team(named: game.home)].compactMap { $0 }
    }

    /// Teams a programme is about: a full name or alias in its title or subtitle, or a nickname there with a league
    /// word in its title, subtitle or category.
    static func teams(in programme: Programme) -> [Team] {
        let text = normalized([programme.title, programme.subtitle ?? ""].joined(separator: " "))
        let leagueText = normalized([programme.title, programme.subtitle ?? "", programme.category ?? ""].joined(separator: " "))
        return TeamCatalog.teams.filter { team in
            // A one-word full name ("Athletics") is only a nickname: it needs a league word too.
            let nickname = normalized(team.nickname)
            if team.fullNames.contains(where: { normalized($0) != nickname && text.contains(normalized($0)) }) { return true }
            return text.contains(nickname)
                && team.league.words.contains { leagueText.contains(" \($0) ") }
        }
    }

    /// Whether a programme on now counts for the Teams group (not a pregame show, a replay…).
    static func isLiveGame(_ programme: Programme) -> Bool {
        let title = normalized(programme.title)
        return !excludedTitleWords.contains { title.contains(" \($0) ") }
    }

    /// The Teams group: game entries first (playlist order; per game, the picked team's feed first), then network
    /// channels whose programme on now is about a picked team (playlist order).
    static func channelIDs(channels: [Channel], nowPlaying: [Channel.ID: Programme], picked: Set<Team.ID>) -> [Channel.ID] {
        guard !picked.isEmpty else { return [] }
        return gameChannelIDs(channels: channels, picked: picked)
            + networkChannelIDs(channels: channels, nowPlaying: nowPlaying, picked: picked)
    }

    static func gameChannelIDs(channels: [Channel], picked: Set<Team.ID>) -> [Channel.ID] {
        // Feeds of one game, grouped by "away @ home", in order of the game's first entry.
        var order: [String] = []
        var feeds: [String: [(channel: Channel, preferred: Bool)]] = [:]
        for channel in channels where isGameGroup(channel.group) {
            guard let game = game(from: channel.name) else { continue }
            let away = team(named: game.away).map { picked.contains($0.id) } ?? false
            let home = team(named: game.home).map { picked.contains($0.id) } ?? false
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

    static func networkChannelIDs(channels: [Channel], nowPlaying: [Channel.ID: Programme],
                                  picked: Set<Team.ID>) -> [Channel.ID] {
        channels.compactMap { channel in
            guard !isGameGroup(channel.group), let programme = nowPlaying[channel.id], isLiveGame(programme),
                  teams(in: programme).contains(where: { picked.contains($0.id) })
            else { return nil }
            return channel.id
        }
    }

    private static let fullNameIndex: [String: Team] = {
        var index: [String: Team] = [:]
        for team in TeamCatalog.teams {
            for name in team.fullNames { index[normalized(name)] = team }
        }
        return index
    }()
}
