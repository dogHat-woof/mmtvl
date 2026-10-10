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
    /// M7c L14.
    let carouselPage: Int
    /// M7c L15: the Live TV preview plays behind the canvas; the backdrop's art fades out.
    var revealsLivePreview = false
    /// M7c L22, L23: the home UI animates away before live content opens (the router animates the change).
    var isLeaving = false
    /// M7c L28: "Version 1.1.0 Build 2" under the clock; nil = hidden.
    var versionLabel: String? = nil
    /// Bumped when MMTVL comes back; the dock slides up.
    var entryGeneration = 0
    @State private var isEntering = false
    let onHoverCard: (Int) -> Void
    let onActivateCard: (Int) -> Void
    let onRefreshShelf: () -> Void
    let shelfImages: ShelfImageLoader
    let onHover: (Int) -> Void
    let onActivate: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // L27: the focused tile's art fills the screen; it dims in the grid (M7c L19).
            ShelfBackdrop(
                item: focusedItem,
                art: focusedItem.map { tileArt.art(for: $0, icon: launcher.icon(for: $0), bundleID: launcher.bundleID(for: $0)) },
                isDimmed: !shelf.cards.isEmpty && !shelf.isCarousel,
                carousel: shelf.isCarousel ? (shelf.cards, shelfIndex ?? carouselPage, shelfImages) : nil,
                artOpacity: revealsLivePreview ? 0 : 1
            )
            .opacity(HomeLayout.heroOpacity(focusedRow: focus.position.row))
            .animation(Theme.focusAnimation, value: focus.position.row)

            TopShelfView(
                item: focusedItem,
                content: shelf,
                focusedIndex: shelfIndex,
                focusMotion: focusMotion,
                onHoverCard: onHoverCard,
                onActivateCard: onActivateCard,
                images: shelfImages,
                carouselPage: carouselPage
            )
            // L13: the Live TV shelf's "time left" stays current while the home screen shows.
            .background {
                TimelineView(.everyMinute) { context in
                    Color.clear.onChange(of: context.date) { onRefreshShelf() }
                }
            }
            // M7c L19: the shelf shows only with row 0 focused.
            .opacity(HomeLayout.shelfOpacity(focusedRow: focus.position.row))
            .animation(Theme.focusAnimation, value: focus.position.row)
            .opacity(isLeaving ? 0 : 1)

            // M7c L19 (D38): the glass dock behind row 0; it scrolls away with the row.
            Color.clear
                .glassPanel(in: RoundedRectangle(cornerRadius: Theme.homeDockCornerRadius, style: .continuous))
                .frame(width: HomeLayout.dockFrame.width, height: HomeLayout.dockFrame.height)
                .offset(x: HomeLayout.dockFrame.minX, y: HomeLayout.dockFrame.minY - scrollOffset)
                .animation(Theme.focusAnimation, value: focus.position.row)
                .allowsHitTesting(false)
                .modifier(HomeExitMotion(isAway: isLeaving || isEntering))

            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach(Array(rowRanges.enumerated()), id: \.offset) { _, range in
                    HStack(alignment: .top, spacing: Theme.tileSpacing) {
                        ForEach(range, id: \.self) { index in
                            tile(at: index)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.homeRowMargin)
            .padding(.top, HomeLayout.rowTop(0))
            // L21: later rows scroll up so the focused row is fully visible.
            .offset(y: -scrollOffset)
            .animation(Theme.focusAnimation, value: focus.position.row)
            .modifier(HomeExitMotion(isAway: isLeaving || isEntering))

            // Scrolled rows pass under the clock.
            Theme.backgroundTopFade
                .frame(height: Theme.homeClockFadeHeight)
                .opacity(scrollOffset > 0 ? 1 : 0)
                .animation(Theme.focusAnimation, value: scrollOffset > 0)
                .allowsHitTesting(false)

            VStack(alignment: .trailing, spacing: Theme.homeClockStackSpacing) {
                clock
                if let versionLabel { capsule(Text(versionLabel)) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 60)
            .padding(.horizontal, Theme.sideMargin)
            .opacity(isLeaving ? 0 : 1)
            .zIndex(1)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
        // L3: pictures dropped in the folder show up when the home screen appears.
        .onAppear {
            tileArt.reloadIfChanged()
            onRefreshShelf()
            slideIn()
        }
        .onChange(of: entryGeneration) { slideIn() }
    }

    /// M7c L23: the dock and rows slide up and fade in when the home screen comes back.
    private func slideIn() {
        isEntering = true
        Task { @MainActor in
            withAnimation(Theme.homeReturnAnimation) { isEntering = false }
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
            capsule(Text(context.date.formatted(date: .omitted, time: .shortened)))
        }
    }

    /// The clock's look (M7c L28: the version uses it too).
    private func capsule(_ text: Text) -> some View {
        text
            .font(Theme.clockFont)
            .foregroundStyle(Theme.primaryText)
            .monospacedDigit()
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .glassPanel(in: Capsule())
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

/// M7c L22: the dock and rows slide down and fade while the home UI is away.
private struct HomeExitMotion: ViewModifier {
    let isAway: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: isAway ? Theme.homeExitSlide : 0)
            .opacity(isAway ? 0 : 1)
    }
}
