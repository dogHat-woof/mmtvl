import Testing
@testable import MMTVL

struct AppRelauncherTests {
    @Test func buildsShellArguments() {
        #expect(AppRelauncher.processArguments(pid: 42, appPath: "/A.app", arguments: ["-windowed", "YES"])
            == ["-c", AppRelauncher.script, "sh", "42", "/A.app", "-windowed", "YES"])
    }
}
