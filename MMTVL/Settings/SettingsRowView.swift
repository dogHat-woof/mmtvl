import SwiftUI

/// One Settings row. Focused (or lifted) rows turn white with dark text, as on tvOS.
struct SettingsRowView: View {
    let row: SettingsRow
    let isFocused: Bool
    let launcher: AppLauncher
    let onHover: () -> Void
    let onActivate: () -> Void

    /// Info rows never look focused.
    private var isHighlighted: Bool { (isFocused || row.isLifted) && row.action != nil }
    private var primary: Color { isHighlighted ? Theme.focusedRowText : Theme.primaryText }
    private var secondary: Color { isHighlighted ? Theme.focusedRowSecondaryText : Theme.secondaryText }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.settingsRowCornerRadius, style: .continuous)
        HStack(spacing: 24) {
            if let image = row.image {
                RowImageView(image: image, launcher: launcher, size: Theme.settingsRowIconSize, foreground: primary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(Theme.settingsRowFont)
                    .foregroundStyle(primary)
                if let detail = row.detail {
                    Text(detail)
                        .font(Theme.settingsDetailFont)
                        .foregroundStyle(secondary)
                }
            }
            Spacer(minLength: 16)
            if row.needsRelaunch {
                Text("Relaunch needed")
                    .font(Theme.settingsDetailFont)
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().strokeBorder(secondary))
            }
            if let value = row.value {
                Text(value)
                    .font(Theme.settingsRowFont)
                    .foregroundStyle(secondary)
            }
            if row.isLifted {
                Image(systemName: "arrow.up.arrow.down")
                    .font(Theme.settingsRowFont)
                    .foregroundStyle(secondary)
            }
            if row.showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(Theme.settingsDetailFont.weight(.semibold))
                    .foregroundStyle(secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.settingsRowMinHeight, alignment: .leading)
        .background(shape.fill(isHighlighted ? Theme.focusedRowFill : .clear))
        .contentShape(shape)
        .opacity(row.isDimmed && !isHighlighted ? Theme.unavailableOpacity : 1)
        .scaleEffect(isHighlighted ? Theme.settingsRowFocusScale : 1)
        .shadow(
            color: .black.opacity(isHighlighted ? Theme.focusShadowOpacity : 0),
            radius: Theme.focusShadowRadius,
            y: Theme.focusShadowYOffset
        )
        .animation(Theme.focusAnimation, value: isHighlighted)
        .onHover { hovering in
            if hovering { onHover() }
        }
        .onTapGesture(perform: onActivate)
    }
}

/// An SF Symbol or app icon for a row or the page's side column.
struct RowImageView: View {
    let image: RowImage
    let launcher: AppLauncher
    let size: CGFloat
    var foreground: Color = Theme.primaryText

    var body: some View {
        switch image {
        case .symbol(let name):
            symbol(name)
        case .item(let item):
            if let icon = launcher.icon(for: item) {
                iconImage(icon)
            } else {
                symbol(item.iconSymbol ?? "app.dashed")
            }
        case .app(let url):
            iconImage(launcher.icon(forApplicationAt: url))
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.8))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
    }

    private func iconImage(_ icon: NSImage) -> some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
