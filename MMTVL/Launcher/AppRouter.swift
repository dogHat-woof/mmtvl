import Observation
import SwiftUI
import os

/// M7 L2: bumped on every home arrow that moved focus and on Select; the focused tile reacts (parallax nudge, press).
struct FocusMotion: Equatable {
    var direction: RemoteCommand?
    var generation = 0
}

/// The current launcher screen. Receives every `RemoteCommand` from `InputRouter`
/// and dispatches it to the active screen.
@Observable
final class AppRouter {
    enum Screen: Equatable {
        case home
        case accessibilityOnboarding
        case settings
        case youtube
        case liveTV
        case pin(PINPurpose)
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
    /// L2. Hover moves don't bump it.
    private(set) var focusMotion = FocusMotion()
    /// M7 L12: nil = the tiles have focus; else the focused card of the focused tile's shelf.
    private(set) var shelfIndex: Int?
    /// D20: read at init, on going home and after PIN flows, not on every render.
    private var hasPINCache = false
    /// The PIN screen's model while `screen` is `.pin`.
    private(set) var pinEntry: PINEntryModel?

    @ObservationIgnored let launcher: AppLauncher
    /// M7 L3: custom tile pictures.
    let tileArt: TileArtStore
    let settings: SettingsModel
    @ObservationIgnored let youtube: any YouTubeHosting
    @ObservationIgnored let liveTV: any LiveTVHosting
    @ObservationIgnored let topShelf: any TopShelfProviding
    /// M7 step 12: card images fetched with headers (Plex).
    @ObservationIgnored let shelfImages = ShelfImageLoader()
    @ObservationIgnored private let pinStore: PINStore
    /// Kept across PIN screens, so cancelling doesn't reset the lockout (L10).
    @ObservationIgnored private var pinLockout = PINLockout()
    /// Where cancelling the PIN screen returns: .home or .settings.
    @ObservationIgnored private var screenBeforePIN: Screen = .home
    /// L8: hover only moves focus after the pointer moved since the last consumed command.
    @ObservationIgnored private var pointerLocationAtLastCommand: NSPoint?
    /// L21: scroll distance not yet turned into a row move, and when it last changed.
    @ObservationIgnored private var scrollAccumulator: CGFloat = 0
    @ObservationIgnored private var lastScrollAt: Date?
    /// Injectable clock (tests).
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var onExitToDesktop: (() -> Void)?
    @ObservationIgnored var onRequestAccessibility: (() -> Void)?

    init(items: [LaunchItem], launcher: AppLauncher, settings: SettingsModel, youtube: any YouTubeHosting,
         liveTV: any LiveTVHosting, pinStore: PINStore, tileArt: TileArtStore,
         topShelf: any TopShelfProviding = NoTopShelf()) {
        self.items = items
        self.launcher = launcher
        self.settings = settings
        self.youtube = youtube
        self.liveTV = liveTV
        self.pinStore = pinStore
        self.tileArt = tileArt
        self.topShelf = topShelf
        let visibleItems = items.visible
        self.visibleItems = visibleItems
        focus = LauncherFocusModel(itemCount: visibleItems.count, perRow: Theme.tilesPerRow)
        hasPINCache = pinStore.load() != nil
        // M7 L18: a web app whose window never showed shakes its tile.
        launcher.onLaunchFailed = { [weak self] id in self?.shakeTriggers[id, default: 0] += 1 }
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
        shelfContentChanged()
    }

    // MARK: Top shelf (M7 D28, L12)

    /// The focused tile, if any.
    var focusedItem: LaunchItem? {
        focus.index.flatMap { visibleItems.indices.contains($0) ? visibleItems[$0] : nil }
    }

    /// The focused tile's shelf. PIN-protected tiles only get a banner.
    var shelfContent: ShelfContent {
        guard let item = focusedItem else { return .banner }
        if item.isPINProtected && hasPINCache { return .banner }
        return topShelf.content(for: item)
    }

    /// Call when the shelf's content may have changed: clamps the card focus, or returns to the tile.
    func shelfContentChanged() {
        guard let index = shelfIndex else { return }
        let count = shelfContent.cards.count
        shelfIndex = count == 0 ? nil : min(index, count - 1)
    }

    /// Mouse hover over a card (with the pointer-moved rule, M1 L8).
    func hoverShelfCard(_ index: Int) {
        guard screen == .home, pointerMovedSinceLastCommand, shelfContent.cards.indices.contains(index) else { return }
        shelfIndex = index
    }

    /// Select on a card, or a click.
    func activateShelfCard(_ index: Int) {
        let cards = shelfContent.cards
        guard screen == .home, cards.indices.contains(index) else { return }
        shelfIndex = nil
        switch cards[index].action {
        case .playChannel(let id):
            openLiveTV(channelID: id)
        case .openTile(let id):
            guard let tileIndex = visibleItems.firstIndex(where: { $0.id == id }) else { return }
            activate(tileIndex)
        }
    }

