import Foundation

/// Pure edits for the Settings tile editor. Every function returns a new array; unknown ids return it unchanged.
nonisolated extension Array where Element == LaunchItem {
    var visible: [LaunchItem] { filter(\.isVisible) }

    /// Moves an item by `offset` positions, clamped to the array bounds.
    func movingItem(id: String, by offset: Int) -> [LaunchItem] {
        guard let index = firstIndex(where: { $0.id == id }) else { return self }
        let target = Swift.min(Swift.max(index + offset, 0), count - 1)
        guard target != index else { return self }
        var result = self
        let item = result.remove(at: index)
        result.insert(item, at: target)
        return result
    }

    /// Stores `true` when hidden and `nil` when shown, keeping the JSON clean.
    func settingHidden(_ hidden: Bool, id: String) -> [LaunchItem] {
        updating(id: id) { $0.isHidden = hidden ? true : nil }
    }

    func settingFullScreen(_ fullScreen: Bool, id: String) -> [LaunchItem] {
        updating(id: id) { $0.launchFullScreen = fullScreen }
    }

    /// Stores `true` when on and `nil` when off, keeping the JSON clean.
    func settingRequiresPIN(_ on: Bool, id: String) -> [LaunchItem] {
        updating(id: id) { $0.requiresPIN = on ? true : nil }
    }

    /// M7 L23: nil = the web app's own start page.
    func settingStartURL(_ url: URL?, id: String) -> [LaunchItem] {
        updating(id: id) { $0.startURL = url }
    }

    /// M7 L24: stored as nil for the default (designed).
    func settingArtStyle(_ style: TileArtStyle, id: String) -> [LaunchItem] {
        updating(id: id) { $0.artStyle = style == .designed ? nil : style.rawValue }
    }

    func removingItem(id: String) -> [LaunchItem] {
        filter { $0.id != id }
    }

    /// Inserts before the first `.system` item (Exit to Desktop), else at the end.
    func insertingTile(_ item: LaunchItem) -> [LaunchItem] {
        var result = self
        if let index = firstIndex(where: { if case .system = $0.kind { true } else { false } }) {
            result.insert(item, at: index)
        } else {
            result.append(item)
        }
        return result
    }

    /// `LaunchItem.defaults` whose id isn't present, in default order.
    var missingDefaults: [LaunchItem] {
        let ids = Set(map(\.id))
        return LaunchItem.defaults.filter { !ids.contains($0.id) }
    }

    /// Adds the default Settings tile if there is none (older files, hand edits) and shows any hidden one,
    /// so Settings is always reachable.
    func ensuringSettingsTile() -> [LaunchItem] {
        guard contains(where: \.isSettingsTile) else {
            guard let settings = LaunchItem.defaults.first(where: \.isSettingsTile) else { return self }
            return insertingTile(settings)
        }
        return map { item in
            guard item.isSettingsTile, !item.isVisible else { return item }
            var item = item
            item.isHidden = nil
            return item
        }
    }

    /// Bundle IDs of `.application` items.
    var applicationBundleIDs: Set<String> {
        Set(compactMap { if case .application(let bundleID) = $0.kind { bundleID } else { nil } })
    }

    private func updating(id: String, _ change: (inout LaunchItem) -> Void) -> [LaunchItem] {
        map { item in
            guard item.id == id else { return item }
            var item = item
            change(&item)
            return item
        }
    }
}
