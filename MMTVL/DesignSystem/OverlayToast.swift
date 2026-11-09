import AppKit
import SwiftUI
import os

/// M7h L8: a short message in a glass capsule, top-centre of the main screen, over any app ("Trackpad On",
/// "Volume −20 dB", "Receiver isn't answering"). It shows for `Theme.toastDuration`, then fades; a new message
/// replaces the one showing and restarts the timer. The panel never becomes key or main, never activates MMTVL
/// and lets clicks through, so the app in front keeps its focus.
final class OverlayToast {
    static let shared = OverlayToast()

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Toast")

    private var state = ToastState()
    private let content = OverlayToastContent()
    private var panel: OverlayToastPanel?
    private var timer: Task<Void, Never>?

    /// The message showing (nil once it has started to fade).
    var message: ToastState.Message? { state.message }

    func show(_ text: String, symbol: String) {
        let generation = state.show(ToastState.Message(text: text, symbol: symbol))
        Self.logger.info("Toast \(text, privacy: .public)")
        // Tests host the app: keep the state, never put a window on the screen.
        guard !AppEnvironment.isRunningTests else { return }

        let panel = panel ?? makePanel()
        self.panel = panel
        if panel.isVisible {
            withAnimation(Theme.toastContentAnimation) {
                content.text = text
                content.symbol = symbol
            }
        } else {
            content.text = text
            content.symbol = symbol
            panel.alphaValue = 0
        }
        place(panel)
        panel.orderFrontRegardless()   // shown without activating MMTVL
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.toastFadeInSeconds
            panel.animator().alphaValue = 1
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])

        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: Theme.toastDuration)
            guard !Task.isCancelled else { return }
            self?.expire(generation)
        }
    }

    private func expire(_ generation: Int) {
        guard state.expire(generation), let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.toastFadeOutSeconds
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // AppKit calls this on the main thread. A message shown during the fade keeps the panel up.
            MainActor.assumeIsolated {
                guard let self, self.state.message == nil else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func makePanel() -> OverlayToastPanel {
        let panel = OverlayToastPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // the capsule draws its own
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: OverlayToastView(content: content))
        hostingView.sizingOptions = []   // the panel's size is set in `place`, never by SwiftUI
        panel.contentView = hostingView
        return panel
    }

    /// A band across the top of the main screen, `Theme.toastBandHeight` canvas points tall at the screen's scale.
    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let height = (Theme.toastBandHeight * Theme.scale(for: frame.size)).rounded(.up)
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
    }
}

/// Which message shows, and which timer may hide it: a newer message invalidates the older timers.
nonisolated struct ToastState: Equatable {
    struct Message: Equatable {
        let text: String
        let symbol: String
    }

    private(set) var message: Message?
    private(set) var generation = 0

    /// Shows `message` (replacing any) and returns the generation its timer must present to `expire`.
    mutating func show(_ message: Message) -> Int {
        self.message = message
        generation += 1
        return generation
    }

    /// The timer for `generation` ran out: true (and no message) unless a newer message replaced it.
    mutating func expire(_ generation: Int) -> Bool {
        guard generation == self.generation, message != nil else { return false }
        message = nil
        return true
    }
}

/// Never key or main: the app in front keeps the keyboard.
private final class OverlayToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What the capsule shows; kept through the fade-out.
@Observable
private final class OverlayToastContent {
    var text = ""
    var symbol = ""
}

/// The capsule on a canvas-wide band, scaled like the rest of the UI (`Theme.scale(for:)`).
private struct OverlayToastView: View {
    let content: OverlayToastContent

    var body: some View {
        GeometryReader { geometry in
            capsule
                .padding(.top, Theme.toastTop)
                .frame(width: Theme.canvasSize.width, height: Theme.toastBandHeight, alignment: .top)
                .scaleEffect(Theme.scale(for: geometry.size))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private var capsule: some View {
        HStack(spacing: Theme.toastSpacing) {
            Image(systemName: content.symbol)
                .font(Theme.toastSymbolFont)
                .contentTransition(.symbolEffect(.replace))
            Text(content.text)
                .font(Theme.toastFont)
                .contentTransition(.opacity)
        }
        .foregroundStyle(Theme.primaryText)
        .lineLimit(1)
        .padding(.horizontal, Theme.toastPadding.width)
        .padding(.vertical, Theme.toastPadding.height)
        .background(Theme.toastScrim, in: Capsule())
        .glassPanel(in: Capsule())
        .shadow(color: .black.opacity(Theme.toastShadowOpacity), radius: Theme.toastShadowRadius)
    }
}
