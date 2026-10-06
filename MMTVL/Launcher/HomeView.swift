import SwiftUI

/// The home screen: clock and rows of tiles, laid out on the 1920×1080 canvas.
/// Focus is rendered from `LauncherFocusModel` (D2), not SwiftUI focus.
struct HomeView: View {
    /// The visible tiles.
    let items: [LaunchItem]
    let focus: LauncherFocusModel
    let launcher: AppLauncher
    let tileArt: TileArtStore
    let shakeTriggers: [LaunchItem.ID: Int]
    let focusMotion: FocusMotion
    /// M7 L12: the focused tile's shelf, and the focused card (nil = the tiles have focus).
    let shelf: ShelfContent
    let shelfIndex: Int?
    let onHoverCard: (Int) -> Void
    let onActivateCard: (Int) -> Void
    let onRefreshShelf: () -> Void
    let shelfImages: ShelfImageLoader
    let onHover: (Int) -> Void
    let onActivate: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // L27: the focused tile's art fills the screen; it fades as the rows scroll (L21).
            ShelfBackdrop(
                item: focusedItem,
                art: focusedItem.map { tileArt.art(for: $0, icon: launcher.icon(for: $0), bundleID: launcher.bundleID(for: $0)) },
                isDimmed: !shelf.cards.isEmpty
            )
            .opacity(max(0, 1 - scrollOffset / Theme.shelfFadeDistance))
            .animation(Theme.focusAnimation, value: focus.position.row)

            TopShelfView(
                item: focusedItem,
                content: shelf,
                focusedIndex: shelfIndex,
                focusMotion: focusMotion,
                onHoverCard: onHoverCard,
                onActivateCard: onActivateCard,
                images: shelfImages
            )
            // L13: the Live TV shelf's "time left" stays current while the home screen shows.
            .background {
                TimelineView(.everyMinute) { context in
                    Color.clear.onChange(of: context.date) { onRefreshShelf() }
                }
            }
            // L21: the shelf scrolls away with the rows and fades.
            .offset(y: -scrollOffset)
            .opacity(max(0, 1 - scrollOffset / Theme.shelfFadeDistance))
            .animation(Theme.focusAnimation, value: focus.position.row)

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
            .padding(.top, HomeLayout.rowTop(0))
            // L21: later rows scroll up so the focused row is fully visible.
            .offset(y: -scrollOffset)
            .animation(Theme.focusAnimation, value: focus.position.row)

            // Scrolled rows pass under the clock.
            Theme.backgroundTopFade
                .frame(height: Theme.homeClockFadeHeight)
                .opacity(scrollOffset > 0 ? 1 : 0)
                .animation(Theme.focusAnimation, value: scrollOffset > 0)
                .allowsHitTesting(false)

            clock
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 60)
                .padding(.horizontal, Theme.sideMargin)
                .zIndex(1)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
        // L3: pictures dropped in the folder show up when the home screen appears.
        .onAppear {
            tileArt.reloadIfChanged()
            onRefreshShelf()
        }
    }

    private var focusedItem: LaunchItem? {
        focus.index.flatMap { items.indices.contains($0) ? items[$0] : nil }
    }

    private var scrollOffset: CGFloat {
        HomeLayout.scrollOffset(focusedRow: focus.position.row)
    }

    /// L28: on a small glass capsule.
    private var clock: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date.formatted(date: .omitted, time: .shortened))
                .font(Theme.clockFont)
                .foregroundStyle(Theme.primaryText)
                .monospacedDigit()
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .glassPanel(in: Capsule())
        }
    }

    /// Item index ranges per row, matching the focus model's chunking.
    private var rowRanges: [Range<Int>] {
        var start = 0
        return focus.rows.map { count in
            defer { start += count }
            return start..<(start + count)
        }
    }

    private func tile(at index: Int) -> some View {
        let item = items[index]
        return AppTileView(
            item: item,
            title: launcher.title(for: item),
            art: tileArt.art(for: item, icon: launcher.icon(for: item), bundleID: launcher.bundleID(for: item)),
            // While a shelf card has focus, its tile drops the focus effect (L12).
            isFocused: focus.index == index && shelfIndex == nil,
            isInstalled: launcher.isInstalled(item),
            shakeTrigger: shakeTriggers[item.id, default: 0],
            focusMotion: focusMotion
        )
        .onHover { hovering in
            if hovering { onHover(index) }
        }
        .onTapGesture { onActivate(index) }
    }
}
