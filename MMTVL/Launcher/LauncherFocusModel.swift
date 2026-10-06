/// Directional focus over a grid of rows (D2). Pure value type; views render focus from it.
nonisolated struct LauncherFocusModel: Equatable, Sendable {
    struct Position: Equatable, Sendable {
        var row: Int
        var column: Int
    }

    /// Item count per row.
    var rows: [Int]
    var position = Position(row: 0, column: 0)

    init(rows: [Int]) {
        self.rows = rows
        if let firstRow = rows.firstIndex(where: { $0 > 0 }) {
            position = Position(row: firstRow, column: 0)
        }
    }

    /// Chunks `itemCount` items into rows of `perRow`.
    init(itemCount: Int, perRow: Int) {
        let perRow = max(perRow, 1)
        let itemCount = max(itemCount, 0)
        let rows = stride(from: 0, to: itemCount, by: perRow).map { min(perRow, itemCount - $0) }
        self.init(rows: rows)
    }

    var isEmpty: Bool { rows.allSatisfy { $0 == 0 } }

    /// Flat index of the focused item, or nil when there are no items.
    var index: Int? {
        guard !isEmpty else { return nil }
        return rows.prefix(position.row).reduce(0, +) + position.column
    }

    /// Moves focus to a flat item index (e.g. on mouse hover). Returns true if the position changed.
    @discardableResult
    mutating func focus(index: Int) -> Bool {
        var remaining = index
        for (row, count) in rows.enumerated() {
            if remaining < count {
                let newPosition = Position(row: row, column: remaining)
                guard newPosition != position else { return false }
                position = newPosition
                return true
            }
            remaining -= count
        }
        return false
    }

    /// Applies a directional command. Returns true if the position changed.
    @discardableResult
    mutating func move(_ command: RemoteCommand) -> Bool {
        guard !isEmpty else { return false }
        switch command {
        case .left:
            guard position.column > 0 else { return false }
            position.column -= 1
            return true
        case .right:
            guard position.column < rows[position.row] - 1 else { return false }
            position.column += 1
            return true
        case .up:
            return moveRow(step: -1)
        case .down:
            return moveRow(step: 1)
        case .select, .back, .home, .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown:
            return false
        }
    }

    /// Moves to the next non-empty row in `step` direction, clamping the column to that row.
    private mutating func moveRow(step: Int) -> Bool {
        var row = position.row + step
        while rows.indices.contains(row) {
            if rows[row] > 0 {
                position = Position(row: row, column: min(position.column, rows[row] - 1))
                return true
            }
            row += step
        }
        return false
    }
}
