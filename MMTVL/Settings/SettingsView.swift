import SwiftUI

/// The Settings screen on the 1920×1080 canvas (D19, M7g): the gray page title, the sliding column track (L1)
/// and the description band (L3).
struct SettingsView: View {
    let model: SettingsModel
    let launcher: AppLauncher
    /// M7 L25: Tile Art previews.
    let tileArt: TileArtStore
    /// A row's id and its column's page (only the current page's rows react).
    let onHoverRow: (String, SettingsPage) -> Void
    let onActivateRow: (String, SettingsPage) -> Void
    /// M7g: a click on the parent column goes back a page.
    let onActivateParent: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Fades through (the old title out, then the new one in), so two titles never overlap.
            ZStack {
                Text(model.title(for: model.page))
                    .font(Theme.settingsTitleFont)
                    .foregroundStyle(Theme.secondaryText)
                    .id(model.title(for: model.page))
                    .transition(Theme.settingsFadeThrough)
            }
            .animation(Theme.settingsFadeOutAnimation, value: model.title(for: model.page))
            .padding(.top, 60)
            .padding(.bottom, 24)

            track

            band
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }

    /// L1: where the track sits. -1 at the root (the root list centered, nothing beside it); from the first
    /// category on, the top two pages stay on screen and each level deeper slides the track one column left.
    /// Every change slides, so opening a category and going back to the root move the root list too.
    private var trackPosition: Int { model.stack.count == 1 ? -1 : max(0, model.stack.count - 2) }

    private var trackOffset: CGFloat {
        if trackPosition < 0 { return Theme.settingsRootColumnLeading }
        return Theme.settingsSideMargin - CGFloat(trackPosition) * (Theme.settingsColumnWidth + Theme.settingsColumnGap)
    }

    private var track: some View {
        ZStack {
            columns
                // Reduce Motion: no slide; the whole track fades through to its new position instead of jumping.
                .id(reduceMotion ? trackPosition : 0)
                .transition(Theme.settingsFadeThrough)
        }
        .frame(width: Theme.canvasSize.width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? Theme.settingsFadeOutAnimation : Theme.settingsPageAnimation, value: trackPosition)
    }

    private var columns: some View {
        HStack(spacing: Theme.settingsColumnGap) {
            ForEach(model.columns) { column in
                SettingsColumnView(
                    model: model,
                    column: column,
                    launcher: launcher,
                    tileArt: tileArt,
                    onHoverRow: onHoverRow,
                    onActivateRow: onActivateRow,
                    onActivateParent: onActivateParent
                )
                .frame(width: Theme.settingsColumnWidth)
                // Content that fades in or out moves with its column during the slide, instead of
                // appearing at its final place (or staying at its old one).
                .geometryGroup()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: trackOffset)
    }

    /// L3: the mode hint or the focused row's description; its height is reserved so the columns never move.
    private var band: some View {
        ZStack {
            if let text = model.bandText {
                Text(text)
                    .font(Theme.settingsDescriptionFont)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .id(text)
                    .transition(Theme.settingsFadeThrough)
            }
        }
        .frame(maxWidth: Theme.settingsBandMaxWidth)
        .frame(height: Theme.settingsBandHeight, alignment: .top)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .animation(Theme.settingsFadeOutAnimation, value: model.bandText)
    }
}
