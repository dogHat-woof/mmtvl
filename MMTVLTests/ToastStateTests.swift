import Testing
@testable import MMTVL

/// M7h L8: a new toast replaces the one showing and restarts its timer.
struct ToastStateTests {
    private let trackpadOn = ToastState.Message(text: "Trackpad On", symbol: "cursorarrow.motionlines")
    private let trackpadOff = ToastState.Message(text: "Trackpad Off", symbol: "cursorarrow.motionlines")

    @Test func timerHidesItsMessage() {
        var state = ToastState()
        let generation = state.show(trackpadOn)
        #expect(state.message == trackpadOn)
        let hidden = state.expire(generation)
        #expect(hidden)
        #expect(state.message == nil)
    }

    @Test func replacementOutlivesTheOldTimer() {
        var state = ToastState()
        let first = state.show(trackpadOn)
        let second = state.show(trackpadOff)
        #expect(state.message == trackpadOff)
        let firstHid = state.expire(first)   // the first message's timer no longer hides anything
        #expect(!firstHid)
        #expect(state.message == trackpadOff)
        let secondHid = state.expire(second)
        #expect(secondHid)
        #expect(state.message == nil)
    }

    @Test func expiringTwiceDoesNothing() {
        var state = ToastState()
        let generation = state.show(trackpadOn)
        _ = state.expire(generation)
        let again = state.expire(generation)
        #expect(!again)
    }
}
