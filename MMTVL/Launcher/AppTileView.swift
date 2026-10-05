import SwiftUI

/// One home screen tile: a 5:3 rounded rect with the app icon or an SF Symbol.
struct AppTileView: View {
    let item: LaunchItem
    let title: String
    let icon: NSImage?
    let isFocused: Bool
    let isInstalled: Bool
    /// Incremented to play the "can't open" shake (L6).
    let shakeTrigger: Int

    var body: some View {
        VStack(spacing: 24) {
            tile
                .scaleEffect(isFocused ? Theme.focusScale : 1)
                .shadow(
                    color: .black.opacity(isFocused ? Theme.focusShadowOpacity : 0),
                    radius: Theme.focusShadowRadius,
                    y: Theme.focusShadowYOffset
                )
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeTrigger) { view, offset in
                    view.offset(x: offset)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-Theme.shakeDistance, duration: 0.05)
                        LinearKeyframe(Theme.shakeDistance, duration: 0.1)
                        LinearKeyframe(-Theme.shakeDistance / 2, duration: 0.1)
                        LinearKeyframe(0, duration: 0.05)
                    }
                }

            Text(title)
                .font(Theme.tileTitleFont)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .opacity(isFocused ? 1 : 0)
        }
        .animation(Theme.focusAnimation, value: isFocused)
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous)
        return ZStack {
            shape.fill(Theme.tileFill)

            artwork
                .opacity(isInstalled ? 1 : Theme.unavailableOpacity)

            if !isInstalled {
                VStack {
                    Spacer()
                    Text("Not installed")
                        .font(Theme.tileCaptionFont)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.bottom, 12)
                }
            }

            if isFocused {
                shape.strokeBorder(Theme.focusHighlight, lineWidth: Theme.focusHighlightWidth)
            }
        }
        .frame(width: Theme.tileSize.width, height: Theme.tileSize.height)
        .contentShape(shape)
    }

    @ViewBuilder
    private var artwork: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: Theme.tileSize.height * Theme.tileIconFraction)
        } else {
            Image(systemName: item.iconSymbol ?? "app.dashed")
                .font(.system(size: Theme.tileSymbolSize))
                .foregroundStyle(Theme.primaryText)
        }
    }
}
