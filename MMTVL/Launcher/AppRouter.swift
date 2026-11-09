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

    private(set) var screen: Screen = .home {
        didSet { if screen != oldValue { updateLivePreview() } }
    }
    /// All tiles in stored order, hidden ones included.
    private(set) var items: [LaunchItem]
    /// The tiles shown on the home screen; `focus` and `activate(_:)` index into these.
    private(set) var visibleItems: [LaunchItem]
    /// Kept while another screen is shown, so Back restores the previous focus position.
    private(set) var focus: LauncherFocusModel {
        didSet {
            guard focus.index != oldValue.index else { return }
            // M7c L25: a failed preview tries again when Live TV gets focus.
            if liveTV.previewFailed, isLiveTVFocused { liveTV.stopPreview() }
            updateLivePreview()
        }
    }
    private(set) var shakeTriggers: [LaunchItem.ID: Int] = [:]
    /// L2. Hover moves don't bump it.
    private(set) var focusMotion = FocusMotion()
    /// M7 L12: nil = the tiles have focus; else the focused card of the focused tile's shelf.
    private(set) var shelfIndex: Int? {
        didSet { if shelfIndex != oldValue { updateLivePreview() } }
    }
    /// M7c L14: the carousel's page while the tiles have focus (auto-advances); 0 when the focused tile changes.
    private(set) var carouselPage = 0
    /// The tile `carouselPage` belongs to.
    @ObservationIgnored private var carouselTileID: LaunchItem.ID?
    @ObservationIgnored private var carouselTask: Task<Void, Never>?
    /// Injectable (tests advance by hand with `advanceCarousel()`).
    @ObservationIgnored var carouselInterval: Duration = Theme.carouselInterval
    /// M7c L28: "Version 1.1.0 Build 2" under the home clock; nil = hidden. Set live by AppDelegate.
    var homeVersionLabel: String?
    /// M7f L8: the lowest Siri Remote battery percent beside the home clock; nil = hidden. Set by AppDelegate.
    var remoteBatteryLevel: Int?
    /// M7f L8: AppDelegate reads the battery again (the home screen appeared or its minute ticked).
    @ObservationIgnored var onRefreshRemoteBattery: (() -> Void)?
    /// M7c L15: `settings.json` `homeLivePreview`, set live by AppDelegate.
    @ObservationIgnored var livePreviewEnabled = true {
        didSet { if livePreviewEnabled != oldValue { updateLivePreview() } }
    }
    /// L16: MMTVL is the active app (AppDelegate, from didBecomeActive/didResignActive).
    @ObservationIgnored var isAppActive = true {
        didSet {
            guard isAppActive != oldValue else { return }
            updateLivePreview()
            if isAppActive {
                homeEntryGeneration += 1
            } else if isLeavingHome {
                // L23: the launched app took the screen; the home UI is back for the return.
                finishLeavingHome(animated: false)
            }
        }
    }
    /// M7c L22, L23: the home UI animates away before Live TV or Plex opens. Commands wait (Home cancels).
    private(set) var isLeavingHome = false
    /// Bumped when the home screen comes back (MMTVL active again); the dock slides up.
    private(set) var homeEntryGeneration = 0
    /// Injectable: 0 (no animation) by default and in tests; AppDelegate sets `Theme.homeExitDuration`.
    @ObservationIgnored var homeExitDelay: Duration = .zero
    @ObservationIgnored private(set) var homeExitTask: Task<Void, Never>?
    /// Injectable; tests use zero.
    @ObservationIgnored var previewDelay: Duration = Theme.previewDelay
    @ObservationIgnored var previewIdleTimeout: Duration = Theme.previewIdleTimeout
    /// L16: no input for `previewIdleTimeout`, or the displays slept.
    @ObservationIgnored private(set) var isIdle = false
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledPreviewID: Channel.ID?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
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
    /// M7c L9: quits MMTVL for real (after the PIN, if one is set).
    @ObservationIgnored var onQuit: (() -> Void)?
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
        syncCarousel()
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

    /// M7c L32: `settings.json` `homeStartTile`, set live by AppDelegate.
    @ObservationIgnored var startTileID = "plex"

    /// M7c L32: Home (any remote, the keyboard, the phone, from any screen or app) shows the home screen on the
    /// start tile; so does Back when it reaches the home screen (user request 2026-10-10).
    func goHomeToStartTile() {
        goHome()
        withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
    }

    /// M7c L32: at launch and on Home, the home screen opens on `id` (else the first tile), out of the top shelf, so
    /// the dock row shows with the next row peeking.
    func focusStartTile(id: String) {
        var newFocus = LauncherFocusModel(itemCount: visibleItems.count, perRow: Theme.tilesPerRow)
        if let index = visibleItems.firstIndex(where: { $0.id == id }) {
            newFocus.focus(index: index)
        }
        focus = newFocus
        shelfIndex = nil
        // L8: a pointer resting where the home screen appears mustn't take the focus; only a real move does.
        pointerLocationAtLastCommand = NSEvent.mouseLocation
        topShelf.refresh(focusing: focusedItem)
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
        defer { updateLivePreview() }
        syncCarousel()
        guard let index = shelfIndex else { return }
        let count = shelfContent.cards.count
        shelfIndex = count == 0 ? nil : min(index, count - 1)
    }

    // MARK: Live TV preview (M7c L15, L16, D37)

    /// The channel the home screen should preview now, or nil.
    /// M7c L25: it preloads with any tile focused while the Live TV tile is on the home screen.
    var wantedPreviewChannelID: Channel.ID? {
        guard screen == .home, livePreviewEnabled, isAppActive, !isIdle,
              let liveItem = visibleItems.first(where: { $0.kind == .internalDestination(.iptv) }),
              !(liveItem.isPINProtected && hasPINCache)
        else { return nil }
        guard isLiveTVFocused else {
            // Another tile: whatever plays keeps playing (no reconnect), else the default channel.
            return liveTV.previewChannelID ?? liveTV.defaultPreviewChannelID
        }
        // M7c L21: the focused page (or card); Down/Back keep the page, so its channel keeps playing.
        let content = shelfContent
        if let index = shelfIndex ?? (content.isCarousel ? carouselPage : nil) {
            let cards = content.cards
            if cards.indices.contains(index), case .playChannel(let id) = cards[index].action { return id }
        }
        return liveTV.defaultPreviewChannelID
    }

    private var isLiveTVFocused: Bool {
        focusedItem?.kind == .internalDestination(.iptv)
    }

    /// Whether the preview's video shows through the backdrop (the Live TV tile focused and its preview playing).
    var revealsLivePreview: Bool {
        screen == .home && isLiveTVFocused && liveTV.isPreviewPlaying
    }

    /// M7c L25: the preview's video is drawn only while the Live TV tile has focus (other tiles' art and crossfades
    /// never show it).
    var showsLivePreviewVideo: Bool {
        screen == .home && isLiveTVFocused
    }

    /// Starts (after `previewDelay`), switches or stops the preview. Called on every focus, shelf, screen,
    /// setting and activity change.
    func updateLivePreview() {
        // Live TV owns the player while it's open (an adopted preview keeps playing).
        if screen == .liveTV {
            cancelScheduledPreview()
            return
        }
        guard let wanted = wantedPreviewChannelID else {
            cancelScheduledPreview()
            if liveTV.previewChannelID != nil || liveTV.previewFailed { liveTV.stopPreview() }
            return
        }
        if idleTask == nil { restartIdleTimer() }
        if wanted == liveTV.previewChannelID || liveTV.previewFailed {
            cancelScheduledPreview()
            return
        }
        guard scheduledPreviewID != wanted else { return }
        cancelScheduledPreview()
        guard previewDelay > .zero else {
            liveTV.startPreview(channelID: wanted)
            return
        }
        scheduledPreviewID = wanted
        let delay = previewDelay
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, scheduledPreviewID == wanted else { return }
            scheduledPreviewID = nil
            if wantedPreviewChannelID == wanted { liveTV.startPreview(channelID: wanted) }
        }
    }

    /// M7f L5: the playlist was re-fetched (`IPTVLibrary.onLineupChange`). A preview whose channel left it stops, and
    /// the default channel (else the first favorite) takes over; the Live TV pages reload around it.
    func playlistDidChange() {
        liveTV.playlistDidChange()
        if screen == .home { topShelf.refresh(focusing: focusedItem) }
        updateLivePreview()
    }

    private func cancelScheduledPreview() {
        previewTask?.cancel()
        previewTask = nil
        scheduledPreviewID = nil
    }

    /// L16: any remote command (`InputRouter.onCommandDispatched`).
    func noteActivity() {
        restartIdleTimer()
        if isIdle {
            isIdle = false
            updateLivePreview()
        }
    }

    /// L16: the displays or the system went to sleep. The next command restarts the preview.
    func screensDidSleep() {
        idleTask?.cancel()
        idleTask = nil
        isIdle = true
        updateLivePreview()
    }

    /// M7c L26: no stream while the screen saver runs.
    func screenSaverDidStart() {
        screensDidSleep()
    }

    /// M7c L26: counts as activity, so the preview can start again.
    func screenSaverDidStop() {
        noteActivity()
    }

    private func restartIdleTimer() {
        idleTask?.cancel()
        let timeout = previewIdleTimeout
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            idleTask = nil
            isIdle = true
            updateLivePreview()
        }
    }

    // MARK: Leaving home (M7c L22, L23)

    /// Animates the home UI away, then runs `open`. With `untilInactive` (an app launch) the UI stays away until
    /// MMTVL resigns active, or comes back after `Theme.homeExitAppFallback`.
    private func leaveHome(untilInactive: Bool = false, _ open: @escaping () -> Void) {
        guard homeExitDelay > .zero else {
            open()
            return
        }
        homeExitTask?.cancel()
        withAnimation(Theme.homeExitAnimation) { isLeavingHome = true }
        let delay = homeExitDelay
        homeExitTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, isLeavingHome else { return }
            open()
            guard untilInactive else {
                finishLeavingHome(animated: false)
                return
            }
            try? await Task.sleep(for: Theme.homeExitAppFallback)
            guard !Task.isCancelled, isLeavingHome else { return }
            finishLeavingHome(animated: true)
        }
    }

    private func finishLeavingHome(animated: Bool) {
        homeExitTask?.cancel()
        homeExitTask = nil
        if animated {
            withAnimation(Theme.homeReturnAnimation) { isLeavingHome = false }
        } else {
            isLeavingHome = false
        }
    }

    /// The Live TV page's channel when it isn't the first page (the first is what Live TV opens by itself).
    private var livePageChannelID: Channel.ID? {
        let content = shelfContent
        guard content.isCarousel, carouselPage > 0, content.cards.indices.contains(carouselPage),
              case .playChannel(let id) = content.cards[carouselPage].action
        else { return nil }
        return id
    }

    // MARK: Carousel (M7c L14)

    /// Resets the page when the focused tile changed, clamps it, and runs the auto-advance timer only while a carousel
    /// shows on the home screen.
    private func syncCarousel() {
        let content = shelfContent
        if focusedItem?.id != carouselTileID {
            carouselTileID = focusedItem?.id
            carouselPage = 0
            carouselTask?.cancel()
            carouselTask = nil
        }
        let count = content.cards.count
        if carouselPage >= count { carouselPage = max(count - 1, 0) }
        if screen == .home && content.autoAdvances && count > 1 {
            if carouselTask == nil { restartCarouselTimer() }
        } else {
            carouselTask?.cancel()
            carouselTask = nil
        }
    }

    /// Auto-advance starts over from the current page.
    private func restartCarouselTimer() {
        carouselTask?.cancel()
        let interval = carouselInterval
        carouselTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.advanceCarousel()
            }
        }
    }

    /// One auto-advance step (wraps). Not while the carousel itself has focus.
    func advanceCarousel() {
        let content = shelfContent
        guard screen == .home, content.autoAdvances, shelfIndex == nil, !content.cards.isEmpty else { return }
        withAnimation(Theme.carouselCrossfade) { carouselPage = (carouselPage + 1) % content.cards.count }
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
            leaveHome { [weak self] in self?.openLiveTV(channelID: id) }
        case .openTile(let id):
            guard let tileIndex = visibleItems.firstIndex(where: { $0.id == id }) else { return }
            let item = visibleItems[tileIndex]
            // The PIN screen comes first, without the animation.
            guard !(item.isPINProtected && hasPIN) else {
                activate(tileIndex)
                return
            }
            // M7c L23: a Plex page fades to its art, then the tile opens (an app keeps the UI away until it's up).
            let isApp = switch item.kind {
            case .application, .url, .defaultBrowser: true
            case .internalDestination, .system: false
            }
            leaveHome(untilInactive: isApp) { [weak self] in self?.activate(tileIndex) }
        }
    }

    private func routeShelf(_ command: RemoteCommand, index: Int) -> Bool {
        let content = shelfContent
        switch command {
        case .left where content.isCarousel, .right where content.isCarousel:
            // M7c L14: pages wrap around.
            let count = content.cards.count
            let new = (index + (command == .left ? -1 : 1) + count) % count
            withAnimation(Theme.carouselCrossfade) {
                shelfIndex = new
                carouselPage = new
            }
            bumpFocusMotion(command)
            return true
        case .left, .right:
            let count = content.cards.count
            let new = min(max(index + (command == .left ? -1 : 1), 0), count - 1)
            if new != index {
                shelfIndex = new
                bumpFocusMotion(command)
            }
            return true
        case .down, .back, .home:
            shelfIndex = nil
            bumpFocusMotion(.down)
            // M7c L14: auto-advance resumes from this page.
            if content.autoAdvances { restartCarouselTimer() }
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

    /// Returns true if the command was consumed. `isRepeat`: a held key's or button's auto-repeat (M7g: Settings
    /// changes page only on a fresh Left or Right).
    func handle(_ command: RemoteCommand, isRepeat: Bool = false) -> Bool {
        if command == .home { launcher.homePressed() }
        if isLeavingHome {
            // L22: commands wait for the animation; Home cancels it and stays home.
            if command == .home {
                finishLeavingHome(animated: true)
                withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
            }
            return true
        }
        let consumed = route(command, isRepeat: isRepeat)
        // M7c L32: every screen's Home lands on the home screen; then on the start tile.
        if command == .home && screen == .home {
            withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
        }
        if consumed {
            pointerLocationAtLastCommand = NSEvent.mouseLocation
        }
        return consumed
    }

    private func route(_ command: RemoteCommand, isRepeat: Bool) -> Bool {
        switch screen {
        case .home:
            shelfContentChanged()
            if let shelfIndex { return routeShelf(command, index: shelfIndex) }
            switch command {
            case .up where focus.position.row == 0 && !shelfContent.cards.isEmpty:
                // L12: Up from the first row enters the shelf; a carousel on its current page (M7c L14).
                shelfIndex = shelfContent.isCarousel ? carouselPage : 0
                bumpFocusMotion(.up)
                return true
            case .up, .down, .left, .right:
                var moved = false
                withAnimation(Theme.focusAnimation) { moved = focus.move(command) }
                if moved {
                    bumpFocusMotion(command)
                    topShelf.refresh(focusing: focusedItem)
                    syncCarousel()
                }
                return true
            case .select:
                if let index = focus.index {
                    bumpFocusMotion(.select)
                    activate(index)
                }
                return true
            case .back:
                // M7c L32: Back on the tiles goes to the start tile, like Home.
                withAnimation(Theme.focusAnimation) { focusStartTile(id: startTileID) }
                return true
            case .home:
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
                goHomeToStartTile()
                return true
            case .up, .down, .left, .right, .playPause, .fastForward, .rewind, .menu, .channelUp, .channelDown:
                return false
            }

        case .settings:
            if command == .home {
                goHome()
                return true
            }
            if settings.handle(command, isRepeat: isRepeat) { return true }
            if command == .back {
                // Back on the root page; M7c L32: on the start tile.
                goHomeToStartTile()
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
                // M7c L32: Back out of Live TV lands on the start tile, like Home.
                goHomeToStartTile()
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
        if isLeavingHome { finishLeavingHome(animated: false) }
        if screen == .youtube {
            youtube.pause()
        }
        if screen == .liveTV {
            // M7c L25: the channel keeps playing as the preview; `updateLivePreview` below stops it if unwanted.
            liveTV.leave(keepingPreview: livePreviewEnabled)
        }
        closePINEntry()
        if screen == .settings { settings.screenDidClose() }
        screen = .home
        hasPINCache = hasPIN
        tileArt.reloadIfChanged()
        topShelf.refresh(focusing: focusedItem)
        shelfContentChanged()
        updateLivePreview()
    }

    var hasPIN: Bool { pinStore.load() != nil }

    /// Shows the PIN screen; cancelling returns to the current screen (home or Settings).
    func requestPIN(_ purpose: PINPurpose) {
        screenBeforePIN = screen == .settings ? .settings : .home
        pinEntry = PINEntryModel(purpose: purpose, storedPIN: pinStore.load(), lockout: pinLockout)
        screen = .pin(purpose)
    }

    /// M7c L9: ⌘Q or the Dock's Quit while the kiosk lock is on: the PIN first, if one is set.
    func requestQuit() {
        if case .pin(.quit) = screen { return }
        if hasPIN {
            // The PIN screen can't sit over Live TV or YouTube (they'd keep playing); cancelling returns home.
            if screen != .home && screen != .settings { goHome() }
            requestPIN(.quit)
        } else {
            onQuit?()
        }
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
            case .quit:
                screen = screenBeforePIN
                onQuit?()
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
        if moved {
            topShelf.refresh(focusing: focusedItem)
            syncCarousel()
        }
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

    /// `page`: the page of the column the row is in; only the current page's rows take focus.
    func hoverSettingsRow(_ id: String, on page: SettingsPage) {
        guard screen == .settings, pointerMovedSinceLastCommand else { return }
        settings.focus(rowID: id, on: page)
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
            let launch = { [weak self] in
                Task {
                    do {
                        try await self?.launcher.launch(item)
                    } catch {
                        Self.logger.error("Failed to launch \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        self?.shakeTriggers[item.id, default: 0] += 1
                    }
                }
            }
            // M7c L23: the Plex tile (its carousel showing) fades to its art first; the UI stays away until the app
            // takes the screen.
            if !isLeavingHome && item.id == focusedItem?.id && shelfContent.isCarousel {
                leaveHome(untilInactive: true) { _ = launch() }
            } else {
                _ = launch()
            }
        case .internalDestination(.settings):
            openSettings()
        case .internalDestination(.youtube):
            openYouTube()
        case .internalDestination(.iptv):
            // M7c L21: a page other than the first keeps playing after Down; Select opens that channel.
            // L22: after the home UI animates away (the preview's video stays put).
            let channelID = livePageChannelID
            leaveHome { [weak self] in self?.openLiveTV(channelID: channelID) }
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
                ZStack {
                    // M7c L15: the Live TV preview's video, under the canvas at the window's size (as M4 L16).
                    if router.screen == .home, liveTV.previewChannelID != nil,
                       let view = (liveTV.player as? MPVPlayerController)?.videoView {
                        // M7c L25: kept in the window while it preloads (mpv needs the render context).
                        MPVVideoRepresentable(view: view)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .opacity(router.showsLivePreviewVideo ? homeFade : 0)
                            .animation(Theme.focusAnimation, value: homeFade)
                            .animation(Theme.shelfBackdropCrossfade, value: router.showsLivePreviewVideo)
                    }
                    content
                        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
                        .scaleEffect(Theme.scale(for: geometry.size))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .background(Theme.backgroundGradient)
            .ignoresSafeArea()
        }
    }

    /// The backdrop's dim as the home rows scroll (M7c L19); the preview video follows it. Leaving home, the video
    /// comes up to full strength with the exit animation, as Live TV shows it (M7c step 35).
    private var homeFade: Double {
        router.isLeavingHome ? 1 : HomeLayout.heroOpacity(focusedRow: router.focus.position.row)
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
                carouselPage: router.carouselPage,
                revealsLivePreview: router.revealsLivePreview,
                isLeaving: router.isLeavingHome,
                versionLabel: router.homeVersionLabel,
                remoteBatteryLevel: router.remoteBatteryLevel,
                entryGeneration: router.homeEntryGeneration,
                onHoverCard: router.hoverShelfCard,
                onActivateCard: router.activateShelfCard,
                onRefreshShelf: {
                    router.topShelf.refresh(focusing: router.focusedItem)
                    router.onRefreshRemoteBattery?()
                },
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
                onActivateRow: router.settings.activate(rowID:on:),
                onActivateParent: router.settings.activateParentColumn
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
