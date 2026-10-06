import Testing
@testable import MMTVL

// Mutating calls are hoisted out of #expect, which can't call mutating members.
struct LauncherFocusModelTests {
    @Test func chunksItemsIntoRows() {
        #expect(LauncherFocusModel(itemCount: 6, perRow: 5).rows == [5, 1])
        #expect(LauncherFocusModel(itemCount: 10, perRow: 5).rows == [5, 5])
        #expect(LauncherFocusModel(itemCount: 0, perRow: 5).rows == [])
    }

    @Test func startsOnFirstItem() {
        let model = LauncherFocusModel(itemCount: 6, perRow: 5)
        #expect(model.position == .init(row: 0, column: 0))
        #expect(model.index == 0)
    }

    @Test func clampsAtRowEdges() {
        var model = LauncherFocusModel(itemCount: 6, perRow: 5)
        var changed = model.move(.left)
        #expect(!changed)
        for _ in 0..<4 {
            changed = model.move(.right)
            #expect(changed)
        }
        #expect(model.position.column == 4)
        changed = model.move(.right)
        #expect(!changed)
        #expect(model.position.column == 4)
    }

    @Test func downIntoShorterRowClampsColumn() {
        var model = LauncherFocusModel(itemCount: 7, perRow: 5)
        model.focus(index: 4)
        var changed = model.move(.down)
        #expect(changed)
        #expect(model.position == .init(row: 1, column: 1))
        #expect(model.index == 6)
        // Up keeps the (clamped) column.
        changed = model.move(.up)
        #expect(changed)
        #expect(model.position == .init(row: 0, column: 1))
    }

    @Test func cannotMovePastFirstOrLastRow() {
        var model = LauncherFocusModel(itemCount: 6, perRow: 5)
        var changed = model.move(.up)
        #expect(!changed)
        changed = model.move(.down)
        #expect(changed)
        changed = model.move(.down)
        #expect(!changed)
        #expect(model.position == .init(row: 1, column: 0))
    }

    @Test func skipsEmptyRows() {
        var model = LauncherFocusModel(rows: [3, 0, 2])
        var changed = model.move(.down)
        #expect(changed)
        #expect(model.position.row == 2)
        changed = model.move(.up)
        #expect(changed)
        #expect(model.position.row == 0)
    }

    @Test func singleItemNeverMoves() {
        var model = LauncherFocusModel(itemCount: 1, perRow: 5)
        for command in [RemoteCommand.up, .down, .left, .right] {
            let changed = model.move(command)
            #expect(!changed)
        }
        #expect(model.index == 0)
    }

    @Test func zeroItemsIsSafe() {
        var model = LauncherFocusModel(itemCount: 0, perRow: 5)
        for command in [RemoteCommand.up, .down, .left, .right, .select] {
            let changed = model.move(command)
            #expect(!changed)
        }
        #expect(model.index == nil)
        let changed = model.focus(index: 0)
        #expect(!changed)
    }

    @Test func nonDirectionalCommandsDoNotMove() {
        var model = LauncherFocusModel(itemCount: 6, perRow: 5)
        for command in [RemoteCommand.select, .back, .home, .playPause, .fastForward, .rewind] {
            let changed = model.move(command)
            #expect(!changed)
        }
    }

    @Test func focusByIndex() {
        var model = LauncherFocusModel(itemCount: 6, perRow: 5)
        var changed = model.focus(index: 5)
        #expect(changed)
        #expect(model.position == .init(row: 1, column: 0))
        changed = model.focus(index: 5)
        #expect(!changed)
        changed = model.focus(index: 99)
        #expect(!changed)
    }
}
