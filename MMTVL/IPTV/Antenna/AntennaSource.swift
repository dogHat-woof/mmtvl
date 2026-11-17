import Foundation
import Observation
import os

/// M7j step 9: Find Tuners' result (`AntennaSource.findOutcome(found:)`).
nonisolated enum AntennaFindOutcome: Equatable, Sendable {
    /// This many tuners answered (found, or known and their lineups read).
    case found(Int)
    /// No tuner known or found.
    case noneFound
    /// The search found nothing, and the known tuners didn't send their lineups.
    case noneAnswered
}

/// M7j L18 (step 9b): a channel scan, as Settings → Live TV → Antenna shows it.
nonisolated enum AntennaScanState: Equatable, Sendable {
    /// The lowest progress of the scanning tuners (percent), and the sum they found.
    case running(progress: Int, found: Int)
    /// The lineup read after the scan: its channels, and how many are new or gone against the lineup before it.
    case finished(found: Int, added: Int, removed: Int)
    /// Stop Scan.
    case stopped
    /// No tuner accepted the scan, or the lineup couldn't be read after it.
    case failed
}

/// M7j L4, L5: the HDHomeRun tuners on the network and their lineups as Live TV channels. Owned by `IPTVLibrary`
/// (`library.antenna`), which merges `channels` after the playlist's. Devices and lineups are kept in memory only.
/// One discovery runs at a time (step 2 security L-b: the `hdhomerun.local` fallback's lookup can block for
/// seconds); a search asked for while one runs waits for it. Logs (category `Antenna`) counts only: never a
/// DeviceID, DeviceAuth, address or stream URL (L15).
@Observable
final class AntennaSource {
    /// Finds the tuners (`HDHomeRunDiscovery.find`); injected for tests.
    typealias Find = () async -> [HDHomeRunDevice]

    /// L5: like the playlist, the lineup is fetched again when it's older than this.
    static let staleness = IPTVLibrary.playlistStaleness
    /// M7n L2: with no tuner known, a search is repeated (`refreshIfStale`, Live TV opening) when the last one is
    /// older than this, so a search that ran before the network was up doesn't hold the next one for 10 minutes.
    static let searchRetryStaleness: TimeInterval = 30
    /// The status while a lineup can't be read.
    nonisolated static let unreachableMessage = "The antenna tuner isn't answering"
    /// L18: a scan is watched for at most this long.
    static let scanTimeLimit: TimeInterval = 15 * 60
    /// L18: `lineup_status.json` is read this often while Settings → Antenna is on screen, else `scanPollSlow`.
    static let scanPollFast: Duration = .seconds(1)
    static let scanPollSlow: Duration = .seconds(5)

