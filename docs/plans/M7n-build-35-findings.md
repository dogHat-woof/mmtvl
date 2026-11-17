# M7n — Build 35 findings: antenna after a restart, a looping guide, smoother guide scrolling

| | |
|---|---|
| Status | In progress |
| Depends on | M7j |
| Master plan decisions used | D23, D40, D52 |
| Planned | 2026-11-15 |

## Goal

The user's findings from build 35 on the MM (2026-11-15):

1. **After a restart of the MM, the Antenna group and the antenna favorites are missing** until Settings → Live TV →
   Antenna → Find Tuners. After this milestone, MMTVL finds the tuner on its own within seconds of the network coming
   up, and the playlist recovers the same way.
2. **The guide's channel list loops**: Down on the last row of Favorites (or any group) goes to the first row, Up on
   the first row goes to the last.
3. **The guide scrolls smoothly**: rows slide when the list moves, and the focus highlight moves with an animation,
   instead of the rows' content being swapped in place.
4. **Live TV stutters** (user, 2026-11-15, after the first three were planned): frame drops or hitches while watching,
   seen on playlist channels on 2026-11-14 and on an antenna channel on 2026-11-15, so not only a network problem.
   This milestone measures it on the MM (step 3), then the user picks the fix (step 4).

## Out of scope

- The group list (Search, Favorites, My Teams, …) keeps its ends: Up from the first group still goes to Search.
- Multiview's picker guide uses the same `GuideModel`/`GuideView`, so it gets 2 and 3 too; nothing else changes there.
- Live TV menus (`LiveMenu`) and Settings lists don't loop.

## Research & findings

### Finding 1: the antenna after a restart

- **The MM's log (read over SSH 2026-11-15)**: the MM booted at 19:58:02. MMTVL's launch refresh ran at 19:58:17
  before the network was up:
  `Antenna discovery: no LAN interface to search on` and `Playlist from iptv.example failed: The Internet connection appears
  to be offline.` The playlist came back 8 s later (`Loaded 191 channels`, 19:58:25), the antenna not until the user's
  Find Tuners at 20:01:10 (`Found 1 tuners (2 tuner slots)`, `Loaded 185 antenna channels`).
- **Why the playlist came back**: opening Live TV (or the home preview) calls `refreshPlaylistIfStale()`
  (`IPTV/LiveTVModel.swift:198-205`), which fetches whenever `playlistChannels` is empty
  (`IPTV/IPTVLibrary.swift:196-200`). So it recovered only because the user opened Live TV; with no Live TV visit the
  next try is the 15-minute timer (`App/AppDelegate.swift:395`).
- **Why the antenna didn't**: `refreshAtLaunch()` (`IPTV/IPTVLibrary+Antenna.swift:23-29`) searches once.
  `HDHomeRunDiscovery.find()` returns `[]` at once when no interface is searchable
  (`IPTV/Antenna/HDHomeRunDiscovery.swift:63-67`), `discover()` sets `lastSearch` (`AntennaSource.swift:331`), and
  `refreshIfStale()` with no tuner known waits until `lastSearch` is older than `staleness`, 10 minutes
  (`AntennaSource.swift:171-176`, `staleness = IPTVLibrary.playlistStaleness`). Opening Live TV after the first search
  calls `refreshAntennaIfStale()` (`LiveTVModel.swift:203`), which does nothing for those 10 minutes. The next real
  try is the first 15-minute tick after them.
- **Favorites**: `iptv-channels.json` kept the antenna favorites (ids not in the lineup are kept and ignored,
  CLAUDE.md); the guide and Home only list channels that exist, so they came back with the lineup. Nothing to fix there.
- Wake (`AppDelegate.swift:1165`, `refreshAfterWake()`) has the same single try; a slow network after wake is the same
  case.
- `CastReceiver` already restarts on a network change with an `NWPathMonitor` (`Cast/CastReceiver.swift:109-123`). A
  retry schedule (L1) covers the restart without a second monitor.

