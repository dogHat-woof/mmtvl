import Foundation
import Testing
@testable import MMTVL

struct SettingsModelTests {
    // MARK: Root page

    @Test func initialFocusIsFirstRow() {
        let (model, _) = makeSettingsModel()
        #expect(model.page == .root)
        #expect(model.focusedRowID == "globalInput")
    }

    @Test func upDownMovesAndClamps() {
        let (model, _) = makeSettingsModel()
        model.press(.up)
        #expect(model.focusedRowID == "globalInput")
        model.press(.down, .down, .down)
        #expect(model.focusedRowID == "accessibility")
    }

    @Test func togglingAppliesSettings() {
        let (model, recorder) = makeSettingsModel()
        model.press(.down, .select)
        #expect(recorder.appliedSettings.count == 1)
        #expect(recorder.appliedSettings.first?.controllersEnabled == false)
        #expect(!model.settings.controllersEnabled)
        #expect(model.row(id: "controllers")?.value == "Off")
    }

    @Test func accessibilityRowRequestsAccess() {
        let (model, recorder) = makeSettingsModel(trusted: false)
        #expect(model.row(id: "accessibility")?.value == "Not Allowed")
        model.press(.down, .down, .down, .select)
        #expect(recorder.accessibilityRequests == 1)
    }

    @Test func approveLoginItemRowOnlyWhenWaitingForApproval() {
        let (plain, _) = makeSettingsModel(loginStatus: .requiresApproval)
        #expect(plain.row(id: "approveLoginItem") == nil)

        var settings = AppSettings()
        settings.launchAtLogin = true
        let (waiting, recorder) = makeSettingsModel(loginStatus: .requiresApproval, settings: settings)
        #expect(waiting.row(id: "approveLoginItem") != nil)
        waiting.activate(rowID: "approveLoginItem")
        #expect(recorder.loginItemsOpened == 1)

        let (windowed, _) = makeSettingsModel(kiosk: false, loginStatus: .requiresApproval, settings: settings)
        #expect(windowed.row(id: "approveLoginItem") == nil)
    }

    @Test func windowedModeMarksKioskOnlyRows() {
        let (model, _) = makeSettingsModel(kiosk: false)
        #expect(model.row(id: "launchAtLogin")?.detail == "Applies in kiosk mode only")
        #expect(model.row(id: "globalInput")?.detail == "Applies in kiosk mode only")
    }

    @Test func globalInputNeedsAccessibilityDetail() {
        let (model, _) = makeSettingsModel(trusted: false)
        #expect(model.row(id: "globalInput")?.detail == "Needs Accessibility access")
    }

    @Test func pushAndPopRestoresFocus() {
        let (model, _) = makeSettingsModel()
        model.focus(rowID: "editHome")
        let pushed = model.handle(.select)
        #expect(pushed)
        #expect(model.page == .homeScreen)
        let popped = model.handle(.back)
        #expect(popped)
        #expect(model.page == .root)
        #expect(model.focusedRowID == "editHome")
        let leftRoot = model.handle(.back)
        #expect(!leftRoot)
    }

    @Test func refreshStatusRereadsAccessibility() {
        let (model, recorder) = makeSettingsModel(trusted: false)
        recorder.trusted = true
        model.refreshStatus()
        #expect(model.row(id: "accessibility")?.value == "Allowed")
    }

    @Test func homeIsNotHandled() {
        let (model, _) = makeSettingsModel()
        let handled = model.handle(.home)
        #expect(!handled)
    }

    @Test func systemActions() {
        let (model, recorder) = makeSettingsModel()
        model.activate(rowID: "relaunch")
        model.activate(rowID: "exit")
        #expect(recorder.relaunches == 1)
        #expect(recorder.exits == 1)
    }
}

