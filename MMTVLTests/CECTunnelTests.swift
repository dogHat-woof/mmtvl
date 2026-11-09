import Foundation
import Testing
@testable import MMTVL

/// Fake time for the tunnel's polling: a pause moves it on.
nonisolated final class FakeCECTime: @unchecked Sendable {
    private(set) var nanoseconds: UInt64 = 0

    var timing: CECTiming {
        CECTiming(now: { self.nanoseconds }, pause: { self.nanoseconds += UInt64($0) * 1000 })
    }
}

/// A fake DisplayPort device: the mini's tunnel by default (DPCD revision 0x11; capable, on, mask 0x8010: address 4
/// and broadcast). A send's bit 7 stays set for `sendReads` reads of 0x3003, then clears. `replyDelay` (fake time)
/// later, `reply` (if any) lands in the RX buffer, with RX info's HPD bits kept, and (per send, `replyEdges`) RX valid
/// is set in 0x3004 for `edgeDuration`, then cleared as DCP would. Every write is recorded and must pass the
/// allow-list.
nonisolated final class FakeDPCD: DPCDDevice, @unchecked Sendable {
    var registers: [UInt32: UInt8] = [0x0000: 0x11, 0x3000: 0x07, 0x3001: 0x01, 0x3002: 0xD2, 0x3003: 0x23,
                                      0x3004: 0x00, 0x300E: 0x10, 0x300F: 0x80, 0x3010: 0x5F, 0x3011: 0x72, 0x3012: 0x01]
    private(set) var writes: [(address: UInt32, bytes: [UInt8])] = []
    private(set) var forbiddenWrites = 0
    /// The tunnel's fake time (`CECTunnelTests.tunnel` sets it).
    var now: () -> UInt64 = { 0 }
    /// corercd's send in progress: 0x3003 reads with bit 7 set before it clears (nil: never clears).
    var busyReads: Int? = 0
    /// corercd starts a send (this many 0x3003 reads with bit 7) right after our TX buffer write.
    var corercdSendsAfterTXWrite: Int?
    var sendReads = 6
    /// IRQ flags after our send (bit 4 sent; 6/7 NACK).
    var flagsAfterSend: UInt8 = 0x00
    var reply: [UInt8]?
    /// After our send completes, the reply shows this much later (nanoseconds).
    var replyDelay: UInt64 = 3_000_000
    /// Whether each send's reply raises RX valid (by send number; the last repeats).
    var replyEdges: [Bool] = [true]
    /// How long RX valid stays set before DCP clears it (nanoseconds); nil = it stays.
    var edgeDuration: UInt64?
    private(set) var sends = 0
    var readsFail = false
    private var pendingSendReads: Int?
    private var replyAt: UInt64?
    private var edgeEnd: UInt64?

    func read(_ address: UInt32, count: Int) -> [UInt8]? {
        guard !readsFail else { return nil }
        if address == 0x3003 { tickTX() }
        advanceRX()
        return (0..<count).map { registers[address + UInt32($0)] ?? 0 }
    }

    func write(_ address: UInt32, _ bytes: [UInt8]) -> Bool {
        writes.append((address, bytes))
        guard CECTunnel.writeAllowed(address, bytes) else {
            forbiddenWrites += 1
            return false
        }
        for (offset, byte) in bytes.enumerated() { registers[address + UInt32(offset)] = byte }
        if address == 0x3020, let reads = corercdSendsAfterTXWrite {
            busyReads = reads
            corercdSendsAfterTXWrite = nil
        }
        if address == 0x3003 {
            pendingSendReads = sendReads
            sends += 1
        }
        return true
    }

    var txBufferWrites: [[UInt8]] { writes.filter { $0.address == 0x3020 }.map(\.bytes) }

    private func tickTX() {
        if let pending = pendingSendReads {
            // Our send: bit 7 (as written) until it's been read `sendReads` times.
            if pending > 0 {
                pendingSendReads = pending - 1
                return
            }
            registers[0x3003, default: 0] &= 0x7F
            registers[0x3004] = flagsAfterSend
            pendingSendReads = nil
            if reply != nil { replyAt = now() + replyDelay }
            return
        }
        // corercd's send.
        switch busyReads {
        case nil:
            registers[0x3003, default: 0] |= 0x80
        case let reads? where reads > 0:
            registers[0x3003, default: 0] |= 0x80
            busyReads = reads - 1
        default:
            registers[0x3003, default: 0] &= 0x7F
        }
    }

    private func advanceRX() {
        let time = now()
        if let at = replyAt, time >= at, let reply {
            for (offset, byte) in reply.enumerated() { registers[0x3010 + UInt32(offset)] = byte }
            registers[0x3002] = (registers[0x3002, default: 0] & 0x30) | UInt8(reply.count - 1) | 0xC0
            if replyEdges[min(sends - 1, replyEdges.count - 1)] {
                registers[0x3004, default: 0] |= 0x01
                edgeEnd = edgeDuration.map { at + $0 }
            }
            replyAt = nil
        }
        if let end = edgeEnd, time >= end {
            registers[0x3004, default: 0] &= 0xFE
            edgeEnd = nil
        }
    }
}

