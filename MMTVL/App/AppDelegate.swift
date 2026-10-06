import AppKit
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppDelegate")

    private let launcher = AppLauncher()
    private var settings = AppSettings()
    private var settingsFile: JSONConfigFile<AppSettings>?
    private var accessibilityWaitTask: Task<Void, Never>?
    private var inputRouter: InputRouter?
    private var router: AppRouter?
    private var windowController: KioskWindowController?
    private var eventTap: GlobalEventTap?
    private var controllers: ControllerInput?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }

        let directory = LaunchItemStore.defaultDirectory
        let settingsFile = JSONConfigFile(url: directory.appending(path: AppSettings.fileName), defaultValue: AppSettings())
        self.settingsFile = settingsFile
        settings = settingsFile.load()
        let bindings = KeyBindings(JSONConfigFile(
            url: directory.appending(path: KeyBindings.fileName),
            defaultValue: KeyBindings.defaultBindings
        ).load())
        let inputRouter = InputRouter(bindings: bindings)
        let kiosk = !AppEnvironment.windowedMode

        let store = LaunchItemStore()
        let storedItems = store.load()
        let items = storedItems.ensuringSettingsTile()
        if items != storedItems {
            do {
                try store.save(items)
            } catch {
                Self.logger.error("Failed to save launch items: \(error.localizedDescription, privacy: .public)")
            }
        }
        let settingsModel = SettingsModel(settings: settings, items: items, environment: makeSettingsEnvironment(kiosk: kiosk))
        let router = AppRouter(items: items, launcher: launcher, settings: settingsModel)
        let windowController = KioskWindowController(
            rootView: LauncherRootView(router: router),
            hidesCursor: settings.cursorAutoHide
        )
        self.inputRouter = inputRouter
        self.router = router
        self.windowController = windowController

        router.onExitToDesktop = { [weak windowController] in windowController?.exitToDesktop() }
        router.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        launcher.onReturnToLauncher = { [weak windowController] in windowController?.show() }
        inputRouter.handler = router.handle
        inputRouter.onGlobalCommand = { [weak self] command in self?.handleGlobal(command) }
        // Reads the current setting, which Settings can change live.
        inputRouter.onCommandDispatched = { [weak self] in
            if self?.settings.cursorAutoHide == true { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        inputRouter.start()

        // L2: global input is off in -windowed mode, so the dev Mac keeps its Home key.
        if kiosk && settings.globalInputEnabled {
            startGlobalInput(showOnboarding: true)
        }
        if settings.controllersEnabled {
            startControllers()
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

    /// Applies a Settings change live (L3) and saves `settings.json`.
    private func applySettings(_ new: AppSettings) {
        let old = settings
        settings = new
        do {
            try settingsFile?.save(new)
        } catch {
            Self.logger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }

        // L8: kiosk-only settings are saved but not applied in -windowed mode.
        let kiosk = !AppEnvironment.windowedMode
        if kiosk && new.globalInputEnabled != old.globalInputEnabled {
            if new.globalInputEnabled {
                startGlobalInput(showOnboarding: false)
            } else {
                eventTap?.stop()
            }
        }
        if new.controllersEnabled != old.controllersEnabled {
            if new.controllersEnabled {
                startControllers()
            } else {
                controllers?.stop()
                controllers = nil
            }
        }
        windowController?.hidesCursor = new.cursorAutoHide
        if kiosk && new.launchAtLogin != old.launchAtLogin {
            LoginItem.apply(enabled: new.launchAtLogin)
        }
    }

    /// Applies a tile edit from Settings and saves `launch-items.json`.
    private func applyItems(_ items: [LaunchItem]) {
        router?.setItems(items)
        do {
            try LaunchItemStore().save(items)
        } catch {
            Self.logger.error("Failed to save launch items: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startControllers() {
        guard let inputRouter, controllers == nil else { return }
        let controllers = ControllerInput(inputRouter: inputRouter, monitorInBackground: !AppEnvironment.windowedMode)
        controllers.start()
        self.controllers = controllers
    }

    /// Starts the event tap; when it can't be created, optionally shows the onboarding (L14) and waits for the grant.
    private func startGlobalInput(showOnboarding: Bool) {
        guard let inputRouter else { return }
        let eventTap = self.eventTap ?? GlobalEventTap(inputRouter: inputRouter)
        self.eventTap = eventTap
        if eventTap.start() { return }
        if showOnboarding {
            router?.showAccessibilityOnboarding()
        }
        startAccessibilityWait()
    }

    private func requestAccessibility() {
        AccessibilityPermission.request()
        startAccessibilityWait()
    }

    /// Idempotent. L7: keeps polling even after "Not now", so a later grant still activates the tap.
    /// Also runs in -windowed mode, so granting from Settings brings MMTVL back; the tap starts in kiosk mode only.
    private func startAccessibilityWait() {
        guard accessibilityWaitTask == nil, !AccessibilityPermission.isTrusted else { return }
        accessibilityWaitTask = Task { [weak self] in
            await AccessibilityPermission.waitUntilTrusted()
            guard let self, AccessibilityPermission.isTrusted else { return }
            accessibilityWaitTask = nil
            if !AppEnvironment.windowedMode && settings.globalInputEnabled {
                if let eventTap {
                    eventTap.start()
                } else {
                    startGlobalInput(showOnboarding: false)
                }
            }
            if router?.screen == .accessibilityOnboarding { router?.goHome() }
            router?.settings.refreshStatus()
            // Come back from System Settings.
            windowController?.show()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // L10: e.g. back from granting Accessibility or approving the login item in System Settings.
        router?.settings.refreshStatus()
    }

    private func makeSettingsEnvironment(kiosk: Bool) -> SettingsEnvironment {
        SettingsEnvironment(
            isKiosk: kiosk,
            versionString: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            applySettings: { [weak self] in self?.applySettings($0) },
            applyItems: { [weak self] in self?.applyItems($0) },
            isAccessibilityTrusted: { AccessibilityPermission.isTrusted },
            requestAccessibility: { [weak self] in self?.requestAccessibility() },
            loginItemStatus: { LoginItem.status },
            openLoginItemsSettings: { LoginItem.openSystemSettings() },
            scanInstalledApps: {
                await InstalledApps.scanInBackground(excludingBundleIDs: [Bundle.main.bundleIdentifier ?? ""])
            },
            relaunch: { AppRelauncher.relaunch() },
            exitToDesktop: { [weak self] in
                self?.router?.goHome()
                self?.windowController?.exitToDesktop()
            },
            tileTitle: { [launcher] in launcher.title(for: $0) },
            isInstalled: { [launcher] in launcher.isInstalled($0) }
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return true
    }
}
