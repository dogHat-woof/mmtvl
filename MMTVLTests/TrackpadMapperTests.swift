import Foundation
import Testing
@testable import MMTVL

/// M7h L7: trackpad mode's motion.
struct TrackpadMapperTests {
    private func touching(_ x: Double, _ y: Double, at time: TimeInterval = 0) -> TouchFrame {
        TouchFrame(count: 1, state: TouchFrame.touchingState, x: x, y: y, timestamp: time)
    }

    private let lift = TouchFrame(count: 0, state: 0, x: 0, y: 0, timestamp: 0)

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000_1 }

    private func isMove(_ action: PointerAction?, dx: Double, dy: Double) -> Bool {
        guard case .move(let x, let y) = action else { return false }
        return close(x, dx) && close(y, dy)
    }

    private func isScroll(_ action: PointerAction?, dx: Double, dy: Double) -> Bool {
        guard case .scroll(let x, let y) = action else { return false }
        return close(x, dx) && close(y, dy)
    }

    @Test func firstFrameOnlyAnchors() {
        var mapper = TrackpadMapper()
        #expect(mapper.feed(touching(0.5, 0.5)).isEmpty)
        #expect(mapper.role == .pointer)
    }

    /// QA: the start of each touch (for the debug log) is reported once, on the frame that began it.
    @Test func touchStartOnlyOnTheFirstFrame() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.91, 0.4))
        #expect(mapper.touchStart?.x == 0.91)
        #expect(mapper.touchStart?.y == 0.4)
        #expect(mapper.role == .verticalScroll)
        _ = mapper.feed(touching(0.91, 0.42, at: 0.02))
        #expect(mapper.touchStart == nil)
        _ = mapper.feed(lift)
        #expect(mapper.touchStart == nil)
        _ = mapper.feed(touching(0.5, 0.05, at: 1))
        #expect(mapper.touchStart?.y == 0.05)
        #expect(mapper.role == .horizontalScroll)
    }

    @Test func deltasScaleAndInvertY() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.5, 0.5))
        // Right 0.01 and up 0.02 on the remote: right 12 and up 24 points (screen y grows downward).
        let actions = mapper.feed(touching(0.51, 0.52))
        #expect(actions.count == 1)
        #expect(isMove(actions.first, dx: 0.01 * TrackpadMapper.pointerScale, dy: -0.02 * TrackpadMapper.pointerScale))
        #expect(isMove(actions.first, dx: 12, dy: -24))
        // Down and left.
        #expect(isMove(mapper.feed(touching(0.5, 0.5)).first, dx: -12, dy: 24))
    }

    @Test func stillFingerMovesNothing() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.4, 0.4))
        #expect(mapper.feed(touching(0.4, 0.4)).isEmpty)
    }

    @Test func rightEdgeScrollsVerticallyOnly() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.9, 0.5))
        #expect(mapper.role == .verticalScroll)
        // Up 0.05 with sideways drift: the content follows the finger up, no horizontal scroll, no pointer move.
        let actions = mapper.feed(touching(0.8, 0.55))
        #expect(actions.count == 1)
        #expect(isScroll(actions.first, dx: 0, dy: -0.05 * TrackpadMapper.scrollScale))
        // It stays a scroll after leaving the edge; a sideways-only move scrolls nothing.
        #expect(mapper.feed(touching(0.5, 0.55)).isEmpty)
        #expect(isScroll(mapper.feed(touching(0.5, 0.45)).first, dx: 0, dy: 60))
    }

    @Test func bottomEdgeScrollsHorizontally() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.5, 0.1))
        #expect(mapper.role == .horizontalScroll)
        let actions = mapper.feed(touching(0.6, 0.15))
        #expect(actions.count == 1)
        #expect(isScroll(actions.first, dx: 0.1 * TrackpadMapper.scrollScale, dy: 0))
        // An up-only move scrolls nothing.
        #expect(mapper.feed(touching(0.6, 0.4)).isEmpty)
    }

    @Test func cornerScrollsVertically() {
        #expect(TrackpadMapper.role(startingAt: 0.9, 0.1) == .verticalScroll)
        #expect(TrackpadMapper.role(startingAt: 0.85, 0.5) == .verticalScroll)
        #expect(TrackpadMapper.role(startingAt: 0.84, 0.12) == .horizontalScroll)
        #expect(TrackpadMapper.role(startingAt: 0.84, 0.13) == .pointer)
    }

    @Test func liftResets() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.5, 0.5))
        _ = mapper.feed(touching(0.6, 0.5))
        #expect(mapper.feed(lift).isEmpty)
        #expect(mapper.role == nil)
        // The next touch starts elsewhere: no jump, and its own start decides its role.
        #expect(mapper.feed(touching(0.9, 0.3)).isEmpty)
        #expect(mapper.role == .verticalScroll)
        #expect(isScroll(mapper.feed(touching(0.9, 0.4)).first, dx: 0, dy: -60))
    }

    @Test func anotherFingerIsANewTouch() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.2, 0.5))
        // Finger 1 lifts while finger 2 at 0.8 stays: no 720-point jump.
        var second = touching(0.8, 0.5)
        second.identifier = 2
        #expect(mapper.feed(second).isEmpty)
        #expect(mapper.role == .pointer)
        // Finger 2 then moves normally.
        var moved = touching(0.81, 0.5)
        moved.identifier = 2
        #expect(isMove(mapper.feed(moved).first, dx: 12, dy: 0))
    }

    @Test func liftingFingerStateEndsTheTouch() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.5, 0.5))
        // A frame whose finger is breaking contact (state 5) counts as a lift.
        #expect(mapper.feed(TouchFrame(count: 1, state: 5, x: 0.7, y: 0.5, timestamp: 0)).isEmpty)
        #expect(mapper.role == nil)
    }

    /// M7h security finding 1: NaN, ±inf and huge positions, in pointer and scroll touches, give no actions;
    /// a jump bigger than `TouchFrame.maxJump` starts a new touch instead of moving.
    @Test func badPositionsGiveNoActions() {
        let bad: [(Double, Double)] = [(.nan, 0.5), (0.5, .nan), (.infinity, 0.5), (0.5, -.infinity), (1e9, 0.5), (0.5, 1e9)]
        for start in [(0.5, 0.5), (0.9, 0.5), (0.5, 0.05)] {   // pointer, vertical scroll, horizontal scroll
            for (x, y) in bad {
                var mapper = TrackpadMapper()
                _ = mapper.feed(touching(start.0, start.1))
                #expect(mapper.feed(touching(x, y)).isEmpty)
                #expect(mapper.role == nil)
                // The next good frame starts over: no jump from the touch before.
                #expect(mapper.feed(touching(start.0 + 0.01, start.1 + 0.01)).isEmpty)
            }
        }
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.1, 0.5))
        #expect(mapper.feed(touching(0.7, 0.5)).isEmpty)
        #expect(isMove(mapper.feed(touching(0.71, 0.5)).first, dx: 12, dy: 0))
    }

    /// Step 5 QA: no pointer moves while a clickpad button is down or for `clickQuiet` after; the finger is still
    /// followed, so nothing jumps when moves resume. Scrolls aren't held.
    @Test func movesHoldAroundAClick() {
        var mapper = TrackpadMapper()
        _ = mapper.feed(touching(0.5, 0.5, at: 1))
        mapper.clickpadPressed(at: 1.05)
        #expect(mapper.feed(touching(0.53, 0.47, at: 1.1)).isEmpty)
        mapper.clickpadReleased(at: 1.2)
        #expect(mapper.feed(touching(0.55, 0.46, at: 1.2 + TrackpadMapper.clickQuiet - 0.01)).isEmpty)
        #expect(isMove(mapper.feed(touching(0.56, 0.46, at: 1.2 + TrackpadMapper.clickQuiet + 0.01)).first, dx: 12, dy: 0))

        // Two buttons: moves hold until both are up. Click state outlives a lift.
        mapper.clickpadPressed(at: 2)
        mapper.clickpadPressed(at: 2)
        mapper.clickpadReleased(at: 2.1)
        _ = mapper.feed(lift)
        _ = mapper.feed(touching(0.5, 0.5, at: 3))
        #expect(mapper.feed(touching(0.6, 0.5, at: 3.1)).isEmpty)
        mapper.clickpadReleased(at: 3.2)
        #expect(mapper.feed(touching(0.61, 0.5, at: 3.4)).count == 1)

        // A scroll touch keeps scrolling during a click.
        var scroller = TrackpadMapper()
        _ = scroller.feed(touching(0.9, 0.5, at: 1))
        scroller.clickpadPressed(at: 1.05)
        #expect(isScroll(scroller.feed(touching(0.9, 0.52, at: 1.1)).first, dx: 0, dy: -0.02 * TrackpadMapper.scrollScale))
    }
}

