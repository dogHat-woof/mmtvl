@testable import MMTVL

/// Records what `PhoneRemote` sends and closes.
final class FakeTransport: RemoteTransport {
    var sent: [(RemoteSessionID, ServerMessage)] = []
    var closed: [RemoteSessionID] = []

    func send(_ message: ServerMessage, to session: RemoteSessionID) {
        sent.append((session, message))
    }

    func close(_ session: RemoteSessionID) {
        closed.append(session)
    }

    func messages(to session: RemoteSessionID) -> [ServerMessage] {
        sent.filter { $0.0 == session }.map(\.1)
    }
}
