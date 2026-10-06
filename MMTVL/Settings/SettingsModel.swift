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
    private(set) var phoneRemote: PhoneRemoteSettingsStatus
    @ObservationIgnored let environment: SettingsEnvironment
    /// The phone pairing code is valid while Pair a Phone shows (M5 L3).
    @ObservationIgnored private var isPairing = false

    init(settings: AppSettings, items: [LaunchItem], environment: SettingsEnvironment) {
        self.settings = settings
        self.items = items
        self.environment = environment
        isAccessibilityTrusted = environment.isAccessibilityTrusted()
        loginItemStatus = environment.loginItemStatus()
        hasPIN = environment.hasPIN()
        iptv = environment.iptvStatus()
        phoneRemote = environment.phoneRemoteStatus()
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
    }

    /// Settings closed (the router went home): ends phone pairing.
    func screenDidClose() {
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
        case .home, .playPause, .fastForward, .rewind:
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
            refreshStatus()
        case .useIPTVPlaylistGuide:
            environment.useIPTVPlaylistGuide()
        case .refreshIPTV:
            environment.refreshIPTV()
        case .removeIPTVSource:
            environment.removeIPTVSource()
            pop()
        case .forgetAllPhones:
            environment.forgetAllPhones()
            refreshStatus()
            pop()
        }
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
        stack.append(PageState(page: page, focusedRowID: nil))
        if page == .addTile {
            installedApps = nil
            Task { await loadInstalledApps() }
        }
        syncPairing()
    }

    private func pop() {
        guard stack.count > 1 else { return }
        pasteMessage = nil
        stack.removeLast()
        syncPairing()
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
