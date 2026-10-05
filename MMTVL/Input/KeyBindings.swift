import AppKit
import Carbon.HIToolbox

/// Default key-code → command mapping. Remappable bindings come in M2.
nonisolated enum KeyBindings {
    static func command(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> RemoteCommand? {
        // ⌘-modified keys always pass through so ⌘Q / ⌘Tab / ⌘H keep working (L4).
        if modifiers.contains(.command) { return nil }

        switch Int(keyCode) {
        case kVK_LeftArrow: return .left
        case kVK_RightArrow: return .right
        case kVK_DownArrow: return .down
        case kVK_UpArrow: return .up
        case kVK_Return, kVK_ANSI_KeypadEnter: return .select
        case kVK_Escape, kVK_Delete: return .back
        case kVK_Space: return .playPause
        case kVK_Home: return .home
        default: return nil
        }
    }
}
