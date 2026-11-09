import AppKit
import IOKit
import IOKit.hid
import os

/// M7h D43, L1: reads the Siri Remote's buttons with `IOHIDManager`, each interface **seized** (so macOS doesn't
/// act on them too), else opened shared. Matching and removal callbacks follow the Bluetooth LE remote coming and
/// going; a removal releases the buttons it held (`synthesized`). Runs on the main run loop.
/// Volume and Mute don't reach a seizing client (step 1); their mapping stays for an interface opened shared.
/// The **digitizer** interface (primary usage page 0x0D) is left unopened (build 24 TV checks): after MMTVL seized it
/// as the remote reconnected, its kernel touch driver (`AppleEmbeddedBluetoothTouch`) was missing, so no
/// `AppleMultitouchDevice` existed for MultitouchSupport, where the touch surface is read. The seize is the likely
/// cause (unverified until a reconnect on the mini); nothing is read from that interface here.
final class SiriRemoteHID {
    struct ButtonEvent: Equatable {
        /// nil for Siri (reserved, never bindable).
        var button: SiriRemoteButton?
        var isSiri: Bool
        var pressed: Bool
        /// A release made up because the interface went away or reading stopped (the user may still hold it).
        var synthesized = false
    }

    /// The IOKit manager's lifecycle and the run loop, injectable so tests can check when teardown happens.
    struct System {
        /// Creates the manager, sets its matching, registers the matching and removal callbacks with `context`
        /// (an unretained `SiriRemoteHID`) and schedules it on the main run loop. Returns the manager.
        var openManager: @MainActor (_ context: UnsafeMutableRawPointer) -> AnyObject
        /// Unregisters the manager's callbacks and unschedules it.
        var closeManager: @MainActor (_ manager: AnyObject) -> Void
        /// Runs a block on a later turn of the main run loop.
        var nextTurn: @MainActor (_ block: @escaping @MainActor () -> Void) -> Void

        static let live = System(
            openManager: { SiriRemoteHID.openLiveManager(context: $0) },
            closeManager: { object in
                let manager = unsafeDowncast(object, to: IOHIDManager.self)   // always one from openManager
                IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
                IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            },
            nextTurn: { block in
                DispatchQueue.main.async { MainActor.assumeIsolated { block() } }
            }
        )
    }

