import CoreGraphics
import Testing
@testable import MMTVL

/// M7h step 13h: one video layer for the home preview and Live TV, keyed by player identity.
struct ScreenVideoLayoutTests {
    private static func liveTV(_ placements: [LiveTVModel.VideoPlacement], screen: AppRouter.Screen = .liveTV,
                               preview: (any LivePlayer)? = nil, showsPreview: Bool = true,
                               homeFade: Double = 1) -> [ScreenVideoPlacement] {
        ScreenVideoLayout.placements(screen: screen, liveTVPlacements: placements, previewPlayer: preview,
                                     showsPreview: showsPreview, homeFade: homeFade)
    }

    @Test func homePreviewIsTheWholeWindowAtTheBackdropsStrength() {
        let player = FakePlayer()
        let shown = Self.liveTV([], screen: .home, preview: player, showsPreview: true, homeFade: 0.4)
        #expect(shown.count == 1)
        #expect(shown.first?.id == ObjectIdentifier(player))
        #expect(shown.first?.canvasRect == nil)
        #expect(shown.first?.opacity == 0.4)
        #expect(shown.first?.animatesOpacity == true)
    }

    @Test func homePreviewStaysInTheWindowWhileHidden() {
        // M7c L25: another tile focused; the preloading preview keeps its view (and GL context), invisible.
        let player = FakePlayer()
        let hidden = Self.liveTV([], screen: .home, preview: player, showsPreview: false, homeFade: 1)
        #expect(hidden.map(\.id) == [ObjectIdentifier(player)])
        #expect(hidden.first?.opacity == 0)
    }

    @Test func homeWithoutAPreviewHasNoVideo() {
        #expect(Self.liveTV([], screen: .home, preview: nil).isEmpty)
    }

    @Test func selectKeepsThePreviewsIdentityAndFullStrength() {
        // Leaving home the fade is 1; Live TV full screen on the adopted player is the same view at the same opacity.
        let player = FakePlayer()
        let leaving = Self.liveTV([], screen: .home, preview: player, showsPreview: true, homeFade: 1)
        let live = Self.liveTV([LiveTVModel.VideoPlacement(player: player, canvasRect: nil, isVisible: true)])
        #expect(leaving.map(\.id) == live.map(\.id))
        #expect(leaving.first?.canvasRect == live.first?.canvasRect)
        #expect(leaving.first?.opacity == 1)
        #expect(live.first?.opacity == 1)
        #expect(live.first?.animatesOpacity == false)
    }

    @Test func liveTVKeepsInvisibleWindowsAndTheirRects() {
        let preview = FakePlayer()
        let other = FakePlayer()
        let slot = CGRect(x: 960, y: 0, width: 960, height: 540)
        let placements = Self.liveTV([
            LiveTVModel.VideoPlacement(player: preview, canvasRect: Theme.guidePreviewRect, isVisible: true),
            LiveTVModel.VideoPlacement(player: other, canvasRect: slot, isVisible: false),
        ])
        #expect(placements.map(\.id) == [ObjectIdentifier(preview), ObjectIdentifier(other)])
        #expect(placements.map(\.canvasRect) == [Theme.guidePreviewRect, slot])
        #expect(placements.map(\.opacity) == [1, 0])
    }

    @Test func liveTVIgnoresTheHomePreview() {
        let player = FakePlayer()
        #expect(Self.liveTV([], preview: player).isEmpty)
    }

    @Test func otherScreensHaveNoVideo() {
        let player = FakePlayer()
        let full = [LiveTVModel.VideoPlacement(player: player, canvasRect: nil, isVisible: true)]
        for screen: AppRouter.Screen in [.settings, .youtube, .accessibilityOnboarding, .pin(.openSettings)] {
            #expect(Self.liveTV(full, screen: screen, preview: player).isEmpty, "\(screen)")
        }
    }

    @Test func liveTVPlacementsAreReadOnlyForLiveTV() {
        var reads = 0
        func placements() -> [LiveTVModel.VideoPlacement] {
            reads += 1
            return []
        }
        _ = ScreenVideoLayout.placements(screen: .home, liveTVPlacements: placements(), previewPlayer: nil,
                                         showsPreview: false, homeFade: 1)
        #expect(reads == 0)
        _ = ScreenVideoLayout.placements(screen: .liveTV, liveTVPlacements: placements(), previewPlayer: nil,
                                         showsPreview: false, homeFade: 1)
        #expect(reads == 1)
    }
}
