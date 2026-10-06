@testable import MMTVL

/// Records what the router asks Live TV to do.
final class FakeLiveTV: LiveTVHosting {
    var opens = 0
    /// The channel id of each open (nil = the last channel / Multiview).
    var openedChannelIDs: [Channel.ID?] = []
    var leaves = 0
    var handled: [RemoteCommand] = []
    var outcome: LiveTVOutcome = .handled

    func open(channelID: Channel.ID?) {
        opens += 1
        openedChannelIDs.append(channelID)
    }
    func leave() { leaves += 1 }

    func handle(_ command: RemoteCommand) -> LiveTVOutcome {
        handled.append(command)
        return outcome
    }
}
