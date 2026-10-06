# M6 — Multiview

| | |
|---|---|
| Status | Done |
| Depends on | M4 (Live TV: player, guide, library), M5 (phone in-app volume, D25) |
| Master plan decisions used | D2, D3, D6, D7 (changed), D10, D14 (changed), D18, D22 (changed), D25 |
| Planned | 2026-10-06 |

## Goal

From the couch, with only the remote, Live TV can show **up to five channels at once**:

- **Getting there.** In the guide, Left from the programme airing now moves onto the **channel name**. Select there opens a **channel menu**: *Watch* and *Add to Multiview*. *Add to Multiview* opens Multiview with the channel that was playing plus the chosen one. Left again from the channel name opens the group list, as Left at now did in M4.
- **Layouts** (all 16:9 windows):
  - **1 + 4**: one large window on top and four small ones along the bottom, like the user's screenshot. The default.
  - **1 + 3**: a large window with three small ones in a column on the right.
  - **2 × 2**.
  - **1 + 2**: a large window with two small ones on the right.
  - **Side by Side**.
  - **Picture in Picture**: full screen with one small window in the bottom-right corner.
- **In Multiview:**
  - Arrows move a white highlight between windows. **Sound follows the highlight.** The others are muted.
  - The highlighted window briefly shows its channel and programme.
  - Play/Pause pauses the highlighted window. Rewind/Fast-forward skip it 30 s back/forward, each window with its own rewind buffer.
  - **Select** on a window opens its menu: *Full Screen*, *Make Main*, *Change Channel*, *Layout*, *Remove* (and *Retry* after a failure). Select on an empty window picks a channel for it.
  - *Change Channel* and empty windows open the **guide as a picker**: Select puts the channel in that window.
  - **Back** returns to full screen with the highlighted channel, without reconnecting it. Home leaves Live TV.
- The channel that was playing keeps playing (and keeps its rewind buffer) when Multiview opens. The highlighted one does the same when Multiview closes.
- Multiview remembers its windows and layout. If Live TV was left in Multiview, the Live TV tile reopens it. *Add to Multiview* later brings back the previous set plus the new channel.

## Out of scope

- **Guide management** moves to a new milestone, **M6b**: multiple EPG sources, manual channel ↔ EPG matching, favorites, hidden channels and groups. The channel menu built here is where M6b adds *Favorite*, *Hide* and *Match Guide*. (User choice, 2026-10-06.)
- **Catch-up.** The provider has none (master plan Q3). Dropped.
- New `RemoteCommand` cases (L16). No Settings rows: Multiview has no settings.
- Zapping channels with Up/Down inside a Multiview window (the arrows move the highlight). Use *Change Channel*.
- Mouse control of Multiview. Rounded video corners. Drag-to-rearrange. Reordering beyond *Make Main* and the picker's swap (L11).
- A Multiview entry from the full-screen player itself: all its buttons are taken (M4 L9). The guide is the way in.

## Research & findings

### libmpv with several cores (verified 2026-10-06 in the MPVKit 1.0.0 headers, `build/Build/Products/Debug/Libmpv.framework/Headers/mpv/`)

- **Several independent cores in one process are supported.** `render.h`, *Threading*: "only one of the mpv_render_* functions can be called at the same time (unless they belong to different mpv cores created by mpv_create())". Each core keeps its own render context (`render.h`: "at most 1 context can exist per mpv core").
  - So each Multiview window gets **its own `MPVHandle` + `MPVVideoLayer`**, the same pair M4 built. No new mpv code paths.
  - Each `CAOpenGLLayer` has its own CGL context, made current before its render calls. This is what M4's layer already does.
- **Render calls block by default.** `render.h`, `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME`: when video is timed to audio, `mpv_render_context_render()` "blocks … for up to the amount specified with the `video-timing-offset` global option" (default 0.050 s), to hit the frame's display time. `mpv_render_context_render`'s doc: "You can prevent this by setting the `video-timing-offset` global option to 0."
  - M4 renders on the main thread (`isAsynchronous = false`). One player blocking up to 50 ms per frame was fine. **Five players doing it on the main thread would starve the UI.**
  - So set **`video-timing-offset=0`** for every core (L7). mpv recommends exactly this. The cost is A/V sync "slightly off" (within a frame). Check it by eye in step 1.
