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
        model.press(.down, .down, .down, .down, .down)
        #expect(model.focusedRowID == "phoneRemote")
        model.press(.down)
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
        model.press(.down, .down, .down, .down, .down, .down, .select)
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

    @Test func settingsTileCanOnlyMove() {
        let (model, recorder) = modelOnHomeScreen()
        model.perform(.push(.tile(id: "settings")))
        // Start Here (M7c L32), Tile Art (M7 L25) and Move; never hide or remove.
        #expect(model.focusableRowIDs == ["tile.start", "tile.art", "tile.move"])
        model.perform(.toggleTileVisible(id: "settings"))
        model.perform(.removeTile(id: "settings"))
        #expect(recorder.appliedItems.isEmpty)
        #expect(model.items == LaunchItem.defaults)
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
        let (model, recorder) = makeSettingsModel(items: LaunchItem.defaults.removingItem(id: "youtube"))
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
        #expect(model.row(id: "add.default.youtube") != nil)
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
        model.activate(rowID: "add.default.youtube")
        #expect(model.items.map(\.id).suffix(2) == ["youtube", "exit"])
    }

    @Test func noAppsLeftShowsInfoRow() async {
        let (model, _) = modelOnAddTile(apps: [plex])
        await model.loadInstalledApps()
        #expect(model.row(id: "apps.none") != nil)
        #expect(!model.focusableRowIDs.contains("apps.none"))
    }
}

struct SettingsPINTests {
    private func rowIDs(_ model: SettingsModel) -> [String] {
        model.sections.flatMap(\.rows).map(\.id)
    }

    @Test func rootOffersSetPINWithoutPIN() {
        let (model, recorder) = makeSettingsModel()
        #expect(rowIDs(model).contains("pin.set"))
        #expect(!rowIDs(model).contains("pin.change"))
        model.perform(model.row(id: "pin.set")!.action!)
        #expect(recorder.pinFlows == [.setNew])
    }

    @Test func rootOffersChangeAndTurnOffWithPIN() {
        let (model, recorder) = makeSettingsModel(hasPIN: true)
        #expect(!rowIDs(model).contains("pin.set"))
        model.perform(model.row(id: "pin.change")!.action!)
        model.perform(model.row(id: "pin.off")!.action!)
        #expect(recorder.pinFlows == [.change, .turnOff])
    }

    @Test func refreshStatusRereadsPIN() {
        let (model, recorder) = makeSettingsModel()
        recorder.hasPIN = true
        model.refreshStatus()
        #expect(model.hasPIN)
        #expect(rowIDs(model).contains("pin.change"))
    }

    @Test func requirePINRowOnlyForOrdinaryTiles() {
        let (model, _) = makeSettingsModel()
        model.perform(.push(.tile(id: "plex")))
        #expect(rowIDs(model).contains("tile.requiresPIN"))
        model.perform(.pop)
        model.perform(.push(.tile(id: "settings")))
        #expect(!rowIDs(model).contains("tile.requiresPIN"))
        model.perform(.pop)
        model.perform(.push(.tile(id: "exit")))
        #expect(!rowIDs(model).contains("tile.requiresPIN"))
        #expect(model.sections.first?.footer == "Exit to Desktop always asks for the PIN when one is set.")
    }

    @Test func toggleRequiresPINAppliesItems() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.tile(id: "plex")))
        model.perform(.toggleTileRequiresPIN(id: "plex"))
        #expect(recorder.appliedItems.last?.first { $0.id == "plex" }?.requiresPIN == true)
        model.perform(.toggleTileRequiresPIN(id: "plex"))
        #expect(recorder.appliedItems.last?.first { $0.id == "plex" }?.requiresPIN == nil)
        model.perform(.toggleTileRequiresPIN(id: "exit"))
        #expect(recorder.appliedItems.count == 2)
    }

    @Test func requirePINDetailDependsOnPIN() {
        let (without, _) = makeSettingsModel()
        without.perform(.push(.tile(id: "plex")))
        #expect(without.row(id: "tile.requiresPIN")?.detail == "Set a PIN in Settings first")
        let (with, _) = makeSettingsModel(hasPIN: true)
        with.perform(.push(.tile(id: "plex")))
        #expect(with.row(id: "tile.requiresPIN")?.detail == nil)
    }
}

