import Foundation
import Testing
@testable import MMTVL

struct AppRouterTests {
    private func makeRouter(
        items: [LaunchItem] = LaunchItem.defaults,
        youtube: FakeYouTube = FakeYouTube(),
        liveTV: FakeLiveTV = FakeLiveTV(),
        pin: String? = nil,
        topShelf: any TopShelfProviding = NoTopShelf()
    ) -> AppRouter {
        let (settings, _) = makeSettingsModel(items: items)
        return AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: youtube, liveTV: liveTV,
                         pinStore: .inMemory(pin), tileArt: makeTestTileArt(), topShelf: topShelf)
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

    /// The Settings tile is the last tile of the first row in the defaults (six per row, M7c L19).
    private func openSettingsFromTile(_ router: AppRouter) {
        for _ in 0..<5 { _ = router.handle(.right) }
        #expect(router.visibleItems[router.focus.index!].isSettingsTile)
        _ = router.handle(.select)
    }

    @Test func goHomeFromSettingsEndsPhonePairing() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory(), tileArt: makeTestTileArt())
        openSettingsFromTile(router)
        router.settings.perform(.push(.phoneRemote))
        router.settings.perform(.push(.pairPhone))
        #expect(recorder.pairingCalls == [true])
        router.goHome()
        #expect(router.screen == .home)
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func goHomeFromSettingsStopsButtonLearning() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory(), tileArt: makeTestTileArt())
        openSettingsFromTile(router)
        router.settings.perform(.push(.remoteButtons))
        router.settings.perform(.push(.remoteCommand(.select)))
        router.settings.perform(.startLearning(.select))
        #expect(recorder.learningHandler != nil)
        _ = router.handle(.home)
        #expect(router.screen == .home)
        #expect(recorder.learningHandler == nil)
    }

    /// M7c L32.
    @Test func launchFocusesTheStartTileOutOfTheShelf() {
        let router = makeRouter()
        _ = router.handle(.right)
        router.focusStartTile(id: "iptv")
        #expect(router.focusedItem?.id == "iptv")
        #expect(router.focus.position.row == 0)
        #expect(router.shelfIndex == nil)
        router.focusStartTile(id: "missing")
        #expect(router.focusedItem?.id == "plex")
    }

    /// M7c L32: Home lands on the start tile, from the home screen and from another screen.
    @Test func homeGoesToTheStartTile() {
        let router = makeRouter()
        router.startTileID = "iptv"
        _ = router.handle(.down)
        #expect(router.focus.position.row == 1)
        _ = router.handle(.home)
        #expect(router.focusedItem?.id == "iptv")
        #expect(router.focus.position.row == 0)

        _ = router.handle(.left)
        let settingsIndex = router.visibleItems.firstIndex { $0.isSettingsTile }!
        router.hover(settingsIndex)
        router.activate(settingsIndex)
        #expect(router.screen == .settings)
        _ = router.handle(.home)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "iptv")

        router.goHomeToStartTile()
        #expect(router.focusedItem?.id == "iptv")
    }

    /// M7c L32 (2026-10-10): Back that reaches the home screen lands on the start tile too.
    @Test func backToHomeGoesToTheStartTile() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.startTileID = "iptv"

        // Back on the tiles, from another row.
        _ = router.handle(.down)
        #expect(router.focus.position.row == 1)
        _ = router.handle(.back)
        #expect(router.focusedItem?.id == "iptv")
        #expect(router.focus.position.row == 0)

        // Back on Settings' root page.
        let settingsIndex = router.visibleItems.firstIndex { $0.isSettingsTile }!
        router.hover(settingsIndex)
        router.activate(settingsIndex)
        #expect(router.screen == .settings)
        _ = router.handle(.back)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "iptv")

        // Back out of Live TV's guide (opened from its tile, now focused), with another start tile.
        router.startTileID = "plex"
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        liveTV.outcome = .leave
        _ = router.handle(.back)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "plex")
    }

    /// M7c L32: the pointer resting over the home screen at launch (no move yet) doesn't take the focus.
    @Test func aRestingPointerDoesntMoveTheStartFocus() {
        let router = makeRouter()
        router.focusStartTile(id: "plex")
        router.hover(7)
        router.hoverShelfCard(0)
        #expect(router.focusedItem?.id == "plex")
        #expect(router.shelfIndex == nil)
    }

    @Test func settingsTileOpensSettings() {
        let router = makeRouter()
        openSettingsFromTile(router)
        #expect(router.screen == .settings)
    }

    /// M7c L32 (2026-10-10): onto the start tile, not the Settings tile.
    @Test func backOnSettingsRootGoesHomeToTheStartTile() {
        let router = makeRouter()
        openSettingsFromTile(router)
        let handled = router.handle(.back)
        #expect(handled)
        #expect(router.screen == .home)
        #expect(router.focusedItem?.id == "plex")
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
        // M7c L32: Home lands on the start tile.
        #expect(router.focusedItem?.id == "plex")
    }

    @Test func reopeningYouTubeAsksControllerEachTime() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.startTileID = "youtube"
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
        _ = router.handle(.down)            // row 1 holds only Exit to Desktop
        #expect(router.visibleItems[router.focus.index!].isExitToDesktop)
        _ = router.handle(.select)
        #expect(router.screen == .pin(.exitToDesktop))
        #expect(exits == 0)
        enterPIN("1357", router)
        #expect(exits == 1)
        #expect(router.screen == .home)
    }

    /// M7c L9.
    @Test func quitWithoutPINQuitsAtOnce() {
        let router = makeRouter()
        var quits = 0
        router.onQuit = { quits += 1 }
        router.requestQuit()
        #expect(quits == 1)
        #expect(router.screen == .home)
    }

    @Test func quitAsksForPINFirst() {
        let router = makeRouter(pin: "1357")
        var quits = 0
        router.onQuit = { quits += 1 }
        router.requestQuit()
        #expect(router.screen == .pin(.quit))
        #expect(router.pinEntry?.title == "Enter PIN to quit MMTVL")
        enterPIN("2468", router)
        #expect(quits == 0)
        #expect(router.screen == .pin(.quit))
        enterPIN("1357", router)
        #expect(quits == 1)
    }

    @Test func cancellingTheQuitPINReturnsToSettings() {
        let router = makeRouter(pin: "1357")
        var quits = 0
        router.onQuit = { quits += 1 }
        router.openSettings()
        router.requestQuit()
        #expect(router.handle(.back))
        #expect(router.screen == .settings)
        #expect(quits == 0)
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
    // MARK: Focus motion (M7 L2)

    @Test func movingArrowsBumpFocusMotion() {
        let router = makeRouter()
        #expect(router.focusMotion == FocusMotion())
        _ = router.handle(.right)
        #expect(router.focusMotion == FocusMotion(direction: .right, generation: 1))
        _ = router.handle(.down)
        #expect(router.focusMotion == FocusMotion(direction: .down, generation: 2))
    }

    @Test func blockedArrowsAndHoverDontBumpFocusMotion() {
        let router = makeRouter()
        _ = router.handle(.left)
        _ = router.handle(.up)
        #expect(router.focusMotion.generation == 0)
        router.hover(3)
        #expect(router.focusMotion.generation == 0)
    }

    @Test func selectBumpsFocusMotion() {
        let router = makeRouter()
        router.openSettings()
        router.goHome()
        _ = router.handle(.down)   // Exit to Desktop (row 1)
        _ = router.handle(.select)
        #expect(router.focusMotion.direction == .select)
        #expect(router.focusMotion.generation == 2)
    }

    // MARK: Top shelf (M7 L12)

    private func card(_ id: String, _ action: ShelfCard.Action) -> ShelfCard {
        ShelfCard(id: id, title: id, subtitle: "", image: .channelLogo(nil), progress: nil, action: action)
    }

    /// Plex (the first tile) has three cards.
    private func shelfRouter(pin: String? = nil, liveTV: FakeLiveTV = FakeLiveTV()) -> (AppRouter, FakeTopShelf) {
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .cards(title: "Continue Watching", [
            card("a", .openTile(id: "plex")), card("b", .playChannel("id:nbatv.us")), card("c", .openTile(id: "youtube")),
        ])
        return (makeRouter(liveTV: liveTV, pin: pin, topShelf: shelf), shelf)
    }

    @Test func upFromTheFirstRowEntersTheShelfOnlyWithCards() {
        let (router, _) = shelfRouter()
        #expect(router.handle(.up))
        #expect(router.shelfIndex == 0)
        #expect(router.focus.index == 0)

        let (other, _) = shelfRouter()
        _ = other.handle(.right)          // YouTube: banner
        _ = other.handle(.up)
        #expect(other.shelfIndex == nil)
    }

    // MARK: Live TV preview (M7c L15, L16)

    /// Live TV (the third tile) has two channel pages (M7c L21): NFL Network (the default preview), then NBA TV.
    private func previewRouter(items: [LaunchItem] = LaunchItem.defaults, pin: String? = nil) -> (AppRouter, FakeLiveTV) {
        let liveTV = FakeLiveTV()
        liveTV.defaultPreviewChannelID = "id:nflnetwork.us"
        let shelf = FakeTopShelf()
        shelf.contents["iptv"] = .carousel(title: "On Now", [
            card("live.nfl", .playChannel("id:nflnetwork.us")), card("live.nba", .playChannel("id:nbatv.us")),
        ], autoAdvances: false)
        let router = makeRouter(items: items, liveTV: liveTV, pin: pin, topShelf: shelf)
        router.previewDelay = .zero
        router.previewIdleTimeout = .seconds(3600)
        return (router, liveTV)
    }

    private func focusLiveTV(_ router: AppRouter) {
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(router.focusedItem?.id == "iptv")
    }

    @Test func focusingLiveTVStartsThePreview() {
        let (router, liveTV) = previewRouter()
        #expect(liveTV.previewStarts.isEmpty)
        focusLiveTV(router)
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
    }

    /// M7c L21: Left/Right in the hero change channel; Down keeps the page and its channel.
    @Test func livePagesSwitchTheChannel() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.up)
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        _ = router.handle(.right)
        #expect(liveTV.previewChannelID == "id:nbatv.us")
        _ = router.handle(.down)
        #expect(router.shelfIndex == nil)
        #expect(router.carouselPage == 1)
        #expect(liveTV.previewChannelID == "id:nbatv.us")
        _ = router.handle(.left)
        _ = router.handle(.right)
        #expect(router.carouselPage == 0)
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
    }

    @Test func livePagesDontAutoAdvance() {
        let (router, _) = previewRouter()
        focusLiveTV(router)
        router.advanceCarousel()
        #expect(router.carouselPage == 0)
    }

    /// M7c L21: Select on the tile opens the page's channel when it isn't the first page.
    @Test func selectOnTheTileOpensTheKeptPage() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(liveTV.openedChannelIDs == [nil])
        router.goHome()
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.down)
        _ = router.handle(.select)
        #expect(liveTV.openedChannelIDs == [nil, "id:nbatv.us"])
    }

    /// M7c L25: moving off the tile keeps the stream (hidden), so coming back is instant.
    @Test func movingOffTheTileKeepsThePreviewHidden() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        #expect(router.showsLivePreviewVideo)
        _ = router.handle(.right)
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        #expect(liveTV.previewStops == 0)
        #expect(!router.showsLivePreviewVideo)
        _ = router.handle(.left)
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
        #expect(router.showsLivePreviewVideo)
    }

    /// M7c L25: the home screen preloads the default channel with any tile focused.
    @Test func theHomeScreenPreloadsWithAnotherTileFocused() {
        let (router, liveTV) = previewRouter()
        _ = router.handle(.right)
        #expect(router.focusedItem?.id != "iptv")
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
        #expect(!router.showsLivePreviewVideo)
        _ = router.handle(.right)
        #expect(liveTV.previewStarts == ["id:nflnetwork.us"])
        #expect(router.showsLivePreviewVideo)
    }

    /// M7c L25: Back from Live TV keeps the channel running as the preview (no stop, no new start).
    @Test func leavingLiveTVKeepsTheChannelPlaying() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        liveTV.previewChannelID = nil   // adopted by Live TV
        liveTV.playingChannelID = "id:nflnetwork.us"
        liveTV.outcome = .leave
        _ = router.handle(.back)
        #expect(router.screen == .home)
        #expect(liveTV.leavesKeepingPreview == [true])
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        #expect(liveTV.calls == ["start id:nflnetwork.us", "open", "leave"])
    }

    @Test func withThePreviewOffLeavingLiveTVStopsIt() {
        let (router, liveTV) = previewRouter()
        router.livePreviewEnabled = false
        focusLiveTV(router)
        _ = router.handle(.select)
        liveTV.outcome = .leave
        _ = router.handle(.back)
        #expect(liveTV.leavesKeepingPreview == [false])
        #expect(liveTV.previewStarts.isEmpty)
    }

    /// M7c L26.
    @Test func theScreenSaverStopsThePreview() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        router.screenSaverDidStart()
        #expect(liveTV.previewChannelID == nil)
        router.screenSaverDidStop()
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
    }

    @Test func aPINLockedLiveTVTileHasNoPreview() {
        var items = LaunchItem.defaults
        items[2].requiresPIN = true
        let (router, liveTV) = previewRouter(items: items, pin: "1234")
        focusLiveTV(router)
        #expect(liveTV.previewStarts.isEmpty)
    }

    @Test func theSettingInactivityAndIdleStopThePreview() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        router.livePreviewEnabled = false
        #expect(liveTV.previewChannelID == nil)
        router.livePreviewEnabled = true
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")

        router.isAppActive = false
        #expect(liveTV.previewChannelID == nil)
        router.isAppActive = true
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")

        router.screensDidSleep()
        #expect(liveTV.previewChannelID == nil)
        router.noteActivity()
        #expect(liveTV.previewChannelID == "id:nflnetwork.us")
        #expect(liveTV.previewStarts.count == 4)
    }

    @Test func aFailedPreviewWaitsForFocusToComeBack() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        liveTV.previewChannelID = nil
        liveTV.previewFailed = true
        _ = router.handle(.up)
        _ = router.handle(.down)
        #expect(liveTV.previewStarts.count == 1)
        _ = router.handle(.left)
        _ = router.handle(.right)
        #expect(liveTV.previewStarts.count == 2)
    }

    @Test func openingSettingsStopsThePreview() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        router.openSettings()
        #expect(liveTV.previewChannelID == nil)
    }

    @Test func openingLiveTVKeepsThePreviewForAdoption() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        #expect(liveTV.calls == ["start id:nflnetwork.us", "open"])
    }

    @Test func noPreviewWithoutAChannel() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV, topShelf: FakeTopShelf())   // no pages, no default channel
        router.previewDelay = .zero
        focusLiveTV(router)
        #expect(liveTV.previewStarts.isEmpty)
    }

    // MARK: Leaving home (M7c L22, L23)

    @Test func selectOnLiveTVAnimatesThenAdopts() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.isLeavingHome)
        #expect(liveTV.opens == 0)
        await router.homeExitTask?.value
        #expect(!router.isLeavingHome)
        #expect(router.screen == .liveTV)
        #expect(liveTV.calls == ["start id:nflnetwork.us", "open"])
    }

    @Test func commandsWaitDuringTheExit() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(router.handle(.right))
        #expect(router.focusedItem?.id == "iptv")
        await router.homeExitTask?.value
        #expect(liveTV.opens == 1)
    }

    @Test func homeCancelsTheExit() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.select)
        let task = router.homeExitTask
        _ = router.handle(.home)
        #expect(!router.isLeavingHome)
        await task?.value
        #expect(liveTV.opens == 0)
        #expect(router.screen == .home)
    }

    @Test func aLivePageAnimatesThenOpensItsChannel() async {
        let (router, liveTV) = previewRouter()
        router.homeExitDelay = .milliseconds(20)
        focusLiveTV(router)
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.select)
        #expect(router.isLeavingHome)
        await router.homeExitTask?.value
        #expect(liveTV.openedChannelIDs == ["id:nbatv.us"])
    }

    @Test func aPlexPageAnimatesThenOpens() async {
        let router = carouselRouter()
        router.homeExitDelay = .milliseconds(20)
        _ = router.handle(.up)
        _ = router.handle(.left)            // the page that opens YouTube (nothing real launches)
        _ = router.handle(.select)
        #expect(router.isLeavingHome)
        #expect(router.screen == .home)
        await router.homeExitTask?.value
        #expect(router.screen == .youtube)
        #expect(!router.isLeavingHome)
    }

    @Test func noAnimationWithoutADelay() {
        let (router, liveTV) = previewRouter()
        focusLiveTV(router)
        _ = router.handle(.select)
        #expect(!router.isLeavingHome)
        #expect(liveTV.opens == 1)
    }

    // MARK: Carousel (M7c L14)

    /// Plex (the first tile) shows a carousel of three pages; the last opens YouTube.
    private func carouselRouter() -> AppRouter {
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .carousel(title: "Continue Watching", [
            card("a", .openTile(id: "plex")), card("b", .openTile(id: "plex")), card("c", .openTile(id: "youtube")),
        ], autoAdvances: true)
        let router = makeRouter(topShelf: shelf)
        router.carouselInterval = .seconds(3600)
        return router
    }

    @Test func carouselAdvancesAndWraps() {
        let router = carouselRouter()
        #expect(router.carouselPage == 0)
        router.advanceCarousel()
        router.advanceCarousel()
        #expect(router.carouselPage == 2)
        router.advanceCarousel()
        #expect(router.carouselPage == 0)
    }

    @Test func upEntersTheCarouselOnItsPage() {
        let router = carouselRouter()
        router.advanceCarousel()
        #expect(router.handle(.up))
        #expect(router.shelfIndex == 1)
        // No auto-advance while the carousel has focus.
        router.advanceCarousel()
        #expect(router.carouselPage == 1)
        _ = router.handle(.down)
        #expect(router.shelfIndex == nil)
        #expect(router.carouselPage == 1)
        router.advanceCarousel()
        #expect(router.carouselPage == 2)
    }

    @Test func carouselLeftRightWrap() {
        let router = carouselRouter()
        _ = router.handle(.up)
        _ = router.handle(.left)
        #expect(router.shelfIndex == 2)
        #expect(router.carouselPage == 2)
        _ = router.handle(.right)
        #expect(router.shelfIndex == 0)
        #expect(router.carouselPage == 0)
    }

    @Test func selectInTheCarouselActivatesThePage() {
        let router = carouselRouter()
        _ = router.handle(.up)
        _ = router.handle(.left)
        _ = router.handle(.select)
        #expect(router.screen == .youtube)
    }

    @Test func carouselPageResetsWhenTheTileChanges() {
        let router = carouselRouter()
        router.advanceCarousel()
        _ = router.handle(.right)
        _ = router.handle(.left)
        #expect(router.carouselPage == 0)
    }

    @Test func upFromTheSecondRowMovesToTheFirst() {
        let (router, _) = shelfRouter()
        _ = router.handle(.down)
        _ = router.handle(.up)
        #expect(router.shelfIndex == nil)
        #expect(router.focus.index == 0)
    }

    @Test func downAndBackReturnToTheTile() {
        let (router, _) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.down)
        #expect(router.shelfIndex == nil)
        #expect(router.focus.index == 0)
        _ = router.handle(.up)
        _ = router.handle(.back)
        #expect(router.shelfIndex == nil)
        #expect(router.screen == .home)
        _ = router.handle(.up)
        _ = router.handle(.up)
        #expect(router.shelfIndex == 0)
    }

    @Test func leftRightClampInTheShelf() {
        let (router, _) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.left)
        #expect(router.shelfIndex == 0)
        _ = router.handle(.right)
        _ = router.handle(.right)
        _ = router.handle(.right)
        #expect(router.shelfIndex == 2)
        #expect(router.focus.index == 0)
    }

    @Test func selectOnAChannelCardOpensLiveTVOnIt() {
        let liveTV = FakeLiveTV()
        let (router, _) = shelfRouter(liveTV: liveTV)
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.select)
        #expect(router.screen == .liveTV)
        #expect(liveTV.openedChannelIDs == ["id:nbatv.us"])
        #expect(router.shelfIndex == nil)
    }

    @Test func selectOnATileCardOpensThatTile() {
        let (router, _) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.right)
        _ = router.handle(.select)
        #expect(router.screen == .youtube)
    }

    @Test func aTileCardAsksForThePINWhenTheTileNeedsIt() {
        var items = LaunchItem.defaults
        items[1].requiresPIN = true
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .cards(title: "Cards", [card("c", .openTile(id: "youtube"))])
        let router = makeRouter(items: items, pin: "1234", topShelf: shelf)
        _ = router.handle(.up)
        _ = router.handle(.select)
        #expect(router.screen == .pin(.openTile(id: "youtube")))
    }

    @Test func aPINProtectedTileNeverEntersItsShelf() {
        var items = LaunchItem.defaults
        items[0].requiresPIN = true
        let shelf = FakeTopShelf()
        shelf.contents["plex"] = .cards(title: "Cards", [card("a", .openTile(id: "plex"))])
        let router = makeRouter(items: items, pin: "1234", topShelf: shelf)
        #expect(router.shelfContent == .banner)
        _ = router.handle(.up)
        #expect(router.shelfIndex == nil)
        // Without a PIN set, the flag doesn't matter.
        let open = makeRouter(items: items, topShelf: shelf)
        _ = open.handle(.up)
        #expect(open.shelfIndex == 0)
    }

    @Test func shrinkingContentClampsOrLeavesTheShelf() {
        let (router, shelf) = shelfRouter()
        _ = router.handle(.up)
        _ = router.handle(.right)
        _ = router.handle(.right)
        shelf.contents["plex"] = .cards(title: "Fewer", [card("a", .openTile(id: "plex"))])
        router.shelfContentChanged()
        #expect(router.shelfIndex == 0)
        shelf.contents["plex"] = .banner
        router.shelfContentChanged()
        #expect(router.shelfIndex == nil)
    }

    @Test func focusChangesAndGoingHomeRefreshTheShelf() {
        let (router, shelf) = shelfRouter()
        _ = router.handle(.right)
        router.openSettings()
        router.goHome()
        #expect(shelf.refreshes == ["youtube", "youtube"])
    }

    // MARK: Mouse wheel (M7 L21)

    @Test func twoPreciseDeltasMoveOneRow() {
        let router = makeRouter()
        router.scrollWheel(deltaY: -25, precise: true)
        #expect(router.focus.position.row == 0)
        router.scrollWheel(deltaY: -25, precise: true)
        #expect(router.focus.position.row == 1)
        router.scrollWheel(deltaY: 40, precise: true)
        #expect(router.focus.position.row == 0)
    }

    @Test func oneWheelLineMovesOneRow() {
        let router = makeRouter()
        router.scrollWheel(deltaY: -1, precise: false)
        #expect(router.focus.position.row == 1)
        router.scrollWheel(deltaY: 1, precise: false)
        #expect(router.focus.position.row == 0)
    }

    @Test func scrollAccumulatorResetsAfterAPause() {
        let router = makeRouter()
        var time = Date(timeIntervalSince1970: 0)
        router.now = { time }
        router.scrollWheel(deltaY: -25, precise: true)
        time += 0.5
        router.scrollWheel(deltaY: -25, precise: true)
        #expect(router.focus.position.row == 0)
    }

    @Test func wheelOnAnotherScreenDoesNothing() {
        let router = makeRouter()
        router.openSettings()
        router.scrollWheel(deltaY: -3, precise: false)
        router.goHome()
        #expect(router.focus.position.row == 0)
    }


    // MARK: Casting (M7b L4)

    @Test func castFromHomeOpensYouTube() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(youtube.opens == 1)
        #expect(youtube.launches.isEmpty)
    }

    @Test func castWithQueryLaunchesIt() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.castYouTube(query: "pairingCode=x")
        #expect(router.screen == .youtube)
        #expect(youtube.launches == ["pairingCode=x"])
        #expect(youtube.opens == 0)
    }

    @Test func castLeavesLiveTV() {
        let liveTV = FakeLiveTV()
        let router = makeRouter(liveTV: liveTV)
        router.openLiveTV()
        router.castYouTube(query: nil)
        #expect(liveTV.leaves == 1)
        #expect(router.screen == .youtube)
    }

    @Test func castFromSettingsEndsPhonePairing() {
        let items = LaunchItem.defaults
        let (settings, recorder) = makeSettingsModel(items: items)
        let router = AppRouter(items: items, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                               liveTV: FakeLiveTV(), pinStore: .inMemory(), tileArt: makeTestTileArt())
        openSettingsFromTile(router)
        router.settings.perform(.push(.phoneRemote))
        router.settings.perform(.push(.pairPhone))
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func castClosesThePINScreen() {
        let router = makeRouter(pin: "1357")
        router.requestPIN(.exitToDesktop)
        #expect(router.pinEntry != nil)
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(router.pinEntry == nil)
    }

    @Test func castWhileOnYouTubeDoesNotPause() {
        let youtube = FakeYouTube()
        let router = makeRouter(youtube: youtube)
        router.openYouTube()
        router.castYouTube(query: "pairingCode=y")
        #expect(youtube.pauses == 0)
        #expect(youtube.launches == ["pairingCode=y"])
        #expect(router.screen == .youtube)
    }

    @Test func castIgnoresTheYouTubeTilePIN() {
        let youtube = FakeYouTube()
        let items = LaunchItem.defaults.settingRequiresPIN(true, id: "youtube")
        let router = makeRouter(items: items, youtube: youtube, pin: "1357")
        router.castYouTube(query: nil)
        #expect(router.screen == .youtube)
        #expect(router.pinEntry == nil)
        #expect(youtube.opens == 1)
    }
}

struct AppRouterLiveTVTests {
    private func makeRouter(liveTV: FakeLiveTV, pin: String? = nil) -> AppRouter {
        let (settings, _) = makeSettingsModel()
        return AppRouter(items: LaunchItem.defaults, launcher: AppLauncher(), settings: settings, youtube: FakeYouTube(),
                         liveTV: liveTV, pinStore: .inMemory(pin), tileArt: makeTestTileArt())
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
