import SwiftUI

/// tvOS 26/27 Liquid Glass (M7 L26, D29): panels use SwiftUI's `glassEffect`; tiles and cards get a glass rim.
/// With Reduce Transparency, panels are solid (`Theme.solidPanelFill`).
private struct GlassPanel<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.solidPanelFill, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

/// The edge of a glass object: a light gradient stroke and a soft sheen at the top.
private struct GlassRim<S: InsettableShape>: ViewModifier {
    let shape: S
    let isFocused: Bool

    func body(content: Content) -> some View {
        content.overlay {
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
}

extension View {
    /// A glass panel behind the content, in a rounded rectangle.
    func glassPanel(cornerRadius: CGFloat = Theme.glassCornerRadius) -> some View {
        modifier(GlassPanel(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// A glass panel behind the content, in any shape (Capsule, Circle, Rectangle).
    func glassPanel(in shape: some Shape) -> some View {
        modifier(GlassPanel(shape: shape))
    }

    /// The glass edge on an opaque tile or card (art shows through the sheen).
    func glassRim(cornerRadius: CGFloat, isFocused: Bool = false) -> some View {
        modifier(GlassRim(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), isFocused: isFocused))
    }
}
