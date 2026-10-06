import SwiftUI

/// Multiview's overlay on the 1920×1080 canvas (M6): empty windows, per-window status, the sound badge,
/// the highlight, the channel chip and the timeshift label. The videos sit under it (L15).
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
        ZStack {
            if let id {
                if model.failedWindows.contains(id) {
                    ZStack {
                        Color.black.opacity(0.6)
                        Text(LiveTVModel.playbackErrorMessage)
                            .font(Theme.multiviewChipDetailFont)
                            .foregroundStyle(Theme.primaryText)
                    }
                } else if state?.phase == .loading {
                    ProgressView().controlSize(.large)
                } else if state?.phase == .paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: Theme.multiviewEmptySymbolSize))
                        .foregroundStyle(Theme.primaryText)
                        .padding(28)
                        .glassPanel(in: Circle())
                }
                if slot == multiview.audioSlot, multiview.channelIDs.count > 1 {
                    soundBadge
                }
                if isFocused, let state, model.showsTimeshiftBar || state.phase == .paused,
                   let timeshift = state.timeshift, !timeshift.isLive {
                    timeshiftLabel(timeshift)
                        .transition(.opacity)
                }
            } else {
                emptyWindow
            }
            if isFocused, id != nil, let banner = model.banner {
                chip(banner)
                    .transition(.opacity)
            }
            if isFocused {
                Rectangle()
                    .strokeBorder(Theme.multiviewFocusBorder, lineWidth: Theme.multiviewFocusBorderWidth)
            }
        }
    }

    private var soundBadge: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.multiviewChipDetailFont)
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassPanel(in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
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

    private var emptyWindow: some View {
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
