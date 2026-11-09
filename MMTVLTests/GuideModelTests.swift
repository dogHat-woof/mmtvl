import Foundation
import Testing
@testable import MMTVL

struct GuideModelTests {
    private let now = GuideTimelineTests.utc(14, 47)

    private func channel(_ n: Int, group: String) -> Channel {
        Channel(id: "id:c\(n)", number: n, name: "Channel \(n)", group: group, tvgID: "c\(n)", tvgName: nil,
                logoURL: nil, streamURL: URL(string: "https://cdn/\(n).m3u8")!)
    }

    /// 10 channels: 1–6 "Live", 7–8 "NBA", 9–10 "NHL".
    private var channels: [Channel] {
        (1...10).map { channel($0, group: $0 <= 6 ? "Live" : ($0 <= 8 ? "NBA" : "NHL")) }
    }

    private func programme(_ channelID: String, _ startHour: Int, _ startMinute: Int, minutes: Int, _ title: String) -> Programme {
        let start = GuideTimelineTests.utc(startHour, startMinute)
        return Programme(channelID: channelID, start: start, stop: start + Double(minutes * 60), title: title)
    }

    /// Row 0 (c1): 14:00–15:00 A, 15:00–16:00 B, 16:00–17:30 C, 17:30–19:00 D.
    /// Row 1 (c2): 14:30–15:30 E, 15:30–16:30 F.
    private var programmes: [Channel.ID: [Programme]] {
        [
            "id:c1": [programme("c1", 14, 0, minutes: 60, "A"), programme("c1", 15, 0, minutes: 60, "B"),
                      programme("c1", 16, 0, minutes: 90, "C"), programme("c1", 17, 30, minutes: 90, "D")],
            "id:c2": [programme("c2", 14, 30, minutes: 60, "E"), programme("c2", 15, 30, minutes: 60, "F")],
        ]
    }

    private func model(group: String? = "Live", focused: Channel.ID? = nil) -> GuideModel {
        var model = GuideModel(allChannels: channels, group: group, focusedChannelID: focused, now: now)
        model.programmes = programmes
        return model
    }

    @Test func initFocusesTheChannelInTheRememberedGroup() {
        let model = model(group: "Live", focused: "id:c3")
        #expect(model.groups == ["All Channels", "Live", "NBA", "NHL"])
        #expect(model.selectedGroup == "Live")
        #expect(model.row == 2)
        #expect(model.focusedChannel?.id == "id:c3")
        #expect(model.focus == .grid)
        #expect(model.focusTime == now)
    }

    @Test func initFallsBackToAllChannels() {
        let model = model(group: "NBA", focused: "id:c10")
        #expect(model.selectedGroup == "All Channels")
        #expect(model.row == 9)
        #expect(model.firstVisibleRow + GuideModel.visibleRows > model.row)
    }

