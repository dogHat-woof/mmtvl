import Foundation
import Observation
import os

/// Everything PhoneRemote does to the outside world. The app wires the real thing; tests pass fakes.
struct PhoneRemoteEnvironment {
    /// NSApp.isActive.
    var isLauncherActive: () -> Bool
    /// InputRouter.dispatch(_:isGlobal:).
    var dispatch: (RemoteCommand, Bool) -> Void
    /// SyntheticInput.canPost.
    var canPostEvents: () -> Bool
    /// SyntheticInput.postKey / postMediaKey.
    var postExternal: (ExternalKey) -> Void
    /// deleteBackward + type.
    var typeEdit: (TextEdit) -> Void
    /// SyntheticInput.postKey(kVK_Return).
    var postReturn: () -> Void
    /// router.screen == .youtube.
    var launcherAcceptsText: () -> Bool
    /// frontmostApplication?.localizedName ?? "Mac".
    var frontAppName: () -> String
    /// VolumeController.perform.
    var volume: (VolumeAction) -> VolumeFeedback
    var now: () -> Date
    /// PairingCode.random.
    var makeCode: () -> String
    /// PhoneToken.make.
    var makeToken: () -> String
}

/// The phone remote coordinator (D24): auth, pairing, command routing, text, volume and status pushes.
@Observable
final class PhoneRemote {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")
    static let maxPhones = 10
    static let maxTextLength = 1000
    static let maxNameLength = 40

    static let openPairingMessage = "Open Settings → Phone Remote → Pair a Phone on the TV"
    static let accessibilityMessage = "Allow Accessibility for MMTVL on the Mac to control other apps"
    static let nothingToTypeMessage = "Nothing to type into here"

    /// Pairing started/rotated/ended, a phone paired, a session opened/closed or authenticated, forget-all.
    @ObservationIgnored var onStatusChange: (() -> Void)?

    private(set) var pairing: PairingCode?
    /// Name of the last phone paired during the current pairing; cleared when pairing starts or ends.
    private(set) var lastPairedName: String?
    private(set) var phones: [PairedPhone]
    private var sessions: [RemoteSessionID: Session] = [:]

    var pairedCount: Int { phones.count }
    /// Authenticated sessions.
    var connectedCount: Int { sessions.values.count { $0.phoneID != nil } }

    @ObservationIgnored private let transport: RemoteTransport
    @ObservationIgnored private let store: PairedPhoneStore
    @ObservationIgnored private let environment: PhoneRemoteEnvironment

    private struct Session {
        /// nil = unauthenticated.
        var phoneID: String?
        var lastText = ""
    }

    init(transport: RemoteTransport, store: PairedPhoneStore, environment: PhoneRemoteEnvironment) {
        self.transport = transport
        self.store = store
        self.environment = environment
        phones = store.load()
    }

    // MARK: From RemoteServer

    func receive(_ data: Data, from session: RemoteSessionID) {
        guard let message = ClientMessage.decode(data) else { return }
        var state = sessions[session] ?? Session()
        defer { sessions[session] = state }

        switch message {
        case .hello(let token):
            hello(token, state: &state, session: session)
        case .pair(let code, let name):
            pair(code, name: name, state: &state, session: session)
        case .command(let command):
            guard state.phoneID != nil else { return }
            route(command, session: session)
        case .textBegin:
            guard state.phoneID != nil else { return }
            state.lastText = ""
        case .text(let value):
            guard state.phoneID != nil, value.count <= Self.maxTextLength else { return }
            let edit = TextEdit.between(state.lastText, value)
            state.lastText = value
            guard !edit.isEmpty, canType(session: session) else { return }
            environment.typeEdit(edit)
        case .submit:
            guard state.phoneID != nil else { return }
            state.lastText = ""
            guard canType(session: session) else { return }
            environment.postReturn()
        case .volume(let action):
            guard state.phoneID != nil else { return }
            switch environment.volume(action) {
            case .level(let level, let muted): transport.send(.volume(level: level, muted: muted), to: session)
            case .sentKeys: transport.send(.volume(level: nil, muted: nil), to: session)
            case .unavailable(let message): transport.send(.toast(message), to: session)
            }
        }
    }

    func sessionClosed(_ session: RemoteSessionID) {
        guard let state = sessions.removeValue(forKey: session) else { return }
        if state.phoneID != nil { onStatusChange?() }
    }

    // MARK: From Settings (L3)

