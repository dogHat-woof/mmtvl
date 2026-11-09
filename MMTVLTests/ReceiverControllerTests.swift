import Foundation
import Testing
@testable import MMTVL

/// Time that moves only when the controller sleeps.
final class FakeReceiverClock: ReceiverClock {
    var now: Duration = .zero

    func sleep(for duration: Duration) async {
        now += duration
        await Task.yield()
    }
}

/// Records writes with the fake time; answers scripted replies at once.
final class FakeReceiverTransport: ReceiverTransport {
    let name = "Fake port"
    let brand: ReceiverBrand
    var onLine: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onReady: (() -> Void)?
    /// L17: false until `becomeReady()` (a TCP connection coming up); serial fakes start ready.
    var isReady = true
    private(set) var closedForConfiguration = false
    /// Step 11: what the TCP transport would say ("Connection refused").
    var failureReason: String?
    private let clock: any ReceiverClock
    /// Lines delivered when these exact bytes are written.
    var replies: [[UInt8]: [String]] = [:]
    private(set) var writes: [(bytes: [UInt8], at: Duration)] = []
    private(set) var isClosed = false

    init(brand: ReceiverBrand, clock: any ReceiverClock) {
        self.brand = brand
        self.clock = clock
    }

    func write(_ bytes: [UInt8]) -> Bool {
        writes.append((bytes, clock.now))
        for line in replies[bytes] ?? [] { onLine?(line) }
        return true
    }

    func close() { isClosed = true }

    /// The port was unplugged (or the connection failed).
    func unplug() { onClose?() }

    func becomeReady() {
        isReady = true
        onReady?()
    }

    /// The name resolved outside the LAN (`ReceiverTCPTransport` at `.ready`).
    func refuseAsNotLAN() {
        closedForConfiguration = true
        isReady = false
        onClose?()
    }
}

/// Makes one fake transport per call; `available = false` means no port.
final class FakeReceiverPorts {
    let clock: any ReceiverClock
    var available = true
    /// L17: whether made transports are ready at once (serial) or wait for `becomeReady()` (TCP).
    var startsReady = true
    /// Per brand, query reply lines (by command).
    var replies: [ReceiverBrand: [ReceiverCommand: [String]]] = [:]
    private(set) var made: [FakeReceiverTransport] = []
    /// Serial paths asked for (network links are in `links` only).
    private(set) var paths: [String?] = []
    private(set) var links: [ReceiverLink] = []

    init(clock: any ReceiverClock) { self.clock = clock }

    func make(link: ReceiverLink, codec: any ReceiverProtocol) -> (any ReceiverTransport)? {
        links.append(link)
        if case .serial(let path) = link { paths.append(path) }
        guard available else { return nil }
        let transport = FakeReceiverTransport(brand: codec.brand, clock: clock)
        transport.isReady = startsReady
        for (command, lines) in replies[codec.brand] ?? [:] { transport.replies[codec.encode(command)] = lines }
        made.append(transport)
        return transport
    }
}

struct ReceiverControllerTests {
    private let clock: FakeReceiverClock
    private let ports: FakeReceiverPorts
    private let controller: ReceiverController

    init() {
        let clock = FakeReceiverClock()
        let ports = FakeReceiverPorts(clock: clock)
        self.clock = clock
        self.ports = ports
        controller = ReceiverController(clock: clock, makeTransport: { ports.make(link: $0, codec: $1) })
    }

    private static func text(_ string: String) -> [UInt8] { Array(string.utf8) }

    @Test func noneOpensNothing() {
        controller.configure(brand: .none, serialPort: nil)
        #expect(ports.paths.isEmpty)
        #expect(!controller.isConnected)
    }

    @Test func configureOpensThePort() {
        controller.configure(brand: .pioneer, serialPort: "/dev/cu.test")
        #expect(ports.paths == ["/dev/cu.test"])
        #expect(controller.isConnected)
        controller.stop()
        #expect(ports.made.first?.isClosed == true)
        #expect(!controller.isConnected)
    }

    /// Research: from standby Pioneer's first `PO` only wakes the CPU; the second, ≥ 100 ms later, turns it on.
    @Test func pioneerPowerOnSendsTwiceAtLeast100msApart() async throws {
        controller.configure(brand: .pioneer, serialPort: nil)
        let written = await controller.send(.powerOn)
        #expect(written)
        let port = try #require(ports.made.first)
        // A bare CR wakes the receiver first, then PO twice.
        #expect(port.writes.map(\.bytes) == [[0x0D], Self.text("PO\r"), Self.text("PO\r")])
        #expect(port.writes[2].at - port.writes[1].at >= .milliseconds(100))
        #expect(port.writes[1].at - port.writes[0].at >= .milliseconds(100))
    }

    @Test func otherBrandsSendPowerOnOnce() async throws {
        controller.configure(brand: .onkyo, serialPort: nil)
        await controller.send(.powerOn)
        let port = try #require(ports.made.first)
        #expect(port.writes.map(\.bytes) == [Self.text("!1PWR01\r")])
    }