struct SettingsYouTubeTests {
    @Test func rootHasYouTubeRows() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "youtube.clear") != nil)
        model.perform(model.row(id: "youtube.reload")!.action!)
        #expect(recorder.youtubeReloads == 1)
    }

    @Test func clearConfirmFocusesCancelFirst() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.confirmClearYouTube))
        #expect(model.focusedRowID == "confirm.cancel")
        model.press(.select)
        #expect(model.page == .root)
        #expect(recorder.youtubeClears == 0)
    }

    @Test func clearConfirmClearsAndPops() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.confirmClearYouTube))
        model.press(.down, .select)
        #expect(recorder.youtubeClears == 1)
        #expect(model.page == .root)
    }
}

struct SettingsLiveTVTests {
    private static let status = IPTVSettingsStatus(
        hasPlaylist: true, playlistHost: "iptv.example", channelCount: 118, playlistLine: "Updated 10:42 PM",
        guideSources: [
            .init(id: "g1", label: "guide-source.online · guide-source_US2.xml.gz", line: "1,234 programmes · 50 channels · Updated 10:43 PM",
                  isFromPlaylist: false),
            .init(id: "g2", label: "guide-source.online · guide-source_FANDUEL1.xml.gz", line: "Loading…", isFromPlaylist: false),
        ],
        customGuideCount: 2, matchedChannelCount: 3)

