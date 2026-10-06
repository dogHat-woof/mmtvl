import AppKit
import ApplicationServices

/// The Accessibility (TCC) grant needed by the global event tap (D4) and AX full screen (D15).
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (adds MMTVL to the Accessibility list) and opens the Privacy pane.
    static func request() {
        // The string literal avoids the non-Sendable global `kAXTrustedCheckOptionPrompt`.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Polls once a second until trusted or cancelled.
    static func waitUntilTrusted() async {
        while !isTrusted && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
