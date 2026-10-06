import Foundation
import Observation

/// The Settings screen (D19): a navigation stack of pages built from data (L4), driven by `RemoteCommand`s.
@Observable
final class SettingsModel {
    struct PageState: Equatable {
        var page: SettingsPage
        var focusedRowID: String?
    }

    private(set) var settings: AppSettings
    /// All tiles in stored order, hidden ones included.
    private(set) var items: [LaunchItem]
    /// Never empty.
    private(set) var stack: [PageState] = [PageState(page: .root, focusedRowID: nil)]
    /// Move mode on the homeScreen page.
    private(set) var movingTileID: String?
    private(set) var isAccessibilityTrusted: Bool
    private(set) var loginItemStatus: LoginItemStatus
    private(set) var hasPIN: Bool
    /// nil = loading (addTile page).
    private(set) var installedApps: [InstalledApp]?
    private(set) var iptv: IPTVSettingsStatus
    /// The last paste error; the paste row's detail. Cleared on any push/pop and on a successful paste.
    private(set) var pasteMessage: String?
    /// Which paste row `pasteMessage` belongs to.
    private(set) var pasteMessageKind: IPTVURLKind?
    private(set) var phoneRemote: PhoneRemoteSettingsStatus
    /// M7: Settings → Plex.
    private(set) var plex: PlexSettingsStatus
    /// M7b: Settings → Casting.
    private(set) var casting: CastingSettingsStatus
    /// M7: `key-bindings.json`, edited on the Remote Buttons pages.
    private(set) var bindings: KeyBindings
    /// M7 L25: pictures for the Tile Art page; nil while looking.
    private(set) var pictures: [PictureFile]?
    /// M7 L25: a failed copy; the page's message until the next push/pop.
    private(set) var tileArtMessage: String?
    /// M7 L23: the last start page paste error; the Start Page row's detail until the next push/pop.
    private(set) var startURLMessage: String?
    /// M7 L8: "No button pressed" after learning timed out; the Add a Button row's detail until the next push/pop.
    private(set) var learnMessage: String?
    /// How long `.learnButton` waits for a press (L8).
    @ObservationIgnored var learnTimeout: Duration = .seconds(10)
    /// Injectable clock (the confirm page's Select delay).
    @ObservationIgnored var now: () -> Date = Date.init
    /// The running learn timeout; tests await it.
    @ObservationIgnored private(set) var learnTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var isLearning = false
    /// The plex.tv/link code is made and polled while the Plex link page shows (M7 L15).
    @ObservationIgnored private var isPlexLinking = false
    @ObservationIgnored private var learnConfirmShownAt: Date?
    @ObservationIgnored let environment: SettingsEnvironment
    /// Channel Up/Down move focus by this many rows (M7 L5).
    static let pageRows = 8
    /// The phone pairing code is valid while Pair a Phone shows (M5 L3).
    @ObservationIgnored private var isPairing = false
    /// L8: a held key's auto-repeat mustn't confirm a learned button by itself.
    static let learnConfirmDelay: TimeInterval = 0.6

    init(settings: AppSettings, items: [LaunchItem], environment: SettingsEnvironment, bindings: KeyBindings = .defaults) {
        self.settings = settings
        self.items = items
        self.bindings = bindings
        self.environment = environment
        isAccessibilityTrusted = environment.isAccessibilityTrusted()
        loginItemStatus = environment.loginItemStatus()
        hasPIN = environment.hasPIN()
        iptv = environment.iptvStatus()
        phoneRemote = environment.phoneRemoteStatus()
        plex = environment.plexStatus()
        casting = environment.castingStatus()
    }

    var page: SettingsPage { stack[stack.count - 1].page }

    /// Rows with an action, in display order.
    var focusableRowIDs: [String] {
        sections.flatMap(\.rows).filter { $0.action != nil }.map(\.id)
    }

    var focusedRowID: String? {
        ListFocus.resolve(ids: focusableRowIDs, current: stack[stack.count - 1].focusedRowID)
    }

