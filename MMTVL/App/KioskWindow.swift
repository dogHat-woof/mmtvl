import AppKit

/// Borderless windows can't become key by default, so they'd never receive key events.
final class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