- **Demuxer buffer sizes can change at runtime.** mpv v0.41.0 `demux/demux.c` ([source](https://github.com/mpv-player/mpv/blob/v0.41.0/demux/demux.c)):
  - The demuxer thread runs `m_config_cache_update` on every loop, then `update_opts()`.
  - `update_opts()` copies `max_bytes`/`max_bytes_bw` from the options and then calls `prune_old_packets(in)` "In case the cache was reduced in size".
  - So setting the **properties** `demuxer-max-back-bytes` / `demuxer-max-bytes` on a playing core takes effect at once, and shrinking prunes the buffer. L6 relies on this.
- **Already known from M4** (still true, don't re-research):
  - The render API (OpenGL) in a `CAOpenGLLayer`, `vo=libmpv`, `hwdec=videotoolbox` (D22).
  - Never `loadfile` before the layer's render context exists. `MPVPlayerController` keeps the URL as `pendingURL` until `onReady`.
  - Removing an `MPVVideoView` from the window releases its GL context; adding it back creates a new one. Leaving and re-entering Live TV three times was verified in M4 step 8.
  - `cache-end` advances in whole HLS segments. `LiveEdgeSmoother` handles the behind-live label.
  - The wakeup callback must not call mpv. One event thread per handle.

### Capacity

- **Streams.** The provider allows **5 concurrent streams** (master plan §3). 1 + 4 uses all five. The user accepted that (2026-10-06): a window that can't connect shows "Can't play this channel".
  - **Unverified:** how the provider counts streams, for example whether a stream just closed by a channel change still counts for a few seconds. Verify in step 7's manual checks: fill 1 + 4, then *Change Channel* on a window several times. If changes fail with HTTP 4xx right after a change but succeed on Retry, see *Risks*.
- **Bandwidth:** 5 × ~4 Mb/s ≈ 20 Mb/s (M4 measured 2.6–4.5 Mb/s per stream).
- **Memory.** M4's buffers (512 MiB back + 256 MiB forward) fill over about 17 minutes at the measured bitrate. Five players with those would reach about 3.8 GB.
  - Windows use **160 MiB back + 64 MiB forward** (L6): about 5.3 minutes of rewind at 4 Mb/s, which still meets D7's ≥ 5 minutes, and about 1.1 GB for five.
  - A window that goes full screen switches back to M4's sizes at runtime (see above).
- **Decoding:** VideoToolbox decode of 5 × 720p H.264 is far below the M4 media engine's capacity.
  - **Unverified:** that all five cores actually get `hwdec-current = videotoolbox`. Step 1 logs it per player, and step 5's manual check reads it.
- **Rendering.**
  - Five GL layers draw on the main thread at the streams' frame rate (25–60 fps).
  - The big 1 + 4 window is 1440 × 810 points: 2880 × 1620 pixels on the 4K HiDPI TV, upscaled from 720p by mpv's default scaler.
  - **Unverified** on the Mac mini: no dropped frames, and UI input stays responsive. Checked in step 5 (2 windows) and step 7 (5 windows).

### Layout geometry (computed; canvas 1920 × 1080 points)

Every window is 16:9. The **raw** rectangles below tile the canvas exactly. Drawn windows are inset by `Theme.multiviewGap / 2` (4 pt) on each side, so the gap between neighbors is 8 pt. Exception: Picture in Picture's main window isn't inset, so it is truly full screen.

| Layout | `rawValue` | Title | Capacity | Main slot | Raw slots (x, y, w, h), in slot order |
|---|---|---|---|---|---|
| 1 + 4 | `onePlusFour` | "1 + 4" | 5 | 0 | (240, 0, 1440, 810); (0, 810, 480, 270); (480, 810, 480, 270); (960, 810, 480, 270); (1440, 810, 480, 270) |
| 1 + 3 | `onePlusThree` | "1 + 3" | 4 | 0 | (0, 135, 1440, 810); (1440, 135, 480, 270); (1440, 405, 480, 270); (1440, 675, 480, 270) |
| 2 × 2 | `grid` | "2 × 2" | 4 | nil | (0, 0, 960, 540); (960, 0, 960, 540); (0, 540, 960, 540); (960, 540, 960, 540) |
| 1 + 2 | `onePlusTwo` | "1 + 2" | 3 | 0 | (0, 180, 1280, 720); (1280, 180, 640, 360); (1280, 540, 640, 360) |
| Side by Side | `sideBySide` | "Side by Side" | 2 | nil | (0, 270, 960, 540); (960, 270, 960, 540) |
| Picture in Picture | `pictureInPicture` | "Picture in Picture" | 2 | 0 | (0, 0, 1920, 1080); (1392, 762, 480, 270) |

- 1 + 4 matches the screenshot: the big window is centered with 240 pt of black on each side. The bottom row is 4 × 480 = 1920 wide, and 810 + 270 = 1080 tall.
- Picture in Picture's small window is 48 pt from the right and bottom edges.

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL/IPTV/Player/MPVOptions.swift` | changed | `video-timing-offset=0` (L7); `BufferProfile` and its sizes (L6). |
| `MMTVL/IPTV/Player/LivePlayer.swift` | changed | `LivePlayer` gains `setVolume`, `setAudible`, `setBufferProfile`. `MPVPlayerController` implements them, gets an `index` for logs, and logs `hwdec-current` once per load. |
| `MMTVL/IPTV/Multiview/MultiviewLayout.swift` | new | Pure: the six layouts, slot rectangles, main slot, directional neighbors (L3, L4). |
| `MMTVL/IPTV/Multiview/MultiviewModel.swift` | new | Pure: `MultiviewSnapshot` (persisted) and `MultiviewModel` (slots, focus, audio, entering, layout change, assign, make main, remove). |
| `MMTVL/IPTV/Multiview/MultiviewView.swift` | new | Overlay on the canvas: focus border, empty-window placeholders, channel chip, sound badge, per-window status. `MultiviewLayoutDiagram` for the layout menu. |
| `MMTVL/IPTV/LiveMenu.swift` | new | Pure: `LiveMenu` (title, items, focus) and `LiveMenuAction`. |
| `MMTVL/IPTV/LiveMenuView.swift` | new | The menu panel drawn over Live TV. |
| `MMTVL/IPTV/Guide/GuideModel.swift` | changed | `.channel` focus between the grid and the groups; `.channelMenu(id)` action (L8). |
| `MMTVL/IPTV/Guide/GuideView.swift` | changed | Focused channel cell; hints per focus and purpose; `isPicking`. |
| `MMTVL/IPTV/IPTVState.swift` | changed | `multiview: MultiviewSnapshot?` (L13), tolerant decoding. |
| `MMTVL/IPTV/IPTVLibrary.swift` | changed | `rememberMultiview(_:)`. |
| `MMTVL/IPTV/LiveTVModel.swift` | changed | Player pool, `.multiview` mode, guide purpose, menus, video placements, per-window failures, app volume. |
| `MMTVL/IPTV/LiveTVView.swift` | changed | Several video views placed from `model.videoPlacements`; multiview overlay; menu overlay. |
| `MMTVL/App/AppDelegate.swift` | changed | Passes a player factory; phone in-app volume goes through `LiveTVModel.setAppVolume`. |
| `MMTVL/DesignSystem/Theme.swift` | changed | `multiview*` and `liveMenu*` tokens. |
| `MMTVLTests/…` | new/changed | See *Tests*. |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | changed | Wrap-up (step 8). |

`MMTVL/IPTV/Multiview/` is picked up by the file-system-synchronized group. **Don't edit `project.pbxproj`.**

### Local decisions

- **L1. Scope** (user choice, 2026-10-06): Multiview only. Guide management is M6b. Catch-up is dropped (Q3).
- **L2. Up to 5 windows, one mpv player each, from a pool** (user choice for 5, 2026-10-06).
  - `LiveTVModel` keeps a pool of at most **5** `LivePlayer`s: the M4 player plus up to four created on demand by a factory.
  - Idle players are reused, never destroyed. That also settles M4 L7's "M6 will add teardown": none is needed.
  - An idle `MPVPlayerController` keeps its core but has no view in the window. Its GL context is released, and its demuxer is empty after `stop`.
- **L3. Layouts:** the six in *Layout geometry*.
  - The order in the layout menu is the table's order.
  - A new Multiview uses **1 + 4** (the user's priority) unless a remembered snapshot has a layout.
- **L4. Directional focus** uses the **raw** slot rectangles. From slot `s` (rect `a`) in direction `d`, a slot with rect `b` is a candidate when both hold:
  - **Its center lies that way:**
    - with `dx = b.midX − a.midX` and `dy = b.midY − a.midY`;
    - Right needs `dx > 0.5`, Left `dx < −0.5`, Down `dy > 0.5`, Up `dy < −0.5`.
  - **It overlaps `a` across the movement:**
    - for Left/Right, the y-ranges overlap by more than 0.5 pt (`min(a.maxY, b.maxY) − max(a.minY, b.minY) > 0.5`);
    - for Up/Down, the x-ranges overlap the same way.

  Choosing among candidates:
  - The smallest primary distance wins (`|dx|` for Left/Right, `|dy|` for Up/Down).
  - Ties go to the smaller secondary distance, then to the lower slot index.
  - No candidate: focus stays and nothing happens. No wrapping.
  - Empty slots are focusable.

  So in 1 + 4, Up from any bottom window reaches the big one, and Down from the big one lands on slot 2. Left/Right from the big one do nothing, because the bottom row doesn't overlap it vertically.
- **L5. Sound follows the highlight** (D14).
  - `audioSlot` is the highlighted slot when it holds a channel. Moving onto an empty slot keeps the previous `audioSlot`.
  - Every other window is muted with mpv `mute` (`setAudible(false)`). Audio keeps decoding, so switching is instant.
  - The phone's in-app volume (M5/D25) applies to every player in the pool. A player's effective mute is `phoneMuted || !audible`.
- **L6. Buffers.**
  - A player in a window uses the **`.tile`** profile: `demuxer-max-back-bytes=160MiB`, `demuxer-max-bytes=64MiB`.
  - A full-screen player uses **`.full`**: M4's 512 MiB / 256 MiB.
  - The profile is set as mpv **properties** at runtime, so a playing stream changes profile without reloading (see *Research*).
- **L7. `video-timing-offset=0`** for every core, single or Multiview. It keeps five render calls from blocking the main thread (see *Research*). If single-player A/V sync looks off, see *Risks*.
- **L8. Guide channel column and channel menu** (user choice, 2026-10-06). This changes M4 L9.
  - In the guide, **Left from the programme airing now** focuses the **channel cell** of that row (`GuideModel.Focus.channel`). Left again opens the groups.
  - On the channel cell:
    - Select returns `.channelMenu(id)`.
    - Up/Down move rows and stay on the channel cell.
    - Right goes back to the programmes.
    - Back closes the guide, as in the grid.
  - The watch guide's channel menu has **Watch** and **Add to Multiview**. The item reads **Show in Multiview** when the channel is already in the remembered snapshot.
  - M6b adds items to this menu.
- **L9. Multiview controls:**

  | Command | Multiview | Menu open (any mode) |
  |---|---|---|
  | Up/Down/Left/Right | move the highlight (L4); sound follows (L5); show the channel chip | Up/Down move; Left/Right nothing |
  | Select | filled window → window menu; empty → picker guide for it | choose the item |
  | Play/Pause | pause/resume the highlighted window + its timeshift label | nothing |
  | Rewind / Fast-forward | −30 s / +30 s on the highlighted window + its timeshift label | nothing |
  | Back | full screen with the highlighted window (L12) | close the menu |
  | Home | leave Live TV | leave Live TV |

- **L10. Menus** are one pure type, `LiveMenu`, drawn by one view. They are:
  - The channel menu (L8).
  - The **window menu**, in this order:
    - **Full Screen**.
    - **Make Main**: only when the layout has a main slot and the window isn't in it.
    - **Change Channel**.
    - **Retry**: only after the window's playback failed.
    - **Layout**, with the current layout's title as its value.
    - **Remove**.
  - The **layout menu**: one item per layout, each with a diagram, and value "Current" on the current one, which is focused first.
- **L11. The picker guide.** *Change Channel* and Select on an empty window open the guide with purpose `.pick(slot:)`.
  - Select on a programme or on a channel cell puts that channel in the slot:
    - If the slot is empty, a pool player plays it.
    - If the slot held another channel, that channel's player is released (stopped) and a pool player plays the new one.
    - **If the channel is already in another window, the two windows swap places.** Nothing reloads.
  - Back returns to Multiview unchanged. Play/Pause pauses the window shown in the preview.
  - The preview shows the **window with sound**. The other windows keep playing, invisible (L15).
- **L12. Entering and leaving Multiview.**
  - **Entering:** *Add to Multiview* on channel X runs `MultiviewModel.entering`:
    - It starts from the remembered snapshot, if any, keeping only channels still in the playlist.
    - It makes sure the channel playing now (if any) is in a window. That window **reuses the M4 player**: no reconnect, and the buffer is kept.
    - It then adds X.
    - The highlight and sound go to X. The other filled windows start playing on pool players.
  - **Leaving with Back or *Full Screen*:**
    - The target is the highlighted window if filled, else the window with sound, else the first filled window.
    - Its player becomes the full-screen player (profile `.full`, audible). The other players stop.
    - The banner shows. The snapshot is kept with `isActive = false`.
  - **Removing the last window:** the snapshot is cleared, every player stops, and the watch guide opens with nothing playing.
- **L13. The snapshot is remembered** in `iptv-state.json` as `multiview` (`layout`, `slots` as channel ids or null, `focusedSlot`, `isActive`).
  - It is saved on enter, assign, make main, remove, layout change, exit and `leave()`. It isn't saved on highlight moves, to avoid a file write per arrow press.
  - `open()` restores Multiview when the snapshot is active and at least one of its channels is still in the playlist. Otherwise it marks the snapshot inactive and resumes the last channel as in M4.
  - A snapshot that can't be decoded (for example an unknown layout) reads as nil. The rest of the state is kept.
- **L14. Per-window failures.** This is M4 L13 per player:
  - The player retries twice by itself.
  - Then `LiveTVModel` refreshes the playlist once for that window and replays the channel's possibly new URL on the same player.
  - If it fails again, the window shows "Can't play this channel", and its menu gets **Retry**.
  - A failure in the full-screen player keeps the M4 behavior.
- **L15. Video placement** is computed by the model (`videoPlacements`) and only drawn by the view. Each placement is a player, a canvas rect (nil = the whole window) and a visibility flag.

  | Mode | Placements |
  |---|---|
  | `.player` | the full-screen player, whole window, visible |
  | `.guide`, watch | the full-screen player at `Theme.guidePreviewRect`, visible |
  | `.guide`, pick | every window's player in slot order. The window with sound sits at `guidePreviewRect`, visible; the others sit at their slot rects, **invisible** (opacity 0, still in the view tree so their GL contexts survive) |
  | `.multiview` | every filled window's player at its slot rect, in slot order (Picture in Picture's small window is drawn after, so above, the main one), visible |
  | `.setupNeeded`, `.loading`, `.unavailable` | the full-screen player, whole window, invisible (as in M4) |

  - The view keys video views by player identity, so a window that moves (swap, Make Main, layout change, leaving Multiview) keeps its view and GL context. Frame changes aren't animated.
- **L16. No new `RemoteCommand`s and no Settings changes.** Everything uses the existing ten commands (M4 L10). M7's binding editor can revisit.

### Key types

```swift
// IPTV/Player/MPVOptions.swift (additions)
nonisolated enum BufferProfile: Sendable, Equatable {
    case full, tile
    /// Values for the mpv properties demuxer-max-back-bytes / demuxer-max-bytes.
    var backBytes: String { self == .full ? MPVOptions.backBuffer : MPVOptions.tileBackBuffer }
    var forwardBytes: String { self == .full ? MPVOptions.forwardBuffer : MPVOptions.tileForwardBuffer }
}
nonisolated enum MPVOptions {
    static let backBuffer = "512MiB"          // unchanged
    static let forwardBuffer = "256MiB"       // unchanged
    static let tileBackBuffer = "160MiB"      // L6
    static let tileForwardBuffer = "64MiB"
    static let all: [(name: String, value: String)] = [ /* M4's list, plus at the end: */ ("video-timing-offset", "0") ]
}
```

```swift
// IPTV/Player/LivePlayer.swift (protocol additions)
protocol LivePlayer: AnyObject {
    // … M4 members unchanged …
    /// The phone's in-app volume (M5 L9, D25). Applied to every pool player.
    func setVolume(_ level: Int, muted: Bool)
    /// Multiview sound (L5). Effective mute = muted (from setVolume) || !audible. Default true.
    func setAudible(_ audible: Bool)
    /// L6. Applied at once if the core exists, else when it's created.
    func setBufferProfile(_ profile: BufferProfile)
}
```

`MPVPlayerController` changes:

- `static var nextIndex = 1`; `let index: Int`; `init() { index = Self.nextIndex; Self.nextIndex += 1 }`. Logs say "player \(index)", e.g. "Loading a stream from <host> (player 2)".
- `@ObservationIgnored private var audible = true`, `private var bufferProfile = BufferProfile.full`.
- `applyVolume()` sets `volume` to `volumeLevel` and `mute` to `volumeMuted || !audible ? "yes" : "no"`.
  - `prepare()` calls `applyVolume()` after creating the core when `volumeLevel != 100 || volumeMuted || !audible`.
  - It calls `applyBufferProfile()` when `bufferProfile != .full`.
- `setAudible(_:)`: store; `applyVolume()`.
- `setBufferProfile(_:)`: store; if `mpv` exists, `setString("demuxer-max-back-bytes", p.backBytes)` and `setString("demuxer-max-bytes", p.forwardBytes)`.
- **hwdec log:** on `.playbackRestart`, if a flag `loggedDecoder` is false, log `mpv.string("hwdec-current") ?? "?"` at info ("Decoder videotoolbox (player 2)") and set the flag. `load(_:)` resets the flag.
- `setVolume` already exists; it now satisfies the protocol.

```swift
// IPTV/Multiview/MultiviewLayout.swift
nonisolated enum MultiviewLayout: String, Codable, CaseIterable, Sendable {
    case onePlusFour, onePlusThree, grid, onePlusTwo, sideBySide, pictureInPicture   // menu order (L3)
    enum Direction: Sendable { case up, down, left, right }

    var title: String              // "1 + 4", "1 + 3", "2 × 2", "1 + 2", "Side by Side", "Picture in Picture"
    var capacity: Int              // 5, 4, 4, 3, 2, 2
    var mainSlot: Int?             // 0 for onePlusFour/onePlusThree/onePlusTwo/pictureInPicture; nil for grid/sideBySide
    /// The table in Research, in slot order. Canvas points; they tile the 1920×1080 canvas.
    var rawSlots: [CGRect]
    /// rawSlots inset by Theme.multiviewGap / 2 on each side, except pictureInPicture's slot 0 (full canvas).
    var slots: [CGRect]
    /// L4. nil when no slot lies that way.
    func neighbor(of slot: Int, _ direction: Direction) -> Int?
}
```

- `slots` needs `Theme.multiviewGap`. Theme is MainActor-isolated by default, so use a `nonisolated static let gap: CGFloat = 8` **inside `MultiviewLayout`**. `Theme.multiviewGap` is defined as `MultiviewLayout.gap`, keeping one source.
- `MultiviewLayout.Direction` has `init?(_ command: RemoteCommand)` mapping up/down/left/right.

```swift
// IPTV/Multiview/MultiviewModel.swift
/// Persisted in iptv-state.json (L13). Channel ids only, never URLs.
nonisolated struct MultiviewSnapshot: Codable, Equatable, Sendable {
    var layout: MultiviewLayout
    var slots: [String?]          // Channel.ID per slot
    var focusedSlot: Int
    var isActive: Bool
}

nonisolated struct MultiviewModel: Equatable, Sendable {
    static let maxWindows = 5
    private(set) var layout: MultiviewLayout
    /// Always layout.capacity long.
    private(set) var slots: [Channel.ID?]
    private(set) var focusedSlot: Int
    /// L5: the filled slot whose sound plays; nil when every slot is empty.
    private(set) var audioSlot: Int?

    /// Pads with nil / truncates to capacity; clamps focusedSlot; audioSlot = focusedSlot if filled, else the first filled.
    init(layout: MultiviewLayout, slots: [Channel.ID?], focusedSlot: Int = 0)
    /// Ids not in `validIDs` become nil.
    init(snapshot: MultiviewSnapshot, validIDs: Set<Channel.ID>)
    func snapshot(isActive: Bool) -> MultiviewSnapshot

    var channelIDs: [Channel.ID]               // filled slots, in slot order
    var isEmpty: Bool
    var focusedChannelID: Channel.ID?
    var audioChannelID: Channel.ID?
    func slot(of id: Channel.ID) -> Int?

    /// L12. See the rules below.
    static func entering(snapshot: MultiviewSnapshot?, current: Channel.ID?, adding: Channel.ID,
                         validIDs: Set<Channel.ID>, defaultLayout: MultiviewLayout = .onePlusFour) -> MultiviewModel
    /// L4/L5. Returns false (and changes nothing) when there's no neighbor.
    mutating func moveFocus(_ direction: MultiviewLayout.Direction) -> Bool
    /// Returns the ids dropped because the new layout is smaller.
    mutating func setLayout(_ layout: MultiviewLayout) -> [Channel.ID]
    /// L11. Returns the id that was in `slot` and is now gone (nil when the slot was empty or for a swap).
    mutating func assign(_ id: Channel.ID, to slot: Int) -> Channel.ID?
    /// Swaps `slot` with layout.mainSlot (no-op without one); focus and sound go to the main slot.
    mutating func makeMain(_ slot: Int)
    /// Returns the removed id.
    mutating func remove(_ slot: Int) -> Channel.ID?
}
```

`MultiviewModel` rules:

- **`entering`:**
  1. `layout = snapshot?.layout ?? defaultLayout`. Slots are the snapshot's, with invalid ids set to nil and the list resized to capacity, or all nil when there's no snapshot.
  2. If `current != nil`, `current != adding`, and `current` isn't in a slot, **place** it.
  3. If `adding` isn't in a slot, **place** it, protecting `current`.
  4. `focusedSlot = slot(of: adding)`; `audioSlot = focusedSlot`.
  - **Place** puts the id in the first nil slot. If there is none, it replaces the **last** slot whose id isn't the protected one.
  - So with no snapshot and something playing, `current` lands in slot 0 (the main window) and `adding` in slot 1.
- **`moveFocus`:** `focusedSlot = neighbor`. If the new slot is filled, `audioSlot = focusedSlot`.
- **`setLayout`:**
  - Take the filled ids in slot order.
  - If there are more than the new capacity, drop ids from the end, never the `audioChannelID`, until they fit.
  - Fill the new layout's slots from 0 with the rest; pad with nil.
  - `focusedSlot` and `audioSlot` = the slot of the previous audio channel, else 0 and nil.
  - Return the dropped ids.
- **`assign`:**
  - If `id` is already in slot `t ≠ slot`, swap `slots[t]` and `slots[slot]` and return nil.
  - Otherwise put it in `slot` and return the previous occupant.
  - Either way `focusedSlot = slot` and `audioSlot = slot`.
- **`makeMain`:** with `main = layout.mainSlot`, `slot ≠ main`, swap them; then `focusedSlot = main` and `audioSlot = main` (if filled).
- **`remove`:**
  - Set the slot to nil.
  - If `audioSlot == slot`, `audioSlot` = the first filled slot or nil.
  - `focusedSlot` stays.

```swift
// IPTV/LiveMenu.swift
nonisolated enum LiveMenuAction: Hashable, Sendable {
    case watch(Channel.ID)
    case addToMultiview(Channel.ID)
    case fullScreen, makeMain, changeChannel, retryWindow, chooseLayout, removeWindow   // the highlighted window
    case setLayout(MultiviewLayout)
}

nonisolated struct LiveMenu: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        var id: String                      // stable, e.g. "watch", "addToMultiview", "layout.grid"
        var title: String
        var value: String? = nil            // right-aligned: the current layout's title, "Current"
        var layout: MultiviewLayout? = nil  // draws a diagram before the title (layout menu)
        var action: LiveMenuAction
    }
    enum Outcome: Equatable, Sendable { case none, close, choose(LiveMenuAction) }

    var title: String
    var items: [Item]
    private(set) var focusedIndex: Int

    init(title: String, items: [Item], focusedIndex: Int = 0)   // clamps
    /// Up/Down move (clamped); Select → .choose(focused action); Back → .close; everything else → .none.
    mutating func handle(_ command: RemoteCommand) -> Outcome
}
```

`GuideModel` changes:

```swift
enum Focus: Equatable, Sendable { case grid, channel, groups(Int) }
enum Action: Equatable, Sendable { case none, play(Channel.ID), close, groupChanged(String), channelMenu(Channel.ID) }
```

- **Grid focus, Left/Rewind on the first cell (airing now):** `focus = .channel` (M4: `.groups`). The other grid rules are unchanged.
- **Channel focus:**
  - **Up/Down:** the same row movement as the grid (clamp, `keepRowVisible`); focus stays `.channel`.
  - **Right/Fast-forward:** `focus = .grid`; `focusTime` is unchanged.
  - **Left/Rewind:** `focus = .groups(groupIndex)`.
  - **Select:** `.channelMenu(focusedChannel.id)`, or `.none` with no channel.
  - **Back:** `.close`.
  - **Play/Pause, Home:** `.none`.
- **Groups focus:** unchanged. Back/Left → `.grid`; Select/Right apply the group.
- **`setChannels`:** unchanged. A `.channel` focus stays `.channel`.

`LiveTVModel` changes:

```swift
@Observable
final class LiveTVModel: LiveTVHosting {
    enum Mode: Equatable { case setupNeeded, loading, player, guide, multiview, unavailable(String) }
    enum GuidePurpose: Equatable { case watch, pick(slot: Int) }
    struct VideoPlacement: Identifiable {
        let player: any LivePlayer
        var id: ObjectIdentifier { ObjectIdentifier(player) }
        var canvasRect: CGRect?          // nil = the whole window
        var isVisible: Bool
    }

    private(set) var player: any LivePlayer          // was `let`: the full-screen player
    private(set) var guidePurpose: GuidePurpose = .watch
    private(set) var multiview: MultiviewModel?      // non-nil in .multiview and in the picker guide
    private(set) var tilePlayers: [Channel.ID: any LivePlayer] = [:]
    private(set) var failedWindows: Set<Channel.ID> = []
    private(set) var menu: LiveMenu?
    // banner, showsTimeshiftBar, playbackError, guide, currentChannel: as in M4

    @ObservationIgnored private var players: [any LivePlayer]          // the pool; players[0] is the init player
    @ObservationIgnored private let makePlayer: () -> any LivePlayer
    @ObservationIgnored private var refreshedWindows: Set<Channel.ID> = []
    @ObservationIgnored private var appVolume: (level: Int, muted: Bool)?

    init(player: any LivePlayer, makePlayer: @escaping () -> any LivePlayer, library: IPTVLibrary,
         now: @escaping () -> Date = Date.init, overlayDuration: Duration = .seconds(5))

    var videoPlacements: [VideoPlacement]            // L15
    /// The window with sound in the picker guide, else `player`.
    var previewPlayer: any LivePlayer
    /// The guide's "playing" mark: the window with sound in the picker guide, else currentChannel.
    var previewChannel: Channel?
    /// Phone in-app volume (D25): every pool player, and players created later.
    func setAppVolume(_ level: Int, muted: Bool)
}
```

`LiveTVModel` behavior (additions to M4's):

- **Pool:**
  - `configure(_ p:)` sets `p.onFailure = { [weak self, weak p] in if let p { self?.playerFailed(p) } }` and applies `appVolume` if set. `init` configures `player` and sets `players = [player]`.
  - `acquirePlayer() -> (any LivePlayer)?`:
    - Return the first pool player that is not a value in `tilePlayers` (compare with `===`).
    - Otherwise, if `players.count < MultiviewModel.maxWindows`, make, configure, append and return a new one.
    - Otherwise log an error and return nil (this can't happen while windows ≤ 5).
  - `release(_ p:)`: `p.stop()`; `p.setAudible(true)`. It stays in `players`.
- **`handle(_:)`** order:
  1. `.home` → `.leave`.
  2. If `menu != nil` → `menu.handle`:
     - `.close` → `menu = nil`.
     - `.choose(a)` → `menu = nil`, then `perform(a)`.
     - Return `.handled`.
  3. Switch on mode as in M4, plus `.multiview` → `handleMultiview`.
- **`handleGuide`**, new or changed cases:
  - `.channelMenu(id)`:
    - Watch purpose: `menu = channelMenu(for: id)`.
    - Pick purpose: same as `.play(id)`.
  - `.play(id)` with pick purpose: `assignWindow(id, slot)`, then `closePicker()`.
  - `.close` with pick purpose: `closePicker()`.
  - Play/Pause with pick purpose: `previewPlayer.togglePause()`.
  - Watch purpose is unchanged from M4.
- **`channelMenu(for id)`:** `LiveMenu(title: channel.name, items:)`:
  - `"watch"` "Watch" → `.watch(id)`.
  - `"addToMultiview"`: "Show in Multiview" if `library.state.multiview?.slots` contains `id`, else "Add to Multiview". Action `.addToMultiview(id)`.
- **`perform`:**
  - `.watch(id)` → the same path as the watch guide's `.play(id)`.
  - `.addToMultiview(id)` → `enterMultiview(adding: id)`.
  - `.fullScreen` → `exitMultiview()`.
  - `.makeMain` → `multiview.makeMain(focusedSlot)`; `applyAudio()`; `saveSnapshot(true)`.
  - `.changeChannel` → `openPicker(slot: focusedSlot)`.
  - `.retryWindow` → for the focused id: remove it from `failedWindows` and `refreshedWindows`, then `tilePlayers[id]?.play(channel.streamURL)`.
  - `.chooseLayout` → `menu = layoutMenu()`.
  - `.setLayout(l)` → `dropped = multiview.setLayout(l)`. Release each dropped id's player and remove it from `tilePlayers` and `failedWindows`. Then `applyAudio()`, `saveSnapshot(true)`.
  - `.removeWindow` → `removeWindow(focusedSlot)`.
- **`enterMultiview(adding:)`:**
  - `let current = isPlaying ? currentChannel?.id : nil`.
  - `mv = MultiviewModel.entering(snapshot: library.state.multiview, current:, adding:, validIDs: Set(library.channels.map(\.id)))`.
  - `startMultiview(mv, reusing: current)`.
- **`startMultiview(_ mv:, reusing current:)`:**
  1. `guide = nil`; `guidePurpose = .watch`; `menu = nil`; `hideOverlays()`; `playbackError = nil`; `tilePlayers = [:]`; `failedWindows = []`; `refreshedWindows = []`.
  2. If `current` is in `mv`: `tilePlayers[current] = player` and `player.setBufferProfile(.tile)`. Otherwise `player.stop()`.
  3. For each id in `mv.channelIDs` without a player, if its channel exists and `acquirePlayer()` gives `p`:
     - `p.setBufferProfile(.tile)`; `tilePlayers[id] = p`; `p.play(channel.streamURL)`.
  4. `multiview = mv`; `mode = .multiview`; `applyAudio()`; `saveSnapshot(true)`; `showWindowChip()`.
- **`applyAudio()`:** for each `(id, p)` in `tilePlayers`, `p.setAudible(id == multiview?.audioChannelID)`.
- **`handleMultiview`:** per L9.
  - Arrows: `if multiview.moveFocus(dir) { applyAudio(); showWindowChip() }`.
  - Select: if the focused slot is filled → `menu = windowMenu()`; else `openPicker(slot:)`.
  - Play/Pause: the focused window's `togglePause()`, then `showTimeshiftBar()`.
  - Rewind/Fast-forward: the focused window's `seek(by: ∓longSkip)`, then `showTimeshiftBar()`.
  - Back: `exitMultiview()`.
  - Returns `.handled`.
- **`exitMultiview()`:**
  1. The target is the focused slot if filled, else `audioSlot`, else the first filled slot. With none, `removeAllWindows()` and return.
  2. `p = tilePlayers[target]`. Release every other tile player.
  3. `player = p`; `p.setBufferProfile(.full)`; `p.setAudible(true)`.
  4. `currentChannel` = the target's channel; `library.rememberChannel(id)`; `playbackError = failedWindows.contains(id) ? Self.playbackErrorMessage : nil`; `refreshedAfterFailure = refreshedWindows.contains(id)`.
  5. `saveSnapshot(false)` **before** clearing; then `multiview = nil`; `tilePlayers = [:]`; `failedWindows = []`; `refreshedWindows = []`.
  6. `mode = .player`; `showBanner()`.
- **`removeWindow(slot)`:**
  - `id = multiview.remove(slot)`. Release its player and remove it from `tilePlayers`, `failedWindows` and `refreshedWindows`.
  - If `multiview.isEmpty`: `removeAllWindows()`. Otherwise `applyAudio()`, `saveSnapshot(true)`.
- **`removeAllWindows()`:**
  - Release all tile players; `tilePlayers = [:]`; `multiview = nil`; `library.rememberMultiview(nil)`.
  - `openGuide()` (watch; nothing plays, so Back leaves).
- **`openPicker(slot:)`:**
  - `guide = GuideModel(allChannels: library.channels, group: library.state.lastGroup, focusedChannelID: multiview.slots[slot] ?? multiview.audioChannelID, now: now())`.
  - `guidePurpose = .pick(slot: slot)`; `mode = .guide`; `hideOverlays()`; `loadProgrammes()`.
- **`closePicker()`:** `guide = nil`; `guidePurpose = .watch`; `mode = .multiview`; `showWindowChip()`.
- **`assignWindow(id, slot)`:**
  1. `displaced = multiview.assign(id, to: slot)`.
  2. If `displaced` has a player: release it; remove `displaced` from `tilePlayers`, `failedWindows` and `refreshedWindows`.
  3. If `tilePlayers[id] == nil`, the channel exists, and `acquirePlayer()` gives `p`: `p.setBufferProfile(.tile)`; `tilePlayers[id] = p`; `p.play(url)`.
  4. `applyAudio()`; `saveSnapshot(true)`.
  - **Release before acquire**, so a full 1 + 4 never needs a sixth player.
- **`windowMenu()`:** `LiveMenu(title: focused channel name, items:)`, per L10:
  - `"fullScreen"` Full Screen.
  - `"makeMain"` Make Main (only when `layout.mainSlot != nil && focusedSlot != mainSlot`).
  - `"changeChannel"` Change Channel.
  - `"retry"` Retry (only if `failedWindows` contains the id).
  - `"layout"` Layout, with value `layout.title`.
  - `"remove"` Remove.
- **`layoutMenu()`:** `LiveMenu(title: "Layout", items: MultiviewLayout.allCases.map { Item(id: "layout.\($0.rawValue)", title: $0.title, value: $0 == current ? "Current" : nil, layout: $0, action: .setLayout($0)) }, focusedIndex: index of the current layout)`.
- **`showWindowChip()`:**
  - Same pattern as `showBanner()`: `banner = Banner(channel: focused channel)`, then `nowNext`, then hide after `overlayDuration` (shared `bannerGeneration`).
  - An empty focused slot sets `banner = nil`.
  - In Multiview the view draws `banner` as a chip on the focused window, not as M4's bottom banner.
- **`playerFailed(_ p)`:**
  - If `multiview != nil` and `p` is a value in `tilePlayers` (key `id`):
    - If `refreshedWindows` lacks `id`: insert it, then a `pendingTask` runs `await library.refreshPlaylist()`. If `tilePlayers[id] === p` still, play the fresh channel's URL on `p`.
    - Otherwise insert `id` into `failedWindows`.
  - Else if `p === player`: M4's `playerFailed()` logic, unchanged.
  - Else ignore it (a released player).
- **`saveSnapshot(_ active: Bool)`:** `library.rememberMultiview(multiview?.snapshot(isActive: active))`.
- **`open()`:** after channels are loaded, and before M4's last-channel step:
  - If `let s = library.state.multiview, s.isActive`: `mv = MultiviewModel(snapshot: s, validIDs: …)`.
    - If `!mv.isEmpty`: `startMultiview(mv, reusing: nil)` and return.
    - Otherwise `library.rememberMultiview(MultiviewSnapshot(..., isActive: false))` (the same snapshot, inactive) and continue.
- **`leave()`:**
  - If `multiview != nil`, `saveSnapshot(true)` first (records the focused slot; a picker guide counts as Multiview).
  - Then stop **every** pool player and set `tilePlayers = [:]`, `failedWindows = []`, `refreshedWindows = []`, `multiview = nil`, `menu = nil`, `guidePurpose = .watch`.
  - Then M4's resets (guide, banner, bar, error, generations).
- **`setAppVolume`:** `appVolume = (level, muted)`; every player in `players` → `setVolume(level, muted:)`.
- **`videoPlacements`:** L15's table.
  - In `.multiview`, iterate slots in order and skip empty ones.
  - In the picker guide, include every tile player in slot order, using `Theme.guidePreviewRect` for the audio window.
  - The canvas rects come from `multiview.layout.slots[slot]`.

### Router and AppDelegate

- **`AppRouter`:** no change. `LiveTVHosting` is unchanged, and Home → `liveTV.leave()` stops every player.
- **`AppDelegate`:**
  - `LiveTVModel(player: MPVPlayerController(), makePlayer: { MPVPlayerController() }, library: iptvLibrary)`.
  - Remove the `livePlayer` property.
  - The volume route's `applyAppVolume` calls `self?.liveTV?.setAppVolume(volume.level, muted: volume.muted)` instead of `livePlayer?.setVolume`, and still calls `youtube?.setVolume`.

### Views

**`LiveTVRootView`** keeps M4's structure; the single video view becomes a `ForEach`:

```swift
ForEach(model.videoPlacements) { placement in
    if let view = (placement.player as? MPVPlayerController)?.videoView {
        let rect = placement.canvasRect.map { CanvasGeometry.windowRect(forCanvasRect: $0, in: size) }
            ?? CGRect(origin: .zero, size: size)
        MPVVideoRepresentable(view: view)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .opacity(placement.isVisible ? 1 : 0)
            .transaction { $0.animation = nil }
    }
}
```

- Keep `.onAppear { (model.player as? MPVPlayerController)?.prepare() }`. Tile players `prepare()` inside `play()`, and their view enters the tree in the same update.
- **Overlay:**
  - `.player` → `PlayerOverlayView`, unchanged.
  - `.guide` → `GuideView(model:, currentChannel: model.previewChannel, phase: model.previewPlayer.state.phase, isPicking: model.guidePurpose != .watch)`.
  - `.multiview` → `MultiviewOverlayView(model: model)`.
  - The other modes as in M4.
  - Then, above everything, `if let menu = model.menu { LiveMenuView(menu: menu) }`.
- `.animation(.easeInOut(duration: 0.2), value: model.menu)` on the overlay.

**`MultiviewOverlayView(model:)`** is drawn on the canvas, positioned with `.frame` + `.offset` like `GuideView`. For each slot `i` of `multiview.layout.slots` (rect `r`):

- **Empty slot:**
  - A `RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius)` filled `Theme.tileFill`.
  - Centered: `Image(systemName: "plus")` (`Theme.multiviewEmptySymbolSize`) over "Add Channel" (`Theme.multiviewChipDetailFont`, `secondaryText`).
- **Filled slot** (player `p = model.tilePlayers[id]`):
  - `p.state.phase == .loading` and not failed → `ProgressView()` centered.
  - `failedWindows.contains(id)` → "Can't play this channel" (`Theme.multiviewChipDetailFont`) on `.black.opacity(0.6)`.
  - `phase == .paused` → `Image(systemName: "pause.fill")` centered on a dark circle.
- **Sound badge:** when `multiview.channelIDs.count > 1`, the audio slot gets `Image(systemName: "speaker.wave.2.fill")` in a black 0.6 capsule, 12 pt from its top-right corner.
- **Focus border** on the focused slot: `Rectangle().strokeBorder(Theme.multiviewFocusBorder, lineWidth: Theme.multiviewFocusBorderWidth)` over `r`.
- **Chip:** when `model.banner` is set and the focused slot is filled, a chip along the bottom of the focused window (`.black.opacity(0.7)` background, 16 pt padding):
  - Line 1: the channel name (`Theme.multiviewChipFont`).
  - Line 2: `banner.now?.title` (`multiviewChipDetailFont`, `secondaryText`), if any.
  - Line 3: "Select: options · Back: full screen" (`multiviewChipDetailFont`, `secondaryText`).
- **Timeshift label:** when `model.showsTimeshiftBar || phase == .paused` for the focused window and its `timeshift?.isLive == false`, the `timeshift.label` capsule at the focused window's top-left (as M4's badge).
- `.animation(.easeInOut(duration: 0.2), value: model.banner)`.

**`MultiviewLayoutDiagram(layout:)`** draws `layout.rawSlots` scaled into `Theme.multiviewDiagramSize` (96 × 54): 1 pt-inset rounded rects, stroked `primaryText`, filled `tileFill`. Picture in Picture's small rect is filled `primaryText`.

**`LiveMenuView(menu:)`:**

- Centered panel, `Theme.liveMenuWidth` wide, `.black.opacity(0.92)` in `RoundedRectangle(cornerRadius: Theme.tileCornerRadius)`, 32 pt padding.
- The title (`Theme.liveMenuTitleFont`).
- Then rows of height `Theme.liveMenuRowHeight`: an optional diagram, the title (`Theme.settingsRowFont`), and the value right-aligned (`Theme.settingsDetailFont`).
- The focused row uses `focusedRowFill` / `focusedRowText`, as in Settings.
- At the bottom, the hint "Select: choose · Back: close" (`settingsHintFont`, `secondaryText`).
- A dim layer (`.black.opacity(0.4)`) covers the whole canvas behind the panel.

**`GuideView`:**

- New parameter `isPicking: Bool`.
- The channel cell of the focused row gets `focusedRowFill` (rounded `guideCellCornerRadius`, padded 8 pt) and `focusedRowText` (the number in `focusedRowSecondaryText`) when `model.focus == .channel`.
- The hint becomes `GuideView.hint(focus: model.focus, isPicking: isPicking)` (a `static func`, nonisolated, unit-tested):

  | Focus | Watch | Pick |
  |---|---|---|
  | `.grid` | "Select: watch · Left at now: channel options · Back: close" | "Select: show in window · Left at now: channel · Back: cancel" |
  | `.channel` | "Select: options · Left: groups · Right: programmes · Back: close" | "Select: show in window · Left: groups · Right: programmes · Back: cancel" |
  | `.groups` | "Select: show group · Back: close list" | same |

### Theme additions

| Token | Value |
|---|---|
| `multiviewGap` | `MultiviewLayout.gap` (8) |
| `multiviewFocusBorder` | `Color.white` |
| `multiviewFocusBorderWidth` | 6 |
| `multiviewEmptySymbolSize` | 48 |
| `multiviewChipFont` | `Font.system(size: 26, weight: .semibold)` |
| `multiviewChipDetailFont` | `Font.system(size: 20)` |
| `multiviewDiagramSize` | `CGSize(width: 96, height: 54)` |
| `liveMenuWidth` | 720 |
| `liveMenuTitleFont` | `Font.system(size: 34, weight: .semibold)` |
| `liveMenuRowHeight` | 72 |

## Implementation steps

After every step, build with `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build`. Run the tests whenever a step adds or changes them. **Never log a full stream URL** (M4 L2); logs use the host and the player index.

- [x] **1. Player capabilities**: `IPTV/Player/MPVOptions.swift`, `IPTV/Player/LivePlayer.swift`, `MMTVLTests/FakePlayer.swift`, `MMTVLTests/MPVOptionsTests.swift` (new)
  - Add `BufferProfile`, the tile sizes and `("video-timing-offset", "0")` (last in `MPVOptions.all`).
  - Add the three protocol methods. Implement them in `MPVPlayerController` per *Key types*, plus `index` and the once-per-load `hwdec-current` log.
  - `FakePlayer` gains:
    - `var volume: (level: Int, muted: Bool)?`
    - `var audible = true`
    - `var bufferProfile = BufferProfile.full`
    - and records them in the three methods.
  - `AppDelegate` still calls `livePlayer?.setVolume`; that compiles unchanged.
  - `MPVOptionsTests`:
    - `MPVOptions.all` contains `("video-timing-offset", "0")` and M4's buffer options.
    - `BufferProfile.tile.backBytes == "160MiB"` and `.forwardBytes == "64MiB"`; `.full` gives M4's values.
  - Done when:
    - The build and tests pass.
    - **Manual (windowed):** Live TV plays a channel as before. Lip sync looks right on a talking-head channel (L7).
    - The `MPV` log shows "Decoder videotoolbox (player 1)".

- [x] **2. Multiview layouts and model (pure)**: `IPTV/Multiview/MultiviewLayout.swift`, `IPTV/Multiview/MultiviewModel.swift`, `IPTV/IPTVState.swift`, `IPTV/IPTVLibrary.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/MultiviewLayoutTests.swift`, `MMTVLTests/MultiviewModelTests.swift`, `MMTVLTests/IPTVLibraryTests.swift`
  - Implement `MultiviewLayout`, `MultiviewSnapshot` and `MultiviewModel` per *Key types* and the rules under them. Add `Theme.multiviewGap`.
  - **`IPTVState`:**
    - Add `var multiview: MultiviewSnapshot?` (init parameter defaulting to nil).
    - Decode it with `try? container.decodeIfPresent(MultiviewSnapshot.self, forKey: .multiview)` flattened to nil, so a bad snapshot never fails the whole file (L13).
  - **`IPTVLibrary.rememberMultiview(_ snapshot: MultiviewSnapshot?)`:** `guard state.multiview != snapshot`, then `updateState { $0.multiview = snapshot }`.
  - `MultiviewLayoutTests`:
    - Capacities 5/4/4/3/2/2; `mainSlot` per the table.
    - Every `rawSlots` rect is 16:9 (`abs(w/h − 16/9) < 0.001`) and inside the canvas.
    - For every layout except Picture in Picture, the raw rects don't overlap, and their areas sum to 1920 × 1080.
    - `slots[i] == rawSlots[i].insetBy(dx: 4, dy: 4)`, except `pictureInPicture.slots[0] == (0, 0, 1920, 1080)`.
    - `onePlusFour.rawSlots` equal the table exactly.
    - **Neighbors** (L4):
      - 1 + 4:
        - 0↓ → 2 (2 and 3 tie on both distances, so the lower index wins); 0← → nil; 0→ → nil; 0↑ → nil.
        - 1↑ → 0; 2↑ → 0; 4↑ → 0.
        - 1→ → 2; 3← → 2; 4→ → nil.
      - 1 + 3: 0→ → 2 (middle: smallest vertical offset); 1← → 0; 1↓ → 2; 3↓ → nil; 0↑ → nil.
      - 2 × 2: 0→ → 1; 0↓ → 2; 1↓ → 3; 3← → 2; 3↑ → 1.
      - 1 + 2: 0→ → 1 (a tie with 2, lower index); 2← → 0.
      - Picture in Picture: 0→ → 1; 0↓ → 1; 1← → 0; 1↑ → 0; 1→ → nil.
      - Side by Side: 0→ → 1; 1→ → nil; 0↓ → nil.
    - `Direction(RemoteCommand.select) == nil`.
  - `MultiviewModelTests` (ids are plain strings like "a"):
    - **init** pads to capacity; clamps focus; `audioSlot` = focused if filled, else the first filled.
    - **entering**, no snapshot:
      - current "a", adding "b" → slots `[a, b, nil, nil, nil]`, focus 1, audio 1, layout 1 + 4.
      - No current → `[b, nil…]`, focus 0.
      - current == adding → `[a, nil…]`.
    - **entering** with a snapshot `[x, nil, y, nil, nil]` (layout 1 + 4):
      - current "a", adding "b" → `[x, a, y, b, nil]`, focus 3.
      - With "y" invalid → `[x, a, b, nil, nil]`.
      - Adding "x" (already there) → unchanged slots, focus 0.
    - **entering** with a full snapshot `[p, q, r, s, t]`:
      - current "a", adding "b" → `a` replaces `t`, then `b` replaces `s` (the last that isn't `a`) → `[p, q, r, b, a]`, focus 3.
    - **entering** with a full Side by Side snapshot `[p, q]`, current "a", adding "b":
      - Placing `a` replaces `q` → `[p, a]`.
      - Placing `b` protects `a`, so it replaces `p` → `[b, a]`, focus 0.
    - **moveFocus:** onto a filled slot moves the audio; onto an empty slot keeps it; returns false at an edge.
    - **setLayout:**
      - From 1 + 4 `[a, b, c, d, e]` with audio on `e` to Side by Side: dropping from the end skips `e`, so `d`, `c`, `b` go. The result is `[a, e]`, returning `[d, c, b]` (any order; compare as sets), with focus and audio on slot 1.
      - To a larger layout: compacts in slot order and pads.
    - **assign:**
      - Into an empty slot → returns nil.
      - Into a filled slot → returns the old id.
      - An id already elsewhere → swap, returns nil.
      - Focus and audio move to the slot.
    - **makeMain** swaps with slot 0 and moves focus and audio there. No-op in 2 × 2.
    - **remove** returns the id, and moves the audio to the first filled slot when it was the audio slot.
    - **Snapshots** round-trip through `JSONEncoder`/`JSONDecoder` and `init(snapshot:validIDs:)`.
  - `IPTVLibraryTests`:
    - `IPTVState` with a multiview snapshot round-trips through the state file.
    - A state file whose `multiview.layout` is `"bogus"` loads with `multiview == nil` and keeps `lastChannelID`.
    - `rememberMultiview` saves.
  - Done when the tests pass.

- [x] **3. Menus (pure) and the menu view**: `IPTV/LiveMenu.swift`, `IPTV/LiveMenuView.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/LiveMenuTests.swift`
  - `LiveMenu` and `LiveMenuAction` per *Key types*. Add `LiveMenuView` and the `liveMenu*` tokens. Nothing shows a menu yet.
  - `MultiviewLayoutDiagram` is needed by `LiveMenuView`. Put it in `IPTV/Multiview/MultiviewView.swift` now; the rest of that file comes in step 5.
  - `LiveMenuTests`:
    - Up/Down clamp at both ends.
    - Select → `.choose(action)` of the focused item.
    - Back → `.close`.
    - Left/Right/Play/Pause → `.none`.
    - `init` clamps `focusedIndex`.
  - Done when the tests pass.

- [x] **4. Guide channel cell and channel menu ("Watch" only)**: `IPTV/Guide/GuideModel.swift`, `IPTV/Guide/GuideView.swift`, `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `MMTVLTests/GuideModelTests.swift`, `MMTVLTests/LiveTVModelTests.swift`, `MMTVLTests/GuideViewHintTests.swift` (new)
  - **GuideModel:** `.channel` focus and `.channelMenu` action per *Key types*.
  - **GuideView:** the focused channel cell, `isPicking` (always false for now), and `hint(focus:isPicking:)`.
  - **LiveTVModel:**
    - `menu` state, plus the menu-first branch in `handle`.
    - `.channelMenu(id)` in the watch guide opens a menu with **only "Watch"**; step 5 adds "Add to Multiview".
    - `perform(.watch)`. The other `perform` cases log and do nothing until steps 5–6.
  - **LiveTVRootView:** draws `LiveMenuView` when `model.menu != nil`.
  - **Update M4 tests:**
    - In `GuideModelTests`, wherever a test presses Left at the now-cell expecting `.groups`, press Left **twice**: the first lands on `.channel`. That's the `left`/`groups` checks around lines 93–121.
    - In `LiveTVModelTests.groupChangeIsRemembered`, press `.left` twice.
  - New `GuideModelTests`:
    - Left at now → `.channel`; Left again → `.groups(groupIndex)`.
    - Right from `.channel` → `.grid`, with the same focused cell.
    - Up/Down in `.channel` move rows and keep `.channel`.
    - Select in `.channel` → `.channelMenu(id)`.
    - Back in `.channel` → `.close`.
  - `GuideViewHintTests`: the six strings in the hint table.
  - New `LiveTVModelTests`:
    - In the guide, Left, Select → `model.menu?.title == "NFL Network"` with items `["watch"]`.
    - Select on "Watch" → `.player`, the channel played, menu nil.
    - Back in the menu → menu nil, still `.guide`.
    - Home with the menu open → `.leave`.
  - Done when:
    - The tests pass.
    - **Manual (windowed):** in the guide, Left at now highlights the channel name; Select shows the menu; Watch plays.