### Findings 2 and 3: the guide list

- `GuideModel.moveRow(by:)` clamps (`IPTV/Guide/GuideModel.swift:366-371`); Up/Down in the grid, the channel cell and
  My Teams' action rows all go through it (`handleGrid`, `handleChannel`, `handleActionRow`). Channel Up/Down page by
  `visibleRows` (6) through the same function.
- `keepRowVisible()` (`GuideModel.swift:378-384`) keeps `firstVisibleRow` so the focused row is on screen.
- `GuideView.rows(now:)` (`IPTV/Guide/GuideView.swift:181-190`) draws only rows `first..<first+6` in a `VStack`, keyed
  by **index** (`id: \.self`). A scroll by one row therefore re-renders all six slots with new content: nothing
  slides, which is the jump the user sees. The focus fill is a per-row background chosen by `row == model.row`, so it
  also jumps. `nowLine(now:)` (`GuideView.swift:383-400`) draws its per-row segments in the same index window.
- Zapping in the player already loops (`LiveTVModel.swift:1524-1533`, `% list.count`), so a looping guide matches it.
- Settings' sliding highlight uses `Theme.focusAnimation` (`spring(response: 0.3, dampingFraction: 0.8)`,
  `Theme.swift:517`; `Settings/SettingsColumnView.swift:169`).
- Existing tests that hold Down/Up past an end and expect clamping: `MMTVLTests/GuideModelTests.swift` around lines
  96-106 and 160-170 (to be read; they change to expect the loop).

### Finding 4: Live TV stutter (measured on the MM, 2026-11-15 ~20:35, an antenna channel playing)

- **The MM**: macOS **26.6.2**, so Q29 (mpv 0.41's coreaudio failure on macOS 27) doesn't apply there; the MPV log
  has no audio fallback, only 2 `Audio device underrun detected` on 2026-11-14 22:36. The display runs
  **1920 × 1080 @ 60.00 Hz** (`system_profiler SPDisplaysDataType`).
- **What the streams are** (MPV log, `Format` and `Decoder` lines): playlist channels are 720p **59.94** fps (once
  60.34) with `Decoder videotoolbox`; antenna channels are 1080i shown as 1080p **29.97** fps (deinterlaced by
  `bwdif`, M7j) or 720p 59.94, and **every antenna start logs `Decoder no`**: MPEG-2 is decoded in software. mpv's
  default `hwdec-codecs` leaves out `mpeg2video` (mpv manual; **unverified** for the mpv 0.41 in MPVKit 1.0.0: check
  with `mpv --list-options` or by setting `hwdec-codecs=all` and reading the `Decoder` line).
- **CPU**: MMTVL at **80 %** (`top`), its **main thread 32.5 %** of a core (`ps -M`), about 9 minutes of CPU in the
  40 minutes since boot.
- **The main thread** (`sample MMTVL 3`, 1,492 samples): **906 (61 %) in `mpv_render_context_render`**, called from
  `CAOpenGLLayer` drawing in Core Animation's commit (`MPVVideoLayer.draw`, `IPTV/Player/MPVVideoView.swift:88`,
  `isAsynchronous = false`, M6 L7). Of those, **650 (44 % of the main thread) in `gl_tex_upload` → `glTexSubImage2D`
  → `AGX…Texture … convertTiles2D` → `agxsTwiddleAddressCommon`**: Apple's OpenGL-on-Metal driver re-tiles each
  software-decoded frame on the CPU, on the main thread. At ~60 frames a second that is roughly 7 ms per frame for the
  upload and ~10 ms for the whole render, out of a 16.7 ms frame; any other main-thread work (SwiftUI, a guide
  refresh, My Teams, network callbacks) then makes frames late. That is the antenna stutter's likely cause.
  VideoToolbox frames (the playlist) arrive as IOSurfaces and skip this upload.
