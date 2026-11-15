import Foundation
import Testing
@testable import MMTVL

/// M7m L6 (D50): which tiles get which items, their values and order, and the menu's keys.
struct TileMenuTests {
    static let plex = LaunchItem(id: "plex", title: "Plex", kind: .application(bundleID: "tv.plex.htpc"))
    static let youtube = LaunchItem(id: "youtube", title: "YouTube", kind: .internalDestination(.youtube))
    static let liveTV = LaunchItem(id: "iptv", title: "Live TV", kind: .internalDestination(.iptv))
    static let browser = LaunchItem(id: "browser", title: "Browser", kind: .defaultBrowser(fullScreen: true))
    static let settings = LaunchItem(id: "settings", title: "Settings", kind: .internalDestination(.settings))
    static let exit = LaunchItem(id: "exit", title: "Exit to Desktop", kind: .system(.exitToDesktop))
    static let link = LaunchItem(id: "web", title: "Web",
                                 kind: .url(URL(string: "https://example.com")!, browserBundleID: "com.brave.Browser"))
    static let defaultBrowserLink = LaunchItem(id: "web2", title: "Web 2",
                                               kind: .url(URL(string: "https://example.com")!, browserBundleID: nil))
    static let all = [plex, youtube, liveTV, browser, settings, exit, link, defaultBrowserLink]

    private func menu(_ item: LaunchItem, isStartTile: Bool = false, isRunning: Bool = false,
                      youTubeOpened: Bool = false) -> TileMenu {
        TileMenu.make(for: item, isStartTile: isStartTile, isRunning: isRunning, youTubeOpened: youTubeOpened)
    }

    private func actions(_ menu: TileMenu) -> [TileMenuAction] { menu.items.map(\.action) }

    private func value(_ action: TileMenuAction, _ menu: TileMenu) -> String? {
        menu.items.first { $0.action == action }?.value
    }

