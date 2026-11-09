import SwiftUI
import Testing
@testable import MMTVL

/// M7l L1, L2 (D46): the glass steps and the banner role.
struct GlassStyleTests {
    @Test func rawValuesRoundTrip() {
        #expect(GlassStyle.allCases.map(\.rawValue) == ["clear", "light", "frosted", "darkFrosted", "solid"])
        for style in GlassStyle.allCases {
            #expect(GlassStyle(rawValue: style.rawValue) == style)
        }
        #expect(GlassStyle(rawValue: "bogus") == nil)
    }

    @Test func titles() {
        #expect(GlassStyle.allCases.map(\.title) == ["Clear", "Light Tint", "Frosted", "Dark Frosted", "Solid"])
    }

    @Test func clearStandardIsTodaysLook() {
        let appearance = GlassAppearance.make(style: .clear, role: .standard, reduceTransparency: false)
        #expect(appearance.panelGlass == Theme.panelGlass)
        #expect(appearance.panelGlass == Glass.clear.tint(.black.opacity(0.22)))
        #expect(appearance.rimScale == 1)
        #expect(appearance.sheenScale == 1)
    }

    @Test func eachStepUsesItsTokens() {
        let light = GlassAppearance.make(style: .light, role: .standard, reduceTransparency: false)
        #expect(light == GlassAppearance(panelGlass: Theme.glassLightPanel,
                                         rimScale: Theme.glassLightRimScale, sheenScale: Theme.glassLightSheenScale))
        let frosted = GlassAppearance.make(style: .frosted, role: .standard, reduceTransparency: false)
        #expect(frosted == GlassAppearance(panelGlass: Theme.glassFrostedPanel,
                                           rimScale: Theme.glassFrostedRimScale, sheenScale: Theme.glassFrostedSheenScale))
        let dark = GlassAppearance.make(style: .darkFrosted, role: .standard, reduceTransparency: false)
        #expect(dark == GlassAppearance(panelGlass: Theme.glassDarkFrostedPanel,
                                        rimScale: Theme.glassDarkFrostedRimScale, sheenScale: Theme.glassDarkFrostedSheenScale))
        // The steps are distinct looks.
        #expect(light.panelGlass != Theme.panelGlass)
        #expect(light.panelGlass != frosted.panelGlass)
        #expect(frosted.panelGlass != dark.panelGlass)
    }

    @Test func solidAndReduceTransparencyHaveNoPanelGlass() {
        for role in [GlassRole.standard, .banner] {
            #expect(GlassAppearance.make(style: .solid, role: role, reduceTransparency: false).panelGlass == nil)
            for style in GlassStyle.allCases {
                #expect(GlassAppearance.make(style: style, role: role, reduceTransparency: true).panelGlass == nil,
                        "\(style) \(role) with Reduce Transparency")
            }
        }
        let solid = GlassAppearance.make(style: .solid, role: .standard, reduceTransparency: false)
        #expect(solid.rimScale == Theme.glassSolidRimScale)
        #expect(solid.sheenScale == Theme.glassSolidSheenScale)
    }

    @Test func bannerOnClearIsDarkFrosted() {
        let banner = GlassAppearance.make(style: .clear, role: .banner, reduceTransparency: false)
        #expect(banner.panelGlass == Theme.bannerPanelGlass)
        #expect(banner.rimScale == Theme.bannerRimScale)
        #expect(banner.sheenScale == Theme.bannerSheenScale)
        // L1: at least as frosted and dark as Dark Frosted (the banner tokens may be tuned darker, never lighter).
        #expect(Theme.bannerPanelGlass == Glass.regular.tint(.black.opacity(Theme.bannerGlassTint)))
        #expect(Theme.bannerGlassTint >= Theme.glassDarkFrostedTint)
        #expect(Theme.bannerRimScale <= Theme.glassDarkFrostedRimScale)
        #expect(Theme.bannerSheenScale <= Theme.glassDarkFrostedSheenScale)
    }

    @Test func bannerIsNeverLighterThanTheStep() {
        for style in GlassStyle.allCases where style != .solid {
            let step = GlassAppearance.make(style: style, role: .standard, reduceTransparency: false)
            let banner = GlassAppearance.make(style: style, role: .banner, reduceTransparency: false)
            #expect(banner.panelGlass == Theme.bannerPanelGlass, "\(style)")
            #expect(banner.rimScale <= step.rimScale, "\(style)")
            #expect(banner.sheenScale <= step.sheenScale, "\(style)")
        }
    }

    @Test func bannerOnSolidStaysSolid() {
        let banner = GlassAppearance.make(style: .solid, role: .banner, reduceTransparency: false)
        #expect(banner.panelGlass == nil)
        #expect(banner == GlassAppearance.make(style: .solid, role: .standard, reduceTransparency: false))
    }
}
