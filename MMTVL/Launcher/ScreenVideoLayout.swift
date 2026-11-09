import CoreGraphics

/// M7h step 13h: every player's video is hosted in one place in `LauncherRootView`, under the home screen and
/// Live TV alike. A view keyed by its player stays in the window across home ↔ Live TV, so Core Animation keeps its
/// GL context and mpv keeps its video (no reload on Select or Back).
struct ScreenVideoPlacement: Identifiable {
    let player: any LivePlayer
    var id: ObjectIdentifier { ObjectIdentifier(player) }
    /// nil = the whole window.
    var canvasRect: CGRect?
    /// 0 keeps the view (and its GL context) in the window without showing it.
    var opacity: Double
    /// The home preview fades with the backdrop; Live TV's windows change at once (as M6 L15). Frames never animate.
    var animatesOpacity: Bool
}

enum ScreenVideoLayout {
    /// What the screen shows of the players' video.
    /// - Parameters:
    ///   - liveTVPlacements: read only for Live TV.
    ///   - previewPlayer: the home preview's player, nil when there's no preview (M7c L15).
    ///   - showsPreview: `AppRouter.showsLivePreviewVideo` (the Live TV tile focused, M7c L25).
    ///   - homeFade: the backdrop's dim as the home rows scroll, 1 while leaving home (M7c step 35).
    static func placements(screen: AppRouter.Screen,
                           liveTVPlacements: @autoclosure () -> [LiveTVModel.VideoPlacement],
                           previewPlayer: (any LivePlayer)?,
                           showsPreview: Bool,
                           homeFade: Double) -> [ScreenVideoPlacement] {
        switch screen {
        case .liveTV:
            return liveTVPlacements().map {
                ScreenVideoPlacement(player: $0.player, canvasRect: $0.canvasRect, opacity: $0.isVisible ? 1 : 0,
                                     animatesOpacity: false)
            }
        case .home:
            // M7c L25: kept in the window while it preloads (mpv needs the render context).
            guard let previewPlayer else { return [] }
            return [ScreenVideoPlacement(player: previewPlayer, canvasRect: nil, opacity: showsPreview ? homeFade : 0,
                                         animatesOpacity: true)]
        case .accessibilityOnboarding, .settings, .youtube, .pin:
            return []
        }
    }
}
