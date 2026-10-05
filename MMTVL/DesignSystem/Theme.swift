import SwiftUI

/// tvOS-style design tokens, in points on a 1920×1080 canvas.
/// The root view lays out on that canvas and scales it to the screen with `scaleEffect`.
enum Theme {
    // MARK: Canvas

    static let canvasSize = CGSize(width: 1920, height: 1080)

    static func scale(for size: CGSize) -> CGFloat {
        size.width / canvasSize.width
    }

    // MARK: Colors

    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255), .black],
        startPoint: .top,
        endPoint: .bottom
    )
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let tileFill = Color.white.opacity(0.12)
    static let focusHighlight = Color.white.opacity(0.3)
    static let focusHighlightWidth: CGFloat = 2

    // MARK: Typography

    static let clockFont = Font.title2
    static let tileTitleFont = Font.title3.weight(.medium)
    static let tileCaptionFont = Font.callout
    static let tileSymbolSize: CGFloat = 72

    // MARK: Layout

    static let tileSize = CGSize(width: 300, height: 180)   // 5:3
    static let tileCornerRadius: CGFloat = 16
    static let tileIconFraction: CGFloat = 0.6               // icon height / tile height
    static let tileSpacing: CGFloat = 48
    static let rowSpacing: CGFloat = 72
    static let sideMargin: CGFloat = 120
    static let tilesPerRow = 5
    static let rowsTopFraction: CGFloat = 0.45               // tiles start ~45% down; top is reserved for the M7 top shelf

    // MARK: Focus

    static let focusScale: CGFloat = 1.1
    static let focusShadowRadius: CGFloat = 30
    static let focusShadowYOffset: CGFloat = 20
    static let focusShadowOpacity: Double = 0.5
    static let unavailableOpacity: Double = 0.4
    static let shakeDistance: CGFloat = 12

    // MARK: Animation

    static let focusAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
}
