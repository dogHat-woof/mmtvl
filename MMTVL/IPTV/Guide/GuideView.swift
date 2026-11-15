import SwiftUI

/// The grid guide on the 1920×1080 canvas (L12): info panel, preview frame (the video sits under it, L16),
/// time header, channel rows, now line and group panel.
struct GuideView: View {
    let model: GuideModel
    let currentChannel: Channel?
    let phase: PlayerState.Phase
    /// The Multiview picker guide (M6 L11): Select puts the channel in a window.
    var isPicking = false
    /// Starred in the channel cell (M6b).
    var favoriteIDs: Set<Channel.ID> = []
    /// M7m L4: Back in the watch guide returns to a channel (`LiveTVModel.canReturnToChannel`); the hint says so.
    var hasChannel = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            ZStack(alignment: .topLeading) {
                infoPanel(now: now)
                    .frame(width: Theme.guideInfoRect.width, height: Theme.guideInfoRect.height, alignment: .topLeading)
                    .offset(x: Theme.guideInfoRect.minX, y: Theme.guideInfoRect.minY)
                previewFrame
                    .frame(width: Theme.guidePreviewRect.width, height: Theme.guidePreviewRect.height)
                    .offset(x: Theme.guidePreviewRect.minX, y: Theme.guidePreviewRect.minY)
                timeHeader
                    .offset(x: Theme.guideGridLeading, y: Theme.guideGridTop)
                rows(now: now)
                    .offset(x: Theme.sideMargin, y: Theme.guideGridTop + Theme.guideTimeHeaderHeight)
                nowLine(now: now)
                switch model.focus {
                case .groups, .search:
                    groupPanel(focus: model.focus)
                        .offset(x: Theme.sideMargin, y: Theme.guideGridTop)
                case .grid, .channel:
                    EmptyView()
                }
                Text(Self.hint(focus: model.focus, isPicking: isPicking, row: model.focusedRow?.kind ?? .channel,
                               hasChannel: hasChannel))
                    .font(Theme.settingsHintFont)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: Theme.canvasSize.width)
                    .offset(y: Theme.canvasSize.height - 64)
            }
            .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
        }
    }

    /// The bottom hint per focus and purpose (M6), and (M7l 8c) My Teams' Choose Teams and upcoming rows.
    /// M7m L4: in the watch guide Back goes back to the channel (`hasChannel`); with no channel it does nothing.
    nonisolated static func hint(focus: GuideModel.Focus, isPicking: Bool, row: GuideModel.Row.Kind = .channel,
                                 hasChannel: Bool = false) -> String {
        let back = hasChannel ? " · Back: back to the channel" : ""
        switch (focus, row, isPicking) {
        case (.grid, .chooseTeams, false), (.channel, .chooseTeams, false):
            return "Select: choose your teams · Left: groups" + back
        case (.grid, .chooseTeams, true), (.channel, .chooseTeams, true):
            return "Select: choose your teams · Left: groups · Back: cancel"
        case (.grid, .upcoming, false), (.channel, .upcoming, false):
            return "Select: watch this channel · Left: groups" + back
        case (.grid, .upcoming, true), (.channel, .upcoming, true):
            return "Select: show this channel in window · Left: groups · Back: cancel"
        default:
            break
        }
        return switch (focus, isPicking) {
        case (.grid, false): "Select: watch · Left at now: channel options" + back
        case (.grid, true): "Select: show in window · Left at now: channel · Back: cancel"
        case (.channel, false): "Select: options · Left: groups · Right: programmes" + back
        case (.channel, true): "Select: show in window · Left: groups · Right: programmes · Back: cancel"
        case (.groups, _): "Select: show group · Back: close list"
        case (.search, _): "Select: search channels and programmes · Back: close list"
        }
    }

    // MARK: Info panel

    @ViewBuilder
    private func infoPanel(now: Date) -> some View {
        switch model.focusedRow {
        case .chooseTeams?: chooseTeamsInfo
        case .upcoming(let game)?: upcomingInfo(game)
        case .channel?, nil: channelInfo(now: now)
        }
    }

    /// M7l 8c: My Teams' Choose Teams row.
    private var chooseTeamsInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TeamPicker.title)
                .font(Theme.guideInfoTitleFont)
                .foregroundStyle(Theme.primaryText)
            Text("Pick pro and college teams. Their live games show here, then their games in the next 3 days.")
                .font(Theme.guideInfoDetailFont)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(4)
        }
    }

    /// M7l 8c: an upcoming game: its programme, the channel and the day. The time is "Wed 10:00 PM – 1:00 AM", not
    /// `LiveBannerView.timeRange`, whose interval format spells out both dates when a game ends after midnight.
    private func upcomingInfo(_ game: UpcomingTeamGame) -> some View {
        let programme = game.programme
        let when = game.dayTime + " – " + programme.stop.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 16) {
            Text(programme.title)
                .font(Theme.guideInfoTitleFont)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
            Text(([game.channel.name, when] + [programme.subtitle, programme.category].compactMap { $0 })
                .joined(separator: " · "))
                .font(Theme.guideInfoDetailFont)
                .foregroundStyle(Theme.primaryText)
            if let summary = programme.summary {
                Text(summary)
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(4)
            }
        }
    }

    @ViewBuilder
    private func channelInfo(now: Date) -> some View {
        let cell = model.focusedCell(now: now)
        let channelName = model.focusedChannel?.name ?? ""
        VStack(alignment: .leading, spacing: 16) {
            if let programme = cell?.programme {
                Text(programme.title)
                    .font(Theme.guideInfoTitleFont)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Text(([channelName, LiveBannerView.timeRange(programme)] + [programme.episode, programme.category].compactMap { $0 })
                    .joined(separator: " · "))
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.primaryText)
                if let summary = programme.summary {
                    Text(summary)
                        .font(Theme.guideInfoDetailFont)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(4)
                }
            } else {
                Text(channelName)
                    .font(Theme.guideInfoTitleFont)
                    .foregroundStyle(Theme.primaryText)
                Text("No programme information")
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Preview

    private var previewFrame: some View {
        ZStack {
            if phase == .idle || phase == .failed {
                Text(phase == .failed ? "Can't play this channel" : "Nothing playing")
                    .font(Theme.guideInfoDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
            RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius)
                .strokeBorder(Theme.focusHighlight, lineWidth: Theme.focusHighlightWidth)
        }
    }

    // MARK: Grid

    private var timeHeader: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.timeline.ticks(width: Theme.guideGridWidth), id: \.date) { tick in
                Text(tick.date.formatted(date: .omitted, time: .shortened))
                    .font(Theme.guideCellTimeFont)
                    .foregroundStyle(Theme.secondaryText)
                    .offset(x: tick.x + 8)
            }
        }
        .frame(width: Theme.guideGridWidth, height: Theme.guideTimeHeaderHeight, alignment: .topLeading)
    }

    private func rows(now: Date) -> some View {
        let first = model.firstVisibleRow
        let last = min(first + GuideModel.visibleRows, model.rows.count)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(first..<max(first, last), id: \.self) { row in
                rowView(row, now: now)
                    .frame(height: Theme.guideRowHeight)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Int, now: Date) -> some View {
        switch model.rows[row] {
        case .channel(let channel): channelRow(row, channel, now: now)
        case .chooseTeams: chooseTeamsRow(row)
        case .upcoming(let game): upcomingRow(row, game)
        }
    }

    private func channelRow(_ row: Int, _ channel: Channel, now: Date) -> some View {
        let focusedCell = row == model.row && model.focus == .grid ? model.focusedCell(now: now) : nil
        let isChannelFocused = row == model.row && model.focus == .channel
        return HStack(spacing: Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth) {
            channelCell(channel, isFocused: isChannelFocused)
                .padding(.horizontal, 8)
                .frame(width: Theme.guideChannelColumnWidth, height: Theme.guideRowHeight - Theme.guideCellSpacing,
                       alignment: .leading)
                .background(isChannelFocused ? Theme.focusedRowFill : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
                .frame(height: Theme.guideRowHeight, alignment: .top)
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.cells(row: row, now: now).enumerated()), id: \.offset) { _, cell in
                    if let span = model.timeline.span(start: cell.start, stop: cell.stop, width: Theme.guideGridWidth) {
                        programmeCell(cell, isFocused: cell == focusedCell)
                            .frame(width: max(0, span.width - Theme.guideCellSpacing),
                                   height: Theme.guideRowHeight - Theme.guideCellSpacing)
                            .offset(x: span.x)
                    }
                }
            }
            .frame(width: Theme.guideGridWidth, height: Theme.guideRowHeight, alignment: .topLeading)
            .clipped()
        }
    }

    /// M7l 8c: whether My Teams' Choose Teams or upcoming row `row` is focused. They have no programme cells to
    /// move between, so the channel column and the grid both focus the whole row.
    private func isActionRowFocused(_ row: Int) -> Bool {
        row == model.row && (model.focus == .grid || model.focus == .channel)
    }

    /// M7l 8c: My Teams' first row, an action rather than a channel: one button across the channel column and the
    /// grid (no channel number, no programme cells), its symbol where channel logos sit and its title in line with
    /// the channel names, the description in line with the programme titles, and a chevron for "opens a page".
    private func chooseTeamsRow(_ row: Int) -> some View {
        let isFocused = isActionRowFocused(row)
        let columnGap = Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth
        return HStack(spacing: columnGap) {
            HStack(spacing: 12) {
                Color.clear.frame(width: Theme.guideChannelNumberWidth, height: 1)
                Image(systemName: "sportscourt")
                    .font(.system(size: Theme.guideRowSymbolSize, weight: .medium))
                    .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
                Text(TeamPicker.title + "…")
                    .font(Theme.guideChannelFont)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: Theme.guideChannelColumnWidth, alignment: .leading)
            HStack(spacing: 16) {
                Text("Add or remove pro and college teams")
                    .font(Theme.guideCellFont)
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.guideRowSymbolSize, weight: .semibold))
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
            }
            .padding(.horizontal, 16)
        }
        .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
        .frame(width: Theme.guideGridLeading - Theme.sideMargin + Theme.guideGridWidth - Theme.guideCellSpacing,
               height: Theme.guideRowHeight - Theme.guideCellSpacing, alignment: .leading)
        .background(isFocused ? Theme.focusedRowFill : Theme.tileFill,
                    in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
        .frame(height: Theme.guideRowHeight, alignment: .top)
    }

    /// M7l 8c: an upcoming game: the channel column as on every guide row, then one cell across the grid (it isn't
    /// on the timeline, so the now line skips it) led by its day and time, then the game ("Tampa Bay Buccaneers at
    /// Chicago Bears") over the programme's title ("NFL Football") when the game came from the subtitle.
    private func upcomingRow(_ row: Int, _ game: UpcomingTeamGame) -> some View {
        let isFocused = isActionRowFocused(row)
        return HStack(spacing: Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth) {
            channelCell(game.channel, isFocused: isFocused)
                .padding(.horizontal, 8)
                .frame(width: Theme.guideChannelColumnWidth, height: Theme.guideRowHeight - Theme.guideCellSpacing,
                       alignment: .leading)
                .background(isFocused ? Theme.focusedRowFill : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
                .frame(height: Theme.guideRowHeight, alignment: .top)
            upcomingCell(game, isFocused: isFocused)
                .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
                .padding(.horizontal, 16)
                .frame(width: Theme.guideGridWidth - Theme.guideCellSpacing,
                       height: Theme.guideRowHeight - Theme.guideCellSpacing, alignment: .leading)
                .background(isFocused ? Theme.focusedRowFill : Theme.tileFill,
                            in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
                .frame(width: Theme.guideGridWidth, height: Theme.guideRowHeight, alignment: .topLeading)
        }
    }

    /// "[calendar] Sun 1:00 PM | Tampa Bay Buccaneers at Chicago Bears / NFL Football".
    private func upcomingCell(_ game: UpcomingTeamGame, isFocused: Bool) -> some View {
        let secondary = isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText
        let title = game.programme.title
        return HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: Theme.guideRowSymbolSize))
                    .foregroundStyle(secondary)
                Text(game.dayTime)
                    .font(Theme.guideCellFont)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: Theme.guideUpcomingTimeWidth, alignment: .leading)
            Rectangle()
                .fill(secondary)
                .frame(width: 2, height: Theme.guideLogoSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.label)
                    .font(Theme.guideCellFont)
                    .lineLimit(1)
                if game.label != title {
                    Text(title)
                        .font(Theme.guideCellTimeFont)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func channelCell(_ channel: Channel, isFocused: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(channel.number)")
                .font(Theme.guideCellTimeFont)
                .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
                .frame(width: Theme.guideChannelNumberWidth, alignment: .trailing)
            if let logo = channel.logoURL {
                ChannelLogoView(url: logo)
                    .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
            }
            Text(channel.name)
                .font(Theme.guideChannelFont)
                .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
                .lineLimit(1)
            if favoriteIDs.contains(channel.id) {
                Image(systemName: "star.fill")
                    .font(.system(size: Theme.guideFavoriteSymbolSize))
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
            }
            if channel.id == currentChannel?.id {
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.guideCellTimeFont)
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
            }
        }
    }

    private func programmeCell(_ cell: GuideModel.Cell, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.programme?.title ?? "No information")
                .font(Theme.guideCellFont)
                .lineLimit(1)
            if let programme = cell.programme {
                Text(programme.start.formatted(date: .omitted, time: .shortened))
                    .font(Theme.guideCellTimeFont)
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
            }
        }
        .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(isFocused ? Theme.focusedRowFill : Theme.tileFill,
                    in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
    }

    /// Through the time header and the channel rows on screen; My Teams' Choose Teams and upcoming rows (M7l 8c)
    /// aren't on the timeline, so it stops at them.
    @ViewBuilder
    private func nowLine(now: Date) -> some View {
        if let span = model.timeline.span(start: now, stop: now + 1, width: Theme.guideGridWidth) {
            let first = model.firstVisibleRow
            let last = min(first + GuideModel.visibleRows, model.rows.count)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.guideNowLine)
                    .frame(width: 2, height: Theme.guideTimeHeaderHeight)
                ForEach(first..<max(first, last), id: \.self) { row in
                    Rectangle()
                        .fill(model.rows[row].kind == .channel ? Theme.guideNowLine : Color.clear)
                        .frame(width: 2, height: Theme.guideRowHeight)
                }
            }
            .offset(x: Theme.guideGridLeading + span.x, y: Theme.guideGridTop)
        }
    }

    // MARK: Groups

    /// The Search row (M7f L12) above the groups. (M7l 8c: Choose Teams is My Teams' first row.)
    private func groupPanel(focus: GuideModel.Focus) -> some View {
        VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
            groupRow(Label("Search", systemImage: "magnifyingglass"), isFocused: focus == .search)
            ForEach(Array(model.groups.enumerated()), id: \.offset) { index, group in
                groupRow(Text(group), isFocused: focus == .groups(index))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: Theme.guideGroupPanelWidth,
               height: Theme.guideTimeHeaderHeight + CGFloat(GuideModel.visibleRows) * Theme.guideRowHeight,
               alignment: .topLeading)
        .glassPanel()
    }

    private func groupRow(_ label: some View, isFocused: Bool) -> some View {
        label
            .font(Theme.guideChannelFont)
            .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
            .padding(.horizontal, 20)
            .frame(width: Theme.guideGroupPanelWidth - 40, height: Theme.guideRowHeight - 16, alignment: .leading)
            .background(isFocused ? Theme.focusedRowFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
    }
}
