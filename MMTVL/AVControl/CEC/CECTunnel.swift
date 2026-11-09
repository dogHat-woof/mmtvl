import Darwin
import Foundation
import IOKit
import os

// M7h step 9 (reopened), L13: HDMI-CEC through DisplayPort AUX tunneling (VESA DPCD 0x3000…), below IOCEC and
// corercd. The Mac's HDMI port is Apple's DP-to-HDMI converter (`pHDMIg`), which tunnels CEC; DCP and corercd already
// have tunneling on, with logical address 4 (playback 1) and broadcast in the mask (step 14b, probes 1 and 2). MMTVL
// only *sends* next to them: it never enables tunneling, never changes the mask, never claims an address, never clears
// the IRQ flags. Every write goes through `guardedWrite`, whose allow-list is the TX buffer (0x3020…0x302F) and TX info
// (0x3003, only with the send bit); anything else is a programming error, refused and logged at fault level. The IOKit
// calls (no headers; `dlsym`, signatures from probe 2's disassembly) are `IODPDeviceCreateWithService`,
// `IODPDeviceReadDPCD` (selector 0) and `IODPDeviceWriteDPCD` (selector 1); a missing one means "not available".
// Everything runs on the tunnel's own serial queue.

/// Whether MMTVL can send on the tunnel.
nonisolated enum CECAvailability: Equatable, Sendable {
    /// Tunneling capable and on, with address 4 in the mask.
    case ready
    /// The display (or this Mac) doesn't tunnel CEC, tunneling is off, address 4 isn't in the mask, or the IOKit calls
    /// are missing.
    case notAvailable
    /// No External DisplayPort device (no HDMI display; the proxies vanish while HPD is low).
    case noDisplay
}

nonisolated enum CECSendResult: Equatable, Sendable {
    /// The send bit cleared.
    case sent
    /// The send bit cleared, but the TX flags say the destination didn't acknowledge (directed frames only).
    case notAcknowledged
    /// Another send (corercd's) was still in progress after 500 ms; nothing was written.
    case busy
    /// Our bytes were written to the TX buffer, but another send (corercd's) had started meanwhile, so our send bit
    /// wasn't set. The hardware may still send our bytes as part of that send (security L1, build 25 review).
    case collided
    /// The send bit didn't clear within 1 s.
    case timedOut
    /// A read or write failed.
    case failed
    case unavailable(CECAvailability)
}

extension CECSendResult {
    /// Step 9c (security M1): the frame may have reached the bus (sent, sent but not acknowledged, written and still
    /// sending after 1 s, or written while another send started: security L1). After a User Control Pressed like that, a Released must follow, or the device may
    /// treat the key as held.
    nonisolated var mayHaveGoneOut: Bool {
        switch self {
        case .sent, .notAcknowledged, .timedOut, .collided: true
        case .busy, .failed, .unavailable: false
        }
    }
}

/// Raw DPCD reads and writes on one DisplayPort device: IOKit's, or a fake in tests. Called only on the tunnel's queue.
nonisolated protocol DPCDDevice: AnyObject {
    /// nil when the read failed.
    func read(_ address: UInt32, count: Int) -> [UInt8]?
    func write(_ address: UInt32, _ bytes: [UInt8]) -> Bool
}

nonisolated enum DPCDOpenResult {
    case device(any DPCDDevice)
    case noDisplay
    /// Why (for the log).
    case notAvailable(String)
}

/// What `HDMICEC` and (step 9c) `CECAudioSystem` need from the tunnel (tests fake it). Both share one tunnel, so
/// every frame goes through its one serial queue.
nonisolated protocol CECLink: AnyObject, Sendable {
    /// Read-only.
    func availability() async -> CECAvailability
    func send(_ frame: CECFrame) async -> CECSendResult
    /// Sends Give Device Power Status to `device` and waits up to 1 s for its Report Power Status (asked once more
    /// without an answer); nil = no answer.
    func powerStatus(of device: CECDevice) async -> CECPowerStatus?
    /// Step 9c: sends `frame` (one of the allowed queries) and waits up to `timeout` for a frame matching `reply`;
    /// nil when it wasn't sent or nothing matched in time. Asked once, never retried.
    func query(_ frame: CECFrame, reply: CECReplyPattern, timeout: Duration) async -> [UInt8]?
    /// Drops the DisplayPort device (after an HDMI hot-plug); the next call opens it again.
    func invalidate()
}

