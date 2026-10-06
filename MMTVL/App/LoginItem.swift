import ServiceManagement
import os

/// Applies `settings.json` → `launchAtLogin` (L10). Kiosk mode only.
enum LoginItem {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "LoginItem")

    static func apply(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled && service.status != .enabled {
                try service.register()
            } else if !enabled && service.status == .enabled {
                try service.unregister()
            }
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister", privacy: .public) login item: \(error.localizedDescription, privacy: .public)")
        }

        let status = service.status
        logger.info("Login item status: \(describe(status), privacy: .public)")
        if status == .requiresApproval {
            logger.info("Approve MMTVL in System Settings → General → Login Items")
        }
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }
}
