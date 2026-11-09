import Foundation
import Testing
@testable import MMTVL

/// M7h (QA, pre-existing since M5): a remote command that arrives while MMTVL's window shows but MMTVL isn't active
/// brings MMTVL forward and then reaches it, once.
struct ForegroundRepairTests {
    /// A real `InputRouter` and `ExternalRouter`, with the app's activation and `repairForeground` faked.
    final class Harness {
        var active = false
        var repairs = 0
        var handled: [(RemoteCommand, Bool)] = []
        var globals: [RemoteCommand] = []
        var posted: [ExternalKey] = []
        let inputRouter = InputRouter(bindings: .defaults)

        init() {
            inputRouter.isActive = { [unowned self] in active }
            inputRouter.handler = { [unowned self] command, isRepeat in
                handled.append((command, isRepeat))
                return true
            }
            inputRouter.onGlobalCommand = { [unowned self] in globals.append($0) }
        }

        /// Like `AppDelegate.repairForeground` with the window showing and Finder in front: one repair at a time.
        func repair() -> Bool {
            if inputRouter.isRepairingForeground { return true }
            repairs += 1
            inputRouter.foregroundRepairStarted()
            return true
        }

        var externalRouter: ExternalRouter {
            ExternalRouter(
                isLauncherInFront: { self.active || self.repair() },
                dispatch: { self.inputRouter.dispatchFromRemote($0, isGlobal: $1, isRepeat: $2) },
                canPostEvents: { true },
                postExternal: { self.posted.append($0) }
            )
        }

        /// The repair's `bringForward` returned.
        func finishRepair(succeeded: Bool) {
            if succeeded { active = true }
            inputRouter.foregroundRepairFinished(succeeded: succeeded)
        }
    }

    @Test func commandReachesMMTVLOnceAfterTheRepair() {
        let harness = Harness()
        #expect(harness.externalRouter.route(.down) == .launcher)
        #expect(harness.repairs == 1)
        #expect(harness.handled.isEmpty)
        #expect(harness.posted.isEmpty)

        harness.finishRepair(succeeded: true)
        #expect(harness.handled.map(\.0) == [.down])
        #expect(harness.handled.map(\.1) == [false])

        // Nothing is left to deliver; later commands go straight in.
        harness.inputRouter.foregroundRepairFinished(succeeded: true)
        #expect(harness.externalRouter.route(.up) == .launcher)
        #expect(harness.handled.map(\.0) == [.down, .up])
        #expect(harness.repairs == 1)
    }

    @Test func repeatsDuringTheRepairAreNotDeliveredAgain() {
        let harness = Harness()
        harness.externalRouter.route(.right)
        for _ in 0..<3 { harness.externalRouter.route(.right, isRepeat: true) }
        #expect(harness.repairs == 1)
        harness.finishRepair(succeeded: true)
        #expect(harness.handled.map(\.0) == [.right])
    }

    @Test func onlyTheLatestPressIsDelivered() {
        let harness = Harness()
        harness.externalRouter.route(.right)
        harness.externalRouter.route(.select)
        #expect(harness.repairs == 1)
        harness.finishRepair(succeeded: true)
        #expect(harness.handled.map(\.0) == [.select])
    }

    /// QA: MMTVL becomes active ~tens of ms after `activate()`, before `bringForward`'s 250 ms check returns.
    /// A press in that window comes after the kept one, and the finish delivers nothing more.
    @Test func pressAfterActivationKeepsTheOrder() {
        let harness = Harness()
        harness.externalRouter.route(.down)
        harness.active = true
        harness.externalRouter.route(.select)
        #expect(harness.handled.map(\.0) == [.down, .select])
        harness.finishRepair(succeeded: true)
        #expect(harness.handled.map(\.0) == [.down, .select])
        #expect(harness.repairs == 1)
    }

    @Test func failedRepairDeliversNothing() {
        let harness = Harness()
        harness.externalRouter.route(.down)
        harness.finishRepair(succeeded: false)
        #expect(harness.handled.isEmpty)
        #expect(harness.globals.isEmpty)
        #expect(harness.posted.isEmpty)

        // The next press tries again.
        harness.externalRouter.route(.down)
        #expect(harness.repairs == 2)
        harness.finishRepair(succeeded: true)
        #expect(harness.handled.map(\.0) == [.down])
    }

    /// Keys from the event tap and the local monitor use `dispatch`, unchanged: not kept, not consumed.
    @Test func keysAreNotKeptDuringTheRepair() {
        let harness = Harness()
        harness.inputRouter.foregroundRepairStarted()
        #expect(!harness.inputRouter.dispatch(.down, isGlobal: false))
        #expect(harness.inputRouter.dispatch(.home, isGlobal: true))
        #expect(harness.globals == [.home])
        harness.finishRepair(succeeded: true)
        #expect(harness.handled.isEmpty)
    }

    @Test func phoneCommandReachesMMTVLOnceAfterTheRepair() {
        let harness = Harness()
        let transport = FakeTransport()
        let phone = PhoneRemote(transport: transport, store: .inMemory(), environment: PhoneRemoteEnvironment(
            isLauncherActive: { harness.active },
            dispatch: { harness.inputRouter.dispatchFromRemote($0, isGlobal: $1) },
            canPostEvents: { true },
            postExternal: { harness.posted.append($0) },
            typeEdit: { _ in },
            postReturn: {},
            launcherAcceptsText: { false },
            frontAppName: { "Finder" },
            volume: { _, done in done(.sentKeys) },
            now: { Date(timeIntervalSinceReferenceDate: 0) },
            makeCode: { "1234" },
            makeToken: { "tok" },
            pointer: { _ in },
            repairForeground: { harness.repair() }
        ))
        phone.setPairing(true)
        phone.receive(Data(#"{"type":"pair","code":"1234","name":"iPhone"}"#.utf8), from: 1)

        phone.receive(Data(#"{"type":"command","command":"down"}"#.utf8), from: 1)
        phone.receive(Data(#"{"type":"command","command":"down"}"#.utf8), from: 1)
        #expect(harness.repairs == 1)
        #expect(harness.handled.isEmpty)
        #expect(harness.posted.isEmpty)
        harness.finishRepair(succeeded: true)
        #expect(harness.handled.map(\.0) == [.down])
    }
}
