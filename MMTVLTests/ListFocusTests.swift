import Testing
@testable import MMTVL

struct ListFocusTests {
    @Test func resolveFallsBackToFirst() {
        #expect(ListFocus.resolve(ids: ["a", "b"], current: "b") == "b")
        #expect(ListFocus.resolve(ids: ["a", "b"], current: "zzz") == "a")
        #expect(ListFocus.resolve(ids: ["a", "b"], current: nil) == "a")
    }

    @Test func moveClampsAtEnds() {
        #expect(ListFocus.move(ids: ["a", "b", "c"], current: "a", by: 1) == "b")
        #expect(ListFocus.move(ids: ["a", "b", "c"], current: "a", by: -1) == "a")
        #expect(ListFocus.move(ids: ["a", "b", "c"], current: "c", by: 1) == "c")
    }

    @Test func emptyIsNil() {
        #expect(ListFocus.resolve(ids: [], current: "a") == nil)
        #expect(ListFocus.move(ids: [], current: nil, by: 1) == nil)
    }
}