nonisolated final class OpenCounter: @unchecked Sendable {
    var value = 0
}

/// M7h step 9 (reopened): the tunnel on a fake DPCD. Nothing here touches IOKit.
struct CECTunnelTests {
    let time = FakeCECTime()

    private func tunnel(_ device: FakeDPCD) -> CECTunnel {
        device.now = { [time] in time.nanoseconds }
        return CECTunnel(open: { .device(device) }, timing: time.timing)
    }

    // MARK: Availability

    @Test func readyWithTunnelingOnAndAddressFourInTheMask() async {
        let device = FakeDPCD()
        #expect(await tunnel(device).availability() == .ready)
        #expect(device.writes.isEmpty)
    }

    @Test func devMacMaskWithoutAddressFourIsNotAvailableAndSendsNothing() async {
        // The dev Mac: the same converter, tunneling on, no address claimed (mask 0x00/0x00).
        let device = FakeDPCD()
        device.registers[0x300E] = 0x00
        device.registers[0x300F] = 0x00
        let tunnel = tunnel(device)
        #expect(await tunnel.availability() == .notAvailable)
        #expect(await tunnel.send(.standbyAll) == .unavailable(.notAvailable))
        #expect(await tunnel.send(.imageViewOn) == .unavailable(.notAvailable))
        #expect(await tunnel.powerStatus() == nil)
        #expect(device.writes.isEmpty)
        // Broadcast alone isn't enough.
        device.registers[0x300F] = 0x80
        #expect(await tunnel.availability() == .notAvailable)
        #expect(device.writes.isEmpty)
    }

    @Test func tunnelingOffOrNotCapableIsNotAvailable() async {
        let off = FakeDPCD()
        off.registers[0x3001] = 0x00
        #expect(await tunnel(off).availability() == .notAvailable)
        #expect(await tunnel(off).send(.standbyAll) == .unavailable(.notAvailable))
        #expect(off.writes.isEmpty)
        let incapable = FakeDPCD()
        incapable.registers[0x3000] = 0x00
        #expect(await tunnel(incapable).availability() == .notAvailable)
        #expect(incapable.writes.isEmpty)
    }

    @Test func noDisplayAndMissingSymbols() async {
        let none = CECTunnel(open: { .noDisplay }, timing: time.timing)
        #expect(await none.availability() == .noDisplay)
        #expect(await none.send(.standbyAll) == .unavailable(.noDisplay))
        let missing = CECTunnel(open: { .notAvailable("IOKit's DisplayPort calls are missing") }, timing: time.timing)
        #expect(await missing.availability() == .notAvailable)
    }

    @Test func unreadableRegistersAreNotAvailable() async {
        let device = FakeDPCD()
        device.readsFail = true
        #expect(await tunnel(device).availability() == .notAvailable)
        #expect(device.writes.isEmpty)
    }

    @Test func aStaleDeviceIsOpenedAgain() async {
        let first = FakeDPCD()
        let second = FakeDPCD()
        let opens = OpenCounter()
        let tunnel = CECTunnel(open: {
            opens.value += 1
            return .device(opens.value == 1 ? first : second)
        }, timing: time.timing)
        #expect(await tunnel.availability() == .ready)
        // After a hot-plug the old device's reads fail: the tunnel opens a fresh one.
        first.readsFail = true
        #expect(await tunnel.availability() == .ready)
        #expect(opens.value == 2)
        // `invalidate` (a hot-plug event) drops it too.
        tunnel.invalidate()
        #expect(await tunnel.availability() == .ready)
        #expect(opens.value == 3)
    }

    // MARK: Sending

