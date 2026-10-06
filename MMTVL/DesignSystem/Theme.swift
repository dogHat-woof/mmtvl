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
    /// The top of `backgroundGradient` fading to clear: keeps the clock legible over scrolled tiles (M7 L21).
    static let backgroundTopFade = LinearGradient(
        colors: [Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255), .clear],
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
    /// M7 L21: the tile title has a fixed height (hidden when unfocused), so every row has the same pitch.
    static let tileTitleHeight: CGFloat = 36
    static let tileTitleSpacing: CGFloat = 24
    /// Distance from one row's top to the next one's.
    static var tileRowPitch: CGFloat { tileSize.height + tileTitleSpacing + tileTitleHeight + rowSpacing }
    /// Space kept under the focused row when the home screen scrolls.
    static let homeBottomMargin: CGFloat = 40
    /// Precise (trackpad) scroll distance that moves focus one row.
    static let homeScrollStep: CGFloat = 40
    static let homeClockFadeHeight: CGFloat = 160

    // MARK: Tile art (M7 L3, L4)

    static let youtubeArtTop = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255)
    static let youtubeArtBottom = Color(red: 0xB3 / 255, green: 0x00 / 255, blue: 0x1B / 255)
    static let liveTVArtTop = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
    static let liveTVArtBottom = Color(red: 0x00 / 255, green: 0x3A / 255, blue: 0x8C / 255)
    static let settingsArtTop = Color(red: 0x63 / 255, green: 0x63 / 255, blue: 0x66 / 255)
    static let settingsArtBottom = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    /// Exit to Desktop, `.url` tiles and apps without an icon.
    static let neutralArtTop = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)
    static let neutralArtBottom = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    /// The white symbol on gradient art, as a fraction of the art's height.
    static let tileArtSymbolFraction: CGFloat = 0.45
    /// The app icon on designed art (M7 L24), as a fraction of the art's height.
    static let designedArtIconFraction: CGFloat = 0.62
    static let tileIconBackdropBlur: CGFloat = 40
    /// The icon backdrop's size as a multiple of the tile width.
    static let tileIconBackdropScale: CGFloat = 2.2
    static let tileIconBackdropDim: Double = 0.35
    /// Custom pictures are downsampled to this many pixels on the long side.
    static let tileArtMaxPixels = 1500
    /// Settings → Tile Art previews (M7 L25).
    static let tileArtPreviewPixels = 600
    static let settingsArtPreviewSize = CGSize(width: 500, height: 300)
    static let settingsRowThumbnailSize = CGSize(width: 80, height: 48)

    // MARK: Top shelf (M7 L12)

    static let shelfHeight: CGFloat = 440
    static let shelfCardSize = CGSize(width: 352, height: 198)
    static let shelfCardSpacing: CGFloat = 40
    static let shelfCardCornerRadius: CGFloat = 12
    static let shelfCardFill = Color.white.opacity(0.08)
    static let shelfTitleFont = Font.system(size: 30, weight: .semibold)
    static let shelfCaptionFont = Font.system(size: 24, weight: .medium)
    static let shelfDetailFont = Font.system(size: 20)
    static let shelfProgressHeight: CGFloat = 4
    static let shelfProgressFill = Color.white
    static let shelfProgressTrack = Color.white.opacity(0.25)
    /// The cards' title sits at this y; the cards at `shelfCardsTop`.
    static let shelfTitleTop: CGFloat = 96
    static let shelfCardsTop: CGFloat = 140
    static let shelfBannerBlur: CGFloat = 30
    static let shelfBannerDim: Double = 0.25
    /// The shelf fades out over this much scrolling (L21).
    static let shelfFadeDistance: CGFloat = 200
    static let shelfCrossfade = Animation.easeInOut(duration: 0.25)

    // MARK: Glass (M7 L26)

    static let glassCornerRadius: CGFloat = 28
    static let glassRimWidth: CGFloat = 1.5
    static let glassRimTop: Double = 0.55
    static let glassRimMiddle: Double = 0.08
    static let glassRimBottom: Double = 0.25
    static let glassRimTopFocused: Double = 0.85
    static let glassRimBottomFocused: Double = 0.4
    static let glassSheen: Double = 0.10
    static let glassSheenFocused: Double = 0.18
    /// Reduce Transparency: panels without see-through.
    static let solidPanelFill = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255).opacity(0.92)

    // MARK: Full-screen top shelf (M7 L27)

    /// The scrim over the art: transparent until this fraction of the height, then down to `shelfScrimOpacity`.
    static let shelfScrimStart: CGFloat = 0.45
    static let shelfScrimOpacity: Double = 0.75
    /// Darkens the art behind the clock.
    static let shelfClockScrimOpacity: Double = 0.35
    /// Designed art on the backdrop: the icon's height and center.
    static let shelfBackdropIconSize: CGFloat = 420
    static let shelfBackdropIconCenter = CGPoint(x: 1440, y: 300)
    static let shelfBackdropCrossfade = Animation.easeInOut(duration: 0.35)
    /// Extra darkening of the art while cards show.
    static let shelfCardsDim: Double = 0.35

    // MARK: Focus

    static let focusScale: CGFloat = 1.1
    static let focusShadowRadius: CGFloat = 30
    static let focusShadowYOffset: CGFloat = 20
    static let focusShadowOpacity: Double = 0.5
    static let unavailableOpacity: Double = 0.4
    static let shakeDistance: CGFloat = 12

    // MARK: Parallax (M7 L1)

    static let parallaxMaxDegrees: Double = 7
    /// The art's foreground layer moves this far at full tilt.
    static let parallaxLayerOffset: CGFloat = 8
    /// The tilt a tile starts with when focus arrives by an arrow (toward the side it came from).
    static let parallaxNudgeAmount: CGFloat = 0.6
    static let parallaxSpring = Animation.spring(response: 0.45, dampingFraction: 0.55)
    /// `parallaxSpring` for keyframes.
    static let parallaxKeyframeSpring = Spring(response: 0.45, dampingRatio: 0.55)
    static let parallaxPerspective: CGFloat = 0.6
    static let specularOpacity: Double = 0.35
    /// The specular radius as a fraction of the tile width.
    static let specularRadiusFraction: CGFloat = 0.9
    static let pressScale: CGFloat = 0.95

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
    /// The star after a favorite's name in the channel cell (M6b).
    static let guideFavoriteSymbolSize: CGFloat = 20

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
    /// Match Guide (M6b L10).
    static let liveMenuWideWidth: CGFloat = 1040
    static let liveMenuTitleFont = Font.system(size: 34, weight: .semibold)
    static let liveMenuRowHeight: CGFloat = 72

    // MARK: Animation

    static let focusAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
}
