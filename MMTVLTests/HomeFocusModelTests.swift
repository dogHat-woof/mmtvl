import Testing
@testable import MMTVL

// Mutating calls are hoisted out of #expect, which can't call mutating members.
struct HomeFocusModelTests {
    @Test func startsOnFirstTile() {
        let model = HomeFocusModel(tileCount: 7, perRow: 5)
        #expect(model.tileIndex == 0)
        #expect(!model.isGearFocused)
    }

    @Test func upFromTopRowFocusesGear() {
        var model = HomeFocusModel(tileCount: 7, perRow: 5)
        let changed = model.move(.up)
        #expect(changed)
        #expect(model.isGearFocused)
        #expect(model.tileIndex == nil)
    }

    @Test func downFromGearReturnsToSameTile() {
        var model = HomeFocusModel(tileCount: 7, perRow: 5)
        model.focusTile(index: 3)
        model.move(.up)
        let changed = model.move(.down)
        #expect(changed)
        #expect(model.tileIndex == 3)
    }

    @Test func otherDirectionsOnGearDoNothing() {
        var model = HomeFocusModel(tileCount: 7, perRow: 5)
        model.move(.up)
        for command in [RemoteCommand.left, .right, .up] {
            let changed = model.move(command)
            #expect(!changed)
            #expect(model.isGearFocused)
        }
    }

    @Test func upFromSecondRowStaysInGrid() {
        var model = HomeFocusModel(tileCount: 7, perRow: 5)
        model.focusTile(index: 6)
        model.move(.up)
        #expect(!model.isGearFocused)
        #expect(model.tiles.position.row == 0)
    }

    @Test func noTilesFocusesGear() {
        var model = HomeFocusModel(tileCount: 0, perRow: 5)
        #expect(model.isGearFocused)
        let moved = model.move(.down)
        #expect(!moved)
        let left = model.leaveGear()
        #expect(!left)
    }

    @Test func focusTileLeavesGear() {
        var model = HomeFocusModel(tileCount: 7, perRow: 5)
        model.move(.up)
        let changed = model.focusTile(index: 6)
        #expect(changed)
        #expect(model.tileIndex == 6)
        #expect(!model.isGearFocused)
        let invalid = model.focusTile(index: 99)
        #expect(!invalid)
    }

    @Test func nonDirectionalCommandsDoNotMove() {
        var model = HomeFocusModel(tileCount: 7, perRow: 5)
        for command in [RemoteCommand.select, .back, .home, .playPause, .fastForward, .rewind] {
            let changed = model.move(command)
            #expect(!changed)
        }
    }
}