    @Test func rootRowShowsSetupState() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "liveTV")?.value == "Not Set Up")
        recorder.iptv = Self.status
        model.refreshStatus()
        #expect(model.row(id: "liveTV")?.value == "118 Channels")
        model.perform(model.row(id: "liveTV")!.action!)
        #expect(model.page == .liveTV)
    }

    /// M7c L15.
    @Test func previewOnHomeTogglesTheSetting() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        let row = model.row(id: "iptv.homePreview")
        #expect(row?.value == "On")
        #expect(row?.detail == "Loads the channel, muted, while the home screen shows; you see it when Live TV is focused")
        model.activate(rowID: "iptv.homePreview")
        #expect(recorder.appliedSettings.last?.homeLivePreview == false)
        #expect(model.row(id: "iptv.homePreview")?.value == "Off")
    }

    /// M7c L28.
    @Test func aboutShowsTheVersionAndBuild() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "about.version")?.value == "1.1.0")
        #expect(model.row(id: "about.build")?.value == "7")
        #expect(model.row(id: "about.version")?.action == nil)
        #expect(model.row(id: "about.showOnHome")?.value == "On")
        model.activate(rowID: "about.showOnHome")
        #expect(recorder.appliedSettings.last?.showVersionOnHome == false)
        #expect(model.row(id: "about.showOnHome")?.value == "Off")
    }

    /// M7c L32.
    @Test func startHereChoosesTheStartTile() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.homeScreen))
        #expect(model.row(id: SettingsModel.tileRowID("plex"))?.detail?.hasSuffix(" · Start tile") == true)
        model.perform(.push(.tile(id: "iptv")))
        #expect(model.row(id: "tile.start")?.value == "Off")
        model.activate(rowID: "tile.start")
        #expect(recorder.appliedSettings.last?.homeStartTile == "iptv")
        #expect(model.row(id: "tile.start")?.value == "On")
        model.perform(.push(.tile(id: "exit")))
        #expect(model.row(id: "tile.start") == nil)
    }

    @Test func aHiddenStartTileFallsBackToTheFirstTile() {
        var settings = AppSettings()
        settings.homeStartTile = "youtube"
        let items = LaunchItem.defaults.settingHidden(true, id: "youtube")
        let (model, recorder) = makeSettingsModel(settings: settings, items: items)
        #expect(model.startTileID == "plex")
        model.perform(.push(.tile(id: "youtube")))
        model.activate(rowID: "tile.start")
        #expect(recorder.appliedSettings.isEmpty)
    }

    @Test func pageWithoutPlaylistOnlyPastes() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.liveTV))
        #expect(model.focusableRowIDs == ["iptv.playlist.paste"])
        #expect(model.row(id: "iptv.playlist.paste")?.title == "Paste Playlist URL")
        #expect(model.row(id: "iptv.guide.add") == nil)
        model.press(.select)
        #expect(recorder.pastes == [.playlist])
    }

    @Test func pasteErrorShowsUntilNavigation() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.liveTV))
        let defaultDetail = model.row(id: "iptv.playlist.paste")?.detail
        #expect(defaultDetail == "Copy the M3U address on this Mac or your iPhone first")

        recorder.pasteResult = "The clipboard doesn't hold a web address."
        model.press(.select)
        #expect(model.row(id: "iptv.playlist.paste")?.detail == "The clipboard doesn't hold a web address.")

        model.press(.back)
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.playlist.paste")?.detail == defaultDetail)

        // A successful paste clears it too.
        model.press(.select)
        recorder.pasteResult = nil
        model.press(.select)
        #expect(model.row(id: "iptv.playlist.paste")?.detail == defaultDetail)
    }

    @Test func pageWithPlaylistAndTwoGuides() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.channelCount = 5
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.focusableRowIDs == ["iptv.playlist.paste", "iptv.guide.g1", "iptv.guide.g2", "iptv.guide.add",
                                          "iptv.groups", "iptv.hiddenChannels", "iptv.homePreview", "iptv.refresh",
                                          "iptv.remove"])
        let info = model.row(id: "iptv.playlist.info")
        #expect(info?.title == "iptv.example")
        #expect(info?.value == "5 Channels")
        #expect(info?.detail == "Updated 10:42 PM")
        #expect(model.row(id: "iptv.playlist.paste")?.title == "Replace with Clipboard URL")
        let first = model.row(id: "iptv.guide.g1")
        #expect(first?.title == "guide-source.online · guide-source_US2.xml.gz")
        #expect(first?.value == "1")
        #expect(first?.detail == "1,234 programmes · 50 channels · Updated 10:43 PM")
        #expect(first?.action == .push(.guideSource(id: "g1")))
        #expect(model.row(id: "iptv.guide.g2")?.value == "2")
        #expect(model.row(id: "iptv.guide.g2")?.detail == "Loading…")
        let footer = model.sections.first { $0.id == "guides" }?.footer
        #expect(footer?.hasPrefix("Guide data for 3 of 5 channels.") == true)

        model.press(.down, .down, .down, .select)
        #expect(recorder.pastes == [.guide])
        model.press(.down, .down, .down, .down, .select)
        #expect(recorder.iptvRefreshes == 1)
    }

    @Test func playlistGuideIsAnInfoRow() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.guideSources = [.init(id: "p", label: "guide.example", line: "Not loaded yet", isFromPlaylist: true)]
        recorder.iptv.customGuideCount = 0
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.focusableRowIDs == ["iptv.playlist.paste", "iptv.guide.add", "iptv.groups", "iptv.hiddenChannels",
                                          "iptv.homePreview", "iptv.refresh", "iptv.remove"])
        #expect(model.row(id: "iptv.guide.p")?.value == "From Playlist")
        #expect(model.row(id: "iptv.guide.p")?.action == nil)
    }

    @Test func noGuideExplainsHowToAddOne() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.guideSources = []
        recorder.iptv.customGuideCount = 0
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.guide.none")?.title == "No guide")
        #expect(model.row(id: "iptv.guide.none")?.detail == "Copy an XMLTV guide address, then add it below")
    }

    @Test func noAddRowAtTheLimit() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.customGuideCount = IPTVLibrary.maxGuideSources
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.guide.add") == nil)
    }

    @Test func guidePasteErrorShowsOnTheGuideRowOnly() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        let playlistDetail = model.row(id: "iptv.playlist.paste")?.detail
        recorder.pasteResult = "That guide is already added"
        model.perform(.pasteIPTVURL(.guide))
        #expect(model.row(id: "iptv.guide.add")?.detail == "That guide is already added")
        #expect(model.row(id: "iptv.playlist.paste")?.detail == playlistDetail)

        model.perform(.pasteIPTVURL(.playlist))
        #expect(model.row(id: "iptv.playlist.paste")?.detail == "That guide is already added")
        #expect(model.row(id: "iptv.guide.add")?.detail == "Copy an XMLTV address on this Mac or your iPhone first")
    }

    @Test func channelsSection() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.groups = [.init(name: "Live Channels", channelCount: 97, isHidden: false),
                                .init(name: "NHL Games", channelCount: 8, isHidden: false)]
        model.refreshStatus()
        model.perform(.push(.liveTV))
        #expect(model.row(id: "iptv.groups")?.value == "All Shown")
        #expect(model.row(id: "iptv.hiddenChannels")?.value == "None")

        recorder.iptv.groups[1].isHidden = true
        recorder.iptv.hiddenChannels = [.init(id: "id:a", number: 3, name: "A", group: "Live Channels"),
                                        .init(id: "id:b", number: 9, name: "B", group: "Live Channels")]
        model.refreshStatus()
        #expect(model.row(id: "iptv.groups")?.value == "1 Hidden")
        #expect(model.row(id: "iptv.hiddenChannels")?.value == "2")
    }

    @Test func groupsPage() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.groups = [.init(name: "Live Channels", channelCount: 97, isHidden: false),
                                .init(name: "NHL Games", channelCount: 8, isHidden: true)]
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(.push(.iptvGroups))
        #expect(model.pageTitle == "Groups")
        #expect(model.focusableRowIDs == ["group.Live Channels", "group.NHL Games"])
        let nhl = model.row(id: "group.NHL Games")
        #expect(nhl?.value == "Hidden")
        #expect(nhl?.detail == "8 channels")
        #expect(nhl?.isDimmed == true)
        model.press(.select)
        model.press(.down, .select)
        #expect(recorder.groupHides == [GroupHide(name: "Live Channels", hidden: true), GroupHide(name: "NHL Games", hidden: false)])
    }

    @Test func hiddenChannelsPage() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        recorder.iptv.hiddenChannels = [.init(id: "id:a", number: 3, name: "A", group: "Live Channels")]
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(.push(.iptvHiddenChannels))
        #expect(model.row(id: "hidden.id:a")?.title == "3  A")
        #expect(model.row(id: "hidden.id:a")?.value == "Show")
        #expect(model.row(id: "hidden.id:a")?.detail == "Live Channels")
        recorder.iptv.hiddenChannels = []
        model.press(.select)
        #expect(recorder.unhiddenChannels == ["id:a"])
        // Empty: only the info row.
        #expect(model.focusableRowIDs.isEmpty)
        #expect(model.sections.flatMap(\.rows).map(\.id) == ["hidden.none"])
    }

    @Test func guidePage() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(.push(.guideSource(id: "g1")))
        #expect(model.pageTitle == "guide-source.online · guide-source_US2.xml.gz")
        #expect(model.row(id: "guideSource.status")?.detail == "1,234 programmes · 50 channels · Updated 10:43 PM")
        #expect(model.focusableRowIDs == ["guideSource.moveDown", "guideSource.remove"])
        model.press(.select)
        #expect(recorder.guideMoves == [GuideMove(id: "g1", step: 1)])
        #expect(model.page == .guideSource(id: "g1"))

        model.perform(.push(.guideSource(id: "g2")))
        #expect(model.focusableRowIDs == ["guideSource.moveUp", "guideSource.remove"])
        model.press(.down, .select)
        #expect(recorder.guideRemovals == ["g2"])
        #expect(model.page == .guideSource(id: "g1"))

        // An id no longer listed shows nothing.
        model.perform(.push(.guideSource(id: "gone")))
        #expect(model.sections.isEmpty)
        #expect(model.pageTitle == "Guide")
    }

    @Test func removeConfirmFocusesCancelFirst() {
        let (model, recorder) = makeSettingsModel()
        recorder.iptv = Self.status
        model.refreshStatus()
        model.perform(.push(.liveTV))
        model.perform(model.row(id: "iptv.remove")!.action!)
        #expect(model.page == .confirmRemoveIPTV)
        #expect(model.focusedRowID == "confirm.cancel")
        model.press(.select)
        #expect(model.page == .liveTV)
        #expect(recorder.iptvRemovals == 0)

        model.perform(.push(.confirmRemoveIPTV))
        model.press(.down, .select)
        #expect(recorder.iptvRemovals == 1)
        #expect(model.page == .liveTV)
    }
    // MARK: Channel Up/Down and Menu (M7 L5, L22)

    @Test func channelUpDownPageByEightRows() {
        let (model, _) = makeSettingsModel()
        #expect(model.handle(.channelDown))
        let ids = model.focusableRowIDs
        #expect(model.focusedRowID == ids[8])
        #expect(model.handle(.channelUp))
        #expect(model.focusedRowID == ids[0])
        model.press(.channelDown, .channelDown, .channelDown, .channelDown, .channelDown)
        #expect(model.focusedRowID == ids.last)
    }

    @Test func menuIsNotHandled() {
        let (model, _) = makeSettingsModel()
        #expect(!model.handle(.menu))
    }

    @Test func channelUpRowTogglesTheDirection() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "channelUp")?.value == "Up the List")
        #expect(model.row(id: "channelUp")?.detail == "Changes channel in Live TV")
        model.activate(rowID: "channelUp")
        #expect(recorder.appliedSettings.last?.channelUpMovesUpList == false)
        #expect(model.row(id: "channelUp")?.value == "Higher Number")
    }

    /// M7c L6.
    @Test func keepOtherAppsOutRowTogglesTheLock() {
        let (model, recorder) = makeSettingsModel()
        #expect(model.row(id: "kioskLock")?.value == "On")
        #expect(model.row(id: "kioskLock")?.action == .toggle(.kioskLock))
        model.activate(rowID: "kioskLock")
        #expect(recorder.appliedSettings.last?.kioskLock == false)
        #expect(model.row(id: "kioskLock")?.value == "Off")
    }
}

