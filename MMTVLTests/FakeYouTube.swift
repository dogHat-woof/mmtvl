@testable import MMTVL

/// Records what the router asks YouTube to do.
final class FakeYouTube: YouTubeHosting {
    var opens = 0
    var sent: [RemoteCommand] = []
    var pauses = 0
    var onExit: (() -> Void)?

    func open() { opens += 1 }
    func send(_ command: RemoteCommand) { sent.append(command) }
    func pause() { pauses += 1 }
}
