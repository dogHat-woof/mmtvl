import Foundation
import Testing
@testable import MMTVL

struct MultiviewModelTests {
    private let all: Set<Channel.ID> = ["a", "b", "c", "d", "e", "p", "q", "r", "s", "t", "x", "y"]

    // MARK: init

    @Test func initPadsClampsAndPicksAudio() {
        let model = MultiviewModel(layout: .onePlusFour, slots: ["a", nil], focusedSlot: 9)
        #expect(model.slots == ["a", nil, nil, nil, nil])
        #expect(model.focusedSlot == 4)
        #expect(model.audioSlot == 0)

        let focused = MultiviewModel(layout: .sideBySide, slots: ["a", "b", "c"], focusedSlot: 1)
        #expect(focused.slots == ["a", "b"])
        #expect(focused.audioSlot == 1)

        let empty = MultiviewModel(layout: .grid, slots: [])
        #expect(empty.isEmpty)
        #expect(empty.audioSlot == nil)
        #expect(empty.audioChannelID == nil)
    }

    // MARK: entering

    @Test func enteringWithoutSnapshot() {
        let model = MultiviewModel.entering(snapshot: nil, current: "a", adding: "b", validIDs: all)
        #expect(model.layout == .onePlusFour)
        #expect(model.slots == ["a", "b", nil, nil, nil])
        #expect(model.focusedSlot == 1)
        #expect(model.audioSlot == 1)

        let nothingPlaying = MultiviewModel.entering(snapshot: nil, current: nil, adding: "b", validIDs: all)
        #expect(nothingPlaying.slots == ["b", nil, nil, nil, nil])
        #expect(nothingPlaying.focusedSlot == 0)

        let same = MultiviewModel.entering(snapshot: nil, current: "a", adding: "a", validIDs: all)
        #expect(same.slots == ["a", nil, nil, nil, nil])
    }

    @Test func enteringWithSnapshot() {
        let snapshot = MultiviewSnapshot(layout: .onePlusFour, slots: ["x", nil, "y", nil, nil], focusedSlot: 2, isActive: false)
        let model = MultiviewModel.entering(snapshot: snapshot, current: "a", adding: "b", validIDs: all)
        #expect(model.slots == ["x", "a", "y", "b", nil])
        #expect(model.focusedSlot == 3)
        #expect(model.audioSlot == 3)

        let invalid = MultiviewModel.entering(snapshot: snapshot, current: "a", adding: "b", validIDs: all.subtracting(["y"]))
        #expect(invalid.slots == ["x", "a", "b", nil, nil])

        let present = MultiviewModel.entering(snapshot: snapshot, current: nil, adding: "x", validIDs: all)
        #expect(present.slots == ["x", nil, "y", nil, nil])
        #expect(present.focusedSlot == 0)
    }

    @Test func enteringAFullSnapshot() {
        let snapshot = MultiviewSnapshot(layout: .onePlusFour, slots: ["p", "q", "r", "s", "t"], focusedSlot: 0, isActive: false)
        let model = MultiviewModel.entering(snapshot: snapshot, current: "a", adding: "b", validIDs: all)
        #expect(model.slots == ["p", "q", "r", "b", "a"])
        #expect(model.focusedSlot == 3)
    }

    @Test func enteringAFullSideBySide() {
        let snapshot = MultiviewSnapshot(layout: .sideBySide, slots: ["p", "q"], focusedSlot: 0, isActive: false)
        let model = MultiviewModel.entering(snapshot: snapshot, current: "a", adding: "b", validIDs: all)
        #expect(model.slots == ["b", "a"])
        #expect(model.focusedSlot == 0)
    }

    // MARK: moveFocus

    @Test func moveFocus() {
        var model = MultiviewModel(layout: .onePlusFour, slots: ["a", "b"], focusedSlot: 1)
        let r1 = model.moveFocus(.up)
        #expect(r1)
        #expect(model.focusedSlot == 0)
        #expect(model.audioSlot == 0)
        let r2 = model.moveFocus(.down)
        #expect(r2)
        #expect(model.focusedSlot == 2)
        #expect(model.audioSlot == 0)
        #expect(model.audioChannelID == "a")
        let r3 = model.moveFocus(.right)
        #expect(r3)
        let r4 = model.moveFocus(.right)
        #expect(r4)
        let r5 = model.moveFocus(.right)
        #expect(r5 == false)
        #expect(model.focusedSlot == 4)
    }

    // MARK: setLayout

    @Test func setLayoutDropsFromTheEndButKeepsTheSound() {
        var model = MultiviewModel(layout: .onePlusFour, slots: ["a", "b", "c", "d", "e"], focusedSlot: 4)
        let dropped = model.setLayout(.sideBySide)
        #expect(Set(dropped) == ["b", "c", "d"])
        #expect(model.slots == ["a", "e"])
        #expect(model.focusedSlot == 1)
        #expect(model.audioSlot == 1)
    }

    @Test func setLayoutToALargerLayoutCompacts() {
        var model = MultiviewModel(layout: .onePlusFour, slots: [nil, "a", nil, "b", nil], focusedSlot: 3)
        let dropped = model.setLayout(.grid)
        #expect(dropped.isEmpty)
        #expect(model.slots == ["a", "b", nil, nil])
        #expect(model.focusedSlot == 1)
        #expect(model.audioSlot == 1)
    }

    // MARK: assign

