import SwiftUI

/// A `LiveMenu` as a centered panel over Live TV, on the 1920×1080 canvas (M6 L10).
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
                ForEach(Array(menu.items.enumerated()), id: \.element.id) { index, item in
                    row(item, isFocused: index == menu.focusedIndex)
                }
                Text("Select: choose · Back: close")
                    .font(Theme.settingsHintFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 16)
            }
            .padding(32)
            .frame(width: Theme.liveMenuWidth, alignment: .leading)
            .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.tileCornerRadius))
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
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
