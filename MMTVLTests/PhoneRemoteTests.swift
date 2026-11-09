import Foundation
import Testing
@testable import MMTVL

/// Backs `PhoneRemoteEnvironment` with recorded state.
final class PhoneRemoteRecorder {
    var isActive = true
    var canPost = true
    var acceptsText = true
    var dispatched: [(RemoteCommand, Bool)] = []
    var posted: [ExternalKey] = []
    var edits: [TextEdit] = []
    var returns = 0
    var volumeResult: VolumeFeedback = .sentKeys
    var volumeActions: [VolumeAction] = []
    var now = Date(timeIntervalSinceReferenceDate: 0)
    var codes = ["1234", "5678", "9012", "3456"]
    var tokenCount = 0
    var statusChanges = 0
    var pointerActions: [PointerAction] = []
    var repairs = false
    var repairCalls = 0

    var environment: PhoneRemoteEnvironment {
        PhoneRemoteEnvironment(
            isLauncherActive: { self.isActive },
            dispatch: { self.dispatched.append(($0, $1)) },
            canPostEvents: { self.canPost },
            postExternal: { self.posted.append($0) },
            typeEdit: { self.edits.append($0) },
            postReturn: { self.returns += 1 },
            launcherAcceptsText: { self.acceptsText },
            frontAppName: { self.isActive ? "MMTVL" : "Plex HTPC" },
            volume: { action, done in
                self.volumeActions.append(action)
                done(self.volumeResult)
            },
            now: { self.now },
            makeCode: { self.codes.removeFirst() },
            makeToken: {
                self.tokenCount += 1
                return "tok\(self.tokenCount)"
            },
            pointer: { self.pointerActions.append($0) },
            repairForeground: {
                self.repairCalls += 1
                return self.repairs
            }
        )
    }
}

struct PhoneRemoteTests {
    let transport = FakeTransport()
    let recorder = PhoneRemoteRecorder()
    let store = PairedPhoneStore.inMemory()
    let remote: PhoneRemote

    init() {
        remote = PhoneRemote(transport: transport, store: store, environment: recorder.environment)
        remote.onStatusChange = { [recorder] in recorder.statusChanges += 1 }
    }

    private func send(_ json: String, from session: RemoteSessionID = 1) {
        remote.receive(Data(json.utf8), from: session)
    }