    @Test func favoritesAreTheDefaultGroup() {
        let lineup = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: ["id:c9", "id:c2"]))
        let model = GuideModel(lineup: lineup, group: nil, focusedChannelID: "id:c2", now: now)
        #expect(model.groups == ["Favorites", "All Channels", "Live", "NBA", "NHL"])
        #expect(model.selectedGroup == "Favorites")
        #expect(model.channels.map(\.id) == ["id:c9", "id:c2"])
        #expect(model.row == 1)
    }

    @Test func focusedChannelOutsideFavoritesOpensAllChannels() {
        let lineup = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: ["id:c9"]))
        let model = GuideModel(lineup: lineup, group: nil, focusedChannelID: "id:c4", now: now)
        #expect(model.selectedGroup == "All Channels")
        #expect(model.focusedChannel?.id == "id:c4")

        // With one visible group there is no All Channels: its own group.
        let oneGroup = ChannelLineup(channels: channels,
                                     preferences: ChannelPreferences(favorites: ["id:c1"], hiddenGroups: ["NBA", "NHL"]))
        let other = GuideModel(lineup: oneGroup, group: nil, focusedChannelID: "id:c4", now: now)
        #expect(other.groups == ["Favorites", "Live"])
        #expect(other.selectedGroup == "Live")
        #expect(other.focusedChannel?.id == "id:c4")
    }

    @Test func setLineupThatDropsTheFocusedChannelKeepsTheRow() {
        var last = model(group: "Live", focused: "id:c6")
        #expect(last.row == 5)
        last.setLineup(ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenChannels: ["id:c6"])))
        #expect(last.selectedGroup == "Live")
        #expect(last.row == 4)
        #expect(last.focusedChannel?.id == "id:c5")

        var middle = model(group: "Live", focused: "id:c3")
        middle.setLineup(ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenChannels: ["id:c3"])))
        #expect(middle.row == 2)
        #expect(middle.focusedChannel?.id == "id:c4")
    }

    @Test func upDownClampAndScroll() {
        var model = model(group: "All Channels")
        _ = model.handle(.up, now: now)
        #expect(model.row == 0)
        for _ in 0..<7 { _ = model.handle(.down, now: now) }
        #expect(model.row == 7)
        #expect(model.firstVisibleRow == 2)
        for _ in 0..<5 { _ = model.handle(.down, now: now) }
        #expect(model.row == 9)
        for _ in 0..<7 { _ = model.handle(.up, now: now) }
        #expect(model.row == 2)
        #expect(model.firstVisibleRow == 2)
        _ = model.handle(.up, now: now)
        #expect(model.firstVisibleRow == 1)
    }

    @Test func rightWalksProgrammesAndMovesTheWindow() {
        var model = model()
        #expect(model.focusedCell(now: now)?.programme?.title == "A")
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "B")
        #expect(model.timeline.windowStart == GuideTimelineTests.utc(14, 30))
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "C")
        #expect(model.timeline.windowStart == GuideTimelineTests.utc(16, 0))
        _ = model.handle(.fastForward, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "D")
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "D")

        _ = model.handle(.left, now: now)
        _ = model.handle(.rewind, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "A")
        #expect(model.focusTime == now)
        #expect(model.timeline.windowStart == GuideTimelineTests.utc(14, 30))
        #expect(model.focus == .grid)

        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(1))
    }

    @Test func groups() {
        var model = model()
        _ = model.handle(.down, now: now)
        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(1))
        _ = model.handle(.down, now: now)
        #expect(model.focus == .groups(2))
        #expect(model.handle(.select, now: now) == .groupChanged("NBA"))
        #expect(model.focus == .grid)
        #expect(model.row == 0)
        #expect(model.channels.map(\.id) == ["id:c7", "id:c8"])

        // Back in groups → grid, no change.
        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        _ = model.handle(.up, now: now)
        #expect(model.handle(.back, now: now) == .none)
        #expect(model.focus == .grid)
        #expect(model.selectedGroup == "NBA")

        // Right applies too; Up stops at the Search row (M7f L12), Down from it returns to the first group.
        _ = model.handle(.left, now: now)   // the now-cell → the channel cell
        _ = model.handle(.left, now: now)
        for _ in 0..<6 { _ = model.handle(.up, now: now) }
        #expect(model.focus == .search)
        _ = model.handle(.down, now: now)
        #expect(model.focus == .groups(0))
        #expect(model.handle(.right, now: now) == .groupChanged("All Channels"))
        #expect(model.channels.count == 10)
    }

    @Test func rowWithoutProgrammesHasOnePlaceholder() {
        var model = model()
        for _ in 0..<2 { _ = model.handle(.down, now: now) }
        let cells = model.cells(row: 2, now: now)
        #expect(cells.count == 1)
        #expect(cells.first?.programme == nil)
        #expect(cells.first?.start == now)
        #expect(cells.first?.stop == now + GuideTimeline.horizon)
        let before = model
        _ = model.handle(.right, now: now)
        #expect(model == before)
    }

    @Test func selectPlaysAndBackCloses() {
        var model = model()
        _ = model.handle(.down, now: now)
        #expect(model.handle(.select, now: now) == .play("id:c2"))
        #expect(model.handle(.back, now: now) == .close)
        #expect(model.handle(.playPause, now: now) == .none)
    }

    @Test func upDownKeepFocusTime() {
        var model = model()
        _ = model.handle(.right, now: now)                    // B, 15:00
        #expect(model.focusTime == GuideTimelineTests.utc(15, 0))
        _ = model.handle(.down, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "E")   // 14:30–15:30 covers 15:00
        _ = model.handle(.right, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "F")
        _ = model.handle(.up, now: now)
        #expect(model.focusedCell(now: now)?.programme?.title == "B")   // 15:00–16:00 covers 15:30
    }

    @Test func programmesThatEndedAreNotCells() {
        var model = model()
        model.programmes["id:c1"]?.insert(programme("c1", 13, 0, minutes: 60, "Over"), at: 0)
        #expect(model.cells(row: 0, now: now).first?.programme?.title == "A")
    }

    @Test func setChannelsKeepsGroupAndRow() {
        var model = model(group: "Live", focused: "id:c4")
        let refreshed = channels.filter { $0.id != "id:c2" }
        model.setChannels(allChannels: refreshed)
        #expect(model.selectedGroup == "Live")
        #expect(model.focusedChannel?.id == "id:c4")
        #expect(model.row == 2)
    }

    // MARK: Channel cell (M6 L8)

    @Test func leftAtNowFocusesTheChannelThenTheGroups() {
        var model = model()
        #expect(model.handle(.left, now: now) == .none)
        #expect(model.focus == .channel)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .groups(1))
    }

    @Test func rightFromTheChannelReturnsToTheSameCell() {
        var model = model()
        _ = model.handle(.right, now: now)
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.focus == .channel)
        let time = model.focusTime
        _ = model.handle(.right, now: now)
        #expect(model.focus == .grid)
        #expect(model.focusTime == time)
        #expect(model.focusedCell(now: now)?.programme?.title == "A")
    }

    @Test func upDownOnTheChannelMoveRows() {
        var model = model()
        _ = model.handle(.left, now: now)
        _ = model.handle(.down, now: now)
        _ = model.handle(.down, now: now)
        #expect(model.row == 2)
        #expect(model.focus == .channel)
        _ = model.handle(.up, now: now)
        #expect(model.row == 1)
        #expect(model.focus == .channel)
    }

    @Test func selectOnTheChannelOpensItsMenu() {
        var model = model()
        _ = model.handle(.down, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.handle(.select, now: now) == .channelMenu("id:c2"))
    }

    @Test func backOnTheChannelCloses() {
        var model = model()
        _ = model.handle(.left, now: now)
        #expect(model.handle(.back, now: now) == .close)
        #expect(model.handle(.playPause, now: now) == .none)
    }

    // MARK: M7 L5

    @Test func menuOpensTheChannelMenuFromTheGridAndTheChannelCell() {
        var model = model(group: "Live", focused: "id:c3")
        #expect(model.handle(.menu, now: now) == .channelMenu("id:c3"))
        model = self.model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)          // A → the channel cell
        #expect(model.focus == .channel)
        #expect(model.handle(.menu, now: now) == .channelMenu("id:c1"))
    }

    @Test func menuInTheGroupsColumnDoesNothing() {
        var model = model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        #expect(model.handle(.menu, now: now) == .none)
    }

    @Test func channelUpDownPageTheRows() {
        var model = GuideModel(allChannels: channels, group: "All Channels", focusedChannelID: "id:c2", now: now)
        #expect(model.handle(.channelDown, now: now) == .none)
        #expect(model.focusedChannel?.id == "id:c8")
        #expect(model.firstVisibleRow == 2)
        _ = model.handle(.channelDown, now: now)
        #expect(model.focusedChannel?.id == "id:c10")
        _ = model.handle(.channelUp, now: now)
        #expect(model.focusedChannel?.id == "id:c4")
        _ = model.handle(.channelUp, now: now)
        #expect(model.focusedChannel?.id == "id:c1")
        #expect(model.firstVisibleRow == 0)
    }

    @Test func channelUpDownPageTheGroups() {
        var model = model(group: "Live", focused: "id:c1")
        _ = model.handle(.left, now: now)
        _ = model.handle(.left, now: now)
        guard case .groups = model.focus else {
            Issue.record("Not in the groups column")
            return
        }
        _ = model.handle(.channelDown, now: now)
        #expect(model.focus == .groups(model.groups.count - 1))
        _ = model.handle(.channelUp, now: now)
        #expect(model.focus == .groups(0))
    }

    // MARK: M7f L12

    @Test func theSearchRowOpensSearchAndKeepsTheGuide() {
        var model = model(group: "NBA", focused: "id:c8")
        _ = model.handle(.left, now: now)   // the channel cell
        _ = model.handle(.left, now: now)   // groups, on NBA
        #expect(model.focus == .groups(2))
        _ = model.handle(.up, now: now)
        _ = model.handle(.up, now: now)
        _ = model.handle(.up, now: now)
        #expect(model.focus == .search)
        #expect(model.handle(.up, now: now) == .none)
        #expect(model.handle(.select, now: now) == .openSearch)
        // The guide keeps its group and row; focus stays on the Search row.
        #expect(model.focus == .search)
        #expect(model.selectedGroup == "NBA")
        #expect(model.focusedChannel?.id == "id:c8")
        #expect(model.handle(.right, now: now) == .openSearch)
        #expect(model.handle(.back, now: now) == .none)
        #expect(model.focus == .grid)
    }

    @Test func focusOnALaterProgramme() {
        var model = model(group: "Live", focused: "id:c1")
        let later = GuideTimelineTests.utc(17, 30)
        // In the group: the row moves and the timeline shows the programme.
        let inGroup = model.focus(channelID: "id:c2", at: later, now: now)
        #expect(inGroup)
        #expect(model.selectedGroup == "Live")
        #expect(model.focusedChannel?.id == "id:c2")
        #expect(model.focus == .grid)
        #expect(model.focusTime == later)
        #expect(model.timeline.windowStart <= later && later < model.timeline.windowEnd)
        // Not in the group: All Channels.
        let inAllChannels = model.focus(channelID: "id:c10", at: later, now: now)
        #expect(inAllChannels)
        #expect(model.selectedGroup == "All Channels")
        #expect(model.focusedChannel?.id == "id:c10")
        #expect(model.firstVisibleRow + GuideModel.visibleRows > model.row)
        // A time before now focuses now; an unknown channel changes nothing.
        let beforeNow = model.focus(channelID: "id:c1", at: now - 3600, now: now)
        #expect(beforeNow)
        #expect(model.focusTime == now)
        let unknown = model.focus(channelID: "id:nope", at: later, now: now)
        #expect(!unknown)
        #expect(model.focusedChannel?.id == "id:c1")
    }
}
