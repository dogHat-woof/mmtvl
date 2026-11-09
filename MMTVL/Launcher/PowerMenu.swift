import Foundation

/// What a power menu item does (M7h L15).
nonisolated enum PowerMenuAction: String, Hashable, Sendable, CaseIterable {
    case turnOff, sleepMac, relaunch, restartMac, cancel

    /// Relaunch and Restart ask for the PIN when one is set (D20).
    var needsPIN: Bool { self == .relaunch || self == .restartMac }
}

/// Why the power menu closed (`AppRouter.onPowerMenuClose`).
nonisolated enum PowerMenuCloseReason: Equatable, Sendable {
    /// Cancel, Back or Menu.
    case cancelled
    /// Home.
    case home
    /// An item, Power, or a screen change (a cast, the guard's goHome).
    case other
}

/// M7h L15: the power menu (Power held), over any screen. Pure, like `LiveMenu`. Up/Down move (clamped), Select
/// chooses, Back and Menu close.
nonisolated struct PowerMenu: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        var action: PowerMenuAction
        var title: String
        var id: PowerMenuAction { action }
    }

    enum Outcome: Equatable, Sendable { case none, close, choose(PowerMenuAction) }

    static let title = "Power"
    static let allItems: [Item] = [
        Item(action: .turnOff, title: "Turn Off TV & Receiver"),
        Item(action: .sleepMac, title: "Sleep Mac mini"),
        Item(action: .relaunch, title: "Relaunch MMTVL"),
        Item(action: .restartMac, title: "Restart Mac mini"),
        Item(action: .cancel, title: "Cancel"),
    ]

    let items: [Item] = PowerMenu.allItems
    private(set) var focusedIndex = 0

    var focusedItem: Item { items[focusedIndex] }

    mutating func handle(_ command: RemoteCommand) -> Outcome {
        switch command {
        case .up, .down:
            focusedIndex = min(max(focusedIndex + (command == .up ? -1 : 1), 0), items.count - 1)
            return .none
        case .select:
            return focusedItem.action == .cancel ? .close : .choose(focusedItem.action)
        case .back, .menu:
            return .close
        case .left, .right, .playPause, .fastForward, .rewind, .channelUp, .channelDown, .home,
             .volumeUp, .volumeDown, .mute, .power, .powerMenu:
            return .none
        }
    }

    /// A click on a row.
    mutating func choose(index: Int) -> Outcome {
        guard items.indices.contains(index) else { return .none }
        focusedIndex = index
        return handle(.select)
    }

    /// Hover.
    mutating func focus(index: Int) {
        guard items.indices.contains(index) else { return }
        focusedIndex = index
    }
}
