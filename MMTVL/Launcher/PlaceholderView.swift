import SwiftUI

/// "Coming soon" screen for internal destinations (YouTube → M3, IPTV → M4).
struct PlaceholderView: View {
    let item: LaunchItem

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: item.iconSymbol ?? "square.dashed")
                .font(.system(size: Theme.tileSymbolSize * 2))
                .foregroundStyle(Theme.primaryText)
            Text(item.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Coming soon")
                .font(Theme.clockFont)
                .foregroundStyle(Theme.secondaryText)
            Text("Press Back to return")
                .font(Theme.tileCaptionFont)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 48)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }
}