    @Test func sendWritesTheTXBufferThenTXInfoAndWaitsForTheSendBit() async {
        let device = FakeDPCD()
        #expect(await tunnel(device).send(.standbyAll) == .sent)
        #expect(device.writes.map(\.address) == [0x3020, 0x3003])
        #expect(device.writes.map(\.bytes) == [[0x4F, 0x36], [0xB1]])
        #expect(device.forbiddenWrites == 0)
        #expect(device.registers[0x3003]! & 0x80 == 0)
        // Nothing but the TX buffer and TX info, ever: control, the mask and the flags are untouched.
        #expect(device.registers[0x3001] == 0x01)
        #expect(device.registers[0x300E] == 0x10)
        #expect(device.registers[0x300F] == 0x80)
    }

    @Test func busyWaitForAnotherSendThenSends() async {
        let device = FakeDPCD()
        device.busyReads = 10   // ~100 ms of corercd's send
        #expect(await tunnel(device).send(.imageViewOn) == .sent)
        #expect(device.txBufferWrites == [[0x40, 0x04]])
        #expect(time.nanoseconds >= 100_000_000)
    }

    @Test func aSendStillInProgressAfter500MillisecondsWritesNothing() async {
        let device = FakeDPCD()
        device.busyReads = nil   // never clears
        let result = await tunnel(device).send(.standbyAll)
        #expect(result == .busy)
        #expect(!result.mayHaveGoneOut)
        #expect(device.writes.isEmpty)
        #expect(time.nanoseconds >= 500_000_000)
        #expect(time.nanoseconds < 600_000_000)
    }

    /// Security low 1: corercd starts a send between our busy check and the TX buffer write. Our bytes are already in
    /// the TX buffer and may go out with that send, so the result is `.collided` (may have gone out), not `.busy`;
    /// TX info is left alone.
    @Test func aSendStartedDuringTheTXBufferWriteLeavesTXInfoAlone() async {
        let device = FakeDPCD()
        device.corercdSendsAfterTXWrite = 3
        let result = await tunnel(device).send(.standbyAll)
        #expect(result == .collided)
        #expect(result.mayHaveGoneOut)
        #expect(device.writes.map(\.address) == [0x3020])
        #expect(!device.writes.contains { $0.address == 0x3003 })
        #expect(device.sends == 0)
    }

    /// Security low 2: the IOKit signatures come from disassembly; a device whose DPCD revision isn't plausible
    /// gets no writes.
    @Test func anImplausibleDPCDRevisionIsNotAvailable() async {
        for revision: UInt8 in [0x00, 0x0F, 0x15, 0x20, 0xEE, 0xFF] {
            let device = FakeDPCD()
            device.registers[0x0000] = revision
            let tunnel = tunnel(device)
            #expect(await tunnel.availability() == .notAvailable, "\(revision)")
            #expect(await tunnel.send(.standbyAll) == .unavailable(.notAvailable))
            #expect(await tunnel.powerStatus() == nil)
            #expect(device.writes.isEmpty)
        }
        for revision: UInt8 in [0x10, 0x11, 0x12, 0x14] {
            let device = FakeDPCD()
            device.registers[0x0000] = revision
            #expect(await tunnel(device).send(.standbyAll) == .sent, "\(revision)")
        }
    }

    @Test func theRevisionIsCheckedOncePerOpenedDevice() async {
        let device = FakeDPCD()
        let tunnel = tunnel(device)
        #expect(await tunnel.send(.standbyAll) == .sent)
        // Read once; a later change on the same opened device isn't re-read (it's checked again after reopening).
        device.registers[0x0000] = 0x00
        #expect(await tunnel.send(.standbyAll) == .sent)
        tunnel.invalidate()
        #expect(await tunnel.send(.standbyAll) == .unavailable(.notAvailable))
    }

    @Test func aSendBitThatNeverClearsTimesOut() async {
        let device = FakeDPCD()
        device.sendReads = 1000
        #expect(await tunnel(device).send(.standbyAll) == .timedOut)
        #expect(device.writes.count == 2)
    }

    @Test func aNackOnADirectedFrameIsReportedButNotOnABroadcast() async {
        let directed = FakeDPCD()
        directed.flagsAfterSend = 0x40
        #expect(await tunnel(directed).send(.imageViewOn) == .notAcknowledged)
        let broadcast = FakeDPCD()
        broadcast.flagsAfterSend = 0x40
        #expect(await tunnel(broadcast).send(.standbyAll) == .sent)
        let acked = FakeDPCD()
        acked.flagsAfterSend = 0x10
        #expect(await tunnel(acked).send(.imageViewOn) == .sent)
    }

    // MARK: Power status

    @Test func powerStatusReadsTheTVsReply() async {
        for (byte, status) in [(UInt8(0), CECPowerStatus.on), (1, .standby), (2, .standbyToOn), (3, .onToStandby)] {
            let device = FakeDPCD()
            device.reply = [0x04, 0x90, byte]
            #expect(await tunnel(device).powerStatus() == status)
            #expect(device.txBufferWrites == [[0x40, 0x8F]])
            #expect(device.forbiddenWrites == 0)
        }
    }

