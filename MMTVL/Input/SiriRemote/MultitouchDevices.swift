import AppKit
import IOKit
import os

/// One frame from a touch surface: how many fingers, and the first finger's state and position.
nonisolated struct TouchFrame: Equatable, Sendable {
    /// `MTTouch.state` while a finger is on the surface.
    static let touchingState: Int32 = 4

    /// Fingers MultitouchSupport reports (0 once the last one lifted).
    var count: Int
    /// The first finger's state (`MTTouch` offset 20).
    var state: Int32
    /// The first finger's normalized position (0…1): x grows rightward, y upward.
    var x: Double
    var y: Double
    /// Seconds on the buttons' clock (`ProcessInfo.systemUptime`), taken when the frame arrived.
    var timestamp: TimeInterval
    /// The first finger's identifier (`MTTouch` offset 16). When it changes, a different finger is first (the
    /// first one lifted while another stayed down): the recognizers treat it as a new touch, not a jump.
    var identifier: Int32 = 0

    var isTouching: Bool { count > 0 && state == Self.touchingState }

    /// M7h security: positions outside this (or not finite) can't be a finger on the surface; the recognizers
    /// treat such a frame as no touch.
    static let positionRange: ClosedRange<Double> = -0.5...1.5
    /// A larger move between two frames of one touch (normalized) starts a new touch instead of moving. A real
    /// finger moves well under 0.1 per frame at 60 frames a second; the remote's frame rate is **unverified**.
    static let maxJump = 0.4

    var hasValidPosition: Bool {
        x.isFinite && y.isFinite && Self.positionRange.contains(x) && Self.positionRange.contains(y)
    }

    /// Too far from the previous frame of the same touch to be one move.
    func jumps(from x: Double, _ y: Double) -> Bool {
        hypot(self.x - x, self.y - y) > Self.maxJump
    }

    /// Reads the first `MTTouch` (96 bytes: identifier Int32 at 16, state Int32 at 20, x and y Float at 32 and 36,
    /// per OpenMultitouchSupport's OpenMTInternal.h; the identifier is **unverified** on the Siri Remote). Called on
    /// MultitouchSupport's thread; copies what it needs and keeps no pointer.
    static func read(touches: UnsafeRawPointer?, count: Int32, at time: TimeInterval) -> TouchFrame {
        guard count > 0, let touches else { return TouchFrame(count: 0, state: 0, x: 0, y: 0, timestamp: time) }
        return TouchFrame(count: Int(count),
                          state: touches.loadUnaligned(fromByteOffset: 20, as: Int32.self),
                          x: Double(touches.loadUnaligned(fromByteOffset: 32, as: Float.self)),
                          y: Double(touches.loadUnaligned(fromByteOffset: 36, as: Float.self)),
                          timestamp: time,
                          identifier: touches.loadUnaligned(fromByteOffset: 16, as: Int32.self))
    }
}

/// MultitouchSupport's contact frame callback: `int cb(MTDeviceRef, MTTouch *, int count, double timestamp, int frame)`.
private typealias MTFrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

/// Runs on MultitouchSupport's private thread: copies the frame and hands it to the main actor. Only the device's
/// address goes along (as a number); `MultitouchDevices` drops frames from devices it no longer has.
nonisolated private func multitouchFrameReceived(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?,
                                                 _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    let touchFrame = TouchFrame.read(touches: touches.map { UnsafeRawPointer($0) }, count: count,
                                     at: ProcessInfo.processInfo.systemUptime)
    let deviceID = UInt(bitPattern: device)
    DispatchQueue.main.async {
        MainActor.assumeIsolated { MultitouchDevices.deliver(touchFrame, from: deviceID) }
    }
    return 0
}

