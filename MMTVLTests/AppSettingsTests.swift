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
}
