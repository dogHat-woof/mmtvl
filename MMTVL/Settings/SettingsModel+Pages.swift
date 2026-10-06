/// Builds the sections and rows for each Settings page.
extension SettingsModel {
    var sections: [SettingsSection] {
        switch page {
        case .root: rootSections
        case .homeScreen: homeScreenSections
        case .tile(let id): tileSections(id: id)
        case .addTile: addTileSections
        case .confirmRestoreDefaults: confirmRestoreSections
        case .confirmClearYouTube: confirmClearYouTubeSections
        case .liveTV: liveTVSections
        case .confirmRemoveIPTV: confirmRemoveIPTVSections
        }
    }

    var pageTitle: String {
        switch page {
        case .root: "Settings"
        case .homeScreen: "Home Screen"
        case .tile(let id): item(id: id).map(environment.tileTitle) ?? "Tile"
        case .addTile: "Add Tile"
        case .confirmRestoreDefaults: "Restore Default Tiles?"
        case .confirmClearYouTube: "Sign Out of YouTube?"
        case .liveTV: "Live TV"
        case .confirmRemoveIPTV: "Remove Live TV Source?"
        }
    }

    var pageImage: RowImage {
        switch page {
        case .root: .symbol("gearshape")
        case .homeScreen: .symbol("square.grid.2x2")
        case .tile(let id): item(id: id).map(RowImage.item) ?? .symbol("app.dashed")
        case .addTile: .symbol("plus.app")
        case .confirmRestoreDefaults: .symbol("arrow.counterclockwise")
        case .confirmClearYouTube: .symbol("play.rectangle")
        case .liveTV: .symbol("tv")
        case .confirmRemoveIPTV: .symbol("tv.slash")
        }
    }

    var hint: String {
        switch page {
        case .root, .tile, .liveTV: "Select: choose · Back: return"
        case .homeScreen:
            movingTileID == nil ? "Select: edit tile · Back: return" : "Up/Down: move · Select or Back: done"
        case .addTile: "Select: add · Back: return"
        case .confirmRestoreDefaults, .confirmClearYouTube, .confirmRemoveIPTV: "Select: choose · Back: cancel"
        }
    }

    private static func onOff(_ value: Bool) -> String { value ? "On" : "Off" }

    private static let kioskOnly = "Applies in kiosk mode only"

    private var rootSections: [SettingsSection] {
        let kiosk = environment.isKiosk

        var globalInputDetail: String?
        if !kiosk {
            globalInputDetail = Self.kioskOnly
        } else if settings.globalInputEnabled && !isAccessibilityTrusted {
            globalInputDetail = "Needs Accessibility access"
        }

        var launchAtLoginDetail: String?
        if !kiosk {
            launchAtLoginDetail = Self.kioskOnly
        } else if settings.launchAtLogin && loginItemStatus == .requiresApproval {
            launchAtLoginDetail = "Waiting for approval in System Settings → General → Login Items"
        }

        var startupRows = [
            SettingsRow(id: "launchAtLogin", title: "Launch at Login", value: Self.onOff(settings.launchAtLogin),
                        detail: launchAtLoginDetail, action: .toggle(.launchAtLogin)),
        ]
        if kiosk && settings.launchAtLogin && loginItemStatus == .requiresApproval {
            startupRows.append(SettingsRow(id: "approveLoginItem", title: "Open Login Items Settings",
                                           action: .openLoginItemsSettings))
        }

        return [
            SettingsSection(id: "input", title: "Remote & Input", rows: [
                SettingsRow(id: "globalInput", title: "Global Home & Media Keys",
                            value: Self.onOff(settings.globalInputEnabled), detail: globalInputDetail,
                            action: .toggle(.globalInputEnabled)),
                SettingsRow(id: "controllers", title: "Game Controllers",
                            value: Self.onOff(settings.controllersEnabled), action: .toggle(.controllersEnabled)),
                SettingsRow(id: "cursorAutoHide", title: "Hide Pointer During Remote Use",
                            value: Self.onOff(settings.cursorAutoHide), action: .toggle(.cursorAutoHide)),
            ]),
            SettingsSection(id: "permissions", title: "Permissions", rows: [
                SettingsRow(id: "accessibility", title: "Accessibility",
                            value: isAccessibilityTrusted ? "Allowed" : "Not Allowed",
                            detail: "Needed for Home in other apps, media keys and full-screen apps",
                            action: .requestAccessibility),
            ]),
            SettingsSection(id: "startup", title: "Startup", rows: startupRows),
            SettingsSection(id: "home", title: "Home Screen", rows: [
                SettingsRow(id: "editHome", title: "Edit Home Screen", showsDisclosure: true,
                            action: .push(.homeScreen)),
            ]),
            pinSection,
            SettingsSection(id: "youtube", title: "YouTube", rows: [
                SettingsRow(id: "youtube.reload", title: "Reload YouTube", action: .reloadYouTube),
                SettingsRow(id: "youtube.clear", title: "Sign Out & Clear YouTube Data", showsDisclosure: true,
                            action: .push(.confirmClearYouTube)),
            ], footer: "To keep kids in their own profile, set a Parent code in YouTube → Settings → Parent code."),
            SettingsSection(id: "liveTV", title: "Live TV", rows: [
                SettingsRow(id: "liveTV", title: "Live TV",
                            value: iptv.hasPlaylist ? Self.channelCount(iptv.channelCount) : "Not Set Up",
                            showsDisclosure: true, action: .push(.liveTV)),
            ]),
            SettingsSection(id: "system", title: "System", rows: [
                SettingsRow(id: "relaunch", title: "Relaunch MMTVL", action: .relaunch),
                SettingsRow(id: "exit", title: "Exit to Desktop", action: .exitToDesktop),
            ], footer: "MMTVL \(environment.versionString) · Saved in ~/Library/Application Support/MMTVL"),
        ]
    }