    func setPairing(_ active: Bool) {
        if active {
            guard pairing == nil else { return }
            pairing = PairingCode(code: environment.makeCode(), expires: environment.now() + PairingCode.lifetime)
            lastPairedName = nil
            Self.logger.info("Pairing started")
        } else {
            guard pairing != nil || lastPairedName != nil else { return }
            pairing = nil
            lastPairedName = nil
            Self.logger.info("Pairing ended")
        }
        onStatusChange?()
    }

    /// Clears the paired phones and closes every authenticated session, so their pages show pairing.
    func forgetAll() {
        phones = []
        save()
        for (id, state) in sessions where state.phoneID != nil {
            sessions[id] = nil
            transport.send(.authFailed, to: id)
            transport.close(id)
        }
        Self.logger.info("Forgot all phones")
        onStatusChange?()
    }

    /// App activation changed: push .status to every authenticated session (L16).
    func frontAppChanged() {
        for (id, state) in sessions where state.phoneID != nil {
            sendStatus(to: id)
        }
    }

    /// Server stopped: drop all session state.
    func reset() {
        sessions = [:]
        onStatusChange?()
    }

    // MARK: Private

    private func hello(_ token: String, state: inout Session, session: RemoteSessionID) {
        let hash = PhoneToken.hash(token)
        guard let phone = phones.first(where: { $0.tokenHash == hash }) else {
            state.phoneID = nil
            transport.send(.authFailed, to: session)
            return
        }
        state.phoneID = phone.id
        Self.logger.info("Phone \"\(phone.name, privacy: .public)\" connected")
        transport.send(.welcome, to: session)
        sendStatus(to: session)
        sessions[session] = state
        onStatusChange?()
    }

    private func pair(_ code: String, name: String, state: inout Session, session: RemoteSessionID) {
        guard var pairing else {
            transport.send(.pairFailed(Self.openPairingMessage), to: session)
            return
        }
        switch pairing.check(code, now: environment.now(), makeCode: environment.makeCode) {
        case .expired:
            transport.send(.pairFailed(Self.openPairingMessage), to: session)
        case .rejected:
            self.pairing = pairing
            transport.send(.pairFailed("Wrong code"), to: session)
        case .rotated(let fresh):
            self.pairing = fresh
            Self.logger.info("Pairing code rotated after \(PairingCode.maxFailures) wrong codes")
            transport.send(.pairFailed("Wrong code. A new code is on the TV"), to: session)
            onStatusChange?()
        case .accepted:
            let token = environment.makeToken()
            let phone = PairedPhone(id: UUID().uuidString, name: Self.cleanName(name),
                                    tokenHash: PhoneToken.hash(token), pairedAt: environment.now())
            phones.append(phone)
            if phones.count > Self.maxPhones {
                phones.removeFirst(phones.count - Self.maxPhones)
            }
            save()
            state.phoneID = phone.id
            lastPairedName = phone.name
            Self.logger.info("Paired \"\(phone.name, privacy: .public)\" (\(self.phones.count) phones)")
            transport.send(.paired(token: token), to: session)
            sendStatus(to: session)
            sessions[session] = state
            onStatusChange?()
        }
    }

    /// L5.
    private func route(_ command: RemoteCommand, session: RemoteSessionID) {
        if environment.isLauncherActive() {
            environment.dispatch(command, false)
        } else if command == .home {
            environment.dispatch(.home, true)
        } else if environment.canPostEvents() {
            ExternalKeyMap.key(for: command).map(environment.postExternal)
        } else {
            transport.send(.toast(Self.accessibilityMessage), to: session)
        }
    }

    /// L7: inside MMTVL only the YouTube screen takes text; elsewhere it needs post-event access.
    private func canType(session: RemoteSessionID) -> Bool {
        if environment.isLauncherActive() && !environment.launcherAcceptsText() {
            transport.send(.toast(Self.nothingToTypeMessage), to: session)
            return false
        }
        if !environment.canPostEvents() {
            transport.send(.toast(Self.accessibilityMessage), to: session)
            return false
        }
        return true
    }

    private func sendStatus(to session: RemoteSessionID) {
        transport.send(.status(frontApp: environment.frontAppName(), launcherActive: environment.isLauncherActive()), to: session)
    }

    private func save() {
        do {
            try store.save(phones)
        } catch {
            Self.logger.error("Failed to save paired phones: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        return trimmed.isEmpty ? "Phone" : trimmed
    }
}
