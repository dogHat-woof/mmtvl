import SwiftUI

/// Pure math of the parallax focus effect (M7 L1). Main-actor because it reads `Theme` tokens.
enum ParallaxMath {
    /// The tilt a newly focused tile starts with: toward the side focus came from (−direction × amount).
    /// x > 0 = right, y > 0 = down. Non-arrow commands: none.
    static func nudge(for direction: RemoteCommand) -> CGSize {
        let amount = Theme.parallaxNudgeAmount
        switch direction {
        case .right: return CGSize(width: -amount, height: 0)
        case .left: return CGSize(width: amount, height: 0)
        case .down: return CGSize(width: 0, height: -amount)
        case .up: return CGSize(width: 0, height: amount)
        default: return .zero
        }
    }

    /// The pointer's location over the tile, normalized to −1…1 on both axes (y down = positive).
    static func tilt(hover: CGPoint, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        func normalize(_ value: CGFloat, _ length: CGFloat) -> CGFloat { min(max(value / length * 2 - 1, -1), 1) }
        return CGSize(width: normalize(hover.x, size.width), height: normalize(hover.y, size.height))
    }

    /// Where the shine sits, in unit coordinates.
    static func specularCenter(tilt: CGSize) -> UnitPoint {
        UnitPoint(x: 0.5 + tilt.width * 0.35, y: 0.15 + tilt.height * 0.35)
    }

    /// M7h 13f: whether a hover update should tilt the tile: only when the pointer (screen coordinates) moved since
    /// `last`, the position recorded when the tile was focused or at the last update it followed. A pointer that
    /// hasn't moved means the view moved under it (focus, scroll, a tilt), so it doesn't tilt. None recorded: no.
    static func followsPointer(at location: CGPoint, last: CGPoint?) -> Bool {
        guard let last else { return false }
        return location != last
    }
}

/// What a keyframe run animates: the nudge tilt and the Select press.
nonisolated private struct ParallaxKeyframes {
    var tilt: CGSize = .zero
    var press: CGFloat = 1
}

nonisolated extension EnvironmentValues {
    /// The focused tile's current tilt (−1…1), for art layers that move with it.
    @Entry var parallaxTilt: CGSize = .zero
}

/// The tvOS focus effect (L1): lift, tilt toward where focus came from (or under the pointer), specular shine.
struct ParallaxFocus: ViewModifier {
    let isFocused: Bool
    let motion: FocusMotion
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverTilt: CGSize = .zero
    @State private var size: CGSize = .zero
    /// M7h 13f: the pointer's screen location when the tile was focused, then at each hover update while focused.
    @State private var lastPointer: CGPoint?

    func body(content: Content) -> some View {
        // The keyframe content closure is Sendable: it gets plain values, not this view's state.
        let isFocused = isFocused
        let reduceMotion = reduceMotion
        let hoverTilt = hoverTilt
        let cornerRadius = cornerRadius
        let width = size.width
        return content
            .onChange(of: isFocused, initial: true) {
                if isFocused {
                    lastPointer = NSEvent.mouseLocation
                } else {
                    self.hoverTilt = .zero
                    lastPointer = nil
                }
            }
            .keyframeAnimator(initialValue: ParallaxKeyframes(), trigger: keyframeTrigger) { view, frame in
                view.modifier(ParallaxRender(hoverTilt: hoverTilt, nudge: frame.tilt, press: frame.press, isFocused: isFocused,
                                             reduceMotion: reduceMotion, cornerRadius: cornerRadius, width: width))
            } keyframes: { _ in
                let direction = isFocused && !reduceMotion ? motion.direction : nil
                KeyframeTrack(\.tilt) {
                    MoveKeyframe(direction.map(ParallaxMath.nudge(for:)) ?? .zero)
                    SpringKeyframe(.zero, duration: 0.8, spring: Theme.parallaxKeyframeSpring)
                }
                KeyframeTrack(\.press) {
                    CubicKeyframe(direction == .select ? Theme.pressScale : 1, duration: 0.1)
                    CubicKeyframe(1, duration: 0.1)
                }
            }
            // M7h 13f: hover outside the tilt and scale, on the untilted shape, so a tilt can't change what the
            // pointer is over or where (inside the transforms each tilt moved the location: a hover loop). The shape
            // grows with focus (the focused tile draws at `focusScale`, with or without Reduce Motion), never with
            // the tilt, so hover and clicks reach the drawn edge.
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .scale(isFocused ? Theme.focusScale : 1))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                guard isFocused, !reduceMotion else { return }
                switch phase {
                case .active(let location):
                    let pointer = NSEvent.mouseLocation
                    let follows = ParallaxMath.followsPointer(at: pointer, last: lastPointer)
                    lastPointer = pointer
                    guard follows else { return }
                    withAnimation(.interactiveSpring) { self.hoverTilt = ParallaxMath.tilt(hover: location, in: size) }
                case .ended:
                    withAnimation(Theme.parallaxSpring) { self.hoverTilt = .zero }
                }
            }
            .shadow(
                color: .black.opacity(isFocused ? Theme.focusShadowOpacity : 0),
                radius: Theme.focusShadowRadius,
                y: Theme.focusShadowYOffset
            )
    }

    /// Runs the keyframes when focus arrives or a focused tile is selected; unfocused tiles settle to rest.
    private var keyframeTrigger: Int { isFocused ? motion.generation : -1 }
}

