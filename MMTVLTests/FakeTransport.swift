@testable import MMTVL

/// Records what `PhoneRemote` sends and closes.
final class FakeTransport: RemoteTransport {
    var sent: [(RemoteSessionID, ServerMessage)] = []
    var closed: [RemoteSessionID] = []
    var authenticated: [RemoteSessionID] = []
    /// Each session's address; nil (the default) keys the pairing throttle by session.
    var hosts: [RemoteSessionID: String] = [:]

    func send(_ message: ServerMessage, to session: RemoteSessionID) {
        sent.append((session, message))
    }

    func close(_ session: RemoteSessionID) {
        closed.append(session)
    }

    func sessionAuthenticated(_ session: RemoteSessionID) {
        authenticated.append(session)
    }

    func peerHost(of session: RemoteSessionID) -> String? {
        hosts[session]
    }

    func messages(to session: RemoteSessionID) -> [ServerMessage] {
        sent.filter { $0.0 == session }.map(\.1)
    }
}