    private func routeShelf(_ command: RemoteCommand, index: Int) -> Bool {
        switch command {
        case .left, .right:
            let count = shelfContent.cards.count
            let new = min(max(index + (command == .left ? -1 : 1), 0), count - 1)
            if new != index {
                shelfIndex = new
                bumpFocusMotion(command)
            }
            return true
        case .down, .back, .home:
            shelfIndex = nil
            bumpFocusMotion(.down)
            return true
        case .select:
            bumpFocusMotion(.select)
            activateShelfCard(index)
            return true
        case .up:
            return true
        case .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown:
            return false
        }
    }

    /// Returns true if the command was consumed.
    func handle(_ command: RemoteCommand) -> Bool {
        if command == .home { launcher.homePressed() }
        let consumed = route(command)
        if consumed {
            pointerLocationAtLastCommand = NSEvent.mouseLocation
        }
        return consumed
    }

    private func route(_ command: RemoteCommand) -> Bool {
        switch screen {
        case .home:
            shelfContentChanged()
            if let shelfIndex { return routeShelf(command, index: shelfIndex) }
            switch command {
            case .up where focus.position.row == 0 && !shelfContent.cards.isEmpty:
                // L12: Up from the first row enters the shelf.
                shelfIndex = 0
                bumpFocusMotion(.up)
                return true
            case .up, .down, .left, .right:
                var moved = false
                withAnimation(Theme.focusAnimation) { moved = focus.move(command) }
                if moved {
                    bumpFocusMotion(command)
                    topShelf.refresh(focusing: focusedItem)
                }
                return true
            case .select:
                if let index = focus.index {
                    bumpFocusMotion(.select)
                    activate(index)
                }
                return true
            case .back, .home:
                return true
            case .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown:
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
            case .up, .down, .left, .right, .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown:
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

        case .youtube:
            // L2: Home always leaves; everything else goes to leanback.
            if command == .home {
                goHome()
            } else {
                youtube.send(command)
            }
            return true

        case .liveTV:
            if command == .home {
                goHome()
                return true
            }
            switch liveTV.handle(command) {
            case .handled:
                break
            case .leave:
                goHome()
            case .openSettings:
                // Live TV isn't set up: Select opens Settings (PIN-guarded like the tile).
                liveTV.leave()
                if hasPIN {
                    requestPIN(.openSettings)
                } else {
                    openSettings()
                }
            }
            return true

        case .pin:
            if command == .home {
                goHome()
            } else if let result = pinEntry?.handle(command) {
                finishPIN(result)
            }
            return true
        }
    }

    private func bumpFocusMotion(_ direction: RemoteCommand) {
        focusMotion = FocusMotion(direction: direction, generation: focusMotion.generation + 1)
    }

    /// Shows the home screen, keeping the focus position. Leaving YouTube pauses it (L3); leaving Live TV stops it (M4 L7).
    func goHome() {
        if screen == .youtube {
            youtube.pause()
        }
        if screen == .liveTV {
            liveTV.leave()
        }
        closePINEntry()
        if screen == .settings { settings.screenDidClose() }
        screen = .home
        hasPINCache = hasPIN
        tileArt.reloadIfChanged()
        topShelf.refresh(focusing: focusedItem)
        shelfContentChanged()
    }

    var hasPIN: Bool { pinStore.load() != nil }

    /// Shows the PIN screen; cancelling returns to the current screen (home or Settings).
    func requestPIN(_ purpose: PINPurpose) {
        screenBeforePIN = screen == .settings ? .settings : .home
        pinEntry = PINEntryModel(purpose: purpose, storedPIN: pinStore.load(), lockout: pinLockout)
        screen = .pin(purpose)
    }

    /// Mouse click on the PIN screen's keypad.
    func pinEnter(row: Int, column: Int) {
        guard let result = pinEntry?.enter(row: row, column: column) else { return }
        finishPIN(result)
    }

    private func finishPIN(_ result: PINEntryModel.Result) {
        guard let purpose = pinEntry?.purpose else { return }
        closePINEntry()
        defer { hasPINCache = hasPIN }
        switch result {
        case .cancelled:
            screen = screenBeforePIN
        case .verified:
            switch purpose {
            case .openSettings:
                openSettings()
            case .openTile(let id):
                screen = .home
                if let item = visibleItems.first(where: { $0.id == id }) { open(item) }
            case .exitToDesktop:
                screen = .home
                onExitToDesktop?()
            case .setNew, .change, .turnOff:
                screen = screenBeforePIN
            }
        case .newPIN(let pin):
            do {
                try pinStore.save(pin)
            } catch {
                Self.logger.error("Failed to save the PIN: \(error.localizedDescription, privacy: .public)")
            }
            returnToSettings()
        case .removed:
            do {
                try pinStore.remove()
            } catch {
                Self.logger.error("Failed to remove the PIN: \(error.localizedDescription, privacy: .public)")
            }
            returnToSettings()
        }
    }

    /// Back to the same Settings page (not `openSettings()`, which resets the page stack).
    private func returnToSettings() {
        screen = .settings
        settings.refreshStatus()
    }

    /// Keeps the lockout for the next PIN screen.
    private func closePINEntry() {
        if let pinEntry { pinLockout = pinEntry.lockout }
        pinEntry = nil
    }

    func openYouTube() {
        youtube.open()
        screen = .youtube
    }

    /// M7b L4: a YouTube cast takes over the TV from any screen. No PIN, even for a protected YouTube tile
    /// (user choice). nil query = keep the page (leanback already paired).
    func castYouTube(query: String?) {
        if screen != .youtube { goHome() }
        if let query {
            youtube.launch(query: query)
        } else {
            youtube.open()
        }
        screen = .youtube
    }

    /// nil = the last channel or Multiview; else that channel full screen (a top shelf card, M7 L13).
    func openLiveTV(channelID: Channel.ID? = nil) {
        liveTV.open(channelID: channelID)
        screen = .liveTV
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
        shelfIndex = nil
        var moved = false
        withAnimation(Theme.focusAnimation) { moved = focus.focus(index: index) }
        if moved { topShelf.refresh(focusing: focusedItem) }
    }

    /// L21: the mouse wheel moves home focus one row per `Theme.homeScrollStep` points (trackpad) or per line (wheel).
    /// Positive deltas (content moves down) move focus up. Other screens ignore it.
    func scrollWheel(deltaY: CGFloat, precise: Bool) {
        guard screen == .home, deltaY != 0 else { return }
        let time = now()
        if let lastScrollAt, time.timeIntervalSince(lastScrollAt) > 0.3 { scrollAccumulator = 0 }
        lastScrollAt = time
        // A direction change starts over.
        if scrollAccumulator != 0 && (scrollAccumulator > 0) != (deltaY > 0) { scrollAccumulator = 0 }
        scrollAccumulator += deltaY
        let step = precise ? Theme.homeScrollStep : 1
        while abs(scrollAccumulator) >= step {
            let up = scrollAccumulator > 0
            scrollAccumulator -= up ? step : -step
            _ = handle(up ? .up : .down)
        }
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

        if item.isPINProtected && hasPIN {
            if item.isSettingsTile {
                requestPIN(.openSettings)
            } else if item.isExitToDesktop {
                requestPIN(.exitToDesktop)
            } else {
                requestPIN(.openTile(id: item.id))
            }
            return
        }
        open(item)
    }

    /// Opens a tile without asking for the PIN (already checked or not needed).
    private func open(_ item: LaunchItem) {
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
        case .internalDestination(.youtube):
            openYouTube()
        case .internalDestination(.iptv):
            openLiveTV()
        case .system(.exitToDesktop):
            onExitToDesktop?()
        }
    }
}

/// Lays the active screen out on the 1920×1080 canvas and scales it to the window.
struct LauncherRootView: View {
    let router: AppRouter
    let youtube: YouTubeController
    let liveTV: LiveTVModel

