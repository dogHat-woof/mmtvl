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

    private var launchedPIDs: Set<pid_t> = []
    private var iconCache: [String: NSImage] = [:]
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
        case .url, .internalDestination, .system:
            true
        }
    }

    func icon(for item: LaunchItem) -> NSImage? {
        guard case .application(let bundleID) = item.kind else { return nil }
        if let cached = iconCache[bundleID] { return cached }
        guard let url = appURL(for: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
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

    private func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
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
