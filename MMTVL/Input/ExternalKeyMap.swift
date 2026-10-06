import Carbon.HIToolbox
import CoreGraphics

/// A key or media key posted to an app other than MMTVL (L5).
nonisolated enum ExternalKey: Equatable, Sendable {
    case key(CGKeyCode)
    case media(Int32)
}

nonisolated enum ExternalKeyMap {
    /// For an app other than MMTVL (L5). The one place to change what phone buttons do there.
    /// `fastForward`/`rewind` → media NEXT/PREVIOUS mirror the default bindings.
    static func key(for command: RemoteCommand) -> ExternalKey? {
        switch command {
        case .up: .key(CGKeyCode(kVK_UpArrow))
        case .down: .key(CGKeyCode(kVK_DownArrow))
        case .left: .key(CGKeyCode(kVK_LeftArrow))
        case .right: .key(CGKeyCode(kVK_RightArrow))
        case .select: .key(CGKeyCode(kVK_Return))
        case .back: .key(CGKeyCode(kVK_Escape))
        case .playPause: .media(SyntheticInput.NXKey.play)
        case .fastForward: .media(SyntheticInput.NXKey.next)
        case .rewind: .media(SyntheticInput.NXKey.previous)
        case .home: nil
        }
    }
}
