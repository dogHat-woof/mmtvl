import Testing
@testable import MMTVL

struct GuideViewHintTests {
    @Test func watchHints() {
        #expect(GuideView.hint(focus: .grid, isPicking: false) == "Select: watch · Left at now: channel options · Back: leave Live TV")
        #expect(GuideView.hint(focus: .channel, isPicking: false)
                == "Select: options · Left: groups · Right: programmes · Back: leave Live TV")
        #expect(GuideView.hint(focus: .groups(0), isPicking: false) == "Select: show group · Back: close list")
        // M7l 8c: My Teams' Choose Teams and upcoming rows.
        #expect(GuideView.hint(focus: .grid, isPicking: false, row: .chooseTeams)
                == "Select: choose your teams · Left: groups · Back: leave Live TV")
        #expect(GuideView.hint(focus: .channel, isPicking: false, row: .upcoming)
                == "Select: watch this channel · Left: groups · Back: leave Live TV")
        #expect(GuideView.hint(focus: .groups(0), isPicking: false, row: .upcoming) == "Select: show group · Back: close list")
    }

    @Test func pickHints() {
        #expect(GuideView.hint(focus: .grid, isPicking: true) == "Select: show in window · Left at now: channel · Back: cancel")
        #expect(GuideView.hint(focus: .channel, isPicking: true)
                == "Select: show in window · Left: groups · Right: programmes · Back: cancel")
        #expect(GuideView.hint(focus: .groups(2), isPicking: true) == "Select: show group · Back: close list")
        #expect(GuideView.hint(focus: .grid, isPicking: true, row: .upcoming)
                == "Select: show this channel in window · Left: groups · Back: cancel")
    }
}
