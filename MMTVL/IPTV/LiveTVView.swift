import AppKit
import SwiftUI

/// The canvas transform `LauncherRootView` applies, for placing AppKit views (the video) in window coordinates.
nonisolated enum CanvasGeometry {
    static let canvas = CGSize(width: 1920, height: 1080)

    /// Same transform LauncherRootView applies: scale = size.width / 1920, canvas centered.
    static func windowRect(forCanvasRect rect: CGRect, in size: CGSize) -> CGRect {
        let scale = size.width / canvas.width
        let originY = (size.height - canvas.height * scale) / 2
        let originX = (size.width - canvas.width * scale) / 2
        return CGRect(x: originX + rect.minX * scale, y: originY + rect.minY * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }
}

/// Live TV: the video view at window size (L16), with overlays on the scaled canvas above it.
struct LiveTVRootView: View {
    let model: LiveTVModel

    private var controller: MPVPlayerController? { model.player as? MPVPlayerController }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.black
                if let videoView = controller?.videoView {
                    let rect = videoRect(in: size)
                    MPVVideoRepresentable(view: videoView)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(showsVideo ? 1 : 0)
                        .transaction { $0.animation = nil }
                }
                overlay
                    .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
                    .scaleEffect(Theme.scale(for: size))
                    .frame(width: size.width, height: size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear { controller?.prepare() }
        .onChange(of: model.library.guideRevision) { model.guideDataChanged() }
        .onChange(of: model.library.channels) { model.channelsChanged() }
    }

    private var showsVideo: Bool {
        model.mode == .player || model.mode == .guide
    }

    /// Full window in player mode; the guide's preview window in guide mode (L16).
    private func videoRect(in size: CGSize) -> CGRect {
        model.mode == .guide
            ? CanvasGeometry.windowRect(forCanvasRect: Theme.guidePreviewRect, in: size)
            : CGRect(origin: .zero, size: size)
    }

    @ViewBuilder
    private var overlay: some View {
        switch model.mode {
        case .player:
            PlayerOverlayView(model: model)
        case .guide:
            if let guide = model.guide {
                GuideView(model: guide, currentChannel: model.currentChannel, phase: model.player.state.phase)
            }
        case .setupNeeded:
            LiveTVMessageView(title: "Live TV isn't set up",
                              message: "Copy your playlist URL, then open Settings → Live TV → Paste Playlist URL.",
                              hint: "Select: open Settings · Back: return")
        case .loading:
            VStack(spacing: 32) {
                ProgressView().controlSize(.large)
                Text("Loading channels…")
                    .font(Theme.settingsRowFont)
                    .foregroundStyle(Theme.secondaryText)
            }
        case .unavailable(let message):
            LiveTVMessageView(title: "Can't load channels", message: message, hint: "Select: try again · Back: return")
        }
    }
}

/// Hosts the player's one video view.
private struct MPVVideoRepresentable: NSViewRepresentable {
    let view: MPVVideoView

    func makeNSView(context: Context) -> MPVVideoView { view }
    func updateNSView(_ nsView: MPVVideoView, context: Context) {}
}

/// Setup, error and empty screens.
private struct LiveTVMessageView: View {
    let title: String
    let message: String
    let hint: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tv")
                .font(.system(size: Theme.tileSymbolSize * 2))
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .font(Theme.settingsTitleFont)
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(Theme.settingsRowFont)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1200)
            Text(hint)
                .font(Theme.settingsHintFont)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 32)
        }
    }
}

/// Banner, timeshift bar, behind-live badge, spinner and error panel (L11).
private struct PlayerOverlayView: View {
    let model: LiveTVModel

    private var state: PlayerState { model.player.state }