    @Test func minimumGapIsHonored() async throws {
        controller.configure(brand: .pioneer, serialPort: nil)
        for _ in 0..<3 { await controller.send(.volumeUp) }
        await controller.send(.queryVolume)
        let port = try #require(ports.made.first)
        #expect(port.writes.count == 5)   // the wake CR and four commands
        for (earlier, later) in zip(port.writes, port.writes.dropFirst()) {
            #expect(later.at - earlier.at >= PioneerProtocol().minimumGap)
        }
    }

    @Test func concurrentSendsKeepTheGapAndAllArrive() async throws {
        controller.configure(brand: .onkyo, serialPort: nil)
        async let first = controller.send(.volumeUp)
        async let second = controller.send(.volumeDown)
        async let third = controller.send(.queryMute)
        _ = await (first, second, third)
        let port = try #require(ports.made.first)
        #expect(port.writes.count == 3)
        #expect(Set(port.writes.map(\.bytes)) == [Self.text("!1MVLUP\r"), Self.text("!1MVLDOWN\r"), Self.text("!1AMTQSTN\r")])
        for (earlier, later) in zip(port.writes, port.writes.dropFirst()) {
            #expect(later.at - earlier.at >= OnkyoProtocol().minimumGap)
        }
    }

    @Test func denonWaitsAfterPowerOn() async throws {
        controller.configure(brand: .denon, serialPort: nil)
        await controller.send(.powerOn)
        await controller.send(.queryPower)
        let port = try #require(ports.made.first)
        #expect(port.writes.count == 2)
        #expect(port.writes[1].at - port.writes[0].at >= .seconds(1))
    }

    /// Step 1: `PF` sometimes gets no reply though the receiver turns off; that isn't a failure.
    @Test func powerCommandWithoutReplyIsNotAFailure() async {
        controller.configure(brand: .pioneer, serialPort: nil)
        #expect(await controller.send(.powerOff))
        #expect(controller.isConnected)
    }

    @Test func sendWithoutAPortFails() async {
        #expect(!(await controller.send(.volumeUp)))
        ports.available = false
        controller.configure(brand: .pioneer, serialPort: nil)
        #expect(!(await controller.send(.volumeUp)))
        controller.stop()
    }

    @Test func statusComesFromRepliesAndUnsolicitedLines() throws {
        var changes = 0
        controller.onStatusChange = { changes += 1 }
        controller.configure(brand: .pioneer, serialPort: nil)
        let port = try #require(ports.made.first)
        port.onLine?("VOL61")
        port.onLine?("SR0219")   // unknown: ignored
        port.onLine?("LM219")
        port.onLine?("MUT1")
        port.onLine?("PWR0")
        #expect(controller.state.volume == ReceiverVolume(raw: 61, dB: -20))
        #expect(controller.state.muted == false)
        #expect(controller.state.power == true)
        #expect(changes == 3)
        #expect(controller.lastReplyAt != nil)
        port.onLine?("PWR0")   // the same again: no change
        #expect(changes == 3)
    }

    @Test func testReportsEachQuerysReply() async throws {
        ports.replies[.pioneer] = [.queryPower: ["PWR0"], .queryVolume: ["VOL61"], .queryMute: ["MUT1"]]
        controller.configure(brand: .pioneer, serialPort: nil)
        let result = await controller.test()
        #expect(result.power == true)
        #expect(result.volume?.dB == -20)
        #expect(result.muted == false)
        let port = try #require(ports.made.first)
        let sent = port.writes.map(\.bytes).filter { $0 != [0x0D] }
        #expect(sent == PioneerProtocol().probeQueries.map(PioneerProtocol().encode))
    }

    @Test func testWithoutAnswersTimesOut() async {
        controller.configure(brand: .denon, serialPort: nil)
        let start = clock.now
        let result = await controller.test()
        #expect(result.isEmpty)
        #expect(clock.now - start >= ReceiverController.replyTimeout * 3)
    }

    @Test func testWithoutAPortIsEmpty() async {
        let result = await controller.test()
        #expect(result.isEmpty)
    }

    /// L12: each brand in order until one answers; only read-only queries (and the wake CR) are ever written.
    @Test func findStopsAtTheFirstBrandThatAnswers() async throws {
        ports.replies[.denon] = [.queryPower: ["PWON"]]
        ports.replies[.anthem] = [.queryPower: ["Z1POW1"]]
        let found = await controller.find(onPort: "/dev/cu.test")
        #expect(found == .denon)
        #expect(ports.made.map(\.brand) == [.pioneer, .onkyo, .denon])
        #expect(ports.paths.allSatisfy { $0 == "/dev/cu.test" })
        for port in ports.made {
            let codec = try #require(port.brand.codec)
            let allowed = Set(codec.probeQueries.filter(\.isQuery).map(codec.encode)).union([codec.wakeRule.onOpen])
            for write in port.writes {
                #expect(allowed.contains(write.bytes), "\(port.brand) wrote \(write.bytes)")
            }
            #expect(port.isClosed)
        }
        // Brands that didn't answer had the whole 2 s.
        let pioneer = try #require(ports.made.first)
        #expect(pioneer.writes.count == 4)   // CR, ?P, ?V, ?M
    }

