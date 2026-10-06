import SwiftUI

/// The gear next to the clock that opens Settings (D19). Uses the tile focus visuals.
struct GearButtonView: View {
    let isFocused: Bool
    let onHover: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: Theme.gearSymbolSize))
            .foregroundStyle(isFocused ? Theme.primaryText : Theme.secondaryText)
            .frame(width: Theme.gearButtonSize, height: Theme.gearButtonSize)
            .background {
                if isFocused { Circle().fill(Theme.tileFill) }
            }
            .overlay {
                if isFocused {
                    Circle().strokeBorder(Theme.focusHighlight, lineWidth: Theme.focusHighlightWidth)
                }
            }
            .contentShape(Circle())
            .scaleEffect(isFocused ? Theme.focusScale : 1)
            .shadow(
                color: .black.opacity(isFocused ? Theme.focusShadowOpacity : 0),
                radius: Theme.focusShadowRadius,
                y: Theme.focusShadowYOffset
            )
            .animation(Theme.focusAnimation, value: isFocused)
            .onHover { hovering in
                if hovering { onHover() }
            }
            .onTapGesture(perform: onActivate)
    }
}