    /// The tuners found, in DeviceID order (L1).
    private(set) var devices: [HDHomeRunDevice] = []
    /// Each device's last lineup, by DeviceID, for Settings' signal (step 9).
    private(set) var entries: [String: [HDHomeRunLineupEntry]] = [:]
    /// GuideNumber order, numbered from `firstNumber` (L2).
    private(set) var channels: [Channel] = []
    /// Protected (DRM) channels left out of `channels` (L5).
    private(set) var leftOut = 0
    private(set) var status: IPTVLibrary.Status = .idle
    /// The last lineup read.
    private(set) var lastFetch: Date?
    /// The last discovery that finished.
    private(set) var lastSearch: Date?
    /// A discovery is running.
    private(set) var isSearching = false
    /// `settings.json` `antennaEnabled` (L14). Off: no discovery or lineup, and everything found is forgotten.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue, !isEnabled else { return }
            reset()
        }
    }
    /// The first antenna channel's `number`: the playlist's count + 1 (L2). Set by the library.
    var firstNumber = 1 {
        didSet {
            guard firstNumber != oldValue else { return }
            rebuildChannels()
        }
    }

    /// A discovery has finished since MMTVL started (or since the antenna was turned on).
    var hasSearched: Bool { lastSearch != nil }

    /// L18: the last channel scan. A finished, stopped or failed one stays until the next scan starts (here or, seen
    /// when Settings → Antenna opens, elsewhere) or the antenna is turned off (step 9b QA major). nil: none since then.
    private(set) var scan: AntennaScanState?
    /// L18: per DeviceID, whether its last `lineup_status.json` allowed a scan (`ScanPossible` 1 and a valid current
    /// source). Missing: not read yet.
    private(set) var scanPossible: [String: Bool] = [:]
    /// L18: Settings → Antenna is on screen (set by the library): a running scan is polled every second. Becoming
    /// visible mid-scan polls at once (step 9b QA minor 3), not after the rest of a 5 s wait.
    var isScanPageVisible = false {
        didSet {
            guard isScanPageVisible, !oldValue else { return }
            pollWait?.cancel()
        }
    }
    /// L18: some tuner may start a scan (none read yet counts as yes).
    var canScan: Bool { devices.contains { scanPossible[$0.id] ?? true } }
    var isScanning: Bool {
        if case .running = scan { return true }
        return false
    }
    /// Step 10 (security N1): whether `deviceID`'s tuner is in the running scan, so its channels get no stream. Only
    /// that tuner: a scan on another one, or a LAN host that always reports a scan, blocks no other tuner's channels.
    /// Before the start POSTs have answered, every tuner the scan may start counts (all of them until their
    /// `lineup_status.json` is read).
    func isScanning(deviceID: String) -> Bool {
        guard isScanning else { return false }
        return scanningDeviceIDs.contains(deviceID) || startingDeviceIDs.contains(deviceID)
    }
    /// L18: called after the scan's state changed; `lineupRead` after the lineup was read again at its end (or after
    /// a stop). Set by the library (rematch, My Teams, Settings).
    @ObservationIgnored var onScanChange: ((_ lineupRead: Bool) async -> Void)?
    /// L18: the scan's start, polling and end (or the stop); tests await it.
    @ObservationIgnored private(set) var scanTask: Task<Void, Never>?

    @ObservationIgnored private let find: Find
    /// Also asks the tuners why a stream failed (M7j L9, `IPTVLibrary.diagnose`).
    @ObservationIgnored let http: HDHomeRunHTTP
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var searchTask: Task<[HDHomeRunDevice], Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Bumped when the antenna is turned off: work started before then drops its results.
    @ObservationIgnored private var generation = 0
    /// L18: bumped by every scan start, stop and reset: a scan task whose token is old drops its results.
    @ObservationIgnored private var scanToken = 0
    /// L18: the tuners the running scan is on (started by MMTVL or elsewhere); Stop Scan aborts these.
    @ObservationIgnored private var scanningDeviceIDs: [String] = []
    /// Step 10 (security N1): the tuners a scan start may still reach (its `lineup_status.json` reads, then its
    /// start POSTs); counted as scanning by `isScanning(deviceID:)`, never aborted by Stop for being in it.
    @ObservationIgnored private var startingDeviceIDs: Set<String> = []
    /// Step 10 (security N2, pre-build QA minor 2): the shared-numbers count last logged (0: none, or not yet).
    @ObservationIgnored private(set) var loggedSharedNumbers = 0
    /// L18: each tuner's last `Found` in this scan (kept when it finishes before the others, QA minor 2).
    @ObservationIgnored private var scanFound: [String: Int] = [:]
    /// L18: the wait before the next poll; cancelled to poll at once.
    @ObservationIgnored private var pollWait: Task<Void, Never>?
    /// L18 (security L1): the `scan=start` POSTs in flight, and the tuners that accepted; Stop waits for them.
    @ObservationIgnored private var startPostsTask: Task<[String], Never>?
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    /// L18 (security L4): the 15-minute limit counts elapsed time on this clock, never the wall clock.
    @ObservationIgnored private let scanClock: () -> ContinuousClock.Instant
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Antenna")

    /// `http` posts nothing unless it was made with `HDHomeRunHTTP.livePost` (only `AppDelegate` does, L18).
    init(find: @escaping Find = { await HDHomeRunDiscovery.find() }, http: HDHomeRunHTTP = HDHomeRunHTTP(),
         now: @escaping () -> Date = Date.init,
         sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         scanClock: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.find = find
        self.http = http
        self.now = now
        self.sleep = sleep
        self.scanClock = scanClock
    }

    /// The lineup of the known tuners (a search first when none is known). When a lineup can't be read the tuners
    /// are searched for once more (L4: an address may have changed) and asked again; if that fails too, the last
    /// channels are kept and `status` is `.failed`. A refresh asked for while one runs waits for it.
    func refresh() async {
        guard isEnabled else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    /// `refresh()` when the lineup is older than `staleness` (or, M7n L2, with no tuner known, when the last search
    /// is older than `searchRetryStaleness`).
    func refreshIfStale() async {
        guard isEnabled else { return }
        let (stamp, limit) = devices.isEmpty ? (lastSearch, Self.searchRetryStaleness) : (lastFetch, Self.staleness)
        guard stamp.map({ now().timeIntervalSince($0) > limit }) ?? true else { return }
        await refresh()
    }

    /// Searches for tuners, then reads their lineups (launch, wake, Find Tuners). Returns how many tuners the
    /// search found. When it finds none, the tuners known before (if any) are asked for their lineups instead, so
    /// a slow network after wake doesn't lose the channels.
    @discardableResult
    func discover() async -> Int {
        guard isEnabled else { return 0 }
        let generation = generation
        let found = await search()
        guard isCurrent(generation) else { return 0 }
        let candidates = found.isEmpty ? devices : found
        guard !candidates.isEmpty else {
            if !channels.isEmpty || !entries.isEmpty {
                entries = [:]
                rebuildChannels()
            }
            status = .idle
            return 0
        }
        if !(await readLineups(of: candidates, generation: generation)), isCurrent(generation) {
            fail(found.isEmpty ? "no tuner answered" : "the tuner didn't send its lineup")
        }
        return found.count
    }

    /// Step 9 (QA 4): what Find Tuners reports after `discover()` returned `found`. A search that found nothing keeps
    /// the known tuners (L5): they count as found when their lineups were read, else none answered.
    func findOutcome(found: Int) -> AntennaFindOutcome {
        if found > 0 { return .found(found) }
        guard !devices.isEmpty else { return .noneFound }
        if case .loaded = status { return .found(devices.count) }
        return .noneAnswered
    }

    // MARK: - Channel scan (L18)

    /// Starts a scan on every tuner whose fresh `lineup_status.json` allows one (`ScanPossible` 1, its current source
    /// valid); a tuner already scanning is joined. Polls until every tuner is done (or `scanTimeLimit`), then reads
    /// the lineup again and counts what changed. The caller stops MMTVL's own antenna streams first.
    func startScan() {
        guard isEnabled, !devices.isEmpty, !isScanning else { return }
        scanToken += 1
        let token = scanToken
        scan = .running(progress: 0, found: 0)
        scanFound = [:]
        startingDeviceIDs = Set(devices.map(\.id))
        scanTask = Task { await performScan(token: token) }
    }

    /// Stop Scan: `scan=abort` to the scanning tuners (no confirm), then the lineup again. Start POSTs still in
    /// flight finish first (security L1), so an abort never reaches a tuner before its start; a tuner that accepted
    /// one is aborted too.
    func stopScan() {
        guard isScanning else { return }
        scanToken += 1
        let token = scanToken
        let generation = generation
        scanTask?.cancel()
        let pending = startPostsTask
        startPostsTask = nil
        let known = scanningDeviceIDs
        scanningDeviceIDs = []
        startingDeviceIDs = []
        scanFound = [:]
        scan = .stopped
        let http = http
        scanTask = Task {
            var ids = known
            if let pending {
                for id in await pending.value where !ids.contains(id) { ids.append(id) }
            }
            for device in devices.filter({ ids.contains($0.id) }) {
                let code = await http.abortScan(on: device)
                if code != 200 { logger.notice("Antenna scan stop: \(Self.answerText(code), privacy: .public)") }
            }
            logger.notice("Antenna scan stopped")
            await refreshAfterScan()
            guard isScanCurrent(token, generation) else { return }
            await onScanChange?(true)
        }
    }

    /// Settings → Antenna opened (L18): each tuner's `lineup_status.json` (no tuner taken) says whether it can scan,
    /// and a scan started elsewhere (the HDHomeRun app) shows as running (replacing the last scan's line) and can be
    /// stopped. The last scan's line otherwise stays (QA major).
    func checkScan() async {
        guard isEnabled, !isScanning, !devices.isEmpty else { return }
        let token = scanToken
        let generation = generation
        let devices = devices
        let statuses = await readLineupStatuses(of: devices)
        // A scan started meanwhile reads the statuses itself.
        guard isScanCurrent(token, generation) else { return }
        recordScanPossible(devices: devices, statuses: statuses)
        let scanning = zip(devices, statuses).filter { $0.1?.scanInProgress == true }
        if !scanning.isEmpty {
            scanToken += 1
            let token = scanToken
            scanningDeviceIDs = scanning.map(\.0.id)
            scanFound = Dictionary(scanning.map { ($0.0.id, $0.1?.found ?? 0) }, uniquingKeysWith: { first, _ in first })
            scan = .running(progress: scanning.compactMap { $0.1?.progress }.min() ?? 0,
                            found: Self.total(scanFound.values))
            logger.notice("Antenna scan running, started elsewhere (\(Self.tunerCount(scanning.count), privacy: .public))")
            let before = Set(channels.map(\.id))
            let startedAt = scanClock()
            scanTask = Task { await pollScan(token: token, generation: generation, before: before, startedAt: startedAt) }
        }
        await onScanChange?(false)
    }

    private func performScan(token: Int) async {
        let generation = generation
        let before = Set(channels.map(\.id))
        let devices = devices
        let statuses = await readLineupStatuses(of: devices)
        guard isScanCurrent(token, generation) else { return }
        recordScanPossible(devices: devices, statuses: statuses)
        var joined: [String] = []
        var toStart: [(HDHomeRunDevice, HDHomeRunLineupStatus)] = []
        for (device, status) in zip(devices, statuses) {
            guard let status else { continue }
            if status.scanInProgress {
                joined.append(device.id)
                if let found = status.found { scanFound[device.id] = found }
            } else if scanPossible[device.id] == true {
                toStart.append((device, status))
            }
        }
        startingDeviceIDs = Set(toStart.map(\.0.id))
        guard !joined.isEmpty || !toStart.isEmpty else {
            logger.notice("Antenna scan: no tuner can scan now")
            scan = nil
            await onScanChange?(false)
            return
        }
        scanningDeviceIDs = joined
        let http = http
        // Not cancelled by Stop: Stop waits for it, then aborts the tuners that accepted. A Stop meanwhile sends no
        // further start.
        let posts = Task { () -> [String] in
            var started: [String] = []
            for (device, status) in toStart {
                guard isScanCurrent(token, generation) else { break }
                let code = await http.startScan(on: device, status: status)
                if code == 200 {
                    started.append(device.id)
                } else {
                    logger.notice("Antenna scan failed: \(Self.answerText(code), privacy: .public)")
                }
            }
            return started
        }
        startPostsTask = posts
        let started = await posts.value
        if startPostsTask == posts { startPostsTask = nil }
        guard isScanCurrent(token, generation) else { return }
        scanningDeviceIDs = joined + started
        startingDeviceIDs = []
        guard !scanningDeviceIDs.isEmpty else {
            scan = .failed
            await onScanChange?(false)
            return
        }
        logger.notice("Antenna scan started (\(Self.tunerCount(self.scanningDeviceIDs.count), privacy: .public))")
        await onScanChange?(false)
        await pollScan(token: token, generation: generation, before: before, startedAt: scanClock())
    }

    /// Every second while Settings → Antenna shows, else every 5 s, until no tuner reports `ScanInProgress` (a tuner
    /// that doesn't answer counts as still scanning) or `scanTimeLimit` has passed on `scanClock`; then `finishScan`.
    /// A tuner that finished leaves `scanningDeviceIDs` (Stop doesn't abort it) and its `Found` still counts.
    private func pollScan(token: Int, generation: Int, before: Set<Channel.ID>,
                          startedAt: ContinuousClock.Instant) async {
        while true {
            await waitForNextPoll()
            guard isScanCurrent(token, generation) else { return }
            let ids = scanningDeviceIDs
            let scanning = devices.filter { ids.contains($0.id) }
            let statuses = await readLineupStatuses(of: scanning)
            guard isScanCurrent(token, generation) else { return }
            var progress: [Int] = []
            var stillScanning: [String] = []
            for (device, status) in zip(scanning, statuses) {
                guard let status else {
                    stillScanning.append(device.id)
                    continue
                }
                if let found = status.found { scanFound[device.id] = found }
                if status.scanInProgress {
                    stillScanning.append(device.id)
                    progress.append(status.progress ?? 0)
                }
            }
            scanningDeviceIDs = stillScanning
            guard !stillScanning.isEmpty else { break }
            if scanClock() - startedAt >= .seconds(Self.scanTimeLimit) {
                logger.notice("Antenna scan still running after 15 minutes; no longer watched")
                break
            }
            let state = AntennaScanState.running(progress: progress.min() ?? 0, found: Self.total(scanFound.values))
            if state != scan {
                scan = state
                await onScanChange?(false)
                guard isScanCurrent(token, generation) else { return }
            }
        }
        await finishScan(token: token, generation: generation, before: before)
    }

    /// The wait between polls, at the page's pace; `isScanPageVisible` turning true ends it early.
    private func waitForNextPoll() async {
        let interval = isScanPageVisible ? Self.scanPollFast : Self.scanPollSlow
        let sleep = sleep
        let wait = Task { await sleep(interval) }
        pollWait = wait
        await withTaskCancellationHandler { await wait.value } onCancel: { wait.cancel() }
        if pollWait == wait { pollWait = nil }
    }

    /// Step 10 (security N2, pre-build QA minor 2): the notice for `count` GuideNumbers on more than one tuner, only
    /// when it differs from the count last logged (`previous`); nil when it doesn't. Back to 0: one "no longer" line.
    nonisolated static func sharedNumbersNotice(_ count: Int, previous: Int) -> String? {
        guard count != previous else { return nil }
        return count > 0 ? "Channel numbers on more than one tuner: \(count) (the first tuner's are used)"
            : "Channel numbers on more than one tuner: none now"
    }

    /// Security M1: a sum that saturates instead of trapping.
    nonisolated static func total(_ values: some Sequence<Int>) -> Int {
        values.reduce(0) { sum, value in
            let (result, overflow) = sum.addingReportingOverflow(value)
            return overflow ? .max : result
        }
    }

    /// The lineup again (L5), and the counts against `before`.
    private func finishScan(token: Int, generation: Int, before: Set<Channel.ID>) async {
        scanningDeviceIDs = []
        await refreshAfterScan()
        guard isScanCurrent(token, generation) else { return }
        scanFound = [:]
        if case .failed = status {
            logger.notice("Antenna scan failed: the lineup didn't load after it")
            scan = .failed
        } else {
            let after = Set(channels.map(\.id))
            let added = after.subtracting(before).count
            let removed = before.subtracting(after).count
            logger.notice("Antenna scan finished: \(self.channels.count, privacy: .public) channels (\(added, privacy: .public) new, \(removed, privacy: .public) gone)")
            scan = .finished(found: channels.count, added: added, removed: removed)
        }
        await onScanChange?(true)
    }

    /// A lineup read that starts after the scan ended: one already running may have started before.
    private func refreshAfterScan() async {
        if let refreshTask { await refreshTask.value }
        await refresh()
    }

    /// Each device's `lineup_status.json`, in order (nil: no answer).
    private func readLineupStatuses(of devices: [HDHomeRunDevice]) async -> [HDHomeRunLineupStatus?] {
        let http = http
        return await withTaskGroup(of: (Int, HDHomeRunLineupStatus?).self) { group in
            for (index, device) in devices.enumerated() {
                group.addTask { (index, await http.lineupStatus(of: device)) }
            }
            var result = [HDHomeRunLineupStatus?](repeating: nil, count: devices.count)
            for await (index, status) in group { result[index] = status }
            return result
        }
    }

    private func recordScanPossible(devices: [HDHomeRunDevice], statuses: [HDHomeRunLineupStatus?]) {
        for (device, status) in zip(devices, statuses) {
            // A tuner that is scanning says nothing about the next scan: unknown (counts as yes) until it's idle.
            if status?.scanInProgress == true {
                scanPossible[device.id] = nil
                continue
            }
            scanPossible[device.id] = status.map {
                $0.scanPossible == true && HDHomeRunScan.startURL(device: device, status: $0) != nil
            } ?? false
        }
    }

    private func isScanCurrent(_ token: Int, _ generation: Int) -> Bool {
        token == scanToken && isCurrent(generation)
    }

    /// "HTTP 403", or "no answer"; never an address.
    private static func answerText(_ code: Int?) -> String {
        code.map { "HTTP \($0)" } ?? "no answer"
    }

    private static func tunerCount(_ count: Int) -> String {
        count == 1 ? "1 tuner" : "\(count) tuners"
    }

    // MARK: - Private

    private func performRefresh() async {
        let generation = generation
        guard !devices.isEmpty else {
            await discover()
            return
        }
        if await readLineups(of: devices, generation: generation) { return }
        guard isCurrent(generation) else { return }
        // L4: once when a lineup fetch fails.
        let found = await search()
        guard isCurrent(generation) else { return }
        guard !found.isEmpty else {
            fail("no tuner answered")
            return
        }
        if !(await readLineups(of: found, generation: generation)), isCurrent(generation) {
            fail("the tuner didn't send its lineup")
        }
    }

    /// One discovery at a time: a search asked for while one runs gets its result.
    private func search() async -> [HDHomeRunDevice] {
        if let searchTask { return await searchTask.value }
        isSearching = true
        let task = Task { await find() }
        searchTask = task
        let found = await task.value
        if searchTask == task {
            searchTask = nil
            isSearching = false
        }
        lastSearch = now()
        return found
    }

    /// Reads every device's lineup; true when each one answered (then `devices`, `entries` and `channels` are
    /// theirs). False changes nothing.
    private func readLineups(of devices: [HDHomeRunDevice], generation: Int) async -> Bool {
        if case .loaded = status {} else { status = .loading }
        let http = http
        let lineups = await withTaskGroup(of: (Int, [HDHomeRunLineupEntry]?).self) { group in
            for (index, device) in devices.enumerated() {
                group.addTask { (index, await http.lineup(of: device)) }
            }
            var result = [[HDHomeRunLineupEntry]?](repeating: nil, count: devices.count)
            for await (index, entries) in group { result[index] = entries }
            return result
        }
        guard isCurrent(generation), lineups.allSatisfy({ $0 != nil }) else { return false }
        self.devices = devices
        entries = Dictionary(zip(devices.map(\.id), lineups.map { $0 ?? [] }), uniquingKeysWith: { first, _ in first })
        rebuildChannels()
        lastFetch = now()
        status = .loaded(now())
        logger.notice("Loaded \(self.channels.count, privacy: .public) antenna channels (\(self.leftOut, privacy: .public) left out)")
        return true
    }

    private func rebuildChannels() {
        let lineups = devices.compactMap { device in entries[device.id].map { (device, $0) } }
        let result = AntennaLineup.channels(devices: lineups, firstNumber: firstNumber)
        // Step 10 (security N2): two tuners with the same channel number; counts only, logged when the count
        // changes (pre-build QA minor 2), not at every rebuild.
        if let line = Self.sharedNumbersNotice(result.sharedNumbers, previous: loggedSharedNumbers) {
            logger.notice("\(line, privacy: .public)")
        }
        loggedSharedNumbers = result.sharedNumbers
        if result.channels != channels { channels = result.channels }
        if result.leftOut != leftOut { leftOut = result.leftOut }
    }

    /// Keeps the last channels (L5).
    private func fail(_ reason: String) {
        logger.notice("Antenna lineup failed: \(reason, privacy: .public)")
        status = .failed(Self.unreachableMessage)
    }

    private func isCurrent(_ generation: Int) -> Bool {
        isEnabled && generation == self.generation
    }

    private func reset() {
        generation += 1
        refreshTask = nil
        // L18: a scan running on the tuner goes on; MMTVL stops watching it.
        scanToken += 1
        scanTask?.cancel()
        scanTask = nil
        pollWait?.cancel()
        pollWait = nil
        startPostsTask = nil
        scan = nil
        scanPossible = [:]
        scanningDeviceIDs = []
        startingDeviceIDs = []
        scanFound = [:]
        loggedSharedNumbers = 0
        devices = []
        entries = [:]
        channels = []
        leftOut = 0
        status = .idle
        lastFetch = nil
        lastSearch = nil
    }
}