    @Test func findNeverEncodesANonQuery() async {
        let found = await controller.find(onPort: nil)
        #expect(found == nil)
        #expect(ports.made.map(\.brand) == ReceiverBrand.supported)
        let nonQueries: [ReceiverCommand] = [.powerOn, .powerOff, .volumeUp, .volumeDown, .mute(true), .mute(false)]
        for port in ports.made {
            let codec = port.brand.codec!
            let forbidden = Set(nonQueries.map(codec.encode))
            #expect(port.writes.allSatisfy { !forbidden.contains($0.bytes) }, "\(port.brand)")
        }
    }

    @Test func findGivesEachBrandTwoSeconds() async {
        let start = clock.now
        _ = await controller.find(onPort: nil)
        #expect(clock.now - start >= ReceiverController.findTimeout * ReceiverBrand.supported.count)
    }

    @Test func findReopensTheConfiguredPort() async throws {
        ports.replies[.pioneer] = [.queryPower: ["PWR1"]]
        controller.configure(brand: .onkyo, serialPort: "/dev/cu.configured")
        let configured = try #require(ports.made.first)
        let found = await controller.find(onPort: "/dev/cu.other")
        #expect(found == .pioneer)
        #expect(configured.isClosed)
        #expect(ports.paths == ["/dev/cu.configured", "/dev/cu.other", "/dev/cu.configured"])
        #expect(controller.isConnected)
        #expect(controller.brand == .onkyo)
        #expect(ports.made.last?.isClosed == false)
    }

    @Test func reconnectsWhenThePortGoesAway() async throws {
        controller.configure(brand: .pioneer, serialPort: nil)
        let first = try #require(ports.made.first)
        ports.available = false
        first.unplug()
        #expect(!controller.isConnected)
        // A few attempts fail while the adapter is out.
        for _ in 0..<2000 where ports.paths.count < 3 { await Task.yield() }
        #expect(ports.paths.count >= 3)
        ports.available = true
        for _ in 0..<2000 where !controller.isConnected { await Task.yield() }
        #expect(controller.isConnected)
        #expect(ports.made.count == 2)
        // The new port gets the wake CR again before its first command.
        await controller.send(.queryPower)
        #expect(ports.made.last?.writes.map(\.bytes) == [[0x0D], Self.text("?P\r")])
        controller.stop()
    }

    @Test func aMissingPortAtConfigureIsRetried() async {
        ports.available = false
        controller.configure(brand: .nad, serialPort: nil)
        #expect(!controller.isConnected)
        ports.available = true
        for _ in 0..<2000 where !controller.isConnected { await Task.yield() }
        #expect(controller.isConnected)
        controller.stop()
    }

    @Test func stopEndsReconnecting() async {
        ports.available = false
        controller.configure(brand: .pioneer, serialPort: nil)
        controller.stop()
        for _ in 0..<20 { await Task.yield() }
        let attempts = ports.paths.count
        for _ in 0..<20 { await Task.yield() }
        #expect(ports.paths.count == attempts)
        #expect(attempts <= 2)
    }

    @Test func linesFromAClosedPortAreIgnored() throws {
        controller.configure(brand: .pioneer, serialPort: nil)
        let first = try #require(ports.made.first)
        let onLine = first.onLine
        controller.configure(brand: .pioneer, serialPort: nil)
        onLine?("PWR0")
        #expect(controller.state.power == nil)
    }

    // MARK: QA fixes

    /// Yields until `condition` holds (bounded).
    private func yield(until condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() { await Task.yield() }
    }

    /// QA 1: `stop()` while Find runs: nothing is reopened afterwards.
    @Test func stopDuringFindLeavesThePortClosed() async {
        controller.configure(brand: .pioneer, serialPort: "/dev/cu.configured")
        let finding = Task { await controller.find(onPort: "/dev/cu.other") }
        await yield { ports.made.count >= 2 }   // the configured port, then Find's first probe
        controller.stop()
        _ = await finding.value
        #expect(!controller.isConnected)
        let opened = ports.paths.count
        for _ in 0..<200 { await Task.yield() }
        #expect(ports.paths.count == opened)
        #expect(!ports.paths.dropFirst().contains("/dev/cu.configured"))
    }

    /// QA 1: `configure(.none)` while Find runs: no reopening and no reconnect loop.
    @Test func configureNoneDuringFindOpensNothingAfterwards() async {
        controller.configure(brand: .pioneer, serialPort: "/dev/cu.configured")
        let finding = Task { await controller.find(onPort: "/dev/cu.other") }
        await yield { ports.made.count >= 2 }
        controller.configure(brand: .none, serialPort: nil)
        _ = await finding.value
        #expect(!controller.isConnected)
        let opened = ports.paths.count
        for _ in 0..<200 { await Task.yield() }
        #expect(ports.paths.count == opened)
    }

