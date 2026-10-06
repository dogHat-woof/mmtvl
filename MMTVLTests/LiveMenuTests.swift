import Testing
@testable import MMTVL

struct LiveMenuTests {
    private func menu(focusedIndex: Int = 0) -> LiveMenu {
        LiveMenu(title: "NBA TV", items: [
            .init(id: "watch", title: "Watch", action: .watch("id:nbatv.us")),
            .init(id: "addToMultiview", title: "Add to Multiview", action: .addToMultiview("id:nbatv.us")),
            .init(id: "layout", title: "Layout", value: "1 + 4", action: .chooseLayout),
        ], focusedIndex: focusedIndex)
    }

    @Test func upDownClamp() {
        var menu = menu()
        #expect(menu.handle(.up) == .none)
        #expect(menu.focusedIndex == 0)
        _ = menu.handle(.down)
        _ = menu.handle(.down)
        _ = menu.handle(.down)
        #expect(menu.focusedIndex == 2)
        _ = menu.handle(.up)
        #expect(menu.focusedIndex == 1)
    }

    @Test func selectChoosesTheFocusedAction() {
        var menu = menu(focusedIndex: 1)
        #expect(menu.handle(.select) == .choose(.addToMultiview("id:nbatv.us")))
    }

    @Test func backCloses() {
        var menu = menu()
        #expect(menu.handle(.back) == .close)
    }

    @Test func otherCommandsDoNothing() {
        var menu = menu(focusedIndex: 1)
        for command in [RemoteCommand.left, .right, .playPause] {
            #expect(menu.handle(command) == .none)
        }
        #expect(menu.focusedIndex == 1)
    }

    @Test func initClampsFocus() {
        #expect(menu(focusedIndex: 9).focusedIndex == 2)
        #expect(menu(focusedIndex: -1).focusedIndex == 0)
        #expect(LiveMenu(title: "Empty", items: [], focusedIndex: 3).focusedIndex == 0)
    }

    // MARK: Scrolling (M6b L10)

    private func long(focusedIndex: Int = 0) -> LiveMenu {
        LiveMenu(title: "Guide", items: (0..<20).map { .init(id: "i\($0)", title: "\($0)", action: .watch("id:\($0)")) },
                 focusedIndex: focusedIndex, isWide: true)
    }

    @Test func initKeepsTheFocusVisible() {
        let menu = long(focusedIndex: 15)
        #expect(menu.firstVisibleIndex == 12)
        #expect(menu.visibleRange == 12..<20)
        #expect(menu.hasHiddenAbove)
        #expect(!menu.hasHiddenBelow)
        #expect(long(focusedIndex: 3).firstVisibleIndex == 3)
    }

    @Test func scrollsWithTheFocus() {
        var menu = long()
        #expect(menu.visibleRange == 0..<8)
        #expect(!menu.hasHiddenAbove && menu.hasHiddenBelow)
        for _ in 0..<7 { _ = menu.handle(.down) }
        #expect(menu.firstVisibleIndex == 0)
        _ = menu.handle(.down)
        #expect(menu.firstVisibleIndex == 1)
        for _ in 0..<30 { _ = menu.handle(.down) }
        #expect(menu.focusedIndex == 19)
        #expect(menu.visibleRange == 12..<20)
        for _ in 0..<12 { _ = menu.handle(.up) }
        #expect(menu.focusedIndex == 7)
        #expect(menu.firstVisibleIndex == 7)
        for _ in 0..<30 { _ = menu.handle(.up) }
        #expect(menu.focusedIndex == 0)
        #expect(menu.firstVisibleIndex == 0)
        #expect(!menu.hasHiddenAbove)
    }

    @Test func shortMenuHasNoHiddenRows() {
        let menu = menu()
        #expect(menu.visibleRange == 0..<3)
        #expect(!menu.hasHiddenAbove && !menu.hasHiddenBelow)
        #expect(!menu.isWide)
    }

    // MARK: M7 L5

    @Test func menuCloses() {
        var menu = menu()
        #expect(menu.handle(.menu) == .close)
    }

    @Test func channelUpDownPageByEight() {
        let items = (0..<20).map { LiveMenu.Item(id: "i\($0)", title: "\($0)", action: .watch("id:\($0)")) }
        var menu = LiveMenu(title: "Long", items: items)
        #expect(menu.handle(.channelDown) == .none)
        #expect(menu.focusedIndex == 8)
        #expect(menu.visibleRange.contains(8))
        _ = menu.handle(.channelDown)
        _ = menu.handle(.channelDown)
        #expect(menu.focusedIndex == 19)
        _ = menu.handle(.channelUp)
        #expect(menu.focusedIndex == 11)
        #expect(menu.visibleRange.contains(11))
    }

}
