import Foundation
import os

// M7j: the antenna's side of the library. Its channels join the playlist's (`updateChannels()`); every change
// rematches the guides and recomputes My Teams, so an antenna game shows there too.

extension IPTVLibrary {
    /// L13: Live TV has something to show: a playlist, or a tuner that was found.
    var hasLiveSource: Bool { hasPlaylist || !antenna.devices.isEmpty }

    /// L13: Live TV may have something to show once the sources are read: a playlist, or the antenna turned on.
    var canHaveLiveSource: Bool { hasPlaylist || antenna.isEnabled }

    /// The playlist and the antenna's lineup when stale, at the same time.
    func refreshChannelsIfStale() async {
        async let playlist: Void = refreshPlaylistIfStale()
        async let tuners: Void = refreshAntennaIfStale()
        _ = await (playlist, tuners)
    }

    /// Launch (D23): the playlist (always fetched) and the antenna's discovery and lineup (L4) at the same time,
    /// then the guides when stale and (L10) the antenna guide when due. M7n L1: then, while the antenna or the
    /// playlist is missing (the network wasn't up yet), the retry loop starts (`channelRetryTask`; not awaited).
    func refreshAtLaunch() async {
        cancelChannelRetry()
        async let playlist: Void = refreshPlaylist()
        async let tuners = discoverAntenna()
        _ = await (playlist, tuners)
        await refreshGuideIfStale()
        await refreshAntennaGuideIfDue()
        startChannelRetryIfMissing()
    }

    /// After wake (D40, L4): the playlist when stale and the antenna's discovery and lineup, then the guides when
    /// stale and (L10) the antenna guide when due. M7n L1: then the retry loop, as at launch.
    func refreshAfterWake() async {
        cancelChannelRetry()
        async let playlist: Void = refreshPlaylistIfStale()
        async let tuners = discoverAntenna()
        _ = await (playlist, tuners)
        await refreshGuideIfStale()
        await refreshAntennaGuideIfDue()
        startChannelRetryIfMissing()
    }

    // MARK: - The launch and wake retry (M7n L1)

    /// The antenna is on and knows no tuner.
    var isAntennaMissing: Bool { antenna.isEnabled && antenna.devices.isEmpty }
    /// A playlist is set and has no channels.
    var isPlaylistMissing: Bool { hasPlaylist && playlistChannels.isEmpty }

    /// One loop at a time: a newer launch or wake refresh ends the old one.
    private func cancelChannelRetry() {
        channelRetryTask?.cancel()
        channelRetryTask = nil
    }

    private func startChannelRetryIfMissing() {
        guard isAntennaMissing || isPlaylistMissing else { return }
        // QA minor 1: two overlapping refreshes (launch, then wake) each start a loop; only the newest runs.
        channelRetryTask?.cancel()
        channelRetryTask = Task { await retryChannelsUntilLoaded() }
    }

    /// While the antenna or the playlist is missing, waits (`channelRetryDelays`, then `channelRetryRepeat`) and tries
    /// the missing ones again: the antenna with `discoverAntenna()`, the playlist with `refreshPlaylist()`, at the same
    /// time. A try that brings channels is followed by the guides (`refreshGuideIfStale()`, then
    /// `refreshAntennaGuideIfDue()`), since a guide import is skipped while there are no channels. Ends when nothing
    /// is missing (both loaded, or the antenna turned off / the playlist removed), when the next try would be more
    /// than `channelRetryLimit` after the first one (on `retryClock`), or when cancelled. Logs once at the start and
    /// once at the end, counts only.
    func retryChannelsUntilLoaded() async {
        let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")
        let start = retryClock()
        logger.notice("Network not ready: retrying the channels for up to 5 min (\(Self.missingText(antenna: self.isAntennaMissing, playlist: self.isPlaylistMissing), privacy: .public) missing)")
        var delays = Self.channelRetryDelays[...]
        var tries = 0
        let antennaWasMissing = isAntennaMissing
        let playlistWasMissing = isPlaylistMissing
        var ending = "nothing missing"
        while true {
            guard !Task.isCancelled else {
                ending = "a newer refresh took over"
                break
            }
            guard isAntennaMissing || isPlaylistMissing else { break }
            let delay = delays.popFirst() ?? Self.channelRetryRepeat
            guard retryClock() - start + delay <= Self.channelRetryLimit else {
                ending = "5 min passed"
                break
            }
            await retrySleep(delay)
            guard !Task.isCancelled else {
                ending = "a newer refresh took over"
                break
            }
            let antennaWanted = isAntennaMissing
            let playlistWanted = isPlaylistMissing
            guard antennaWanted || playlistWanted else { break }
            tries += 1
            // In its own task: a newer refresh cancelling this loop doesn't cancel a fetch in flight.
            await Task { await self.retryMissingChannels(antenna: antennaWanted, playlist: playlistWanted) }.value
        }
        // QA minor 2: an antenna turned off or a playlist removed isn't "nothing missing" in the log.
        if ending == "nothing missing", (antennaWasMissing && !antenna.isEnabled) || (playlistWasMissing && !hasPlaylist) {
            ending = "a source was turned off or removed"
        }
        logger.notice("Channel retry ended (\(ending, privacy: .public)) after \(tries, privacy: .public) tries: \(self.antenna.devices.count, privacy: .public) tuners, \(self.antenna.channels.count, privacy: .public) antenna channels, \(self.playlistChannels.count, privacy: .public) playlist channels")
    }

