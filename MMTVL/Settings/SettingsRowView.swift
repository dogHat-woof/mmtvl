import SwiftUI

/// One Settings row. Focused (or lifted) rows turn white with dark text, as on tvOS.
struct SettingsRowView: View {
    let row: SettingsRow
    let isFocused: Bool
    let launcher: AppLauncher
    var tileArt: TileArtStore? = nil
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
                RowImageView(image: image, launcher: launcher, size: Theme.settingsRowIconSize, foreground: primary,
                             tileArt: tileArt)
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
    /// M7 L25: for `.tileArt` and `.picture`.
    var tileArt: TileArtStore? = nil
    var items: [LaunchItem] = []

    var body: some View {
        switch image {
        case .picture(let url):
            if let preview = tileArt?.preview(of: url) {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Theme.settingsRowThumbnailSize.width, height: Theme.settingsRowThumbnailSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                symbol("photo")
            }
        case .tileArt(let itemID, let choice):
            if let art = tileArtPreview(itemID: itemID, choice) {
                let radius = Theme.tileCornerRadius * Theme.settingsArtPreviewSize.width / Theme.tileSize.width
                TileArtView(art: art, size: Theme.settingsArtPreviewSize, cornerRadius: radius)
                    .glassRim(cornerRadius: radius)
            } else {
                symbol("photo")
            }
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
        case .qrCode(let string):
            if let qrCode = QRCodeImage.make(string) {
                qrCodeImage(qrCode)
            } else {
                symbol("qrcode")
            }
        }
    }

    private func tileArtPreview(itemID: String, _ choice: TileArtChoice) -> TileArt? {
        guard let tileArt, let item = items.first(where: { $0.id == itemID }) else { return nil }
        let icon = launcher.icon(for: item)
        let bundleID = launcher.bundleID(for: item)
        switch choice {
        case .current: return tileArt.art(for: item, icon: icon, bundleID: bundleID)
        case .style(let style): return tileArt.styledArt(for: item, icon: icon, bundleID: bundleID, style: style)
        case .file(let url): return tileArt.preview(of: url).map(TileArt.picture)
        }
    }

    /// Ignores `size`. White padding keeps the quiet zone the QR spec asks for.
    private func qrCodeImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(Theme.settingsQRCodeSize * 0.08)
            .frame(width: Theme.settingsQRCodeSize, height: Theme.settingsQRCodeSize)
            .background(RoundedRectangle(cornerRadius: 24).fill(.white))
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
