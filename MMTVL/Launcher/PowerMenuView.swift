import SwiftUI

/// M7h L15: the power menu as a centered glass panel on the 1920×1080 canvas (D29), laid out like `LiveMenuView`;
/// `LauncherRootView` dims the window behind it. Relaunch and Restart show a lock while a PIN is set.
struct PowerMenuView: View {
    let menu: PowerMenu
    let hasPIN: Bool
    var onHover: (Int) -> Void = { _ in }
    var onChoose: (Int) -> Void = { _ in }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
                Text(PowerMenu.title)
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
                Text("Select: choose · Back: close")
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

    private func row(_ item: PowerMenu.Item, isFocused: Bool) -> some View {
        HStack(spacing: Theme.menuRowPadding) {
            Text(item.title)
                .font(Theme.settingsRowFont)
                .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
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
