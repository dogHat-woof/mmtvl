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
    private var plex: PlexAccount?
    private var liveTV: LiveTVModel?
    private var settings = AppSettings()
    private var settingsFile: JSONConfigFile<AppSettings>?
    private var bindingsFile: JSONConfigFile<[InputBinding]>?
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
    private var appActivationObserver: NSObjectProtocol?
    private var castReceiver: CastReceiver?
    /// M7b D31: the phone trackpad.
    private let phonePointer = PhonePointer()
    /// M7b D32: Android screen mirroring through Reflector.
    private var reflector: ReflectorMonitor?
    /// M7b L15: the last AirPlay probe; refreshed when Settings → Casting opens.
    private var airPlayState: AirPlayReceiverState = .unknown
    /// M7c L9: set by the PIN-checked quit, Relaunch and a logout/shutdown; otherwise the kiosk lock cancels a quit.
    private var allowsTermination = false
    /// M7c L8b: takes the screen back from apps MMTVL didn't open.
    private let kioskGuard = KioskGuard()
    private var powerOffObserver: NSObjectProtocol?
    /// M7c L16: the displays or the system went to sleep; the Live TV preview stops.
    private var screensSleepObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }

        let directory = LaunchItemStore.defaultDirectory
        let settingsFile = JSONConfigFile(url: directory.appending(path: AppSettings.fileName), defaultValue: AppSettings())
        self.settingsFile = settingsFile
        settings = settingsFile.load()
        if settings.castDeviceID == nil {
            // M7b L3: the DIAL device uuid, made once.
            settings.castDeviceID = UUID().uuidString.lowercased()
            do {
                try settingsFile.save(settings)
            } catch {
                Self.logger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
            }
        }
        let bindingsFile = JSONConfigFile(url: directory.appending(path: KeyBindings.fileName),
                                          defaultValue: KeyBindings.defaultBindings)
        self.bindingsFile = bindingsFile
        let bindings = migrateBindings(KeyBindings(bindingsFile.load()))
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
        let plex = PlexAccount(network: .live,
                               configFile: JSONConfigFile(url: directory.appending(path: PlexConfig.fileName),
                                                          defaultValue: PlexConfig()),
                               tokens: .keychain)
        self.plex = plex
        let settingsModel = SettingsModel(settings: settings, items: items, environment: makeSettingsEnvironment(kiosk: kiosk),
                                          bindings: bindings)
        let youtube = YouTubeController(userAgent: YouTubeConfig.userAgent(override: settings.youtubeUserAgent),
                                        castEnabled: settings.youtubeCastEnabled)
        self.youtube = youtube
        let liveTV = LiveTVModel(player: MPVPlayerController(), makePlayer: { MPVPlayerController() }, library: iptvLibrary)
        liveTV.channelUpMovesUpList = settings.channelUpMovesUpList
        self.liveTV = liveTV
        var liveShelf = LiveShelfSource.library(iptvLibrary)
        liveShelf.defaultChannel = { [weak liveTV] in liveTV?.defaultPreviewChannelID }
        // M7c L24.
        liveTV.prefetchLogos = { ChannelLogoCache.shared.prefetch($0) }
        liveTV.prefetchStreams = { StreamResolver.shared.prefetch($0) }
        // M7c L30: the loopback relay mpv loads Live TV through.
        HLSRelay.shared.start()
        // M7c L31: a channel highlighted in the guide starts loading before Select.
        liveTV.warmStream = { url in
            Task { HLSRelay.shared.prefetch(await StreamResolver.shared.resolve(url)) }
        }
        ChannelLogoCache.shared.pruneDisk()
        let topShelf = TopShelfModel(live: liveShelf, plex: plex)
        let router = AppRouter(items: items, launcher: launcher, settings: settingsModel, youtube: youtube,
                               liveTV: liveTV, pinStore: .keychain, tileArt: TileArtStore(), topShelf: topShelf)
        topShelf.onChange = { [weak router] in router?.shelfContentChanged() }
        let windowController = KioskWindowController(
            rootView: LauncherRootView(router: router, youtube: youtube, liveTV: liveTV),
            hidesCursor: settings.cursorAutoHide
        )
        self.inputRouter = inputRouter
        self.router = router
        self.windowController = windowController

        router.onExitToDesktop = { [weak windowController] in windowController?.exitToDesktop() }
        router.onQuit = { [weak self] in
            self?.allowsTermination = true
            // Not from inside applicationShouldTerminate.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        router.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        launcher.onReturnToLauncher = { [weak windowController] in windowController?.show(reason: "appQuit") }
        launcher.onOpened = { [weak self] in self?.kioskGuard.opened(bundleIDs: $0) }
        // Leanback's own exit (Back at its top level); it may fire several times, going home is idempotent.
        // M7c L32: on the start tile, like Home.
        youtube.onExit = { [weak router] in
            if router?.screen == .youtube { router?.goHomeToStartTile() }
        }
        iptvLibrary.onStatusChange = { [weak router] in router?.settings.refreshStatus() }
        plex.onChange = { [weak router] in
            router?.settings.refreshStatus()
            router?.shelfContentChanged()
        }
        // M7b L21: Home on MMTVL also ends a mirroring session.
        inputRouter.handler = { [weak self, weak router] command in
            if command == .home {
                self?.endMirroringIfNeeded()
                self?.kioskGuard.homePressed()
            }
            return router?.handle(command) ?? false
        }
        inputRouter.onScrollWheel = { [weak router] deltaY, precise in router?.scrollWheel(deltaY: deltaY, precise: precise) }
        inputRouter.onGlobalCommand = { [weak self] command in self?.handleGlobal(command) }
        // Reads the current setting, which Settings can change live.
        inputRouter.onCommandDispatched = { [weak self] in
            if self?.settings.cursorAutoHide == true { NSCursor.setHiddenUntilMouseMoves(true) }
            self?.router?.noteActivity()
        }
        router.startTileID = settings.homeStartTile
        router.focusStartTile(id: router.startTileID)
        router.livePreviewEnabled = settings.homeLivePreview
        router.homeVersionLabel = settings.showVersionOnHome ? AppVersion.current.label : nil
        router.homeExitDelay = Theme.homeExitDuration
        router.isAppActive = NSApp.isActive
        observeScreensSleep()
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
            observePowerOff()
        }
        updateKioskLock()
        setUpPhoneRemote(inputRouter: inputRouter, router: router)
        setUpCasting()

        windowController.show(reason: "launch")
        setUpReflector()

        // M4 L4/L5: channels are fetched at every launch; the guide only when stale.
        if iptvLibrary.hasPlaylist {
            Task {
                await iptvLibrary.refreshPlaylist()
                await iptvLibrary.refreshGuideIfStale()
            }
        }
    }

    /// M7 L7: an older `key-bindings.json` gets the defaults of the new commands once (only triggers not bound yet).
    private func migrateBindings(_ bindings: KeyBindings) -> KeyBindings {
        guard settings.keyBindingsRevision < KeyBindings.currentRevision else { return bindings }
        let migrated = bindings.addingDefaults(for: [.menu, .channelUp, .channelDown])
        do {
            try bindingsFile?.save(migrated.bindings)
            settings.keyBindingsRevision = KeyBindings.currentRevision
            try settingsFile?.save(settings)
            Self.logger.info("Added default buttons for Menu and Channel Up/Down")
        } catch {
            Self.logger.error("Failed to save key bindings: \(error.localizedDescription, privacy: .public)")
        }
        return migrated
    }

    /// M5: the phone remote server, its coordinator and the volume routes (D24, D25).
    private func setUpPhoneRemote(inputRouter: InputRouter, router: AppRouter) {
        let volume = VolumeController(
            mode: { [weak self] in self?.settings.volumeMode ?? .auto },
            isLauncherActive: { NSApp.isActive },
            applyAppVolume: { [weak self] volume in
                self?.liveTV?.setAppVolume(volume.level, muted: volume.muted)
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
            makeToken: { PhoneToken.make() },
            pointer: { [weak self] in self?.phonePointer.perform($0) },
            repairForeground: { [weak self] in self?.repairForeground() ?? false }
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

    /// M7c L3: the window shows but MMTVL isn't active and nothing else is in front (after a launched app quit).
    private func repairForeground() -> Bool {
        guard !AppEnvironment.windowedMode, !NSApp.isActive,
              let windowController, windowController.window.isVisible
        else { return false }
        let front = NSWorkspace.shared.frontmostApplication
        guard front == nil || front?.bundleIdentifier == "com.apple.finder"
                || front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        else { return false }
        Task { await windowController.bringForward(reason: "repair") }
        return true
    }

    /// M7b D30: the YouTube DIAL receiver, in kiosk and -windowed mode alike.
    private func setUpCasting() {
        let bridge = CastBridge(
            isAppReady: { [weak self] in self?.youtube?.isDIALReady ?? false },
            forward: { [weak self] request in await self?.youtube?.handleDIAL(request) },
            launch: { [weak self] query in self?.castToTV(query: query) },
            didConnect: { [weak self] in self?.castToTV(query: nil) }
        )
        let receiver = CastReceiver(deviceID: settings.castDeviceID ?? UUID().uuidString.lowercased(),
                                    friendlyName: "MMTVL", bridge: bridge)
        receiver.onStateChange = { [weak self] in self?.router?.settings.refreshStatus() }
        castReceiver = receiver
        if settings.youtubeCastEnabled { receiver.start() }
    }

    /// M7b L4: a cast takes over the TV from any screen or app, without the PIN.
    private func castToTV(query: String?) {
        endMirroringIfNeeded()
        launcher.homePressed()
        router?.castYouTube(query: query)
        windowController?.show(reason: "cast")
    }

    /// M7b D32, L18–L22: keep Reflector running hidden and follow its mirroring sessions.
    private func setUpReflector() {
        let reflector = ReflectorMonitor(autoStart: settings.reflectorAutoStart)
        reflector.onSessionBegan = { [weak self] in
            // L20: leave Live TV/YouTube like Home (no PIN), then bring the mirrored screen forward.
            guard let self else { return }
            launcher.homePressed()
            router?.goHome()
            NSRunningApplication.runningApplications(withBundleIdentifier: ReflectorMonitor.bundleID).first?.activate()
        }
        reflector.onSessionEnded = { [weak self] in
            // L22: back to the home screen unless the user switched to another app on purpose.
            let front = NSWorkspace.shared.frontmostApplication
            guard front == nil || front?.bundleIdentifier == ReflectorMonitor.bundleID
                    || front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            else { return }
            self?.router?.goHome()
            self?.windowController?.show(reason: "mirroringEnded")
        }
        reflector.onStatusChange = { [weak self] in self?.router?.settings.refreshStatus() }
        self.reflector = reflector
        reflector.start()
    }

    /// L21: Home or a YouTube cast during mirroring ends it first.
    private func endMirroringIfNeeded() {
        guard let reflector, reflector.isMirroring else { return }
        reflector.endMirroring()
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
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let isRegular = app?.activationPolicy == .regular
            let isSelf = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                self?.phoneRemote?.frontAppChanged()
                self?.guardActivation(bundleID: bundleID, isRegular: isRegular, isSelf: isSelf)
            }
        }
    }

    /// M7c L8b: an app MMTVL didn't open came forward; take the screen back like Home.
    private func guardActivation(bundleID: String?, isRegular: Bool, isSelf: Bool) {
        kioskGuard.isEnabled = isLockEffective
        guard kioskGuard.appDidActivate(bundleID: bundleID, isRegular: isRegular, isSelf: isSelf) == .takeBack else { return }
        launcher.homePressed()
        router?.goHome()
        windowController?.show(reason: "guard")
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

    /// What Settings → Casting shows (M7b L14, L16).
    private func castingSettingsStatus() -> CastingSettingsStatus {
        var status = CastingSettingsStatus()
        if settings.youtubeCastEnabled {
            status.youtube = switch castReceiver?.state ?? .off {
            case .off: .off
            case .starting: .starting
            case .ready: .ready
            case .failed(let message): .failed(message)
            }
        }
        status.airPlay = airPlayState
        if let reflector, reflector.isInstalled {
            status.reflector = reflector.isMirroring ? .mirroring : reflector.isRunning ? .ready : .notRunning
        }
        let plexHTPC = "tv.plex.htpc"
        if !NSRunningApplication.runningApplications(withBundleIdentifier: plexHTPC).isEmpty {
            status.plexHTPC = .running
        } else if NSWorkspace.shared.urlForApplication(withBundleIdentifier: plexHTPC) != nil {
            status.plexHTPC = .notRunning
        }
        return status
    }

    private func refreshCasting() {
        Task {
            airPlayState = await AirPlayReceiverProbe.check()
            router?.settings.refreshStatus()
        }
    }

    /// What Settings → Plex shows (L15). Never tokens.
    private func plexSettingsStatus() -> PlexSettingsStatus {
        guard let plex else { return PlexSettingsStatus() }
        var status = PlexSettingsStatus()
        status.isSignedIn = plex.isSignedIn
        status.linkCode = plex.linkCode
        status.linkURL = plex.linkCode.map(PlexAPI.linkURL(code:))
        status.serverName = plex.serverName
        status.servers = plex.servers.map { server in
            PlexSettingsStatus.Server(id: server.clientIdentifier, name: server.name,
                                      detail: server.owned == false ? "Shared with you" : "Yours")
        }
        status.statusLine = plex.statusLine
        status.itemCount = plex.continueWatching.count
        status.hasNoServer = plex.status == .noServer && plex.servers.isEmpty
        status.needsServerChoice = plex.status == .noServer && plex.servers.count > 1
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
            overridesFile: JSONConfigFile(url: directory.appending(path: IPTVState.overridesFileName), defaultValue: [String: String]()),
            preferencesFile: JSONConfigFile(url: directory.appending(path: ChannelPreferences.fileName),
                                            defaultValue: ChannelPreferences())
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

        // M6b: one line per guide. Labels may show a guide's file name, never its query (L2).
        status.guideSources = library.guideSources.map { source in
            let info = library.guideSourceInfo[source.id] ?? IPTVLibrary.GuideSourceInfo()
            func summary(_ updated: String) -> String {
                "\(info.programmeCount.formatted()) programmes · \(info.matchedChannels) channels · Updated \(updated)"
            }
            let line = switch info.status {
            case .loading: "Loading…"
            case .failed(let message): "Failed: \(message)"
            case .loaded(let date): summary(time(date))
            case .idle: library.state.guideImports[source.id]
                .map { summary($0.formatted(date: .abbreviated, time: .shortened)) } ?? "Not loaded yet"
            }
            return IPTVSettingsStatus.GuideSourceStatus(id: source.id, label: source.label, line: line,
                                                        isFromPlaylist: source.isFromPlaylist)
        }
        status.customGuideCount = library.customGuideCount
        status.matchedChannelCount = library.matchedChannelCount

        // M6b L5: groups and hidden channels, in playlist order.
        let hiddenGroups = Set(library.preferences.hiddenGroups)
        let counts = Dictionary(grouping: library.channels, by: \.group).mapValues(\.count)
        status.groups = ChannelList.groups(of: library.channels).map { name in
            IPTVSettingsStatus.GroupStatus(name: name, channelCount: counts[name] ?? 0, isHidden: hiddenGroups.contains(name))
        }
        let hiddenChannels = Set(library.preferences.hiddenChannels)
        status.hiddenChannels = library.channels.filter { hiddenChannels.contains($0.id) }.map { channel in
            IPTVSettingsStatus.HiddenChannelStatus(id: channel.id, number: channel.number, name: channel.name, group: channel.group)
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
            switch kind {
            case .playlist:
                Task { await library.setPlaylistURL(url) }
            case .guide:
                switch library.guideAddProblem(url) {
                case .duplicate: return "That guide is already added"
                case .full: return "Up to \(IPTVLibrary.maxGuideSources) guides; remove one first"
                case nil: Task { await library.addGuideURL(url) }
                }
            }
            return nil
        }
    }

    /// A global binding fired while another app is frontmost.
    private func handleGlobal(_ command: RemoteCommand) {
        // Only Home is global by default; ignore others for now.
        guard command == .home else { return }
        // M7b L21: Home during mirroring ends it.
        endMirroringIfNeeded()
        // D18: the other app keeps running. An app still starting won't take the screen back when it's up.
        kioskGuard.homePressed()
        launcher.homePressed()
        router?.goHomeToStartTile()
        windowController?.show(reason: "home")
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
            windowController?.show(reason: "wake")
            eventTap?.ensureEnabled()
            if settings.phoneRemoteEnabled, case .failed = remoteServer?.state {
                startPhoneRemote()
            }
            castReceiver?.restart()
            reflector?.systemDidWake()
        }
    }

    /// M7c L6: the lock applies in kiosk mode with `kioskLock` on and the event tap running (Home must work).
    /// Exit to Desktop turns it off until the next show (`KioskWindowController.isExitedToDesktop`).
    private var lockConfigured: Bool {
        !AppEnvironment.windowedMode && settings.kioskLock && settings.globalInputEnabled && eventTap?.isRunning == true
    }

    private var isLockEffective: Bool {
        lockConfigured && windowController?.isExitedToDesktop != true
    }

    private func updateKioskLock() {
        windowController?.lockOptions = lockConfigured
    }

    /// M7c L16: display sleep and system sleep stop the Live TV preview.
    private func observeScreensSleep() {
        let center = NSWorkspace.shared.notificationCenter
        screensSleepObservers = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.router?.screensDidSleep() }
            }
        }
        // M7c L26: the screen saver stops the Live TV preview; its end counts as activity.
        let distributed = DistributedNotificationCenter.default()
        screensSleepObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.router?.screenSaverDidStart() }
        })
        screensSleepObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.router?.screenSaverDidStop() }
        })
    }

    /// L9: a logout, restart or shutdown may always quit MMTVL.
    private func observePowerOff() {
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.allowsTermination = true }
        }
    }

    /// L9: ⌘Q and the Dock's Quit ask for the PIN while the kiosk lock is on.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !allowsTermination, isLockEffective, let router else { return .terminateNow }
        Self.logger.info("Quit needs the PIN (kiosk lock)")
        router.requestQuit()
        if case .pin(.quit) = router.screen {
            windowController?.show(reason: "quit")
        }
        return .terminateCancel
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
        liveTV?.channelUpMovesUpList = new.channelUpMovesUpList
        if new.phoneRemoteEnabled != old.phoneRemoteEnabled {
            if new.phoneRemoteEnabled {
                startPhoneRemote()
            } else {
                stopPhoneRemote()
            }
        }
        if new.youtubeCastEnabled != old.youtubeCastEnabled {
            if new.youtubeCastEnabled {
                castReceiver?.start()
            } else {
                castReceiver?.stop()
            }
        }
        reflector?.autoStart = new.reflectorAutoStart
        router?.startTileID = new.homeStartTile
        router?.livePreviewEnabled = new.homeLivePreview
        router?.homeVersionLabel = new.showVersionOnHome ? AppVersion.current.label : nil
        updateKioskLock()
        if kiosk && new.launchAtLogin != old.launchAtLogin {
            LoginItem.apply(enabled: new.launchAtLogin)
        }
    }

    /// M7: a Remote Buttons edit applies at once everywhere (`InputRouter.bindings` is read on every event).
    private func applyBindings(_ bindings: KeyBindings) {
        inputRouter?.bindings = bindings
        do {
            try bindingsFile?.save(bindings.bindings)
        } catch {
            Self.logger.error("Failed to save key bindings: \(error.localizedDescription, privacy: .public)")
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
        eventTap.lockActive = { [weak self] in self?.isLockEffective ?? false }
        self.eventTap = eventTap
        if eventTap.start() {
            updateKioskLock()
            return
        }
        if showOnboarding {
            router?.showAccessibilityOnboarding()
        }
        startAccessibilityWait()
    }

    private func requestAccessibility() {
        kioskGuard.openedSystemSettings()
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
                updateKioskLock()
            }
            if router?.screen == .accessibilityOnboarding { router?.goHome() }
            router?.settings.refreshStatus()
            // Come back from System Settings.
            windowController?.show(reason: "accessibilityGranted")
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // L10: e.g. back from granting Accessibility or approving the login item in System Settings.
        router?.settings.refreshStatus()
        router?.isAppActive = true
        windowController?.appDidBecomeActive()
    }

    /// M7c L16: an app launched or Exit to Desktop stops the Live TV preview.
    func applicationDidResignActive(_ notification: Notification) {
        router?.isAppActive = false
        windowController?.appDidResignActive()
    }

    private func makeSettingsEnvironment(kiosk: Bool) -> SettingsEnvironment {
        SettingsEnvironment(
            isKiosk: kiosk,
            version: .current,
            applySettings: { [weak self] in self?.applySettings($0) },
            applyItems: { [weak self] in self?.applyItems($0) },
            isAccessibilityTrusted: { AccessibilityPermission.isTrusted },
            requestAccessibility: { [weak self] in self?.requestAccessibility() },
            loginItemStatus: { LoginItem.status },
            openLoginItemsSettings: { [weak self] in
                self?.kioskGuard.openedSystemSettings()
                LoginItem.openSystemSettings()
            },
            scanInstalledApps: {
                await InstalledApps.scanInBackground(excludingBundleIDs: [Bundle.main.bundleIdentifier ?? ""])
            },
            relaunch: { [weak self] in AppRelauncher.relaunch(allowTermination: { self?.allowsTermination = true }) },
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
            moveGuideSource: { [weak self] id, step in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.moveGuideSource(id, by: step) }
            },
            removeGuideSource: { [weak self] id in
                guard let library = self?.iptvLibrary else { return }
                Task { await library.removeGuideSource(id) }
            },
            setIPTVGroupHidden: { [weak self] name, hidden in self?.iptvLibrary?.setGroupHidden(name, hidden) },
            unhideIPTVChannel: { [weak self] id in self?.iptvLibrary?.setChannelHidden(id, false) },
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
            forgetAllPhones: { [weak self] in self?.phoneRemote?.forgetAll() },
            applyBindings: { [weak self] in self?.applyBindings($0) },
            setButtonLearning: { [weak self] handler in self?.inputRouter?.captureHandler = handler },
            tileArtFileName: { [weak self] in self?.router?.tileArt.customFileName(for: $0) },
            plexStatus: { [weak self] in self?.plexSettingsStatus() ?? PlexSettingsStatus() },
            setPlexLinking: { [weak self] in self?.plex?.setLinking($0) },
            choosePlexServer: { [weak self] id in
                guard let plex = self?.plex else { return }
                Task { await plex.chooseServer(id: id) }
            },
            signOutOfPlex: { [weak self] in self?.plex?.signOut() },
            refreshPlex: { [weak self] in self?.plex?.startRefresh(maxAge: .seconds(120)) },
            webAppInfo: { [launcher] in launcher.webAppInfo(for: $0) },
            pasteURL: { ClipboardURL.parse(NSPasteboard.general.string(forType: .string)) },
            findPictures: {
                await Task.detached { PictureFinder.find(in: PictureFinder.defaultFolders) }.value
            },
            setTilePicture: { [weak self] id, url in
                do {
                    try self?.router?.tileArt.setPicture(from: url, for: id)
                    return nil
                } catch {
                    Self.logger.error("Can't copy tile art: \(error.localizedDescription, privacy: .public)")
                    return "Couldn't copy that picture"
                }
            },
            removeTilePicture: { [weak self] in self?.router?.tileArt.removePicture(for: $0) },
            castingStatus: { [weak self] in self?.castingSettingsStatus() ?? CastingSettingsStatus() },
            refreshCasting: { [weak self] in self?.refreshCasting() },
            openAirPlaySettings: { [weak self] in
                self?.kioskGuard.openedSystemSettings()
                if let url = URL(string: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show(reason: "reopen")
        return true
    }
}
