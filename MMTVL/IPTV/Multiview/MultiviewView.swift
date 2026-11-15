import SwiftUI

/// Multiview's overlay on the 1920×1080 canvas (M6): empty windows, per-window status, the outlines, the channel
/// chip and the timeshift label. The videos sit under it (L15).
/// M7m (D51, burn-in): nothing static stays bright. The bold outline on the focused window shows after each press and
/// fades to a thin, faint outline on the window with sound (L12, L13; it replaces the speaker badge); the empty and
/// failed windows' text fades with it (L14); the pause symbol and timeshift label hide 15 s after a press (L15).
struct MultiviewOverlayView: View {
    let model: LiveTVModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let multiview = model.multiview {
                let rects = multiview.layout.slots
                ForEach(Array(rects.enumerated()), id: \.offset) { slot, rect in
                    windowOverlay(multiview, slot: slot)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: model.banner)
        .animation(.easeInOut(duration: 0.2), value: model.showsTimeshiftBar)
    }

    @ViewBuilder
    private func windowOverlay(_ multiview: MultiviewModel, slot: Int) -> some View {
        let isFocused = slot == multiview.focusedSlot
        let id = multiview.slots[slot]
        let state = id.flatMap { model.tilePlayers[$0] }?.state
        // L14: the windows' own text, bright only around a press (always on the focused window).
        let showsText = model.multiviewHighlightVisible || isFocused
        // M7j L8, L9: the window's own text ("Can't play this channel", "Both antenna tuners are in use", …).
        let failure = id.flatMap { model.windowErrors[$0] }
        let isFailed = failure != nil
        // L15: these two change only when they show or hide, so their fades don't ride on every press.
        let showsPause = id != nil && !isFailed && state?.phase == .paused && model.pausedOverlayVisible
        let showsLabel = isFocused && id != nil
            && (model.showsTimeshiftBar || (state?.phase == .paused && model.pausedOverlayVisible))
        ZStack {
            if id != nil {
                if let failure {
                    ZStack {
                        Color.black.opacity(0.6)
                        Text(failure)
                            .font(Theme.multiviewChipDetailFont)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.primaryText)
                            .opacity(showsText ? 1 : 0)
                            .animation(Theme.multiviewHighlightFade, value: showsText)
                    }
                } else if state?.phase == .loading {
                    ProgressView().controlSize(.large)
                }
                ZStack {
                    if showsPause {
                        Image(systemName: "pause.fill")
                            .font(.system(size: Theme.multiviewEmptySymbolSize))
                            .foregroundStyle(Theme.primaryText)
                            .padding(28)
                            .glassPanel(in: Circle())
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showsPause)
                ZStack {
                    if showsLabel, let timeshift = state?.timeshift, !timeshift.isLive {
                        timeshiftLabel(timeshift)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showsLabel)
            } else {
                emptyWindow(showsText: showsText)
            }
            if isFocused, id != nil, let banner = model.banner {
                chip(banner)
                    .transition(.opacity)
            }
            outlines(isFocused: isFocused, hasSound: slot == multiview.audioSlot)
                .animation(Theme.multiviewHighlightFade, value: model.multiviewHighlightVisible)
                .animation(Theme.multiviewHighlightFade, value: multiview.focusedSlot)
                .animation(Theme.multiviewHighlightFade, value: multiview.audioSlot)
        }
    }

    /// L12, L13: the bold outline on the focused window while the highlight shows; the thin one on the window with
    /// sound whenever the bold one isn't on it. Both are always in the tree, so they fade rather than pop.
    private func outlines(isFocused: Bool, hasSound: Bool) -> some View {
        let bold = isFocused && model.multiviewHighlightVisible
        return ZStack {
            Rectangle()
                .strokeBorder(Theme.multiviewRestingBorder, lineWidth: Theme.multiviewRestingBorderWidth)
                .opacity(hasSound && !bold ? 1 : 0)
            Rectangle()
                .strokeBorder(Theme.multiviewFocusBorder, lineWidth: Theme.multiviewFocusBorderWidth)
                .opacity(bold ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    /// How far behind live, at the window's top-left (as M4's badge).
    private func timeshiftLabel(_ timeshift: Timeshift) -> some View {
        VStack {
            HStack {
                Text(timeshift.label)
                    .font(Theme.multiviewChipDetailFont.monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassPanel(in: Capsule())
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    /// L14: the fill stays; the plus and "Add Channel" fade with the highlight.
    private func emptyWindow(showsText: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius)
                .fill(Theme.tileFill)
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: Theme.multiviewEmptySymbolSize))
                    .foregroundStyle(Theme.primaryText)
                Text("Add Channel")
                    .font(Theme.multiviewChipDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
            .opacity(showsText ? 1 : 0)
            .animation(Theme.multiviewHighlightFade, value: showsText)
        }
    }

    private func chip(_ banner: LiveTVModel.Banner) -> some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.channel.name)
                    .font(Theme.multiviewChipFont)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if let now = banner.now {
                    Text(now.title)
                        .font(Theme.multiviewChipDetailFont)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Text("Select: options · Back: full screen")
                    .font(Theme.multiviewChipDetailFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(in: Rectangle())
        }
    }
}

/// A small picture of a layout for the layout menu (M6 L10): its raw slots scaled into `multiviewDiagramSize`.
struct MultiviewLayoutDiagram: View {
    let layout: MultiviewLayout
    var tint: Color = Theme.primaryText

    var body: some View {
        let size = Theme.multiviewDiagramSize
        let scale = size.width / Theme.canvasSize.width
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.rawSlots.enumerated()), id: \.offset) { index, raw in
                let rect = CGRect(x: raw.minX * scale, y: raw.minY * scale,
                                  width: raw.width * scale, height: raw.height * scale).insetBy(dx: 1, dy: 1)
                let isInset = layout == .pictureInPicture && index > 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isInset ? tint : Theme.tileFill)
                    .strokeBorder(tint, lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
