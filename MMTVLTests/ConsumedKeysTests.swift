import Testing
@testable import MMTVL

/// M7c step 15: a consumed key-down's key-up is consumed too.
struct ConsumedKeysTests {
    @Test func keyUpFollowsItsKeyDown() {
        var keys = ConsumedKeys()
        keys.keyDown(36, consumed: true)     // Return → Select
        keys.keyDown(0, consumed: false)     // "a", unbound
        let returnUp = keys.keyUp(36)
        let returnUpAgain = keys.keyUp(36)
        let letterUp = keys.keyUp(0)
        let unseenUp = keys.keyUp(53)        // a key-up without a key-down seen
        #expect(returnUp)
        #expect(!returnUpAgain)              // only once
        #expect(!letterUp)
        #expect(!unseenUp)
    }

    @Test func aPassedKeyDownForgetsAnEarlierConsumedOne() {
        var keys = ConsumedKeys()
        keys.keyDown(36, consumed: true)
        keys.keyDown(36, consumed: false)    // e.g. learning ended between presses
        let up = keys.keyUp(36)
        #expect(!up)
    }
}
