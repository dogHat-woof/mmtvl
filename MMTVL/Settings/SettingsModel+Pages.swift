import Foundation

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
        case .guideSource(let id): guideSourceSections(id: id)
        case .iptvGroups: iptvGroupsSections
        case .iptvHiddenChannels: iptvHiddenChannelsSections
        case .phoneRemote: phoneRemoteSections
        case .pairPhone: pairPhoneSections
        case .confirmForgetPhones: confirmForgetPhonesSections
        case .remoteButtons: remoteButtonsSections
        case .remoteCommand(let command): remoteCommandSections(command)
        case .remoteBinding(let command, let trigger): remoteBindingSections(command, trigger)
        case .learnButton(let command): learnButtonSections(command)
        case .confirmLearn(let command, let trigger): confirmLearnSections(command, trigger)
        case .confirmRestoreButtons: confirmRestoreButtonsSections
        case .plex: plexSections
        case .plexLink: plexLinkSections
        case .tileArt(let id): tileArtSections(id: id)
        case .plexServers: plexServersSections
        case .confirmPlexSignOut: confirmPlexSignOutSections
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
        case .guideSource(let id): guideSource(id: id)?.label ?? "Guide"
        case .iptvGroups: "Groups"
        case .iptvHiddenChannels: "Hidden Channels"
        case .phoneRemote: "Phone Remote"
        case .pairPhone: "Pair a Phone"
        case .confirmForgetPhones: "Forget All Phones?"
        case .remoteButtons: "Remote Buttons"
        case .remoteCommand(let command): command.title
        case .remoteBinding(_, let trigger): TriggerName.describe(trigger)
        case .learnButton: "Press a Button"
        case .confirmLearn(let command, let trigger): "Use \(TriggerName.describe(trigger)) for \(command.title)?"
        case .confirmRestoreButtons: "Restore Default Buttons?"
        case .plex: "Plex"
        case .plexLink: "Sign In to Plex"
        case .tileArt: "Tile Art"
        case .plexServers: "Plex Server"
        case .confirmPlexSignOut: "Sign Out of Plex?"
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
        case .guideSource: .symbol("list.bullet.rectangle")
        case .iptvGroups: .symbol("folder")
        case .iptvHiddenChannels: .symbol("eye.slash")
        case .phoneRemote: .symbol("iphone")
        case .pairPhone: phoneRemote.pairingURL.map(RowImage.qrCode) ?? .symbol("iphone")
        case .confirmForgetPhones: .symbol("iphone.slash")
        case .remoteButtons, .remoteCommand, .remoteBinding, .confirmLearn: .symbol("appletvremote.gen4")
        case .learnButton: .symbol("hand.point.up.left")
        case .confirmRestoreButtons: .symbol("arrow.counterclockwise")
        case .plex, .plexServers: .symbol("play.square.stack")
        case .plexLink: plex.linkURL.map(RowImage.qrCode) ?? .symbol("play.square.stack")
        case .confirmPlexSignOut: .symbol("rectangle.portrait.and.arrow.right")
        case .tileArt(let id): .tileArt(itemID: id, tileArtPreviewChoice)
        }
    }

    var hint: String {
        switch page {
        case .root, .tile, .liveTV, .phoneRemote, .guideSource, .iptvGroups, .iptvHiddenChannels,
             .remoteButtons, .remoteCommand, .remoteBinding, .plex, .plexServers, .tileArt:
            "Select: choose · Back: return"
        case .plexLink: "Back: cancel"
        case .learnButton: "Waiting for a button…"
        case .pairPhone: "Back: done"
        case .homeScreen:
            movingTileID == nil ? "Select: edit tile · Back: return" : "Up/Down: move · Select or Back: done"
        case .addTile: "Select: add · Back: return"
        case .confirmRestoreDefaults, .confirmClearYouTube, .confirmRemoveIPTV, .confirmForgetPhones,
             .confirmLearn, .confirmRestoreButtons, .confirmPlexSignOut:
            "Select: choose · Back: cancel"
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
                SettingsRow(id: "remoteButtons", title: "Remote Buttons", showsDisclosure: true,
                            action: .push(.remoteButtons)),
                SettingsRow(id: "channelUp", title: "Channel Up",
                            value: settings.channelUpMovesUpList ? "Up the List" : "Higher Number",
                            detail: "Changes channel in Live TV", action: .toggle(.channelUpMovesUpList)),
                SettingsRow(id: "cursorAutoHide", title: "Hide Pointer During Remote Use",
                            value: Self.onOff(settings.cursorAutoHide), action: .toggle(.cursorAutoHide)),
                SettingsRow(id: "phoneRemote", title: "Phone Remote", value: Self.onOff(settings.phoneRemoteEnabled),
                            showsDisclosure: true, action: .push(.phoneRemote)),
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
            SettingsSection(id: "plex", title: "Plex", rows: [
                SettingsRow(id: "plex", title: "Plex", value: plex.isSignedIn ? "Signed In" : "Not Signed In",
                            showsDisclosure: true, action: .push(.plex)),
            ]),
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
                tileArtRow(id: id),
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
        if environment.webAppInfo(item) != nil {
            rows.append(contentsOf: startURLRows(item))
        }
        if !item.isExitToDesktop {
            rows.append(SettingsRow(id: "tile.requiresPIN", title: "Require PIN",
                                    value: Self.onOff(item.requiresPIN == true),
                                    detail: hasPIN ? nil : "Set a PIN in Settings first",
                                    action: .toggleTileRequiresPIN(id: id)))
        }
        let isDefault = LaunchItem.defaults.contains { $0.id == id }
        rows.append(tileArtRow(id: id))
        rows.append(SettingsRow(id: "tile.move", title: "Move", action: .startMove(id: id)))
        rows.append(SettingsRow(id: "tile.remove", title: "Remove from Home Screen",
                                detail: isDefault ? "You can add it back from Add Tile" : nil,
                                action: .removeTile(id: id)))
        let footer = item.isExitToDesktop ? "Exit to Desktop always asks for the PIN when one is set." : nil
        return [SettingsSection(id: "options", rows: rows, footer: footer)]
    }

    /// M7 L23: web app tiles only.
    private func startURLRows(_ item: LaunchItem) -> [SettingsRow] {
        var rows = [SettingsRow(id: "tile.startURL", title: "Start Page",
                                value: item.startURL.map(Self.startURLLabel) ?? "App's Own",
                                detail: startURLMessage ?? "Copy a page address on this Mac or your iPhone, then select",
                                action: .pasteTileStartURL(id: item.id))]
        if item.startURL != nil {
            rows.append(SettingsRow(id: "tile.startURL.clear", title: "Use the App's Own Start Page",
                                    action: .clearTileStartURL(id: item.id)))
        }
        return rows
    }

    /// Host + path (+ "?" + query), cut to 48 characters.
    static func startURLLabel(_ url: URL) -> String {
        var label = (url.host() ?? "") + url.path()
        if let query = url.query(), !query.isEmpty { label += "?" + query }
        return label.count > 48 ? String(label.prefix(47)) + "…" : label
    }

    /// M7 L3, L25: opens the Tile Art page.
    private func tileArtRow(id: String) -> SettingsRow {
        let value = environment.tileArtFileName(id)
            ?? (item(id: id)?.tileArtStyle == .icon ? "App Icon" : "Designed")
        return SettingsRow(id: "tile.art", title: "Tile Art", value: value, showsDisclosure: true,
                           action: .push(.tileArt(id: id)))
    }

    /// L25: the style for apps; only designed art for built-ins and web addresses.
    private func offersIconStyle(_ item: LaunchItem) -> Bool {
        switch item.kind {
        case .application, .defaultBrowser: true
        case .url, .internalDestination, .system: false
        }
    }

    private func tileArtSections(id: String) -> [SettingsSection] {
        guard let item = item(id: id) else { return [] }
        let custom = environment.tileArtFileName(id)
        let styleDetail = custom == nil ? nil : "Used when there's no picture"
        var styleRows = [SettingsRow(id: "art.designed", title: "Designed",
                                     value: item.tileArtStyle == .designed ? "Selected" : nil, detail: styleDetail,
                                     action: .setTileArtStyle(id: id, .designed))]
        if offersIconStyle(item) {
            styleRows.append(SettingsRow(id: "art.icon", title: "App Icon",
                                         value: item.tileArtStyle == .icon ? "Selected" : nil, detail: styleDetail,
                                         action: .setTileArtStyle(id: id, .icon)))
        }
        var sections = [SettingsSection(id: "style", title: "Style", rows: styleRows)]
        if let custom {
            sections.append(SettingsSection(id: "custom", title: "Your Picture", rows: [
                SettingsRow(id: "art.custom", title: custom, value: "In Use"),
                SettingsRow(id: "art.removeCustom", title: "Remove Picture", action: .removeTileArtPicture(id: id)),
            ]))
        }
        var pictureRows: [SettingsRow]
        if let pictures {
            pictureRows = pictures.enumerated().map { index, file in
                SettingsRow(id: "art.file.\(index)", title: file.name, detail: PictureFinder.detail(file),
                            image: .picture(file.url), action: .useTileArtPicture(id: id, file.url))
            }
            if pictureRows.isEmpty {
                pictureRows.append(SettingsRow(id: "art.file.none", title: "No pictures in Downloads, Pictures or Desktop"))
            }
        } else {
            pictureRows = [SettingsRow(id: "art.file.loading", title: "Looking for pictures…")]
        }
        if let tileArtMessage {
            pictureRows.insert(SettingsRow(id: "art.message", title: tileArtMessage), at: 0)
        }
        sections.append(SettingsSection(id: "pictures", title: "Pictures on This Mac", rows: pictureRows,
                                        footer: "You can also put a 5:3 picture named \(id).png in …/MMTVL/tile-art."))
        return sections
    }

    /// L25: the side column previews the focused option.
    private var tileArtPreviewChoice: TileArtChoice {
        guard let id = focusedRowID, let action = row(id: id)?.action else { return .current }
        switch action {
        case .setTileArtStyle(_, let style): return .style(style)
        case .useTileArtPicture(_, let url): return .file(url)
        default: return .current
        }
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
                                        detail: pasteMessage(for: .playlist) ?? "Copy the M3U address on this Mac or your iPhone first",
                                        action: .pasteIPTVURL(.playlist)))
        var sections = [SettingsSection(id: "playlist", title: "Playlist", rows: playlistRows)]
        guard iptv.hasPlaylist else { return sections }

        sections.append(guidesSection)
        sections.append(channelsSection)
        sections.append(SettingsSection(id: "manage", rows: [
            SettingsRow(id: "iptv.refresh", title: "Refresh Now", action: .refreshIPTV),
            SettingsRow(id: "iptv.remove", title: "Remove Live TV Source", showsDisclosure: true,
                        action: .push(.confirmRemoveIPTV)),
        ], footer: "Addresses are kept in the Keychain. The first paste may ask for permission; choose Allow."))
        return sections
    }

    private func pasteMessage(for kind: IPTVURLKind) -> String? {
        pasteMessageKind == kind ? pasteMessage : nil
    }

    private func guideSource(id: String) -> IPTVSettingsStatus.GuideSourceStatus? {
        iptv.guideSources.first { $0.id == id }
    }

    /// M6b L1: the guides in priority order; pasted ones open their own page.
    private var guidesSection: SettingsSection {
        var rows = iptv.guideSources.enumerated().map { index, source in
            SettingsRow(id: "iptv.guide.\(source.id)", title: source.label,
                        value: source.isFromPlaylist ? "From Playlist" : "\(index + 1)", detail: source.line,
                        showsDisclosure: !source.isFromPlaylist,
                        action: source.isFromPlaylist ? nil : .push(.guideSource(id: source.id)))
        }
        if rows.isEmpty {
            rows.append(SettingsRow(id: "iptv.guide.none", title: "No guide",
                                    detail: "Copy an XMLTV guide address, then add it below"))
        }
        if iptv.customGuideCount < IPTVLibrary.maxGuideSources {
            rows.append(SettingsRow(id: "iptv.guide.add", title: "Add Guide from Clipboard",
                                    detail: pasteMessage(for: .guide) ?? "Copy an XMLTV address on this Mac or your iPhone first",
                                    action: .pasteIPTVURL(.guide)))
        }
        return SettingsSection(id: "guides", title: "Guides", rows: rows,
                               footer: "Guide data for \(iptv.matchedChannelCount) of \(iptv.channelCount) channels. A channel uses the first guide in this list that has it.")
    }

    /// M6b L5: groups and hidden channels; favorites and single channels are managed from the guide.
    private var channelsSection: SettingsSection {
        let hiddenGroups = iptv.groups.filter(\.isHidden).count
        return SettingsSection(id: "channels", title: "Channels", rows: [
            SettingsRow(id: "iptv.groups", title: "Groups", value: hiddenGroups == 0 ? "All Shown" : "\(hiddenGroups) Hidden",
                        showsDisclosure: true, action: .push(.iptvGroups)),
            SettingsRow(id: "iptv.hiddenChannels", title: "Hidden Channels",
                        value: iptv.hiddenChannels.isEmpty ? "None" : "\(iptv.hiddenChannels.count)",
                        showsDisclosure: true, action: .push(.iptvHiddenChannels)),
        ], footer: "To favorite, hide or match one channel: in the guide, press Left on the programme airing now, then Select.")
    }

    private var iptvGroupsSections: [SettingsSection] {
        let rows = iptv.groups.map { group in
            SettingsRow(id: "group.\(group.name)", title: group.name, value: group.isHidden ? "Hidden" : "Shown",
                        detail: "\(group.channelCount) channels", isDimmed: group.isHidden,
                        action: .toggleIPTVGroupHidden(group.name))
        }
        return [SettingsSection(id: "groups", rows: rows,
                                footer: "Hidden groups and their channels don't show in the guide or when changing channels.")]
    }

    private var iptvHiddenChannelsSections: [SettingsSection] {
        var rows = iptv.hiddenChannels.map { channel in
            SettingsRow(id: "hidden.\(channel.id)", title: "\(channel.number)  \(channel.name)", value: "Show",
                        detail: channel.group, action: .unhideIPTVChannel(id: channel.id))
        }
        if rows.isEmpty {
            rows.append(SettingsRow(id: "hidden.none", title: "No hidden channels"))
        }
        return [SettingsSection(id: "hiddenChannels", rows: rows, footer: "Select a channel to show it again.")]
    }

    /// M6b: one pasted guide.
    private func guideSourceSections(id: String) -> [SettingsSection] {
        let pasted = iptv.guideSources.filter { !$0.isFromPlaylist }
        guard let index = pasted.firstIndex(where: { $0.id == id }) else { return [] }
        var rows = [SettingsRow(id: "guideSource.status", title: "Status", detail: pasted[index].line)]
        if index > 0 {
            rows.append(SettingsRow(id: "guideSource.moveUp", title: "Move Up", action: .moveGuideSource(id: id, by: -1)))
        }
        if index < pasted.count - 1 {
            rows.append(SettingsRow(id: "guideSource.moveDown", title: "Move Down", action: .moveGuideSource(id: id, by: 1)))
        }
        rows.append(SettingsRow(id: "guideSource.remove", title: "Remove Guide", action: .removeGuideSource(id: id)))
        return [SettingsSection(id: "guideSource", rows: rows,
                                footer: "When two guides have the same channel, the higher one wins.")]
    }

    private var confirmRemoveIPTVSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.removeIPTV", title: "Remove", action: .removeIPTVSource),
            ], footer: "Forgets the playlist and guide addresses and deletes the downloaded guide."),
        ]
    }

    /// M5.
    private var phoneRemoteSections: [SettingsSection] {
        var serverRows = [
            SettingsRow(id: "phone.enabled", title: "Phone Remote", value: Self.onOff(settings.phoneRemoteEnabled),
                        detail: phoneRemote.problem, action: .toggle(.phoneRemoteEnabled)),
        ]
        if settings.phoneRemoteEnabled {
            serverRows.append(SettingsRow(id: "phone.address", title: "Address",
                                          value: phoneRemote.address ?? "No network connection"))
            if phoneRemote.isRunning {
                serverRows.append(SettingsRow(id: "phone.pair", title: "Pair a Phone", showsDisclosure: true,
                                              action: .push(.pairPhone)))
            }
        }

        var phoneRows = [
            SettingsRow(id: "phone.count", title: "Paired Phones", value: "\(phoneRemote.pairedCount)",
                        detail: phoneRemote.connectedCount > 0 ? "\(phoneRemote.connectedCount) connected now" : nil),
        ]
        if phoneRemote.pairedCount > 0 {
            phoneRows.append(SettingsRow(id: "phone.forget", title: "Forget All Phones", showsDisclosure: true,
                                         action: .push(.confirmForgetPhones)))
        }

        return [
            SettingsSection(id: "phone.server", rows: serverRows,
                            footer: "Open the address in the phone's browser. The phone must be on the same network as this Mac."),
            SettingsSection(id: "phone.phones", title: "Phones", rows: phoneRows),
            SettingsSection(id: "phone.access", title: "Typing & Other Apps", rows: [
                SettingsRow(id: "phone.accessibility", title: "Accessibility",
                            value: phoneRemote.canControlOtherApps ? "Allowed" : "Not Allowed",
                            detail: "Needed to type from the phone and to control Plex, Prime Video and the browser",
                            action: .requestAccessibility),
            ], footer: "Volume buttons use SoundSource when it's running, else the Mac's volume when the output allows it, else MMTVL's own volume."),
        ]
    }

    /// M5 L3: the code is valid while this page shows.
    private var pairPhoneSections: [SettingsSection] {
        var rows = [
            SettingsRow(id: "pair.code", title: "Pairing Code", value: phoneRemote.pairingCode ?? "—"),
            SettingsRow(id: "pair.address", title: phoneRemote.address ?? "No network connection",
                        detail: "Or open this address on the phone and enter the code"),
        ]
        if let name = phoneRemote.lastPairedName {
            rows.append(SettingsRow(id: "pair.done", title: "Paired \"\(name)\"", image: .symbol("checkmark.circle")))
        }
        rows.append(SettingsRow(id: "pair.close", title: "Done", action: .pop))
        return [
            SettingsSection(id: "pair", rows: rows,
                            footer: "Scan the code with the phone's camera. Pairing ends when you leave this page."),
        ]
    }

    private var confirmForgetPhonesSections: [SettingsSection] {
        [
            SettingsSection(id: "confirm", rows: [
                SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
                SettingsRow(id: "confirm.forget", title: "Forget All Phones", action: .forgetAllPhones),
            ], footer: "Every phone will need to pair again."),
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

    // MARK: - Remote Buttons (M7, D27)

    private var remoteButtonsSections: [SettingsSection] {
        let rows = RemoteCommand.allCases.map { command in
            let names = bindings.bindings(for: command).map { TriggerName.describe($0.trigger) }
            var value = names.prefix(2).joined(separator: " · ")
            if names.count > 2 { value += " +\(names.count - 2)" }
            return SettingsRow(id: "command.\(command.rawValue)", title: command.title, value: names.isEmpty ? "None" : value,
                               showsDisclosure: true, action: .push(.remoteCommand(command)))
        }
        return [
            SettingsSection(id: "commands", title: "Commands", rows: rows),
            SettingsSection(id: "manage", rows: [
                SettingsRow(id: "restoreButtons", title: "Restore Default Buttons", showsDisclosure: true,
                            action: .push(.confirmRestoreButtons)),
            ], footer: "Buttons apply at once. Phone remote buttons can't be changed."),
        ]
    }

    private func remoteCommandSections(_ command: RemoteCommand) -> [SettingsSection] {
        var rows = bindings.bindings(for: command).enumerated().map { index, binding in
            var detail = TriggerName.kind(binding.trigger)
            if binding.isGlobal { detail += " · Works in other apps" }
            return SettingsRow(id: "binding.\(index)", title: TriggerName.describe(binding.trigger), detail: detail,
                               showsDisclosure: true, action: .push(.remoteBinding(command, binding.trigger)))
        }
        if rows.isEmpty {
            rows.append(SettingsRow(id: "binding.none", title: "No buttons"))
        }
        rows.append(SettingsRow(id: "learn", title: "Add a Button", detail: learnMessage, action: .startLearning(command)))
        var footer: String?
        if command == .home {
            footer = "Home buttons can work in other apps too (needs Accessibility)."
        } else if KeyBindings.essentialCommands.contains(command) {
            footer = "Keep at least one button for \(command.title)."
        }
        return [SettingsSection(id: "buttons", title: "Buttons", rows: rows, footer: footer)]
    }

    private func remoteBindingSections(_ command: RemoteCommand, _ trigger: InputBinding.Trigger) -> [SettingsSection] {
        var rows: [SettingsRow] = []
        if command == .home {
            let isGlobal = bindings.binding(matching: trigger)?.isGlobal == true
            rows.append(SettingsRow(id: "binding.global", title: "Works in Other Apps", value: Self.onOff(isGlobal),
                                    detail: isAccessibilityTrusted ? nil : "Needs Accessibility access",
                                    action: .toggleBindingGlobal(trigger)))
        }
        if bindings.canRemove(trigger) {
            rows.append(SettingsRow(id: "binding.remove", title: "Remove Button", action: .removeBinding(trigger)))
        } else {
            rows.append(SettingsRow(id: "binding.cantRemove", title: "The last button for \(command.title) can't be removed"))
        }
        return [SettingsSection(id: "binding", rows: rows)]
    }

    private func learnButtonSections(_ command: RemoteCommand) -> [SettingsSection] {
        [SettingsSection(id: "learn", rows: [
            SettingsRow(id: "learn.prompt", title: "Press the button to use for \(command.title)",
                        detail: "On the remote, a keyboard or a game controller. Waits 10 seconds."),
            SettingsRow(id: "learn.cancel", title: "Cancel", action: .pop),
        ])]
    }

    private func confirmLearnSections(_ command: RemoteCommand, _ trigger: InputBinding.Trigger) -> [SettingsSection] {
        var detail: String?
        if let existing = bindings.binding(matching: trigger) {
            detail = existing.command == command
                ? "Already used for \(command.title)"
                : "Now used for \(existing.command.title); it moves to \(command.title)"
        }
        return [SettingsSection(id: "confirm", rows: [
            SettingsRow(id: "confirm.use", title: "Use This Button", detail: detail, action: .useLearned(command, trigger)),
            SettingsRow(id: "confirm.retry", title: "Try Again", action: .startLearning(command)),
            SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
        ])]
    }

    private var confirmRestoreButtonsSections: [SettingsSection] {
        [SettingsSection(id: "confirm", rows: [
            SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
            SettingsRow(id: "confirm.restoreButtons", title: "Restore Defaults", action: .restoreDefaultButtons),
        ], footer: "Replaces every button with the defaults.")]
    }

    // MARK: - Plex (M7 D28, L15)

    private var plexSections: [SettingsSection] {
        guard plex.isSignedIn else {
            return [SettingsSection(id: "plex", rows: [
                SettingsRow(id: "plex.signIn", title: "Sign In", detail: "Shows Continue Watching on the Home screen",
                            showsDisclosure: true, action: .push(.plexLink)),
            ], footer: "Signing in uses a code at plex.tv/link; no password is typed here.")]
        }
        let canChoose = plex.servers.count > 1
        return [SettingsSection(id: "plex", rows: [
            SettingsRow(id: "plex.server", title: "Server", value: plex.serverName ?? "None",
                        showsDisclosure: canChoose, action: canChoose ? .push(.plexServers) : nil),
            SettingsRow(id: "plex.status", title: "Status", value: plex.statusLine),
            SettingsRow(id: "plex.signOut", title: "Sign Out", showsDisclosure: true, action: .push(.confirmPlexSignOut)),
        ], footer: "Selecting a Continue Watching item opens Plex.")]
    }

    private var plexLinkSections: [SettingsSection] {
        if plex.isSignedIn && plex.hasNoServer {
            return [SettingsSection(id: "link", rows: [
                SettingsRow(id: "plexLink.noServer", title: "No Plex Media Server on this account"),
                SettingsRow(id: "plexLink.cancel", title: "Done", action: .pop),
            ])]
        }
        return [SettingsSection(id: "link", rows: [
            SettingsRow(id: "plexLink.code", title: "Code", value: plex.linkCode ?? "…"),
            SettingsRow(id: "plexLink.where", title: "plex.tv/link",
                        detail: "On a phone or computer, open plex.tv/link and enter the code, or scan the QR code"),
            SettingsRow(id: "plexLink.cancel", title: "Cancel", action: .pop),
        ])]
    }

    private var plexServersSections: [SettingsSection] {
        let rows = plex.servers.map { server in
            SettingsRow(id: "plexServer.\(server.id)", title: server.name,
                        value: server.name == plex.serverName ? "Selected" : nil, detail: server.detail,
                        action: .choosePlexServer(id: server.id))
        }
        return [SettingsSection(id: "servers", rows: rows, footer: "Continue Watching comes from this server.")]
    }

    private var confirmPlexSignOutSections: [SettingsSection] {
        [SettingsSection(id: "confirm", rows: [
            SettingsRow(id: "confirm.cancel", title: "Cancel", action: .pop),
            SettingsRow(id: "confirm.signOutOfPlex", title: "Sign Out", action: .signOutOfPlex),
        ], footer: "Removes this Mac from your Plex account's sign-in here. Plex HTPC stays signed in.")]
    }
}