    /// `System.live`'s manager: Siri Remote matching, the callbacks (context: an unretained `SiriRemoteHID`), scheduled.
    private static func openLiveManager(context: UnsafeMutableRawPointer) -> IOHIDManager {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = RemoteBattery.productIDs.sorted().map {
            [kIOHIDVendorIDKey: RemoteBattery.appleVendorID, kIOHIDProductIDKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<SiriRemoteHID>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<SiriRemoteHID>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
            }
        }, context)
        // The manager itself is never opened: each interface is opened by hand (seize, else shared), as in
        // step 1's probe. Scheduling enumerates the matching interfaces (and delivers their values).
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return manager
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "SiriRemote")
    /// The usage pages the buttons arrive on; other values (touch, motion) are filtered out by IOKit.
    private static let buttonPages: [UInt32] = [SiriRemoteButton.consumerPage, SiriRemoteButton.genericDesktopPage]
    /// kHIDPage_Digitizer: the touch surface's interface, left to macOS.
    nonisolated static let digitizerPage: UInt32 = 0x0D

    /// Whether an interface is opened (seized, else shared): every one but the digitizer. An interface without a
    /// primary usage page is opened, as before.
    nonisolated static func shouldOpen(primaryUsagePage: UInt32?) -> Bool {
        primaryUsagePage != digitizerPage
    }

    var onButton: ((ButtonEvent) -> Void)?
    /// M7h step 11 (QA major): the remote connected (its first interface opened) or disconnected (its last one went,
    /// or reading stopped). May run inside IOKit's callbacks: the receiver must not stop reading from it.
    var onConnectionChange: (() -> Void)?
    /// At least one interface is open.
    var isConnected: Bool { !devices.isEmpty }
    /// Reading (a deferred stop still pending counts as stopped).
    var isRunning: Bool { manager != nil && !stopPending }
    /// How many times a value from an unknown `sender` was logged: once per start (QA: a wrong `sender`
    /// assumption would otherwise look like "connected, buttons dead").
    private(set) var unknownSenderNotices = 0

    private enum Key: Hashable {
        case button(SiriRemoteButton)
        case siri
    }

    private struct OpenDevice {
        /// nil only in tests (`interfaceOpened`).
        let device: IOHIDDevice?
        var held: Set<Key> = []
    }

    private let system: System
    private var manager: AnyObject?
    private var devices: [ObjectIdentifier: OpenDevice] = [:]
    private var connectionCheckTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    /// Security review (step 4): `onButton` runs inside IOKit's callbacks. A `stop()` from there (Settings turned
    /// the remote off with the remote's own Select) must not free the manager or the devices under IOKit's frame,
    /// so it waits for the next run-loop turn.
    private var deliveryDepth = 0
    private var stopPending = false
    private var loggedUnknownSender = false

    init(system: System = .live) {
        self.system = system
    }

    /// Safety net: a released reader must never stay scheduled with an unretained context.
    isolated deinit {
        if manager != nil { teardown(releasing: false) }
    }

    func start() {
        if stopPending {
            // A stop asked for during delivery hasn't run yet: keep reading.
            stopPending = false
            return
        }
        guard manager == nil else { return }
        loggedUnknownSender = false
        manager = system.openManager(Unmanaged.passUnretained(self).toOpaque())
        Self.logger.info("Siri Remote: reading started")
        observeWake()
        // Matches arrive on the run loop; give them a moment before saying none is there.
        connectionCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.isRunning, self.devices.isEmpty else { return }
            Self.logger.notice("Siri Remote: no remote connected")
        }
    }

    func stop() {
        guard manager != nil, !stopPending else { return }
        guard deliveryDepth == 0 else {
            stopPending = true
            system.nextTurn { [weak self] in
                guard let self, self.stopPending else { return }
                self.stopPending = false
                self.teardown(releasing: true)
            }
            return
        }
        teardown(releasing: true)
    }

    /// Closes every interface and the manager. `releasing`: synthesize releases for held buttons first.
    private func teardown(releasing: Bool) {
        guard let manager else { return }
        connectionCheckTask?.cancel()
        connectionCheckTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        let wasConnected = isConnected
        for id in devices.keys {
            if releasing { releaseHeld(of: id) }
            if let device = devices[id]?.device { Self.close(device) }
        }
        devices.removeAll()
        system.closeManager(manager)
        self.manager = nil
        stopPending = false
        Self.logger.info("Siri Remote: reading stopped")
        if wasConnected, releasing { onConnectionChange?() }
    }

    /// Unregisters the value callback and closes the interface; errors (an already-terminated service) are ignored.
    private static func close(_ device: IOHIDDevice) {
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// After the Mac wakes, start over (the remote reconnects; stale interfaces are dropped).
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                Self.logger.info("Siri Remote: restarting after wake")
                self.stop()
                self.start()
            }
        }
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard devices[id] == nil, !stopPending else { return }
        let name = Self.interfaceName(device)
        guard Self.shouldOpen(primaryUsagePage: Self.primaryUsagePage(device)) else {
            // Its kernel touch driver must start for MultitouchSupport to see the surface.
            Self.logger.notice("Siri Remote interface \(name, privacy: .public) left to macOS (touch)")
            return
        }
        var result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result == kIOReturnSuccess {
            Self.logger.notice("Siri Remote interface \(name, privacy: .public) open: seized")
        } else {
            let seizeError = Self.hex(result)
            result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if result == kIOReturnSuccess {
                Self.logger.notice("Siri Remote interface \(name, privacy: .public) open: not seized (\(seizeError, privacy: .public))")
            } else {
                Self.logger.error("Siri Remote interface \(name, privacy: .public) open failed: \(Self.hex(result), privacy: .public)")
                return
            }
        }
        let valueMatching: [[String: UInt32]] = Self.buttonPages.map { [kIOHIDElementUsagePageKey: $0] }
        IOHIDDeviceSetInputValueMatchingMultiple(device, valueMatching as CFArray)
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, sender, value in
            guard let context, let sender else { return }
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let pressed = IOHIDValueGetIntegerValue(value) != 0
            let deviceID = ObjectIdentifier(Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue())
            MainActor.assumeIsolated {
                Unmanaged<SiriRemoteHID>.fromOpaque(context).takeUnretainedValue()
                    .valueChanged(page: page, usage: usage, pressed: pressed, deviceID: deviceID)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        interfaceOpened(id, device: device)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard devices[id] != nil else { return }
        Self.logger.info("Siri Remote interface \(Self.interfaceName(device), privacy: .public) removed")
        interfaceRemoved(id)
    }

    /// Records an opened interface; the first one means the remote connected. Internal for tests (`device` nil).
    func interfaceOpened(_ id: ObjectIdentifier, device: IOHIDDevice?) {
        guard devices[id] == nil, !stopPending else { return }
        let wasConnected = isConnected
        devices[id] = OpenDevice(device: device)
        if !wasConnected {
            Self.logger.notice("Siri Remote connected")
            onConnectionChange?()
        }
    }

    /// Releases what the interface held and closes it; the last one going means the remote disconnected.
    /// Internal for tests.
    func interfaceRemoved(_ id: ObjectIdentifier) {
        guard devices[id] != nil else { return }
        releaseHeld(of: id)
        // A stop() from inside the releases is deferred, so the entry is still here.
        guard let open = devices.removeValue(forKey: id) else { return }
        if let device = open.device { Self.close(device) }
        if devices.isEmpty {
            Self.logger.notice("Siri Remote disconnected")
            onConnectionChange?()
        }
    }

    /// Internal for tests.
    func valueChanged(page: UInt32, usage: UInt32, pressed: Bool, deviceID: ObjectIdentifier) {
        guard !stopPending else { return }
        guard devices[deviceID] != nil else {
            // Dropped; said once per start (no values logged).
            if !loggedUnknownSender {
                loggedUnknownSender = true
                unknownSenderNotices += 1
                Self.logger.notice("Siri Remote: value from an unknown device, ignored")
            }
            return
        }
        let key: Key
        if SiriRemoteButton.isSiri(usagePage: page, usage: usage) {
            key = .siri
        } else if let button = SiriRemoteButton.from(usagePage: page, usage: usage) {
            key = .button(button)
        } else {
            return
        }
        // Only changes go on (a repeated report of the same state is dropped).
        if pressed {
            guard devices[deviceID]?.held.insert(key).inserted == true else { return }
        } else {
            guard devices[deviceID]?.held.remove(key) != nil else { return }
        }
        deliver(Self.event(for: key, pressed: pressed, synthesized: false))
    }

    /// Hands an event to `onButton`; a `stop()` from inside it is deferred to the next run-loop turn.
    /// Internal for tests.
    func deliver(_ event: ButtonEvent) {
        deliveryDepth += 1
        defer { deliveryDepth -= 1 }
        onButton?(event)
    }

    /// Releases for every button the interface still holds.
    private func releaseHeld(of id: ObjectIdentifier) {
        guard let held = devices[id]?.held, !held.isEmpty else { return }
        devices[id]?.held.removeAll()
        for key in held {
            deliver(Self.event(for: key, pressed: false, synthesized: true))
        }
    }

    private static func event(for key: Key, pressed: Bool, synthesized: Bool) -> ButtonEvent {
        switch key {
        case .button(let button): ButtonEvent(button: button, isSiri: false, pressed: pressed, synthesized: synthesized)
        case .siri: ButtonEvent(button: nil, isSiri: true, pressed: pressed, synthesized: synthesized)
        }
    }

    private static func primaryUsagePage(_ device: IOHIDDevice) -> UInt32? {
        (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.uint32Value
    }

    /// "0x0C/0x01": the interface's primary usage page and usage.
    private static func interfaceName(_ device: IOHIDDevice) -> String {
        func number(_ key: String) -> String {
            guard let value = (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue else { return "?" }
            return String(format: "0x%02X", value)
        }
        return "\(number(kIOHIDPrimaryUsagePageKey))/\(number(kIOHIDPrimaryUsageKey))"
    }

    private static func hex(_ result: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: result))
    }
}
