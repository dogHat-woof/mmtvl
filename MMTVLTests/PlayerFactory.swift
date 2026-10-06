@testable import MMTVL

/// Makes the pool's extra players for LiveTVModel and remembers them.
final class PlayerFactory {
    var made: [FakePlayer] = []

    func make() -> any LivePlayer {
        let player = FakePlayer()
        made.append(player)
        return player
    }
}
