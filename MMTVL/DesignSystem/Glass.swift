import SwiftUI

/// tvOS 26/27 Liquid Glass (M7 L26, D29): panels use SwiftUI's `glassEffect`; tiles and cards get a glass rim.
/// M7f L9: panels are clear glass with a dark tint (`Theme.panelGlass`) and the unfocused rim.
/// M7l (D46): the `glassStyle` environment picks the step and the role (L1) its look, through `GlassAppearance`.
/// With Solid, or Reduce Transparency, panels are solid (`Theme.solidPanelFill`) and have no rim.
private struct GlassPanel<S: InsettableShape>: ViewModifier {
    let shape: S
    let role: GlassRole
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.glassStyle) private var glassStyle

    func body(content: Content) -> some View {
        let appearance = GlassAppearance.make(style: glassStyle, role: role, reduceTransparency: reduceTransparency)
        if let glass = appearance.panelGlass {
            // The rim sits between the glass and the content, so its sheen never lightens
            // a focused (white) row's dark text.
            content
                .background {
                    GlassRimLayer(shape: shape, isFocused: false,
                                  rimScale: appearance.rimScale, sheenScale: appearance.sheenScale)
                }
                .glassEffect(glass, in: shape)
        } else {
            content.background(Theme.solidPanelFill, in: shape)
        }
    }
}

/// The edge of a glass object: a light gradient stroke and a soft sheen at the top.
/// `rimScale` and `sheenScale` (M7l L2) dim them for the glass step; 1 is the full look.
private struct GlassRimLayer<S: InsettableShape>: View {
    let shape: S
    let isFocused: Bool
    let rimScale: Double
    let sheenScale: Double

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [.white.opacity((isFocused ? Theme.glassSheenFocused : Theme.glassSheen) * sheenScale),
                                               .clear],
                                      startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity((isFocused ? Theme.glassRimTopFocused : Theme.glassRimTop) * rimScale),
                                        .white.opacity(Theme.glassRimMiddle * rimScale),
                                        .white.opacity((isFocused ? Theme.glassRimBottomFocused : Theme.glassRimBottom) * rimScale)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: Theme.glassRimWidth
            )
        }
        .allowsHitTesting(false)
    }
}

/// The glass edge over an opaque tile or card.
private struct GlassRim<S: InsettableShape>: ViewModifier {
    let shape: S
    let isFocused: Bool
    @Environment(\.glassStyle) private var glassStyle

    func body(content: Content) -> some View {
        // Reduce Transparency doesn't change tile rims (M7l L2), only panels.
        let appearance = GlassAppearance.make(style: glassStyle, role: .standard, reduceTransparency: false)
        content.overlay {
            GlassRimLayer(shape: shape, isFocused: isFocused,
                          rimScale: appearance.rimScale, sheenScale: appearance.sheenScale)
        }
    }
}

nonisolated extension EnvironmentValues {
    /// The app-wide glass step (M7l L4), set on the root view from `settings.json` `glassStyle`.
    @Entry var glassStyle: GlassStyle = .clear
}

extension View {
    /// A glass panel behind the content, in a rounded rectangle. `role: .banner` for overlays on video (M7l L1).
    func glassPanel(cornerRadius: CGFloat = Theme.glassCornerRadius, role: GlassRole = .standard) -> some View {
        modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), role: role))
    }

    /// A glass panel behind the content, in any insettable shape (Capsule, Circle, Rectangle).
    func glassPanel(in shape: some InsettableShape, role: GlassRole = .standard) -> some View {
        modifier(GlassPanel(shape: shape, role: role))
    }

    /// The glass edge on an opaque tile or card (art shows through the sheen).
    func glassRim(cornerRadius: CGFloat, isFocused: Bool = false) -> some View {
        modifier(GlassRim(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), isFocused: isFocused))
    }
}