    /// QA 1: a new configuration during Find keeps its own port; Find doesn't reopen the old one over it.
    @Test func configureDuringFindKeepsTheNewPort() async throws {
        controller.configure(brand: .pioneer, serialPort: "/dev/cu.configured")
        let finding = Task { await controller.find(onPort: "/dev/cu.other") }
        await yield { ports.made.count >= 2 }
        controller.configure(brand: .denon, serialPort: "/dev/cu.new")
        let fresh = try #require(ports.made.last)
        #expect(fresh.brand == .denon)
        _ = await finding.value
        #expect(controller.isConnected)
        #expect(controller.brand == .denon)
        #expect(!fresh.isClosed)
        let opened = ports.paths.count
        for _ in 0..<200 { await Task.yield() }
        #expect(ports.paths.count == opened)
        #expect(ports.paths.last != "/dev/cu.configured")
    }

    /// QA 1: a reconnect loop stops once a port is open, however it was opened.
    @Test func reconnectLoopStopsAfterAnyConnect() async {
        ports.available = false
        controller.configure(brand: .pioneer, serialPort: nil)
        ports.available = true
        _ = await controller.find(onPort: nil)   // reopens the configured port at the end
        #expect(controller.isConnected)
        let opened = ports.paths.count
        for _ in 0..<200 { await Task.yield() }
        #expect(ports.paths.count == opened)
    }

    /// QA 2: a command waiting for the gap when `configure` changes the brand is dropped, not written with the old
    /// brand's bytes to the new port.
    @Test func commandQueuedBeforeConfigureIsDropped() async throws {
        controller.configure(brand: .pioneer, serialPort: nil)
        let old = try #require(ports.made.first)
        let sending = Task { await controller.send(.volumeUp) }
        await yield { old.writes.count >= 1 }   // the wake CR is out; VU waits for the gap
        #expect(old.writes.map(\.bytes) == [[0x0D]])
        controller.configure(brand: .onkyo, serialPort: nil)
        let written = await sending.value
        #expect(!written)
        let fresh = try #require(ports.made.last)
        #expect(fresh !== old)
        #expect(!fresh.writes.contains { $0.bytes == Self.text("VU\r") })
        #expect(!old.writes.contains { $0.bytes == Self.text("VU\r") })
        // Commands queued after the change go out with the new codec.
        await controller.send(.volumeUp)
        #expect(fresh.writes.map(\.bytes) == [Self.text("!1MVLUP\r")])
    }

    /// QA 3: every Test starts with the wake bytes, not only the first on an open port.
    @Test func eachTestStartsWithTheWakeBytes() async throws {
        ports.replies[.pioneer] = [.queryPower: ["PWR0"], .queryVolume: ["VOL61"], .queryMute: ["MUT1"]]
        controller.configure(brand: .pioneer, serialPort: nil)
        _ = await controller.test()
        let second = await controller.test()
        #expect(second.power == true)
        let port = try #require(ports.made.first)
        let run = [[0x0D], Self.text("?P\r"), Self.text("?V\r"), Self.text("?M\r")]
        #expect(port.writes.map(\.bytes) == run + run)
        for (earlier, later) in zip(port.writes, port.writes.dropFirst()) {
            #expect(later.at - earlier.at >= PioneerProtocol().minimumGap)
        }
    }

    /// QA 5: only `/dev/cu.*` paths are opened as given; anything else is Automatic.
    @Test func serialPortPathMustBeCallout() {
        let usb = SerialPortInfo(path: "/dev/cu.usbserial-XXXXXXXX", usbProductName: "FT232R USB UART")
        let bluetooth = SerialPortInfo(path: "/dev/cu.Bluetooth-Incoming-Port", usbProductName: nil)
        let listed = [usb, bluetooth]
        #expect(SerialPort.port(for: "/dev/tty.usbserial-XXXXXXXX", available: listed) == usb)
        #expect(SerialPort.port(for: "/dev/tty.usbserial-XXXXXXXX", available: [bluetooth]) == nil)
        #expect(SerialPort.port(for: "/dev/cu./../tty.usbserial-X", available: []) == nil)
        #expect(SerialPort.port(for: "/tmp/cu.fake", available: []) == nil)
        #expect(SerialPort.port(for: nil, available: listed) == usb)
        #expect(SerialPort.port(for: "/dev/cu.Bluetooth-Incoming-Port", available: listed) == bluetooth)
        #expect(SerialPort.port(for: "/dev/cu.usbserial-OTHER", available: listed)?.path == "/dev/cu.usbserial-OTHER")
    }

