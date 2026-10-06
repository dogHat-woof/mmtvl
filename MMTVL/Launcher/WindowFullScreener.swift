import AppKit
import ApplicationServices
import os

/// Puts another app's main window into full screen through the Accessibility API (D15).
final class WindowFullScreener {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "WindowFullScreener")
    private static let fullScreenAttribute = "AXFullScreen"

    /// Polls every 300 ms until the app's main window reports AXFullScreen == true, or the timeout passes.
    /// No-op if not trusted.
    func makeFullScreen(pid: pid_t, timeout: Duration = .seconds(15)) async {
        guard AccessibilityPermission.isTrusted else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline, !Task.isCancelled {
            if let window = Self.mainWindow(of: app) {
                if Self.isFullScreen(window) {
                    Self.logger.info("Window of pid \(pid) is full screen")
                    return
                }
                // `true as CFBoolean` avoids the non-Sendable global `kCFBooleanTrue`.
                AXUIElementSetAttributeValue(window, Self.fullScreenAttribute as CFString, true as CFBoolean)
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        Self.logger.error("Gave up making pid \(pid) full screen after \(timeout, privacy: .public)")
    }

    /// Focused window, else main window, else the first standard window.
    private static func mainWindow(of app: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window: AXUIElement = copyAttribute(app, attribute) {
                return window
            }
        }
        let windows: [AXUIElement] = copyAttribute(app, kAXWindowsAttribute) ?? []
        return windows.first { window in
            let subrole: String? = copyAttribute(window, kAXSubroleAttribute)
            return subrole == kAXStandardWindowSubrole
        }
    }

    private static func isFullScreen(_ window: AXUIElement) -> Bool {
        let value: Bool? = copyAttribute(window, fullScreenAttribute)
        return value ?? false
    }

    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
