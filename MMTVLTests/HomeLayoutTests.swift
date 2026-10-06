import CoreGraphics
import Testing
@testable import MMTVL

struct HomeLayoutTests {
    @Test func rowPitchHasOneSource() {
        #expect(Theme.tileRowPitch == 312)
        #expect(abs(HomeLayout.rowTop(0) - 486) < 0.001)
        #expect(abs(HomeLayout.rowTop(2) - (486 + 2 * 312)) < 0.001)
    }

    @Test func firstTwoRowsDontScroll() {
        #expect(HomeLayout.scrollOffset(focusedRow: 0) == 0)
        #expect(HomeLayout.scrollOffset(focusedRow: 1) == 0)
    }

    @Test func laterRowsSitAtTheBottom() {
        // 486 + 2×312 + 240 + 40 − 1080
        #expect(abs(HomeLayout.scrollOffset(focusedRow: 2) - 310) < 0.001)
        #expect(abs(HomeLayout.scrollOffset(focusedRow: 3) - 622) < 0.001)
        #expect(abs(HomeLayout.scrollOffset(focusedRow: 4) - 934) < 0.001)
    }
}