    /// D20.
    private var pinSection: SettingsSection {
        let rows = hasPIN
            ? [
                SettingsRow(id: "pin.change", title: "Change PIN", action: .startPIN(.change)),
                SettingsRow(id: "pin.off", title: "Turn Off PIN", action: .startPIN(.turnOff)),
            ]
            : [
                SettingsRow(id: "pin.set", title: "Set PIN",
                            detail: "Guards Settings, Exit to Desktop and tiles set to Require PIN",
                            action: .startPIN(.setNew)),
            ]
        return SettingsSection(id: "pin", title: "PIN", rows: rows,
                               footer: hasPIN ? "The PIN guards Settings, Exit to Desktop and tiles set to Require PIN." : nil)
    }

    private var homeScreenSections: [SettingsSection] {
        let tileRows = items.map { item in
            var detail = item.kindDescription
            if !environment.isInstalled(item) { detail += " · Not installed" }
            return SettingsRow(
                id: Self.tileRowID(item.id),
                title: environment.tileTitle(item),
                value: item.isVisible ? nil : "Hidden",
                detail: detail,
                image: .item(item),
                showsDisclosure: true,
                isDimmed: !item.isVisible,
                isLifted: movingTileID == item.id,
                action: .push(.tile(id: item.id))
            )
        }
        return [
            SettingsSection(id: "tiles", title: "Tiles", rows: tileRows,
                            footer: "Hidden tiles stay here but don't show on the Home screen."),
            SettingsSection(id: "manage", rows: [
                SettingsRow(id: "addTile", title: "Add Tile", showsDisclosure: true, action: .push(.addTile)),
                SettingsRow(id: "restoreDefaults", title: "Restore Default Tiles", showsDisclosure: true,
                            action: .push(.confirmRestoreDefaults)),
            ]),
        ]
    }

    private func tileSections(id: String) -> [SettingsSection] {
        guard let item = item(id: id) else { return [] }
        if item.isSettingsTile {
            return [SettingsSection(id: "options", rows: [
                SettingsRow(id: "tile.move", title: "Move", action: .startMove(id: id)),
            ], footer: "Settings is always on the Home screen and asks for the PIN when one is set.")]
        }
        var rows = [
            SettingsRow(id: "tile.visible", title: "Show on Home Screen", value: Self.onOff(item.isVisible),
                        action: .toggleTileVisible(id: id)),
        ]
        if item.supportsFullScreen {
            rows.append(SettingsRow(id: "tile.fullScreen", title: "Open Full Screen",
                                    value: Self.onOff(item.wantsFullScreen),
                                    detail: isAccessibilityTrusted ? nil : "Needs Accessibility access",
                                    action: .toggleTileFullScreen(id: id)))
        }
        if !item.isExitToDesktop {
            rows.append(SettingsRow(id: "tile.requiresPIN", title: "Require PIN",
                                    value: Self.onOff(item.requiresPIN == true),
                                    detail: hasPIN ? nil : "Set a PIN in Settings first",
                                    action: .toggleTileRequiresPIN(id: id)))
        }
        let isDefault = LaunchItem.defaults.contains { $0.id == id }
        rows.append(SettingsRow(id: "tile.move", title: "Move", action: .startMove(id: id)))
        rows.append(SettingsRow(id: "tile.remove", title: "Remove from Home Screen",
                                detail: isDefault ? "You can add it back from Add Tile" : nil,
                                action: .removeTile(id: id)))
        let footer = item.isExitToDesktop ? "Exit to Desktop always asks for the PIN when one is set." : nil
        return [SettingsSection(id: "options", rows: rows, footer: footer)]
    }

