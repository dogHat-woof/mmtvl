import Foundation
import Testing
@testable import MMTVL

struct AppSettingsTests {
    @Test func emptyObjectDecodesToDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings == AppSettings())
        #expect(settings.globalInputEnabled)
        #expect(settings.controllersEnabled)
        #expect(settings.cursorAutoHide)
        #expect(!settings.launchAtLogin)
    }

    @Test func partialObjectKeepsOtherDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"launchAtLogin": true}"#.utf8))
        var expected = AppSettings()
        expected.launchAtLogin = true
        #expect(settings == expected)
    }

    @Test func youtubeUserAgentIsOptional() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.youtubeUserAgent == nil)
        let encoded = try String(decoding: JSONEncoder().encode(settings), as: UTF8.self)
        #expect(!encoded.contains("youtubeUserAgent"))
    }

    @Test func youtubeUserAgentRoundTrips() throws {
        var settings = AppSettings()
        settings.youtubeUserAgent = "Custom/1.0"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func phoneRemoteDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"launchAtLogin": true}"#.utf8))
        #expect(settings.phoneRemoteEnabled)
        #expect(settings.phoneRemotePort == 8765)
        #expect(settings.phoneRemoteVolume == "auto")
        #expect(settings.volumeMode == .auto)
    }

    @Test func phoneRemoteHandEdits() throws {
        let json = #"{"phoneRemoteVolume": "bogus", "phoneRemotePort": 80, "phoneRemoteEnabled": false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.volumeMode == .auto)
        #expect(settings.validatedPhoneRemotePort == 8765)
        #expect(!settings.phoneRemoteEnabled)

        let custom = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"phoneRemoteVolume": "app", "phoneRemotePort": 9000}"#.utf8))
        #expect(custom.volumeMode == .app)
        #expect(custom.validatedPhoneRemotePort == 9000)
    }
}
