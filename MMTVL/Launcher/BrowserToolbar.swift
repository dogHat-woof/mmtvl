import AppKit
import ApplicationServices
import os

/// M7c L10: a full-screen browser hides its tabs and address bar until the pointer touches the top edge, which a
/// remote never does. Turns on View → Always Show Toolbar in Full Screen (Chromium, Safari) through Accessibility.
enum BrowserToolbar {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "BrowserToolbar")
    /// Read from Brave on macOS 26 (M7c step 5 spike); Chrome shares the menu. Safari is unverified.
    static let itemTitlePrefix = "Always Show Toolbar in Full Screen"
    static let viewMenuTitle = "View"
    /// A cold launch has no menu bar yet.
    static let retryInterval: Duration = .milliseconds(500)
    static let retryTimeout: Duration = .seconds(5)

    enum Outcome: String { case pressed, alreadyOn, notFound, notTrusted }

    @discardableResult
    static func ensureShown(pid: pid_t) async -> Outcome {
        guard AccessibilityPermission.isTrusted else { return .notTrusted }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        let deadline = ContinuousClock.now + retryTimeout
        var outcome = Outcome.notFound
        while !Task.isCancelled {
            if let item = toolbarItem(of: app) {
                let mark: String? = copyAttribute(item, kAXMenuItemMarkCharAttribute)
                if mark?.isEmpty ?? true {
                    outcome = AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? .pressed : .notFound
                } else {
                    outcome = .alreadyOn
                }
                break
            }
            guard ContinuousClock.now < deadline else { break }
            try? await Task.sleep(for: retryInterval)
        }
        logger.info("Always Show Toolbar in Full Screen for pid \(pid): \(outcome.rawValue, privacy: .public)")
        return outcome
    }

    /// Menu bar → View → its menu → the item whose title begins with `itemTitlePrefix`.
    private static func toolbarItem(of app: AXUIElement) -> AXUIElement? {
        guard let menuBar: AXUIElement = copyAttribute(app, kAXMenuBarAttribute) else { return nil }
        let barItems: [AXUIElement] = copyAttribute(menuBar, kAXChildrenAttribute) ?? []
        guard let view = barItems.first(where: { title(of: $0) == viewMenuTitle }),
              let menu = (copyAttribute(view, kAXChildrenAttribute) as [AXUIElement]?)?.first
        else { return nil }
        let items: [AXUIElement] = copyAttribute(menu, kAXChildrenAttribute) ?? []
        return items.first { title(of: $0)?.hasPrefix(itemTitlePrefix) == true }
    }

    private static func title(of element: AXUIElement) -> String? {
        copyAttribute(element, kAXTitleAttribute)
    }

    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