    private var confirmRestoreSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.restore", title: "Restore Defaults", action: .restoreDefaults),
            ], footer: "Replaces every tile with the defaults. Added apps, hidden tiles and the order are reset."),
        ]
    }

    private var confirmClearYouTubeSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.clearYouTube", title: "Sign Out & Clear", action: .clearYouTubeData),
            ], footer: "Signs every account out of YouTube on this Mac and deletes its watch data. YouTube's Parent code may be removed too."),
        ]
    }

    private static func channelCount(_ count: Int) -> String {
        "\(count.formatted()) Channels"
    }

    /// M4: the playlist and guide addresses come from the clipboard (L2).
    private var liveTVSections: [SettingsSection] {
        var playlistRows: [SettingsRow] = []
        if iptv.hasPlaylist {
            playlistRows.append(SettingsRow(id: "iptv.playlist.info", title: iptv.playlistHost ?? "Playlist",
                                            value: Self.channelCount(iptv.channelCount), detail: iptv.playlistLine))
        }
        playlistRows.append(SettingsRow(id: "iptv.playlist.paste",
                                        title: iptv.hasPlaylist ? "Replace with Clipboard URL" : "Paste Playlist URL",
                                        detail: pasteMessage ?? "Copy the M3U address on this Mac or your iPhone first",
                                        action: .pasteIPTVURL(.playlist)))
        var sections = [SettingsSection(id: "playlist", title: "Playlist", rows: playlistRows)]
        guard iptv.hasPlaylist else { return sections }

        let guideTitle: String
        let guideDetail: String
        switch iptv.guideKind {
        case .none:
            guideTitle = "No guide"
            guideDetail = "Paste an XMLTV guide URL to see what's on"
        case .playlist(let host):
            guideTitle = "From the playlist: \(host)"
            guideDetail = iptv.guideLine
        case .custom(let host):
            guideTitle = "Custom: \(host)"
            guideDetail = iptv.guideLine
        }
        var guideRows = [
            SettingsRow(id: "iptv.guide.info", title: guideTitle, detail: guideDetail),
            SettingsRow(id: "iptv.guide.paste", title: "Paste Guide URL", action: .pasteIPTVURL(.guide)),
        ]
        if case .custom = iptv.guideKind {
            guideRows.append(SettingsRow(id: "iptv.guide.usePlaylist", title: "Use the Playlist's Guide",
                                         action: .useIPTVPlaylistGuide))
        }
        sections.append(SettingsSection(id: "guide", title: "Guide", rows: guideRows))
        sections.append(SettingsSection(id: "manage", rows: [
            SettingsRow(id: "iptv.refresh", title: "Refresh Now", action: .refreshIPTV),
            SettingsRow(id: "iptv.remove", title: "Remove Live TV Source", showsDisclosure: true,
                        action: .push(.confirmRemoveIPTV)),
        ], footer: "Addresses are kept in the Keychain. The first paste may ask for permission; choose Allow."))
        return sections
    }

    private var confirmRemoveIPTVSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.removeIPTV", title: "Remove", action: .removeIPTVSource),
            ], footer: "Forgets the playlist and guide addresses and deletes the downloaded guide."),
        ]
    }

    private var addTileSections: [SettingsSection] {
        var sections: [SettingsSection] = []
        let missing = items.missingDefaults
        if !missing.isEmpty {
            sections.append(SettingsSection(id: "builtIn", title: "MMTVL", rows: missing.map { item in
                SettingsRow(id: "add.default.\(item.id)", title: environment.tileTitle(item), image: .item(item),
                            action: .addDefaultTile(id: item.id))
            }))
        }

        let appRows: [SettingsRow]
        if let installedApps {
            let taken = items.applicationBundleIDs.union(missing.applicationBundleIDs)
            let rows = installedApps.filter { !taken.contains($0.bundleID) }.map { app in
                SettingsRow(id: "add.app.\(app.bundleID)", title: app.name, image: .app(app.url), action: .addApp(app))
            }
            appRows = rows.isEmpty ? [SettingsRow(id: "apps.none", title: "No other apps found")] : rows
        } else {
            appRows = [SettingsRow(id: "apps.loading", title: "Loading…")]
        }
        sections.append(SettingsSection(id: "apps", title: "Applications", rows: appRows))
        return sections
    }
}
