import Foundation
import Testing
@testable import MMTVL

/// M6b L5, L11.
struct ChannelLineupTests {
    private static let nfl = "id:nflnetwork.us"
    private static let nba = "id:nbatv.us"
    private static let redZone = "name:red zone"

    private var channels: [Channel] {
        get throws { ChannelList.make(from: try M3UParser.parse(IPTVFixtures.playlist)) }
    }

    @Test func noPreferencesKeepsTheGroups() throws {
        let lineup = ChannelLineup(channels: try channels)
        #expect(lineup.groups == ["My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.favorites.isEmpty)
        #expect(lineup.visibleChannels.count == 5)
        #expect(lineup.channels(in: "All Channels").count == 5)
        #expect(lineup.channels(in: "NBA Games").map(\.name) == ["Lakers @ Celtics", "Knicks @ Heat"])
        #expect(lineup.channels(in: "Nope").isEmpty)
    }

    @Test func favoritesComeFirstInTheOrderAdded() throws {
        let lineup = ChannelLineup(channels: try channels, preferences: ChannelPreferences(favorites: [Self.nba, Self.nfl]))
        #expect(lineup.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["NBA TV", "NFL Network"])
    }

    @Test func hiddenFavoriteIsNotAFavorite() throws {
        let lineup = ChannelLineup(channels: try channels,
                                   preferences: ChannelPreferences(favorites: [Self.nba, Self.nfl], hiddenChannels: [Self.nba]))
        #expect(lineup.favorites.map(\.name) == ["NFL Network"])
        #expect(!lineup.isVisible(Self.nba))
        #expect(lineup.isVisible(Self.nfl))
        #expect(!lineup.visibleChannels.contains { $0.id == Self.nba })
        #expect(!lineup.channels(in: "Live Channels").contains { $0.id == Self.nba })
    }

    @Test func hidingAGroup() throws {
        let lineup = ChannelLineup(channels: try channels, preferences: ChannelPreferences(hiddenGroups: ["NBA Games"]))
        // One visible group left, so no All Channels.
        #expect(lineup.groups == ["My Teams", "Live Channels"])
        #expect(lineup.visibleChannels.map(\.name) == ["NFL Network", "NBA TV", "Red Zone"])
        #expect(lineup.channels(in: "NBA Games").isEmpty)
    }

    @Test func unknownFavoritesAreIgnored() throws {
        let lineup = ChannelLineup(channels: try channels,
                                   preferences: ChannelPreferences(favorites: ["id:gone", Self.redZone]))
        #expect(lineup.favorites.map(\.name) == ["Red Zone"])
        let none = ChannelLineup(channels: try channels, preferences: ChannelPreferences(favorites: ["id:gone"]))
        #expect(none.groups.first == "My Teams")
    }

    // MARK: M7l 8b: live team games top Favorites

    @Test func teamChannelsComeFirstInFavorites() throws {
        let channels = try channels
        let games = channels.filter { $0.group == "NBA Games" }.map(\.id)
        let preferences = ChannelPreferences(favorites: [Self.nba, Self.nfl])
        let lineup = ChannelLineup(channels: channels, preferences: preferences, teamChannelIDs: games)
        #expect(lineup.groups.prefix(3) == ["Favorites", "My Teams", "All Channels"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["Lakers @ Celtics", "Knicks @ Heat", "NBA TV", "NFL Network"])
        // The My Teams group and the saved favorites are unchanged.
        #expect(lineup.channels(in: "My Teams").map(\.id) == games)
        #expect(lineup.favorites.map(\.name) == ["NBA TV", "NFL Network"])
        #expect(preferences.favorites == [Self.nba, Self.nfl])
    }

    @Test func aTeamChannelThatIsAFavoriteShowsOnceAtTheTop() throws {
        let preferences = ChannelPreferences(favorites: [Self.nba, Self.redZone, Self.nfl])
        let lineup = ChannelLineup(channels: try channels, preferences: preferences, teamChannelIDs: [Self.nfl])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["NFL Network", "NBA TV", "Red Zone"])
        #expect(lineup.favorites.map(\.name) == ["NBA TV", "Red Zone", "NFL Network"])
    }

    @Test func liveTeamGamesAloneMakeAFavoritesGroup() throws {
        let lineup = ChannelLineup(channels: try channels, teamChannelIDs: [Self.redZone])
        #expect(lineup.groups.prefix(2) == ["Favorites", "My Teams"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["Red Zone"])
        #expect(lineup.favorites.isEmpty)
        // Hidden team channels don't count.
        let hidden = ChannelLineup(channels: try channels, preferences: ChannelPreferences(hiddenChannels: [Self.redZone]),
                                   teamChannelIDs: [Self.redZone])
        #expect(!hidden.groups.contains("Favorites"))
    }

    @Test func withoutTeamGamesFavoritesIsAsBefore() throws {
        let preferences = ChannelPreferences(favorites: [Self.nba, Self.nfl])
        let lineup = ChannelLineup(channels: try channels, preferences: preferences, teamChannelIDs: [])
        #expect(lineup == ChannelLineup(channels: try channels, preferences: preferences))
        #expect(lineup.groups == ["Favorites", "My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.channels(in: "Favorites").map(\.name) == ["NBA TV", "NFL Network"])
        #expect(lineup.channels(in: "Favorites") == lineup.favorites)
    }

    @Test func tolerantDecoding() throws {
        let json = #"{"favorites": 3, "hiddenGroups": ["x"]}"#
        let preferences = try JSONDecoder().decode(ChannelPreferences.self, from: Data(json.utf8))
        #expect(preferences == ChannelPreferences(hiddenGroups: ["x"]))
        #expect(try JSONDecoder().decode(ChannelPreferences.self, from: Data("{}".utf8)) == ChannelPreferences())
    }
}