nonisolated extension CECLink {
    /// The TV's power status.
    func powerStatus() async -> CECPowerStatus? {
        await powerStatus(of: .tv)
    }
}

/// Monotonic time and a blocking pause, for the queue's polling loops (tests fake both).
nonisolated struct CECTiming: Sendable {
    /// Nanoseconds, monotonic.
    var now: @Sendable () -> UInt64
    /// Blocks for this many microseconds.
    var pause: @Sendable (UInt32) -> Void

    static let system = CECTiming(now: { DispatchTime.now().uptimeNanoseconds }, pause: { usleep($0) })
}

nonisolated final class CECTunnel: CECLink, @unchecked Sendable {
    static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "CEC")

    /// DPCD registers (VESA DP 1.3+ CEC tunneling; names from Linux `drm_dp.h`).
    enum Register {
        static let revision: UInt32 = 0x0000
        static let capability: UInt32 = 0x3000
        static let control: UInt32 = 0x3001
        static let rxInfo: UInt32 = 0x3002
        static let txInfo: UInt32 = 0x3003
        static let irqFlags: UInt32 = 0x3004
        static let maskLow: UInt32 = 0x300E
        static let maskHigh: UInt32 = 0x300F
        static let rxBuffer: UInt32 = 0x3010
        static let txBuffer: UInt32 = 0x3020
        static let txBufferEnd: UInt32 = 0x302F
    }

    static let sendBit: UInt8 = 0x80
    static let retries: UInt8 = 3
    /// A send in progress (corercd's) gets this long to finish before ours.
    static let busyWaitNanoseconds: UInt64 = 500_000_000
    /// Our send bit must clear within this (~65 ms on the mini).
    static let sendWaitNanoseconds: UInt64 = 1_000_000_000
    /// The TV's Report Power Status must arrive within this.
    static let replyWaitNanoseconds: UInt64 = 1_000_000_000
    static let pollMicroseconds: UInt32 = 10_000
    /// While waiting for a reply, the IRQ flags are read this often (RX valid may be cleared by DCP within 10 ms).
    static let flagsPollMicroseconds: UInt32 = 5_000
    /// …and RX info and the RX buffer every this many flag reads (10 ms).
    static let changeCheckEvery = 2
    /// DPCD 0x0000 (DPCD_REV) a device must report before MMTVL writes to it: the IOKit calls' signatures come from
    /// disassembly of two macOS builds, so an implausible revision means the calls don't do what MMTVL thinks.
    static let plausibleRevisions: ClosedRange<UInt8> = 0x10...0x14

    private let queue = DispatchQueue(label: "dev.mmtvl.launcher.cec")
    private let open: @Sendable () -> DPCDOpenResult
    private let timing: CECTiming
    // Queue only.
    private var device: (any DPCDDevice)?
    /// The opened device whose DPCD revision was checked (once per device).
    private var revisionCheckedDevice: ObjectIdentifier?
    private var lastAvailability: CECAvailability?
    private var lastReason: String?

    init(open: @escaping @Sendable () -> DPCDOpenResult = IOKitDPCD.open, timing: CECTiming = .system) {
        self.open = open
        self.timing = timing
    }

    // MARK: The fence

    /// The only DPCD writes MMTVL makes: 1…16 bytes inside the TX buffer (0x3020…0x302F), or one byte to TX info
    /// (0x3003) with the send bit. Never 0x3001 (control), 0x300E/0x300F (the mask), 0x3004 (the IRQ flags) or
    /// anything else. Pure.
    static func writeAllowed(_ address: UInt32, _ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty, bytes.count <= 16 else { return false }
        if address >= Register.txBuffer, UInt64(address) + UInt64(bytes.count) - 1 <= UInt64(Register.txBufferEnd) {
            return true
        }
        return address == Register.txInfo && bytes.count == 1 && bytes[0] & sendBit != 0
    }

    /// Every write goes through here (and `IOKitDPCDDevice.write` checks again).
    private func guardedWrite(_ device: any DPCDDevice, _ address: UInt32, _ bytes: [UInt8]) -> Bool {
        guard Self.writeAllowed(address, bytes) else {
            Self.logger.fault("CEC: refused a write to \(Self.hexAddress(address), privacy: .public) (\(bytes.count, privacy: .public) bytes): only the TX buffer and TX info")
            return false
        }
        return device.write(address, bytes)
    }

    // MARK: CECLink

    func availability() async -> CECAvailability {
        await onQueue { self.check().availability }
    }

    func send(_ frame: CECFrame) async -> CECSendResult {
        await onQueue { self.sendNow(frame) }
    }

    func powerStatus(of device: CECDevice) async -> CECPowerStatus? {
        await onQueue { self.powerStatusNow(of: device) }
    }

    func query(_ frame: CECFrame, reply: CECReplyPattern, timeout: Duration) async -> [UInt8]? {
        let components = timeout.components
        let nanoseconds = UInt64(max(0, components.seconds)) * 1_000_000_000
            + UInt64(max(0, components.attoseconds / 1_000_000_000))
        return await onQueue {
            guard case .reply(let bytes) = self.queryNow(frame, reply: reply, timeout: nanoseconds) else { return nil }
            return bytes
        }
    }

    func invalidate() {
        queue.async { self.device = nil }
    }

    // MARK: On the queue

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private struct Check {
        var availability: CECAvailability
        var device: (any DPCDDevice)?
    }

    /// Opens the device if needed and reads (only) 0x3000, 0x3001 and the mask. A read failing on a kept device
    /// (stale after a hot-plug) drops it and tries once with a fresh one.
    private func check() -> Check {
        for attempt in 0..<2 {
            let wasKept = device != nil
            if device == nil {
                switch open() {
                case .device(let opened):
                    device = opened
                    // Every opened device is checked, even if it's the same object again.
                    revisionCheckedDevice = nil
                case .noDisplay: return note(.noDisplay, reason: "no HDMI display")
                case .notAvailable(let reason): return note(.notAvailable, reason: reason)
                }
            }
            guard let device else { break }
            if revisionCheckedDevice != ObjectIdentifier(device) {
                guard let revision = read(device, Register.revision) else {
                    self.device = nil
                    if wasKept, attempt == 0 { continue }
                    return note(.notAvailable, reason: "the DPCD revision can't be read")
                }
                guard Self.plausibleRevisions.contains(revision) else {
                    // Dropped, so a later check opens and checks it again.
                    self.device = nil
                    return note(.notAvailable, reason: "implausible DPCD revision \(Self.hex8(revision)); not writing to this device")
                }
                revisionCheckedDevice = ObjectIdentifier(device)
            }
            guard let capability = read(device, Register.capability), let control = read(device, Register.control),
                  let maskLow = read(device, Register.maskLow), let maskHigh = read(device, Register.maskHigh)
            else {
                self.device = nil
                if wasKept, attempt == 0 { continue }
                return note(.notAvailable, reason: "the tunnel's registers can't be read")
            }
            let mask = UInt16(maskLow) | UInt16(maskHigh) << 8
            if capability & 1 == 0 {
                return note(.notAvailable, reason: "this display doesn't tunnel CEC (0x3000 = \(Self.hex8(capability)))")
            }
            if control & 1 == 0 {
                return note(.notAvailable, reason: "tunneling is off (0x3001 = \(Self.hex8(control))); MMTVL never turns it on")
            }
            if mask & (1 << UInt16(CECFrame.initiator)) == 0 {
                return note(.notAvailable, reason: "logical address \(CECFrame.initiator) isn't in the mask (\(String(format: "0x%04X", mask))); MMTVL never claims one")
            }
            var result = note(.ready, reason: "ready, mask \(String(format: "0x%04X", mask))")
            result.device = device
            return result
        }
        return note(.notAvailable, reason: "the tunnel's registers can't be read")
    }

    /// Logs availability changes (and a changed reason).
    private func note(_ availability: CECAvailability, reason: String) -> Check {
        if availability != lastAvailability || reason != lastReason {
            switch availability {
            case .ready: Self.logger.notice("CEC: HDMI-CEC \(reason, privacy: .public)")
            case .notAvailable: Self.logger.notice("CEC: HDMI-CEC not available: \(reason, privacy: .public)")
            case .noDisplay: Self.logger.notice("CEC: no HDMI display")
            }
            lastAvailability = availability
            lastReason = reason
        }
        return Check(availability: availability, device: nil)
    }

    private func sendNow(_ frame: CECFrame) -> CECSendResult {
        let check = check()
        guard let device = check.device else {
            Self.logger.notice("CEC: \(frame.description, privacy: .public) not sent: \(String(describing: check.availability), privacy: .public)")
            return .unavailable(check.availability)
        }
        // CECFrame builds only allowed frames from address 4; checked again here (the mask was checked for 4 only).
        guard CECFrame.isAllowed(frame.bytes) else {
            Self.logger.fault("CEC: refused \(frame.description, privacy: .public): not an allowed frame from address \(CECFrame.initiator, privacy: .public)")
            return .failed
        }
        // A send in progress (corercd's): wait for its send bit to clear.
        let waitStart = timing.now()
        var info = read(device, Register.txInfo)
        while let current = info, current & Self.sendBit != 0, timing.now() - waitStart < Self.busyWaitNanoseconds {
            timing.pause(Self.pollMicroseconds)
            info = read(device, Register.txInfo)
        }
        guard let before = info else {
            self.device = nil
            Self.logger.notice("CEC: \(frame.description, privacy: .public) not sent: TX info can't be read")
            return .failed
        }
        guard before & Self.sendBit == 0 else {
            Self.logger.notice("CEC: \(frame.description, privacy: .public) not sent: another send is still in progress after 500 ms")
            return .busy
        }
        guard guardedWrite(device, Register.txBuffer, frame.bytes) else {
            Self.logger.notice("CEC: \(frame.description, privacy: .public) not sent: the write failed")
            return .failed
        }
        // corercd may have started a send between the busy check and our TX buffer write: then it's sending (with
        // our bytes, or its own) and our send bit would collide. Leave it; ours may still go out with that send
        // (`.collided`, which `mayHaveGoneOut`, so a Pressed is still released). A failed re-read is treated the same.
        guard let recheck = read(device, Register.txInfo), recheck & Self.sendBit == 0 else {
            Self.logger.notice("CEC: \(frame.description, privacy: .public) not sent: another send started while the frame was written (it may go out with that send)")
            return .collided
        }
        guard guardedWrite(device, Register.txInfo, [frame.txInfo(retries: Self.retries)]) else {
            Self.logger.notice("CEC: \(frame.description, privacy: .public) not sent: the write failed")
            return .failed
        }
        let sendStart = timing.now()
        var after: UInt8?
        repeat {
            timing.pause(Self.pollMicroseconds)
            after = read(device, Register.txInfo)
        } while (after.map { $0 & Self.sendBit != 0 } ?? true) && timing.now() - sendStart < Self.sendWaitNanoseconds
        let milliseconds = (timing.now() - sendStart) / 1_000_000
        guard let after, after & Self.sendBit == 0 else {
            Self.logger.notice("CEC: \(frame.description, privacy: .public) written, but not sent within 1 s")
            return .timedOut
        }
        let flags = read(device, Register.irqFlags) ?? 0
        let isBroadcast = frame.bytes[0] & 0x0F == 0x0F
        // Bit 4 TX sent; 6 address NACK, 7 data NACK (the owner clears them, so they may already be gone).
        let nacked = !isBroadcast && flags & 0xC0 != 0 && flags & 0x10 == 0
        Self.logger.notice("CEC: sent \(frame.description, privacy: .public) in \(milliseconds, privacy: .public) ms, flags \(Self.hex8(flags), privacy: .public)\(nacked ? ", not acknowledged" : "", privacy: .public)")
        return nacked ? .notAcknowledged : .sent
    }

    /// Give Device Power Status to `device`; with no answer within 1 s, sent once more (a missed reply would make the
    /// Power button turn things "on" while the TV is on, or a ready receiver read as not answering).
    private func powerStatusNow(of device: CECDevice) -> CECPowerStatus? {
        let frame = CECFrame.givePowerStatus(to: device)
        let pattern = CECReplyPattern.powerStatus(from: device)
        var outcome = queryNow(frame, reply: pattern, timeout: Self.replyWaitNanoseconds)
        if outcome == .noAnswer {
            Self.logger.notice("CEC: asking \(device.logName, privacy: .public) for the power status once more")
            outcome = queryNow(frame, reply: pattern, timeout: Self.replyWaitNanoseconds)
        }
        guard case .reply(let reply) = outcome else { return nil }
        let status = CECPowerStatus.parseReply(reply, pattern: pattern)
        if status == nil { Self.logger.notice("CEC: unknown power status in \(CECFrame.hex(reply), privacy: .public)") }
        return status
    }

    enum QueryOutcome: Equatable {
        case reply([UInt8])
        /// Sent, but nothing matching arrived in time.
        case noAnswer
        case notSent
    }

    /// Sends `frame`, then watches the RX side (read-only) until a frame matching `reply` shows, or `timeout` passes.
    /// The IRQ flags (0x3004, never written) are read every 2 ms: RX valid rising (0 → 1) means a new frame even when
    /// its bytes are identical to the last one. Every 10 ms RX info (0x3002) and the RX buffer are read as well: a
    /// change in either also means a new frame. Frames that don't match are skipped.
    private func queryNow(_ frame: CECFrame, reply: CECReplyPattern, timeout: UInt64) -> QueryOutcome {
        guard let device = check().device else { return .notSent }
        var lastInfo = read(device, Register.rxInfo)
        var lastFlags = read(device, Register.irqFlags)
        var lastRX = read(device, Register.rxBuffer, count: 3)
        let result = sendNow(frame)
        guard result == .sent, let device = self.device else {
            Self.logger.notice("CEC: no answer to \(frame.description, privacy: .public) (not sent: \(String(describing: result), privacy: .public))")
            return .notSent
        }
        let start = timing.now()
        var tick = 0
        repeat {
            let flags = read(device, Register.irqFlags)
            let validRose = (flags ?? 0) & 1 != 0 && (lastFlags ?? 0) & 1 == 0
            lastFlags = flags
            var changed = validRose
            var info: UInt8?
            if validRose || tick % Self.changeCheckEvery == 0 {
                info = read(device, Register.rxInfo)
                let rx = read(device, Register.rxBuffer, count: 3)
                if info != lastInfo || rx != lastRX { changed = true }
                lastInfo = info
                lastRX = rx
            }
            if changed, let info {
                let count = Int(info & 0xF) + 1
                if let bytes = read(device, Register.rxBuffer, count: count) {
                    if reply.matches(bytes) {
                        Self.logger.notice("CEC: answer to \(frame.description, privacy: .public): \(CECFrame.hex(bytes), privacy: .public)")
                        return .reply(bytes)
                    }
                    Self.logger.debug("CEC: received \(CECFrame.hex(bytes), privacy: .public) while waiting for an answer")
                }
            }
            tick += 1
            timing.pause(Self.flagsPollMicroseconds)
        } while timing.now() - start < timeout
        Self.logger.notice("CEC: no answer to \(frame.description, privacy: .public) within \(timeout / 1_000_000, privacy: .public) ms")
        return .noAnswer
    }

    private func read(_ device: any DPCDDevice, _ address: UInt32) -> UInt8? {
        device.read(address, count: 1)?.first
    }

    private func read(_ device: any DPCDDevice, _ address: UInt32, count: Int) -> [UInt8]? {
        guard let bytes = device.read(address, count: count), bytes.count == count else { return nil }
        return bytes
    }

    static func hex8(_ value: UInt8) -> String { String(format: "0x%02X", value) }
    static func hexAddress(_ address: UInt32) -> String { String(format: "0x%04X", address) }
}

