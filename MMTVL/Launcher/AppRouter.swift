import Observation
import SwiftUI
import os

/// The current launcher screen. Receives every `RemoteCommand` from `InputRouter`
/// and dispatches it to the active screen.
@Observable
final class AppRouter {
    enum Screen: Equatable {
        case home
        case placeholder(LaunchItem)
        case accessibilityOnboarding
        case settings
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppRouter")

    private(set) var screen: Screen = .home
    /// All tiles in stored order, hidden ones included.
    private(set) var items: [LaunchItem]
    /// The tiles shown on the home screen; `focus` and `activate(_:)` index into these.
    private(set) var visibleItems: [LaunchItem]
    /// Kept while another screen is shown, so Back restores the previous focus position.
    private(set) var focus: LauncherFocusModel
    private(set) var shakeTriggers: [LaunchItem.ID: Int] = [:]

    @ObservationIgnored let launcher: AppLauncher
    let settings: SettingsModel
    /// L8: hover only moves focus after the pointer moved since the last consumed command.
    @ObservationIgnored private var pointerLocationAtLastCommand: NSPoint?
    @ObservationIgnored var onExitToDesktop: (() -> Void)?
    @ObservationIgnored var onRequestAccessibility: (() -> Void)?

    init(items: [LaunchItem], launcher: AppLauncher, settings: SettingsModel) {
        self.items = items
        self.launcher = launcher
        self.settings = settings
        let visibleItems = items.visible
        self.visibleItems = visibleItems
        focus = LauncherFocusModel(itemCount: visibleItems.count, perRow: Theme.tilesPerRow)
    }

    /// Replaces the tiles (Settings edits), keeping focus on the same tile where possible.
    func setItems(_ newItems: [LaunchItem]) {
        let oldIndex = focus.index
        let focusedID = oldIndex.map { visibleItems[$0].id }

        items = newItems
        visibleItems = newItems.visible
        var newFocus = LauncherFocusModel(itemCount: visibleItems.count, perRow: Theme.tilesPerRow)
        if let focusedID, let index = visibleItems.firstIndex(where: { $0.id == focusedID }) {
            newFocus.focus(index: index)
        } else if let oldIndex, !visibleItems.isEmpty {
            newFocus.focus(index: min(oldIndex, visibleItems.count - 1))
        }
        focus = newFocus
    }

    /// Returns true if the command was consumed.
    func handle(_ command: RemoteCommand) -> Bool {
        let consumed = route(command)
        if consumed {
            pointerLocationAtLastCommand = NSEvent.mouseLocation
        }
        return consumed
    }

    private func route(_ command: RemoteCommand) -> Bool {
        switch screen {
        case .home:
            switch command {
            case .up, .down, .left, .right:
                withAnimation(Theme.focusAnimation) { _ = focus.move(command) }
                return true
            case .select:
                if let index = focus.index { activate(index) }
                return true
            case .back, .home:
                return true
            case .playPause, .fastForward, .rewind:
                return false
            }

        case .placeholder:
            switch command {
            case .back, .home:
                goHome()
                return true
            case .up, .down, .left, .right, .select, .playPause, .fastForward, .rewind:
                return false
            }

        case .accessibilityOnboarding:
            switch command {
            case .select:
                onRequestAccessibility?()
                return true
            case .back, .home:
                goHome()
                return true
            case .up, .down, .left, .right, .playPause, .fastForward, .rewind:
                return false
            }

        case .settings:
            if command == .home {
                goHome()
                return true
            }
            if settings.handle(command) { return true }
            if command == .back {
                // Back on the root page.
                goHome()
                return true
            }
            return false
        }
    }

    /// Shows the home screen, keeping the focus position.
    func goHome() {
        screen = .home
    }

    func showAccessibilityOnboarding() {
        screen = .accessibilityOnboarding
    }

    func openSettings() {
        settings.reset()
        screen = .settings
    }

    private var pointerMovedSinceLastCommand: Bool {
        NSEvent.mouseLocation != pointerLocationAtLastCommand
    }

    func hover(_ index: Int) {
        guard screen == .home, pointerMovedSinceLastCommand else { return }
        withAnimation(Theme.focusAnimation) { _ = focus.focus(index: index) }
    }

    func hoverSettingsRow(_ id: String) {
        guard screen == .settings, pointerMovedSinceLastCommand else { return }
        settings.focus(rowID: id)
    }

    /// `index` is into `visibleItems`.
    func activate(_ index: Int) {
        guard visibleItems.indices.contains(index) else { return }
        focus.focus(index: index)
        let item = visibleItems[index]

        switch item.kind {
        case .application, .url, .defaultBrowser:
            guard launcher.isInstalled(item) else {
                // L6: not-installed tiles only shake.
                shakeTriggers[item.id, default: 0] += 1
                return
            }
            Task {
                do {
                    try await launcher.launch(item)
                } catch {
                    Self.logger.error("Failed to launch \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    shakeTriggers[item.id, default: 0] += 1
                }
            }
        case .internalDestination(.settings):
            openSettings()
        case .internalDestination:
            screen = .placeholder(item)
        case .system(.exitToDesktop):
            onExitToDesktop?()
        }
    }
}

/// Lays the active screen out on the 1920×1080 canvas and scales it to the window.
struct LauncherRootView: View {
    let router: AppRouter

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
                .scaleEffect(Theme.scale(for: geometry.size))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Theme.backgroundGradient)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch router.screen {
        case .home:
            HomeView(
                items: router.visibleItems,
                focus: router.focus,
                launcher: router.launcher,
                shakeTriggers: router.shakeTriggers,
                onHover: router.hover,
                onActivate: router.activate
            )
        case .placeholder(let item):
            PlaceholderView(item: item)
        case .accessibilityOnboarding:
            AccessibilityOnboardingView(
                onOpenSettings: { router.onRequestAccessibility?() },
                onNotNow: router.goHome
            )
        case .settings:
            SettingsView(
                model: router.settings,
                launcher: router.launcher,
                onHoverRow: router.hoverSettingsRow,
                onActivateRow: router.settings.activate
            )
        }
    }
}
