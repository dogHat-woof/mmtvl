import SwiftUI

/// The grid guide on the 1920×1080 canvas (L12): info panel, preview frame (the video sits under it, L16),
/// time header, channel rows, now line and group panel.
struct GuideView: View {
    let model: GuideModel
    let currentChannel: Channel?
    let phase: PlayerState.Phase

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
                if case .groups(let index) = model.focus {
                    groupPanel(focused: index)
                        .offset(x: Theme.sideMargin, y: Theme.guideGridTop)
                }
                Text("Select: watch · Left at now: groups · Back: close")
                    .font(Theme.settingsHintFont)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: Theme.canvasSize.width)
                    .offset(y: Theme.canvasSize.height - 64)
            }
            .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
        }
    }

    // MARK: Info panel

    @ViewBuilder
    private func infoPanel(now: Date) -> some View {
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
        let last = min(first + GuideModel.visibleRows, model.channels.count)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(first..<max(first, last), id: \.self) { row in
                rowView(row, now: now)
                    .frame(height: Theme.guideRowHeight)
            }
        }
    }

    private func rowView(_ row: Int, now: Date) -> some View {
        let channel = model.channels[row]
        let focusedCell = row == model.row && model.focus == .grid ? model.focusedCell(now: now) : nil
        return HStack(spacing: Theme.guideGridLeading - Theme.sideMargin - Theme.guideChannelColumnWidth) {
            channelCell(channel)
                .frame(width: Theme.guideChannelColumnWidth, alignment: .leading)
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

    private func channelCell(_ channel: Channel) -> some View {
        HStack(spacing: 12) {
            Text("\(channel.number)")
                .font(Theme.guideCellTimeFont)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, alignment: .trailing)
            if let logo = channel.logoURL {
                AsyncImage(url: logo) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
            }
            Text(channel.name)
                .font(Theme.guideChannelFont)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            if channel.id == currentChannel?.id {
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.guideCellTimeFont)
                    .foregroundStyle(Theme.secondaryText)
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

    @ViewBuilder
    private func nowLine(now: Date) -> some View {
        if let span = model.timeline.span(start: now, stop: now + 1, width: Theme.guideGridWidth) {
            let rowCount = min(GuideModel.visibleRows, model.channels.count)
            Rectangle()
                .fill(Theme.guideNowLine)
                .frame(width: 2, height: Theme.guideTimeHeaderHeight + CGFloat(rowCount) * Theme.guideRowHeight)
                .offset(x: Theme.guideGridLeading + span.x, y: Theme.guideGridTop)
        }
    }

    // MARK: Groups

    private func groupPanel(focused: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
            ForEach(Array(model.groups.enumerated()), id: \.offset) { index, group in
                Text(group)
                    .font(Theme.guideChannelFont)
                    .foregroundStyle(index == focused ? Theme.focusedRowText : Theme.primaryText)
                    .padding(.horizontal, 20)
                    .frame(width: Theme.guideGroupPanelWidth - 40, height: Theme.guideRowHeight - 16, alignment: .leading)
                    .background(index == focused ? Theme.focusedRowFill : Color.clear,
                                in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: Theme.guideGroupPanelWidth,
               height: Theme.guideTimeHeaderHeight + CGFloat(GuideModel.visibleRows) * Theme.guideRowHeight,
               alignment: .topLeading)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.tileCornerRadius))
    }
}
