import AppKit
import SwiftUI
import os

/// Owns the launcher window (D1): a borderless window covering the menu-bar screen,
/// with the Dock and menu bar hidden while the launcher is active.
final class KioskWindowController {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "KioskWindowController")
    private static let kioskOptions: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar]

    let window: NSWindow
    private let windowed: Bool
    private var screenObserver: NSObjectProtocol?

    init(rootView: some View, windowed: Bool = AppEnvironment.windowedMode) {
        self.windowed = windowed
        if windowed {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MMTVL"
            window.center()
        } else {
            window = KioskWindow(
                contentRect: Self.kioskFrame(),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .normal
            window.collectionBehavior = [.fullScreenNone]
        }
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView
        window.initialFirstResponder = hostingView

        if !windowed {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refit() }
            }
        }
    }

    /// The menu-bar screen's full frame (not `visibleFrame`), so the window covers the Dock and menu-bar strip.
    private static func kioskFrame() -> NSRect {
        (NSScreen.screens.first ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func refit() {
        let frame = Self.kioskFrame()
        Self.logger.info("Screen parameters changed; refitting to \(frame.debugDescription, privacy: .public)")
        window.setFrame(frame, display: true)
    }

    func show() {
        if !windowed {
            refit()
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        NSApp.activate()
        applyPresentationOptions()
    }

    func exitToDesktop() {
        if !windowed {
            NSApp.presentationOptions = []
        }
        window.orderOut(nil)
        NSApp.hide(nil)
    }

    /// Set after the window is shown; `.hideMenuBar` must always be paired with `.hideDock`.
    func applyPresentationOptions() {
        guard !windowed else { return }
        NSApp.presentationOptions = Self.kioskOptions
    }
}
