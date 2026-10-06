@testable import MMTVL

/// The remote presses that enter `code` on the privacy keypad, starting with the highlight on `startRow`.
/// Up/Down to each digit's row, then Left/Select/Right for its column (`0` is Select on the last row).
func pinCommands(for code: String, startRow: Int = 0) -> [RemoteCommand] {
    var row = startRow
    var commands: [RemoteCommand] = []
    for character in code {
        let digit = Int(String(character))!
        let target = PINPad.rows.firstIndex { $0.contains(digit) }!
        let step: RemoteCommand = target > row ? .down : .up
        commands += Array(repeating: step, count: abs(target - row))
        row = target
        let digits = PINPad.rows[target]
        let column = digits.count == 1 ? 1 : digits.firstIndex(of: digit)!
        commands.append([RemoteCommand.left, .select, .right][column])
    }
    return commands
}
