import SwiftUI

/// A `LiveMenu` as a centered panel over Live TV, on the 1920×1080 canvas (M6 L10). Shows the visible window of
/// rows with chevrons where rows are hidden (M6b L10).
struct LiveMenuView: View {
    let menu: LiveMenu

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
                Text(menu.title)
                    .font(Theme.liveMenuTitleFont)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .padding(.bottom, 16)
                chevron("chevron.up", shows: menu.hasHiddenAbove)
                ForEach(menu.visibleRange, id: \.self) { index in
                    row(menu.items[index], isFocused: index == menu.focusedIndex)
                }
                chevron("chevron.down", shows: menu.hasHiddenBelow)
                Text("Select: choose · Back: close")
                    .font(Theme.settingsHintFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 16)
            }
            .padding(32)
            .frame(width: menu.isWide ? Theme.liveMenuWideWidth : Theme.liveMenuWidth, alignment: .leading)
            .glassPanel()
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }

    /// Always takes its line, so the panel doesn't jump when it appears.
    private func chevron(_ symbol: String, shows: Bool) -> some View {
        Image(systemName: symbol)
            .font(Theme.settingsDetailFont)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .opacity(shows ? 1 : 0)
    }

    private func row(_ item: LiveMenu.Item, isFocused: Bool) -> some View {
        HStack(spacing: 20) {
            if let layout = item.layout {
                MultiviewLayoutDiagram(layout: layout, tint: isFocused ? Theme.focusedRowText : Theme.primaryText)
            }
            Text(item.title)
                .font(Theme.settingsRowFont)
                .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let value = item.value {
                Text(value)
                    .font(Theme.settingsDetailFont)
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Theme.liveMenuRowHeight)
        .background(isFocused ? Theme.focusedRowFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.settingsRowCornerRadius))
    }
}
