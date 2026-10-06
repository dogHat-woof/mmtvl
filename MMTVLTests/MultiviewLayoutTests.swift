import CoreGraphics
import Testing
@testable import MMTVL

struct MultiviewLayoutTests {
    private let canvas = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func capacitiesAndMainSlots() {
        #expect(MultiviewLayout.allCases.map(\.capacity) == [5, 4, 4, 3, 2, 2])
        #expect(MultiviewLayout.allCases.map(\.mainSlot) == [0, 0, nil, 0, nil, 0])
        #expect(MultiviewLayout.allCases.map(\.title) == ["1 + 4", "1 + 3", "2 × 2", "1 + 2", "Side by Side", "Picture in Picture"])
    }

    @Test(arguments: MultiviewLayout.allCases)
    func rawSlotsAre16x9InsideTheCanvas(_ layout: MultiviewLayout) {
        for rect in layout.rawSlots {
            #expect(abs(rect.width / rect.height - 16.0 / 9.0) < 0.001)
            #expect(canvas.contains(rect))
        }
    }

    @Test(arguments: MultiviewLayout.allCases.filter { $0 != .pictureInPicture })
    func rawSlotsTileTheCanvas(_ layout: MultiviewLayout) {
        let rects = layout.rawSlots
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height == 0, "\(layout) slots \(i) and \(j)")
            }
        }
        let area: CGFloat = rects.reduce(0) { $0 + $1.width * $1.height }
        let canvasArea: CGFloat = 1920 * 1080
        // Every window is 16:9, so all but 2 × 2 leave black bars (1 + 4's beside the big window).
        if layout == .grid {
            #expect(area == canvasArea)
        } else {
            #expect(area < canvasArea)
        }
    }

    @Test(arguments: MultiviewLayout.allCases)
    func slotsAreInset(_ layout: MultiviewLayout) {
        for (index, raw) in layout.rawSlots.enumerated() {
            if layout == .pictureInPicture && index == 0 {
                #expect(layout.slots[index] == CGRect(x: 0, y: 0, width: 1920, height: 1080))
            } else {
                #expect(layout.slots[index] == raw.insetBy(dx: 4, dy: 4))
            }
        }
    }

    @Test func onePlusFourMatchesTheTable() {
        #expect(MultiviewLayout.onePlusFour.rawSlots == [
            CGRect(x: 240, y: 0, width: 1440, height: 810),
            CGRect(x: 0, y: 810, width: 480, height: 270), CGRect(x: 480, y: 810, width: 480, height: 270),
            CGRect(x: 960, y: 810, width: 480, height: 270), CGRect(x: 1440, y: 810, width: 480, height: 270),
        ])
    }

    @Test func onePlusFourNeighbors() {
        let layout = MultiviewLayout.onePlusFour
        #expect(layout.neighbor(of: 0, .down) == 2)
        #expect(layout.neighbor(of: 0, .left) == nil)
        #expect(layout.neighbor(of: 0, .right) == nil)
        #expect(layout.neighbor(of: 0, .up) == nil)
        #expect(layout.neighbor(of: 1, .up) == 0)
        #expect(layout.neighbor(of: 2, .up) == 0)
        #expect(layout.neighbor(of: 4, .up) == 0)
        #expect(layout.neighbor(of: 1, .right) == 2)
        #expect(layout.neighbor(of: 3, .left) == 2)
        #expect(layout.neighbor(of: 4, .right) == nil)
    }

    @Test func onePlusThreeNeighbors() {
        let layout = MultiviewLayout.onePlusThree
        #expect(layout.neighbor(of: 0, .right) == 2)
        #expect(layout.neighbor(of: 1, .left) == 0)
        #expect(layout.neighbor(of: 1, .down) == 2)
        #expect(layout.neighbor(of: 3, .down) == nil)
        #expect(layout.neighbor(of: 0, .up) == nil)
    }

    @Test func gridNeighbors() {
        let layout = MultiviewLayout.grid
        #expect(layout.neighbor(of: 0, .right) == 1)
        #expect(layout.neighbor(of: 0, .down) == 2)
        #expect(layout.neighbor(of: 1, .down) == 3)
        #expect(layout.neighbor(of: 3, .left) == 2)
        #expect(layout.neighbor(of: 3, .up) == 1)
    }

    @Test func onePlusTwoNeighbors() {
        let layout = MultiviewLayout.onePlusTwo
        #expect(layout.neighbor(of: 0, .right) == 1)
        #expect(layout.neighbor(of: 2, .left) == 0)
    }

    @Test func pictureInPictureNeighbors() {
        let layout = MultiviewLayout.pictureInPicture
        #expect(layout.neighbor(of: 0, .right) == 1)
        #expect(layout.neighbor(of: 0, .down) == 1)
        #expect(layout.neighbor(of: 1, .left) == 0)
        #expect(layout.neighbor(of: 1, .up) == 0)
        #expect(layout.neighbor(of: 1, .right) == nil)
    }

    @Test func sideBySideNeighbors() {
        let layout = MultiviewLayout.sideBySide
        #expect(layout.neighbor(of: 0, .right) == 1)
        #expect(layout.neighbor(of: 1, .right) == nil)
        #expect(layout.neighbor(of: 0, .down) == nil)
    }

    @Test func directionFromCommand() {
        #expect(MultiviewLayout.Direction(RemoteCommand.select) == nil)
        #expect(MultiviewLayout.Direction(RemoteCommand.left) == .left)
    }
}
