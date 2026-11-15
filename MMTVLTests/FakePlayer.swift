import Foundation
@testable import MMTVL

/// Records what Live TV asks the player to do.
final class FakePlayer: LivePlayer {
    var state = PlayerState()
    var onFailure: (() -> Void)?
    var played: [URL] = []
    /// M7j L6: `direct` of each `play`, in the same order as `played`.
    var playedDirect: [Bool] = []
    var stops = 0
    var pauses = 0
    var seeks: [Double] = []
    var liveSeeks = 0
    var volume: (level: Int, muted: Bool)?
    var audible = true
    var bufferProfile = BufferProfile.full
    var holdsSleepAssertion = true

    func play(_ url: URL, direct: Bool) {
        played.append(url)
        playedDirect.append(direct)
        state = PlayerState(phase: .loading)
    }

    func stop() {
        stops += 1
        state = PlayerState()
    }

    func togglePause() {
        pauses += 1
        switch state.phase {
        case .playing: state.phase = .paused
        case .paused: state.phase = .playing
        default: break
        }
    }

    func seek(by seconds: Double) { seeks.append(seconds) }
    func seekToLive() { liveSeeks += 1 }
    func setVolume(_ level: Int, muted: Bool) { volume = (level, muted) }
    func setAudible(_ audible: Bool) { self.audible = audible }
    func setBufferProfile(_ profile: BufferProfile) { bufferProfile = profile }
    func setHoldsSleepAssertion(_ holds: Bool) { holdsSleepAssertion = holds }

    /// Retries exhausted.
    func fail() {
        state.phase = .failed
        onFailure?()
    }
}
