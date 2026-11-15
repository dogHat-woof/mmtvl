import Foundation

/// What a home tile menu item does (M7m L6, D50).
nonisolated enum TileMenuAction: String, Hashable, Sendable {
    case move, quit, restart, reloadYouTube, hide, startHere, toggleFullScreen, toggleRequiresPIN, tileSettings

    /// D20: edits ask for the PIN when one is set; Quit, Restart and Reload don't (a protected tile's reopen asks like
    /// a normal open). Tile Settings… asks once, as Settings' own PIN.
    var needsPIN: Bool {
        switch self {
        case .quit, .restart, .reloadYouTube: false
        case .move, .hide, .startHere, .toggleFullScreen, .toggleRequiresPIN, .tileSettings: true
        }
    }
}

/// M7m L5, L6 (D50): the menu Menu opens on a focused home tile. Pure, like `PowerMenu`: Up/Down move (clamped),
/// Select chooses, Back and Menu close.
nonisolated struct TileMenu: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        var action: TileMenuAction
        var title: String
        /// Right-aligned ("On", "Off"); nil = none.
        var value: String?
        var id: TileMenuAction { action }
    }

    enum Outcome: Equatable, Sendable { case none, close, choose(TileMenuAction) }

    let tileID: String
    let title: String
    private(set) var items: [Item]
    private(set) var focusedIndex = 0

    var focusedItem: Item { items[focusedIndex] }

    /// L6's table, in its order; items that don't apply are left out. `isRunning`: the tile's app runs (Quit and
    /// Restart); `youTubeOpened`: YouTube's web view exists (Reload YouTube). Security hardening: a tile whose app
    /// (`bundleID`, `AppLauncher.bundleID(for:)`) is MMTVL itself (`ownBundleID`) never offers Quit or Restart.
    static func make(for item: LaunchItem, isStartTile: Bool, isRunning: Bool, youTubeOpened: Bool,
                     ownBundleID: String? = nil, bundleID: String? = nil) -> TileMenu {
        var items = [Item(action: .move, title: "Move")]
        let isMMTVL = ownBundleID != nil && (bundleID ?? appBundleID(item)) == ownBundleID
        if isRunning && canQuit(item) && !isMMTVL {
            items.append(Item(action: .quit, title: "Quit \(item.title)"))
            items.append(Item(action: .restart, title: "Restart \(item.title)"))
        }
        if item.kind == .internalDestination(.youtube) && youTubeOpened {
            items.append(Item(action: .reloadYouTube, title: "Reload YouTube"))
        }
        if !item.isSettingsTile {
            items.append(Item(action: .hide, title: "Hide from Home Screen"))
        }
        if !item.isExitToDesktop {
            items.append(Item(action: .startHere, title: "Start Here", value: isStartTile ? "On" : nil))
        }
        if item.supportsFullScreen {
            items.append(Item(action: .toggleFullScreen, title: "Open Full Screen", value: onOff(item.wantsFullScreen)))
        }
        if !item.isSettingsTile && !item.isExitToDesktop {
            items.append(Item(action: .toggleRequiresPIN, title: "Require PIN", value: onOff(item.requiresPIN == true)))
        }
        items.append(Item(action: .tileSettings, title: "Tile Settings…"))
        return TileMenu(tileID: item.id, title: item.title, items: items)
    }

    /// L6: an app, the default browser, or a link with its own browser (a link in the default browser has no app to
    /// quit: `AppLauncher.bundleID(for:)` is nil).
    private static func canQuit(_ item: LaunchItem) -> Bool {
        switch item.kind {
        case .application, .defaultBrowser: true
        case .url(_, let browserBundleID): browserBundleID != nil
        case .internalDestination, .system: false
        }
    }

    /// The bundle id the tile names itself (an app, a link's browser); nil for the default browser and built-ins.
    private static func appBundleID(_ item: LaunchItem) -> String? {
        switch item.kind {
        case .application(let bundleID): bundleID
        case .url(_, let browserBundleID): browserBundleID
        case .defaultBrowser, .internalDestination, .system: nil
        }
    }

    private static func onOff(_ isOn: Bool) -> String { isOn ? "On" : "Off" }

    mutating func handle(_ command: RemoteCommand) -> Outcome {
        switch command {
        case .up, .down:
            focusedIndex = min(max(focusedIndex + (command == .up ? -1 : 1), 0), items.count - 1)
            return .none
        case .select:
            let item = focusedItem
            // L6: Start Here on the start tile does nothing.
            if item.action == .startHere && item.value != nil { return .none }
            return .choose(item.action)
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