/// A web app tile's start page (M7 L23).
struct SettingsWebAppStartPageTests {
    static let meet = LaunchItem(id: "app.meet", title: "Google Meet",
                                 kind: .application(bundleID: "com.brave.Browser.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"))
    static let info = WebAppInfo(appID: "kjg", name: "Google Meet", startURL: URL(string: "https://meet.google.com/landing?lfhs=2"),
                                 browserBundleID: "com.brave.Browser")

    private func onMeetPage() -> (SettingsModel, SettingsRecorder) {
        let (model, recorder) = makeSettingsModel(items: LaunchItem.defaults + [Self.meet])
        recorder.webApps["app.meet"] = Self.info
        model.perform(.push(.homeScreen))
        model.perform(.push(.tile(id: "app.meet")))
        return (model, recorder)
    }

    @Test func onlyWebAppsHaveTheRows() {
        let (model, _) = onMeetPage()
        let ids = model.focusableRowIDs
        #expect(ids.firstIndex(of: "tile.startURL") == ids.firstIndex(of: "tile.fullScreen")! + 1)
        #expect(model.row(id: "tile.startURL")?.value == "App's Own")
        #expect(model.row(id: "tile.startURL")?.detail == "Copy a page address on this Mac or your iPhone, then select")
        #expect(model.row(id: "tile.startURL.clear") == nil)

        let (plain, _) = makeSettingsModel()
        plain.perform(.push(.homeScreen))
        plain.perform(.push(.tile(id: "plex")))
        #expect(plain.row(id: "tile.startURL") == nil)
    }

