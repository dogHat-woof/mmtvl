/// M7f L11 (D41): MMTVL's own text entry, a tvOS-style alphabetical grid driven by `RemoteCommand`s.
/// Pure; a screen keeps one and draws it with `OnScreenKeyboardView`.
nonisolated struct OnScreenKeyboard: Equatable, Sendable {
    static let maxLength = 40
    /// Every row is laid out on this many columns; wide keys span several.
    static let columns = 7

    enum Mode: Equatable, Sendable { case letters, digits }

    enum Key: Equatable, Sendable {
        case character(Character)
        case space, delete
        /// 123 in letters mode, abc in digits mode: switches to `Mode`.
        case mode(Mode)

        var span: Int {
            switch self {
            case .character: 1
            case .space: 3
            case .delete, .mode: 2
            }
        }

        var title: String {
            switch self {
            case .character(let c): String(c)
            case .space: "Space"
            case .delete: "Delete"
            case .mode(.digits): "123"
            case .mode(.letters): "abc"
            }
        }
    }

    /// The focused key: its row, and its index in that row (not its column).
    struct Focus: Equatable, Sendable {
        var row: Int
        var key: Int
    }

    enum Outcome: Equatable, Sendable {
        /// Nothing the caller must act on (focus or mode may have changed).
        case none
        /// `text` changed.
        case changed
        /// Right from a row's last key: the screen moves focus to what's right of the keyboard.
        case leaveRight
        /// Up from the top row.
        case leaveUp
        case back
    }

    private(set) var text = ""
    private(set) var mode = Mode.letters
    private(set) var focus = Focus(row: 0, key: 0)

    init(text: String = "") {
        self.text = String(text.prefix(Self.maxLength))
    }

    static func rows(for mode: Mode) -> [[Key]] {
        let bottom: [Key] = [.space, .delete, .mode(mode == .letters ? .digits : .letters)]
        let characterRows: [String] = switch mode {
        case .letters: ["abcdefg", "hijklmn", "opqrstu", "vwxyz"]
        case .digits: ["1234567", "890&'-."]
        }
        return characterRows.map { $0.map(Key.character) } + [bottom]
    }

    var rows: [[Key]] { Self.rows(for: mode) }

    var focusedKey: Key { rows[focus.row][focus.key] }

    mutating func handle(_ command: RemoteCommand) -> Outcome {
        switch command {
        case .left:
            if focus.key > 0 { focus.key -= 1 }
            return .none
        case .right:
            guard focus.key < rows[focus.row].count - 1 else { return .leaveRight }
            focus.key += 1
            return .none
        case .up:
            guard focus.row > 0 else { return .leaveUp }
            moveVertically(to: focus.row - 1)
            return .none
        case .down:
            if focus.row < rows.count - 1 { moveVertically(to: focus.row + 1) }
            return .none
        case .select:
            return press(focusedKey)
        case .playPause:
            return deleteLast()
        case .back:
            return .back
        case .home, .fastForward, .rewind, .menu, .channelUp, .channelDown:
            return .none
        }
    }

    /// Phone text (L11): deletions, then the insertion, clamped to `maxLength`.
    mutating func apply(_ edit: TextEdit) {
        text.removeLast(min(edit.deletions, text.count))
        text = String((text + edit.insertion).prefix(Self.maxLength))
    }

    mutating func clear() {
        text = ""
    }

    private mutating func press(_ key: Key) -> Outcome {
        switch key {
        case .character(let c): return type(String(c))
        case .space: return type(" ")
        case .delete: return deleteLast()
        case .mode(let newMode):
            mode = newMode
            // Focus stays on the mode key, now on the new layout's bottom row.
            let bottom = rows.count - 1
            focus = Focus(row: bottom, key: rows[bottom].count - 1)
            return .none
        }
    }

    private mutating func type(_ string: String) -> Outcome {
        guard text.count < Self.maxLength else { return .none }
        text += string
        return .changed
    }

    private mutating func deleteLast() -> Outcome {
        guard !text.isEmpty else { return .none }
        text.removeLast()
        return .changed
    }

    /// Lands on the key covering the focused key's first column; a short row clamps to its last key.
    private mutating func moveVertically(to row: Int) {
        let column = Self.startColumn(of: focus.key, in: rows[focus.row])
        let target = rows[row]
        var start = 0
        for (index, key) in target.enumerated() {
            if column < start + key.span {
                focus = Focus(row: row, key: index)
                return
            }
            start += key.span
        }
        focus = Focus(row: row, key: target.count - 1)
    }

    static func startColumn(of index: Int, in row: [Key]) -> Int {
        row.prefix(index).reduce(0) { $0 + $1.span }
    }
}