    var body: some View {
        ZStack {
            if state.phase == .loading && model.playbackError == nil {
                ProgressView().controlSize(.large)
            }
            if let error = model.playbackError {
                errorPanel(error)
            }
            // How far behind live, with the bar: after a seek, then it fades (user choice, 2026-10-06).
            if showsTimeshift, let timeshift = state.timeshift, !timeshift.isLive {
                VStack {
                    HStack {
                        Spacer()
                        Text(timeshift.label)
                            .font(Theme.liveBannerDetailFont.monospacedDigit())
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.horizontal, Theme.sideMargin)
                .transition(.opacity)
            }
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 24) {
                    if let banner = model.banner {
                        LiveBannerView(banner: banner)
                    }
                    if showsTimeshift {
                        TimeshiftBarView(timeshift: state.timeshift, isPaused: state.phase == .paused)
                    }
                }
                .padding(.horizontal, Theme.sideMargin)
                .padding(.top, 120)
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.liveOverlayGradient)
                .opacity(model.banner != nil || showsTimeshift ? 1 : 0)
            }
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
        .animation(.easeInOut(duration: 0.25), value: model.banner)
        .animation(.easeInOut(duration: 0.25), value: model.showsTimeshiftBar)
        .animation(.easeInOut(duration: 0.25), value: state.phase)
    }

    /// The bar and the behind-live badge: 5 s after a seek, and while paused.
    private var showsTimeshift: Bool {
        model.showsTimeshiftBar || state.phase == .paused
    }

    private func errorPanel(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Theme.tileSymbolSize))
                .foregroundStyle(Theme.secondaryText)
            Text(message)
                .font(Theme.settingsTitleFont)
                .foregroundStyle(Theme.primaryText)
            Text("Select: try again · Up/Down: change channel · Back: return")
                .font(Theme.settingsHintFont)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(60)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.tileCornerRadius))
    }
}

/// Channel, now and next.
struct LiveBannerView: View {
    let banner: LiveTVModel.Banner

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            if let logo = banner.channel.logoURL {
                AsyncImage(url: logo) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: Theme.liveBannerLogoSize, height: Theme.liveBannerLogoSize)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("\(banner.channel.number)  \(banner.channel.name)")
                    .font(Theme.liveBannerTitleFont)
                    .foregroundStyle(Theme.primaryText)
                if let now = banner.now {
                    Text(now.title)
                        .font(Theme.liveBannerProgrammeFont)
                        .foregroundStyle(Theme.primaryText)
                    HStack(spacing: 20) {
                        Text(Self.timeRange(now))
                            .font(Theme.liveBannerDetailFont)
                            .foregroundStyle(Theme.secondaryText)
                        ProgressView(value: Self.progress(of: now, at: Date()))
                            .progressViewStyle(.linear)
                            .tint(Theme.primaryText)
                            .frame(width: 320)
                    }
                    if let next = banner.next {
                        Text("Next: \(next.title) · \(next.start.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.liveBannerDetailFont)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    Text("No programme information")
                        .font(Theme.liveBannerDetailFont)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    /// "7:00 – 8:30 PM"
    static func timeRange(_ programme: Programme) -> String {
        (programme.start..<max(programme.start, programme.stop)).formatted(.interval.hour().minute())
    }

    static func progress(of programme: Programme, at date: Date) -> Double {
        let length = programme.stop.timeIntervalSince(programme.start)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(programme.start) / length, 0), 1)
    }
}

/// How far behind live, and how much is buffered (D7).
private struct TimeshiftBarView: View {
    let timeshift: Timeshift?
    let isPaused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let playhead = playheadFraction
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.tileFill)
                    Capsule().fill(Theme.focusHighlight)
                        .frame(width: width)
                    Capsule().fill(Theme.primaryText)
                        .frame(width: max(Theme.liveBarHeight, width * playhead))
                }
            }
            .frame(height: Theme.liveBarHeight)
            HStack(spacing: 16) {
                if isPaused {
                    Image(systemName: "pause.fill")
                }
                Text(timeshift?.label ?? "LIVE")
                    .monospacedDigit()
                Spacer()
                Text("Left/Right: 10 s · Rewind/FF: 30 s · Play/Pause")
                    .foregroundStyle(Theme.secondaryText)
            }
            .font(Theme.liveBannerDetailFont)
            .foregroundStyle(Theme.primaryText)
        }
    }

    /// The playhead within the buffered range; the whole track is the buffer.
    private var playheadFraction: Double {
        guard let timeshift, timeshift.buffered > 0 else { return 1 }
        return min(max((timeshift.position - timeshift.rangeStart) / timeshift.buffered, 0), 1)
    }
}