- **Likely cause for playlist channels**: 59.94 fps content on a 60.00 Hz display repeats a frame about every
  16.7 s (29.97: every 33 s) under mpv's default `video-sync=audio`. mpv's render API gets no display timing from
  MMTVL (no `mpv_render_context_report_swap`, and `video-timing-offset=0`, `MPVOptions.swift:30`), so it can't
  smooth that. **Unverified** until step 3 measures it; main-thread hitches can hit them too.
- **Fix candidates** (for step 4, each **unverified** until step 3 tries it on the MM):
  - (a) `hwdec-codecs=all` (or adding `mpeg2video`): VideoToolbox decodes MPEG-2 (whether Apple silicon has MPEG-2
    hardware or VT's software decoder, the frames come back as IOSurfaces). Deinterlacing then needs a VideoToolbox
    deinterlacer (FFmpeg's `bwdif_videotoolbox`/`yadif_videotoolbox` filters, if MPVKit's FFmpeg 8.1 has them) or
    `hwdec=videotoolbox-copy` (copies back, keeps the upload).
  - (b) `opengl-pbo=yes`: uploads through pixel buffer objects, which may move the re-tiling off the calling thread.
  - (c) Render off the main thread: `CAOpenGLLayer.isAsynchronous = true`, or an own render thread / display link
    (reverses M6 L7, which keeps render calls on main; Multiview's 5 players make this the biggest change).
  - (d) `video-sync=display-resample` with `display-fps-override=60` (or the real refresh rate), and/or switching the
    TV mode to 59.94 Hz while Live TV plays (whether the MM offers a 59.94 Hz mode for this TV is **unverified**:
    `displayplacer list` or System Settings → Displays → Refresh Rate).
  - (e) **Move every libmpv property read off the main thread.** With the render API the main thread is mpv's render
    thread, and `render.h` ("Threading") says the render thread must not call other libmpv functions such as
    `mpv_get_property`: mpv's waits are "made non-fatal with timeouts; then playback quality will be degraded"
    ("mpv_render_context_render() not being called or stuck."). MMTVL reads properties on main every 0.5 s
    (`pollTimeshift` → `pollFormat`, `IPTV/Player/LivePlayer.swift:390-461`) and once per start (`:323`). QA of
    3a, 2026-11-15; that message wasn't in the MM's MPV log for the last 48 h (checked 2026-11-15), but MMTVL asks
    mpv for warnings only, so its level decides whether it would show (**unverified**).
- **(a)'s limits, from MPVKit 1.0.0's binaries** (QA of 3a): libavcodec has the `mpeg2_videotoolbox` hwaccel, but the
  LGPL libavfilter is built with `--disable-filters` plus only `bwdif`, `yadif`, `w3fdif`, `estdif` (and Vulkan
  ones): no `bwdif_videotoolbox`/`yadif_videotoolbox`. So hardware MPEG-2 decoding plus deinterlacing means
  `videotoolbox-copy` (a copy back and the same upload) or giving up deinterlacing for antenna 1080i.
- **3a's stats on the dev Mac** (windowed, macOS 27, a 59.94 fps playlist channel): about 11–13 draws and 46–49 mpv
  dropped frames a second, longest render 12–13 ms. Possibly the window was occluded (**unverified**); the MM will
  tell. The line gains update callbacks, callback-to-draw delay, the longest gap between draws and the rate after
  filters (3a follow-up) so 3b can tell main-thread delays from mpv signalling few frames.

## Design

- **L1 (finding 1): retry the launch and wake refresh while the network comes up.** `IPTVLibrary` gets
  `retryChannelsUntilLoaded()`, run after `refreshAtLaunch()` and `refreshAfterWake()` (as part of them). While either
  source is missing — the antenna is on and knows no tuner (`antenna.devices.isEmpty`), or there is a playlist and
  `playlistChannels` is empty — it waits and tries the missing ones again: after 5, 10, 20, 30 s, then every 60 s, for
  at most 5 minutes from the first try (`Theme`-like constants on `IPTVLibrary`, e.g. `launchRetryDelays`). The
  antenna is retried with `discoverAntenna()` (a search, then the lineup, then `antennaDidChange()`), the playlist with
  `refreshPlaylist()`. When a try brings channels, the guides follow (`refreshGuideIfStale()`,
  `refreshAntennaGuideIfDue()`), since a guide import is skipped while there are no channels. One retry loop at a time
  (a new launch/wake refresh cancels the old loop); turning the antenna off or removing the playlist ends its part.
  The waits use an injected sleep (as `AntennaSource` does) so tests don't wait. A user who has no tuner at all costs
  at most ~9 one-second searches in 5 minutes, then the normal cadence.
- **L2 (finding 1): no 10-minute hold on Live TV's search when no tuner is known.** `AntennaSource.refreshIfStale()`
  with `devices` empty uses a short staleness (`searchRetryStaleness`, 30 s) for `lastSearch`, so opening Live TV
  after a failed search searches again. With a tuner known, `staleness` (10 min) still applies to the lineup.
- **L3 (finding 2): the channel list loops.** `moveRow(by:)`: a single step (±1) past either end wraps
  (`(row + step) mod rows.count`). A page (Channel Up/Down, ±`visibleRows`) clamps to the first/last row, and only
  wraps when the focus is already on that end row (so paging never skips past the top or bottom unseen). Lists of one
  row don't move. `keepRowVisible()` then puts the wrapped row on screen (`firstVisibleRow` = 0 at the top,
  `rows.count - visibleRows` at the bottom).
- **L4 (finding 3): rows slide.** `GuideView` draws the rows in a clipped window `visibleRows × guideRowHeight` high.
  Inside it, each row of a buffered range (`first - visibleRows ..< first + 2 × visibleRows`, clamped to the rows) sits
  at `y = index × guideRowHeight`, keyed by the row's stable `Row.id` (not its index), and the stack is offset by
  `-firstVisibleRow × guideRowHeight`, animated with a new `Theme.guideScrollAnimation` (a spring like
  `focusAnimation`, response about 0.3, no bounce). The now line's per-row segments move with the rows (drawn inside
  the same scrolling stack, e.g. as an overlay per row), the header segment stays put. A jump of more than
  `visibleRows` rows (a loop from the bottom to the top, a group change, a search result) isn't animated (no fast
  scroll through blank rows): the view compares the old and new `firstVisibleRow` and uses no animation for big jumps.
  Changing the group isn't animated either (`row` and `firstVisibleRow` reset with new rows).
