import SwiftUI

/// The home screen: gear, clock and rows of tiles, laid out on the 1920×1080 canvas.
/// Focus is rendered from `HomeFocusModel` (D2), not SwiftUI focus.
struct HomeView: View {
    /// The visible tiles.
    let items: [LaunchItem]
    let focus: HomeFocusModel
    let launcher: AppLauncher
    let shakeTriggers: [LaunchItem.ID: Int]
    let onHover: (Int) -> Void
    let onActivate: (Int) -> Void
    let onHoverGear: () -> Void
    let onActivateGear: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: Theme.headerSpacing) {
                GearButtonView(isFocused: focus.isGearFocused, onHover: onHoverGear, onActivate: onActivateGear)
                clock
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 60)
            .padding(.horizontal, Theme.sideMargin)

            if items.isEmpty {
                Text("No tiles. Select the gear to open Settings.")
                    .font(Theme.clockFont)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.canvasSize.height * Theme.rowsTopFraction)
            }

            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach(Array(rowRanges.enumerated()), id: \.offset) { _, range in
                    HStack(alignment: .top, spacing: Theme.tileSpacing) {
                        ForEach(range, id: \.self) { index in
                            tile(at: index)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.sideMargin)
            .padding(.top, Theme.canvasSize.height * Theme.rowsTopFraction)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date.formatted(date: .omitted, time: .shortened))
                .font(Theme.clockFont)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
        }
    }

    /// Item index ranges per row, matching the focus model's chunking.
    private var rowRanges: [Range<Int>] {
        var start = 0
        return focus.tiles.rows.map { count in
            defer { start += count }
            return start..<(start + count)
        }
    }

    private func tile(at index: Int) -> some View {
        let item = items[index]
        return AppTileView(
            item: item,
            title: launcher.title(for: item),
            icon: launcher.icon(for: item),
            isFocused: focus.tileIndex == index,
            isInstalled: launcher.isInstalled(item),
            shakeTrigger: shakeTriggers[item.id, default: 0]
        )
        .onHover { hovering in
            if hovering { onHover(index) }
        }
        .onTapGesture { onActivate(index) }
    }
}