    @Test func pastingAPageOfTheAppsSite() {
        let (model, recorder) = onMeetPage()
        recorder.clipboard = "https://meet.google.com/home?calling=1\n"
        model.activate(rowID: "tile.startURL")
        let saved = recorder.appliedItems.last?.first { $0.id == "app.meet" }
        #expect(saved?.startURL?.absoluteString == "https://meet.google.com/home?calling=1")
        #expect(model.row(id: "tile.startURL")?.value == "meet.google.com/home?calling=1")
        #expect(model.row(id: "tile.startURL.clear") != nil)

        model.activate(rowID: "tile.startURL.clear")
        #expect(recorder.appliedItems.last?.first { $0.id == "app.meet" }?.startURL == nil)
        #expect(model.row(id: "tile.startURL")?.value == "App's Own")
        #expect(model.focusedRowID == "tile.startURL")
    }

    @Test func aPageOnAnotherSiteIsRefused() {
        let (model, recorder) = onMeetPage()
        recorder.clipboard = "https://example.com/meet"
        model.activate(rowID: "tile.startURL")
        #expect(recorder.appliedItems.isEmpty)
        #expect(model.row(id: "tile.startURL")?.detail == "Use a page on meet.google.com")
        recorder.clipboard = nil
        model.activate(rowID: "tile.startURL")
        #expect(model.row(id: "tile.startURL")?.detail == "The clipboard is empty. Copy the URL first.")
        model.press(.back)
        model.perform(.push(.tile(id: "app.meet")))
        #expect(model.row(id: "tile.startURL")?.detail == "Copy a page address on this Mac or your iPhone, then select")
    }

    @Test func longAddressesAreCut() {
        let url = URL(string: "https://meet.google.com/a/very/long/path/that/goes/on/and/on?x=1")!
        let label = SettingsModel.startURLLabel(url)
        #expect(label.count == 48)
        #expect(label.hasSuffix("…"))
    }
}
