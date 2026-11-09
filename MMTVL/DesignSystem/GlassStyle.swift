import SwiftUI

/// How see-through MMTVL's glass is (M7l L2, D46): Settings → System → Glass, `settings.json` `glassStyle`.
/// One named step for every panel and tile rim; Reduce Transparency still makes panels Solid.
nonisolated enum GlassStyle: String, CaseIterable, Codable, Sendable {
    case clear, light, frosted, darkFrosted, solid

    var title: String {
        switch self {
        case .clear: "Clear"
        case .light: "Light Tint"
        case .frosted: "Frosted"
        case .darkFrosted: "Dark Frosted"
        case .solid: "Solid"
        }
    }
}

/// What a panel sits over (M7l L1): `.banner` is for the player's overlays over moving video,
/// which are always at least as frosted and dark as Dark Frosted.
nonisolated enum GlassRole: Sendable {
    case standard, banner
}

/// The look a glass style gives one role, from `Theme`'s tokens.
struct GlassAppearance: Equatable {
    /// The panel's glass; nil draws `Theme.solidPanelFill` without a rim.
    var panelGlass: Glass?
    /// Multiplies the rim's stroke opacities (focused and not).
    var rimScale: Double
    /// Multiplies the rim's top sheen.
    var sheenScale: Double

    static func make(style: GlassStyle, role: GlassRole, reduceTransparency: Bool) -> GlassAppearance {
        var appearance = base(for: style)
        if role == .banner, appearance.panelGlass != nil {
            // Every non-solid step is at most as dark as Dark Frosted, so the banner tokens win;
            // the rim and sheen never get stronger than the step's own.
            appearance = GlassAppearance(panelGlass: Theme.bannerPanelGlass,
                                         rimScale: min(appearance.rimScale, Theme.bannerRimScale),
                                         sheenScale: min(appearance.sheenScale, Theme.bannerSheenScale))
        }
        if reduceTransparency {
            appearance.panelGlass = nil
        }
        return appearance
    }

    private static func base(for style: GlassStyle) -> GlassAppearance {
        switch style {
        case .clear:
            GlassAppearance(panelGlass: Theme.panelGlass, rimScale: 1, sheenScale: 1)
        case .light:
            GlassAppearance(panelGlass: Theme.glassLightPanel,
                            rimScale: Theme.glassLightRimScale, sheenScale: Theme.glassLightSheenScale)
        case .frosted:
            GlassAppearance(panelGlass: Theme.glassFrostedPanel,
                            rimScale: Theme.glassFrostedRimScale, sheenScale: Theme.glassFrostedSheenScale)
        case .darkFrosted:
            GlassAppearance(panelGlass: Theme.glassDarkFrostedPanel,
                            rimScale: Theme.glassDarkFrostedRimScale, sheenScale: Theme.glassDarkFrostedSheenScale)
        case .solid:
            GlassAppearance(panelGlass: nil,
                            rimScale: Theme.glassSolidRimScale, sheenScale: Theme.glassSolidSheenScale)
        }
    }
}