/// M7h D43: the Siri Remote's touch surface through Apple's private MultitouchSupport framework (`dlopen`, never
/// linked). Only the remote's surfaces are used: never a built-in trackpad, and never another external one (a Magic
/// Trackpad): a surface must belong to an Apple device with one of `RemoteBattery.productIDs`, or, when no product
/// id is found, have the remote's family id (`isRemoteSurface`). Missing symbols
/// leave it unavailable (buttons keep working). Surfaces come and go with the Bluetooth remote:
/// `AppleMultitouchDevice` matching and termination rebuild the list; sleep stops it and wake starts it again.
final class MultitouchDevices {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "SiriRemote")
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    /// Matching and termination often come in bursts (a remote's interfaces); rebuild once after them.
    private static let rebuildDelay: Duration = .milliseconds(500)

    /// The C functions, resolved once.
    private struct API {
        typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
        typealias Register = @convention(c) (UnsafeMutableRawPointer, MTFrameCallback) -> Void
        typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
        typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32
        typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
        typealias GetFamilyID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32
        typealias GetService = @convention(c) (UnsafeMutableRawPointer) -> io_service_t

        let createList: CreateList
        let register: Register
        let unregister: Register
        let start: Start
        let stop: Stop
        let isBuiltIn: IsBuiltIn
        let getFamilyID: GetFamilyID
        let getService: GetService

        /// The API, or the first symbol that's missing.
        static func load() -> Result<API, LoadError> {
            guard let handle = dlopen(MultitouchDevices.frameworkPath, RTLD_NOW) else {
                return .failure(LoadError(missing: "MultitouchSupport.framework"))
            }
            func symbol<T>(_ name: String, as type: T.Type) throws(LoadError) -> T {
                guard let pointer = dlsym(handle, name) else { throw LoadError(missing: name) }
                return unsafeBitCast(pointer, to: type)
            }
            do throws(LoadError) {
                return .success(API(
                    createList: try symbol("MTDeviceCreateList", as: CreateList.self),
                    register: try symbol("MTRegisterContactFrameCallback", as: Register.self),
                    unregister: try symbol("MTUnregisterContactFrameCallback", as: Register.self),
                    start: try symbol("MTDeviceStart", as: Start.self),
                    stop: try symbol("MTDeviceStop", as: Stop.self),
                    isBuiltIn: try symbol("MTDeviceIsBuiltIn", as: IsBuiltIn.self),
                    getFamilyID: try symbol("MTDeviceGetFamilyID", as: GetFamilyID.self),
                    getService: try symbol("MTDeviceGetService", as: GetService.self)))
            } catch {
                return .failure(error)
            }
        }
    }

    private struct LoadError: Error {
        let missing: String
    }

    private static let api: Result<API, LoadError> = API.load()
    private static var loggedUnavailable = false
    /// The running instance frames are delivered to (one in the app).
    private static weak var active: MultitouchDevices?

    /// Delivers a frame copied on MultitouchSupport's thread, if its device is still one of the active instance's.
    static func deliver(_ frame: TouchFrame, from deviceID: UInt) {
        guard let active, active.deviceIDs.contains(deviceID) else { return }
        active.onFrame?(frame)
    }

    /// The Siri Remote's multitouch family id (0x91, measured on the mini in M7h step 1).
    static let remoteFamilyID: Int32 = 0x91

    /// Which rule made a surface the remote's (logged, so the mini's TV build shows which path it takes).
    enum SurfaceMatch: Equatable {
        /// Its IOKit service (or a parent) is an Apple device with one of `RemoteBattery.productIDs`.
        case product
        /// No product id was found on the service or its parents, and its family is `remoteFamilyID`.
        case family
    }

    /// Whether a surface is the Siri Remote's (user decision 2026-11-06): not built in, and either (a) an Apple
    /// product id of the remote, or (b) no product id found and the remote's family id. A surface with any other
    /// product id (a Magic Trackpad: 804, family 129) stays out, whatever its family.
    static func remoteSurfaceMatch(isBuiltIn: Bool, vendorID: Int?, productID: Int?, familyID: Int32) -> SurfaceMatch? {
        guard !isBuiltIn else { return nil }
        guard let productID else { return familyID == remoteFamilyID ? .family : nil }
        guard vendorID == RemoteBattery.appleVendorID, RemoteBattery.productIDs.contains(productID) else { return nil }
        return .product
    }

    static func isRemoteSurface(isBuiltIn: Bool, vendorID: Int?, productID: Int?, familyID: Int32) -> Bool {
        remoteSurfaceMatch(isBuiltIn: isBuiltIn, vendorID: vendorID, productID: productID, familyID: familyID) != nil
    }

    /// Frames from the remote's surfaces, on the main actor.
    var onFrame: ((TouchFrame) -> Void)?
    /// The surfaces stopped (sleep, a rebuild after matching/termination, or `stop()`): no lift frame will come
    /// for a touch in progress, so the recognizers forget it.
    var onReset: (() -> Void)?
    /// MultitouchSupport and every symbol MMTVL needs were found.
    var isAvailable: Bool {
        if case .success = Self.api { return true }
        return false
    }
    /// Remote surfaces delivering frames.
    var surfaceCount: Int { devices.count }

    private var isRunning = false
    private var isAsleep = false
    /// Keeps the listed devices alive while they're used.
    private var list: CFArray?
    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceIDs: Set<UInt> = []
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var sleepObservers: [NSObjectProtocol] = []
    private var rebuildTask: Task<Void, Never>?

    /// Safety net: the matching notifications carry an unretained context.
    isolated deinit {
        if isRunning { stop() }
    }

    func start() {
        guard !isRunning else { return }
        let api: API
        switch Self.api {
        case .success(let loaded):
            api = loaded
        case .failure(let error):
            if !Self.loggedUnavailable {
                Self.loggedUnavailable = true
                Self.logger.notice("Multitouch not available (\(error.missing, privacy: .public) missing); no swipes or trackpad mode")
            }
            return
        }
        isRunning = true
        isAsleep = false
        Self.active = self
        armNotifications()
        observeSleep()
        startDevices(api)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        rebuildTask?.cancel()
        rebuildTask = nil
        stopDevices()
        disarmNotifications()
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObservers = []
        if Self.active === self { Self.active = nil }
    }

    // MARK: Devices

    private func startDevices(_ api: API) {
        stopDevices()
        guard let list = api.createList()?.takeRetainedValue() else {
            Self.logger.notice("Multitouch: 0 remote surfaces")
            return
        }
        var skippedBuiltIn = 0
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            let isBuiltIn = api.isBuiltIn(device)
            var family: Int32 = 0
            _ = api.getFamilyID(device, &family)
            let service = isBuiltIn ? 0 : api.getService(device)
            let vendorID = Self.intProperty("VendorID", of: service)
            let productID = Self.intProperty("ProductID", of: service)
            guard let match = Self.remoteSurfaceMatch(isBuiltIn: isBuiltIn, vendorID: vendorID, productID: productID,
                                                      familyID: family) else {
                if isBuiltIn {
                    skippedBuiltIn += 1
                } else {
                    Self.logger.info("Multitouch: skipped a surface (family \(family, privacy: .public), product \(productID ?? -1, privacy: .public)): not a Siri Remote")
                }
                continue
            }
            api.register(device, multitouchFrameReceived)
            let status = api.start(device, 0)
            guard status == 0 else {
                api.unregister(device, multitouchFrameReceived)
                Self.logger.error("Multitouch: surface family \(family, privacy: .public) didn't start: \(status, privacy: .public)")
                continue
            }
            devices.append(device)
            deviceIDs.insert(UInt(bitPattern: device))
            let rule = match == .product ? "product" : "family 0x91"
            Self.logger.notice("Multitouch: Siri Remote surface (family \(family, privacy: .public), product \(productID ?? -1, privacy: .public)) accepted by \(rule, privacy: .public)")
        }
        self.list = list
        if skippedBuiltIn > 0 {
            Self.logger.info("Multitouch: skipped \(skippedBuiltIn, privacy: .public) built-in surfaces")
        }
        Self.logger.notice("Multitouch: \(self.devices.count, privacy: .public) remote surfaces")
    }

    private func stopDevices() {
        if case .success(let api) = Self.api {
            for device in devices {
                api.unregister(device, multitouchFrameReceived)
                _ = api.stop(device)
            }
        }
        devices = []
        deviceIDs = []
        list = nil   // releases the devices
        onReset?()
    }

    /// A number property of the service or one of its parents; nil without a service.
    private static func intProperty(_ key: String, of service: io_service_t) -> Int? {
        guard service != 0 else { return nil }
        let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                    IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        return (value as? NSNumber)?.intValue
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: Self.rebuildDelay)
            guard let self, !Task.isCancelled, self.isRunning, !self.isAsleep,
                  case .success(let api) = Self.api else { return }
            self.rebuildTask = nil
            self.startDevices(api)
        }
    }

    // MARK: Matching notifications

    /// `AppleMultitouchDevice` services appearing or going away (the remote connecting, or idling off).
    private func armNotifications() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), { context, iterator in
                MainActor.assumeIsolated {
                    MultitouchDevices.drain(iterator)
                    guard let context else { return }
                    Unmanaged<MultitouchDevices>.fromOpaque(context).takeUnretainedValue().devicesChanged()
                }
            }, context, &iterator)
            guard result == KERN_SUCCESS else {
                Self.logger.error("Multitouch: device notifications failed: \(result, privacy: .public)")
                continue
            }
            // Draining arms the notification (the devices already there are the list startDevices builds).
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    private func disarmNotifications() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators = []
        if let notifyPort {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
            IONotificationPortDestroy(notifyPort)
        }
        notifyPort = nil
    }

    private static func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func devicesChanged() {
        guard isRunning else { return }
        scheduleRebuild()
    }

    // MARK: Sleep and wake

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    self.isAsleep = true
                    self.rebuildTask?.cancel()
                    self.rebuildTask = nil
                    self.stopDevices()
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    Self.logger.info("Multitouch: restarting after wake")
                    self.isAsleep = false
                    self.scheduleRebuild()
                }
            },
        ]
    }
}
