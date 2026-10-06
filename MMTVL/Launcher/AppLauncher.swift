import AppKit
import os

/// Launches external apps and URLs (D13) and brings the launcher back when an app it launched quits.
final class AppLauncher {
    enum LaunchError: Error {
        case notInstalled(bundleID: String)
        case unsupportedKind
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppLauncher")

    /// Called when an app we launched quits and nothing else took the foreground (L5).
    var onReturnToLauncher: (() -> Void)?

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
    private var iconCache: [URL: NSImage] = [:]
    private var terminationObserver: NSObjectProtocol?

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

    func launch(_ item: LaunchItem) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        switch item.kind {
        case .application(let bundleID):
            guard let url = appURL(for: bundleID) else {
                throw LaunchError.notInstalled(bundleID: bundleID)
            }
            Self.logger.info("Launching \(bundleID, privacy: .public)")
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            launchedPIDs.insert(app.processIdentifier)
            makeFullScreenIfWanted(item, pid: app.processIdentifier)

        case .defaultBrowser(let fullScreen):
            guard let browserURL = defaultBrowserURL() else {
                throw LaunchError.notInstalled(bundleID: "default browser")
            }
            let bundleID = Bundle(url: browserURL)?.bundleIdentifier
            configuration.arguments = Self.launchArguments(browserBundleID: bundleID, fullScreen: fullScreen)
            Self.logger.info("Launching default browser \(bundleID ?? "?", privacy: .public) with \(configuration.arguments, privacy: .public)")
            let app = try await NSWorkspace.shared.openApplication(at: browserURL, configuration: configuration)
            launchedPIDs.insert(app.processIdentifier)
            makeFullScreenIfWanted(item, pid: app.processIdentifier)

        case .url(let url, let browserBundleID?):
            guard let browserURL = appURL(for: browserBundleID) else {
                throw LaunchError.notInstalled(bundleID: browserBundleID)
            }
            Self.logger.info("Opening \(url.absoluteString, privacy: .public) in \(browserBundleID, privacy: .public)")
            let app = try await NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: configuration)
            launchedPIDs.insert(app.processIdentifier)

        case .url(let url, nil):
            Self.logger.info("Opening \(url.absoluteString, privacy: .public) in the default browser")
            NSWorkspace.shared.open(url)

        case .internalDestination, .system:
            throw LaunchError.unsupportedKind
        }
    }

    /// D15: also covers apps that were already running, where `--start-fullscreen` has no effect.
    private func makeFullScreenIfWanted(_ item: LaunchItem, pid: pid_t) {
        guard item.wantsFullScreen && AccessibilityPermission.isTrusted else { return }
        Task { await fullScreener.makeFullScreen(pid: pid) }
    }

    private func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func defaultBrowserURL() -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
    }

    private func applicationDidTerminate(pid: pid_t) {
        guard launchedPIDs.remove(pid) != nil else { return }

        // L5: only come back if the user hasn't deliberately switched to another app.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isOurs = frontmost == nil
            || frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            || frontmost?.processIdentifier == pid
        guard isOurs else {
            Self.logger.info("Launched app \(pid) quit, but \(frontmost?.bundleIdentifier ?? "?", privacy: .public) is frontmost; staying put")
            return
        }
        Self.logger.info("Launched app \(pid) quit; returning to launcher")
        onReturnToLauncher?()
    }
}
