import Foundation

/// M7f L10: web apps that hold a call. They're never reloaded when opened again, since a reload drops the call.
nonisolated enum CallingApps {
    /// Matched exactly or as a subdomain (`us02web.zoom.us`).
    static let hosts: [String] = [
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "teams.cloud.microsoft",
        "zoom.us",
        "zoom.com",
        "webex.com",
        "whereby.com",
        "discord.com",
        "web.whatsapp.com",
        "messenger.com",
        "facetime.apple.com",
        "web.skype.com",
    ]

    static func isCalling(host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
