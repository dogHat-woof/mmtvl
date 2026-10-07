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

    /// M7 L18: full screen for one window (a browser window showing a web app). Polls like `makeFullScreen(pid:)`.
    func makeFullScreen(window: AXUIElement, timeout: Duration = .seconds(5)) async {
        guard AccessibilityPermission.isTrusted else { return }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if Self.isFullScreen(window) { return }
            AXUIElementSetAttributeValue(window, Self.fullScreenAttribute as CFString, true as CFBoolean)
            try? await Task.sleep(for: .milliseconds(300))
        }
        Self.logger.error("Gave up making a web app window full screen after \(timeout, privacy: .public)")
    }

    /// M7 L18: the app's first window whose title begins with `titlePrefix`.
    func findWindow(pid: pid_t, titlePrefix: String) -> AXUIElement? {
        guard AccessibilityPermission.isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        let windows: [AXUIElement] = Self.copyAttribute(app, kAXWindowsAttribute) ?? []
        return windows.first { window in
            let title: String? = Self.copyAttribute(window, kAXTitleAttribute)
            return title?.hasPrefix(titlePrefix) == true
        }
    }

    /// M7 L18: whether the app shows a window. Without Accessibility it can't tell and answers true.
    func hasWindow(pid: pid_t) -> Bool {
        guard AccessibilityPermission.isTrusted else { return true }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return Self.mainWindow(of: app) != nil
    }

    /// M7b L21: presses the close button of every window of the app at least `minimumSize` big.
    /// Returns how many it pressed (0 without Accessibility).
    func closeWindows(pid: pid_t, minimumSize: CGSize) -> Int {
        guard AccessibilityPermission.isTrusted else { return 0 }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        let windows: [AXUIElement] = Self.copyAttribute(app, kAXWindowsAttribute) ?? []
        var pressed = 0
        for window in windows {
            guard let size = Self.size(of: window),
                  size.width >= minimumSize.width, size.height >= minimumSize.height,
                  let button: AXUIElement = Self.copyAttribute(window, kAXCloseButtonAttribute)
            else { continue }
            if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success { pressed += 1 }
        }
        return pressed
    }

    private static func size(of window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        // The type ID was checked above.
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
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
