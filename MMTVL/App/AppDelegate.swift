import AppKit
import Carbon.HIToolbox
import Network
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "AppDelegate")
    private static let phoneLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")

    private let launcher = AppLauncher()
    private var youtube: YouTubeController?
    private var iptvLibrary: IPTVLibrary?
    private var liveTV: LiveTVModel?
    private var settings = AppSettings()
    private var settingsFile: JSONConfigFile<AppSettings>?
    private var accessibilityWaitTask: Task<Void, Never>?
    private var inputRouter: InputRouter?
    private var router: AppRouter?
    private var windowController: KioskWindowController?
    private var eventTap: GlobalEventTap?
    private var controllers: ControllerInput?
    private var wakeObserver: NSObjectProtocol?
    private var remoteServer: RemoteServer?
    private var phoneRemote: PhoneRemote?
    private var volume: VolumeController?
    private var livePlayer: MPVPlayerController?
    private var appActivationObserver: NSObjectProtocol?

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
        let iptvLibrary = makeIPTVLibrary(directory: directory)
        self.iptvLibrary = iptvLibrary
        let settingsModel = SettingsModel(settings: settings, items: items, environment: makeSettingsEnvironment(kiosk: kiosk))
        let youtube = YouTubeController(userAgent: YouTubeConfig.userAgent(override: settings.youtubeUserAgent))
        self.youtube = youtube
        let livePlayer = MPVPlayerController()
        self.livePlayer = livePlayer
        let liveTV = LiveTVModel(player: livePlayer, library: iptvLibrary)
        self.liveTV = liveTV
        let router = AppRouter(items: items, launcher: launcher, settings: settingsModel, youtube: youtube,
                               liveTV: liveTV, pinStore: .keychain)
        let windowController = KioskWindowController(
            rootView: LauncherRootView(router: router, youtube: youtube, liveTV: liveTV),
            hidesCursor: settings.cursorAutoHide
        )
        self.inputRouter = inputRouter
        self.router = router
        self.windowController = windowController

        router.onExitToDesktop = { [weak windowController] in windowController?.exitToDesktop() }
        router.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        launcher.onReturnToLauncher = { [weak windowController] in windowController?.show() }
        // Leanback's own exit; it may fire several times, going home is idempotent.
        youtube.onExit = { [weak router] in
            if router?.screen == .youtube { router?.goHome() }
        }
        iptvLibrary.onStatusChange = { [weak router] in router?.settings.refreshStatus() }
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
        setUpPhoneRemote(inputRouter: inputRouter, router: router)

        windowController.show()

        // M4 L4/L5: channels are fetched at every launch; the guide only when stale.
        if iptvLibrary.hasPlaylist {
            Task {
                await iptvLibrary.refreshPlaylist()
                await iptvLibrary.refreshGuideIfStale()
            }
        }
    }

    /// M5: the phone remote server, its coordinator and the volume routes (D24, D25).
    private func setUpPhoneRemote(inputRouter: InputRouter, router: AppRouter) {
        let volume = VolumeController(
            mode: { [weak self] in self?.settings.volumeMode ?? .auto },
            isLauncherActive: { NSApp.isActive },
            applyAppVolume: { [weak self] volume in
                self?.livePlayer?.setVolume(volume.level, muted: volume.muted)
                self?.youtube?.setVolume(volume.level, muted: volume.muted)
            }
        )
        self.volume = volume
        let server = RemoteServer()
        let phoneRemote = PhoneRemote(transport: server, store: .keychain, environment: PhoneRemoteEnvironment(
            isLauncherActive: { NSApp.isActive },
            dispatch: { [weak inputRouter] command, isGlobal in inputRouter?.dispatch(command, isGlobal: isGlobal) },
            canPostEvents: { SyntheticInput.canPost },
            postExternal: { key in
                switch key {
                case .key(let code): SyntheticInput.postKey(code)
                case .media(let media): SyntheticInput.postMediaKey(media)
                }
            },
            typeEdit: { edit in
                SyntheticInput.deleteBackward(edit.deletions)
                SyntheticInput.type(edit.insertion)
            },
            postReturn: { SyntheticInput.postKey(CGKeyCode(kVK_Return)) },
            launcherAcceptsText: { [weak router] in router?.screen == .youtube },
            frontAppName: { NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac" },
            volume: { [weak volume] action in volume?.perform(action) ?? .unavailable("Volume can't be changed here") },
            now: { Date() },
            makeCode: { PairingCode.random() },
            makeToken: { PhoneToken.make() }
        ))
        server.onMessage = { [weak phoneRemote] id, data in phoneRemote?.receive(data, from: id) }
        server.onSessionClosed = { [weak phoneRemote] id in phoneRemote?.sessionClosed(id) }
        server.onStateChange = { [weak router] in router?.settings.refreshStatus() }
        phoneRemote.onStatusChange = { [weak router] in router?.settings.refreshStatus() }
        remoteServer = server
        self.phoneRemote = phoneRemote
        if settings.phoneRemoteEnabled { startPhoneRemote() }
        observeAppActivation()
    }

    private func startPhoneRemote() {
        let port = settings.validatedPhoneRemotePort
        guard let httpPort = NWEndpoint.Port(rawValue: UInt16(port)),
              let socketPort = NWEndpoint.Port(rawValue: UInt16(port + 1))
        else { return }
        Self.phoneLogger.info("Phone remote on port \(port)")
        remoteServer?.start(httpPort: httpPort, socketPort: socketPort)
    }

    private func stopPhoneRemote() {
        remoteServer?.stop()
        phoneRemote?.reset()
        Self.phoneLogger.info("Phone remote stopped")
    }

    /// L16: the phone shows which app is in front.
    private func observeAppActivation() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.phoneRemote?.frontAppChanged() }
        }
    }

    /// What Settings → Phone Remote shows.
    private func phoneRemoteSettingsStatus() -> PhoneRemoteSettingsStatus {
        var status = PhoneRemoteSettingsStatus()
        switch remoteServer?.state ?? .stopped {
        case .stopped: break
        case .starting: status.problem = "Starting…"
        case .running: status.isRunning = true
        case .failed(let message): status.problem = message
        }
        if let ip = LocalAddress.primaryIPv4() {
            status.address = "http://\(ip):\(settings.validatedPhoneRemotePort)"
        }
        if let phoneRemote {
            status.pairingCode = phoneRemote.pairing?.code
            if let address = status.address, let code = status.pairingCode {
                status.pairingURL = "\(address)/#pair=\(code)"
            }
            status.lastPairedName = phoneRemote.lastPairedName
            status.pairedCount = phoneRemote.pairedCount
            status.connectedCount = phoneRemote.connectedCount
        }
        status.canControlOtherApps = SyntheticInput.canPost
        return status
    }

    private func makeIPTVLibrary(directory: URL) -> IPTVLibrary {
        var epgStore: EPGStore?
        do {
            epgStore = try EPGStore.open(at: EPGStore.defaultURL)
        } catch {
            Self.logger.error("Guide storage unavailable: \(error.localizedDescription, privacy: .public)")
        }
        return IPTVLibrary(
            sources: .keychain,
            store: epgStore,
            network: .live,
            stateFile: JSONConfigFile(url: directory.appending(path: IPTVState.fileName), defaultValue: IPTVState()),
            overridesFile: JSONConfigFile(url: directory.appending(path: IPTVState.overridesFileName), defaultValue: [String: String]())
        )
    }

    /// What Settings → Live TV shows. Times are time-only; hosts only (L2).
    private func iptvSettingsStatus() -> IPTVSettingsStatus {
        guard let library = iptvLibrary else { return IPTVSettingsStatus() }
        func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

        var status = IPTVSettingsStatus()
        status.hasPlaylist = library.hasPlaylist
        status.playlistHost = library.playlistHost
        status.channelCount = library.channels.count
        switch library.playlistStatus {
        case .idle: status.playlistLine = ""
        case .loading: status.playlistLine = "Loading…"
        case .loaded(let date): status.playlistLine = "Updated \(time(date))"
        case .failed(let message): status.playlistLine = "Failed: \(message)"
        }

        switch library.guideSource {
        case .none: status.guideKind = .none
        case .playlist(let url): status.guideKind = .playlist(url.host() ?? "?")
        case .custom(let url): status.guideKind = .custom(url.host() ?? "?")
        }
        let programmes = "\(library.guideProgrammeCount.formatted()) programmes"
        switch library.guideStatus {
        case .loading:
            status.guideLine = "Loading…"
        case .failed(let message):
            status.guideLine = "Failed: \(message)"
        case .loaded(let date):
            status.guideLine = "\(programmes) · Updated \(time(date))"
        case .idle:
            if case .none = library.guideSource {
                status.guideLine = "No guide"
            } else if let imported = library.state.lastGuideImport {
                status.guideLine = "\(programmes) · Updated \(imported.formatted(date: .abbreviated, time: .shortened))"
            } else {
                status.guideLine = ""
            }
        }
        return status
    }

    /// L2: reads the clipboard on Select. Returns an error message, or nil after starting the save + refresh.
    private func pasteIPTVURL(_ kind: IPTVURLKind) -> String? {
        let text = NSPasteboard.general.string(forType: .string)
        switch ClipboardURL.parse(text) {
        case .failure(let problem):
            return ClipboardURL.message(for: problem)
        case .success(let url):
            Self.logger.info("Pasted a \(kind == .playlist ? "playlist" : "guide", privacy: .public) URL for \(url.host() ?? "?", privacy: .public)")
            guard let library = iptvLibrary else { return nil }
            Task {
                switch kind {
                case .playlist: await library.setPlaylistURL(url)
                case .guide: await library.setGuideURL(url)
                }
            }
            return nil
        }
    }

    /// A global binding fired while another app is frontmost.
    private func handleGlobal(_ command: RemoteCommand) {
        // Only Home is global by default; ignore others for now.
        guard command == .home else { return }
        // D18: the other app keeps running. An app still starting won't take the screen back when it's up.
        launcher.homePressed()
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
            if settings.phoneRemoteEnabled, case .failed = remoteServer?.state {
                startPhoneRemote()
            }
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
        if new.phoneRemoteEnabled != old.phoneRemoteEnabled {
            if new.phoneRemoteEnabled {
                startPhoneRemote()
            } else {
                stopPhoneRemote()
            }
        }
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
        // Harmless when granted; prompts if PostEvent is ever separate from Accessibility (M5).
        SyntheticInput.requestAccess()
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
            isInstalled: { [launcher] in launcher.isInstalled($0) },
            hasPIN: { PINStore.keychain.load() != nil },
            startPINFlow: { [weak self] in self?.router?.requestPIN($0) },
            reloadYouTube: { [weak self] in self?.youtube?.reload() },
            clearYouTubeData: { [weak self] in
                Task { await self?.youtube?.clearData() }
            },
            iptvStatus: { [weak self] in self?.iptvSettingsStatus() ?? IPTVSettingsStatus() },
            pasteIPTVURL: { [weak self] in self?.pasteIPTVURL($0) },
            useIPTVPlaylistGuide: { [weak self] in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.setGuideURL(nil) }
            },
            refreshIPTV: { [weak self] in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.refreshAll() }
            },
            removeIPTVSource: { [weak self] in
                guard let library = self?.iptvLibrary else { return }
                self?.liveTV?.leave()
                Task { await library.removeSource() }
            },
            phoneRemoteStatus: { [weak self] in self?.phoneRemoteSettingsStatus() ?? PhoneRemoteSettingsStatus() },
            setPhonePairing: { [weak self] in self?.phoneRemote?.setPairing($0) },
            forgetAllPhones: { [weak self] in self?.phoneRemote?.forgetAll() }
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return true
    }
}
