import Testing
@testable import MMTVL

struct AppRouterTests {
    private func makeRouter(
        items: [LaunchItem] = LaunchItem.defaults,
        youtube: FakeYouTube = FakeYouTube(),
        liveTV: FakeLiveTV = FakeLiveTV(),
        pin: String? = nil
    ) -> AppRouter {
        let (settings, _) = makeSettingsModel(items: items)
        return AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: youtube, liveTV: liveTV,
                         pinStore: .inMemory(pin))
    }

    private func enterPIN(_ code: String, _ router: AppRouter) {
        for command in pinCommands(for: code, startRow: router.pinEntry?.pad.row ?? 0) {
            _ = router.handle(command)
        }
    }

    /// The YouTube tile is the second tile in the defaults.
    private func openYouTubeFromTile(_ router: AppRouter) {
        _ = router.handle(.right)
        #expect(router.visibleItems[router.focus.index!].kind == .internalDestination(.youtube))
        _ = router.handle(.select)
    }

    /// The Settings tile is the first tile of the second row in the defaults.
    private func openSettingsFromTile(_ router: AppRouter) {
        _ = router.handle(.down)
        #expect(router.visibleItems[router.focus.index!].isSettingsTile)
        _ = router.handle(.select)
    }

    @Test func goHomeFromSettingsEndsPhonePairing() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory())
        openSettingsFromTile(router)
        router.settings.perform(.push(.phoneRemote))
        router.settings.perform(.push(.pairPhone))
        #expect(recorder.pairingCalls == [true])
        router.goHome()
        #expect(router.screen == .home)
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func settingsTileOpensSettings() {
        let router = makeRouter()
        openSettingsFromTile(router)
        #expect(router.screen == .settings)
    }

    @Test func backOnSettingsRootGoesHomeKeepingFocus() {
        let router = makeRouter()
        openSettingsFromTile(router)
        let handled = router.handle(.back)
        #expect(handled)
        #expect(router.screen == .home)
        #expect(router.visibleItems[router.focus.index!].isSettingsTile)
    }

    @Test func homeInSettingsGoesHome() {
        let router = makeRouter()
        router.openSettings()
        _ = router.handle(.down)
        let handled = router.handle(.home)
        #expect(handled)
        #expect(router.screen == .home)
    }

    @Test func setItemsKeepsFocusOnSameItem() {
        let router = makeRouter()
        _ = router.handle(.right)
        _ = router.handle(.right)
        let focusedID = router.visibleItems[router.focus.index!].id
        router.setItems(router.items.settingHidden(true, id: router.items[0].id))
        #expect(router.visibleItems[router.focus.index!].id == focusedID)
    }

    @Test func hidingFocusedItemClampsIndex() {
        let items = Array(LaunchItem.defaults.prefix(3))
        let router = makeRouter(items: items)
        _ = router.handle(.right)
        _ = router.handle(.right)
        router.setItems(items.settingHidden(true, id: items[2].id))
        #expect(router.focus.index == 1)
    }

    @Test func youtubeTileOpensYouTube() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
    }

    @Test func youtubeForwardsCommandsExceptHome() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        let commands: [RemoteCommand] = [.up, .down, .left, .right, .select, .back, .playPause, .fastForward, .rewind]
        for command in commands {
            #expect(router.handle(command))
        }
        #expect(youtube.sent == commands)
        #expect(router.screen == .youtube)
    }

    @Test func homeLeavesYouTubeAndPauses() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        #expect(router.handle(.home))
        #expect(router.screen == .home)
        #expect(youtube.pauses == 1)
        #expect(youtube.sent.isEmpty)
        #expect(router.visibleItems[router.focus.index!].kind == .internalDestination(.youtube))
    }

    @Test func reopeningYouTubeAsksControllerEachTime() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        openYouTubeFromTile(router)
        _ = router.handle(.home)
        _ = router.handle(.select)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 2)
    }

    // MARK: PIN (D20)

    @Test func settingsTileOpensDirectlyWithoutPIN() {
        let router = makeRouter()
        openSettingsFromTile(router)
        #expect(router.screen == .settings)
        #expect(router.pinEntry == nil)
    }

    @Test func settingsTileAsksForPIN() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        #expect(router.screen == .pin(.openSettings))
        enterPIN("1357", router)
        #expect(router.screen == .settings)
        #expect(router.pinEntry == nil)
    }

    @Test func wrongPINStaysOnPINScreen() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        enterPIN("2468", router)
        #expect(router.screen == .pin(.openSettings))
        #expect(router.pinEntry?.message == "Wrong PIN")
    }

    @Test func backOnEmptyPINAndHomeReturnHome() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        #expect(router.handle(.back))
        #expect(router.screen == .home)
        openSettingsFromTile(router)
        _ = router.handle(.left)
        #expect(router.handle(.home))
        #expect(router.screen == .home)
        #expect(router.pinEntry == nil)
    }

    @Test func exitTileAsksForPINThenExits() {
        let router = makeRouter(pin: "1357")
        var exits = 0
        router.onExitToDesktop = { exits += 1 }
        _ = router.handle(.down)
        _ = router.handle(.right)
        #expect(router.visibleItems[router.focus.index!].isExitToDesktop)
        _ = router.handle(.select)
        #expect(router.screen == .pin(.exitToDesktop))
        #expect(exits == 0)
        enterPIN("1357", router)
        #expect(exits == 1)
        #expect(router.screen == .home)
    }

    @Test func flaggedTileAsksForPINThenOpens() {
        let items = LaunchItem.defaults.settingRequiresPIN(true, id: "youtube")
        let youtube = FakeYouTube()
        let router = makeRouter(items: items, youtube: youtube, pin: "1357")
        openYouTubeFromTile(router)
        #expect(router.screen == .pin(.openTile(id: "youtube")))
        #expect(youtube.opens == 0)
        enterPIN("1357", router)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
    }

    @Test func unflaggedTileOpensWithoutPIN() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube, pin: "1357")
        openYouTubeFromTile(router)
        #expect(router.screen == .youtube)
    }

    @Test func lockoutSurvivesCancel() {
        let router = makeRouter(pin: "1357")
        openSettingsFromTile(router)
        for _ in 0..<5 { enterPIN("2468", router) }
        _ = router.handle(.back)
        #expect(router.screen == .home)
        _ = router.handle(.select)
        _ = router.handle(.left)
        #expect(router.pinEntry?.message?.hasPrefix("Too many tries") == true)
    }

    @Test func settingsPINFlowReturnsToSameSettingsPage() {
        let router = makeRouter()
        router.openSettings()
        router.settings.perform(.push(.homeScreen))
        router.requestPIN(.setNew)
        #expect(router.screen == .pin(.setNew))
        enterPIN("2580", router)
        enterPIN("2580", router)
        #expect(router.screen == .settings)
        #expect(router.settings.page == .homeScreen)
        #expect(router.hasPIN)
    }

    @Test func cancellingSettingsPINFlowReturnsToSettings() {
        let router = makeRouter(pin: "1357")
        router.openSettings()
        router.requestPIN(.turnOff)
        _ = router.handle(.back)
        #expect(router.screen == .settings)
        #expect(router.hasPIN)
        router.requestPIN(.turnOff)
        enterPIN("1357", router)
        #expect(router.screen == .settings)
        #expect(!router.hasPIN)
    }
}

