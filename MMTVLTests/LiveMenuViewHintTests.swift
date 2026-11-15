import Testing
@testable import MMTVL

struct LiveMenuViewHintTests {
    /// M7m L3: Back closes a menu, and goes back from a submenu (Layout, Match Guide) to its menu.
    @Test func footerHints() {
        #expect(LiveMenuView.hint(isSubmenu: false) == "Select: choose · Back: close")
        #expect(LiveMenuView.hint(isSubmenu: true) == "Select: choose · Back: back")
    }
}
