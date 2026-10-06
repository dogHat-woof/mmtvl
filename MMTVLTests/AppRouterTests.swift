import Testing
@testable import MMTVL

struct AppRouterTests {
    private func makeRouter(items: [LaunchItem] = LaunchItem.defaults) -> AppRouter {
        let (settings, _) = makeSettingsModel(items: items)
        return AppRouter(items: items, launcher: AppLauncher(), settings: settings)
    }

    /// The Settings tile is the first tile of the second row in the defaults.
    private func openSettingsFromTile(_ router: AppRouter) {
        _ = router.handle(.down)
        #expect(router.visibleItems[router.focus.index!].isSettingsTile)
        _ = router.handle(.select)
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
}