struct AppRouterLiveTVTests {
    private func makeRouter(liveTV: FakeLiveTV, pin: String? = nil) -> AppRouter {
        let (settings, _) = makeSettingsModel()
        return AppRouter(items: LaunchItem.defaults, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                         liveTV: liveTV, pinStore: .inMemory(pin))
    }

    /// The Live TV tile is the third tile in the defaults.
    private func openLiveTVFromTile(_ router: AppRouter) {
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(router.visibleItems[router.focus.index!].kind == .internalDestination(.iptv))
        _ = router.handle(.select)
    }

    @Test func tileOpensLiveTV() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        openLiveTVFromTile(router)
        #expect(router.screen == .liveTV)
        #expect(liveTV.opens == 1)
    }

    @Test func homeLeaves() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        openLiveTVFromTile(router)
        #expect(router.handle(.home))
        #expect(router.screen == .home)
        #expect(liveTV.leaves == 1)
        #expect(liveTV.handled.isEmpty)
    }

    @Test func leaveOutcomeGoesHome() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        liveTV.outcome = .leave
        #expect(router.handle(.back))
        #expect(router.screen == .home)
        #expect(liveTV.leaves == 1)
    }

    @Test func commandsAreForwarded() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        for command in [RemoteCommand.up, .down, .left, .right, .select, .playPause, .fastForward, .rewind, .back] {
            #expect(router.handle(command))
        }
        #expect(liveTV.handled == [.up, .down, .left, .right, .select, .playPause, .fastForward, .rewind, .back])
        #expect(router.screen == .liveTV)
    }

    @Test func openSettingsWithoutPIN() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        liveTV.outcome = .openSettings
        _ = router.handle(.select)
        #expect(router.screen == .settings)
        #expect(liveTV.leaves == 1)
    }

    @Test func openSettingsWithPIN() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV, pin: "1357")
        router.openLiveTV()
        liveTV.outcome = .openSettings
        _ = router.handle(.select)
        #expect(router.screen == .pin(.openSettings))
        #expect(liveTV.leaves == 1)
        // Cancelling returns home.
        _ = router.handle(.back)
        #expect(router.screen == .home)
    }
}