// MARK: IOKit

/// The External `DCPDPDeviceProxy` through IOKit's DisplayPort user client (no headers: `dlsym`). Signatures from
/// the disassembly of IOKit on macOS 26.6.2 (25G83) and 27.2 (step 14b): `IODPDeviceRef
/// IODPDeviceCreateWithService(CFAllocatorRef, io_service_t)` (needs `IODPDeviceUserInterfaceSupported`), `IOReturn
/// IODPDeviceReadDPCD(IODPDeviceRef, uint32_t address, void *buffer, uint32_t length)` and `IOReturn
/// IODPDeviceWriteDPCD(IODPDeviceRef, uint32_t address, const void *buffer, uint32_t length)`.
nonisolated enum IOKitDPCD {
    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> UnsafeMutableRawPointer?
    typealias ReadDPCD = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    typealias WriteDPCD = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer, UInt32) -> Int32

    struct Symbols: @unchecked Sendable {
        let create: CreateWithService
        let read: ReadDPCD
        let write: WriteDPCD
    }

    static let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(handle, "IODPDeviceCreateWithService"),
              let read = dlsym(handle, "IODPDeviceReadDPCD"),
              let write = dlsym(handle, "IODPDeviceWriteDPCD")
        else { return nil }
        return Symbols(create: unsafeBitCast(create, to: CreateWithService.self),
                       read: unsafeBitCast(read, to: ReadDPCD.self),
                       write: unsafeBitCast(write, to: WriteDPCD.self))
    }()

    /// The External `DCPDPDeviceProxy` (the converter `pHDMIg` first, if there are several), opened.
    static func open() -> DPCDOpenResult {
        guard let symbols else { return .notAvailable("IOKit's DisplayPort calls are missing") }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPDPDeviceProxy"), &iterator) == KERN_SUCCESS
        else { return .noDisplay }
        defer { IOObjectRelease(iterator) }
        var external: [io_service_t] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if property(service, "Location") as? String == "External" {
                external.append(service)
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }
        defer { external.forEach { IOObjectRelease($0) } }
        guard let chosen = external.first(where: { property($0, "BranchDeviceID") as? String == "pHDMIg" }) ?? external.first
        else { return .noDisplay }
        guard let ref = symbols.create(kCFAllocatorDefault, chosen) else {
            return .notAvailable("the DisplayPort device can't be opened")
        }
        return .device(IOKitDPCDDevice(ref: ref, symbols: symbols))
    }

    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// One opened IODPDevice (a CF object, released with it).