    func row(id: String) -> SettingsRow? {
        sections.lazy.flatMap(\.rows).first { $0.id == id }
    }

    func reset() {
        stack = [PageState(page: .root, focusedRowID: nil)]
        movingTileID = nil
        refreshStatus()
        syncPairing()
        syncLearning()
        syncPlexLink()
    }

    /// Settings closed (the router went home): ends phone pairing, button learning and the Plex link code.
    func screenDidClose() {
        syncLearning(closed: true)
        syncPlexLink(closed: true)
        guard isPairing else { return }
        isPairing = false
        environment.setPhonePairing(false)
        refreshStatus()
    }

    /// L10: re-read on open, after toggles, after a PIN flow and when the app becomes active.
    func refreshStatus() {
        isAccessibilityTrusted = environment.isAccessibilityTrusted()
        loginItemStatus = environment.loginItemStatus()
        hasPIN = environment.hasPIN()
        iptv = environment.iptvStatus()
        phoneRemote = environment.phoneRemoteStatus()
        plex = environment.plexStatus()
        casting = environment.castingStatus()
        followPlexSignIn()
    }

    /// Returns false only for commands it doesn't use, and for Back on the root page (the router then goes home).
    func handle(_ command: RemoteCommand) -> Bool {
        switch command {
        case .up, .down:
            let step = command == .up ? -1 : 1
            if let movingTileID, page == .homeScreen {
                updateItems(items.movingItem(id: movingTileID, by: step))
            } else {
                setFocus(ListFocus.move(ids: focusableRowIDs, current: focusedRowID, by: step))
            }
            return true
        case .left, .right:
            // L13: no value cycling.
            return true
        case .select:
            if case .confirmLearn = page, let shownAt = learnConfirmShownAt,
               now().timeIntervalSince(shownAt) < Self.learnConfirmDelay {
                return true
            }
            if movingTileID != nil {
                movingTileID = nil
            } else if let id = focusedRowID, let action = row(id: id)?.action {
                perform(action)
            }
            return true
        case .back:
            if movingTileID != nil {
                movingTileID = nil
                return true
            }
            guard stack.count > 1 else { return false }
            pop()
            return true
        case .channelUp, .channelDown:
            // M7 L5: a page of rows.
            guard movingTileID == nil else { return true }
            let step = command == .channelUp ? -Self.pageRows : Self.pageRows
            setFocus(ListFocus.move(ids: focusableRowIDs, current: focusedRowID, by: step))
            return true
        case .home, .playPause, .fastForward, .rewind, .menu:
            return false
        }
    }

    /// Mouse hover.
    func focus(rowID: String) {
        guard movingTileID == nil, focusableRowIDs.contains(rowID) else { return }
        setFocus(rowID)
    }

    /// Mouse click.
    func activate(rowID: String) {
        if movingTileID != nil {
            movingTileID = nil
            return
        }
        guard let action = row(id: rowID)?.action else { return }
        setFocus(rowID)
        perform(action)
    }

