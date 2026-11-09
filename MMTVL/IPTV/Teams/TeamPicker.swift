import Foundation

/// M7l L12: the guide's Choose Teams, a stack of `LiveMenu`s. Pure: `LiveTVModel` keeps one while it's open, pushes
/// a level on Select, pops on Back and rebuilds the top level's menu after a team is toggled.
/// Level 1 lists the 8 leagues; a pro league lists its teams; a college league its conferences, then their teams.
nonisolated struct TeamPicker: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case leagues
        case league(TeamLeague)
        case conference(TeamLeague, String)

        /// The parent level's action that opens this level (nil for level 1).
        var openAction: LiveMenuAction? {
            switch self {
            case .leagues: nil
            case .league(let league): .openTeamLeague(league)
            case .conference(let league, let conference): .openTeamConference(league, conference)
            }
        }
    }

    static let title = "Choose Teams"
    /// A picked team's value.
    static let pickedValue = "In My Teams"

    /// Starts at level 1; never empty.
    private(set) var path: [Level] = [.leagues]

    var level: Level { path.last ?? .leagues }

    /// The top level's menu, its values from `picked`.
    func menu(picked: Set<Team.ID>, focusedIndex: Int = 0) -> LiveMenu {
        switch level {
        case .leagues:
            let items = TeamLeague.allCases.map { league in
                LiveMenu.Item(id: "league.\(league.rawValue)", title: league.title,
                              value: Self.onCountLabel(TeamCatalog.teams(in: league), picked: picked),
                              action: .openTeamLeague(league))
            }
            return LiveMenu(title: Self.title, items: items, focusedIndex: focusedIndex)
        case .league(let league) where league.isCollege:
            let items = TeamCatalog.conferences(in: league).map { conference in
                LiveMenu.Item(id: "conference.\(league.rawValue).\(conference)", title: conference,
                              value: Self.onCountLabel(TeamCatalog.teams(in: league, conference: conference),
                                                       picked: picked),
                              action: .openTeamConference(league, conference))
            }
            return LiveMenu(title: league.title, items: items, focusedIndex: focusedIndex)
        case .league(let league):
            return LiveMenu(title: league.title, items: Self.teamItems(TeamCatalog.teams(in: league), picked: picked),
                            focusedIndex: focusedIndex)
        case .conference(let league, let conference):
            return LiveMenu(title: conference,
                            items: Self.teamItems(TeamCatalog.teams(in: league, conference: conference), picked: picked),
                            focusedIndex: focusedIndex)
        }
    }

    mutating func push(_ level: Level) {
        path.append(level)
    }

    /// Back: true when a level was left; false on level 1 (close the picker).
    mutating func pop() -> Bool {
        guard path.count > 1 else { return false }
        path.removeLast()
        return true
    }

    /// "2 On" when any of `teams` are picked, else nil (the wording of Settings → Live TV → My Teams, M7l L13).
    static func onCountLabel(_ teams: [Team], picked: Set<Team.ID>) -> String? {
        let count = teams.count { picked.contains($0.id) }
        return count == 0 ? nil : "\(count) On"
    }

    private static func teamItems(_ teams: [Team], picked: Set<Team.ID>) -> [LiveMenu.Item] {
        teams.map { team in
            LiveMenu.Item(id: "team.\(team.id)", title: team.name,
                          value: picked.contains(team.id) ? pickedValue : nil, action: .toggleTeam(team.id))
        }
    }
}
