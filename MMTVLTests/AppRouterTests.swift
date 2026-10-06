import Testing
@testable import MMTVL

struct AppRouterTests {
    private func makeRouter(items: [LaunchItem] = LaunchItem.defaults) -> AppRouter {
        let (settings, _) = makeSettingsModel(items: items)
        return AppRouter(items: items, launcher: AppLauncher(), settings: settings)
    }

    @Test func upThenSelectOpensSettings() {
        let router = makeRouter()
        _ = router.handle(.up)
        #expect(router.focus.isGearFocused)
        _ = router.handle(.select)
        #expect(router.screen == .settings)
    }

    @Test func backOnSettingsRootGoesHomeWithGearFocused() {
        let router = makeRouter()
        _ = router.handle(.up)
        _ = router.handle(.select)
        let handled = router.handle(.back)
        #expect(handled)
        #expect(router.screen == .home)
        #expect(router.focus.isGearFocused)
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
        let focusedID = router.visibleItems[router.focus.tileIndex!].id
        router.setItems(router.items.settingHidden(true, id: router.items[0].id))
        #expect(router.visibleItems[router.focus.tileIndex!].id == focusedID)
    }

    @Test func hidingFocusedItemClampsIndex() {
        let items = Array(LaunchItem.defaults.prefix(3))
        let router = makeRouter(items: items)
        _ = router.handle(.right)
        _ = router.handle(.right)
        router.setItems(items.settingHidden(true, id: items[2].id))
        #expect(router.focus.tileIndex == 1)
    }

    @Test func hidingEverythingFocusesGear() {
        let router = makeRouter()
        let allHidden = router.items.reduce(router.items) { $0.settingHidden(true, id: $1.id) }
        router.setItems(allHidden)
        #expect(router.visibleItems.isEmpty)
        #expect(router.focus.isGearFocused)
    }
}
