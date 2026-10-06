import Foundation

/// What a Live TV menu item does (M6 L10). Window actions apply to the highlighted Multiview window.
nonisolated enum LiveMenuAction: Hashable, Sendable {
    case watch(Channel.ID)
    case addToMultiview(Channel.ID)
    case fullScreen, makeMain, changeChannel, retryWindow, chooseLayout, removeWindow
    case setLayout(MultiviewLayout)
}

/// A menu drawn over Live TV: the guide's channel menu, Multiview's window menu and layout menu (M6 L10). Pure.
nonisolated struct LiveMenu: Equatable, Sendable {
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
    private(set) var focusedIndex: Int

    init(title: String, items: [Item], focusedIndex: Int = 0) {
        self.title = title
        self.items = items
        self.focusedIndex = min(max(focusedIndex, 0), max(0, items.count - 1))
    }

    var focusedItem: Item? { items.indices.contains(focusedIndex) ? items[focusedIndex] : nil }

    /// Up/Down move (clamped); Select → .choose(focused action); Back → .close; everything else → .none.
    mutating func handle(_ command: RemoteCommand) -> Outcome {
        switch command {
        case .up, .down:
            guard !items.isEmpty else { return .none }
            focusedIndex = min(max(focusedIndex + (command == .up ? -1 : 1), 0), items.count - 1)
            return .none
        case .select:
            return focusedItem.map { .choose($0.action) } ?? .none
        case .back:
            return .close
        case .left, .right, .playPause, .fastForward, .rewind, .home:
            return .none
        }
    }
}
