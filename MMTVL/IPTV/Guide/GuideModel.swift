import Foundation

/// Guide focus and navigation (M4 L9, L12; M6 L8 channel cell). Pure: `LiveTVModel` feeds it commands and programmes.
nonisolated struct GuideModel: Equatable, Sendable {
    static let visibleRows = 6

    /// `.channel`: the channel cell of the focused row (M6 L8), between the grid and the groups.
    /// `.search` (M7f L12): the Search row above the groups.
    enum Focus: Equatable, Sendable { case grid, channel, groups(Int), search }
    enum Action: Equatable, Sendable {
        case none, play(Channel.ID), close, groupChanged(String), channelMenu(Channel.ID)
        /// M7f L12: Select on the Search row.
        case openSearch
    }
    /// One focusable cell: a programme, or a placeholder spanning the window when a row has no data.
    struct Cell: Equatable, Sendable {
        var programme: Programme?
        var start: Date
        var stop: Date
    }

    private(set) var groups: [String]
    private(set) var groupIndex: Int
    /// The selected group's.
    private(set) var channels: [Channel]
    /// Set by LiveTVModel after loading.
    var programmes: [Channel.ID: [Programme]] = [:]
    private(set) var focus: Focus = .grid
    private(set) var row = 0
    /// The time the focus aims at (≥ now).
    private(set) var focusTime: Date
    private(set) var firstVisibleRow = 0
    private(set) var timeline: GuideTimeline
    private var lineup: ChannelLineup

    /// The default group (no remembered one) is the first: Favorites when it exists (M6b L11).
    init(lineup: ChannelLineup, group: String?, focusedChannelID: Channel.ID?, now: Date) {
        self.lineup = lineup
        let groups = lineup.groups
        self.groups = groups
        groupIndex = group.flatMap { groups.firstIndex(of: $0) } ?? 0
        channels = []
        focusTime = now
        timeline = GuideTimeline(now: now)
        channels = channelsOfSelectedGroup()
        if let focusedChannelID, !channels.contains(where: { $0.id == focusedChannelID }) {
            // Show the focused channel: All Channels if there is one, else its own group.
            let channelGroup = lineup.visibleChannels.first { $0.id == focusedChannelID }?.group
            if let index = groups.firstIndex(of: ChannelList.allChannelsGroup)
                ?? channelGroup.flatMap({ groups.firstIndex(of: $0) }) {
                groupIndex = index
                channels = channelsOfSelectedGroup()
            }
        }
        row = focusedChannelID.flatMap { id in channels.firstIndex { $0.id == id } } ?? 0
        firstVisibleRow = min(row, max(0, channels.count - Self.visibleRows))
    }

    var selectedGroup: String? { groups.indices.contains(groupIndex) ? groups[groupIndex] : nil }

    var focusedChannel: Channel? { channels.indices.contains(row) ? channels[row] : nil }

    /// Cells of `row` overlapping [now, now + horizon), sorted; one placeholder cell [now, now + horizon) when none.
    func cells(row: Int, now: Date) -> [Cell] {
        let end = now + GuideTimeline.horizon
        guard channels.indices.contains(row) else { return [] }
        let cells = (programmes[channels[row].id] ?? [])
            .filter { $0.start < end && $0.stop > now }
            .sorted { $0.start < $1.start }
            .map { Cell(programme: $0, start: $0.start, stop: $0.stop) }
        return cells.isEmpty ? [Cell(programme: nil, start: now, stop: end)] : cells
    }

    /// The cell containing focusTime, else the first after it, else the last.
    func focusedCell(now: Date) -> Cell? {
        let cells = cells(row: row, now: now)
        return focusedCellIndex(in: cells).map { cells[$0] }
    }

    mutating func handle(_ command: RemoteCommand, now: Date) -> Action {
        switch focus {
        case .grid: handleGrid(command, now: now)
        case .channel: handleChannel(command)
        case .groups(let index): handleGroups(command, index: index, now: now)
        case .search: handleSearchRow(command)
        }
    }

    /// M7f L12: a search result for a later programme. Focus goes to `channelID` (All Channels if it isn't in the
    /// selected group, else its own group) at `date`. False when the channel isn't in the lineup.
    @discardableResult
    mutating func focus(channelID: Channel.ID, at date: Date, now: Date) -> Bool {
        if !channels.contains(where: { $0.id == channelID }) {
            guard lineup.visibleChannels.contains(where: { $0.id == channelID }) else { return false }
            let channelGroup = lineup.visibleChannels.first { $0.id == channelID }?.group
            let candidates = [ChannelList.allChannelsGroup] + [channelGroup].compactMap { $0 }
            let groups = groups, lineup = lineup
            guard let index = candidates.compactMap({ groups.firstIndex(of: $0) })
                .first(where: { lineup.channels(in: groups[$0]).contains { $0.id == channelID } })
            else { return false }
            groupIndex = index
            channels = channelsOfSelectedGroup()
            firstVisibleRow = 0
        }
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else { return false }
        row = index
        keepRowVisible()
        focus = .grid
        focusTime = max(date, now)
        timeline = GuideTimeline(now: now)
        timeline.reveal(focusTime, now: now)
        return true
    }

    /// Tests and callers without preferences.
    init(allChannels: [Channel], group: String?, focusedChannelID: Channel.ID?, now: Date) {
        self.init(lineup: ChannelLineup(channels: allChannels), group: group, focusedChannelID: focusedChannelID, now: now)
    }

    mutating func setChannels(allChannels: [Channel]) {
        setLineup(ChannelLineup(channels: allChannels))
    }

    /// After a playlist refresh or a favorites/hiding change: keep group/row by id where possible, else the row index.
    mutating func setLineup(_ lineup: ChannelLineup) {
        let focusedID = focusedChannel?.id
        let group = selectedGroup
        self.lineup = lineup
        groups = lineup.groups
        groupIndex = group.flatMap { groups.firstIndex(of: $0) } ?? 0
        channels = channelsOfSelectedGroup()
        row = focusedID.flatMap { id in channels.firstIndex { $0.id == id } } ?? min(row, max(0, channels.count - 1))
        firstVisibleRow = min(firstVisibleRow, max(0, channels.count - Self.visibleRows))
        keepRowVisible()
        if case .groups(let index) = focus {
            focus = .groups(min(index, max(0, groups.count - 1)))
        }
    }

    // MARK: - Private

    private func channelsOfSelectedGroup() -> [Channel] {
        guard let group = selectedGroup else { return [] }
        return lineup.channels(in: group)
    }

    private func focusedCellIndex(in cells: [Cell]) -> Int? {
        guard !cells.isEmpty else { return nil }
        if let index = cells.firstIndex(where: { $0.start <= focusTime && focusTime < $0.stop }) { return index }
        if let index = cells.firstIndex(where: { $0.start > focusTime }) { return index }
        return cells.count - 1
    }

    private mutating func handleGrid(_ command: RemoteCommand, now: Date) -> Action {
        switch command {
        case .up, .down:
            moveRow(command)
            return .none
        case .right, .fastForward:
            let cells = cells(row: row, now: now)
            guard let index = focusedCellIndex(in: cells), index + 1 < cells.count else { return .none }
            moveFocus(to: cells[index + 1], now: now)
            return .none
        case .left, .rewind:
            let cells = cells(row: row, now: now)
            guard let index = focusedCellIndex(in: cells) else { return .none }
            if index == 0 {
                focus = .channel
            } else {
                moveFocus(to: cells[index - 1], now: now)
            }
            return .none
        case .select:
            return focusedChannel.map { .play($0.id) } ?? .none
        case .back:
            return .close
        case .menu:
            // M7 L5: the channel menu, as Select on the channel cell.
            return focusedChannel.map { .channelMenu($0.id) } ?? .none
        case .channelUp, .channelDown:
            moveRow(by: command == .channelUp ? -Self.visibleRows : Self.visibleRows)
            return .none
        case .playPause, .home:
            return .none
        }
    }

    private mutating func handleChannel(_ command: RemoteCommand) -> Action {
        switch command {
        case .up, .down:
            moveRow(command)
            return .none
        case .right, .fastForward:
            focus = .grid
            return .none
        case .left, .rewind:
            focus = .groups(groupIndex)
            return .none
        case .select:
            return focusedChannel.map { .channelMenu($0.id) } ?? .none
        case .back:
            return .close
        case .menu:
            // M7 L5: the channel menu, as Select on the channel cell.
            return focusedChannel.map { .channelMenu($0.id) } ?? .none
        case .channelUp, .channelDown:
            moveRow(by: command == .channelUp ? -Self.visibleRows : Self.visibleRows)
            return .none
        case .playPause, .home:
            return .none
        }
    }

    private mutating func handleGroups(_ command: RemoteCommand, index: Int, now: Date) -> Action {
        switch command {
        case .up where index == 0:
            // M7f L12: the Search row sits above the first group.
            focus = .search
            return .none
        case .up, .down:
            guard !groups.isEmpty else { return .none }
            focus = .groups(min(max(index + (command == .up ? -1 : 1), 0), groups.count - 1))
            return .none
        case .select, .right:
            guard groups.indices.contains(index) else { return .none }
            groupIndex = index
            channels = channelsOfSelectedGroup()
            row = 0
            firstVisibleRow = 0
            focusTime = now
            timeline = GuideTimeline(now: now)
            focus = .grid
            return .groupChanged(groups[index])
        case .back, .left:
            focus = .grid
            return .none
        case .channelUp, .channelDown:
            guard !groups.isEmpty else { return .none }
            let step = command == .channelUp ? -Self.visibleRows : Self.visibleRows
            focus = .groups(min(max(index + step, 0), groups.count - 1))
            return .none
        case .playPause, .home, .fastForward, .rewind, .menu:
            return .none
        }
    }

    /// M7f L12: the Search row; Down returns to the first group.
    private mutating func handleSearchRow(_ command: RemoteCommand) -> Action {
        switch command {
        case .select, .right:
            // Focus stays here, so closing search comes back to the Search row.
            return .openSearch
        case .down:
            if !groups.isEmpty { focus = .groups(0) }
            return .none
        case .back, .left:
            focus = .grid
            return .none
        case .up, .playPause, .home, .fastForward, .rewind, .menu, .channelUp, .channelDown:
            return .none
        }
    }

    private mutating func moveRow(_ command: RemoteCommand) {
        moveRow(by: command == .up ? -1 : 1)
    }

    /// Clamped; M7 L5 pages with Channel Up/Down.
    private mutating func moveRow(by step: Int) {
        guard !channels.isEmpty else { return }
        row = min(max(row + step, 0), channels.count - 1)
        keepRowVisible()
    }

    private mutating func moveFocus(to cell: Cell, now: Date) {
        focusTime = max(cell.start, now)
        timeline.reveal(focusTime, now: now)
    }

    private mutating func keepRowVisible() {
        if row < firstVisibleRow {
            firstVisibleRow = row
        } else if row >= firstVisibleRow + Self.visibleRows {
            firstVisibleRow = row - Self.visibleRows + 1
        }
    }
}