struct SettingsHomeScreenTests {
    private func modelOnHomeScreen(items: [LaunchItem] = LaunchItem.defaults) -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(items: items)
        model.perform(.push(.homeScreen))
        return (model, recorder)
    }

    @Test func listsEveryTileIncludingHidden() {
        let items = LaunchItem.defaults.settingHidden(true, id: "iptv")
        let (model, _) = modelOnHomeScreen(items: items)
        let tileRows = model.sections.first { $0.id == "tiles" }!.rows
        #expect(tileRows.map(\.id) == items.map { "tile.\($0.id)" })
        let iptv = model.row(id: "tile.iptv")!
        #expect(iptv.value == "Hidden")
        #expect(iptv.isDimmed)
    }

    @Test func fullScreenRowOnlyForApps() {
        let (model, _) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "plex")))
        #expect(model.row(id: "tile.fullScreen") != nil)
        model.perform(.pop)
        model.perform(.push(.tile(id: "youtube")))
        #expect(model.row(id: "tile.fullScreen") == nil)
    }

    @Test func toggleVisibleAppliesItems() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "youtube")))
        model.activate(rowID: "tile.visible")
        #expect(recorder.appliedItems.last?.first { $0.id == "youtube" }?.isVisible == false)
        #expect(model.row(id: "tile.visible")?.value == "Off")
    }

    @Test func toggleFullScreenAppliesItems() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "prime")))
        model.activate(rowID: "tile.fullScreen")
        #expect(recorder.appliedItems.last?.first { $0.id == "prime" }?.wantsFullScreen == false)
    }

    @Test func moveModeReordersAndEnds() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "plex")))
        model.activate(rowID: "tile.move")
        #expect(model.page == .homeScreen)
        #expect(model.movingTileID == "plex")
        #expect(model.focusedRowID == "tile.plex")
        #expect(model.row(id: "tile.plex")?.isLifted == true)

        model.press(.down)
        #expect(model.items.map(\.id).prefix(2) == ["youtube", "plex"])
        #expect(recorder.appliedItems.last?.map(\.id) == model.items.map(\.id))
        #expect(model.focusedRowID == "tile.plex")

        model.press(.select)
        #expect(model.movingTileID == nil)
    }

    @Test func backEndsMoveModeWithoutLeavingPage() {
        let (model, _) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "plex")))
        model.perform(.startMove(id: "plex"))
        let handled = model.handle(.back)
        #expect(handled)
        #expect(model.movingTileID == nil)
        #expect(model.page == .homeScreen)
    }

    @Test func removeFocusesNeighbor() {
        let (model, _) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "youtube")))
        model.activate(rowID: "tile.remove")
        #expect(model.page == .homeScreen)
        #expect(!model.items.contains { $0.id == "youtube" })
        #expect(model.focusedRowID == "tile.iptv")
    }

    @Test func restoreDefaultsConfirms() {
        let items = LaunchItem.defaults.removingItem(id: "plex")
        let (model, recorder) = modelOnHomeScreen(items: items)
        model.perform(.push(.confirmRestoreDefaults))
        #expect(model.focusedRowID == "confirm.cancel")
        model.activate(rowID: "confirm.restore")
        #expect(model.items == LaunchItem.defaults)
        #expect(recorder.appliedItems.last == LaunchItem.defaults)
        #expect(model.page == .homeScreen)
    }

    @Test func cancelRestorePops() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.confirmRestoreDefaults))
        model.press(.select)
        #expect(model.page == .homeScreen)
        #expect(recorder.appliedItems.isEmpty)
    }
}

struct SettingsAddTileTests {
    private let plex = InstalledApp(bundleID: "tv.plex.htpc", name: "Plex HTPC", url: URL(filePath: "/Applications/Plex HTPC.app"))
    private let new = InstalledApp(bundleID: "com.example.new", name: "New", url: URL(filePath: "/Applications/New.app"))

    private func modelOnAddTile(apps: [InstalledApp]) -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(items: LaunchItem.defaults.removingItem(id: "settings"))
        recorder.installedApps = apps
        model.perform(.push(.homeScreen))
        model.perform(.push(.addTile))
        return (model, recorder)
    }

    @Test func showsLoadingThenApps() async {
        let (model, _) = modelOnAddTile(apps: [plex, new])
        #expect(model.row(id: "apps.loading") != nil)
        await model.loadInstalledApps()
        #expect(model.row(id: "apps.loading") == nil)
        #expect(model.row(id: "add.app.tv.plex.htpc") == nil)
        #expect(model.row(id: "add.app.com.example.new") != nil)
        #expect(model.row(id: "add.default.settings") != nil)
    }

    @Test func addingAppInsertsBeforeExit() async {
        let (model, recorder) = modelOnAddTile(apps: [new])
        await model.loadInstalledApps()
        model.activate(rowID: "add.app.com.example.new")
        let ids = model.items.map(\.id)
        #expect(ids.suffix(2) == ["app.com.example.new", "exit"])
        #expect(model.items.first { $0.id == "app.com.example.new" }?.kind == .application(bundleID: "com.example.new"))
        #expect(recorder.appliedItems.last == model.items)
        #expect(model.page == .homeScreen)
        #expect(model.focusedRowID == "tile.app.com.example.new")
    }

    @Test func addingDefaultTileInsertsBeforeExit() async {
        let (model, _) = modelOnAddTile(apps: [])
        await model.loadInstalledApps()
        model.activate(rowID: "add.default.settings")
        #expect(model.items.map(\.id).suffix(2) == ["settings", "exit"])
    }

    @Test func noAppsLeftShowsInfoRow() async {
        let (model, _) = modelOnAddTile(apps: [plex])
        await model.loadInstalledApps()
        #expect(model.row(id: "apps.none") != nil)
        #expect(!model.focusableRowIDs.contains("apps.none"))
    }
}
