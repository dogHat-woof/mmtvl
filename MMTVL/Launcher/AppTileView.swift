import SwiftUI

/// One home screen tile: a 5:3 rounded rect with its art (M7 L3, L4).
struct AppTileView: View {
    let item: LaunchItem
    let title: String
    let art: TileArt
    let isFocused: Bool
    let isInstalled: Bool
    /// Incremented to play the "can't open" shake (L6).
    let shakeTrigger: Int
    /// M7 L2: drives the parallax nudge and press.
    let focusMotion: FocusMotion

    var body: some View {
        VStack(spacing: Theme.tileTitleSpacing) {
            tile
                .parallaxFocus(isFocused: isFocused, motion: focusMotion, cornerRadius: Theme.tileCornerRadius)
                // After the parallax, so the shake moves the whole tile.
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
                .frame(height: Theme.tileTitleHeight)
                .opacity(isFocused ? 1 : 0)
        }
        .animation(Theme.focusAnimation, value: isFocused)
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous)
        return ZStack {
            shape.fill(Theme.tileFill)

            TileArtView(art: art)
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

        }
        .frame(width: Theme.tileSize.width, height: Theme.tileSize.height)
        // L26: the glass edge, inside the parallax so it tilts with the tile.
        .glassRim(cornerRadius: Theme.tileCornerRadius, isFocused: isFocused)
        .contentShape(shape)
    }
}
