@testable import MMTVL

/// Records what the router asks YouTube to do.
final class FakeYouTube: YouTubeHosting {
    var opens = 0
    var sent: [RemoteCommand] = []
    var pauses = 0
    var launches: [String] = []
    var reloads = 0
    var hasOpened = false
    var onExit: (() -> Void)?

    func open() {
        opens += 1
        hasOpened = true
    }
    func send(_ command: RemoteCommand) { sent.append(command) }
    func pause() { pauses += 1 }
    func launch(query: String) {
        launches.append(query)
        hasOpened = true
    }
    func reload() { reloads += 1 }
}