- [x] **5. Player pool, entering and leaving Multiview**: `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `IPTV/Multiview/MultiviewView.swift`, `App/AppDelegate.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/PlayerFactory.swift` (new), `MMTVLTests/LiveTVModelTests.swift`, `MMTVLTests/MultiviewLiveTVTests.swift` (new)
  - **Model:**
    - `init(player:makePlayer:…)`, the pool (`configure`, `acquirePlayer`, `release`).
    - `.multiview` mode; "Add to Multiview" in the channel menu (L8 titles).
    - `enterMultiview`, `startMultiview`, `applyAudio`, `handleMultiview` (arrows, Play/Pause, RW/FF, Back; **Select only logs for now**).
    - `exitMultiview`; `showWindowChip`; `saveSnapshot`; `leave()` changes.
    - `setAppVolume`, `videoPlacements` (`.player`, `.guide` watch, `.multiview`, other modes), `previewPlayer`, `previewChannel`.
    - `playerFailed(_:)` with the window branch.
  - **AppDelegate** per *Router and AppDelegate*.
  - **Views:**
    - `LiveTVRootView`'s `ForEach` over placements.
    - `MultiviewOverlayView` with **empty slots, the focus border and the chip**. Spinner, failure, pause, sound badge and timeshift label come in step 7.
    - Theme `multiview*` tokens.
  - **Tests:**
    - `PlayerFactory` (test helper): `final class PlayerFactory { var made: [FakePlayer] = []; func make() -> any LivePlayer { … append … } }`.
    - Update every `LiveTVModel(...)` construction in `LiveTVModelTests` to pass `makePlayer: factory.make` (or `{ FakePlayer() }` where the test doesn't care).
  - `MultiviewLiveTVTests`, using `makeLibrary` with `IPTVState(lastChannelID: "id:nflnetwork.us")` so NFL Network plays first. The fixture playlist has five channels: NFL Network, NBA TV, Red Zone, and the two NBA games.
    - Helper `addToMultiview(_ model: LiveTVModel, _ id: Channel.ID)`:
      1. If `mode == .multiview`, press Back (full screen).
      2. Press Select (the guide opens on the current channel).
      3. Press Down, or Up, until `model.guide?.focusedChannel?.id == id`, at most 10 presses. With no remembered group, the guide shows "All Channels", so every fixture channel is reachable.
      4. Left (channel cell), Select (menu), Down, Select ("Add to Multiview" / "Show in Multiview").
    - It drives only remote commands, so it also tests the real path.
    - **Add NBA TV while NFL Network plays:**
      - mode `.multiview`; slots `["id:nflnetwork.us", "id:nbatv.us", nil, nil, nil]`, focus 1.
      - `factory.made.count == 1`; NBA TV played on `made[0]`; the main player played nothing new (`played.count == 1`).
      - The main player has `bufferProfile == .tile` and `audible == false`; `made[0].audible == true`.
      - `library.state.multiview?.isActive == true`.
    - **Arrows:** Up from slot 1 → focus 0; `audible` swaps; `banner?.channel.name == "NFL Network"`. Down → slot 2 (empty): focus 2, but NFL Network stays audible. Right → slot 3.
    - **RW/FF/Play/Pause** act on the focused window's player only (`seeks`, `pauses`).
    - **Back** from focus on NBA TV:
      - `.player`, `model.player === made[0]`, `currentChannel` NBA TV.
      - The original player `stops == 1`.
      - `made[0].bufferProfile == .full`, audible.
      - The snapshot is kept with `isActive == false`.
    - **Re-enter:** in the guide, "Show in Multiview" on NBA TV → both windows back; NFL Network replays on a pool player; no more than 2 players exist in total.
    - **Five windows:** add the remaining three channels one by one with the helper (each one exits to full screen and re-enters). Afterwards 1 + 4 is full, and the pool has exactly 5 players (`factory.made.count == 4`).
    - **`leave()`** stops every pool player. `open()` restores Multiview with the same slots, and every slot's channel is played again.
    - **`setAppVolume(30, muted: false)`** reaches every player, including one created afterwards.
    - **Placements:**
      - `.multiview` → one per filled slot with the layout's slot rects, visible.
      - `.player` → one, nil rect.
      - Watch `.guide` → `Theme.guidePreviewRect`.
    - **Window failure:**
      - `made[0].fail()` → the network fetch count +1 and NBA TV replayed on `made[0]`.
      - `fail()` again → `failedWindows` contains it.
      - Back from it → `.player` with `playbackError` set.
  - Done when:
    - The tests pass.
    - **Manual (windowed):** play a channel; guide → Left → Select → Add to Multiview on another channel.
      - Both windows play in 1 + 4. The first never went black or reconnected.
      - Arrows move the white border; the sound switches at once; the chip shows the channel.
      - Back returns full screen to the highlighted one without a reload.
      - The `MPV` log shows a videotoolbox decoder for each player.
      - Repeat 3 times.

- [x] **6. Window menu, layouts, picker guide, restore**: `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `IPTV/Guide/GuideView.swift`, `MMTVLTests/MultiviewLiveTVTests.swift`
  - **Model:**
    - Select in Multiview opens `windowMenu()` (filled) or `openPicker` (empty).
    - The `perform` cases `.fullScreen`, `.makeMain`, `.changeChannel`, `.retryWindow`, `.chooseLayout`, `.setLayout`, `.removeWindow`.
    - `openPicker`, `closePicker`, `assignWindow`; the pick-purpose branches of `handleGuide`.
    - `removeWindow`, `removeAllWindows`.
    - `videoPlacements` for the picker guide.
  - **Views:** `GuideView` gets `isPicking` from `model.guidePurpose`. The preview uses `previewPlayer`/`previewChannel`.
  - `MultiviewLiveTVTests`:
    - **Window menu** ids for a filled 1 + 4 window not in the main slot: `["fullScreen", "makeMain", "changeChannel", "layout", "remove"]`. In 2 × 2 there's no `makeMain`; after a failure, `retry` comes before `layout`.
    - **Select on an empty slot** → `.guide`, `guidePurpose == .pick(slot:)`. Select on a row → that channel plays on a pool player in that slot; back in `.multiview` with focus there.
    - **Change Channel** on a filled window to a new channel → the old player is stopped and released; the pool doesn't grow past 5 when 1 + 4 is full.
    - **Change Channel** to a channel already in another window → the slots swap, and no player's `played` changes.
    - **Back in the picker guide** → `.multiview`, slots unchanged.
    - **Make Main** → the slots swap, and focus and audio go to slot 0.
    - **Layout → Side by Side** from a full 1 + 4 with audio on slot 3 → two windows kept (slot 0's and the audio one), three players stopped, the snapshot saved.
    - **Remove** → its player stopped. Removing every window → `.guide` (watch), nothing playing, `library.state.multiview == nil`.
    - **Retry** after two failures → the window plays again and leaves `failedWindows`.
    - **Picker placements:** the audio window at `guidePreviewRect`, visible; the others at their slot rects, invisible.
  - Done when:
    - The tests pass.
    - **Manual (windowed):**
      - The window menu works for each item.
      - Change Channel shows the guide with the audio window in the preview, and the choice lands in the right window.
      - Each of the six layouts looks right.
      - Remove until empty → guide.
      - Home in Multiview, then the Live TV tile → Multiview comes back.

- [x] **7. Multiview polish and the five-window check**: `IPTV/Multiview/MultiviewView.swift`, `IPTV/LiveTVView.swift`
  - Complete `MultiviewOverlayView`: the spinner, the failure text, the pause symbol, the sound badge and the timeshift label (*Views*).
  - Done when **manual, in kiosk mode on the Mac mini and TV, with real channels:**
    - Fill 1 + 4 with five live channels. All play smoothly; the arrows respond at once; the sound follows.
    - Activity Monitor after 10 minutes: CPU low (hardware decode), **memory under about 2.5 GB**.
    - The `MPV` log shows no "mpv_render_context_render() not being called or stuck".
    - Change Channel on one window 3 times in a row. Each new channel starts (Retry is allowed once). Record what happens in *Deviations*: this is the stream-limit check.
    - Rewind one window 2 minutes; the others stay live; its label shows "−2:xx".
    - Back → that window full screen, still 2 minutes behind (no reload). Fast-forward to LIVE.
    - Picture in Picture: the small window is drawn above the big one.

- [x] **8. Docs wrap-up**: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - **CLAUDE.md:**
    - `iptv-state.json` also holds the Multiview snapshot (layout, channel ids per window, active). Hand edits are fine while MMTVL is quit.
    - Multiview runs up to 5 mpv players (one per window, pooled), and the `MPV` log lines name the player ("player 2").
  - **Master plan:** M6 → Done once the manual checks pass. Check that D7, D14 and D22 match what was built.
  - Tick this plan's boxes.
  - Done when the docs match the code.

- [x] **9. Full test run and kiosk pass**: no files
  - `xcodebuild … test` passes.
  - Run *Manual verification* in kiosk mode on the Mac mini and TV.
  - Done when every item is ticked or recorded in *Deviations*.

## Tests

| File | Asserts |
|---|---|
| `MMTVLTests/MPVOptionsTests.swift` (new) | `video-timing-offset=0`; buffer profile sizes. |
| `MMTVLTests/MultiviewLayoutTests.swift` (new) | Capacities, main slots, 16:9 rects, tiling, insets, neighbors. |
| `MMTVLTests/MultiviewModelTests.swift` (new) | init, entering, focus/audio, setLayout, assign, makeMain, remove, snapshots. |
| `MMTVLTests/LiveMenuTests.swift` (new) | Menu navigation and outcomes. |
| `MMTVLTests/GuideViewHintTests.swift` (new) | Guide hints per focus and purpose. |
| `MMTVLTests/GuideModelTests.swift` (changed) | Channel focus; Left twice to the groups. |
| `MMTVLTests/IPTVLibraryTests.swift` (changed) | Multiview snapshot persistence and tolerant decoding. |
| `MMTVLTests/LiveTVModelTests.swift` (changed) | `makePlayer` in constructors; channel menu; Left twice. |
| `MMTVLTests/MultiviewLiveTVTests.swift` (new) | Entering/leaving, pool reuse and cap, audio, per-window commands, menus, picker, layouts, removal, restore, failures, placements, volume. |
| `MMTVLTests/FakePlayer.swift` (changed), `PlayerFactory.swift` (new) | Test doubles. |

Commands (see CLAUDE.md):

```sh
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test -only-testing:'MMTVLTests/MultiviewModelTests'
```

Tests never touch the network or mpv. Every player in tests is a `FakePlayer`.

## Manual verification

Run in kiosk mode on the Mac mini and TV unless noted:

- [x] Single-channel Live TV still works as in M4 (zap, rewind, guide), with good lip sync.
- [x] Guide: Left at now → channel name; Select → menu (Watch, Add to Multiview); Left again → groups.
- [x] Add to Multiview while a channel plays → it keeps playing without a reconnect, and the new one joins in 1 + 4.
- [x] Five live channels in 1 + 4: smooth video, instant highlight moves, sound follows the highlight. Memory under ~2.5 GB after 10 min.
- [x] Each layout (1 + 4, 1 + 3, 2 × 2, 1 + 2, Side by Side, Picture in Picture) from the window menu → Layout. Windows that don't fit are dropped, never the one with sound.
- [x] Window menu: Full Screen, Make Main, Change Channel (the picker guide, swap when the channel is already shown), Remove.
- [x] Per-window Play/Pause and Rewind/Fast-forward; Back keeps the rewound position full screen.
- [x] Home from Multiview → home; all streams stop (Activity Monitor network drops to ~0). The Live TV tile reopens Multiview.
- [x] Sleep/wake while in Multiview → home, all stopped.
- [x] A window that can't play shows "Can't play this channel"; Retry works.
- [x] With `phoneRemoteVolume: "app"`, the phone's volume buttons change Multiview's volume. Mute silences everything; unmute brings back only the highlighted window's sound.
- [x] A controller drives Multiview (D-pad, A = Select, B = Back, X = Play/Pause, shoulders = RW/FF).

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| The main thread stalls with 5 GL layers | Laggy highlight moves; "mpv_render_context_render() not being called or stuck" in the MPV log | Confirm `video-timing-offset=0` is applied (check `mpv.string("video-timing-offset")`). If still slow, set `MPVVideoLayer.isAsynchronous = true` for tile players only. Ask before changing the layer. |
| A/V sync worse in single mode after L7 | Lips visibly off in step 1 | Set `video-timing-offset` back to the default (`0.050`) as a property while a player is full screen, and to `0` with the tile profile (the same place as `setBufferProfile`). Record it in Deviations. |
| Invisible (opacity 0) video layers aren't drawn, so mpv thinks rendering stalled | Stutter or the "not being called" log while the picker guide is open | Use opacity `0.01` instead of 0 for hidden placements. |
| The provider refuses a 5th stream, or counts a just-closed stream for a while | A window fails right after Change Channel, then works on Retry | Delay the new `play` by 2 s after releasing a player when 5 windows are in use. Record it, and ask the user before adding. If the 5th never works, cap windows at 4 (D14) and ask. |
| Memory too high on the mini | Activity Monitor above ~3 GB with 5 windows | Lower `tileBackBuffer` to 96MiB (about 3 min of rewind per window). Record the change in D7. |
| Hardware decoding falls back to software for some cores | The MPV log shows `Decoder no` for a player; high CPU | Record the player count where it happens. Cap windows there and ask. |
| A video view goes black after a window swap or layout change | Black window after Make Main | Check that placements are keyed by player identity (`ObjectIdentifier`) and not by slot. The view must not be re-created when its slot changes. |
| Overlays drawn under a video | The focus border or chip is missing over a window | The overlay canvas must come after the `ForEach` in the `ZStack` (M4 L16 ordering). |
| Leaving Live TV leaves a stream running | Network traffic after Home | `leave()` must stop every player in `players`, not just `player`. Covered by a test. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-10-06 (planner):** the user chose to split M6: Multiview here, guide management in M6b. They allowed 5 windows (all of the provider's streams) and chose the guide channel menu as the way in.
- **2026-10-06, step 1 (executor):** code, build and `MPVOptionsTests` done. The manual checks (lip sync, "Decoder videotoolbox (player 1)" in the MPV log) are left for the user.
- **2026-10-06, step 2 (executor), small fix:** the planned test "areas sum to 1920 × 1080 for every layout except Picture in Picture" can't hold: with 16:9 windows only 2 × 2 covers the canvas. 1 + 4 has 240 pt bars beside the big window, and 1 + 3, 1 + 2 and Side by Side have bars above and below (the geometry table itself). `MultiviewLayoutTests` checks no overlap for those five layouts, full coverage for 2 × 2, and less than the canvas for the others. The geometry is unchanged.
- **2026-10-06, steps 5–6 (executor), small additions:**
  - `leave()` and `removeAllWindows()` call `release` (stop + `setAudible(true)`) on the pool players, not only `stop`, and set the full-screen `player` back to `.full`. Otherwise a player muted or shrunk as a window could later play full screen silent or with the tile buffer (for example, `open()` falling back to the last channel after a stale snapshot).
  - `playerFailed` ignores the full-screen `player` while Multiview is open unless it is a window. A stopped, released player can't fail anyway.
  - `exitMultiview` handles a target window that has no player (can't happen while windows ≤ 5) by playing its channel on `player`.
  - Step 4's test that expected only `["watch"]` in the channel menu now expects `["watch", "addToMultiview"]` after step 5.
  - The step 6 test "Change Channel to a new channel while 1 + 4 is full" needs a sixth channel, so that test serves the fixture playlist plus an "ESPN" entry.
- **2026-10-06, steps 7 and 9 (executor):** step 7's overlay code is built. Its "done when" checks, step 9's kiosk pass and *Manual verification* need the Mac mini and TV and are left for the user. Q10 (the stream-limit check) is still open. M6 stays *In progress* until they pass.
- **2026-10-06 (user):** every manual check passed on the Mac mini and TV: steps 1 and 4–7 and the *Manual verification* list. That includes the stream-limit check (Change Channel 3 times with 1 + 4 full) and lip sync with `video-timing-offset=0`. None of the *Risks* fallbacks were needed. M6 is Done.