/// M7h: only the Siri Remote's surface is used (never a built-in trackpad or a Magic Trackpad): by product id, else by family 0x91.
struct MultitouchSurfaceTests {
    @Test func onlyTheRemotesSurface() {
        // (a) The remote's product id.
        #expect(MultitouchDevices.isRemoteSurface(isBuiltIn: false, vendorID: 76, productID: 789, familyID: 145))
        #expect(MultitouchDevices.remoteSurfaceMatch(isBuiltIn: false, vendorID: 76, productID: 789, familyID: 145) == .product)
        #expect(MultitouchDevices.isRemoteSurface(isBuiltIn: false, vendorID: 76, productID: 614, familyID: 0))
        // (b) No product id found: the remote's family 0x91 only.
        #expect(MultitouchDevices.remoteSurfaceMatch(isBuiltIn: false, vendorID: nil, productID: nil, familyID: 145) == .family)
        #expect(!MultitouchDevices.isRemoteSurface(isBuiltIn: false, vendorID: nil, productID: nil, familyID: 129))
        // Another product id stays out whatever its family (Magic Trackpad: 804, family 129).
        #expect(!MultitouchDevices.isRemoteSurface(isBuiltIn: false, vendorID: 76, productID: 804, familyID: 145))
        #expect(!MultitouchDevices.isRemoteSurface(isBuiltIn: false, vendorID: 76, productID: 804, familyID: 129))
        // Built in: never.
        #expect(!MultitouchDevices.isRemoteSurface(isBuiltIn: true, vendorID: 76, productID: 789, familyID: 145))
        #expect(!MultitouchDevices.isRemoteSurface(isBuiltIn: true, vendorID: nil, productID: nil, familyID: 145))
        // Not Apple's.
        #expect(!MultitouchDevices.isRemoteSurface(isBuiltIn: false, vendorID: 1452, productID: 789, familyID: 145))
    }

    @Test func readsTheFirstTouch() {
        var bytes = [UInt8](repeating: 0, count: 96 * 2)
        bytes.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: Int32(4), toByteOffset: 20, as: Int32.self)
            raw.storeBytes(of: Float(0.25), toByteOffset: 32, as: Float.self)
            raw.storeBytes(of: Float(0.75), toByteOffset: 36, as: Float.self)
        }
        bytes.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: Int32(7), toByteOffset: 16, as: Int32.self)
        }
        let frame = bytes.withUnsafeBytes { TouchFrame.read(touches: $0.baseAddress, count: 2, at: 5) }
        #expect(frame == TouchFrame(count: 2, state: 4, x: 0.25, y: 0.75, timestamp: 5, identifier: 7))
        #expect(frame.isTouching)
        #expect(TouchFrame.read(touches: nil, count: 0, at: 6) == TouchFrame(count: 0, state: 0, x: 0, y: 0, timestamp: 6))
        #expect(!TouchFrame.read(touches: nil, count: 0, at: 6).isTouching)
    }
}