    /// The full table for a running app, in order.
    @Test func aRunningAppHasEveryItemInOrder() {
        let menu = menu(Self.plex, isStartTile: true, isRunning: true)
        #expect(menu.tileID == "plex")
        #expect(menu.title == "Plex")
        #expect(actions(menu) == [.move, .quit, .restart, .hide, .startHere, .toggleFullScreen, .toggleRequiresPIN,
                                  .tileSettings])
        #expect(menu.items.map(\.title) == ["Move", "Quit Plex", "Restart Plex", "Hide from Home Screen", "Start Here",
                                            "Open Full Screen", "Require PIN", "Tile Settings…"])
        #expect(menu.focusedIndex == 0)
    }

    @Test func moveIsOnEveryTile() {
        for item in Self.all {
            #expect(actions(menu(item)).first == .move, "\(item.id)")
        }
    }

    @Test func quitAndRestartOnlyWhileAnAppTileRuns() {
        for item in [Self.plex, Self.browser, Self.link] {
            #expect(actions(menu(item, isRunning: true)).contains(.quit), "\(item.id)")
            #expect(actions(menu(item, isRunning: true)).contains(.restart), "\(item.id)")
            #expect(!actions(menu(item, isRunning: false)).contains(.quit), "\(item.id)")
            #expect(!actions(menu(item, isRunning: false)).contains(.restart), "\(item.id)")
        }
        // A link in the default browser, built-ins and Exit never (whatever `isRunning` says).
        for item in [Self.defaultBrowserLink, Self.youtube, Self.liveTV, Self.settings, Self.exit] {
            #expect(!actions(menu(item, isRunning: true)).contains(.quit), "\(item.id)")
            #expect(!actions(menu(item, isRunning: true)).contains(.restart), "\(item.id)")
        }
    }

    /// Security hardening: MMTVL's own app never gets Quit or Restart, by its id on the tile or the resolved one.
    @Test func mmtvlItselfIsNeverQuitOrRestarted() {
        let own = "dev.mmtvl.launcher"
        let mmtvl = LaunchItem(id: "self", title: "MMTVL", kind: .application(bundleID: own))
        let byTile = TileMenu.make(for: mmtvl, isStartTile: false, isRunning: true, youTubeOpened: false,
                                   ownBundleID: own)
        #expect(!actions(byTile).contains(.quit))
        #expect(!actions(byTile).contains(.restart))
        let byResolvedID = TileMenu.make(for: Self.browser, isStartTile: false, isRunning: true, youTubeOpened: false,
                                         ownBundleID: own, bundleID: own)
        #expect(!actions(byResolvedID).contains(.quit))
        // Another app still gets them.
        let plex = TileMenu.make(for: Self.plex, isStartTile: false, isRunning: true, youTubeOpened: false,
                                 ownBundleID: own, bundleID: "tv.plex.htpc")
        #expect(actions(plex).contains(.quit))
        #expect(actions(plex).contains(.restart))
    }

    @Test func reloadYouTubeOnlyOnTheYouTubeTileOnceOpened() {
        #expect(!actions(menu(Self.youtube)).contains(.reloadYouTube))
        #expect(actions(menu(Self.youtube, youTubeOpened: true)) == [.move, .reloadYouTube, .hide, .startHere,
                                                                     .toggleRequiresPIN, .tileSettings])
        for item in Self.all where item.id != "youtube" {
            #expect(!actions(menu(item, isRunning: true, youTubeOpened: true)).contains(.reloadYouTube), "\(item.id)")
        }
    }

    @Test func hideOnEveryTileButSettings() {
        for item in Self.all {
            #expect(actions(menu(item)).contains(.hide) == !item.isSettingsTile, "\(item.id)")
        }
    }

    @Test func startHereOnEveryTileButExitWithOnForTheStartTile() {
        for item in Self.all {
            #expect(actions(menu(item)).contains(.startHere) == !item.isExitToDesktop, "\(item.id)")
        }
        #expect(value(.startHere, menu(Self.youtube, isStartTile: true)) == "On")
        #expect(value(.startHere, menu(Self.youtube, isStartTile: false)) == nil)
    }

    @Test func choosingStartHereOnTheStartTileDoesNothing() {
        var start = menu(Self.liveTV, isStartTile: true)
        let index = start.items.firstIndex { $0.action == .startHere }!
        #expect(start.choose(index: index) == TileMenu.Outcome.none)
        var other = menu(Self.liveTV, isStartTile: false)
        #expect(other.choose(index: index) == .choose(.startHere))
    }

    @Test func openFullScreenOnlyWhereSupportedWithItsValue() {
        for item in Self.all {
            #expect(actions(menu(item)).contains(.toggleFullScreen) == item.supportsFullScreen, "\(item.id)")
        }
        #expect(value(.toggleFullScreen, menu(Self.plex)) == "Off")
        #expect(value(.toggleFullScreen, menu(Self.browser)) == "On")   // the default browser's default
        var fullScreenPlex = Self.plex
        fullScreenPlex.launchFullScreen = true
        #expect(value(.toggleFullScreen, menu(fullScreenPlex)) == "On")
    }

    @Test func requirePINOnEveryTileButSettingsAndExitWithItsValue() {
        for item in Self.all {
            let expected = !item.isSettingsTile && !item.isExitToDesktop
            #expect(actions(menu(item)).contains(.toggleRequiresPIN) == expected, "\(item.id)")
        }
        #expect(value(.toggleRequiresPIN, menu(Self.plex)) == "Off")
        var protected = Self.plex
        protected.requiresPIN = true
        #expect(value(.toggleRequiresPIN, menu(protected)) == "On")
    }

    @Test func tileSettingsOnEveryTileLast() {
        for item in Self.all {
            #expect(actions(menu(item)).last == .tileSettings, "\(item.id)")
        }
        #expect(actions(menu(Self.settings)) == [.move, .startHere, .tileSettings])
        #expect(actions(menu(Self.exit)) == [.move, .hide, .tileSettings])
    }

    /// L6's PIN column: edits ask, Quit/Restart/Reload don't.
    @Test func editsNeedThePIN() {
        let edits: [TileMenuAction] = [.move, .hide, .startHere, .toggleFullScreen, .toggleRequiresPIN, .tileSettings]
        let others: [TileMenuAction] = [.quit, .restart, .reloadYouTube]
        #expect(edits.filter { !$0.needsPIN }.isEmpty)
        #expect(others.filter { $0.needsPIN }.isEmpty)
    }

    @Test func upDownClampAndSelectChooses() {
        var menu = menu(Self.plex, isRunning: true)
        #expect(menu.handle(.up) == TileMenu.Outcome.none)
        #expect(menu.focusedIndex == 0)
        #expect(menu.handle(.down) == TileMenu.Outcome.none)
        #expect(menu.focusedItem.action == .quit)
        for _ in 0..<20 { _ = menu.handle(.down) }
        #expect(menu.focusedIndex == menu.items.count - 1)
        #expect(menu.handle(.select) == .choose(.tileSettings))
        #expect(menu.handle(.left) == TileMenu.Outcome.none)
        #expect(menu.handle(.right) == TileMenu.Outcome.none)
        menu.focus(index: 1)
        #expect(menu.focusedItem.action == .quit)
        menu.focus(index: 99)
        #expect(menu.focusedIndex == 1)
        #expect(menu.choose(index: 2) == .choose(.restart))
        #expect(menu.focusedIndex == 2)
        #expect(menu.choose(index: 99) == TileMenu.Outcome.none)
    }

    @Test func backAndMenuClose() {
        var menu = menu(Self.plex)
        #expect(menu.handle(.back) == .close)
        #expect(menu.handle(.menu) == .close)
    }
}