    /// One try of the retry loop; the guides when it brought channels.
    private func retryMissingChannels(antenna retryAntenna: Bool, playlist retryPlaylist: Bool) async {
        async let playlist: Void = retryPlaylistIfMissing(retryPlaylist)
        async let tuners: Void = retryAntennaIfMissing(retryAntenna)
        _ = await (playlist, tuners)
        let brought = (retryAntenna && !antenna.devices.isEmpty) || (retryPlaylist && !playlistChannels.isEmpty)
        guard brought else { return }
        await refreshGuideIfStale()
        await refreshAntennaGuideIfDue()
    }

    private func retryPlaylistIfMissing(_ wanted: Bool) async {
        guard wanted, isPlaylistMissing else { return }
        await refreshPlaylist()
    }

    private func retryAntennaIfMissing(_ wanted: Bool) async {
        guard wanted, isAntennaMissing else { return }
        await discoverAntenna()
    }

    private nonisolated static func missingText(antenna: Bool, playlist: Bool) -> String {
        switch (antenna, playlist) {
        case (true, true): "antenna and playlist"
        case (true, false): "antenna"
        default: "playlist"
        }
    }

    /// The antenna's lineup (a search first when no tuner is known).
    func refreshAntenna() async {
        await antenna.refresh()
        await antennaDidChange()
    }

    func refreshAntennaIfStale() async {
        await antenna.refreshIfStale()
        await antennaDidChange()
    }

    /// Searches for tuners and reads their lineups; returns how many tuners were found.
    @discardableResult
    func discoverAntenna() async -> Int {
        let found = await antenna.discover()
        await antennaDidChange()
        return found
    }

    /// L14: `settings.json` `antennaEnabled` changed. Off: the antenna channels go at once; on: a search starts.
    func applyAntennaEnabled(_ enabled: Bool) async {
        guard enabled != antenna.isEnabled else { return }
        antenna.isEnabled = enabled
        Logger(subsystem: "dev.mmtvl.launcher", category: "Antenna")
            .notice("Antenna \(enabled ? "on" : "off", privacy: .public)")
        await antennaDidChange()
        if enabled {
            await discoverAntenna()
            await refreshAntennaGuideIfDue()
        }
    }

    // MARK: - Channel scan (L18)

    /// Settings → Antenna → Scan for Channels → Scan: MMTVL's own antenna streams stop first
    /// (`stopAntennaStreams`), then `AntennaSource.startScan()`.
    func startAntennaScan() {
        guard antenna.isEnabled, !antenna.devices.isEmpty, !antenna.isScanning else { return }
        stopAntennaStreams?()
        antenna.startScan()
        onStatusChange?()
    }

    /// Stop Scan (no confirm).
    func stopAntennaScan() {
        antenna.stopScan()
        onStatusChange?()
    }

    /// Settings → Antenna on screen or not (L18): a running scan is polled every second while it is; opening it
    /// reads whether the tuners can scan and shows a scan started elsewhere.
    func antennaPageVisible(_ visible: Bool) async {
        antenna.isScanPageVisible = visible
        guard visible else { return }
        await antenna.checkScan()
    }