    /// M7h step 10: answering = a reply since `configure`, and the last `request` got its reply.
    @Test func isAnsweringFollowsRequestsAndReplies() async throws {
        ports.replies[.pioneer] = [.queryVolume: ["VOL61"], .volumeUp: ["VOL62"], .mute(true): ["MUT0"]]
        #expect(!controller.isAnswering)
        controller.configure(brand: .pioneer, serialPort: nil)
        #expect(!controller.isAnswering)
        #expect(await controller.request(.queryVolume) == .volume(raw: 61, dB: -20))
        #expect(controller.isAnswering)
        #expect(await controller.request(.volumeUp) == .volume(raw: 62, dB: -19))
        #expect(await controller.request(.mute(true)) == .muted(true))
        // No reply within `replyTimeout`: not answering, until any line parses again.
        #expect(await controller.request(.volumeDown) == nil)
        #expect(!controller.isAnswering)
        let port = try #require(ports.made.first)
        port.onLine?("VOL60")
        #expect(controller.isAnswering)
        // A new configuration starts over.
        controller.configure(brand: .pioneer, serialPort: nil)
        #expect(!controller.isAnswering)
    }

    /// Step 10 QA minor 2: a serial port is up when it's opened, and again when it's reopened.
    @Test func linkUpWhenThePortOpens() async throws {
        var ups = 0
        controller.onLinkUp = { ups += 1 }
        controller.configure(brand: .pioneer, serialPort: nil)
        #expect(ups == 1)
        try #require(ports.made.last).unplug()
        for _ in 0..<2000 where ups < 2 { await Task.yield() }
        #expect(ups == 2)
        controller.stop()
    }

    @Test func requestWaitsForTheRightKindOfReply() async throws {
        // The receiver answers VU with an unrelated line only: that isn't the reply.
        ports.replies[.pioneer] = [.volumeUp: ["PWR0"]]
        controller.configure(brand: .pioneer, serialPort: nil)
        let start = clock.now
        #expect(await controller.request(.volumeUp) == nil)
        #expect(clock.now - start >= ReceiverController.replyTimeout)
        #expect(!controller.isAnswering)
    }
}