    @Test func assign() {
        var model = MultiviewModel(layout: .onePlusFour, slots: ["a", "b"], focusedSlot: 0)
        let r6 = model.assign("c", to: 2)
        #expect(r6 == nil)
        #expect(model.slots == ["a", "b", "c", nil, nil])
        #expect(model.focusedSlot == 2)
        #expect(model.audioSlot == 2)

        let r7 = model.assign("d", to: 1)

        #expect(r7 == "b")
        #expect(model.slots == ["a", "d", "c", nil, nil])
        #expect(model.focusedSlot == 1)

        let r8 = model.assign("a", to: 2)

        #expect(r8 == nil)
        #expect(model.slots == ["c", "d", "a", nil, nil])
        #expect(model.focusedSlot == 2)
        #expect(model.audioSlot == 2)

        let r9 = model.assign("a", to: 2)

        #expect(r9 == nil)
        #expect(model.slots == ["c", "d", "a", nil, nil])
    }

    // MARK: makeMain

    @Test func makeMain() {
        var model = MultiviewModel(layout: .onePlusFour, slots: ["a", "b", "c"], focusedSlot: 2)
        model.makeMain(2)
        #expect(model.slots == ["c", "b", "a", nil, nil])
        #expect(model.focusedSlot == 0)
        #expect(model.audioSlot == 0)

        var grid = MultiviewModel(layout: .grid, slots: ["a", "b"], focusedSlot: 1)
        grid.makeMain(1)
        #expect(grid.slots == ["a", "b", nil, nil])
        #expect(grid.focusedSlot == 1)
    }

    // MARK: rotate (M7f L6)

    @Test func rotateMovesEveryChannelThroughTheMainWindow() {
        var right = MultiviewModel(layout: .onePlusFour, slots: ["a", "b", "c", "d", "e"])
        let rotated1 = right.rotate(by: 1)
        #expect(rotated1)
        #expect(right.slots == ["b", "c", "d", "e", "a"])
        #expect(right.focusedSlot == 0)
        #expect(right.audioSlot == 0)
        #expect(right.audioChannelID == "b")

        var left = MultiviewModel(layout: .onePlusFour, slots: ["a", "b", "c", "d", "e"])
        let rotated2 = left.rotate(by: -1)
        #expect(rotated2)
        #expect(left.slots == ["e", "a", "b", "c", "d"])
        #expect(left.focusedSlot == 0)
        #expect(left.audioChannelID == "e")

        var pip = MultiviewModel(layout: .pictureInPicture, slots: ["a", "b"])
        let rotated3 = pip.rotate(by: 1)
        #expect(rotated3)
        #expect(pip.slots == ["b", "a"])
    }

    @Test func rotateSkipsEmptyWindows() {
        var model = MultiviewModel(layout: .onePlusFour, slots: ["a", "b", nil, "d", nil])
        let rotated4 = model.rotate(by: 1)
        #expect(rotated4)
        #expect(model.slots == ["b", "d", nil, "a", nil])
        let rotated5 = model.rotate(by: -1)
        #expect(rotated5)
        #expect(model.slots == ["a", "b", nil, "d", nil])
    }

    @Test func rotateNeedsAMainWindowAndTwoChannels() {
        var grid = MultiviewModel(layout: .grid, slots: ["a", "b", "c", "d"])
        let rotated6 = grid.rotate(by: 1)
        #expect(rotated6 == false)
        #expect(grid.slots == ["a", "b", "c", "d"])

        var sideBySide = MultiviewModel(layout: .sideBySide, slots: ["a", "b"])
        let rotated7 = sideBySide.rotate(by: -1)
        #expect(rotated7 == false)
        #expect(sideBySide.slots == ["a", "b"])

        var single = MultiviewModel(layout: .onePlusFour, slots: ["a"])
        let rotated8 = single.rotate(by: 1)
        #expect(rotated8 == false)
        #expect(single.slots == ["a", nil, nil, nil, nil])
    }

    @Test func focusSetsTheHighlightAndSoundFollowsAFilledWindow() {
        var model = MultiviewModel(layout: .onePlusThree, slots: ["a", "b"])
        model.focus(1)
        #expect(model.focusedSlot == 1)
        #expect(model.audioSlot == 1)
        model.focus(2)
        #expect(model.focusedSlot == 2)
        #expect(model.audioSlot == 1)
        model.focus(9)
        #expect(model.focusedSlot == 2)
    }

    // MARK: remove

    @Test func remove() {
        var model = MultiviewModel(layout: .onePlusFour, slots: ["a", "b", "c"], focusedSlot: 2)
        let r10 = model.remove(1)
        #expect(r10 == "b")
        #expect(model.audioSlot == 2)
        let r11 = model.remove(2)
        #expect(r11 == "c")
        #expect(model.audioSlot == 0)
        #expect(model.focusedSlot == 2)
        let r12 = model.remove(0)
        #expect(r12 == "a")
        #expect(model.audioSlot == nil)
        #expect(model.isEmpty)
    }

    // MARK: Snapshots

    @Test func snapshotsRoundTrip() throws {
        let model = MultiviewModel(layout: .onePlusThree, slots: ["a", nil, "c"], focusedSlot: 2)
        let snapshot = model.snapshot(isActive: true)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MultiviewSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(MultiviewModel(snapshot: decoded, validIDs: all) == model)

        let filtered = MultiviewModel(snapshot: decoded, validIDs: ["c"])
        #expect(filtered.slots == [nil, nil, "c", nil])
    }
}
