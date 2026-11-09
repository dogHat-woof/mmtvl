import SwiftUI

/// tvOS 26/27 Liquid Glass (M7 L26, D29): panels use SwiftUI's `glassEffect`; tiles and cards get a glass rim.
/// M7f L9: panels are clear glass with a dark tint (`Theme.panelGlass`) and the unfocused rim.
/// With Reduce Transparency, panels are solid (`Theme.solidPanelFill`) and have no rim.
private struct GlassPanel<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.solidPanelFill, in: shape)
        } else {
            // The rim sits between the glass and the content, so its sheen never lightens
            // a focused (white) row's dark text.
            content
                .background { GlassRimLayer(shape: shape, isFocused: false) }
                .glassEffect(Theme.panelGlass, in: shape)
        }
    }
}

/// The edge of a glass object: a light gradient stroke and a soft sheen at the top.
private struct GlassRimLayer<S: InsettableShape>: View {
    let shape: S
    let isFocused: Bool

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [.white.opacity(isFocused ? Theme.glassSheenFocused : Theme.glassSheen), .clear],
                                      startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(isFocused ? Theme.glassRimTopFocused : Theme.glassRimTop),
                                        .white.opacity(Theme.glassRimMiddle),
                                        .white.opacity(isFocused ? Theme.glassRimBottomFocused : Theme.glassRimBottom)],
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

    func body(content: Content) -> some View {
        content.overlay { GlassRimLayer(shape: shape, isFocused: isFocused) }
    }
}

extension View {
    /// A glass panel behind the content, in a rounded rectangle.
    func glassPanel(cornerRadius: CGFloat = Theme.glassCornerRadius) -> some View {
        modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// A glass panel behind the content, in any insettable shape (Capsule, Circle, Rectangle).
    func glassPanel(in shape: some InsettableShape) -> some View {
        modifier(GlassPanel(shape: shape))
    }

    /// The glass edge on an opaque tile or card (art shows through the sheen).
    func glassRim(cornerRadius: CGFloat, isFocused: Bool = false) -> some View {
        modifier(GlassRim(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), isFocused: isFocused))
    }
}
