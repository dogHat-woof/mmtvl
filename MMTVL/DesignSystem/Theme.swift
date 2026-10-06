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

    // MARK: Settings

    // Literal sizes on purpose: the semantic macOS fonts are too small on the 1920-point TV canvas.
    static let settingsTitleFont = Font.system(size: 48, weight: .semibold)
    static let settingsSectionFont = Font.system(size: 24, weight: .semibold)
    static let settingsRowFont = Font.system(size: 30, weight: .medium)
    static let settingsDetailFont = Font.system(size: 22)
    static let settingsHintFont = Font.system(size: 22)

    static let settingsSideColumnWidth: CGFloat = 600
    static let settingsListWidth: CGFloat = 1000
    static let settingsColumnSpacing: CGFloat = 80
    static let settingsRowMinHeight: CGFloat = 80
    static let settingsRowCornerRadius: CGFloat = 12
    static let settingsRowSpacing: CGFloat = 8
    static let settingsSectionSpacing: CGFloat = 40
    static let settingsRowIconSize: CGFloat = 48
    static let settingsPageImageSize: CGFloat = 280
    /// The phone pairing QR code (M5); fits the side column and reads from the couch.
    static let settingsQRCodeSize: CGFloat = 440

    static let settingsRowFocusScale: CGFloat = 1.03
    static let focusedRowFill = Color.white
    static let focusedRowText = Color.black
    static let focusedRowSecondaryText = Color.black.opacity(0.6)

    // MARK: PIN (D20; layout after Google TV's privacy keypad)

    static let pinTitleFont = Font.system(size: 56, weight: .semibold)
    static let pinLabelFont = Font.system(size: 20, weight: .semibold)
    static let pinSlotWidth: CGFloat = 90
    static let pinSlotSpacing: CGFloat = 18
    static let pinSlotHeight: CGFloat = 4
    static let pinActiveSlotHeight: CGFloat = 6
    static let pinDialSize: CGFloat = 340
    static let pinDialDigitFont = Font.system(size: 48, weight: .regular)
    static let pinDialFill = Color.white
    static let pinDialText = Color.black.opacity(0.6)
    static let pinKeypadFont = Font.system(size: 30, weight: .semibold)
    static let pinKeypadColumnSpacing: CGFloat = 20
    static let pinKeypadRowSpacing: CGFloat = 24
    static let pinColumnSpacing: CGFloat = 80

    // MARK: Live TV player (M4)

    static let liveBannerTitleFont = Font.system(size: 40, weight: .semibold)
    static let liveBannerProgrammeFont = Font.system(size: 30, weight: .medium)
    static let liveBannerDetailFont = Font.system(size: 22)
    static let liveBannerLogoSize: CGFloat = 96
    static let liveBarHeight: CGFloat = 8
    static let liveOverlayGradient = LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)

    // MARK: Live TV guide (M4)

    static let guidePreviewRect = CGRect(x: 1160, y: 60, width: 640, height: 360)
    static let guideInfoRect = CGRect(x: 120, y: 60, width: 980, height: 360)
    static let guideGridTop: CGFloat = 460
    static let guideTimeHeaderHeight: CGFloat = 48
    static let guideRowHeight: CGFloat = 80
    /// Gap between cells and rows.
    static let guideCellSpacing: CGFloat = 4
    static let guideChannelColumnWidth: CGFloat = 340
    static let guideGridLeading: CGFloat = 472
    static let guideGridWidth: CGFloat = 1328
    static let guideGroupPanelWidth: CGFloat = 420
    static let guideInfoTitleFont = Font.system(size: 44, weight: .semibold)
    static let guideInfoDetailFont = Font.system(size: 24)
    static let guideCellFont = Font.system(size: 24, weight: .medium)
    static let guideCellTimeFont = Font.system(size: 18)
    static let guideChannelFont = Font.system(size: 24, weight: .medium)
    static let guideCellCornerRadius: CGFloat = 10
    static let guideNowLine = Color(red: 1, green: 0.27, blue: 0.23)
    static let guideLogoSize: CGFloat = 48

    // MARK: Multiview (M6)

    static let multiviewGap = MultiviewLayout.gap
    static let multiviewDiagramSize = CGSize(width: 96, height: 54)
    static let multiviewFocusBorder = Color.white
    static let multiviewFocusBorderWidth: CGFloat = 6
    static let multiviewEmptySymbolSize: CGFloat = 48
    static let multiviewChipFont = Font.system(size: 26, weight: .semibold)
    static let multiviewChipDetailFont = Font.system(size: 20)

    // MARK: Live TV menus (M6)

    static let liveMenuWidth: CGFloat = 720
    static let liveMenuTitleFont = Font.system(size: 34, weight: .semibold)
    static let liveMenuRowHeight: CGFloat = 72

    // MARK: Animation

    static let focusAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
}
