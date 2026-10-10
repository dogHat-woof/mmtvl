import AppKit
import os

/// Home pressed while a launched app is still starting: that app must not take the screen when it comes up.
/// Pure; `AppLauncher` feeds it launches, Home presses and activations.
nonisolated struct LaunchCancellation: Sendable {
    /// Plex HTPC can take several seconds to show its window.
    static let window: TimeInterval = 20

    private var launch: (bundleID: String, startedAt: Date)?
    private var cancelled: (bundleID: String, until: Date)?

    /// A new launch replaces any earlier one and its cancellation.
    mutating func began(_ bundleID: String, at date: Date) {
        launch = (bundleID, date)
        cancelled = nil
    }

    /// Returns the cancelled app's bundle ID when Home falls within `window` of a launch.
    mutating func homePressed(at date: Date) -> String? {
        guard let launch, date.timeIntervalSince(launch.startedAt) < Self.window else { return nil }
        cancelled = (launch.bundleID, date + Self.window)
        return launch.bundleID
    }

    /// True when `bundleID` came forward after Home cancelled it; the launcher takes the screen back.
    func shouldReturn(activated bundleID: String?, at date: Date) -> Bool {
        guard let cancelled, let bundleID else { return false }
        return bundleID == cancelled.bundleID && date < cancelled.until
    }
}

/// A Chromium web app (PWA) shim's identity, from its Info.plist (M7 L18, L23).
nonisolated struct WebAppInfo: Equatable, Sendable {
    /// `CrAppModeShortcutID`, the browser's app id.
    var appID: String
    /// `CrAppModeShortcutName`, the window title's start.
    var name: String
    /// `CrAppModeShortcutURL`, the app's own start page.
    var startURL: URL?
    /// `CrBundleIdentifier`, e.g. com.brave.Browser.
    var browserBundleID: String
}

nonisolated enum WebApp {
    /// nil for a bundle that isn't a Chromium web app shim.
    static func info(bundleURL: URL) -> WebAppInfo? {
        let plistURL = bundleURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let appID = plist["CrAppModeShortcutID"] as? String, !appID.isEmpty,
              let browserBundleID = plist["CrBundleIdentifier"] as? String, !browserBundleID.isEmpty
        else { return nil }
        let name = plist["CrAppModeShortcutName"] as? String
            ?? plist["CFBundleName"] as? String ?? appID
        return WebAppInfo(appID: appID, name: name,
                          startURL: (plist["CrAppModeShortcutURL"] as? String).flatMap(URL.init(string:)),
                          browserBundleID: browserBundleID)
    }

    /// L23: Chromium's switches for a web app's shortcut-menu item, used for any page of the app.
    static func launchArguments(appID: String, startURL: URL) -> [String] {
        ["--app-id=\(appID)", "--app-launch-url-for-shortcuts-menu-item=\(startURL.absoluteString)"]
    }
}

/// L18: a web app shim that quits this soon after its launch handed off to the browser.
nonisolated struct WebAppHandoff {
    static let quickQuit: TimeInterval = 5

    static func isHandoff(launchedAt: Date, quitAt: Date) -> Bool {
        let elapsed = quitAt.timeIntervalSince(launchedAt)
        return elapsed >= 0 && elapsed <= quickQuit
    }
}

/// Launches external apps and URLs (D13) and brings the launcher back when an app it launched quits,
/// or when an app comes forward after Home cancelled its launch.
final class AppLauncher {
    enum LaunchError: Error {
        case notInstalled(bundleID: String)
        case unsupportedKind
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppLauncher")

    /// Called when an app we launched quits and nothing else took the foreground (L5).
    var onReturnToLauncher: (() -> Void)?
    /// M7 L18: a web app's window never showed; the router shakes the tile (its id).
    var onLaunchFailed: ((String) -> Void)?
    /// M7c L8b: the bundle ids a launch may bring forward (the app, a web app's browser), before it opens.
    var onOpened: (([String]) -> Void)?