    @Test func noReplyIsUnknownAfterOneRetry() async {
        let device = FakeDPCD()
        #expect(await tunnel(device).powerStatus() == nil)
        // Asked twice, 1 s each. The last frame in the RX buffer (the receiver's 5F:72:01) isn't an answer.
        #expect(device.txBufferWrites == [[0x40, 0x8F], [0x40, 0x8F]])
        #expect(time.nanoseconds >= 2_000_000_000)
        #expect(!device.writes.contains { $0.address == 0x3004 })
    }

    /// The mini's RX buffer already holds the TV's last `04:90:00`, with the same RX info: the new reply's bytes are
    /// identical. DCP clears RX valid after 5 ms, so only the 5 ms flag poll sees the edge (the 10 ms change check
    /// sees nothing new).
    private static func identicalReplyDevice() -> FakeDPCD {
        let device = FakeDPCD()
        device.registers[0x3010] = 0x04
        device.registers[0x3011] = 0x90
        device.registers[0x3012] = 0x00
        device.registers[0x3002] = 0xD2
        device.reply = [0x04, 0x90, 0x00]
        device.edgeDuration = 5_000_000
        return device
    }

    @Test func anIdenticalReplyIsCaughtByTheRXValidEdge() async {
        let device = Self.identicalReplyDevice()
        #expect(await tunnel(device).powerStatus() == .on)
        #expect(device.txBufferWrites == [[0x40, 0x8F]])   // no retry needed
        #expect(!device.writes.contains { $0.address == 0x3004 })
        #expect(time.nanoseconds < 1_000_000_000)
    }

    @Test func anIdenticalReplyWithoutAnEdgeIsCaughtOnTheRetry() async {
        let device = Self.identicalReplyDevice()
        device.replyEdges = [false, true]   // the first reply is invisible: same bytes, same RX info, no edge
        #expect(await tunnel(device).powerStatus() == .on)
        #expect(device.txBufferWrites == [[0x40, 0x8F], [0x40, 0x8F]])
        #expect(time.nanoseconds >= 1_000_000_000)
        #expect(!device.writes.contains { $0.address == 0x3004 })
    }

    @Test func anIdenticalReplyNeverSeenIsUnknownAfterTheRetry() async {
        let device = Self.identicalReplyDevice()
        device.replyEdges = [false]
        #expect(await tunnel(device).powerStatus() == nil)
        #expect(device.txBufferWrites == [[0x40, 0x8F], [0x40, 0x8F]])
        #expect(device.sends == 2)   // one retry only
        #expect(!device.writes.contains { $0.address == 0x3004 })
    }

    @Test func otherFramesAreSkippedAndAnUnknownStatusIsNoAnswer() async {
        let other = FakeDPCD()
        other.reply = [0x5F, 0x72, 0x01]
        #expect(await tunnel(other).powerStatus() == nil)
        let unknown = FakeDPCD()
        unknown.reply = [0x04, 0x90, 0x07]
        #expect(await tunnel(unknown).powerStatus() == nil)
    }

    @Test func aStatusQueryThatIsntSentIsUnknownWithoutARetry() async {
        let device = FakeDPCD()
        device.reply = [0x04, 0x90, 0x00]
        device.flagsAfterSend = 0x40   // the TV didn't acknowledge
        #expect(await tunnel(device).powerStatus() == nil)
        #expect(device.sends == 1)
    }

    @Test func nothingIsEverWrittenToTheIRQFlags() async {
        // Every scenario's tunnel calls, on one device each: only 0x3020… and 0x3003 are written.
        for setUp in [{ (_: FakeDPCD) in }, { $0.reply = [0x04, 0x90, 0x01] }, { $0.busyReads = 5 },
                      { $0.flagsAfterSend = 0xD1 }, { $0.reply = [0x04, 0x90, 0x00]; $0.edgeDuration = 1_000_000 }, { $0.corercdSendsAfterTXWrite = 3 }] {
            let device = FakeDPCD()
            setUp(device)
            let tunnel = tunnel(device)
            _ = await tunnel.send(.standbyAll)
            _ = await tunnel.powerStatus()
            _ = await tunnel.send(.imageViewOn)
            #expect(device.writes.allSatisfy { $0.address == 0x3003 || (0x3020...0x302F).contains($0.address) })
            #expect(device.forbiddenWrites == 0)
        }
    }
}
