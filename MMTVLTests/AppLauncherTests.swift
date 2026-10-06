import Foundation
import Testing
@testable import MMTVL

struct AppLauncherTests {
    @Test func chromiumBrowsersStartFullScreen() {
        #expect(AppLauncher.launchArguments(browserBundleID: "com.brave.Browser", fullScreen: true) == ["--start-fullscreen"])
        #expect(AppLauncher.launchArguments(browserBundleID: "com.google.Chrome", fullScreen: true) == ["--start-fullscreen"])
    }

    @Test func noArgumentsWhenFullScreenIsOff() {
        #expect(AppLauncher.launchArguments(browserBundleID: "com.brave.Browser", fullScreen: false).isEmpty)
    }

    @Test func nonChromiumBrowsersGetNoArguments() {
        #expect(AppLauncher.launchArguments(browserBundleID: "com.apple.Safari", fullScreen: true).isEmpty)
        #expect(AppLauncher.launchArguments(browserBundleID: nil, fullScreen: true).isEmpty)
    }
}

struct WantsFullScreenTests {
    private func app(_ launchFullScreen: Bool?) -> LaunchItem {
        LaunchItem(id: "a", title: "App", kind: .application(bundleID: "com.example.app"), launchFullScreen: launchFullScreen)
    }

    private func browser(_ launchFullScreen: Bool?) -> LaunchItem {
        LaunchItem(id: "b", title: "Browser", kind: .defaultBrowser(fullScreen: true), launchFullScreen: launchFullScreen)
    }

    @Test func applicationDefaultsToWindowed() {
        #expect(!app(nil).wantsFullScreen)
        #expect(app(true).wantsFullScreen)
        #expect(!app(false).wantsFullScreen)
    }

    @Test func defaultBrowserFollowsKindUnlessOverridden() {
        #expect(browser(nil).wantsFullScreen)
        #expect(!browser(false).wantsFullScreen)
    }

    @Test func primeDefaultIsFullScreen() {
        #expect(LaunchItem.defaults.first { $0.id == "prime" }?.wantsFullScreen == true)
    }

    @Test func oldJSONWithoutLaunchFullScreenDecodes() throws {
        let json = #"{ "id" : "plex", "title" : "Plex", "kind" : { "application" : { "bundleID" : "tv.plex.htpc" } } }"#
        let item = try JSONDecoder().decode(LaunchItem.self, from: Data(json.utf8))
        #expect(item.launchFullScreen == nil)
        #expect(!item.wantsFullScreen)
    }
}