- **L5 (finding 3): the focus highlight animates** with `Theme.focusAnimation` when `model.row` or the focused cell
  changes, as in Settings (a fill crossfade or slide; the implementer picks the simplest that looks smooth, e.g.
  `.animation(Theme.focusAnimation, value: …)` on the row's fills). Reduce Motion: no slide; rows and the highlight
  move without animation (`@Environment(\.accessibilityReduceMotion)`), as the home screen's parallax does.

## Implementation steps

- [x] **1. The antenna and playlist retry after launch and wake (L1, L2)** `[implementer]`: files:
  `MMTVL/IPTV/IPTVLibrary+Antenna.swift`, `MMTVL/IPTV/IPTVLibrary.swift` (the retry constants and an injected sleep if
  the library has none), `MMTVL/IPTV/Antenna/AntennaSource.swift`, tests in `MMTVLTests/IPTVLibraryTests.swift` and the
  antenna source's tests.
  - Logs (category `IPTV`/`Antenna`, notice): "Retrying the antenna search in N s" style lines are not needed per try;
    log once when the loop starts ("Network not ready: retrying the channels for up to 5 min") and once when it ends
    with what came back (counts only, never an address or URL).
  - Done when: tests show (a) a launch whose first search finds nothing and whose second finds a tuner ends with the
    antenna channels merged, without waiting in real time; (b) a failed playlist at launch is fetched again; (c) the
    loop stops at 5 minutes, when both sources are there, and when the antenna is turned off; (d) `refreshIfStale` with
    no tuner searches again after 30 s, not before; with a tuner known the 10-minute lineup staleness is unchanged.
    Full suite passes.
- [x] **2. The guide loops and scrolls smoothly (L3, L4, L5)** `[implementer]`: files:
  `MMTVL/IPTV/Guide/GuideModel.swift`, `MMTVL/IPTV/Guide/GuideView.swift`, `MMTVL/DesignSystem/Theme.swift`,
  `MMTVLTests/GuideModelTests.swift`.
  - Done when: tests show Down on the last row goes to row 0 with `firstVisibleRow` 0, Up on row 0 goes to the last row
    with `firstVisibleRow = rows.count - 6`, a page clamps then wraps from the end row, a one-row list stays, My Teams'
    action rows loop too; the old clamping tests are updated. The guide on the dev Mac (`-windowed YES`, a playlist or
    the antenna) slides one row per press and the highlight animates; a loop jumps without a long scroll. Full suite
    passes.
- [ ] **3. Live TV stutter: measure (finding 4)** `[implementer]` then `[human]`:
  - 3a `[implementer]` (done), files: `MMTVL/IPTV/Player/LivePlayer.swift` (or a new `PlaybackStats.swift` beside it),
    `MMTVL/IPTV/Player/MPVOptions.swift`. While a player plays full screen, every 10 s log one notice line (category
    `MPV`): the player, `Decoder`, the stream fps, mpv's `frame-drop-count`, `decoder-frame-drop-count`,
    `vo-delayed-frame-count`, `mistimed-frame-count` (deltas since the last line), `avsync`, and the longest
    `mpv_render_context_render` call and the number over 12 ms in the period (timed in `MPVVideoLayer.draw`). Numbers
    only, never a URL. Plus **hidden `defaults` switches** for the experiments (Release builds too), read at launch and logged
    once when set (all off by default, removed or turned into the fix in step 4): `mpvHwdecCodecs` (string),
    `mpvOpenGLPBO` (bool), `mpvVideoSync` (string), `mpvDisplayFPS` (number). Done when: the lines show on the dev Mac
    during playback, and setting a switch changes the matching mpv option (tested). Full suite passes.
  - 3b `[human]`, on the MM with a test build (asks first): the same antenna channel and the same playlist channel,
    about 2 minutes each, for the baseline and then each switch (set over SSH with `defaults write
    dev.mmtvl.launcher <key> …`, relaunch MMTVL), the user noting whether it stutters. The orchestrator reads the
    stats lines (`log show … category == "MPV"`) and runs `sample MMTVL 3` for each.
  - Done when: the results are in a table here (setting, channel, drops and late frames per minute, longest render,
    main-thread render share, what the user saw), and the cause is named.
  - **3b results (2026-11-16, build 38, the MM at 1920 × 1080 @ 60.00 Hz; a playlist game, 720p 59.94 fps,
    VideoToolbox).** "33 ms repeats" = 10-s periods whose longest gap between draws is over 25 ms (one frame shown for
    two refreshes):

    | Setting | Periods | Drops | 33 ms repeats | Draws per 10 s | Longest render | avsync | What the user saw |
    |---|---|---|---|---|---|---|---|
    | None (baseline), 20:10–21:09 | 354 | 7 periods with 1–5 (see below) | 216 of 354 (one per ~16.7 s) | 599–600 | 4.1 ms | ≤ 6 ms | the stutter (finding 4) |
    | `mpvVideoSync display-resample` alone, 21:12–21:15 | 15 | 1 (after launch) | 9 of 15 | 599–600 | 3.9 ms | ≤ 3 ms | not judged; the stats show no change |
    | `display-resample` + `mpvDisplayFPS 60`, 21:15–21:18 | 17 | 1 (21:17:48, unexplained) | **0** | **600** | 5.6 ms | ≤ 7 ms | **smooth; audio in sync** (also on other channels) |
    | the same, an antenna channel (1080 29.97 fps MPEG-2, software decoding, deinterlaced to 59.94), 21:20 | 2 | 0 | 0 | 600 | 8.6 ms | ≤ 1 ms | (briefly) |

    - **Cause 1 (the regular hitch):** 59.94 fps video on a 60.00 Hz display with mpv's default `video-sync=audio`
      repeats a frame every 1 / (60 − 59.94) ≈ 16.7 s (216 seen, ~212 expected). `display-resample` alone does
      nothing: with the render API mpv isn't told the display's rate (the stats line shows no "display … fps"), so it
      falls back silently. With `display-fps-override` it shows one frame per refresh and resamples audio by 0.1 %.
    - **Cause 2 (drops after the playlist refresh):** each 15-minute refresh in the baseline (20:07:41, 20:22:42,
      21:03:43; the others were relaunches) was followed within 6 s by a period with 1–2 drops and a draw 30–50 ms
      late. Main-actor work in `IPTVLibrary.refreshPlaylist()` (M3U parse, `EPGMatcher.match` in `rematch()`, the
      lineup and My Teams updates) is suspected; a `sample MMTVL` across the 21:30 refresh is to confirm which.
    - **Unexplained:** isolated drops with nothing else logged (20:42:20, 20:43:00, 21:17:48; about 3 an hour, 1–3
      frames). And 21:18:38: 13 drops and a 211 ms gap in the 10 s before a channel change, while the user was
      navigating (what was pressed: asked).
- [ ] **4. Live TV stutter: the fix** `[implementer]`: chosen with the user from step 3's table (candidates in
  finding 4). Planned in detail here once step 3 is done.
  - 2026-11-16, chosen with the user ("do both"): (a) Live TV's mpv uses `video-sync=display-resample` with the
    display's real refresh rate as `display-fps-override` (from the screen the player is on, updated when the
    screen or its mode changes, so a 59.94 or 50 Hz TV mode is right too), replacing the hand-set switches;
    (b) the playlist refresh's heavy work leaves the main actor, per the sample (cause 2).
  - **4a. The display's rate** `[implementer]`, files: `MMTVL/IPTV/Player/MPVOptions.swift`,
    `MMTVL/IPTV/Player/LivePlayer.swift`, `MMTVL/IPTV/Player/MPVVideoView.swift` (or a new `DisplayRefresh.swift`
    beside them), `CLAUDE.md`, tests.
    - `MPVOptions.all` adds `("video-sync", "display-resample")` for every Live TV core (full screen, Multiview, the
      home preview).
    - A player whose video view is on a screen sets mpv's `display-fps-override` (a runtime property) to that screen's
      refresh rate: the mode's `CGDisplayCopyDisplayMode(id)?.refreshRate` (exact, e.g. 59.94), else
      `NSScreen.maximumFramesPerSecond`; a rate outside 1…240 or 0 sets nothing (mpv then keeps audio timing, as
      before). Set again when the view's window changes screen and on `NSApplication.didChangeScreenParameters`
      (a TV mode change). One notice line per change: "Display rate 60.00 Hz (player N)".
    - The step 3a switches (`mpvHwdecCodecs`, `mpvOpenGLPBO`, `mpvVideoSync`, `mpvDisplayFPS`) and `MPVSwitches` are
      removed, with their `CLAUDE.md` lines and tests; the stats line stays (it shows "display … fps").
    - Tests: the rate choice (mode rate, fallback, 0, out of range), `MPVOptions.all` has the video-sync option.
    - Done when: the build and the full suite pass; on the dev Mac (`-windowed YES`) a playing channel logs the
      display rate and its stats line shows "display … fps". On the MM (step 5): `defaults delete` the two switches,
      then 600 draws per 10 s and no 33 ms repeats with no switch set.
  - **4b. Refresh work off the main actor** `[implementer]`. Measured 2026-11-16 21:30 on the MM (`sample MMTVL 40 1`
    across a refresh, both switches on; 25 375 samples of ~1.6 ms; the main thread draws the video, in
    `CAOpenGLLayer` display during the CA commit, so main-thread work in one piece holds frames back). The refresh's
    10-s period had 7 drops, 4 delayed frames and an 84 ms gap. Main-thread samples outside drawing:
    - `IPTVLibrary.refreshPlaylist()` 79 (~125 ms): `M3UParser.parse` 34 (~55 ms; `parseAttributes` builds the
      attribute regex anew for every line, `Regex.init` 10 samples), `rematch()` 26 (`EPGMatcher.match` 10,
      `antennaMatches` 5, `updateTeams` → `TeamMatcher.networkChannelIDs` 14 and `programmesIfRead` 8).
    - The 5-minute My Teams timer (`AppDelegate.startIPTVRefreshTimer`, closure #2 → `updateTeams()`) 51 (~80 ms),
      almost all in `TeamMatcher.networkChannelIDs` (`teamsBySide`, case- and diacritic-insensitive `contains`). Both
      timers start at launch, so every third team update meets the 15-minute refresh.
    - Not the cause: `MPVPlayerController.pollTimeshift` 52 over the 40 s, in small pieces.
    Files: `MMTVL/IPTV/Sources/M3UParser.swift`, `MMTVL/IPTV/IPTVLibrary.swift`, `MMTVL/IPTV/IPTVLibrary+Antenna.swift`
    if needed, tests.
    - `M3UParser.parseAttributes`: the regex is built once (a static, or a hand scan with the same result).
    - `refreshPlaylist()`: `M3UParser.parse` and `ChannelList.make` run off the main actor (`Task.detached`, as
      `updateTeams` already does for the upcoming games); the URL check and assignments stay on the main actor after.
    - `rematch()`: `EPGMatcher.match` and `antennaMatches` run off the main actor; `epgMatches` is assigned on the
      main actor afterwards.
    - `updateTeams()`: `TeamMatcher.gameChannelIDs` and `networkChannelIDs` run off the main actor in the same detached
      task style; the existing guards after each await (picked teams or options changed: return) stay, and
      cancellation keeps the previous result, as the upcoming games do.
    - Behaviour and results unchanged; existing tests keep passing; a test that parsing gives the same entries as
      before for a playlist with many attributes (the regex change).
    - Done when: build and full suite pass; on the MM a refresh shows no drops in its stats period (step 5).
- [ ] **5. Build for the MM and the user's checks** `[human]` (after the user says yes to a test build):
  - Restart the MM with the antenna on and antenna favorites: Live TV shows Antenna and the favorites within about a
    minute of login, without Settings. `log show` (Antenna, IPTV) shows the retry line and `Found 1 tuners`.
  - In the guide, Favorites and another group: Down at the bottom goes to the top and Up at the top to the bottom;
    rows slide smoothly; Channel Up/Down page as before.
  - Live TV: the stutter from step 3 is gone on the same channels.

## Tests

- `MMTVLTests/IPTVLibraryTests.swift`: the launch retry (step 1, a–c).
- The antenna source's tests: `refreshIfStale` short staleness with no tuner (d).
- `MMTVLTests/GuideModelTests.swift`: the loop and paging (step 2).
- `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`

## Manual verification

Steps 3b and 5 above; the TV checks are the user's.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Rendering 18 rows instead of 6 slows the guide on the MM | Scrolling stutters | Buffer one page (`first - 1 ..< first + visibleRows + 1`) |
| The animation fights fast held-key repeats | Rows lag behind the focus | A shorter spring or `.easeOut(0.15)` |

## Deviations & questions

- 2026-11-15, step 2 (orchestrator): **a loop never slides**, in any list length (`GuideModel.wrapCount` in the
  view's scroll position); L4 only excluded jumps of more than `visibleRows`, so a loop in a 7–12-row list slid back.
- 2026-11-15, step 2 (orchestrator): `Theme.guideScrollAnimation` is `spring(response: 0.22, dampingFraction: 1)`,
  not L4's "about 0.3", so a held key lags less (the risk table's fallback, taken early).
- 2026-11-15, step 2: the highlight is a crossfade of each cell's fill and text colours, not a sliding highlight
  (L5 allowed either; `matchedGeometryEffect` misplaces fills inside per-row offsets, as `SettingsRowView` notes).
- 2026-11-15, step 2 (QA minor 3, not fixed): a repeated row id gets an index-based fallback key; not reachable today
  (channel ids are unique, `Channel.swift:58`).
- 2026-11-15, pre-build security review (steps 1–3a): no findings at medium or above. Low, not fixed: a playlist
  that loads with 0 channels is fetched again up to ~7 times in the 5-minute retry (bounded); if wanted, retry the
  playlist only after a network error. Note: the 3a switches ship in Release until step 4 removes them or makes one the fix.
- 2026-11-16, guide group list fix (411f1a9: the group panel scrolls to the focused group; it ran past the panel), at
  the user's request: pre-build security review of the diff since build 36 found nothing at medium or above.
- 2026-11-16, at the user's request after build 37 (the group list scrolled, but not smoothly): the group panel
  slides like the channel rows (L4, L5: a clipped window of `GuideModel.visibleGroupRows` = 7 rows moved by
  `firstVisibleGroupRow` with `guideScrollAnimation`, the highlight fades) instead of a ScrollView, and loops like L3:
  Down on the last group is Search, Up on Search the last group; a page (now 7 rows) stops at either end and wraps
  only from it, and reaches Search. A loop jumps (`groupWrapCount`).
  Pre-build security review of the diff since build 37: nothing at medium or above.
- 2026-11-16, step 4a (implementer, QA PASS): an unusable rate after a usable one resets `display-fps-override` to
  "0" (mpv's default, audio timing) rather than keeping the old screen's rate.
- 2026-11-16, step 4b (implementer, QA-deep PASS): the team matching moved off the main actor isn't cancelled with the
  update (the plan said "cancellation keeps the previous result"), because `aCancelledUpdateWithTheSamePicksStillSetsTheGroup`
  pins that a cancelled update with the same picks still sets the group. Added beyond the plan: `rematch()` runs one at a
  time (FIFO), and `matchGuides()` / `updateTeams()` match again on the main actor when their inputs changed during
  the detached match. The attribute regex is built once per `parse` (a static `Regex` isn't Sendable). QA-deep minors,
  not fixed: no test reaches the "changed meanwhile" fallbacks (needs a tests-only hook); Remove Live TV Source during a
  rematch can leave antenna refs to deleted guide rows until the next antenna guide download (pre-existing, no visible
  effect); two team updates can still finish out of order until the next 5-minute update (pre-existing). Possibly
  still on the main actor: `EPGStore.channelsBySource` / `programmes(refs:)` grouping, `updateChannels` and
  `updateLineup`; step 5's sample will show it.
- 2026-11-16, pre-build security review for build 39 (steps 4a, 4b): nothing at medium or above. Low, pre-existing,
  not fixed: no size limit on the playlist body (`IPTVNetwork.swift:20-25`), and the attribute regex may be quadratic
  on one huge `#EXTINF` line; since 4b that ties up a background thread instead of the main actor. If wanted: a size
  cap (`tooLarge`, as the antenna guide has) and a 1 MB-line timing test.
- 2026-11-15, finding 4 added at the user's request (Live TV stutter): steps 3–4 added, the build step is now 5.
