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
    /// M7m L8: this tile is being moved: lifted above the focus scale and wiggling (no wiggle with Reduce Motion).
    var isMoving = false

    var body: some View {
        VStack(spacing: Theme.tileTitleSpacing) {
            tile
                .parallaxFocus(isFocused: isFocused, motion: focusMotion, cornerRadius: Theme.tileCornerRadius)
                // M7m L8: after the parallax, so the lift and wiggle take the whole tile, shine and shadow included.
                .scaleEffect(isMoving ? Theme.tileMoveLiftScale : 1)
                .modifier(TileJiggle(isOn: isMoving))
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
        .animation(Theme.focusAnimation, value: isMoving)
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

/// M7m L8: the moving tile's wiggle, ± `Theme.tileJiggleAngle` once per `Theme.tileJiggleDuration`, drawn from the
/// clock so it stops dead (at rest) when the move ends. Reduce Motion: none, the lift alone shows the move.
private struct TileJiggle: ViewModifier {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let wiggles = isOn && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: !wiggles)) { context in
            content.rotationEffect(.degrees(wiggles ? Self.angle(at: context.date) : 0))
        }
    }

    static func angle(at date: Date) -> Double {
        let period = Theme.tileJiggleDuration
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return sin(phase * 2 * .pi) * Theme.tileJiggleAngle
    }
}