/// One frame of the effect: tilt (pointer + nudge), shine and scale.
private struct ParallaxRender: ViewModifier {
    let hoverTilt: CGSize
    let nudge: CGSize
    let press: CGFloat
    let isFocused: Bool
    let reduceMotion: Bool
    let cornerRadius: CGFloat
    let width: CGFloat

    nonisolated init(hoverTilt: CGSize, nudge: CGSize, press: CGFloat, isFocused: Bool, reduceMotion: Bool,
                     cornerRadius: CGFloat, width: CGFloat) {
        self.hoverTilt = hoverTilt
        self.nudge = nudge
        self.press = press
        self.isFocused = isFocused
        self.reduceMotion = reduceMotion
        self.cornerRadius = cornerRadius
        self.width = width
    }

    func body(content: Content) -> some View {
        let tilt = isFocused && !reduceMotion ? clamped(hoverTilt + nudge) : .zero
        content
            .environment(\.parallaxTilt, tilt)
            .overlay { if isFocused { specular(tilt: tilt) } }
            .rotation3DEffect(.degrees(tilt.width * Theme.parallaxMaxDegrees), axis: (x: 0, y: 1, z: 0),
                              perspective: Theme.parallaxPerspective)
            .rotation3DEffect(.degrees(-tilt.height * Theme.parallaxMaxDegrees), axis: (x: 1, y: 0, z: 0),
                              perspective: Theme.parallaxPerspective)
            .scaleEffect(isFocused ? Theme.focusScale * (reduceMotion ? 1 : press) : 1)
    }

    private func clamped(_ tilt: CGSize) -> CGSize {
        CGSize(width: min(max(tilt.width, -1), 1), height: min(max(tilt.height, -1), 1))
    }

    private func specular(tilt: CGSize) -> some View {
        RadialGradient(
            colors: [.white.opacity(Theme.specularOpacity), .white.opacity(0)],
            center: ParallaxMath.specularCenter(tilt: tilt),
            startRadius: 0,
            endRadius: max(width, 1) * Theme.specularRadiusFraction
        )
        .blendMode(.plusLighter)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// An art layer that moves with the focused tile's tilt (depth).
struct ParallaxLayer<Content: View>: View {
    @Environment(\.parallaxTilt) private var tilt
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(x: tilt.width * Theme.parallaxLayerOffset, y: tilt.height * Theme.parallaxLayerOffset)
    }
}

extension View {
    /// L1. The shake (or anything that must move the whole tile) goes after this modifier.
    func parallaxFocus(isFocused: Bool, motion: FocusMotion, cornerRadius: CGFloat) -> some View {
        modifier(ParallaxFocus(isFocused: isFocused, motion: motion, cornerRadius: cornerRadius))
    }
}

private func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}