    private func pair(_ code: String, from session: RemoteSessionID = 1, name: String = "iPhone") {
        send(#"{"type":"pair","code":"\#(code)","name":"\#(name)"}"#, from: session)
    }

    /// Pairs session 1 with "tok1" and clears the recordings.
    private func paired(session: RemoteSessionID = 1) {
        remote.setPairing(true)
        pair(remote.pairing!.code, from: session)
        transport.sent = []
    }

    private func status() -> ServerMessage {
        .status(frontApp: recorder.isActive ? "MMTVL" : "Plex HTPC", launcherActive: recorder.isActive)
    }

    @Test func unauthenticatedMessagesAreIgnored() {
        send(#"{"type":"command","command":"up"}"#)
        send(#"{"type":"text","value":"abc"}"#)
        send(#"{"type":"volume","action":"up"}"#)
        send(#"{"type":"submit"}"#)
        send(#"{"type":"textBegin"}"#)
        #expect(recorder.dispatched.isEmpty)
        #expect(recorder.posted.isEmpty)
        #expect(recorder.edits.isEmpty)
        #expect(recorder.returns == 0)
        #expect(recorder.volumeActions.isEmpty)
        #expect(transport.sent.isEmpty)
    }

    @Test func badHelloFailsButStaysOpen() {
        send(#"{"type":"hello","token":"nope"}"#)
        #expect(transport.messages(to: 1) == [.authFailed])
        #expect(transport.closed.isEmpty)
    }

    @Test func pairWithoutPairing() {
        pair("1234")
        #expect(transport.messages(to: 1) == [.pairFailed(PhoneRemote.openPairingMessage)])
    }

    @Test func pairing() {
        remote.setPairing(true)
        #expect(remote.pairing?.code == "1234")
        pair("0000")
        #expect(transport.messages(to: 1).last == .pairFailed("Wrong code"))
        for _ in 0..<3 { pair("0000") }
        pair("0000")
        #expect(transport.messages(to: 1).last == .pairFailed("Wrong code. A new code is on the TV"))
        #expect(remote.pairing?.code == "5678")

        transport.sent = []
        let changesBefore = recorder.statusChanges
        pair("5678")
        #expect(transport.messages(to: 1) == [.paired(token: "tok1"), status()])
        let phones = store.load()
        #expect(phones.count == 1)
        #expect(phones.first?.tokenHash == PhoneToken.hash("tok1"))
        #expect(phones.first?.name == "iPhone")
        #expect(remote.lastPairedName == "iPhone")
        #expect(remote.pairedCount == 1)
        #expect(remote.connectedCount == 1)
        #expect(recorder.statusChanges > changesBefore)
    }

    @Test func helloAfterPairing() {
        paired()
        send(#"{"type":"hello","token":"tok1"}"#, from: 2)
        #expect(transport.messages(to: 2) == [.welcome, status()])
        #expect(remote.connectedCount == 2)
    }

    @Test func expiredPairing() {
        remote.setPairing(true)
        recorder.now += PairingCode.lifetime + 1
        pair("1234")
        #expect(transport.messages(to: 1) == [.pairFailed(PhoneRemote.openPairingMessage)])
    }

    @Test func elevenPairingsKeepTen() {
        remote.setPairing(true)
        for session in 1...11 {
            recorder.now += 1
            pair("1234", from: session, name: "Phone \(session)")
        }
        let phones = store.load()
        #expect(phones.count == 10)
        #expect(phones.first?.name == "Phone 2")
        #expect(phones.last?.name == "Phone 11")
    }

    @Test func commandsWhileActive() {
        paired()
        send(#"{"type":"command","command":"down"}"#)
        #expect(recorder.dispatched.map(\.0) == [.down])
        #expect(recorder.dispatched.map(\.1) == [false])
    }

    @Test func commandsWhileInactive() {
        paired()
        recorder.isActive = false
        send(#"{"type":"command","command":"home"}"#)
        #expect(recorder.dispatched.map(\.0) == [.home])
        #expect(recorder.dispatched.map(\.1) == [true])

        send(#"{"type":"command","command":"up"}"#)
        send(#"{"type":"command","command":"playPause"}"#)
        #expect(recorder.posted == [.key(126), .media(16)])

        recorder.canPost = false
        send(#"{"type":"command","command":"up"}"#)
        #expect(recorder.posted.count == 2)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.accessibilityMessage))
    }

    /// M7h L3: the phone goes through `ExternalRouter`; volume and power commands still post nothing to other apps.
    @Test func volumeAndPowerCommandsDoNothingInOtherApps() {
        paired()
        recorder.isActive = false
        for command in ["volumeUp", "volumeDown", "mute", "power", "powerMenu"] {
            send(#"{"type":"command","command":"\#(command)"}"#)
        }
        #expect(recorder.posted.isEmpty)
        #expect(recorder.dispatched.isEmpty)
        #expect(transport.messages(to: 1).isEmpty)

        // Without Accessibility the phone hears about it, as before (not for Power, which is ignored: step 12).
        recorder.canPost = false
        send(#"{"type":"command","command":"power"}"#)
        #expect(transport.messages(to: 1).isEmpty)
        send(#"{"type":"command","command":"mute"}"#)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.accessibilityMessage))
    }

    /// M7h step 12 (step 4 security low): a paired phone's raw `power` / `powerMenu` never reach MMTVL's screens
    /// (no power menu, no TV off), with MMTVL in front or not.
    @Test func powerCommandsFromThePhoneAreIgnored() {
        paired()
        for isActive in [true, false] {
            recorder.isActive = isActive
            recorder.repairs = true
            send(#"{"type":"command","command":"power"}"#)
            send(#"{"type":"command","command":"powerMenu"}"#)
        }
        #expect(recorder.dispatched.isEmpty)
        #expect(recorder.posted.isEmpty)
        #expect(recorder.repairCalls == 0)
        #expect(transport.messages(to: 1).isEmpty)
        // Other commands still go through.
        recorder.isActive = true
        send(#"{"type":"command","command":"select"}"#)
        #expect(recorder.dispatched.map(\.0) == [.select])
    }

    /// M7c L3: MMTVL's window shows but it isn't active; the command goes to MMTVL, not out as a key.
    @Test func commandsRepairTheForeground() {
        paired()
        recorder.isActive = false
        recorder.repairs = true
        send(#"{"type":"command","command":"down"}"#)
        #expect(recorder.dispatched.map(\.0) == [.down])
        #expect(recorder.dispatched.map(\.1) == [false])
        #expect(recorder.posted.isEmpty)
        #expect(recorder.repairCalls == 1)

        recorder.isActive = true
        send(#"{"type":"command","command":"up"}"#)
        #expect(recorder.repairCalls == 1)
    }

    @Test func textDiffs() {
        paired()
        send(#"{"type":"text","value":"s"}"#)
        send(#"{"type":"text","value":"st"}"#)
        #expect(recorder.edits == [TextEdit(deletions: 0, insertion: "s"), TextEdit(deletions: 0, insertion: "t")])
        send(#"{"type":"textBegin"}"#)
        send(#"{"type":"text","value":"x"}"#)
        #expect(recorder.edits.last == TextEdit(deletions: 0, insertion: "x"))
    }

    @Test func textNeedsSomewhereToGo() {
        paired()
        recorder.acceptsText = false
        send(#"{"type":"text","value":"a"}"#)
        #expect(recorder.edits.isEmpty)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.nothingToTypeMessage))

        recorder.acceptsText = true
        send(#"{"type":"text","value":"ab"}"#)
        #expect(recorder.edits == [TextEdit(deletions: 0, insertion: "b")])

        recorder.isActive = false
        recorder.canPost = false
        send(#"{"type":"text","value":"abc"}"#)
        #expect(recorder.edits.count == 1)
        #expect(transport.messages(to: 1).last == .toast(PhoneRemote.accessibilityMessage))
    }

    @Test func overlongTextIsIgnored() {
        paired()
        let long = String(repeating: "a", count: 1001)
        send(#"{"type":"text","value":"\#(long)"}"#)
        #expect(recorder.edits.isEmpty)
        send(#"{"type":"text","value":"a"}"#)
        #expect(recorder.edits == [TextEdit(deletions: 0, insertion: "a")])
    }

    @Test func submitPostsReturnAndResets() {
        paired()
        send(#"{"type":"text","value":"cats"}"#)
        send(#"{"type":"submit"}"#)
        #expect(recorder.returns == 1)
        send(#"{"type":"text","value":"a"}"#)
        #expect(recorder.edits.last == TextEdit(deletions: 0, insertion: "a"))
    }

    @Test func volumeFeedback() {
        paired()
        recorder.volumeResult = .level(0.5, muted: false)
        send(#"{"type":"volume","action":"up"}"#)
        recorder.volumeResult = .sentKeys
        send(#"{"type":"volume","action":"down"}"#)
        recorder.volumeResult = .unavailable("Volume can't be changed here")
        send(#"{"type":"volume","action":"mute"}"#)
        #expect(recorder.volumeActions == [.up, .down, .mute])
        #expect(transport.messages(to: 1) == [
            .volume(level: 0.5, muted: false),
            .volume(level: nil, muted: nil),
            .toast("Volume can't be changed here"),
        ])
    }

    @Test func forgetAll() {
        paired()
        send(#"{"type":"textBegin"}"#, from: 2)   // unauthenticated
        remote.forgetAll()
        #expect(store.load().isEmpty)
        #expect(remote.pairedCount == 0)
        #expect(transport.messages(to: 1) == [.authFailed])
        #expect(transport.closed == [1])
        #expect(transport.messages(to: 2).isEmpty)
        #expect(remote.connectedCount == 0)
    }

    @Test func frontAppChangedOnlyReachesAuthenticatedSessions() {
        paired()
        send(#"{"type":"textBegin"}"#, from: 2)
        recorder.isActive = false
        remote.frontAppChanged()
        #expect(transport.messages(to: 1) == [status()])
        #expect(transport.messages(to: 2).isEmpty)
    }

    @Test func sessionClosedDecrementsConnected() {
        paired()
        #expect(remote.connectedCount == 1)
        remote.sessionClosed(1)
        #expect(remote.connectedCount == 0)
    }

    @Test func endingPairing() {
        paired()
        #expect(remote.lastPairedName == "iPhone")
        remote.setPairing(true)
        #expect(remote.pairing?.code == "1234")
        remote.setPairing(false)
        #expect(remote.pairing == nil)
        #expect(remote.lastPairedName == nil)
    }

    // MARK: Trackpad (M7b L13)

    @Test func pointerActionsNeedAuthentication() {
        send(#"{"type":"pointer","dx":3,"dy":4}"#)
        #expect(recorder.pointerActions.isEmpty)
        paired()
        send(#"{"type":"pointer","dx":3,"dy":4}"#)
        send(#"{"type":"click","button":"right"}"#)
        send(#"{"type":"scroll","dx":0,"dy":-12.5}"#)
        #expect(recorder.pointerActions == [.move(dx: 3, dy: 4), .click(.right), .scroll(dx: 0, dy: -12.5)])
        #expect(transport.sent.isEmpty)
    }

    @Test func pointerWithoutAccessibilityToastsEveryFiveSeconds() {
        paired()
        recorder.canPost = false
        send(#"{"type":"pointer","dx":1,"dy":1}"#)
        send(#"{"type":"pointer","dx":1,"dy":1}"#)
        recorder.now += 4
        send(#"{"type":"scroll","dx":1,"dy":1}"#)
        #expect(transport.sent.count == 1)
        recorder.now += 1
        send(#"{"type":"click","button":"left"}"#)
        #expect(transport.sent.count == 2)
        #expect(recorder.pointerActions.isEmpty)
    }

}
