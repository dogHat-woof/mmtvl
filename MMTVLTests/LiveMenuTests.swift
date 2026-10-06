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
}