    /// `AntennaSource.onScanChange`: after the lineup was read again (the scan ended or was stopped), the channels
    /// merge, the guides rematch and My Teams is recomputed (`rematch()`); then Settings reads the new state.
    func antennaScanDidChange(lineupRead: Bool) async {
        if lineupRead {
            let before = antennaChannelIDs
            _ = updateChannels()
            await rematch()
            await importAntennaGuideForNewChannels(before: before)
        }
        onStatusChange?()
    }

    /// The antenna channels' ids in `channels` (the merged list), before a lineup read merges.
    private var antennaChannelIDs: Set<Channel.ID> { Set(channels.lazy.filter(\.isDirectStream).map(\.id)) }

    /// Pre-build QA minor 1: the antenna guide keeps programmes only for the channels matched at its import, so a
    /// channel a lineup read (a scan, a refresh) newly brought would have none until the next download, 20–28 h
    /// later. When a new antenna channel now matches an antenna-guide channel and has no programmes, the guide is
    /// imported again, as Match Guide does (`reimport`: never within an hour of the last import or attempt; then the
    /// guide is due when that hour ends, `dueAntennaGuideWhenTheHourEnds`). Nothing new matched, or the first lineup
    /// since the antenna had no channels (launch: `refreshAntennaGuideIfDue` follows), downloads nothing.
    private func importAntennaGuideForNewChannels(before: Set<Channel.ID>) async {
        guard keepsAntennaGuide, !before.isEmpty else { return }
        var missing = 0
        for channel in channels where channel.isDirectStream && !before.contains(channel.id) {
            guard let ref = epgMatches[channel.id], ref.sourceID == AntennaGuide.sourceID else { continue }
            if await !hasProgrammes(ref) { missing += 1 }
        }
        guard missing > 0 else { return }
        Logger(subsystem: "dev.mmtvl.launcher", category: "Antenna")
            .notice("New antenna channels without programmes: \(missing, privacy: .public); importing the guide again")
        if await !reimport(AntennaGuide.sourceID) { dueAntennaGuideWhenTheHourEnds() }
    }

    /// The antenna channels' guide matches (L10, L11, L12). `antennaGuide`: the antenna guide's channels while it's
    /// in use (`keepsAntennaGuide`), else nil. In use: `AntennaGuide.match` over it, except that an override naming
    /// a pasted guide's channel (Match Guide offers those too, L12) wins, as an override does in `EPGMatcher`. Not in
    /// use: the pasted guides' rules (`EPGMatcher`, by name; tvg-id is nil), so Match Guide works for antenna
    /// channels as for the playlist's.
    nonisolated static func antennaMatches(_ antennaChannels: [Channel], antennaGuide: [EPGChannel]?,
                                           pasted sources: [EPGSourceChannels],
                                           overrides: [String: String]) -> [Channel.ID: EPGRef] {
        guard let antennaGuide else {
            return EPGMatcher.match(antennaChannels, sources: sources, overrides: overrides)
        }
        var result = AntennaGuide.match(antennaChannels, to: antennaGuide, overrides: overrides)
            .mapValues { EPGRef(sourceID: AntennaGuide.sourceID, epgID: $0) }
        guard !overrides.isEmpty else { return result }
        let antennaIDs = Set(antennaGuide.map { $0.id.lowercased() })
        for channel in antennaChannels {
            guard let target = AntennaGuide.overrideTarget(for: channel, in: overrides), !target.isEmpty,
                  !antennaIDs.contains(target),
                  let source = sources.first(where: { $0.channels.contains { $0.id.lowercased() == target } })
            else { continue }
            result[channel.id] = EPGRef(sourceID: source.sourceID, epgID: target)
        }
        return result
    }

