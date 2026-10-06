/// Focus on the home screen (D2): the tile grid plus the gear by the clock, which sits "above" the top row.
nonisolated struct HomeFocusModel: Equatable, Sendable {
    private(set) var tiles: LauncherFocusModel
    private(set) var isGearFocused: Bool

    init(tileCount: Int, perRow: Int) {
        tiles = LauncherFocusModel(itemCount: tileCount, perRow: perRow)
        isGearFocused = tiles.isEmpty
    }

    /// Flat index of the focused tile; nil while the gear is focused.
    var tileIndex: Int? { isGearFocused ? nil : tiles.index }

    /// Tiles: directions move inside the grid; Up on the top row focuses the gear.
    /// Gear: Down returns to the same tile (if there are tiles); other directions do nothing.
    /// Returns true if focus changed.
    @discardableResult
    mutating func move(_ command: RemoteCommand) -> Bool {
        switch command {
        case .up, .down, .left, .right:
            if isGearFocused {
                return command == .down ? leaveGear() : false
            }
            if tiles.move(command) { return true }
            return command == .up ? focusGear() : false
        case .select, .back, .home, .playPause, .fastForward, .rewind:
            return false
        }
    }

    /// Focuses a tile (also leaves the gear). False if the index is out of range or nothing changed.
    @discardableResult
    mutating func focusTile(index: Int) -> Bool {
        guard index >= 0, index < tiles.rows.reduce(0, +) else { return false }
        let wasGear = isGearFocused
        isGearFocused = false
        let moved = tiles.focus(index: index)
        return wasGear || moved
    }

    @discardableResult
    mutating func focusGear() -> Bool {
        guard !isGearFocused else { return false }
        isGearFocused = true
        return true
    }

    @discardableResult
    mutating func leaveGear() -> Bool {
        guard isGearFocused, !tiles.isEmpty else { return false }
        isGearFocused = false
        return true
    }
}
