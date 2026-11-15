import Foundation

/// Why the PIN screen is shown (D20, L8).
nonisolated enum PINPurpose: Hashable, Sendable {
    /// Verify, then continue.
    case openSettings, openTile(id: String), exitToDesktop
    /// M7c L9: ⌘Q or the Dock's Quit while the kiosk lock is on.
    case quit
    /// M7h L15: the power menu's Relaunch MMTVL and Restart Mac mini.
    case relaunch, restartMac
    /// M7m L9 (D50): a home tile menu item that edits the tile, or Tile Settings… (`AppRouter.finishPIN` runs it).
    case tileAction(id: String, action: TileMenuAction)
    /// Settings → PIN section.
    case setNew, change, turnOff
}

/// The PIN entry stages: verify the current PIN, enter a new one, confirm it.
nonisolated struct PINFlow: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case verify
        case enterNew
        case confirmNew(String)
    }

    enum Outcome: Equatable, Sendable {
        case next, wrongPIN, mismatch, verified, removed
        case newPIN(String)
    }

    let purpose: PINPurpose
    private(set) var stage: Stage

    init(purpose: PINPurpose) {
        self.purpose = purpose
        stage = purpose == .setNew ? .enterNew : .verify
    }

    mutating func submit(_ code: String, storedPIN: String?) -> Outcome {
        switch stage {
        case .verify:
            // Defensive: the router never asks to verify without a PIN.
            guard let storedPIN else { return .verified }
            guard code == storedPIN else { return .wrongPIN }
            switch purpose {
            case .change:
                stage = .enterNew
                return .next
            case .turnOff:
                return .removed
            case .openSettings, .openTile, .exitToDesktop, .quit, .relaunch, .restartMac, .tileAction, .setNew:
                return .verified
            }
        case .enterNew:
            stage = .confirmNew(code)
            return .next
        case .confirmNew(let first):
            guard code == first else {
                stage = .enterNew
                return .mismatch
            }
            return .newPIN(code)
        }
    }
}

/// L10: 5 wrong PINs in a row lock entry for 60 s. In memory only.
nonisolated struct PINLockout: Equatable, Sendable {
    static let maxFailures = 5
    static let duration: TimeInterval = 60

    private(set) var failures = 0
    private(set) var lockedUntil: Date?

    /// Whole seconds left (rounded up), or nil when not locked. Clears an expired lock.
    mutating func remaining(at now: Date) -> Int? {
        guard let lockedUntil else { return nil }
        let left = lockedUntil.timeIntervalSince(now)
        guard left > 0 else {
            self.lockedUntil = nil
            return nil
        }
        return Int(left.rounded(.up))
    }

    mutating func recordFailure(at now: Date) {
        failures += 1
        if failures >= Self.maxFailures {
            lockedUntil = now.addingTimeInterval(Self.duration)
            failures = 0
        }
    }

    mutating func recordSuccess() {
        failures = 0
        lockedUntil = nil
    }
}
