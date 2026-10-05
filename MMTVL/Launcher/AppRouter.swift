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
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppRouter")

    private(set) var screen: Screen = .home
    let items: [LaunchItem]
    /// Kept while a placeholder is shown, so Back restores the previous focus position.
    private(set) var focus: LauncherFocusModel
    private(set) var shakeTriggers: [LaunchItem.ID: Int] = [:]

    @ObservationIgnored let launcher: AppLauncher
    @ObservationIgnored var onExitToDesktop: (() -> Void)?

    init(items: [LaunchItem], launcher: AppLauncher) {
        self.items = items
        self.launcher = launcher
        focus = LauncherFocusModel(itemCount: items.count, perRow: Theme.tilesPerRow)
    }

    /// Returns true if the command was consumed.
    func handle(_ command: RemoteCommand) -> Bool {
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
            case .playPause:
                return false
            }

        case .placeholder:
            switch command {
            case .back, .home:
                screen = .home
                return true
            case .up, .down, .left, .right, .select, .playPause:
                return false
            }
        }
    }

    func hover(_ index: Int) {
        guard screen == .home else { return }
        withAnimation(Theme.focusAnimation) { _ = focus.focus(index: index) }
    }

    func activate(_ index: Int) {
        guard items.indices.contains(index) else { return }
        focus.focus(index: index)
        let item = items[index]

        switch item.kind {
        case .application, .url:
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
                items: router.items,
                focus: router.focus,
                launcher: router.launcher,
                shakeTriggers: router.shakeTriggers,
                onHover: router.hover,
                onActivate: router.activate
            )
        case .placeholder(let item):
            PlaceholderView(item: item)
        }
    }
}
