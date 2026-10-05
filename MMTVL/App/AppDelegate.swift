import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let inputRouter = InputRouter()
    private let launcher = AppLauncher()
    private var router: AppRouter?
    private var windowController: KioskWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }

        let items = LaunchItemStore().load()
        let router = AppRouter(items: items, launcher: launcher)
        let windowController = KioskWindowController(rootView: LauncherRootView(router: router))
        self.router = router
        self.windowController = windowController

        router.onExitToDesktop = { [weak windowController] in windowController?.exitToDesktop() }
        launcher.onReturnToLauncher = { [weak windowController] in windowController?.show() }
        inputRouter.handler = router.handle
        inputRouter.start()

        windowController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return true
    }
}