    func perform(_ action: SettingsAction) {
        switch action {
        case .toggle(let key):
            var new = settings
            new[keyPath: key.keyPath].toggle()
            settings = new
            environment.applySettings(new)
            refreshStatus()
        case .requestAccessibility:
            environment.requestAccessibility()
        case .openLoginItemsSettings:
            environment.openLoginItemsSettings()
        case .push(let page):
            push(page)
        case .pop:
            pop()
        case .relaunch:
            environment.relaunch()
        case .exitToDesktop:
            environment.exitToDesktop()
        case .toggleTileVisible(let id):
            guard let item = item(id: id), !item.isSettingsTile else { return }
            updateItems(items.settingHidden(item.isVisible, id: id))
        case .toggleTileFullScreen(let id):
            guard let item = item(id: id) else { return }
            updateItems(items.settingFullScreen(!item.wantsFullScreen, id: id))
        case .startMove(let id):
            pop()
            movingTileID = id
            setFocus(Self.tileRowID(id))
        case .removeTile(let id):
            guard let index = items.firstIndex(where: { $0.id == id }), !items[index].isSettingsTile else { return }
            let neighbor = items.indices.contains(index + 1) ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
            updateItems(items.removingItem(id: id))
            pop()
            setFocus(neighbor.map { Self.tileRowID($0.id) })
        case .addDefaultTile(let id):
            guard let item = LaunchItem.defaults.first(where: { $0.id == id }) else { return }
            addTile(item)
        case .addApp(let app):
            addTile(LaunchItem(id: "app.\(app.bundleID)", title: app.name, kind: .application(bundleID: app.bundleID)))
        case .restoreDefaults:
            updateItems(LaunchItem.defaults)
            pop()
        case .startPIN(let purpose):
            environment.startPINFlow(purpose)
        case .toggleTileRequiresPIN(let id):
            guard let item = item(id: id), !item.isSettingsTile, !item.isExitToDesktop else { return }
            updateItems(items.settingRequiresPIN(item.requiresPIN != true, id: id))
        case .reloadYouTube:
            environment.reloadYouTube()
        case .clearYouTubeData:
            environment.clearYouTubeData()
            pop()
        case .pasteIPTVURL(let kind):
            pasteMessage = environment.pasteIPTVURL(kind)
            pasteMessageKind = pasteMessage == nil ? nil : kind
            refreshStatus()
        case .moveGuideSource(let id, let step):
            environment.moveGuideSource(id, step)
            refreshStatus()
        case .removeGuideSource(let id):
            environment.removeGuideSource(id)
            pop()
            refreshStatus()
        case .toggleIPTVGroupHidden(let name):
            environment.setIPTVGroupHidden(name, !(iptv.groups.first { $0.name == name }?.isHidden ?? false))
            refreshStatus()
        case .unhideIPTVChannel(let id):
            environment.unhideIPTVChannel(id)
            refreshStatus()
        case .refreshIPTV:
            environment.refreshIPTV()
        case .removeIPTVSource:
            environment.removeIPTVSource()
            pop()
        case .forgetAllPhones:
            environment.forgetAllPhones()
            refreshStatus()
            pop()
        case .startLearning(let command):
            if case .confirmLearn = page { pop() }
            push(.learnButton(command))
        case .useLearned(let command, let trigger):
            applyBindings(bindings.adding(trigger, for: command))
            pop()
            setFocus("binding.\(bindings.bindings(for: command).count - 1)")
        case .removeBinding(let trigger):
            guard bindings.canRemove(trigger) else { return }
            applyBindings(bindings.removing(trigger))
            pop()
        case .toggleBindingGlobal(let trigger):
            guard let binding = bindings.binding(matching: trigger) else { return }
            applyBindings(bindings.settingGlobal(!binding.isGlobal, for: trigger))
        case .restoreDefaultButtons:
            applyBindings(.defaults)
            pop()
        case .choosePlexServer(let id):
            environment.choosePlexServer(id)
            if page == .plexServers { pop() }
            refreshStatus()
        case .openAirPlaySettings:
            environment.openAirPlaySettings()
        case .signOutOfPlex:
            environment.signOutOfPlex()
            pop()
            refreshStatus()
        case .pasteTileStartURL(let id):
            pasteStartURL(id: id)
        case .clearTileStartURL(let id):
            startURLMessage = nil
            updateItems(items.settingStartURL(nil, id: id))
            setFocus("tile.startURL")
        case .setTileArtStyle(let id, let style):
            updateItems(items.settingArtStyle(style, id: id))
        case .useTileArtPicture(let id, let url):
            tileArtMessage = environment.setTilePicture(id, url)
            refreshStatus()
        case .removeTileArtPicture(let id):
            environment.removeTilePicture(id)
            setFocus("art.designed")
            refreshStatus()
        }
    }

    /// L15: once the link page's code is used, the page leaves: to the server list when there are several
    /// servers, else back to the Plex page (with no server, it stays and says so).
    private func followPlexSignIn() {
        guard page == .plexLink, plex.isSignedIn else { return }
        if plex.needsServerChoice {
            pop()
            push(.plexServers)
        } else if plex.serverName != nil {
            pop()
        }
    }

