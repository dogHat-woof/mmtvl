import Foundation
import os

/// M7h D43: the Siri Remote. Owns the HID reader, the gesture state machine and the touch surface, and routes per L3:
/// learning capture → the button's binding → volume and power (from any app, `onVolume` / `onPower`) →
/// `ExternalRouter` (MMTVL in front, Home, else a synthetic key for the app in front).
/// Siri Remote bindings act from any app, whatever their `isGlobal` (L2). Touch (L6, L7): swipes step like the
/// clickpad's directions (through the same L3 routing) in normal mode, only with `swipesEnabled` (step 13e; off, touches
/// do nothing outside trackpad mode); trackpad mode moves the pointer, scrolls and
/// clicks (centre short = left, long = right, L4) through the phone's `PhonePointer`; Home leaves it (L5).
final class SiriRemoteInput {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "SiriRemote")

    /// Volume Up/Down and Mute (D44): `AppDelegate` sends them to `VolumeController` with the L8 toast. Seized, the
    /// remote's volume buttons never arrive here (step 1; they reach the event tap, L3a); unseized they do.
    var onVolume: (VolumeAction) -> Void = { action in
        SiriRemoteInput.logger.info("Siri Remote volume \(action.rawValue, privacy: .public) (not wired)")
    }
    /// `power` and `powerMenu` (D45): `PowerMenuPresenter.handle` (step 12).
    var onPower: (RemoteCommand) -> Void = { command in
        SiriRemoteInput.logger.info("Siri Remote \(command.rawValue, privacy: .public) (not wired yet)")
    }

    /// L5: Siri double-press toggles it, Home leaves it (and stopping the remote), with the L8 toast.
    private(set) var isTrackpadMode = false
    /// Step 13e: `settings.json` `siriRemoteSwipes` (default off). Off: touches outside trackpad mode do nothing.
    var swipesEnabled = false {
        didSet { if !swipesEnabled { swipes.cancelTouch() } }
    }
    /// Trackpad mode turned on or off (L7: cursor auto-hide is off while it's on).
    var onTrackpadModeChange: (Bool) -> Void = { _ in }
    /// M7h step 11 (QA major): the remote connected or disconnected (`SiriRemoteHID.onConnectionChange`).
    var onConnectionChange: () -> Void = {}
    var isRunning: Bool { hid.isRunning }
    var isConnected: Bool { hid.isConnected }
    /// M7h step 11 (Settings → Siri Remote → Status): MultitouchSupport loaded and, while the remote is connected,
    /// its touch surface is in use.
    var isTouchAvailable: Bool {
        guard let touch, touch.isAvailable else { return false }
        return !isConnected || touch.surfaceCount > 0
    }
    /// How many times the Accessibility notice was logged: once per run of the remote (`start()` resets it).
    private(set) var accessibilityNotices = 0
    /// How many times a pointer action was refused for the app in front (security M1): once per front-app change.
    private(set) var pointerBlockedNotices = 0

    private let inputRouter: InputRouter
    private let externalRouter: ExternalRouter
    private let hid: SiriRemoteHID
    private let touch: MultitouchDevices?
    /// Trackpad mode's moves, scrolls and clicks (`PhonePointer.perform`), only when MMTVL may post events.
    private let pointer: (PointerAction) -> Void
    /// Security M1: whether the pointer may act in the app in front (`KioskGuard.pointerGate`).
    private let pointerGate: () -> KioskGuard.PointerGate
    /// Step 13e (c): shows the pointer (`NSCursor.setHiddenUntilMouseMoves(false)` and `PhonePointer.reveal`); called
    /// only when MMTVL may post events and the gate allows, like `pointer`.
    private let revealPointer: () -> Void
    private let now: () -> TimeInterval
    private var gestures = SiriRemoteGestures()
    private var swipes = SwipeRecognizer()
    private var trackpad = TrackpadMapper()
    /// Step 13e (c): when trackpad mode reveals the pointer, and the task that waits for it.
    private var reveal = PointerReveal()
    private var revealTask: Task<Void, Never>?
    /// Buttons whose press went to Settings' learning; their release is dropped.
    private var captured: Set<SiriRemoteButton> = []
    private var tickTask: Task<Void, Never>?
    /// The Accessibility notice is logged once per run of the remote, not per press.
    private var loggedNeedsAccessibility = false
    /// The app in front the last refused pointer action was for; nil after an allowed one.
    private var blockedFrontApp: String?

    /// The clickpad: its presses pause swipes (L6).
    private static let clickpadButtons: Set<SiriRemoteButton> = [.up, .down, .left, .right, .select]

    /// `touch`: nil reads no touch surface (tests). Frames' timestamps are on `now`'s clock (`systemUptime`).
    init(inputRouter: InputRouter, externalRouter: ExternalRouter,
         hid: SiriRemoteHID = SiriRemoteHID(),
         touch: MultitouchDevices? = MultitouchDevices(),
         pointer: @escaping (PointerAction) -> Void = { _ in },
         pointerGate: @escaping () -> KioskGuard.PointerGate = { .allowed },
         revealPointer: @escaping () -> Void = {},
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.inputRouter = inputRouter
        self.hid = hid
        self.touch = touch
        self.pointer = pointer
        self.pointerGate = pointerGate
        self.revealPointer = revealPointer
        self.externalRouter = externalRouter
        self.now = now
        hid.onButton = { [weak self] in self?.handle($0) }
        hid.onConnectionChange = { [weak self] in self?.onConnectionChange() }
        touch?.onFrame = { [weak self] in self?.touched($0) }
        touch?.onReset = { [weak self] in self?.touchSurfacesReset() }
    }

    func start() {
        loggedNeedsAccessibility = false
        hid.start()
        touch?.start()
    }

    func stop() {
        hid.stop()   // releases held buttons through `handle`
        touch?.stop()
        gestures.cancelAll()
        swipes.reset()
        trackpad = TrackpadMapper()
        captured.removeAll()
        stopTicks()
        // A stopped remote can't turn it off again (and auto-hide would stay off).
        if isTrackpadMode { setTrackpadMode(false) }
        // Step 13e (c): no lift frame comes after a stop (trackpad mode is off, so nothing is revealed).
        reveal.touchesReset(at: now())
        syncRevealTask()
    }

    /// The touch surfaces stopped or were rebuilt (sleep, wake, the remote connecting or idling off): no lift
    /// frame comes for a touch in progress, so its last position is stale. Click state stays.
    func touchSurfacesReset() {
        swipes.cancelTouch()
        trackpad.reset()
        // Step 13e (c): counts as a lift (in trackpad mode, the pointer is revealed).
        reveal.touchesReset(at: now())
        syncRevealTask()
    }

    /// A frame from the remote's touch surface (L6, L7).
    func touched(_ frame: TouchFrame) {
        // Step 13e (c): in both modes, so trackpad mode turning on knows whether a finger is down.
        reveal.touch(isTouching: frame.isTouching && frame.hasValidPosition, at: now())
        syncRevealTask()
        if isTrackpadMode {
            let actions = trackpad.feed(frame)
            if let start = trackpad.touchStart, let role = trackpad.role { logTouchStart(start, role) }
            for action in actions { post(action) }
        } else if swipesEnabled {
            for command in swipes.feed(frame) { route(command, isRepeat: false) }
        }
    }

    private func handle(_ event: SiriRemoteHID.ButtonEvent) {
        let time = now()
        if event.isSiri {
            // L2: Siri is reserved, never captured or bound; only its press counts.
            guard event.pressed, !event.synthesized else { return }
            perform(gestures.siriPressed(at: time))
            return
        }
        guard let button = event.button else { return }
        // L6: clicking moves the finger a little; no swipe steps or pointer moves around a click (captured presses too).
        if Self.clickpadButtons.contains(button) {
            if event.pressed {
                swipes.clickpadPressed(at: time)
                trackpad.clickpadPressed(at: time)
            } else {
                swipes.clickpadReleased(at: time)
                trackpad.clickpadReleased(at: time)
            }
        }
        if !event.pressed {
            if captured.remove(button) != nil { return }
            if event.synthesized {
                gestures.cancel(button)
            } else {
                perform(gestures.release(button, at: time))
            }
            updateTicks()
            return
        }
        // M7 L8: Settings is learning a button.
        if inputRouter.capture(.siriRemote(button: button)) {
            captured.insert(button)
            return
        }
        let command = inputRouter.bindings.binding(siriRemote: button)?.command
        perform(gestures.press(button, command: command, at: time))
        updateTicks()
    }

    private func perform(_ events: [SiriRemoteGestures.Event]) {
        for event in events {
            switch event {
            case .command(let command, let isRepeat):
                route(command, isRepeat: isRepeat)
            case .toggleTrackpad:
                setTrackpadMode(!isTrackpadMode)
            case .click(let button):
                // L4, L7: at the pointer, through PhonePointer (ClickCounter makes double-clicks).
                Self.logger.debug("Trackpad \(button.rawValue, privacy: .public) click")
                post(.click(button))
            }
        }
    }

    /// L5: on or off, with the toast and the log line.
    private func setTrackpadMode(_ on: Bool) {
        guard on != isTrackpadMode else { return }
        isTrackpadMode = on
        gestures.isTrackpadMode = on
        // A touch in progress starts over in the new mode.
        swipes.cancelTouch()
        trackpad.reset()
        Self.logger.notice("Trackpad mode \(on ? "on" : "off", privacy: .public)")
        OverlayToast.shared.show(on ? "Trackpad On" : "Trackpad Off", symbol: "cursorarrow.motionlines")
        onTrackpadModeChange(on)
        // Step 13e (c): on, the pointer is revealed (after the lift if a finger is down); off, nothing is pending.
        reveal.modeChanged(isOn: on, at: now())
        syncRevealTask()
    }

    // MARK: Revealing the pointer (step 13e (c))

    /// Starts the wait for a pending reveal, or cancels it when none is pending (a touch down, trackpad mode off).
    private func syncRevealTask() {
        guard reveal.isPending else {
            revealTask?.cancel()
            revealTask = nil
            return
        }
        guard revealTask == nil else { return }
        revealTask = Task { [weak self] in
            while !Task.isCancelled, let wait = self?.revealWait() {
                // Security low 2: always sleep a little, so a due reveal that isn't taken can't spin the main actor.
                try? await Task.sleep(for: .seconds(max(wait, PointerReveal.minimumWait)))
                guard !Task.isCancelled, let self else { return }
                if revealIfDue() { return }
            }
        }
    }

    /// Seconds until the pending reveal, at most `liftDelay` per sleep; nil when none is pending.
    private func revealWait() -> TimeInterval? {
        reveal.dueTime.map { min(max(0, $0 - now()), PointerReveal.liftDelay) }
    }

    /// Reveals the pointer if a reveal is due and allowed (`isPointerAllowed`, as every trackpad post); true once
    /// nothing is pending, which ends the wait.
    private func revealIfDue() -> Bool {
        if reveal.takeDue(at: now(), isAllowed: { isPointerAllowed() }) {
            Self.logger.debug("Trackpad: pointer revealed")
            revealPointer()
        }
        guard !reveal.isPending else { return false }
        revealTask = nil
        return true
    }

    /// QA (scroll edges): where each trackpad touch began and what it became.
    private func logTouchStart(_ start: (x: Double, y: Double), _ role: TrackpadMapper.Role) {
        let position = String(format: "%.2f, %.2f", start.x, start.y)
        let name = switch role {
        case .pointer: "pointer"
        case .verticalScroll: "scroll vertical"
        case .horizontalScroll: "scroll horizontal"
        }
        Self.logger.debug("Trackpad touch at \(position, privacy: .public): \(name, privacy: .public)")
    }

    /// L7: pointer actions are synthetic events (`SyntheticInput`, tagged); without Accessibility nothing is posted.
    /// Security M1: with the kiosk lock in force, nothing is posted unless the guard allows the app in front.
    private func post(_ action: PointerAction) {
        if isPointerAllowed() { pointer(action) }
    }

    /// `post`'s checks, shared with the pointer reveal (step 13e (c)): Accessibility, then security M1's gate, each
    /// refusal noted once.
    private func isPointerAllowed() -> Bool {
        guard externalRouter.canPostEvents() else {
            noteNeedsAccessibility()
            return false
        }
        switch pointerGate() {
        case .allowed:
            blockedFrontApp = nil
            return true
        case .blocked(let bundleID):
            guard blockedFrontApp != bundleID else { return false }
            blockedFrontApp = bundleID
            pointerBlockedNotices += 1
            Self.logger.info("Trackpad: ignored, \(bundleID, privacy: .public) isn't allowed")
            return false
        }
    }

    /// Logged once per run of the remote.
    private func noteNeedsAccessibility() {
        guard !loggedNeedsAccessibility else { return }
        loggedNeedsAccessibility = true
        accessibilityNotices += 1
        Self.logger.notice("Siri Remote can't control other apps without Accessibility")
    }

    /// L3, after the binding.
    private func route(_ command: RemoteCommand, isRepeat: Bool) {
        switch command {
        case .volumeUp: onVolume(.up)
        case .volumeDown: onVolume(.down)
        case .mute: onVolume(.mute)
        case .power, .powerMenu:
            // Security S3: a button bound to Power that repeats (an arrow) acts once.
            if !isRepeat { onPower(command) }
        default:
            // L5: Home (TV) leaves trackpad mode, and goes Home as usual.
            if command == .home, isTrackpadMode { setTrackpadMode(false) }
            let outcome = externalRouter.route(command, isRepeat: isRepeat)
            Self.logger.debug("Siri Remote \(command.rawValue, privacy: .public)\(isRepeat ? " (repeat)" : "", privacy: .public)")
            if outcome == .needsAccessibility { noteNeedsAccessibility() }
        }
    }

    // MARK: Ticks (long presses and repeats)

    private func updateTicks() {
        if gestures.needsTicks {
            guard tickTask == nil else { return }
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: SiriRemoteTiming.tickInterval)
                    guard !Task.isCancelled, let self else { return }
                    self.perform(self.gestures.tick(at: self.now()))
                    if !self.gestures.needsTicks {
                        self.tickTask = nil
                        return
                    }
                }
            }
        } else {
            stopTicks()
        }
    }

    private func stopTicks() {
        tickTask?.cancel()
        tickTask = nil
    }
}
