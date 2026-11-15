import SwiftUI

/// M7m L5, L6 (D50): the home tile menu, a sibling of `PowerMenuView`: a centered glass panel on the 1920×1080 canvas
/// (D29) with the tile's title, rows with a right-aligned value column like `LiveMenuView`'s ("On", "Off"), and a lock
/// on the rows that ask for the PIN while one is set. `LauncherRootView` dims the window behind it.
struct TileMenuView: View {
    static let hint = "Select: choose · Back: close"

    let menu: TileMenu
    let hasPIN: Bool
    var onHover: (Int) -> Void = { _ in }
    var onChoose: (Int) -> Void = { _ in }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
                Text(menu.title)
                    .font(Theme.liveMenuTitleFont)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .padding(.bottom, Theme.menuTitleSpacing)
                ForEach(Array(menu.items.enumerated()), id: \.element.id) { index, item in
                    row(item, isFocused: index == menu.focusedIndex)
                        .contentShape(Rectangle())
                        .onHover { inside in if inside { onHover(index) } }
                        .onTapGesture { onChoose(index) }
                }
                Text(Self.hint)
                    .font(Theme.settingsHintFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, Theme.menuTitleSpacing)
            }
            .padding(Theme.menuPanelPadding)
            .frame(width: Theme.liveMenuWidth, alignment: .leading)
            .glassPanel()
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }

    private func row(_ item: TileMenu.Item, isFocused: Bool) -> some View {
        HStack(spacing: Theme.menuRowPadding) {
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
            if hasPIN && item.action.needsPIN {
                Image(systemName: "lock.fill")
                    .font(Theme.settingsDetailFont)
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
            }
        }
        .padding(.horizontal, Theme.menuRowPadding)
        .frame(height: Theme.liveMenuRowHeight)
        .background(isFocused ? Theme.focusedRowFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.liveMenuRowCornerRadius))
    }
}
