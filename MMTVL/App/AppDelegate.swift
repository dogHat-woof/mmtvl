import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launcher = AppLauncher()
    private var settings = AppSettings()
    private var inputRouter: InputRouter?
    private var router: AppRouter?
    private var windowController: KioskWindowController?
    private var eventTap: GlobalEventTap?
    private var controllers: ControllerInput?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }

        let directory = LaunchItemStore.defaultDirectory
        settings = JSONConfigFile(url: directory.appending(path: AppSettings.fileName), defaultValue: AppSettings()).load()
        let bindings = KeyBindings(JSONConfigFile(
            url: directory.appending(path: KeyBindings.fileName),
            defaultValue: KeyBindings.defaultBindings
        ).load())
        let inputRouter = InputRouter(bindings: bindings)
        let kiosk = !AppEnvironment.windowedMode

        let items = LaunchItemStore().load()
        let router = AppRouter(items: items, launcher: launcher)
        let windowController = KioskWindowController(
            rootView: LauncherRootView(router: router),
            hidesCursor: settings.cursorAutoHide
        )
        self.inputRouter = inputRouter
        self.router = router
        self.windowController = windowController

        router.onExitToDesktop = { [weak windowController] in windowController?.exitToDesktop() }
        launcher.onReturnToLauncher = { [weak windowController] in windowController?.show() }
        inputRouter.handler = router.handle
        inputRouter.onGlobalCommand = { [weak self] command in self?.handleGlobal(command) }
        let cursorAutoHide = settings.cursorAutoHide
        inputRouter.onCommandDispatched = {
            if cursorAutoHide { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        inputRouter.start()

        // L2: global input is off in -windowed mode, so the dev Mac keeps its Home key.
        if kiosk && settings.globalInputEnabled {
            startGlobalInput(inputRouter: inputRouter, router: router)
        }
        if settings.controllersEnabled {
            let controllers = ControllerInput(inputRouter: inputRouter, monitorInBackground: kiosk)
            controllers.start()
            self.controllers = controllers
        }
        if kiosk {
            LoginItem.apply(enabled: settings.launchAtLogin)
            observeWake()
        }

        windowController.show()
    }

    /// A global binding fired while another app is frontmost.
    private func handleGlobal(_ command: RemoteCommand) {
        // Only Home is global by default; ignore others for now.
        guard command == .home else { return }
        // D18: the other app keeps running.
        router?.goHome()
        windowController?.show()
    }

    /// L9: system wake (not display-only wake) returns to the launcher home screen,
    /// after a delay for the HDMI/AVR re-handshake.
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        }
    }

    private func systemDidWake() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            router?.goHome()
            windowController?.show()
            eventTap?.ensureEnabled()
        }
    }

    /// Starts the event tap, or shows the Accessibility onboarding when it can't be created.
    private func startGlobalInput(inputRouter: InputRouter, router: AppRouter) {
        let eventTap = GlobalEventTap(inputRouter: inputRouter)
        self.eventTap = eventTap
        if eventTap.start() { return }
        router.showAccessibilityOnboarding()
        router.onRequestAccessibility = { AccessibilityPermission.request() }
        // L7: keeps polling even after "Not now", so a later grant still activates the tap.
        Task { [weak self, weak eventTap, weak router] in
            await AccessibilityPermission.waitUntilTrusted()
            guard AccessibilityPermission.isTrusted else { return }
            eventTap?.start()
            if router?.screen == .accessibilityOnboarding { router?.goHome() }
            // Come back from System Settings.
            self?.windowController?.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return true
    }
}