    static let finderBundleID = "com.apple.finder"
    /// Item 20: macOS's full-screen exit animation takes about 0.7 s.
    static let quitSettleDelay: Duration = .seconds(1)

    /// L18: how long to look for a web app's window after a hand-off, and how often.
    static let webAppWindowSearch: Duration = .seconds(10)
    static let webAppWindowPoll: Duration = .milliseconds(300)

    /// Chromium browsers honor `--start-fullscreen`, but only when they aren't already running.
    /// Other browsers (Safari), and already-running ones, get full screen via Accessibility (`WindowFullScreener`).
    nonisolated static let chromiumBundleIDs: Set<String> = [
        "com.brave.Browser",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
    ]

    nonisolated static func launchArguments(browserBundleID: String?, fullScreen: Bool) -> [String] {
        guard fullScreen, let browserBundleID, chromiumBundleIDs.contains(browserBundleID) else { return [] }
        return ["--start-fullscreen"]
    }

    private let fullScreener = WindowFullScreener()
    private var launchedPIDs: Set<pid_t> = []
    /// L18: launched web app shims, to tell a hand-off (a quick quit) from the app closing.
    private var webAppLaunches: [pid_t: (item: LaunchItem, info: WebAppInfo, launchedAt: Date)] = [:]
    private var iconCache: [URL: NSImage] = [:]
    private var terminationObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var cancellation = LaunchCancellation()

