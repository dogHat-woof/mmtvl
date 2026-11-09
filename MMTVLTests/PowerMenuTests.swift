import Testing
@testable import MMTVL

/// M7h L15: the power menu's items, focus and outcomes.
struct PowerMenuTests {
    @Test func itemsInOrder() {
        let menu = PowerMenu()
        #expect(menu.items.map(\.title) == ["Turn Off TV & Receiver", "Sleep Mac mini", "Relaunch MMTVL",
                                            "Restart Mac mini", "Cancel"])
        #expect(menu.items.map(\.action) == [.turnOff, .sleepMac, .relaunch, .restartMac, .cancel])
        #expect(menu.focusedItem.action == .turnOff)
        #expect(PowerMenuAction.allCases.filter(\.needsPIN) == [.relaunch, .restartMac])
    }

    @Test func upAndDownMoveClamped() {
        var menu = PowerMenu()
        #expect(menu.handle(.up) == PowerMenu.Outcome.none)
        #expect(menu.focusedIndex == 0)
        for _ in 0..<10 { _ = menu.handle(.down) }
        #expect(menu.focusedItem.action == .cancel)
        _ = menu.handle(.up)
        #expect(menu.focusedItem.action == .restartMac)
    }

    @Test func selectChoosesTheFocusedItem() {
        var menu = PowerMenu()
        var chosen: [PowerMenu.Outcome] = []
        for _ in 0..<4 {
            chosen.append(menu.handle(.select))
            _ = menu.handle(.down)
        }
        #expect(chosen == [.choose(.turnOff), .choose(.sleepMac), .choose(.relaunch), .choose(.restartMac)])
        // Cancel closes.
        #expect(menu.focusedItem.action == .cancel)
        #expect(menu.handle(.select) == .close)
    }

    @Test func backAndMenuClose() {
        var menu = PowerMenu()
        #expect(menu.handle(.back) == .close)
        #expect(menu.handle(.menu) == .close)
    }

    @Test func otherCommandsDoNothing() {
        var menu = PowerMenu()
        for command in [RemoteCommand.left, .right, .playPause, .fastForward, .rewind, .channelUp, .channelDown,
                        .volumeUp, .volumeDown, .mute, .power, .powerMenu, .home] {
            #expect(menu.handle(command) == PowerMenu.Outcome.none)
        }
        #expect(menu.focusedIndex == 0)
    }

    @Test func clickAndHover() {
        var menu = PowerMenu()
        menu.focus(index: 2)
        #expect(menu.focusedItem.action == .relaunch)
        menu.focus(index: 9)
        #expect(menu.focusedIndex == 2)
        #expect(menu.choose(index: 1) == .choose(.sleepMac))
        #expect(menu.choose(index: 4) == .close)
        #expect(menu.choose(index: -1) == PowerMenu.Outcome.none)
    }
}
