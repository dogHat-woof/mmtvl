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