    init() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.applicationDidTerminate(pid: pid) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.applicationDidActivate(bundleID: bundleID) }
        }
    }

    /// Any Home press (local or global). Within a few seconds of a launch, the app won't take the screen
    /// when it finishes starting; it keeps running (D18).
    func homePressed() {
        guard let bundleID = cancellation.homePressed(at: Date()) else { return }
        Self.logger.notice("Home during the launch of \(bundleID, privacy: .public); it won't take the screen")
    }

    func isInstalled(_ item: LaunchItem) -> Bool {
        switch item.kind {
        case .application(let bundleID):
            appURL(for: bundleID) != nil
        case .url(_, let browserBundleID?):
            appURL(for: browserBundleID) != nil
        case .defaultBrowser:
            defaultBrowserURL() != nil
        case .url, .internalDestination, .system:
            true
        }
    }

    /// The tile title. The default browser tile shows the browser's own name, e.g. "Brave Browser".
    func title(for item: LaunchItem) -> String {
        guard case .defaultBrowser = item.kind,
              let url = defaultBrowserURL(),
              let bundle = Bundle(url: url),
              let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                  ?? bundle.object(forInfoDictionaryKey: "CFBundleName")) as? String
        else { return item.title }
        return name
    }

    /// The app behind a tile (M7 L24 designed art): its bundle id, or the default browser's.
    func bundleID(for item: LaunchItem) -> String? {
        switch item.kind {
        case .application(let bundleID): bundleID
        case .defaultBrowser: defaultBrowserURL().flatMap { Bundle(url: $0)?.bundleIdentifier }
        case .url(_, let browserBundleID): browserBundleID
        case .internalDestination, .system: nil
        }
    }

    func icon(for item: LaunchItem) -> NSImage? {
        let url: URL?
        switch item.kind {
        case .application(let bundleID): url = appURL(for: bundleID)
        case .defaultBrowser: url = defaultBrowserURL()
        case .url, .internalDestination, .system: url = nil
        }
        guard let url else { return nil }
        return icon(forApplicationAt: url)
    }

    /// Icon of an app bundle (Settings "Add Tile" rows), cached by URL.
    func icon(forApplicationAt url: URL) -> NSImage {
        if let cached = iconCache[url] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[url] = icon
        return icon
    }

    /// M7 L18: the tile's Chromium web app identity; nil for other tiles.
    func webAppInfo(for item: LaunchItem) -> WebAppInfo? {
        guard case .application(let bundleID) = item.kind, let url = appURL(for: bundleID) else { return nil }
        return WebApp.info(bundleURL: url)
    }

    func launch(_ item: LaunchItem) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        switch item.kind {
        case .application(let bundleID):
            guard let url = appURL(for: bundleID) else {
                throw LaunchError.notInstalled(bundleID: bundleID)
            }
            let webApp = WebApp.info(bundleURL: url)
            onOpened?([bundleID] + (webApp.map { [$0.browserBundleID] } ?? []))
            if let webApp, let startURL = item.startURL {
                try await launchWebApp(item, bundleID: bundleID, info: webApp, startURL: startURL)
                return
            }
            Self.logger.notice("Launching \(bundleID, privacy: .public)")
            cancellation.began(bundleID, at: Date())
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            launchedPIDs.insert(app.processIdentifier)
            if let webApp {
                webAppLaunches[app.processIdentifier] = (item, webApp, Date())
            }
            makeFullScreenIfWanted(item, pid: app.processIdentifier)

        case .defaultBrowser(let fullScreen):
            guard let browserURL = defaultBrowserURL() else {
                throw LaunchError.notInstalled(bundleID: "default browser")
            }
            let bundleID = Bundle(url: browserURL)?.bundleIdentifier
            if let bundleID {
                onOpened?([bundleID])
                cancellation.began(bundleID, at: Date())
            }
            configuration.arguments = Self.launchArguments(browserBundleID: bundleID, fullScreen: fullScreen)
            Self.logger.notice("Launching default browser \(bundleID ?? "?", privacy: .public) with \(configuration.arguments, privacy: .public)")
            let app = try await NSWorkspace.shared.openApplication(at: browserURL, configuration: configuration)
            launchedPIDs.insert(app.processIdentifier)
            makeFullScreenIfWanted(item, pid: app.processIdentifier)

        case .url(let url, let browserBundleID?):
            guard let browserURL = appURL(for: browserBundleID) else {
                throw LaunchError.notInstalled(bundleID: browserBundleID)
            }
            Self.logger.notice("Opening \(url.absoluteString, privacy: .public) in \(browserBundleID, privacy: .public)")
            onOpened?([browserBundleID])
            cancellation.began(browserBundleID, at: Date())
            let app = try await NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: configuration)
            launchedPIDs.insert(app.processIdentifier)
            makeFullScreenIfWanted(item, pid: app.processIdentifier)

        case .url(let url, nil):
            Self.logger.notice("Opening \(url.absoluteString, privacy: .public) in the default browser")
            if let browserID = defaultBrowserURL().flatMap({ Bundle(url: $0)?.bundleIdentifier }) { onOpened?([browserID]) }
            NSWorkspace.shared.open(url)

        case .internalDestination, .system:
            throw LaunchError.unsupportedKind
        }
    }

    /// L23: the browser opens the web app on `startURL` through a short-lived forwarding instance (not tracked);
    /// then the web app's own window is looked for as after a hand-off (L18).
    private func launchWebApp(_ item: LaunchItem, bundleID: String, info: WebAppInfo, startURL: URL) async throws {
        guard let browserURL = appURL(for: info.browserBundleID) else {
            throw LaunchError.notInstalled(bundleID: info.browserBundleID)
        }
        Self.logger.notice("Launching web app \(bundleID, privacy: .public) on a page at \(startURL.host() ?? "?", privacy: .public)")
        // Home during the launch cancels the web app coming forward, not the browser.
        cancellation.began(bundleID, at: Date())
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = WebApp.launchArguments(appID: info.appID, startURL: startURL)
        _ = try await NSWorkspace.shared.openApplication(at: browserURL, configuration: configuration)
        Task { await findWebAppWindow(item, bundleID: bundleID, info: info, excluding: nil) }
    }

    /// L18: up to 10 s, a running shim with a window (tracked), else a browser window titled with the app's name.
    /// Nothing: the tile shakes.
    private func findWebAppWindow(_ item: LaunchItem, bundleID: String, info: WebAppInfo, excluding deadPID: pid_t?) async {
        let deadline = ContinuousClock.now + Self.webAppWindowSearch
        while ContinuousClock.now < deadline {
            let shims = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != deadPID && !$0.isTerminated }
            if let shim = shims.first(where: { fullScreener.hasWindow(pid: $0.processIdentifier) }) {
                Self.logger.notice("Web app \(bundleID, privacy: .public) is open")
                launchedPIDs.insert(shim.processIdentifier)
                makeFullScreenIfWanted(item, pid: shim.processIdentifier)
                return
            }
            for browser in NSRunningApplication.runningApplications(withBundleIdentifier: info.browserBundleID) {
                if let window = fullScreener.findWindow(pid: browser.processIdentifier, titlePrefix: info.name) {
                    Self.logger.notice("Web app \(bundleID, privacy: .public) opened in a browser window")
                    if item.wantsFullScreen { await fullScreener.makeFullScreen(window: window) }
                    return
                }
            }
            try? await Task.sleep(for: Self.webAppWindowPoll)
        }
        Self.logger.error("Web app \(bundleID, privacy: .public) didn't open; check the browser")
        onLaunchFailed?(item.id)
    }

    /// D15: also covers apps that were already running, where `--start-fullscreen` has no effect.
    /// M7c L10: browser tiles (not web apps) also get View → Always Show Toolbar in Full Screen.
    private func makeFullScreenIfWanted(_ item: LaunchItem, pid: pid_t) {
        guard item.wantsFullScreen && AccessibilityPermission.isTrusted else { return }
        let isBrowserTile = switch item.kind {
        case .defaultBrowser, .url: true
        case .application, .internalDestination, .system: false
        }
        Task {
            await fullScreener.makeFullScreen(pid: pid)
            if isBrowserTile { await BrowserToolbar.ensureShown(pid: pid) }
        }
    }

    private func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func defaultBrowserURL() -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
    }

    private func applicationDidActivate(bundleID: String?) {
        guard cancellation.shouldReturn(activated: bundleID, at: Date()) else { return }
        Self.logger.notice("\(bundleID ?? "?", privacy: .public) came forward after Home; returning to the launcher")
        onReturnToLauncher?()
    }

    private func applicationDidTerminate(pid: pid_t) {
        if let webApp = webAppLaunches.removeValue(forKey: pid),
           WebAppHandoff.isHandoff(launchedAt: webApp.launchedAt, quitAt: Date()),
           case .application(let bundleID) = webApp.item.kind {
            // L18: the shim handed off to the browser; the app isn't closed. Look for its window instead.
            launchedPIDs.remove(pid)
            Self.logger.notice("Web app \(bundleID, privacy: .public) handed off to the browser; looking for its window")
            Task { await findWebAppWindow(webApp.item, bundleID: bundleID, info: webApp.info, excluding: pid) }
            return
        }
        guard launchedPIDs.remove(pid) != nil else { return }

        // L5: only come back if the user hasn't deliberately switched to another app. M7c: macOS makes Finder
        // frontmost when a full-screen app quits, which isn't the user's choice.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isOurs = frontmost == nil
            || frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            || frontmost?.processIdentifier == pid
            || frontmost?.bundleIdentifier == Self.finderBundleID
        guard isOurs else {
            Self.logger.notice("Launched app \(pid) quit, but \(frontmost?.bundleIdentifier ?? "?", privacy: .public) is frontmost; staying put")
            return
        }
        Self.logger.notice("Launched app \(pid) quit; returning to launcher")
        // Item 20: let macOS finish closing a full-screen app's Space first; activating MMTVL (and setting its
        // presentation options) during that animation left the Dock stuck on the dead Space.
        Task { [weak self] in
            try? await Task.sleep(for: Self.quitSettleDelay)
            self?.onReturnToLauncher?()
        }
    }
}
