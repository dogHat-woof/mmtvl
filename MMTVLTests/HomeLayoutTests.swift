import CoreGraphics
import Testing
@testable import MMTVL

/// M7c L19 (D38): the tvOS 26 dock layout.
struct HomeLayoutTests {
    @Test func rowPitchHasOneSource() {
        #expect(Theme.tileRowPitch == 244)
        #expect(HomeLayout.rowTop(0) == 800)
        #expect(HomeLayout.rowTop(2) == 1288, "rowTop(2) = \(HomeLayout.rowTop(2))")
    }

    @Test func secondRowPeeksAtTheBottom() {
        let visible = Theme.canvasSize.height - HomeLayout.rowTop(1)
        #expect(visible > 0)
        #expect(visible <= 50)
    }

    @Test func sixTilesFillTheWidth() {
        let width = CGFloat(Theme.tilesPerRow) * Theme.tileSize.width + CGFloat(Theme.tilesPerRow - 1) * Theme.tileSpacing
            + 2 * Theme.homeRowMargin
        #expect(Theme.tilesPerRow == 6)
        #expect(width == Theme.canvasSize.width)
    }

    @Test func theDockWrapsRowZero() {
        let dock = HomeLayout.dockFrame
        #expect(dock.minY < HomeLayout.rowTop(0))
        #expect(dock.maxY > HomeLayout.rowTop(0) + Theme.tileSize.height)
        #expect(dock.maxY < HomeLayout.rowTop(0) + Theme.tileSize.height + Theme.tileTitleSpacing)
    }

    @Test func rowZeroDoesntScroll() {
        #expect(HomeLayout.scrollOffset(focusedRow: 0) == 0)
        #expect(HomeLayout.heroOpacity(focusedRow: 0) == 1)
        #expect(HomeLayout.shelfOpacity(focusedRow: 0) == 1)
    }

    @Test func laterRowsSitAtTheGridTop() {
        for row in 1...4 {
            #expect(HomeLayout.rowTop(row) - HomeLayout.scrollOffset(focusedRow: row) == Theme.homeGridFocusTop)
        }
        #expect(HomeLayout.heroOpacity(focusedRow: 1) == Theme.homeGridHeroOpacity)
        #expect(HomeLayout.shelfOpacity(focusedRow: 2) == 0)
    }

    /// M7l L5 (D47): the dock shows with row 0 focused and fades out in the grid.
    @Test func theDockFadesInTheGrid() {
        #expect(HomeLayout.dockOpacity(focusedRow: 0) == 1)
        #expect(HomeLayout.dockOpacity(focusedRow: 1) == 0)
        #expect(HomeLayout.dockOpacity(focusedRow: 2) == 0)
    }
}
