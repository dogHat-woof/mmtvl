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

struct LaunchCancellationTests {
    private let start = Date(timeIntervalSince1970: 1_791_200_000)

    @Test func homeDuringALaunchSendsTheAppBack() {
        var cancellation = LaunchCancellation()
        cancellation.began("tv.plex.htpc", at: start)
        #expect(cancellation.homePressed(at: start + 3) == "tv.plex.htpc")
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 8))
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 22))
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 23) == false)
        #expect(cancellation.shouldReturn(activated: "com.apple.Safari", at: start + 8) == false)
        #expect(cancellation.shouldReturn(activated: nil, at: start + 8) == false)
    }

    @Test func homeLongAfterALaunchCancelsNothing() {
        var cancellation = LaunchCancellation()
        cancellation.began("tv.plex.htpc", at: start)
        #expect(cancellation.homePressed(at: start + 20) == nil)
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 21) == false)
    }

    @Test func withoutALaunchNothingIsCancelled() {
        var cancellation = LaunchCancellation()
        #expect(cancellation.homePressed(at: start) == nil)
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start) == false)
    }

    @Test func aNewLaunchClearsTheCancellation() {
        var cancellation = LaunchCancellation()
        cancellation.began("tv.plex.htpc", at: start)
        _ = cancellation.homePressed(at: start + 2)
        cancellation.began("tv.plex.htpc", at: start + 5)
        #expect(cancellation.shouldReturn(activated: "tv.plex.htpc", at: start + 8) == false)
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

/// Chromium web app tiles (M7 L18, L23).
struct WebAppTests {
    private func makeBundle(_ plist: [String: Any]) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory.appending(path: "WebAppTests-\(UUID().uuidString)/Meet.app")
        let contents = bundle.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }

    @Test func readsAWebAppShim() throws {
        let bundle = try makeBundle([
            "CFBundleIdentifier": "com.brave.Browser.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
            "CrAppModeShortcutID": "kjgfgldnnfoeklkmfkjfagphfepbbdan",
            "CrAppModeShortcutName": "Google Meet",
            "CrAppModeShortcutURL": "https://meet.google.com/landing?lfhs=2",
            "CrBundleIdentifier": "com.brave.Browser",
        ])
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        #expect(WebApp.info(bundleURL: bundle) == WebAppInfo(
            appID: "kjgfgldnnfoeklkmfkjfagphfepbbdan", name: "Google Meet",
            startURL: URL(string: "https://meet.google.com/landing?lfhs=2"), browserBundleID: "com.brave.Browser"))
    }

    @Test func aNormalAppIsNoWebApp() throws {
        let bundle = try makeBundle(["CFBundleIdentifier": "tv.plex.htpc", "CFBundleName": "Plex HTPC"])
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        #expect(WebApp.info(bundleURL: bundle) == nil)
        #expect(WebApp.info(bundleURL: URL(fileURLWithPath: "/nonexistent/App.app")) == nil)
    }

    @Test func launchArguments() {
        let url = URL(string: "https://meet.google.com/home?calling=1")!
        #expect(WebApp.launchArguments(appID: "kjg", startURL: url)
            == ["--app-id=kjg", "--app-launch-url-for-shortcuts-menu-item=https://meet.google.com/home?calling=1"])
    }

    @Test func handoffBoundaries() {
        let launch = Date(timeIntervalSince1970: 1000)
        #expect(WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch + 0.3))
        #expect(WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch + 5))
        #expect(!WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch + 5.1))
        #expect(!WebAppHandoff.isHandoff(launchedAt: launch, quitAt: launch - 1))
    }
}
