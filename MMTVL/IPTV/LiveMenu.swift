import Foundation

/// What a Live TV menu item does (M6 L10). Window actions apply to the highlighted Multiview window.
nonisolated enum LiveMenuAction: Hashable, Sendable {
    case watch(Channel.ID)
    case addToMultiview(Channel.ID)
    case fullScreen, makeMain, changeChannel, retryWindow, chooseLayout, removeWindow
    case setLayout(MultiviewLayout)
    // M6b L8, L9: the guide's channel menu.
    case toggleFavorite(Channel.ID)
    case moveFavorite(Channel.ID, by: Int)
    case openMatchGuide(Channel.ID)
    case matchGuide(Channel.ID, GuideMatchChoice)
    case hideChannel(Channel.ID)
    /// M7f L13: add or remove a team of this game or programme.
    case toggleTeam(Team.ID)
}

/// A menu drawn over Live TV: the guide's channel menu, Multiview's window menu and layout menu (M6 L10). Pure.
/// At most `visibleRows` rows show; the window follows the focus (M6b L10).
nonisolated struct LiveMenu: Equatable, Sendable {
    static let visibleRows = 8

    struct Item: Identifiable, Equatable, Sendable {
        /// Stable, e.g. "watch", "addToMultiview", "layout.grid".
        var id: String
        var title: String
        /// Right-aligned: the current layout's title, "Current".
        var value: String? = nil
        /// Draws a diagram before the title (layout menu).
        var layout: MultiviewLayout? = nil
        var action: LiveMenuAction
    }

    enum Outcome: Equatable, Sendable { case none, close, choose(LiveMenuAction) }

    var title: String
    var items: [Item]
    /// A wider panel (Match Guide's long names).
    var isWide: Bool
    private(set) var focusedIndex: Int
    private(set) var firstVisibleIndex = 0

    init(title: String, items: [Item], focusedIndex: Int = 0, isWide: Bool = false) {
        self.title = title
        self.items = items
        self.isWide = isWide
        self.focusedIndex = min(max(focusedIndex, 0), max(0, items.count - 1))
        firstVisibleIndex = min(self.focusedIndex, max(0, items.count - Self.visibleRows))
    }

    var focusedItem: Item? { items.indices.contains(focusedIndex) ? items[focusedIndex] : nil }

    var visibleRange: Range<Int> { firstVisibleIndex..<min(firstVisibleIndex + Self.visibleRows, items.count) }
    var hasHiddenAbove: Bool { firstVisibleIndex > 0 }
    var hasHiddenBelow: Bool { visibleRange.upperBound < items.count }

    /// Up/Down move (clamped), Channel Up/Down by a page; Select → .choose(focused action); Back and Menu → .close;
    /// everything else → .none.
    mutating func handle(_ command: RemoteCommand) -> Outcome {
        switch command {
        case .up, .down, .channelUp, .channelDown:
            guard !items.isEmpty else { return .none }
            let step = switch command {
            case .up: -1
            case .down: 1
            case .channelUp: -Self.visibleRows   // M7 L5: a page
            default: Self.visibleRows
            }
            focusedIndex = min(max(focusedIndex + step, 0), items.count - 1)
            if focusedIndex < firstVisibleIndex {
                firstVisibleIndex = focusedIndex
            } else if focusedIndex >= firstVisibleIndex + Self.visibleRows {
                firstVisibleIndex = focusedIndex - Self.visibleRows + 1
            }
            return .none
        case .select:
            return focusedItem.map { .choose($0.action) } ?? .none
        case .back, .menu:
            return .close
        case .left, .right, .playPause, .fastForward, .rewind, .home:
            return .none
        }
    }
}
