import CoreGraphics

/// Home screen row geometry and scrolling (M7 L21). Pure; on the 1920×1080 canvas.
/// Main-actor (not `nonisolated`) because it reads `Theme` tokens.
enum HomeLayout {
    /// The height a row of tiles takes: tile, spacing and title.
    static var rowHeight: CGFloat { Theme.tileSize.height + Theme.tileTitleSpacing + Theme.tileTitleHeight }

    /// The top of a row before scrolling. M7c L19: row 0 sits in the dock, row 1 peeks at the bottom edge.
    static func rowTop(_ row: Int) -> CGFloat {
        Theme.homeFirstRowTop + CGFloat(row) * Theme.tileRowPitch
    }

    /// How far the rows move up so the focused row is fully visible. Row 0: nothing moves (the dock);
    /// a later row: its top sits at `homeGridFocusTop`, with the row above visible.
    static func scrollOffset(focusedRow: Int) -> CGFloat {
        guard focusedRow >= 1 else { return 0 }
        return max(0, rowTop(focusedRow) - Theme.homeGridFocusTop)
    }

    /// The hero (backdrop art, carousel, Live TV preview): full with row 0 focused, dimmed in the grid.
    static func heroOpacity(focusedRow: Int) -> Double {
        focusedRow == 0 ? 1 : Theme.homeGridHeroOpacity
    }

    /// The hero's text and the shelf show only with row 0 focused.
    static func shelfOpacity(focusedRow: Int) -> Double {
        focusedRow == 0 ? 1 : 0
    }

    /// The dock panel behind row 0, before scrolling.
    static var dockFrame: CGRect {
        CGRect(x: Theme.homeDockInset, y: rowTop(0) - Theme.homeDockPadding,
               width: Theme.canvasSize.width - 2 * Theme.homeDockInset,
               height: Theme.tileSize.height + 2 * Theme.homeDockPadding)
    }
}
