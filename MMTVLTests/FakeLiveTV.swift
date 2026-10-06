@testable import MMTVL

/// Records what the router asks Live TV to do.
final class FakeLiveTV: LiveTVHosting {
    var opens = 0
    var leaves = 0
    var handled: [RemoteCommand] = []
    var outcome: LiveTVOutcome = .handled

    func open() { opens += 1 }
    func leave() { leaves += 1 }

    func handle(_ command: RemoteCommand) -> LiveTVOutcome {
        handled.append(command)
        return outcome
    }
}