    var body: some View {
        if router.screen == .youtube {
            // L4: outside the scaled canvas, at the window's real size.
            YouTubeView(controller: youtube)
        } else if router.screen == .liveTV {
            // M4 L16: the video sits outside the scaled canvas; overlays are scaled inside LiveTVRootView.
            LiveTVRootView(model: liveTV)
        } else {
            GeometryReader { geometry in
                content
                    .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
                    .scaleEffect(Theme.scale(for: geometry.size))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(Theme.backgroundGradient)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.screen {
        case .home:
            HomeView(
                items: router.visibleItems,
                focus: router.focus,
                launcher: router.launcher,
                tileArt: router.tileArt,
                shakeTriggers: router.shakeTriggers,
                focusMotion: router.focusMotion,
                shelf: router.shelfContent,
                shelfIndex: router.shelfIndex,
                onHoverCard: router.hoverShelfCard,
                onActivateCard: router.activateShelfCard,
                onRefreshShelf: { router.topShelf.refresh(focusing: router.focusedItem) },
                shelfImages: router.shelfImages,
                onHover: router.hover,
                onActivate: router.activate
            )
        case .accessibilityOnboarding:
            AccessibilityOnboardingView(
                onOpenSettings: { router.onRequestAccessibility?() },
                onNotNow: router.goHome
            )
        case .settings:
            SettingsView(
                model: router.settings,
                launcher: router.launcher,
                tileArt: router.tileArt,
                onHoverRow: router.hoverSettingsRow,
                onActivateRow: router.settings.activate
            )
        case .youtube, .liveTV:
            // Shown by `body` outside the canvas.
            EmptyView()
        case .pin:
            if let pinEntry = router.pinEntry {
                PINEntryView(model: pinEntry, onEnter: router.pinEnter)
            }
        }
    }
}
