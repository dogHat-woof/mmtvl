import Foundation

/// Persisted in iptv-state.json (M6 L13). Channel ids only, never URLs.
nonisolated struct MultiviewSnapshot: Codable, Equatable, Sendable {
    var layout: MultiviewLayout
    /// Channel.ID per slot.
    var slots: [String?]
    var focusedSlot: Int
    var isActive: Bool
}

/// Multiview's windows, highlight and sound (M6 L4, L5, L11, L12). Pure; LiveTVModel maps it to players.
nonisolated struct MultiviewModel: Equatable, Sendable {
    static let maxWindows = 5

    private(set) var layout: MultiviewLayout
    /// Always layout.capacity long.
    private(set) var slots: [Channel.ID?]
    private(set) var focusedSlot: Int
    /// L5: the filled slot whose sound plays; nil when every slot is empty.
    private(set) var audioSlot: Int?

    /// Pads with nil / truncates to capacity; clamps focusedSlot; audioSlot = focusedSlot if filled, else the first filled.
    init(layout: MultiviewLayout, slots: [Channel.ID?], focusedSlot: Int = 0) {
        self.layout = layout
        self.slots = Self.fitted(slots, to: layout.capacity)
        self.focusedSlot = min(max(focusedSlot, 0), layout.capacity - 1)
        audioSlot = nil
        audioSlot = self.slots[self.focusedSlot] != nil ? self.focusedSlot : firstFilledSlot
    }

    /// Ids not in `validIDs` become nil.
    init(snapshot: MultiviewSnapshot, validIDs: Set<Channel.ID>) {
        self.init(layout: snapshot.layout,
                  slots: snapshot.slots.map { id in id.flatMap { validIDs.contains($0) ? $0 : nil } },
                  focusedSlot: snapshot.focusedSlot)
    }

    func snapshot(isActive: Bool) -> MultiviewSnapshot {
        MultiviewSnapshot(layout: layout, slots: slots, focusedSlot: focusedSlot, isActive: isActive)
    }

    /// Filled slots, in slot order.
    var channelIDs: [Channel.ID] { slots.compactMap { $0 } }
    var isEmpty: Bool { channelIDs.isEmpty }
    var focusedChannelID: Channel.ID? { slots[focusedSlot] }
    var audioChannelID: Channel.ID? { audioSlot.flatMap { slots[$0] } }

    func slot(of id: Channel.ID) -> Int? { slots.firstIndex(of: id) }

    /// L12: the remembered windows (still-valid ids), plus the channel playing now, plus `adding`.
    /// Highlight and sound go to `adding`.
    static func entering(snapshot: MultiviewSnapshot?, current: Channel.ID?, adding: Channel.ID,
                         validIDs: Set<Channel.ID>, defaultLayout: MultiviewLayout = .onePlusFour) -> MultiviewModel {
        var model = if let snapshot {
            MultiviewModel(snapshot: snapshot, validIDs: validIDs)
        } else {
            MultiviewModel(layout: defaultLayout, slots: [])
        }
        if let current, current != adding, model.slot(of: current) == nil {
            model.place(current, protecting: nil)
        }
        if model.slot(of: adding) == nil {
            model.place(adding, protecting: current)
        }
        let slot = model.slot(of: adding) ?? 0
        model.focusedSlot = slot
        model.audioSlot = slot
        return model
    }

    /// L4/L5. Returns false (and changes nothing) when there's no neighbor.
    mutating func moveFocus(_ direction: MultiviewLayout.Direction) -> Bool {
        guard let next = layout.neighbor(of: focusedSlot, direction) else { return false }
        focusedSlot = next
        if slots[next] != nil { audioSlot = next }
        return true
    }

    /// M7f L6: highlights `slot` (sound follows when it's filled), as an arrow would.
    mutating func focus(_ slot: Int) {
        guard slots.indices.contains(slot) else { return }
        focusedSlot = slot
        if slots[slot] != nil { audioSlot = slot }
    }

    /// M7f L6: Left/Right on the main window move every channel one window along the filled slots, in slot order
    /// (empty windows stay empty). `+1`: `A | B C D E` → `B | C D E A`; `-1`: → `E | A B C D`. Focus and sound stay on
    /// the main window. False (no change) without a main window or with fewer than 2 filled windows.
    mutating func rotate(by step: Int) -> Bool {
        guard let main = layout.mainSlot, step != 0 else { return false }
        let filled = slots.indices.filter { slots[$0] != nil }
        guard filled.count >= 2 else { return false }
        let ids = filled.map { slots[$0] }
        let count = ids.count
        let shift = ((step % count) + count) % count
        for (position, slot) in filled.enumerated() {
            slots[slot] = ids[(position + shift) % count]
        }
        focusedSlot = main
        if slots[main] != nil { audioSlot = main }
        return true
    }

    /// Returns the ids dropped because the new layout is smaller. The window with sound is never dropped.
    mutating func setLayout(_ layout: MultiviewLayout) -> [Channel.ID] {
        var ids = channelIDs
        let audioID = audioChannelID
        var dropped: [Channel.ID] = []
        while ids.count > layout.capacity, let index = ids.lastIndex(where: { $0 != audioID }) {
            dropped.append(ids.remove(at: index))
        }
        self.layout = layout
        slots = Self.fitted(ids, to: layout.capacity)
        if let audioID, let slot = slot(of: audioID) {
            focusedSlot = slot
            audioSlot = slot
        } else {
            focusedSlot = 0
            audioSlot = nil
        }
        return dropped
    }

    /// L11. Returns the id that was in `slot` and is now gone (nil when the slot was empty or for a swap).
    mutating func assign(_ id: Channel.ID, to slot: Int) -> Channel.ID? {
        var displaced: Channel.ID?
        if let other = self.slot(of: id), other != slot {
            slots.swapAt(other, slot)
        } else if slots[slot] != id {
            displaced = slots[slot]
            slots[slot] = id
        }
        focusedSlot = slot
        audioSlot = slot
        return displaced
    }

    /// Swaps `slot` with layout.mainSlot (no-op without one); focus and sound go to the main slot.
    mutating func makeMain(_ slot: Int) {
        guard let main = layout.mainSlot else { return }
        if slot != main { slots.swapAt(slot, main) }
        focusedSlot = main
        if slots[main] != nil { audioSlot = main }
    }

    /// Returns the removed id.
    mutating func remove(_ slot: Int) -> Channel.ID? {
        let id = slots[slot]
        slots[slot] = nil
        if audioSlot == slot { audioSlot = firstFilledSlot }
        return id
    }

    // MARK: - Private

    private var firstFilledSlot: Int? { slots.firstIndex { $0 != nil } }

    private static func fitted(_ slots: [Channel.ID?], to capacity: Int) -> [Channel.ID?] {
        Array((slots + Array(repeating: nil, count: max(0, capacity - slots.count))).prefix(capacity))
    }

    /// The first empty slot; when full, the last slot not holding `protected`.
    private mutating func place(_ id: Channel.ID, protecting protected: Channel.ID?) {
        if let empty = slots.firstIndex(where: { $0 == nil }) {
            slots[empty] = id
        } else if let last = slots.lastIndex(where: { $0 != protected }) {
            slots[last] = id
        }
    }
}