    /// L23: an http(s) page on the web app's own site (else it would open in a browser tab).
    private func pasteStartURL(id: String) {
        guard let item = item(id: id), let webApp = environment.webAppInfo(item) else { return }
        switch environment.pasteURL() {
        case .failure(let problem):
            startURLMessage = ClipboardURL.message(for: problem)
        case .success(let url):
            if let host = webApp.startURL?.host(), url.host()?.lowercased() != host.lowercased() {
                startURLMessage = "Use a page on \(host)"
                return
            }
            startURLMessage = nil
            updateItems(items.settingStartURL(url, id: id))
        }
    }

    private func applyBindings(_ new: KeyBindings) {
        bindings = new
        environment.applyBindings(new)
    }

    /// L8: the handler's capture. Replaces the learn page with the confirm page; ignored when not learning.
    private func learned(_ trigger: InputBinding.Trigger) {
        guard case .learnButton(let command) = page else { return }
        pop()
        push(.confirmLearn(command, trigger))
        learnConfirmShownAt = now()
    }

    /// L8: no press within `learnTimeout`.
    private func learnTimedOut() {
        guard case .learnButton = page else { return }
        pop()
        learnMessage = "No button pressed"
    }

    func loadPictures() async {
        pictures = await environment.findPictures()
    }

    func loadInstalledApps() async {
        installedApps = await environment.scanInstalledApps()
    }

    static func tileRowID(_ itemID: String) -> String { "tile.\(itemID)" }

    func item(id: String) -> LaunchItem? {
        items.first { $0.id == id }
    }

    /// L2: inserted before Exit to Desktop; back on the tile list with the new tile focused.
    private func addTile(_ item: LaunchItem) {
        updateItems(items.insertingTile(item))
        pop()
        setFocus(Self.tileRowID(item.id))
    }

    private func push(_ page: SettingsPage) {
        pasteMessage = nil
        pasteMessageKind = nil
        learnMessage = nil
        startURLMessage = nil
        tileArtMessage = nil
        stack.append(PageState(page: page, focusedRowID: nil))
        if page == .addTile {
            installedApps = nil
            Task { await loadInstalledApps() }
        }
        if case .tileArt = page {
            pictures = nil
            Task { await loadPictures() }
        }
        syncPairing()
        syncLearning()
        syncPlexLink()
        if page == .plex { environment.refreshPlex() }
        if page == .casting { environment.refreshCasting() }
    }

    private func pop() {
        guard stack.count > 1 else { return }
        pasteMessage = nil
        pasteMessageKind = nil
        learnMessage = nil
        startURLMessage = nil
        tileArtMessage = nil
        stack.removeLast()
        syncPairing()
        syncLearning()
        syncPlexLink()
    }

    /// M7 L15: the link code is made and polled exactly while the Plex link page shows.
    private func syncPlexLink(closed: Bool = false) {
        let active = !closed && page == .plexLink
        guard active != isPlexLinking else { return }
        isPlexLinking = active
        environment.setPlexLinking(active)
    }

    /// M7 L8: the capture handler is set exactly while the learn page shows (and Settings is open).
    private func syncLearning(closed: Bool = false) {
        var active = false
        if !closed, case .learnButton = page { active = true }
        guard active != isLearning else { return }
        isLearning = active
        learnTimeoutTask?.cancel()
        learnTimeoutTask = nil
        if active {
            environment.setButtonLearning { [weak self] trigger in self?.learned(trigger) }
            let timeout = learnTimeout
            learnTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.learnTimedOut()
            }
        } else {
            environment.setButtonLearning(nil)
        }
    }

    /// M5 L3: pairing is active exactly while the Pair a Phone page shows.
    private func syncPairing() {
        let active = page == .pairPhone
        guard active != isPairing else { return }
        isPairing = active
        environment.setPhonePairing(active)
        refreshStatus()
    }

    private func setFocus(_ id: String?) {
        stack[stack.count - 1].focusedRowID = id
    }

    private func updateItems(_ new: [LaunchItem]) {
        items = new
        environment.applyItems(new)
    }
}
