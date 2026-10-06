import Foundation
import Testing
@testable import MMTVL

struct LaunchItemEditingTests {
    let items: [LaunchItem] = [
        LaunchItem(id: "a", title: "A", kind: .application(bundleID: "com.example.a")),
        LaunchItem(id: "b", title: "B", kind: .application(bundleID: "com.example.b")),
        LaunchItem(id: "c", title: "C", kind: .internalDestination(.youtube)),
        LaunchItem(id: "exit", title: "Exit", kind: .system(.exitToDesktop)),
    ]

    @Test func movesItems() {
        #expect(items.movingItem(id: "a", by: 1).map(\.id) == ["b", "a", "c", "exit"])
        #expect(items.movingItem(id: "c", by: -2).map(\.id) == ["c", "a", "b", "exit"])
    }

    @Test func movingPastTheEdgesOrUnknownIdIsUnchanged() {
        #expect(items.movingItem(id: "a", by: -1) == items)
        #expect(items.movingItem(id: "exit", by: 1) == items)
        #expect(items.movingItem(id: "nope", by: 1) == items)
    }

    @Test func hidesAndShows() {
        let hidden = items.settingHidden(true, id: "b")
        #expect(hidden[1].isHidden == true)
        #expect(!hidden[1].isVisible)
        #expect(hidden.visible.map(\.id) == ["a", "c", "exit"])
        let shown = hidden.settingHidden(false, id: "b")
        #expect(shown[1].isHidden == nil)
        #expect(shown[1].isVisible)
    }

    @Test func setsFullScreenExplicitly() {
        let prime = LaunchItem.defaults.first { $0.id == "prime" }!
        #expect(prime.wantsFullScreen)
        let edited = [prime].settingFullScreen(false, id: "prime")
        #expect(!edited[0].wantsFullScreen)
    }

    @Test func removesItems() {
        #expect(items.removingItem(id: "b").map(\.id) == ["a", "c", "exit"])
    }

    @Test func insertsBeforeSystemItemOrAppends() {
        let new = LaunchItem(id: "x", title: "X", kind: .application(bundleID: "com.example.x"))
        #expect(items.insertingTile(new).map(\.id) == ["a", "b", "c", "x", "exit"])
        #expect(Array(items.prefix(2)).insertingTile(new).map(\.id) == ["a", "b", "x"])
    }

    @Test func findsMissingDefaults() {
        let missing = LaunchItem.defaults.removingItem(id: "settings").missingDefaults
        #expect(missing.map(\.id) == ["settings"])
        #expect(LaunchItem.defaults.missingDefaults.isEmpty)
    }

    @Test func collectsApplicationBundleIDs() {
        #expect(items.applicationBundleIDs == ["com.example.a", "com.example.b"])
    }

    @Test func oldJSONWithoutIsHiddenDecodesVisible() throws {
        let json = #"[{"id":"a","title":"A","kind":{"application":{"bundleID":"com.example.a"}}}]"#
        let decoded = try JSONDecoder().decode([LaunchItem].self, from: Data(json.utf8))
        #expect(decoded[0].isVisible)
    }

    @Test func visibleItemEncodesWithoutIsHidden() throws {
        let data = try JSONEncoder().encode(items[0])
        #expect(!String(decoding: data, as: UTF8.self).contains("isHidden"))
    }

    @Test func onlyAppsAndBrowserSupportFullScreen() {
        #expect(items[0].supportsFullScreen)
        #expect(LaunchItem(id: "br", title: "Browser", kind: .defaultBrowser(fullScreen: true)).supportsFullScreen)
        #expect(!items[2].supportsFullScreen)
        #expect(!items[3].supportsFullScreen)
        #expect(!LaunchItem(id: "u", title: "U", kind: .url(URL(string: "https://example.com")!, browserBundleID: nil)).supportsFullScreen)
    }

    @Test func defaultsHaveSettingsBeforeExit() {
        let ids = LaunchItem.defaults.map(\.id)
        let settingsIndex = try! #require(ids.firstIndex(of: "settings"))
        #expect(ids[settingsIndex + 1] == "exit")
    }

    @Test func ensuringSettingsTileAddsMissingOne() {
        let result = items.ensuringSettingsTile()
        #expect(result.map(\.id) == ["a", "b", "c", "settings", "exit"])
        #expect(result.ensuringSettingsTile() == result)
    }

    @Test func ensuringSettingsTileShowsHiddenOne() {
        let hidden = LaunchItem.defaults.settingHidden(true, id: "settings")
        #expect(hidden.ensuringSettingsTile() == LaunchItem.defaults)
    }
}

struct LaunchItemPINTests {
    @Test func settingRequiresPINStoresTrueOrNil() {
        let on = LaunchItem.defaults.settingRequiresPIN(true, id: "browser")
        #expect(on.first { $0.id == "browser" }?.requiresPIN == true)
        let off = on.settingRequiresPIN(false, id: "browser")
        #expect(off.first { $0.id == "browser" }?.requiresPIN == nil)
    }

    @Test func pinProtection() {
        let items = LaunchItem.defaults.settingRequiresPIN(true, id: "browser")
        func item(_ id: String) -> LaunchItem { items.first { $0.id == id }! }
        #expect(item("settings").isPINProtected)
        #expect(item("exit").isPINProtected)
        #expect(item("browser").isPINProtected)
        #expect(!item("plex").isPINProtected)
    }

    @Test func oldJSONWithoutRequiresPINDecodes() throws {
        let json = #"[{"id":"plex","title":"Plex","kind":{"application":{"bundleID":"tv.plex.htpc"}}}]"#
        let items = try JSONDecoder().decode([LaunchItem].self, from: Data(json.utf8))
        #expect(items.first?.requiresPIN == nil)
    }
}
