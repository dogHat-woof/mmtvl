import Testing
@testable import MMTVL

/// M7l L12: the guide's Choose Teams levels, on the bundled catalog.
struct TeamPickerTests {
    private static let michigan = "ncaaf.michigan-wolverines"

    @Test func levelOneListsTheEightLeaguesWithOnCounts() {
        let picked: Set<Team.ID> = ["nba.lal", "nba.bos", Self.michigan]
        let menu = TeamPicker().menu(picked: picked)
        #expect(menu.title == "Choose Teams")
        #expect(menu.items.map(\.title) == TeamLeague.allCases.map(\.title))
        #expect(menu.items.map(\.action) == TeamLeague.allCases.map { .openTeamLeague($0) })
        let values = Dictionary(uniqueKeysWithValues: menu.items.map { ($0.id, $0.value) })
        #expect(values["league.nba"] == "2 On")
        #expect(values["league.ncaaf"] == "1 On")
        #expect(values["league.nfl"] == .some(nil))
        #expect(values["league.ncaaw"] == .some(nil))
    }

    @Test func aCollegeLeagueListsConferencesThenTeams() {
        var picker = TeamPicker()
        picker.push(.league(.ncaaf))
        let picked: Set<Team.ID> = [Self.michigan]
        let conferences = picker.menu(picked: picked)
        #expect(conferences.title == "College Football")
        #expect(conferences.items.map(\.title) == TeamCatalog.conferences(in: .ncaaf))
        let bigTen = conferences.items.first { $0.title == "Big Ten" }
        #expect(bigTen?.value == "1 On")
        #expect(bigTen?.action == .openTeamConference(.ncaaf, "Big Ten"))
        #expect(conferences.items.filter { $0.title != "Big Ten" }.allSatisfy { $0.value == nil })

        picker.push(.conference(.ncaaf, "Big Ten"))
        let teams = picker.menu(picked: picked)
        #expect(teams.title == "Big Ten")
        #expect(teams.items.map(\.title) == TeamCatalog.teams(in: .ncaaf, conference: "Big Ten").map(\.name))
        let michigan = teams.items.first { $0.action == .toggleTeam(Self.michigan) }
        #expect(michigan?.title == "Michigan Wolverines")
        #expect(michigan?.value == "In My Teams")
        #expect(teams.items.filter { $0.action != .toggleTeam(Self.michigan) }.allSatisfy { $0.value == nil })
    }

    @Test func popReturnsToTheParentAndFalseOnLevelOne() {
        var picker = TeamPicker()
        picker.push(.league(.ncaam))
        picker.push(.conference(.ncaam, "ACC"))
        let leftConference = picker.pop()
        #expect(leftConference)
        #expect(picker.level == .league(.ncaam))
        #expect(picker.menu(picked: []).title == "College Basketball")
        let leftLeague = picker.pop()
        #expect(leftLeague)
        #expect(picker.level == .leagues)
        let leftLevelOne = picker.pop()
        #expect(!leftLevelOne)
        #expect(picker.path == [.leagues])
    }

    @Test func aProLeagueGoesStraightToTeams() {
        var picker = TeamPicker()
        picker.push(.league(.nba))
        let menu = picker.menu(picked: ["nba.lal"], focusedIndex: 3)
        #expect(menu.title == "NBA")
        #expect(menu.items.map(\.title) == TeamCatalog.teams(in: .nba).map(\.name))
        #expect(menu.items.allSatisfy { if case .toggleTeam = $0.action { true } else { false } })
        #expect(menu.items.first { $0.action == .toggleTeam("nba.lal") }?.value == "In My Teams")
        #expect(menu.focusedIndex == 3)
    }
}
