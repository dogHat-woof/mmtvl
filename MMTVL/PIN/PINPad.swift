/// The privacy keypad (D20, L9): Up/Down moves a visible row highlight, and Left/Select/Right enters the
/// row's first/middle/last digit. Nothing shows which column was pressed, so a watcher can't read the PIN.
nonisolated struct PINPad: Equatable, Sendable {
    static let length = 4
    static let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9], [0]]

    enum Event: Equatable, Sendable {
        case changed
        case submitted(String)
        case cancelled
        case ignored
    }

    private(set) var row = 0
    private(set) var digits: [Int] = []

    var isFull: Bool { digits.count >= Self.length }

    mutating func handle(_ command: RemoteCommand) -> Event {
        switch command {
        case .up: moveRow(by: -1)
        case .down: moveRow(by: 1)
        case .left: enterColumn(0)
        case .select: enterColumn(1)
        case .right: enterColumn(2)
        case .back:
            if digits.isEmpty { .cancelled } else { deleteLast() }
        case .home, .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown: .ignored
        }
    }

    /// Mouse click on the small keypad. Column is clamped to the row's length; the highlight moves to `row`.
    mutating func enter(row: Int, column: Int) -> Event {
        guard Self.rows.indices.contains(row) else { return .ignored }
        self.row = row
        let digits = Self.rows[row]
        return append(digits[min(max(column, 0), digits.count - 1)])
    }

    /// After a wrong PIN or between stages.
    mutating func clear() {
        row = 0
        digits = []
    }

    private mutating func moveRow(by step: Int) -> Event {
        let target = min(max(row + step, 0), Self.rows.count - 1)
        guard target != row else { return .ignored }
        row = target
        return .changed
    }

    /// The 0 row has only a middle digit (the D-pad circle shows it in the center), so only Select enters it.
    private mutating func enterColumn(_ column: Int) -> Event {
        let digits = Self.rows[row]
        if digits.count == 1 {
            return column == 1 ? append(digits[0]) : .ignored
        }
        return append(digits[column])
    }

    private mutating func append(_ digit: Int) -> Event {
        guard !isFull else { return .ignored }
        digits.append(digit)
        return isFull ? .submitted(digits.map(String.init).joined()) : .changed
    }

    private mutating func deleteLast() -> Event {
        digits.removeLast()
        return .changed
    }
}