    /// L9: after an antenna stream failed (`onFailure`), why, asking the tuner (no tuner taken). The tuner not
    /// answering: a search and the lineup again; a 404: the lineup again. Either way, `.retry` with the channel
    /// when the lineup was read and still has it, else the problem. `mayRetry` false (the channel was already
    /// retried since it was chosen): the problem at once, without the search or lineup read. The playlist is never
    /// re-fetched for an antenna failure.
    func diagnose(_ channel: Channel, httpStatus: Int?, mayRetry: Bool) async -> AntennaDiagnosis.Outcome {
        guard case .antenna(let deviceID) = channel.source else { return .show(.unknown) }
        let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Antenna")
        let device = antenna.devices.first { $0.id == deviceID }
        var problem = AntennaProblem.unreachable
        if let device {
            problem = await AntennaDiagnosis.diagnose(device: device, httpStatus: httpStatus, http: antenna.http)
        }
        logger.notice("Antenna stream: \(problem.logText, privacy: .public)")
        guard mayRetry, problem == .unreachable || problem == .unknownChannel else { return .show(problem) }
        if problem == .unreachable {
            await discoverAntenna()
        } else {
            await refreshAntenna()
        }
        guard case .loaded = antenna.status else { return .show(.unreachable) }
        guard let fresh = channels.first(where: { $0.id == channel.id }) else { return .show(problem) }
        return .retry(fresh)
    }

    /// M7j L14: what Settings → Live TV → Antenna shows (`AppDelegate.iptvSettingsStatus()`). Names, models, counts
    /// and the guide's line only: never a DeviceID, an address or DeviceAuth.
    func fillAntennaSettings(_ status: inout IPTVSettingsStatus) {
        status.antennaEnabled = antenna.isEnabled
        status.antennaSearching = antenna.isSearching || !antenna.hasSearched
        let antennaChannels = antenna.channels
        // Step 10 (security N3): each device's channel count and entries by GuideNumber are built once per call
        // (the first entry with a number, as before), not searched per channel: at the caps (16 devices × 1,000
        // entries) a linear search per channel ran on the main actor at every status change while Settings showed.
        var channelCounts: [String: Int] = [:]
        for channel in antennaChannels {
            if case .antenna(let deviceID) = channel.source { channelCounts[deviceID, default: 0] += 1 }
        }
        status.antennaTuners = antenna.devices.map { device in
            IPTVSettingsStatus.AntennaTunerStatus(name: device.name, model: device.model, tunerCount: device.tunerCount,
                                                  channelCount: channelCounts[device.id] ?? 0)
        }
        let entriesByNumber = antenna.entries.mapValues { entries in
            Dictionary(entries.map { ($0.guideNumber, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let hidden = Set(preferences.hiddenChannels)
        status.antennaChannels = antennaChannels.map { channel in
            var entry: HDHomeRunLineupEntry?
            if case .antenna(let deviceID) = channel.source, let number = channel.guideNumber {
                entry = entriesByNumber[deviceID]?[number]
            }
            return IPTVSettingsStatus.AntennaChannelStatus(
                id: channel.id, displayNumber: channel.displayNumber, name: channel.name, isHD: entry?.hd ?? false,
                signalQuality: entry?.signalQuality.map { min(max($0, 0), 100) }, isHidden: hidden.contains(channel.id))
        }
        status.antennaLeftOut = antenna.leftOut
        if case .failed(let message) = antenna.status { status.antennaLineupLine = message }
        // L18: counts only.
        status.antennaScan = antenna.scan
        status.antennaCanScan = antenna.canScan

        // Step 8: the antenna guide has its own line; it isn't one of the Guides section's guides.
        let id = AntennaGuide.sourceID
        let info = guideSourceInfo[id] ?? GuideSourceInfo()
        func summary(_ date: Date) -> String {
            "Updated \(Self.settingsDate(date)) · \(info.programmeCount.formatted()) programmes · \(info.matchedChannels) of \(antennaChannels.count) channels"
        }
        status.antennaGuideLine = switch info.status {
        case .loading: "Loading…"
        case .failed(let message): "Failed: \(message)"
        case .loaded(let date): summary(date)
        case .idle: state.guideImports[id].map(summary) ?? "Not loaded yet"
        }
    }

    /// "Nov 15, 9:12 AM" (`.dateTime` with a time would say "Nov 15 at 9:12 AM").
    nonisolated static func settingsDate(_ date: Date) -> String {
        "\(date.formatted(.dateTime.month(.abbreviated).day())), \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// Merges the antenna's channels; on a change, rematches (which recomputes My Teams). Then tells Settings, so it
    /// reads the new channels, groups and guide matches (step 9 QA 1).
    private func antennaDidChange() async {
        let before = antennaChannelIDs
        if updateChannels() {
            await rematch()
            await importAntennaGuideForNewChannels(before: before)
        }
        onStatusChange?()
    }
}
