import Testing
@testable import MMTVL

/// M7h 13g: a replaced GL render context turns mpv's video off, so a playing or loading stream is loaded again.
struct VideoContextReloadTests {
    private func reloads(replaced: Bool = true, hasPending: Bool = false, hasCurrentURL: Bool = true,
                         phase: PlayerState.Phase) -> Bool {
        MPVPlayerController.reloadsAfterContextChange(replaced: replaced, hasPending: hasPending,
                                                      hasCurrentURL: hasCurrentURL, phase: phase)
    }

    @Test func firstCreationDoesNotReload() {
        #expect(!reloads(replaced: false, phase: .playing))
        #expect(!reloads(replaced: false, phase: .loading))
    }

    @Test func replacedWhilePlayingOrLoadingReloads() {
        #expect(reloads(phase: .playing))
        #expect(reloads(phase: .loading))
    }

    @Test func replacedWhilePausedIdleOrFailedDoesNotReload() {
        #expect(!reloads(phase: .paused))
        #expect(!reloads(phase: .idle))
        #expect(!reloads(phase: .failed))
    }

    @Test func pendingURLWins() {
        #expect(!reloads(hasPending: true, phase: .playing))
        #expect(!reloads(hasPending: true, phase: .loading))
    }

    @Test func noCurrentURLDoesNotReload() {
        #expect(!reloads(hasCurrentURL: false, phase: .playing))
        #expect(!reloads(hasCurrentURL: false, phase: .loading))
    }
}
