import Foundation

enum AppEnvironment {
    /// `-windowed YES` launch argument: run in a normal window without kiosk presentation options.
    static let windowedMode = UserDefaults.standard.bool(forKey: "windowed")

    /// True when the app is only hosting unit tests; it then skips the kiosk window.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
