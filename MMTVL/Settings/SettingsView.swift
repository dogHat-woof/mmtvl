import SwiftUI

/// The Settings screen on the 1920×1080 canvas: title, side image, scrolling list, hint (D19).
struct SettingsView: View {
    let model: SettingsModel
    let launcher: AppLauncher
    let onHoverRow: (String) -> Void
    let onActivateRow: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(model.pageTitle)
                .font(Theme.settingsTitleFont)
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 60)
                .padding(.bottom, 24)

            HStack(alignment: .center, spacing: Theme.settingsColumnSpacing) {
                RowImageView(image: model.pageImage, launcher: launcher, size: Theme.settingsPageImageSize)
                    .frame(width: Theme.settingsSideColumnWidth)
                list
                    .frame(width: Theme.settingsListWidth)
                    // Keeps scrolled rows from drawing over the page title and hint.
                    .clipped()
            }
            .frame(maxHeight: .infinity)

            Text(model.hint)
                .font(Theme.settingsHintFont)
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, 48)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.settingsSectionSpacing) {
                    ForEach(model.sections) { section in
                        sectionView(section)
                    }
                }
                // Room for the focused row's scale and shadow.
                .padding(.vertical, 40)
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo(model.focusedRowID, anchor: .center) }
            .onChange(of: model.page) { proxy.scrollTo(model.focusedRowID, anchor: .center) }
            .onChange(of: model.focusedRowID) { _, id in
                withAnimation(Theme.focusAnimation) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func sectionView(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
            if let title = section.title {
                Text(title)
                    .font(Theme.settingsSectionFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 32)
            }
            ForEach(section.rows) { row in
                SettingsRowView(
                    row: row,
                    isFocused: row.id == model.focusedRowID,
                    launcher: launcher,
                    onHover: { onHoverRow(row.id) },
                    onActivate: { onActivateRow(row.id) }
                )
                .id(row.id)
            }
            if let footer = section.footer {
                Text(footer)
                    .font(Theme.settingsDetailFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 32)
            }
        }
    }
}