/// Time that moves only when a test advances it; sleepers wake in order of their deadlines.
final class ManualReceiverClock: ReceiverClock {
    private(set) var now: Duration = .zero
    private var sleepers: [(until: Duration, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(for duration: Duration) async {
        let until = now + duration
        await withCheckedContinuation { continuation in
            sleepers.append((until, continuation))
        }
    }

    /// Moves time forward by `duration`, waking each sleeper due by then (each runs until it sleeps again or ends).
    func advance(by duration: Duration) async {
        let target = now + duration
        while true {
            await settle()
            guard let index = sleepers.indices.filter({ sleepers[$0].until <= target })
                .min(by: { sleepers[$0].until < sleepers[$1].until }) else { break }
            let sleeper = sleepers.remove(at: index)
            now = max(now, sleeper.until)
            sleeper.continuation.resume()
        }
        now = target
        await settle()
    }

    func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}

/// M7h L17: the controller over a network link (fake transports; the TCP transport itself is untested on a real
/// receiver).
struct ReceiverControllerNetworkTests {
    private let clock: ManualReceiverClock
    private let ports: FakeReceiverPorts
    private let controller: ReceiverController
    private static let link = ReceiverLink.network(host: "192.168.1.20", port: nil)

    init() {
        let clock = ManualReceiverClock()
        let ports = FakeReceiverPorts(clock: clock)
        self.clock = clock
        self.ports = ports
        controller = ReceiverController(clock: clock, makeTransport: { ports.make(link: $0, codec: $1) })
    }

    private static func text(_ string: String) -> [UInt8] { Array(string.utf8) }

    /// Ends the controller's tasks.
    private func finish() async {
        controller.stop()
        await clock.advance(by: .seconds(1000))
    }

    @Test func networkLinkGoesToTheFactory() async {
        controller.configure(brand: .onkyo, link: Self.link)
        #expect(ports.links == [Self.link])
        #expect(ports.paths.isEmpty)
        #expect(controller.portPath == nil)
        #expect(controller.link == Self.link)
        await finish()
    }

    @Test func commandsWaitForTheConnection() async throws {
        ports.startsReady = false
        controller.configure(brand: .onkyo, link: Self.link)
        let transport = try #require(ports.made.first)
        let sending = Task { await controller.send(.powerOn) }
        await clock.advance(by: .milliseconds(500))
        #expect(transport.writes.isEmpty)
        transport.becomeReady()
        await clock.advance(by: .milliseconds(100))
        #expect(await sending.value)
        #expect(transport.writes.map(\.bytes) == [Self.text("!1PWR01\r")])
        await finish()
    }

    @Test func aConnectionThatNeverComesUpFailsTheCommand() async throws {
        ports.startsReady = false
        controller.configure(brand: .denon, link: Self.link)
        let transport = try #require(ports.made.first)
        let sending = Task { await controller.send(.queryPower) }
        await clock.advance(by: ReceiverController.readyTimeout + .milliseconds(100))
        #expect(!(await sending.value))
        #expect(transport.writes.isEmpty)
        await finish()
    }

    /// L17: reconnect after 1, 2, 5, then every 10 s; back to 1 s once a connection stayed up 10 s.
    @Test func reconnectBacksOff() async throws {
        ports.startsReady = false
        controller.configure(brand: .yamaha, link: Self.link)
        for (attempt, delay) in [1, 2, 5, 10, 10].enumerated() {
            let made = ports.made.count
            try #require(made == attempt + 1)
            ports.made.last?.unplug()   // refused
            await clock.advance(by: .seconds(delay) - .milliseconds(10))
            #expect(ports.made.count == made, "attempt \(attempt) came early")
            await clock.advance(by: .milliseconds(10))
            #expect(ports.made.count == made + 1, "attempt \(attempt) after \(delay) s")
        }
        let up = try #require(ports.made.last)
        up.becomeReady()
        await clock.advance(by: ReceiverController.stableConnection)
        up.unplug()   // dropped after it was up a while
        let made = ports.made.count
        await clock.advance(by: .seconds(1))
        #expect(ports.made.count == made + 1)
        await finish()
    }

    /// Security L1: a host that accepts and closes at once isn't retried every second; the waits keep growing.
    @Test func aConnectionThatClosesAtOnceKeepsBackingOff() async throws {
        ports.startsReady = false
        controller.configure(brand: .denon, link: Self.link)
        for (attempt, delay) in [1, 2, 5, 10].enumerated() {
            let made = ports.made.count
            let transport = try #require(ports.made.last)
            transport.becomeReady()
            await clock.advance(by: .milliseconds(50))
            transport.unplug()
            await clock.advance(by: .seconds(delay) - .milliseconds(10))
            #expect(ports.made.count == made, "attempt \(attempt) came early")
            await clock.advance(by: .milliseconds(10))
            #expect(ports.made.count == made + 1, "attempt \(attempt) after \(delay) s")
        }
        await finish()
    }

    /// Re-review follow-up 1: a host that resolved outside the LAN is a configuration error: no reconnecting, no
    /// reopening after the idle close; only a reconfigure tries again.
    @Test func aHostOutsideTheLANIsNotRetried() async throws {
        ports.startsReady = false
        controller.configure(brand: .denon, link: .network(host: "receiver.example", port: nil))
        try #require(ports.links.count == 1)
        ports.made.first?.refuseAsNotLAN()
        #expect(!controller.isConnected)
        await clock.advance(by: .seconds(120))
        #expect(ports.links.count == 1)
        #expect(!(await controller.send(.queryPower)))
        await clock.advance(by: .seconds(400))   // past the idle close
        #expect(!(await controller.send(.queryPower)))
        await clock.advance(by: .seconds(60))
        #expect(ports.links.count == 1)
        controller.configure(brand: .denon, link: .network(host: "receiver.example", port: nil))
        #expect(ports.links.count == 2)
        await finish()
    }

    /// Security L1: a reply proves the link works, so the backoff starts over even on a short connection.
    @Test func aReplyStartsTheBackoffOver() async throws {
        ports.startsReady = false
        controller.configure(brand: .denon, link: Self.link)
        for _ in 0..<3 {   // push the backoff to 5 s
            ports.made.last?.unplug()
            await clock.advance(by: .seconds(5))
        }
        let transport = try #require(ports.made.last)
        transport.becomeReady()
        transport.onLine?("PWON")
        transport.unplug()
        let made = ports.made.count
        await clock.advance(by: .seconds(1))
        #expect(ports.made.count == made + 1)
        await finish()
    }

    /// QA minor 1: after an idle close and reopen, the first failure waits 1 s, not the old backoff's 10 s.
    @Test func idleReopenStartsTheBackoffOver() async throws {
        ports.startsReady = false
        controller.configure(brand: .onkyo, link: Self.link)
        for delay in [1, 2, 5, 10] {   // the backoff now at 10 s
            ports.made.last?.unplug()
            await clock.advance(by: .seconds(delay))
        }
        await clock.advance(by: .seconds(300))
        #expect(!controller.isConnected)
        let sending = Task { await controller.send(.queryPower) }
        await clock.settle()
        let reopened = try #require(ports.made.last)
        reopened.unplug()   // refused
        await clock.advance(by: .milliseconds(100))
        #expect(!(await sending.value))
        let made = ports.made.count
        await clock.advance(by: .milliseconds(890))
        #expect(ports.made.count == made)
        await clock.advance(by: .milliseconds(10))
        #expect(ports.made.count == made + 1)
        await finish()
    }

    /// Serial keeps its fixed 5 s.
    @Test func serialReconnectStaysAtFiveSeconds() async throws {
        controller.configure(brand: .pioneer, serialPort: nil)
        ports.available = false
        ports.made.first?.unplug()
        await clock.advance(by: .seconds(4))
        #expect(ports.paths.count == 1)
        await clock.advance(by: .seconds(1))
        #expect(ports.paths.count == 2)
        await clock.advance(by: .seconds(5))
        #expect(ports.paths.count == 3)
        await finish()
    }

    /// L17: closed after 5 minutes without commands; the next command opens it again.
    @Test func closesWhenIdleAndReopensOnDemand() async throws {
        controller.configure(brand: .onkyo, link: Self.link)
        let first = try #require(ports.made.first)
        await clock.advance(by: .seconds(299))
        #expect(!first.isClosed)
        await clock.advance(by: .seconds(1))
        #expect(first.isClosed)
        #expect(!controller.isConnected)
        await clock.advance(by: .seconds(60))
        #expect(ports.made.count == 1)   // no reconnecting while idle
        #expect(await controller.send(.queryPower))
        #expect(ports.made.count == 2)
        #expect(ports.made.last?.writes.map(\.bytes) == [Self.text("!1PWRQSTN\r")])
        // The idle close runs again.
        await clock.advance(by: .seconds(300))
        #expect(ports.made.last?.isClosed == true)
        await finish()
    }

    @Test func commandsPostponeTheIdleClose() async throws {
        controller.configure(brand: .onkyo, link: Self.link)
        let first = try #require(ports.made.first)
        await clock.advance(by: .seconds(200))
        await controller.send(.volumeUp)
        await clock.advance(by: .seconds(200))
        #expect(!first.isClosed)
        await clock.advance(by: .seconds(100))
        #expect(first.isClosed)
        await finish()
    }

    @Test func idleCloseStopsReconnecting() async throws {
        ports.startsReady = false
        controller.configure(brand: .onkyo, link: Self.link)
        ports.available = false
        ports.made.first?.unplug()
        await clock.advance(by: .seconds(300))
        let attempts = ports.links.count
        await clock.advance(by: .seconds(120))
        #expect(ports.links.count == attempts)
        // A command after the idle close tries again.
        ports.available = true
        ports.startsReady = true
        #expect(await controller.send(.queryMute))
        #expect(ports.links.count == attempts + 1)
        await finish()
    }

    /// While reconnecting with backoff, a command doesn't force a connection; it fails at once.
    @Test func commandsDuringBackoffDontReconnect() async throws {
        ports.startsReady = false
        controller.configure(brand: .onkyo, link: Self.link)
        ports.made.first?.unplug()
        await clock.settle()
        let attempts = ports.links.count
        let start = clock.now
        #expect(!(await controller.send(.volumeUp)))
        #expect(clock.now == start)
        #expect(ports.links.count == attempts)
        await clock.advance(by: .seconds(1))
        #expect(ports.links.count == attempts + 1)   // the backoff's own attempt
        await finish()
    }

    @Test func serialLinkIsNeverClosedForBeingIdle() async throws {
        controller.configure(brand: .pioneer, serialPort: nil)
        await clock.advance(by: .seconds(900))
        #expect(controller.isConnected)
        #expect(ports.made.first?.isClosed == false)
        await finish()
    }

    /// Find on Network's check: nothing is written before the connection is up; only read-only queries after.
    @Test func probeWaitsForTheConnectionThenSendsQueriesOnly() async throws {
        let codec = OnkyoProtocol()
        let transport = FakeReceiverTransport(brand: .onkyo, clock: clock)
        transport.isReady = false
        transport.replies[codec.encode(.queryPower)] = ["!1PWR00"]
        let probing = Task { await ReceiverController.probe(transport, codec: codec, clock: clock) }
        await clock.advance(by: .milliseconds(300))
        #expect(transport.writes.isEmpty)
        transport.becomeReady()
        await clock.advance(by: .milliseconds(100))
        #expect(await probing.value)
        #expect(transport.writes.map(\.bytes) == [codec.encode(.queryPower)])
        #expect(transport.isClosed)
    }

    @Test func probeOfAConnectionThatFailsIsFalse() async {
        let codec = DenonProtocol()
        let transport = FakeReceiverTransport(brand: .denon, clock: clock)
        transport.isReady = false
        let probing = Task { await ReceiverController.probe(transport, codec: codec, clock: clock) }
        await clock.advance(by: .milliseconds(100))
        transport.unplug()
        await clock.advance(by: .milliseconds(100))
        #expect(!(await probing.value))
        #expect(transport.writes.isEmpty)
        #expect(transport.isClosed)
    }

    /// Step 10 QA minor 3: a volume request waits `volumeReadyTimeout` for the connection, not `readyTimeout`.
    @Test func volumeRequestsWaitLessForTheConnection() async {
        final class Flag { var done = false }
        ports.startsReady = false
        controller.configure(brand: .onkyo, link: Self.link)
        let flag = Flag()
        let task = Task {
            let reply = await controller.request(.volumeUp, readyTimeout: ReceiverController.volumeReadyTimeout)
            flag.done = true
            return reply
        }
        await clock.advance(by: .milliseconds(1400))
        #expect(!flag.done)
        await clock.advance(by: .milliseconds(200))
        #expect(flag.done)
        #expect(await task.value == nil)
        #expect(ReceiverController.volumeReadyTimeout < ReceiverController.readyTimeout)
        await finish()
    }

    /// Step 10 QA minor 2: `onLinkUp` when a TCP connection becomes ready (not when it's only made).
    @Test func linkUpWhenTheConnectionIsReady() async throws {
        var ups = 0
        controller.onLinkUp = { ups += 1 }
        ports.startsReady = false
        controller.configure(brand: .onkyo, link: Self.link)
        #expect(ups == 0)
        try #require(ports.made.last).becomeReady()
        #expect(ups == 1)
        await finish()
    }

    /// M7h step 10: closed for being idle still counts as answering (the next command opens it); the backoff doesn't.
    @Test func idleClosedNetworkLinkStillAnswers() async throws {
        ports.replies[.onkyo] = [.queryVolume: ["!1MVL28"]]
        controller.configure(brand: .onkyo, link: Self.link)
        #expect(await controller.request(.queryVolume) == .volume(raw: 0x28, dB: nil))
        #expect(controller.isAnswering)
        await clock.advance(by: .seconds(300))
        #expect(!controller.isConnected)
        #expect(controller.isAnswering)
        // A connection that drops (not idle) is reconnecting with backoff: not answering.
        #expect(await controller.request(.queryVolume) != nil)
        try #require(ports.made.last).unplug()
        #expect(!controller.isAnswering)
        await finish()
    }

    // MARK: Step 11: the last connect error, for Test Connection

    @Test func aRefusedConnectionIsTheLastError() async throws {
        ports.startsReady = false
        controller.configure(brand: .pioneer, link: Self.link)
        #expect(controller.lastConnectError == nil)
        let transport = try #require(ports.made.first)
        transport.failureReason = "Connection refused"
        transport.unplug()
        #expect(controller.lastConnectError == "Connection refused")
        // The next connection coming up clears it.
        await clock.advance(by: .seconds(1))
        try #require(ports.made.last).becomeReady()
        #expect(controller.lastConnectError == nil)
        // One that was up and then ended.
        try #require(ports.made.last).unplug()
        #expect(controller.lastConnectError == "The receiver closed the connection")
        await finish()
    }

    @Test func aConnectionWithoutAReasonIsNoAnswer() async throws {
        ports.startsReady = false
        controller.configure(brand: .denon, link: Self.link)
        try #require(ports.made.first).unplug()
        #expect(controller.lastConnectError == "No answer")
        // Reconfiguring starts over.
        controller.configure(brand: .denon, link: Self.link)
        #expect(controller.lastConnectError == nil)
        await finish()
    }

    @Test func offTheLANIsTheLastError() async throws {
        ports.startsReady = false
        controller.configure(brand: .yamaha, link: Self.link)
        try #require(ports.made.first).refuseAsNotLAN()
        #expect(controller.lastConnectError == "The address isn't on this network")
        await finish()
    }

    @Test func noSerialPortIsTheLastError() async {
        ports.available = false
        controller.configure(brand: .pioneer, serialPort: nil)
        #expect(controller.lastConnectError == "No serial port found")
        ports.available = true
        await clock.advance(by: .seconds(5))
        #expect(controller.isConnected)
        #expect(controller.lastConnectError == nil)
        try? #require(ports.made.last).unplug()
        #expect(controller.lastConnectError == "The serial port went away")
        await finish()
    }

    @Test func aReplyClearsTheLastError() async throws {
        ports.startsReady = false
        controller.configure(brand: .pioneer, link: Self.link)
        let transport = try #require(ports.made.first)
        transport.failureReason = "Connection refused"
        transport.unplug()
        await clock.advance(by: .seconds(1))
        let next = try #require(ports.made.last)
        next.onLine?("PWR0")
        #expect(controller.lastConnectError == nil)
        await finish()
    }

    /// QA major: Settings hears about connection failures, closes and the link coming up, once per change.
    @Test func linkChangesAreAnnounced() async throws {
        ports.startsReady = false
        var calls = 0
        controller.onLinkChange = { calls += 1 }
        controller.configure(brand: .pioneer, link: Self.link)
        #expect(calls == 1)   // connecting
        let first = try #require(ports.made.first)
        first.failureReason = "Connection refused"
        first.unplug()
        #expect(calls == 2)   // the failure
        #expect(controller.lastConnectError == "Connection refused")
        await clock.advance(by: .seconds(1))
        #expect(calls == 3)   // connecting again
        let second = try #require(ports.made.last)
        second.becomeReady()
        #expect(calls == 4)   // up: the error cleared
        second.onLine?("PWR0")
        #expect(controller.isAnswering)
        #expect(calls == 5)   // answering
        second.onLine?("PWR0")
        #expect(calls == 5)   // nothing changed
        second.unplug()
        #expect(!controller.isAnswering)
        #expect(calls == 6)   // the drop
        await finish()
    }

    @Test func aMissingSerialPortIsAnnounced() async {
        ports.available = false
        var calls = 0
        controller.onLinkChange = { calls += 1 }
        controller.configure(brand: .pioneer, serialPort: nil)
        #expect(calls == 1)
        await clock.advance(by: .seconds(5))
        #expect(calls == 1)   // still no port: the same, said once
        ports.available = true
        await clock.advance(by: .seconds(5))
        #expect(calls == 2)
        await finish()
    }
}
