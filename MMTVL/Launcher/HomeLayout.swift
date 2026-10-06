import CoreGraphics

/// Home screen row geometry and scrolling (M7 L21). Pure; on the 1920×1080 canvas.
/// Main-actor (not `nonisolated`) because it reads `Theme` tokens.
enum HomeLayout {
    /// The height a row of tiles takes: tile, spacing and title.
    static var rowHeight: CGFloat { Theme.tileSize.height + Theme.tileTitleSpacing + Theme.tileTitleHeight }

    /// The top of a row before scrolling.
    static func rowTop(_ row: Int) -> CGFloat {
        Theme.canvasSize.height * Theme.rowsTopFraction + CGFloat(row) * Theme.tileRowPitch
    }

    /// How far the rows (and the top shelf) move up so the focused row is fully visible.
    /// Rows 0 and 1 fit under the shelf; later rows sit at the bottom with the rows above them visible.
    static func scrollOffset(focusedRow: Int) -> CGFloat {
        guard focusedRow >= 2 else { return 0 }
        return max(0, rowTop(focusedRow) + rowHeight + Theme.homeBottomMargin - Theme.canvasSize.height)
    }
}
