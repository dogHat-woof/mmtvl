import CoreGraphics

/// The six Multiview layouts (M6 L3), in menu order. Every window is 16:9.
nonisolated enum MultiviewLayout: String, Codable, CaseIterable, Sendable {
    case onePlusFour, onePlusThree, grid, onePlusTwo, sideBySide, pictureInPicture

    enum Direction: Sendable {
        case up, down, left, right

        init?(_ command: RemoteCommand) {
            switch command {
            case .up: self = .up
            case .down: self = .down
            case .left: self = .left
            case .right: self = .right
            default: return nil
            }
        }
    }

    /// The gap between neighboring windows; `Theme.multiviewGap` reads it.
    static let gap: CGFloat = 8

    var title: String {
        switch self {
        case .onePlusFour: "1 + 4"
        case .onePlusThree: "1 + 3"
        case .grid: "2 × 2"
        case .onePlusTwo: "1 + 2"
        case .sideBySide: "Side by Side"
        case .pictureInPicture: "Picture in Picture"
        }
    }

    var capacity: Int { rawSlots.count }

    var mainSlot: Int? {
        switch self {
        case .onePlusFour, .onePlusThree, .onePlusTwo, .pictureInPicture: 0
        case .grid, .sideBySide: nil
        }
    }

    /// The plan's *Layout geometry* table, in slot order. Canvas points; they tile the 1920×1080 canvas.
    var rawSlots: [CGRect] {
        switch self {
        case .onePlusFour:
            [CGRect(x: 240, y: 0, width: 1440, height: 810),
             CGRect(x: 0, y: 810, width: 480, height: 270), CGRect(x: 480, y: 810, width: 480, height: 270),
             CGRect(x: 960, y: 810, width: 480, height: 270), CGRect(x: 1440, y: 810, width: 480, height: 270)]
        case .onePlusThree:
            [CGRect(x: 0, y: 135, width: 1440, height: 810),
             CGRect(x: 1440, y: 135, width: 480, height: 270), CGRect(x: 1440, y: 405, width: 480, height: 270),
             CGRect(x: 1440, y: 675, width: 480, height: 270)]
        case .grid:
            [CGRect(x: 0, y: 0, width: 960, height: 540), CGRect(x: 960, y: 0, width: 960, height: 540),
             CGRect(x: 0, y: 540, width: 960, height: 540), CGRect(x: 960, y: 540, width: 960, height: 540)]
        case .onePlusTwo:
            [CGRect(x: 0, y: 180, width: 1280, height: 720),
             CGRect(x: 1280, y: 180, width: 640, height: 360), CGRect(x: 1280, y: 540, width: 640, height: 360)]
        case .sideBySide:
            [CGRect(x: 0, y: 270, width: 960, height: 540), CGRect(x: 960, y: 270, width: 960, height: 540)]
        case .pictureInPicture:
            [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1392, y: 762, width: 480, height: 270)]
        }
    }

    /// `rawSlots` inset by half the gap on each side, except Picture in Picture's main window (full canvas).
    var slots: [CGRect] {
        rawSlots.enumerated().map { index, rect in
            self == .pictureInPicture && index == 0 ? rect : rect.insetBy(dx: Self.gap / 2, dy: Self.gap / 2)
        }
    }

    /// L4: the nearest slot that way whose rect overlaps this one across the movement. nil when none.
    func neighbor(of slot: Int, _ direction: Direction) -> Int? {
        let rects = rawSlots
        guard rects.indices.contains(slot) else { return nil }
        let a = rects[slot]
        var best: (index: Int, primary: CGFloat, secondary: CGFloat)?
        for (index, b) in rects.enumerated() where index != slot {
            let dx = b.midX - a.midX
            let dy = b.midY - a.midY
            let horizontal = direction == .left || direction == .right
            let lies = switch direction {
            case .right: dx > 0.5
            case .left: dx < -0.5
            case .down: dy > 0.5
            case .up: dy < -0.5
            }
            let overlap = horizontal
                ? min(a.maxY, b.maxY) - max(a.minY, b.minY)
                : min(a.maxX, b.maxX) - max(a.minX, b.minX)
            guard lies, overlap > 0.5 else { continue }
            let primary = horizontal ? abs(dx) : abs(dy)
            let secondary = horizontal ? abs(dy) : abs(dx)
            if let current = best,
               current.primary < primary || (current.primary == primary && current.secondary <= secondary) {
                continue
            }
            best = (index, primary, secondary)
        }
        return best?.index
    }
}
