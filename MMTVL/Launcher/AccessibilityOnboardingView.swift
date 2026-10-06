import SwiftUI

/// Asks for the Accessibility permission on first kiosk launch (L7). Remote-navigable:
/// Select opens Settings, Back dismisses.
struct AccessibilityOnboardingView: View {
    let onOpenSettings: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: Theme.tileSymbolSize * 2))
                .foregroundStyle(Theme.primaryText)
            Text("Allow MMTVL to control this Mac")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("MMTVL needs Accessibility access so the Home button works in every app, media keys reach MMTVL, and apps open full screen.")
                .font(Theme.clockFont)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Theme.canvasSize.width / 2)
            HStack(spacing: Theme.tileSpacing) {
                capsule("Open Settings", isFocused: true, action: onOpenSettings)
                capsule("Not now", isFocused: false, action: onNotNow)
            }
            .padding(.top, 24)
            Text("Select: Open Settings · Back: Not now")
                .font(Theme.tileCaptionFont)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 24)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }

    /// Uses the M1 tile focus visuals: fill, highlight stroke, scale and shadow.
    private func capsule(_ title: String, isFocused: Bool, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(Theme.tileTitleFont)
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 48)
            .padding(.vertical, 20)
            .background(Capsule().fill(Theme.tileFill))
            .overlay {
                if isFocused {
                    Capsule().strokeBorder(Theme.focusHighlight, lineWidth: Theme.focusHighlightWidth)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(isFocused ? Theme.focusScale : 1)
            .shadow(
                color: .black.opacity(isFocused ? Theme.focusShadowOpacity : 0),
                radius: Theme.focusShadowRadius,
                y: Theme.focusShadowYOffset
            )
            .onTapGesture(perform: action)
    }
}
