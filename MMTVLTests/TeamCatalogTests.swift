import Foundation
import Testing
@testable import MMTVL

/// M7l L6–L8, L11, L13: the college catalog (`college-teams.json`), its decoding, titles and conference order.
struct TeamCatalogTests {
    static let fixture = """
    [
      { "aliases": ["Michigan"], "conference": "Big Ten", "id": "ncaaw.michigan-wolverines", "league": "ncaaw",
        "name": "Michigan Wolverines", "nickname": "Wolverines", "school": "Michigan" },
      { "aliases": ["Grambling", "Grambling State"], "conference": "SWAC (FCS)", "id": "ncaaf.grambling-tigers",
        "league": "ncaaf", "name": "Grambling Tigers", "nickname": "Tigers", "school": "Grambling" },
      { "conference": "Big East", "id": "ncaam.duke-blue-devils", "league": "ncaam", "name": "Duke Blue Devils",
        "nickname": "Blue Devils", "school": "Duke" },
      { "aliases": [], "conference": "X", "id": "xfl.team", "league": "xfl", "name": "Unknown League",
        "nickname": "U", "school": "U" },
      { "aliases": [], "conference": "X", "id": "nba.lal", "league": "nba", "name": "A Pro League",
        "nickname": "P", "school": "P" },
      { "aliases": [], "conference": "X", "id": "ncaam.wrong-league", "league": "ncaaf", "name": "Wrong Prefix",
        "nickname": "W", "school": "W" },
      { "aliases": [], "conference": "Big Ten", "id": "ncaaw.michigan-wolverines", "league": "ncaaw",
        "name": "Duplicate", "nickname": "D", "school": "D" }
    ]
    """

    @Test func theBundledCatalogLoads() {
        let college = TeamCatalog.collegeTeams
        for league in TeamLeague.allCases where league.isCollege {
            #expect(TeamCatalog.teams(in: league).count > 200, "\(league)")
            #expect(!TeamCatalog.conferences(in: league).isEmpty, "\(league)")
        }
        #expect(college.allSatisfy { $0.league.isCollege && $0.id.hasPrefix("\($0.league.rawValue).") })
        #expect(college.allSatisfy { $0.school?.isEmpty == false && $0.conference?.isEmpty == false })
        // Pro teams first, every id once.
        #expect(Array(TeamCatalog.teams.prefix(TeamCatalog.proTeams.count)) == TeamCatalog.proTeams)
        #expect(TeamCatalog.teams.count == TeamCatalog.proTeams.count + college.count)
        #expect(Set(TeamCatalog.teams.map(\.id)).count == TeamCatalog.teams.count)
        #expect(TeamCatalog.byID["ncaaf.michigan-wolverines"]?.conference == "Big Ten")
        #expect(TeamCatalog.teams(in: .ncaaf, conference: "Big Ten").contains { $0.id == "ncaaf.michigan-wolverines" })
    }

    @Test func fixtureEntriesDecode() throws {
        let teams = try TeamCatalog.collegeTeams(fromJSON: Data(Self.fixture.utf8))
        // Unknown and pro leagues, an id outside its league and a repeated id are skipped.
        #expect(teams.map(\.id) == ["ncaaw.michigan-wolverines", "ncaaf.grambling-tigers", "ncaam.duke-blue-devils"])
        let michigan = teams[0]
        #expect(michigan.league == .ncaaw)
        #expect(michigan.name == "Michigan Wolverines")
        #expect(michigan.school == "Michigan")
        #expect(michigan.nickname == "Wolverines")
        #expect(michigan.conference == "Big Ten")
        #expect(michigan.aliases == ["Michigan"])
        #expect(michigan.pickTitle == "Michigan Wolverines (Women's Basketball)")
        #expect(teams[1].aliases == ["Grambling", "Grambling State"])
        #expect(teams[1].pickTitle == "Grambling Tigers (Football)")
        // Missing aliases read as none.
        #expect(teams[2].aliases == [])
        #expect(teams[2].pickTitle == "Duke Blue Devils (Basketball)")
        #expect(throws: (any Error).self) { try TeamCatalog.collegeTeams(fromJSON: Data("{}".utf8)) }
    }

    @Test func leagueTitles() {
        #expect(TeamLeague.allCases.filter(\.isCollege) == [.ncaaf, .ncaam, .ncaaw, .ncaabase])
        #expect(TeamLeague.allCases.map(\.title) == ["NFL", "NBA", "NHL", "MLB", "College Football", "College Basketball",
                                                     "Women's College Basketball", "College Baseball"])
        #expect(TeamLeague.ncaabase.sportTitle == "Baseball")
        #expect(TeamCatalog.byID["nba.lal"]?.pickTitle == "Los Angeles Lakers")
        #expect(TeamCatalog.byID["nba.lal"]?.school == nil)
    }

    @Test func footballConferencesListFBSBeforeFCS() {
        let conferences = TeamCatalog.conferences(in: .ncaaf)
        #expect(conferences.contains("Big Ten"))
        #expect(conferences.contains("Big Sky (FCS)"))
        let firstFCS = conferences.firstIndex(where: TeamCatalog.isFCS) ?? conferences.endIndex
        let fbs = Array(conferences[..<firstFCS])
        let fcs = Array(conferences[firstFCS...])
        #expect(!fbs.isEmpty && !fcs.isEmpty)
        #expect(!fbs.contains(where: TeamCatalog.isFCS))
        #expect(fcs.allSatisfy(TeamCatalog.isFCS))
        #expect(fcs.contains("FCS Independents"))
        #expect(fbs == fbs.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(fcs == fcs.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        // Basketball: alphabetical.
        let basketball = TeamCatalog.conferences(in: .ncaam)
        #expect(basketball.first == "ACC")
        #expect(basketball == basketball.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}
