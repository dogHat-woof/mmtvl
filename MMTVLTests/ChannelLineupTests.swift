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
        #expect(lineup.groups == ["All Channels", "Live Channels", "NBA Games"])
        #expect(lineup.favorites.isEmpty)
        #expect(lineup.visibleChannels.count == 5)
        #expect(lineup.channels(in: "All Channels").count == 5)
        #expect(lineup.channels(in: "NBA Games").map(\.name) == ["Lakers @ Celtics", "Knicks @ Heat"])
        #expect(lineup.channels(in: "Nope").isEmpty)
    }

    @Test func favoritesComeFirstInTheOrderAdded() throws {
        let lineup = ChannelLineup(channels: try channels, preferences: ChannelPreferences(favorites: [Self.nba, Self.nfl]))
        #expect(lineup.groups == ["Favorites", "All Channels", "Live Channels", "NBA Games"])
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
        #expect(lineup.groups == ["Live Channels"])
        #expect(lineup.visibleChannels.map(\.name) == ["NFL Network", "NBA TV", "Red Zone"])
        #expect(lineup.channels(in: "NBA Games").isEmpty)
    }

    @Test func unknownFavoritesAreIgnored() throws {
        let lineup = ChannelLineup(channels: try channels,
                                   preferences: ChannelPreferences(favorites: ["id:gone", Self.redZone]))
        #expect(lineup.favorites.map(\.name) == ["Red Zone"])
        let none = ChannelLineup(channels: try channels, preferences: ChannelPreferences(favorites: ["id:gone"]))
        #expect(none.groups.first == "All Channels")
    }

    @Test func tolerantDecoding() throws {
        let json = #"{"favorites": 3, "hiddenGroups": ["x"]}"#
        let preferences = try JSONDecoder().decode(ChannelPreferences.self, from: Data(json.utf8))
        #expect(preferences == ChannelPreferences(hiddenGroups: ["x"]))
        #expect(try JSONDecoder().decode(ChannelPreferences.self, from: Data("{}".utf8)) == ChannelPreferences())
    }
}