nonisolated final class IOKitDPCDDevice: DPCDDevice {
    private let ref: UnsafeMutableRawPointer
    private let symbols: IOKitDPCD.Symbols

    init(ref: UnsafeMutableRawPointer, symbols: IOKitDPCD.Symbols) {
        self.ref = ref
        self.symbols = symbols
    }

    deinit {
        Unmanaged<AnyObject>.fromOpaque(ref).release()
    }

    func read(_ address: UInt32, count: Int) -> [UInt8]? {
        guard (1...16).contains(count) else { return nil }
        var buffer = [UInt8](repeating: 0, count: count)
        let result = buffer.withUnsafeMutableBytes { symbols.read(ref, address, $0.baseAddress!, UInt32(count)) }
        return result == KERN_SUCCESS ? buffer : nil
    }

    /// The fence again, right before the call.
    func write(_ address: UInt32, _ bytes: [UInt8]) -> Bool {
        guard CECTunnel.writeAllowed(address, bytes) else {
            CECTunnel.logger.fault("CEC: refused a write to \(CECTunnel.hexAddress(address), privacy: .public) at the device")
            return false
        }
        let result = bytes.withUnsafeBytes { symbols.write(ref, address, $0.baseAddress!, UInt32(bytes.count)) }
        if result != KERN_SUCCESS {
            CECTunnel.logger.notice("CEC: write to \(CECTunnel.hexAddress(address), privacy: .public) failed (\(String(format: "0x%08X", UInt32(bitPattern: result)), privacy: .public))")
        }
        return result == KERN_SUCCESS
    }
}
