import Testing
@testable import MMTVL

struct GuideViewHintTests {
    @Test func watchHints() {
        #expect(GuideView.hint(focus: .grid, isPicking: false) == "Select: watch · Left at now: channel options · Back: close")
        #expect(GuideView.hint(focus: .channel, isPicking: false)
                == "Select: options · Left: groups · Right: programmes · Back: close")
        #expect(GuideView.hint(focus: .groups(0), isPicking: false) == "Select: show group · Back: close list")
    }

    @Test func pickHints() {
        #expect(GuideView.hint(focus: .grid, isPicking: true) == "Select: show in window · Left at now: channel · Back: cancel")
        #expect(GuideView.hint(focus: .channel, isPicking: true)
                == "Select: show in window · Left: groups · Right: programmes · Back: cancel")
        #expect(GuideView.hint(focus: .groups(2), isPicking: true) == "Select: show group · Back: close list")
    }
}
