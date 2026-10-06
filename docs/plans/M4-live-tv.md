# M4 — Live TV (IPTV core)

| | |
|---|---|
| Status | Planned |
| Depends on | M2b (Settings framework), M3 (Keychain helper, PIN, outside-canvas hosting pattern) |
| Master plan decisions used | D2, D3, D6, D7, D8, D9, D10, D18, D19, D20, D22 (new), D23 (new) |
| Planned | 2026-10-06 |

## Goal

From the couch, with only the remote:

- **Settings → Live TV** takes the provider's M3U playlist URL from the **clipboard**, copied on the Mac or on an iPhone through Universal Clipboard. It is stored in the Keychain and the channels load. An optional **guide (XMLTV) URL** is pasted the same way. If the playlist names its own guide (`url-tvg` / `x-tvg-url`), that one is used by default. Settings shows the channel count, when the playlist and guide were last updated, and any error. It also has Refresh Now and Remove.
- The **Live TV** tile resumes the **last channel, full screen**. On first use, with no last channel, it opens the guide.
- **Full-screen player:**
  - Up/Down change channel and show a banner with the channel and its now/next programmes.
  - Select opens the guide.
  - Left/Right skip back/forward 10 s; Rewind/Fast-forward skip 30 s.
  - Play/Pause pauses live TV.
  - At least **5 minutes of rewind** is kept in memory (D7). A bar shows how far behind live you are and how much is buffered.
  - Back hides overlays, then leaves. Home leaves at any time.
- **Grid guide:**
  - Channels down the left, programmes on a 2-hour time grid, and the playing channel in a **preview window** at the top right. The selected programme's title, time and description sit at the top left.
  - Up/Down move between channels; Left/Right move between programmes.
  - Left from the programme airing now opens the **group list**.
  - Select plays that channel full screen.
- Video is decoded in hardware (VideoToolbox), and the display doesn't sleep while something plays.

The user's provider (the provider, verified 2026-10-06) is a small plain-M3U playlist of live HLS streams with no built-in guide; see *Research & findings*.

## Out of scope

- **Xtream Codes API sources.** The user's provider is plain M3U (no `player_api.php`). It can be added later if a provider needs it. The research is recorded below.
- Multiple EPG sources, manual channel ↔ EPG matching, favorites, hidden groups/channels, multiview, catch-up (**M6**). Catch-up isn't offered by the current provider.
- Typing URLs with the remote. Phone text entry is **M5** and can later fill the same Keychain items.
- Programme reminders, recordings (non-goal), search, channel numbers typed on a keypad, parental ratings.
- Mouse control inside Live TV. The keyboard, remote and controller cover it; the mouse still works everywhere else.
- Persisting channels between launches. The playlist is re-fetched at launch and when Live TV opens (D23).
- New `RemoteCommand` cases. Every Live TV action uses the existing ten (L10).

## Research & findings

### The user's provider (verified 2026-10-06 with a redacted summary script; no credentials left the Mac)

- The playlist URL is `https://iptv.example/app2/<18-char token>`. It returns `audio/x-mpegurl`, about **30 KB**, starting with a bare `#EXTM3U`. There is **no `url-tvg`/`x-tvg-url`**, so the provider supplies no guide.
- **118 `#EXTINF` entries** in 5 groups:
  - "Live Channels": 97 US sports networks (NFL Network, NBA TV, MLB Network, FanDuel Sports Network …).
  - "NBA Games": 10, "NHL Games": 8, "MLB Games": 2, "NFL Games": 1. These are event streams; game entries carry `tvg-type="movie"` and use the event name as `tvg-id`.
- **Attributes:**
  - `tvg-id` appears on all 118, but is empty on some channels (e.g. "Red Zone2", "PAC 12 Network").
  - `tvg-name` and `tvg-logo` on 97; `group-title` on all 118.
  - Duration is `#EXTINF:0`.
  - No `#EXTVLCOPT`/`#EXTGRP`.
- `tvg-id`s look like iptv-org channel ids, lowercased: `nflnetwork.us`, `nbatv.us`, `ballysportsdetroit.us`, `marqueesportsnetwork.us`. Match them case-insensitively.
- **Not Xtream.** `iptv.example` is a WordPress site (`player_api.php`, `get.php`, `xmltv.php` → 404). The stream host is a CDN: `https://stream-cdn.example/<43-char token>/<channel|perdias>/<id>/chunks.m3u8`, and `player_api.php` → 404 there too. Q3 is answered: plain M3U, no Xtream, no catch-up.
- **Every stream is live HLS:**
  - A media playlist of 10 × 4.004 s segments: a **40 s server window**, so the server offers no rewind of its own.
  - Segment URLs are relative, on the same host, `video/m2ts`.
  - The playlist and segments answered 200 to user agents `libmpv`, `Lavf/61.7.100`, `mpv 0.40.0` and none.
- **Measured stream:** H.264 1280×720, about 2.6–4.5 Mb/s (mpv `raw-input-rate` 0.47–0.58 MB/s).
- Logos are on third-party hosts (`gamepanel.work`, `nflhd.tv`, `imgx.fubo.tv`).

### The chosen guide: guide-source US2 (user choice 2026-10-06; measured the same day)

- URL `https://guide-source.online/guide-source/guide-source_US2.xml.gz`: 6.5 MB gzip, 77 MB XML, **769 channels and 80,531 programmes**. Times look like `20261005050000 +0000`. Served as `application/octet-stream`.
- Its ids look like `NFL.Network.HD.us2`, `FS1.Fox.Sports.1.HD.us2`, `NBC.Sports.Bay.Area.Plus.us2`; display names like "NBC Sports Bay Area HD".
- Measured against the user's 97 "Live Channels" (the game entries have no guide anywhere):

  | Matching | Channels with guide data |
  |---|---|
  | `tvg-id` equal to an EPG id | **0**: the playlist uses iptv-org-style ids (`nflnetwork.us`), US2 doesn't |
  | L6 exact normalized names | **28** (NFL Network, NBA TV, ESPN, TBS, Yes Network, NBC Sports Boston …) |
  | L6 + the `epg-overrides.json` draft below (L17) | **58**, and every matched channel has programmes |

- **Not in US2 at all (39):** the 21 FanDuel Sports Network regionals, NESN, TVG, Red Zone2, PAC 12, TSN 1–5, Star Sports ×3, Sky Sports Cricket/Golf, SuperSport, Astro Cricket, Premier Sports.
  - `guide-source_ALL_SOURCES1.xml.gz` (194 MB gzip, about 2 GB XML, 27,393 channels) lists the FanDuel regionals (e.g. `FanDuel.Sports.Indiana.us`), BTN, HGTV, TSN and Star Sports.
  - `guide-source_US_SPORTS1` holds team/event channels (`NBA-LosAngelesLakers.us`), not networks.
  - Adding a second source for the gaps is M6 (multiple EPG sources). Pasting ALL_SOURCES1 instead of US2 would work with this design (streaming parse, only matched channels kept), but downloads 194 MB per refresh.
- **Fuzzy matching was tested and rejected.** Token-subset matching reached 55/97 on US2 and 94/97 on ALL_SOURCES1, but with many **wrong** matches:
  - "Red Zone" → `Red.TV.rs` (Serbia); "BTN Network" → a Korean channel.
  - "Marquee Network" → `Marquee.TV.HD.gr`; "CBS" → `CBS.News.us`.
  - "AT&T Pittsburgh" → `and.TV.us2`; "NBC Sports Chicago" → `NBC.Sports.4K.us2`.

  Wrong programmes are worse than none, so L6 stays exact and L17 adds explicit mappings.
- Normalizing `+` as "plus" matters: without it, "NBC Sports Bay Area+" matched the main feed `NBC.Sports.Bay.Area.HD.us2` instead of `NBC.Sports.Bay.Area.Plus.us2`.

**Draft `epg-overrides.json` for the user's playlist and US2.** Every target id was checked to exist in US2 and have programmes. The keys are channel names as in the playlist. The executor installs this file during the step 10 manual check, in `~/Library/Application Support/MMTVL/`:

```json
{
  "Red Zone": "NFL.RedZone.HD.us2",
  "Marquee Network": "Marquee.Sports.Network.HD.us2",
  "Root Sports NW": "ROOT.Sports.Northwest.HD.us2",
  "MASN": "MASN.-.Mid.Atlantic.Sports.Network.us2",
  "MASN2": "MASN2.-.Mid.Atlantic.Sports.Network.2.HD.us2",
  "NESN2": "NESN+.New.England.Sports.Network.Plus.us2",
  "SportsNet Lakers": "Spectrum.SportsNet.Lakers.HD.us2",
  "SportsNet LA Dodgers": "Spectrum.SportsNet.LA.Dodgers.HD.us2",
  "Space City Home": "Space.City.Home.Network.HD.us2",
  "AT&T Pittsburgh": "SportsNet.Pittsburgh.HD.us2",
  "MSG": "MSG.National.us2",
  "MSG+": "MSG.Plus.us2",
  "NBC Sports Chicago": "CHSN.Chicago.Sports.Network.us2",
  "Monumental Sports": "Monumental.Sports.Network.HD.us2",
  "Fox Sports 1": "FS1.Fox.Sports.1.HD.us2",
  "Fox Sports 2": "FS2.Fox.Sports.2.HD.us2",
  "BTN Network": "Big.Ten.Network.HD.us2",
  "NBC SNY": "SNY.SportsNet.New.York.HD.us2",
  "ACCN": "ACC.Network.us2",
  "Weather Channel": "The.Weather.Channel.HD.us2",
  "Fox News": "Fox.News.Channel.HD.us2",
  "CNN News": "CNN.HD.us2",
  "CBS": "CBS.Sports.Network.HD.us2",
  "TruTV East": "truTV.HD.us2",
  "Animal Planet East": "Animal.Planet.HD.us2",
  "Discovery Science": "Science.Channel.HD.us2",
  "History Channel": "History.HD.us2",
  "A&E NETWORK": "A.and.E.HD.East.us2",
  "HGTV": "Home.and.Garden.Television.HD.us2",
  "beIN USA": "beIN.Sports.USA.HD.us2"
}
```

Mapping notes:

- "CBS" is the playlist's name for CBS Sports Network (its `tvg-id` is `cbssportsnetworkusa.us`).
- "NESN2" is NESN+.
- "Discovery Science" is now Science Channel.
- "NBC Sports Chicago" became CHSN.
- "AT&T Pittsburgh" is SportsNet Pittsburgh.
- "MSG" maps to MSG National (MSG's zone feeds are separate EPG channels).

### libmpv / MPVKit (verified on this Mac, 2026-10-06, by a throwaway spike against a real channel)

- **MPVKit `1.0.0`** (2026-07-25) bundles mpv v0.41.0, FFmpeg n8.1.2, libplacebo 7.360.1 and MoltenVK 1.4.2. SPM `https://github.com/mpvkit/MPVKit.git`. Docs: [release](https://github.com/mpvkit/MPVKit/releases/tag/1.0.0), [Package.swift](https://github.com/mpvkit/MPVKit/blob/1.0.0/Package.swift).
  - Product **`MPVKit` is LGPL v3**. `MPVKit-GPL` only adds GPL bits and SMB; don't use it.
  - It ships prebuilt static xcframeworks: about **350 MB to download once**. The Debug app grew to about 55 MB.
  - Module: **`import Libmpv`**. Client API 2.5.
- **Builds with Xcode 27 and Swift 6.** In a scratch copy of this project, MPVKit + GRDB were added with exactly the pbxproj edits in step 1. With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, a probe file compiled **with no errors or warnings**. The full test suite (163 tests) passed. The probe contained:
  - a `nonisolated` mpv handle class with a wakeup callback;
  - a `nonisolated` `CAOpenGLLayer` subclass;
  - a GRDB record and store;
  - a `nonisolated` `XMLParserDelegate`;
  - `import zlib`;
  - an IOKit power assertion.
- **Rendering: the render API with OpenGL works; use it** (D22). The spike used:
  - `vo=libmpv`;
  - `mpv_render_context_create` with `MPV_RENDER_API_TYPE_OPENGL` inside a `CAOpenGLLayer`. The render context was created in `copyCGLContext(forPixelFormat:)`, with a 3.2-core, double-buffered, accelerated pixel format;
  - `mpv_render_context_render` with the current FBO and `FLIP_Y=1` in `draw(inCGLContext:…)`;
  - an update callback that does `DispatchQueue.main.async { layer.setNeedsDisplay() }`.

  Results:
  - A screenshot showed the channel's picture correctly. The layer drew about 55 times a second.
  - `hwdec-current` was `videotoolbox`.
  - **After a window resize, mpv rendered at the new size** (`osd-dimensions` followed).
  - mpv logs `after creating texture: OpenGL error INVALID_FRAMEBUFFER_OPERATION` a few times at start and after a resize. It is harmless: the picture is fine.
  - The spike didn't set `contentsScale`, so it rendered at 1× on a Retina screen. The plan sets it (step 7).
- **Why not MPVKit's Metal demo path** (`vo=gpu-next`, `gpu-context=moltenvk`, `wid` = CAMetalLayer):
  - Its README calls it an unofficial patch.
  - **Layer resizes are ignored** ([MPVKit #3](https://github.com/mpvkit/MPVKit/issues/3), open), which would break the guide's preview window.
  - mpv's `client.h` recommends the render API over `wid`.
  - OpenGL is deprecated on macOS but present in the macOS 27 SDK. IINA, the main mpv front end on macOS, uses the same approach.
- **Rewind from the cache works on live HLS (spike).** Options: `cache=yes`, `demuxer-max-back-bytes=512MiB`, `demuxer-max-bytes=64MiB`, `hwdec=videotoolbox`.
  - After 75 s of live play, `seek -60 relative` put playback **74 s behind** `cache-end`, beyond the server's 40 s window. It played on from there.
  - **Pause 30 s → resume** worked. While paused, the demuxer kept downloading (`fw-bytes` grew), and after resuming playback was 107 s behind.
  - `seek <cache-end − 2> absolute` jumped to live but **underran** (`paused-for-cache`, audio underruns). mpv naturally plays **10–14 s behind `cache-end`**, so jump to `cache-end − 10` instead (L8).
  - `seekable`/`partially-seekable` read `no` the whole time, yet in-cache seeks worked. mpv adds `SEEK_CACHED` for unseekable demuxers. **Don't set `force-seekable`**, and don't use `seekable` to decide anything.
  - `mpv_get_property_string(h, "demuxer-cache-state")` returns **JSON**. Spike sample:
    ```json
    {"cache-end":92.053667,"reader-pts":21.397334,"cache-duration":70.656333,"eof":false,"underrun":false,"idle":false,
     "total-bytes":28251520,"fw-bytes":23299120,"raw-input-rate":248030,"bof-cached":true,"eof-cached":false,
     "seekable-ranges":[{"start":0.000000,"end":91.437667}], "ts-per-stream":[…]}
    ```
    `time-pos` and the range timestamps share one timeline (start ≈ 0 at the first frame).
- **mpv manual facts** ([manual](https://mpv.io/manual/stable/), demux.c v0.41.0):
  - `demuxer-max-bytes` (forward) defaults to 150 MiB; `demuxer-max-back-bytes` to 50 MiB.
  - `demuxer-donate-buffer=yes` (default) lets the back buffer use unused forward space.
  - While paused, the demuxer keeps reading until the forward buffer is full, then stops reading. After that, a live server may drop the connection (server-dependent).
  - `seek <t> absolute` is exact by default; `+keyframes` is faster.
  - In libmpv, `idle=yes` by default, and input media keys and `media-controls` are off. **Leave them off**; MMTVL's InputRouter owns media keys.
- **libmpv threading** (`client.h`):
  - The API is thread-safe.
  - **Only one thread may call `mpv_wait_event` per handle.**
  - **The wakeup callback must not call any mpv function**; it only signals a queue that drains `mpv_wait_event(h, 0)` until `MPV_EVENT_NONE`.
  - Read `MPV_FORMAT_FLAG` as `Int32`, not `Bool`.
  - Free the render context before `mpv_terminate_destroy`.
  - Only one render context can exist per mpv core.
  - `LC_NUMERIC` must be "C". It is in a Cocoa app that never calls `setlocale`.
- **Events:**
  - `MPV_EVENT_START_FILE`, `FILE_LOADED`, `PLAYBACK_RESTART` (playback actually running).
  - `END_FILE`, with `mpv_event_end_file.reason`: `EOF`=0, `STOP`=2, `QUIT`=3, `ERROR`=4 (`error` holds an `MPV_ERROR_*`), `REDIRECT`=5. EOF also happens when the connection drops. `loadfile … replace` ends the previous file with reason `STOP`.
  - `SHUTDOWN`, `LOG_MESSAGE`.

### GRDB (verified 2026-10-06)

- **GRDB.swift `7.11.1`** (2026-06-18), MIT, SPM `https://github.com/groue/GRDB.swift.git`. Requires Swift 6.1+.
- Use **`DatabasePool`** (WAL mode: reads run alongside an import's write). Use `DatabaseQueue()` in memory for tests.
- **With default MainActor isolation**, declare records as `nonisolated struct … : Codable, Sendable, FetchableRecord, PersistableRecord`, with every conformance on the declaration and `Columns` inside the type ([GRDB #1823](https://github.com/groue/GRDB.swift/issues/1823)). Verified in the scratch project.
- Bulk insert: one `write {}` is one transaction. Record `insert` uses cached statements. Measured: 400k rows in about 2 s; ~5k rows is instant.
- **Pitfall:** in a sync-looking closure context, `try await pool.read {}` can silently pick the *sync* overload. The sign is the warning "no 'async' operations occur within 'await'"; treat it as an error.

### XMLTV and gzip (verified 2026-10-06)

- **XMLTV** ([DTD](https://github.com/XMLTV/xmltv/blob/master/xmltv.dtd)):
  - Structure: `<tv>` then `<channel id>` elements (`display-name`+, `icon src`), **then** `<programme start stop? channel>` elements with `title`+, `sub-title`*, `desc`*, `category`*, `episode-num system="xmltv_ns|onscreen"`*.
  - Times are `YYYYMMDDhhmmss` (or a leading part of it), optionally followed by ` ±hhmm`. **No offset means UTC.**
  - `xmltv_ns` is zero-based `season.episode.part` (`1.0.0/1` = S2 E1).
  - A missing `stop` comes from the channel's next programme.
- **Typical sizes:** `.xml.gz` is common and served as `application/octet-stream`, so URLSession won't decompress it. guide-source US2 is 6.5 MB gz / 77 MB raw / 80k programmes; ALL_SOURCES1 is 194 MB gz.
- **Foundation `XMLParser` streams:**
  - 200 MB parses in about 1.8 s at 11 MB RSS, from `XMLParser(contentsOf:)` or `XMLParser(stream:)`.
  - `parse()` is synchronous; run it off main.
  - Keep `shouldResolveExternalEntities = false`; files carry a DOCTYPE.
  - Text arrives in several `foundCharacters` chunks.
  - **The delegate must be a `nonisolated final class`**; a MainActor delegate doesn't compile when used off main.
- **gzip:** `import zlib` works (the SDK has a `zlib` module). `inflateInit2_(&s, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))` auto-detects the gzip header; a round trip was verified. Apple's Compression framework (`COMPRESSION_ZLIB`) is raw DEFLATE and **fails on gzip**. Don't use it.

### Swift concurrency in this project (verified in the scratch project)

- With `SWIFT_APPROACHABLE_CONCURRENCY = YES`, a plain `nonisolated async` function **runs on the caller's actor**. Called from the main actor, it runs **on the main thread**.
- A `@concurrent` function runs off main (test: `pthread_main_np() == 0`).
- **CPU-heavy work (XMLTV parsing, gunzip) must be in a `@concurrent` function**, or it blocks the UI.

### Clipboard privacy (SDK, MacOSX27.0.sdk `NSPasteboard.h`)

- macOS 15.4+ has `NSPasteboard.accessBehavior` (`.default/.ask/.alwaysAllow/.alwaysDeny`).
- Programmatic reads of the general pasteboard that aren't "user originated and paste related" (⌘V, a Paste menu) **may show a system alert** the first time. After that, the app appears in System Settings, where the user can choose Always Allow.
- The spike read `NSPasteboard.general` from a command-line tool on macOS 27 with no alert. Whether MMTVL.app gets the alert is **unverified**; check in step 6.

### Xtream Codes (for later; not used in M4)

`player_api.php?username&password` returns `user_info`/`server_info`. Other endpoints: `&action=get_live_categories`, `&action=get_live_streams` (fields may be string or number), `xmltv.php`, and stream URLs like `/live/U/P/<id>.ts|m3u8`. Sources: [ektotv/xtream-api types](https://github.com/ektotv/xtream-api/blob/main/src/types.ts), [IPTVnator mock](https://github.com/4gray/iptvnator/tree/master/apps/xtream-mock-server/src/app).

### M3U details ([Kodi IPTV Simple README](https://github.com/kodi-pvr/pvr.iptvsimple/blob/Omega/README.md), [iptv-playlist-parser](https://github.com/freearhey/iptv-playlist-parser/blob/master/src/index.js))

- Header attributes: `url-tvg` or `x-tvg-url`. The value may hold several URLs separated by commas.
- Entry attributes: `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, `tvg-chno`, `tvg-type`, `catchup*`.
- `#EXTGRP:` sets the group for the following entries until changed; `group-title` wins over it.
- **The display name is everything after the first comma outside quotes, trimmed.**
- Xtream-made playlists mark VOD by `/movie/` and `/series/` in the URL path.

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL.xcodeproj/project.pbxproj` | changed | MPVKit 1.0.0 and GRDB 7.11.1 package products on the **app target only** (step 1). |
| `MMTVL.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | new | Pins packages. Commit it. |
| `MMTVL/IPTV/Sources/M3UParser.swift` | new | Pure M3U parser → `M3UPlaylist`. |
| `MMTVL/IPTV/Sources/Channel.swift` | new | `Channel` and `ChannelList` (playlist → channels, ids, groups). |
| `MMTVL/IPTV/Sources/IPTVSourceStore.swift` | new | Keychain-backed playlist/guide URLs; in-memory variant for tests. |
| `MMTVL/IPTV/Sources/ClipboardURL.swift` | new | Pure clipboard text → URL validation. |
| `MMTVL/IPTV/Sources/IPTVNetwork.swift` | new | Injectable `fetchText` and `download` closures; `.live` uses URLSession. |
| `MMTVL/IPTV/EPG/XMLTVDate.swift` | new | Pure XMLTV timestamp parsing. |
| `MMTVL/IPTV/EPG/Programme.swift` | new | `Programme` and `EPGChannel` (GRDB records). |
| `MMTVL/IPTV/EPG/XMLTVParser.swift` | new | Streaming SAX parser (nonisolated delegate). |
| `MMTVL/IPTV/EPG/Gunzip.swift` | new | File-to-file gzip inflate with zlib. |
| `MMTVL/IPTV/EPG/EPGMatcher.swift` | new | Pure channel ↔ EPG id matching and name normalization. |
| `MMTVL/IPTV/EPG/EPGStore.swift` | new | GRDB store: migrations, replace, queries. |
| `MMTVL/IPTV/EPG/GuideImporter.swift` | new | `@concurrent` download → gunzip → parse → match → store. |
| `MMTVL/IPTV/IPTVState.swift` | new | `iptv-state.json`: last channel, last group, guide refresh bookkeeping. Also the `epg-overrides.json` file name (L17). |
| `MMTVL/IPTV/IPTVLibrary.swift` | new | `@Observable` channels, groups, statuses, refresh policy, programme queries, Settings status. |
| `MMTVL/IPTV/Player/MPVOptions.swift` | new | The mpv option list (D7 buffer sizes). |
| `MMTVL/IPTV/Player/MPVHandle.swift` | new | `nonisolated` libmpv wrapper: create, options, commands, properties, event thread. |
| `MMTVL/IPTV/Player/MPVVideoView.swift` | new | `MPVVideoLayer` (CAOpenGLLayer, render API) and its hosting `NSView`. |
| `MMTVL/IPTV/Player/Timeshift.swift` | new | Pure rewind math from `demuxer-cache-state` JSON. |
| `MMTVL/IPTV/Player/SleepAssertion.swift` | new | IOKit display-sleep assertion. |
| `MMTVL/IPTV/Player/LivePlayer.swift` | new | `LivePlayer` protocol, `PlayerState`, `MPVPlayerController`. |
| `MMTVL/IPTV/Guide/GuideTimeline.swift` | new | Pure time-window and cell-geometry math. |
| `MMTVL/IPTV/Guide/GuideModel.swift` | new | Pure guide focus/navigation state. |
| `MMTVL/IPTV/Guide/GuideView.swift` | new | Guide layout on the canvas (info panel, preview frame, grid, group list). |
| `MMTVL/IPTV/LiveTVModel.swift` | new | `@Observable` Live TV screen: modes, channel zapping, overlays, command handling. `LiveTVHosting` protocol. |
| `MMTVL/IPTV/LiveTVView.swift` | new | `LiveTVRootView` (player view + scaled overlays), banner, timeshift bar, setup/loading/error screens. `CanvasGeometry`. |
| `MMTVL/Launcher/AppRouter.swift` | changed | `.liveTV` screen and routing; placeholder removed. |
| `MMTVL/Launcher/PlaceholderView.swift` | **deleted** | No internal destination uses it any more (L14). |
| `MMTVL/App/AppDelegate.swift` | changed | Create the library, store, player and Live TV model; launch refresh; Settings wiring. |
| `MMTVL/Settings/*` | changed | Live TV page, actions, status, confirm page. |
| `MMTVL/DesignSystem/Theme.swift` | changed | Guide and player overlay tokens. |
| `MMTVLTests/…` | new/changed | See *Tests*. |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | changed | Wrap-up. |

`MMTVL/IPTV/` and its subfolders are picked up by the file-system-synchronized group, so don't add file references by hand. Only step 1 edits `project.pbxproj`.

### Local decisions

- **L1. Plain M3U only.** The provider isn't Xtream (verified). Supporting one source type keeps M4 small; Xtream can be a later addition.
- **L2. Source URLs come from the clipboard** (user choice, 2026-10-06). The paste rows read `NSPasteboard.general` on Select, validate, and save to the Keychain (accounts `iptv-playlist-url` and `iptv-guide-url`; service `dev.mmtvl.launcher`).
  - **Never log or display a full source or stream URL.** They carry tokens. Show and log only the host.
- **L3. The guide source** (user choice, "provider's EPG, overridable"):
  - A pasted guide URL wins.
  - Otherwise use the first `url-tvg`/`x-tvg-url` of the playlist.
  - Otherwise there is no guide: the grid shows "No information" rows, and Settings explains how to add one.
  - The current provider has no playlist guide. The user chose **guide-source US2** (`https://guide-source.online/guide-source/guide-source_US2.xml.gz`), pasted in Settings like the playlist.
- **L4. Channels are not stored on disk** (D23). The playlist is fetched:
  - at launch, if a source is set;
  - when Live TV opens, if the last fetch is more than **10 minutes** old (game entries come and go);
  - on Refresh Now;
  - once more after a playback failure.

  The parsed list lives in memory. Only the guide goes to SQLite (D8).
- **L5. Guide refresh:**
  - Runs at launch and when Live TV opens, if the last successful import is more than **12 hours** old or the guide URL changed (a SHA-256 of the URL is stored, never the URL). Also on Refresh Now, and after pasting a URL.
  - Import keeps:
    - programmes overlapping **[now − 6 h, now + 4 days]**;
    - only for EPG channels matched to a playlist channel at import time;
    - all `<channel>` entries (id + display names), so a later playlist change can re-match by name without a download.
- **L6. EPG matching** (`EPGMatcher`), in this order:
  1. An `epg-overrides.json` entry (L17) whose target id exists in the guide.
  2. `tvg-id` equals an EPG channel id, ignoring case.
  3. The normalized `tvg-name` or name equals a normalized display name. The first EPG channel in file order wins. Normalizing:
     - lowercases and folds diacritics;
     - replaces `&` with " and " and `+` with " plus ";
     - splits on non-alphanumerics;
     - drops the tokens `hd fhd uhd sd 4k hevc`;
     - joins the rest.
  4. Otherwise there is no guide data.
  - **No fuzzy matching** (token subsets, contains, edit distance). It was measured and produced wrong channels (see *The chosen guide*). A manual matching UI is M6; until then L17 covers it.
- **L17. `epg-overrides.json`** is a hand-edited map in the D10 directory: `{ "<channel name or tvg-id>": "<EPG channel id>" }`.
  - Keys match a playlist channel's name first, then its `tvg-id`, both case-insensitively. Use names: the user's playlist reuses some `tvg-id`s for different channels.
  - It is read through `JSONConfigFile<[String: String]>` (default `{}`; a corrupt file → `.bak` + `{}`, as for every config file) on every rematch, so hand edits apply on the next Refresh Now. **No relaunch needed.**
  - An entry whose target isn't in the current guide is ignored (logged at debug level), and the channel falls through to rules 2–3.
  - Override targets are part of the import's wanted ids, so their programmes are kept.
  - The draft for the user's setup is in *The chosen guide*. M6's matching UI will write the same file.
- **L7. Player = one mpv core for the app's lifetime**, created on the first play, with the render API (OpenGL) in a `CAOpenGLLayer` (D22).
  - Leaving Live TV, system wake and Home all **stop** playback (`stop`). Coming back reloads the last channel at live, so the rewind buffer doesn't survive leaving. That fits the 5-connection limit and saves bandwidth; it differs from D18's "leave running" on purpose, because a live stream left playing in the background has no value.
  - The core is never destroyed (M6 multiview will add teardown).
- **L8. Rewind (D7):**
  - `cache=yes`, `demuxer-max-back-bytes=512MiB`, `demuxer-max-bytes=256MiB`.
  - At the measured ~4 Mb/s, 512 MiB is about **17 min** of rewind, and still about 8 min at 8 Mb/s. The forward buffer allows about 8 min of pause before the demuxer stops reading.
  - "Behind live" = `cache-end − time-pos − 15` (mpv's natural 10–14 s lag counts as live).
  - Jump to live seeks to `cache-end − 10`.
  - Seeks use `absolute+keyframes`, clamped to `[rangeStart + 1, cache-end − 10]`.
- **L9. Player controls:**

  | Command | Full-screen player | Guide |
  |---|---|---|
  | Up / Down | previous / next channel in the current group (wraps) + banner | move row |
  | Left / Right | −10 s / +10 s + timeshift bar | previous / next programme; Left on the programme airing now → group list |
  | Rewind / Fast-forward | −30 s / +30 s + bar | same as Left / Right (no paging) |
  | Select | open the guide (on an error screen: retry) | play the focused row's channel full screen |
  | Play/Pause | pause / resume (bar stays while paused) | pause / resume the preview |
  | Back | hide banner/bar if shown, else leave Live TV | close the group list, else back to the player (or leave when nothing plays) |
  | Home | leave Live TV (router) | leave Live TV (router) |

  - Changing channel always starts at live.
  - Fast-forwarding into the live edge clamps there; that is how you return to live. Changing channel also returns to live.
- **L10. No new `RemoteCommand`s.** Channel up/down = Up/Down in the player. The remote isn't chosen yet (Q1), and every action fits the existing ten. M7's binding editor can revisit.
- **L11. Overlays:**
  - The banner (channel, now/next) shows for **5 s** after a channel change or when the player opens.
  - The timeshift bar shows for 5 s after a seek and stays while paused. It hides after 5 s even when behind live; a small "−m:ss" badge stays in the top-right corner while behind live.
  - Back hides whatever is shown first.
- **L12. The guide** shows:
  - **6 rows** and a **2-hour** window starting at the half hour.
  - It can look **24 h** ahead and can't go into the past: the left edge is the programme airing now.
  - An **"All Channels"** group comes first when the playlist has more than one group.
  - The selected group is remembered (`iptv-state.json`).
  - Select plays the row's channel even on a future programme. There are no reminders.
- **L13. Playback failure:**
  - When `END_FILE` comes with `eof` or `error` while playing or loading, the player retries the same URL **twice**, 2 s apart.
  - Then `LiveTVModel` refreshes the playlist once and plays the channel's (possibly new) URL.
  - If that fails, it shows "Can't play this channel" (Select retries).
  - `stop`-reason ends are ignored.
- **L14. The placeholder screen is removed.** Every internal destination (YouTube, Live TV, Settings) is now real. `Screen.placeholder` and `PlaceholderView.swift` go.
- **L15. A display-sleep assertion** (`kIOPMAssertionTypePreventUserIdleDisplaySleep`) is held while the player is `loading` or `playing`, and released when paused, stopped or failed. This is the "sleep assertions during playback" item M2 deferred to M4.
- **L16. The video view sits outside the scaled canvas** (as YouTube, M3 L4), at a frame computed from canvas coordinates: the full window in player mode, `Theme.guidePreviewRect` scaled in guide mode. Overlays are SwiftUI on the scaled canvas above it.

### Key types

```swift
// IPTV/Sources/M3UParser.swift
nonisolated struct M3UEntry: Equatable, Sendable {
    var name: String                    // after the first comma outside quotes, trimmed; "" if missing
    var attributes: [String: String]    // keys lowercased, e.g. "tvg-id"
    var group: String?                  // group-title, else the current #EXTGRP, else nil
    var url: String                     // the URL line, trimmed
    var tvgID: String? { nonEmpty("tvg-id") }
    var tvgName: String? { nonEmpty("tvg-name") }
    var logo: String? { nonEmpty("tvg-logo") }
}
nonisolated struct M3UPlaylist: Equatable, Sendable {
    var guideURLs: [URL]                // header url-tvg / x-tvg-url, split on ",", http(s) only
    var entries: [M3UEntry]
}
nonisolated enum M3UParser {
    enum ParseError: Error, Equatable { case notAPlaylist }
    static func parse(_ text: String) throws -> M3UPlaylist
}
```

Parser rules:

- Strip a leading BOM (`\u{FEFF}`). Split lines on `\n`, then trim `\r` and whitespace. Skip empty lines.
- A line starting with `#EXTM3U` holds the header attributes.
- `#EXTINF:` starts a pending entry:
  - Attributes match `([A-Za-z0-9_-]+)="([^"]*)"`.
  - The name is the text after the first `,` that is outside double quotes.
- `#EXTGRP:<name>` sets the current group. Other `#` lines are ignored.
- A non-`#` line is the URL of the pending entry; then clear the pending entry. A URL line without a pending `#EXTINF` is ignored.
- Throw `.notAPlaylist` only when there is no `#EXTM3U` line **and** no `#EXTINF` line. Network errors return HTML, which must fail.

```swift
// IPTV/Sources/Channel.swift
nonisolated struct Channel: Identifiable, Hashable, Sendable {
    let id: String          // see ChannelList.make
    let number: Int         // 1-based position among kept channels
    let name: String
    let group: String       // entry.group ?? "Other"
    let tvgID: String?
    let tvgName: String?
    let logoURL: URL?
    let streamURL: URL
}
nonisolated enum ChannelList {
    static let allChannelsGroup = "All Channels"
    /// Keeps entries whose URL is http(s) and not VOD (path contains "/movie/" or "/series/", or ends in .mp4/.mkv/.avi/.mov).
    /// id: "id:" + tvgID.lowercased(), else "name:" + name.lowercased(); duplicates get "#2", "#3"… in order.
    /// name: entry.name, else tvgName, else "Channel \(number)".
    static func make(from playlist: M3UPlaylist) -> [Channel]
    /// Distinct groups in first-appearance order.
    static func groups(of channels: [Channel]) -> [String]
    /// [allChannelsGroup] + groups when there is more than one group, else the groups.
    static func guideGroups(of channels: [Channel]) -> [String]
    /// All channels for allChannelsGroup, else that group's channels, in playlist order.
    static func channels(in group: String, of channels: [Channel]) -> [Channel]
}
```

```swift
// IPTV/Sources/IPTVSourceStore.swift: closure struct like PINStore.
struct IPTVSourceStore {
    static let playlistAccount = "iptv-playlist-url"
    static let guideAccount = "iptv-guide-url"
    var playlistURL: () -> URL?             // Keychain errors: log, nil
    var setPlaylistURL: (URL) throws -> Void
    var guideURL: () -> URL?
    var setGuideURL: (URL?) throws -> Void  // nil removes
    var removeAll: () throws -> Void
    static let keychain: IPTVSourceStore
    static func inMemory(playlist: URL? = nil, guide: URL? = nil) -> IPTVSourceStore  // small final class box
}

// IPTV/Sources/ClipboardURL.swift
nonisolated enum ClipboardURL {
    enum Problem: Error, Equatable { case empty, notAWebAddress }
    /// First non-empty line, trimmed; must be http/https with a non-empty host.
    static func parse(_ text: String?) -> Result<URL, Problem>
    static func message(for problem: Problem) -> String
    // .empty → "The clipboard is empty. Copy the URL first."
    // .notAWebAddress → "The clipboard doesn't hold a web address."
}

// IPTV/Sources/IPTVNetwork.swift
struct IPTVNetwork {
    /// GET as text (UTF-8, lossy). Throws IPTVNetworkError.http(status) for non-2xx. Timeout 30 s.
    var fetchText: @Sendable (URL) async throws -> String
    /// Downloads to a temporary file that the caller then owns. Throws for non-2xx. Timeout 120 s.
    var download: @Sendable (URL) async throws -> URL
    static let live: IPTVNetwork   // URLSession(configuration: .ephemeral)-based; move the download to
                                   // FileManager.default.temporaryDirectory/UUID before returning
}
nonisolated enum IPTVNetworkError: Error, Equatable { case http(Int) }
```

```swift
// IPTV/EPG/XMLTVDate.swift
nonisolated enum XMLTVDate {
    /// "20261005143000 +0000", "20261005143000", "202610051430 -0500", "20261005143000+0100".
    /// Needs at least YYYYMMDDhhmm; missing seconds = 0; missing offset = UTC. nil when malformed.
    static func parse(_ string: String) -> Date?
}

// IPTV/EPG/Programme.swift
nonisolated struct Programme: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "programme"
    var id: Int64?
    var channelID: String        // EPG channel id, lowercased
    var start: Date
    var stop: Date
    var title: String
    var subtitle: String?
    var summary: String?         // <desc>
    var category: String?        // first <category>
    var episode: String?         // onscreen text, else xmltv_ns as "S2 E1"
    enum Columns { static let channelID = Column(CodingKeys.channelID); static let start = Column(CodingKeys.start); static let stop = Column(CodingKeys.stop) }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
nonisolated struct EPGChannel: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "epgChannel"
    var id: String               // lowercased
    var names: [String]          // display-names in file order (GRDB stores the array as JSON text)
}
```

```swift
// IPTV/EPG/XMLTVParser.swift
nonisolated final class XMLTVParser: NSObject, XMLParserDelegate {
    struct Result: Sendable { var channels: [EPGChannel]; var programmes: [Programme] }
    /// `wantedIDs` is called once, at the first <programme> (the DTD puts every <channel> first), with the
    /// channels read so far. It returns the lowercased EPG ids to keep programmes for.
    /// Keeps programmes overlapping `window`. Fills a missing stop with the next programme's start on the same
    /// channel, or start + 30 min for the last one. Throws the parser's error when parse() fails.
    static func parse(fileURL: URL, window: DateInterval, wantedIDs: ([EPGChannel]) -> Set<String>) throws -> Result
}
```

Parser details:

- Accumulate `foundCharacters` per element.
- Keep only the **first** `title`, `sub-title`, `desc` and `category` of a programme.
- `episode-num`: prefer `system="onscreen"` text as is. Otherwise convert `xmltv_ns` `"a.b.c"`: season = a + 1, episode = b + 1, ignoring `/total` parts and empty fields. Examples: `"1.0.0/1"` → `"S2 E1"`; `".4."` → `"E5"`.
- Drop programmes with an unparseable `start`, a missing channel, or a channel not in the wanted set.
- If `<channel>` elements appear **after** programmes, add them to `channels` but don't re-evaluate `wantedIDs` (log once).

```swift
// IPTV/EPG/Gunzip.swift
nonisolated enum Gunzip {
    /// First two bytes are 1F 8B.
    static func isGzip(_ url: URL) throws -> Bool
    /// Streams `source` → `destination` in 256 KB chunks with inflateInit2_(…, 15 + 32, …).
    /// On Z_STREAM_END with input left (concatenated members), inflateReset and continue. Throws on zlib errors.
    static func decompress(_ source: URL, to destination: URL) throws
}

// IPTV/EPG/EPGMatcher.swift
nonisolated enum EPGMatcher {
    static func normalize(_ name: String) -> String
    /// Channel.ID → EPG id (lowercased), per L6. `overrides` is epg-overrides.json as read (keys and values in any case).
    static func match(_ channels: [Channel], to epgChannels: [EPGChannel], overrides: [String: String] = [:]) -> [Channel.ID: String]
}

// IPTV/EPG/EPGStore.swift
nonisolated final class EPGStore: Sendable {
    init(writer: any DatabaseWriter) throws          // runs migrations
    /// DatabasePool at `url`. If opening or migrating fails, deletes the file (it is a cache) and tries once more.
    static func open(at url: URL) throws -> EPGStore
    static func inMemory() throws -> EPGStore        // DatabaseQueue(); tests use this, so tests never import GRDB
    static var defaultURL: URL                       // LaunchItemStore.defaultDirectory/"guide.sqlite"
    /// One transaction: delete everything, insert all.
    func replaceAll(channels: [EPGChannel], programmes: [Programme]) async throws
    func channels() async throws -> [EPGChannel]
    /// Programmes whose channelID is in `ids` and that overlap `interval`, grouped by channelID, sorted by start.
    func programmes(channelIDs: Set<String>, overlapping interval: DateInterval) async throws -> [String: [Programme]]
    func programmeCount() async throws -> Int
    func removeAll() async throws
}
```

Schema (migration `"v1"`):

- `epgChannel`: `id TEXT PRIMARY KEY`, `names TEXT NOT NULL`.
- `programme`: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `channelID TEXT NOT NULL`, `start DATETIME NOT NULL`, `stop DATETIME NOT NULL`, `title TEXT NOT NULL`, `subtitle TEXT`, `summary TEXT`, `category TEXT`, `episode TEXT`.
- Index `programme_on_channel_start` on `(channelID, start)`.

Overlap query: `channelID IN ids AND start < interval.end AND stop > interval.start`.

```swift
// IPTV/EPG/GuideImporter.swift
nonisolated enum GuideImporter {
    struct Outcome: Sendable, Equatable { var programmeCount: Int; var matchedChannels: Int }
    /// MUST be @concurrent: parsing a big file must not run on the main actor.
    /// download → (gunzip if gzip) to Caches/MMTVL/guide.xml → parse with window
    /// [now − 6 h, now + 4 d] and wantedIDs = Set(EPGMatcher.match(channels, to: parsedChannels, overrides: overrides).values)
    /// → store.replaceAll. Deletes the temporary files afterwards (also on error).
    @concurrent static func importGuide(from url: URL, channels: [Channel], overrides: [String: String],
                                        store: EPGStore, network: IPTVNetwork, now: Date) async throws -> Outcome
}
```

```swift
// IPTV/IPTVState.swift: iptv-state.json through JSONConfigFile.
nonisolated struct IPTVState: Codable, Equatable, Sendable {
    static let fileName = "iptv-state.json"
    static let overridesFileName = "epg-overrides.json"   // L17
    var lastChannelID: String?
    var lastGroup: String?
    var lastGuideImport: Date?
    var lastGuideSourceHash: String?   // SHA-256 hex of the guide URL string (CryptoKit)
    // custom init(from:) with decodeIfPresent for every key, like AppSettings
}
```

```swift
// IPTV/IPTVLibrary.swift
@Observable
final class IPTVLibrary {
    enum Status: Equatable { case idle, loading, loaded(Date), failed(String) }
    enum GuideSource: Equatable { case none, playlist(URL), custom(URL) }

    private(set) var channels: [Channel] = []
    private(set) var playlistStatus: Status = .idle
    private(set) var guideStatus: Status = .idle
    private(set) var guideProgrammeCount = 0
    /// Bumped after every guide import or rematch; views reload programmes when it changes.
    private(set) var guideRevision = 0
    @ObservationIgnored private(set) var epgIDs: [Channel.ID: String] = [:]
    @ObservationIgnored private var playlistGuideURLs: [URL] = []
    @ObservationIgnored private var lastPlaylistFetch: Date?
    @ObservationIgnored var onStatusChange: (() -> Void)?    // AppDelegate → settings.refreshStatus()

    init(sources: IPTVSourceStore, store: EPGStore?, network: IPTVNetwork,
         stateFile: JSONConfigFile<IPTVState>, overridesFile: JSONConfigFile<[String: String]>,
         now: @escaping () -> Date = Date.init)

    var hasPlaylist: Bool
    var guideSource: GuideSource         // L3
    private(set) var state: IPTVState    // loaded from the state file at init; saved on every change
    func rememberChannel(_ id: Channel.ID)
    func rememberGroup(_ group: String)

    func refreshPlaylist() async          // no-op while .loading; parse; channels; rematch; status; onStatusChange
    func refreshPlaylistIfStale() async   // when channels are empty or lastPlaylistFetch > 10 min ago
    func refreshGuide() async             // no-op while .loading or when guideSource == .none (status .idle)
    func refreshGuideIfStale() async      // per L5
    func refreshAll() async               // playlist, then guide (forced)
    func setPlaylistURL(_ url: URL) async // save, clear channels, refreshAll
    func setGuideURL(_ url: URL?) async   // save (nil = use the playlist's), refreshGuide
    func removeSource() async             // Keychain removeAll, store.removeAll, reset state & memory

    /// Keyed by Channel.ID; channels without an EPG match are absent.
    func programmes(for channels: [Channel], in interval: DateInterval) async -> [Channel.ID: [Programme]]
    func nowNext(for channel: Channel, at date: Date) async -> (now: Programme?, next: Programme?)
}
```

- Errors become `.failed(message)`:
  - `IPTVNetworkError.http(s)` → "Server error (HTTP \(s))".
  - `.notAPlaylist` → "The address didn't return a playlist".
  - `URLError` → its `localizedDescription`.
  - `XMLParser` errors → "The guide file couldn't be read".
- **Logs use `url.host()` only** (L2), category "IPTV".
- `rematch()` (private): `epgIDs = EPGMatcher.match(channels, to: try await store.channels(), overrides: overridesFile.load())`, then `guideRevision += 1`. It runs after every playlist refresh and guide import. `refreshGuide()` also passes `overridesFile.load()` to the importer.
- The library stays usable with `store == nil` (the database failed to open): the guide stays `.failed("Guide storage unavailable")`.

```swift
// IPTV/Player/MPVOptions.swift
nonisolated enum MPVOptions {
    static let backBuffer = "512MiB"
    static let forwardBuffer = "256MiB"
    /// Applied in order with mpv_set_option_string before mpv_initialize. A failing option is logged and skipped.
    static let all: [(name: String, value: String)] = [
        ("vo", "libmpv"), ("hwdec", "videotoolbox"), ("ytdl", "no"),
        ("input-default-bindings", "no"), ("input-media-keys", "no"), ("media-controls", "no"),
        ("idle", "yes"), ("keep-open", "no"),
        ("cache", "yes"), ("demuxer-max-bytes", forwardBuffer), ("demuxer-max-back-bytes", backBuffer),
        ("network-timeout", "15"),
    ]
}

// IPTV/Player/MPVHandle.swift
nonisolated enum MPVEvent: Sendable, Equatable {
    enum EndReason: Sendable, Equatable { case eof, stop, quit, error, redirect, other }
    case fileLoaded, playbackRestart
    case endFile(EndReason, error: Int32)
    case shutdown
    case log(level: String, text: String)    // requested at "warn"; text with URLs redacted
}
nonisolated final class MPVHandle: @unchecked Sendable {
    let handle: OpaquePointer
    /// mpv_create, options, mpv_request_log_messages("warn"), mpv_initialize, wakeup callback.
    /// `onEvent` runs on the private event queue; the owner hops to the main actor.
    init(options: [(name: String, value: String)], onEvent: @escaping @Sendable (MPVEvent) -> Void) throws
    func command(_ args: [String])            // strdup'd NULL-terminated argv; logs failures (args[0] only)
    func string(_ name: String) -> String?    // mpv_get_property_string + mpv_free
    func double(_ name: String) -> Double?    // MPV_FORMAT_DOUBLE
    func setString(_ name: String, _ value: String)
    static func redact(_ text: String) -> String   // replaces https?://\S+ with "<url>"
}

// IPTV/Player/MPVVideoView.swift
nonisolated final class MPVVideoLayer: CAOpenGLLayer, @unchecked Sendable {
    init(mpv: MPVHandle)
    /// True once the render context exists (set on the main thread).
    private(set) var isReady: Bool
    /// Called on the main thread when the render context is created.
    var onReady: (@Sendable () -> Void)?
}
final class MPVVideoView: NSView {   // layer-hosting: layer = videoLayer, then wantsLayer = true
    let videoLayer: MPVVideoLayer
    init(mpv: MPVHandle)
    // viewDidChangeBackingProperties: videoLayer.contentsScale = window?.backingScaleFactor ?? 2
}
```

`MPVVideoLayer` follows the spike exactly, plus four additions:

- **Setup:** `isAsynchronous = false`, `needsDisplayOnBoundsChange = true`, `backgroundColor = black`.
- **`copyCGLPixelFormat`:** `kCGLPFAOpenGLProfile = kCGLOGLPVersion_3_2_Core`, `kCGLPFADoubleBuffer`, `kCGLPFAAccelerated`, `kCGLPFAAllowOfflineRenderers`.
- **`copyCGLContext(forPixelFormat:)`:**
  - `super`, then `CGLSetCurrentContext(ctx)`.
  - **If a render context already exists, free it first** (only one per core).
  - `mpv_render_context_create` with `MPV_RENDER_PARAM_API_TYPE` = `MPV_RENDER_API_TYPE_OPENGL` and `MPV_RENDER_PARAM_OPENGL_INIT_PARAMS`. `get_proc_address` looks symbols up with `CFBundleGetFunctionPointerForName` in bundle `com.apple.opengl`.
  - `mpv_render_context_set_update_callback`: the callback does `DispatchQueue.main.async { layer.setNeedsDisplay() }`.
  - Set `isReady` and call `onReady` on main.
- **`releaseCGLContext(_:)`:** make it current, `mpv_render_context_free`, `isReady = false`, then `super`.
- **`canDraw`** returns true.
- **`draw(inCGLContext:…)`:** read `GL_FRAMEBUFFER_BINDING` and `GL_VIEWPORT`. Call `mpv_render_context_render` with `MPV_RENDER_PARAM_OPENGL_FBO` (`mpv_opengl_fbo(fbo:w:h:internal_format: 0)`) and `MPV_RENDER_PARAM_FLIP_Y = 1`. Then `glFlush()`.
- **OpenGL deprecation warnings:** the scratch build showed none. If some appear, leave them; don't add build settings (`GL_SILENCE_DEPRECATION` is a C macro that Swift ignores).

```swift
// IPTV/Player/Timeshift.swift
nonisolated struct Timeshift: Equatable, Sendable {
    static let liveSlack: Double = 15       // L8
    static let liveOffset: Double = 10      // jump-to-live target below cache-end
    var position: Double                    // time-pos
    var rangeStart: Double                  // start of the seekable range containing position (else the smallest start)
    var cacheEnd: Double                    // "cache-end"
    var behindLive: Double { max(0, cacheEnd - position - Self.liveSlack) }
    var isLive: Bool { behindLive < 1 }
    var buffered: Double { max(0, cacheEnd - rangeStart) }
    var livePosition: Double { cacheEnd - Self.liveOffset }
    /// position + delta, clamped to [rangeStart + 1, livePosition] (if that range is empty, livePosition).
    func target(seekingBy delta: Double) -> Double
    /// nil when the JSON lacks cache-end or seekable-ranges is empty.
    static func parse(cacheStateJSON: String, timePos: Double) -> Timeshift?
    /// "LIVE" when isLive, else "−m:ss" (or "−h:mm:ss"), using U+2212 minus.
    var label: String
}

// IPTV/Player/SleepAssertion.swift
final class SleepAssertion {
    /// Idempotent. IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, on, "MMTVL Live TV") / IOPMAssertionRelease.
    func hold(_ on: Bool)
}

// IPTV/Player/LivePlayer.swift
nonisolated struct PlayerState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case idle, loading, playing, paused, failed }
    var phase: Phase = .idle
    var timeshift: Timeshift?
}
protocol LivePlayer: AnyObject {
    var state: PlayerState { get }
    /// After retries are exhausted (L13). Set by LiveTVModel.
    var onFailure: (() -> Void)? { get set }
    func play(_ url: URL)
    func stop()
    func togglePause()
    func seek(by seconds: Double)
    func seekToLive()
}
@Observable
final class MPVPlayerController: LivePlayer {
    private(set) var state = PlayerState()
    /// Created with the mpv core on first use; LiveTVRootView hosts it.
    private(set) var videoView: MPVVideoView?
    @ObservationIgnored var onFailure: (() -> Void)?
    /// Creates the core and view without playing, so the view can get its GL context early.
    func prepare()
}
```

`MPVPlayerController` behavior:

- **`prepare()`:** creates `MPVHandle(options: MPVOptions.all, onEvent:)` (logging creation errors; `state.phase = .failed`) and `MPVVideoView`.
  - `onEvent`: `{ [weak self] event in Task { @MainActor in self?.handle(event) } }`.
  - `videoLayer.onReady`: `{ [weak self] in Task { @MainActor in self?.loadPending() } }`.
- **`play(url)`:**
  - `prepare()` if needed; `retries = 0`; `currentURL = url`; `phase = .loading`; `timeshift = nil`.
  - If `videoLayer.isReady`, run `loadfile <url> replace`; otherwise keep it as `pendingURL`.
  - **Never `loadfile` before the render context exists.** With `vo=libmpv` and no render context, mpv has no video output for that file.
- **Events:**
  - `.playbackRestart` → `.playing` if the phase was `.loading` or `.playing`.
  - `.endFile(.eof/.error)` while loading/playing:
    - With retries left (2), wait 2 s and `loadfile` the same URL again (`phase = .loading`).
    - Otherwise `phase = .failed` and `onFailure?()`.
  - Other end reasons → ignored.
  - `.log` → `Logger(category: "MPV").info`.
- **`stop()`:** `command(["stop"])`; `phase = .idle`; `timeshift = nil`; `pendingURL = nil`; cancel any retry.
- **`togglePause()`:** only when playing/paused. `setString("pause", "yes"/"no")`, `phase = .paused/.playing`.
- **`seek(by:)`:** with a timeshift, `command(["seek", String(format: "%.3f", target), "absolute+keyframes"])`.
- **`seekToLive()`:** the same, with `livePosition`.
- **Polling:** a 0.5 s main-run-loop `Timer` while the phase is playing/paused reads `double("time-pos")` and `string("demuxer-cache-state")` → `Timeshift.parse`, and assigns `timeshift` when it changed.
- **Sleep:** `phase` `didSet` → `sleep.hold(phase == .loading || phase == .playing)` (L15).

```swift
// IPTV/Guide/GuideTimeline.swift
nonisolated struct GuideTimeline: Equatable, Sendable {
    static let windowDuration: TimeInterval = 2 * 3600
    static let horizon: TimeInterval = 24 * 3600
    var windowStart: Date                         // always on a :00/:30 boundary
    var windowEnd: Date { windowStart + Self.windowDuration }
    static func halfHourFloor(_ date: Date) -> Date
    init(now: Date)                               // windowStart = halfHourFloor(now)
    /// If `focusStart` (≥ now) isn't in [windowStart, windowStart + 1.5 h), windowStart = halfHourFloor(focusStart),
    /// never earlier than halfHourFloor(now).
    mutating func reveal(_ focusStart: Date, now: Date)
    /// Horizontal span of [start, stop) clipped to the window, in points for `width`; nil if outside.
    func span(start: Date, stop: Date, width: CGFloat) -> (x: CGFloat, width: CGFloat)?
    /// Labels every 30 min across the window: [(x, Date)].
    func ticks(width: CGFloat) -> [(x: CGFloat, date: Date)]
}

// IPTV/Guide/GuideModel.swift
nonisolated struct GuideModel: Equatable, Sendable {
    static let visibleRows = 6
    enum Focus: Equatable, Sendable { case grid, groups(Int) }
    enum Action: Equatable, Sendable { case none, play(Channel.ID), close, groupChanged(String) }
    /// One focusable cell: a programme, or a placeholder spanning the window when a row has no data.
    struct Cell: Equatable, Sendable { var programme: Programme?; var start: Date; var stop: Date }

    private(set) var groups: [String]
    private(set) var groupIndex: Int
    private(set) var channels: [Channel]           // the selected group's
    var programmes: [Channel.ID: [Programme]]      // set by LiveTVModel after loading
    private(set) var focus: Focus = .grid
    private(set) var row = 0
    private(set) var focusTime: Date               // the time the focus aims at (≥ now)
    private(set) var firstVisibleRow = 0
    private(set) var timeline: GuideTimeline

    init(allChannels: [Channel], group: String?, focusedChannelID: Channel.ID?, now: Date)
    /// Cells of `row` overlapping [now, now + horizon), sorted; one placeholder cell [now, now + horizon) when none.
    func cells(row: Int, now: Date) -> [Cell]
    func focusedCell(now: Date) -> Cell?           // the cell containing focusTime, else the first after it, else the last
    var focusedChannel: Channel?
    mutating func handle(_ command: RemoteCommand, now: Date) -> Action
    mutating func setChannels(allChannels: [Channel])   // after a playlist refresh: keep group/row by id where possible
}
```

`GuideModel.init`:

- `groups = ChannelList.guideGroups(of: allChannels)`.
- `groupIndex`: the index of `group` if present, else 0.
- If `focusedChannelID` isn't in that group, switch to group 0 ("All Channels") when present.
- `row`: the index of `focusedChannelID` in the group, else 0. `firstVisibleRow` keeps that row visible.
- `focusTime = now`; `timeline = GuideTimeline(now:)`.

`GuideModel.handle`, **grid focus:**

- **Up / Down:** `row` ± 1, clamped, no wrap. `focusTime` is unchanged. Keep `row` in `[firstVisibleRow, firstVisibleRow + visibleRows)`. Returns `.none`.
- **Right:** the next cell after the focused one, if any: `focusTime = max(next.start, now)`, `timeline.reveal(focusTime, now:)`.
- **Left:**
  - If the focused cell is the first (airing now): `focus = .groups(groupIndex)`.
  - Otherwise, the previous cell: `focusTime = max(prev.start, now)`, `reveal`.
- **Rewind / Fast-forward:** same as Left / Right (L9).
- **Select:** `.play(focusedChannel.id)` when a channel exists, else `.none`.
- **Back:** `.close`.
- **Play/Pause, Home:** `.none`; the caller handles them.

`GuideModel.handle`, **groups focus:**

- **Up / Down:** move the group index (clamped).
- **Select / Right:** apply the group:
  - `groupIndex = i`; `channels` = that group; `row = 0`; `firstVisibleRow = 0`; `focusTime = now`; `timeline = GuideTimeline(now:)`; `focus = .grid`.
  - Returns `.groupChanged(groups[i])`.
- **Back / Left:** `focus = .grid` (no change), `.none`.

```swift
// IPTV/LiveTVModel.swift
enum LiveTVOutcome: Equatable { case handled, leave, openSettings }

/// What the router needs; tests use a fake.
protocol LiveTVHosting: AnyObject {
    func open()
    func leave()
    func handle(_ command: RemoteCommand) -> LiveTVOutcome
}

@Observable
final class LiveTVModel: LiveTVHosting {
    enum Mode: Equatable { case setupNeeded, loading, player, guide, unavailable(String) }
    struct Banner: Equatable { var channel: Channel; var now: Programme?; var next: Programme? }

    private(set) var mode: Mode = .loading
    private(set) var currentChannel: Channel?
    private(set) var banner: Banner?
    private(set) var showsTimeshiftBar = false
    private(set) var playbackError: String?          // "Can't play this channel"
    private(set) var guide: GuideModel?
    let player: any LivePlayer
    let library: IPTVLibrary
    /// The last async work started by open()/commands; tests await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let overlayDuration: Duration    // 5 s; tests assert state right after a command, never wait for hiding

    init(player: any LivePlayer, library: IPTVLibrary, now: @escaping () -> Date = Date.init,
         overlayDuration: Duration = .seconds(5))
}
```

`LiveTVModel` behavior:

- **`open()`:**
  - If `!library.hasPlaylist` → `.setupNeeded`; return.
  - Kick off `Task { await library.refreshGuideIfStale() }` (fire and forget).
  - `pendingTask = Task`:
    1. If `channels` is empty, `mode = .loading`.
    2. `await library.refreshPlaylistIfStale()`.
    3. If there are still no channels: `.unavailable(message)`, where the message is the playlist error or "The playlist has no channels".
    4. Otherwise, if `state.lastChannelID` matches a channel → `play(channel)` (mode `.player`).
    5. Otherwise → `openGuide()`.
- **`leave()`:** `player.stop()`, `guide = nil`, `banner = nil`, `showsTimeshiftBar = false`, `playbackError = nil`, cancel `pendingTask`. Keep `currentChannel` so the guide can focus it later.
- **`play(_ channel)`** (private):
  - `currentChannel = channel`; `playbackError = nil`; `refreshedAfterFailure = false`; `player.play(channel.streamURL)`.
  - `library.rememberChannel(channel.id)`; `mode = .player`; `guide = nil`; `showBanner()`.
- **`showBanner()`:**
  - Set `banner` (programmes nil).
  - Then a task: `nowNext` fills `now`/`next` if the banner still shows the same channel.
  - Then hide after `overlayDuration`, using a generation counter so a newer banner isn't hidden early.
- **`showTimeshiftBar()`:** the same pattern. It stays visible while `player.state.phase == .paused`; the view checks that too.
- **`player.onFailure`** (set in init):
  - If `!refreshedAfterFailure`: set it, `await library.refreshPlaylist()`, find the channel by id, `player.play(newURL)`.
  - Otherwise `playbackError = "Can't play this channel"`.
- **`handle(_:)` in `.player`:** per L9:
  - Up/Down zap through `ChannelList.channels(in: zapGroup, of: library.channels)`, wrapping around.
    - `zapGroup` is `state.lastGroup` if it contains the current channel, else the current channel's group.
    - If the zap list is empty or has one channel, it's a no-op.
  - Select:
    - If `playbackError != nil` → retry `play(currentChannel)`.
    - Otherwise `openGuide()`.
  - Back: if a banner or the bar is visible, hide them → `.handled`; otherwise `.leave`.
- **`handle` in `.guide`:**
  - Play/Pause → `player.togglePause()`.
  - Everything else → `guide.handle(command, now: now())`:
    - `.play(id)`: if it's the current channel and the phase isn't failed/idle → `mode = .player` + banner. Otherwise `play(channel)`.
    - `.groupChanged(g)` → `library.rememberGroup(g)` + `loadProgrammes()`.
    - `.close`: if a current channel is playing (phase not idle/failed) → `mode = .player`; otherwise `.leave`.
- **`handle` in `.setupNeeded` / `.unavailable`:**
  - Select → `.openSettings` (setup) or retry `open()` (unavailable).
  - Back → `.leave`.
  - Everything else → `.handled`.
- **`handle` in `.loading`:** Back → `.leave`; everything else `.handled`.
- **`openGuide()`:**
  - `guide = GuideModel(allChannels:group: state.lastGroup, focusedChannelID: currentChannel?.id, now:)`.
  - `mode = .guide`; hide the banner and bar; `loadProgrammes()`.
- **`loadProgrammes()`:** `guide.programmes = await library.programmes(for: guide.channels, in: [now − 1 h, now + 24 h])` (only if the guide still shows the same group).
- **Observation:**
  - When `library.guideRevision` changes while the guide is open, reload programmes. In the view, `.onChange(of: library.guideRevision) { model.guideDataChanged() }`.
  - When `library.channels` changes, `guide?.setChannels(allChannels:)`.

### Router changes (`Launcher/AppRouter.swift`)

```swift
enum Screen: Equatable {
    case home, accessibilityOnboarding, settings, youtube, liveTV
    case pin(PINPurpose)
}
@ObservationIgnored let liveTV: any LiveTVHosting
init(items:launcher:settings:youtube:liveTV:pinStore:)
func openLiveTV() { liveTV.open(); screen = .liveTV }
```

- **`open(item)`:**
  - `.internalDestination(.iptv)` → `openLiveTV()`.
  - List `.settings`, `.youtube` and `.iptv` explicitly; remove the generic `.internalDestination` → placeholder case.
- **`route` for `.liveTV`:**
  - `.home` → `goHome()`.
  - Anything else → `switch liveTV.handle(command)`:
    - `.handled` → nothing.
    - `.leave` → `goHome()`.
    - `.openSettings` → `hasPIN ? requestPIN(.openSettings) : openSettings()`. `screenBeforePIN` becomes `.home`, since `requestPIN` only remembers `.settings`, and that is fine. Call `liveTV.leave()` first.
  - Always return true.
- **`goHome()`:** also `if screen == .liveTV { liveTV.leave() }`.
- Remove `Screen.placeholder` and its route and view cases; delete `PlaceholderView.swift`.
- **`LauncherRootView(router:youtube:liveTV:)`:** when `router.screen == .liveTV`, show `LiveTVRootView(model: liveTV)` full window, like YouTube. `liveTV` is the concrete `LiveTVModel`. The `content` switch gets `case .liveTV: EmptyView()`.

### Live TV views (`IPTV/LiveTVView.swift`, `IPTV/Guide/GuideView.swift`)

`CanvasGeometry` (pure, nonisolated, testable):

```swift
nonisolated enum CanvasGeometry {
    static let canvas = CGSize(width: 1920, height: 1080)
    /// Same transform LauncherRootView applies: scale = size.width / 1920, canvas centered.
    static func windowRect(forCanvasRect rect: CGRect, in size: CGSize) -> CGRect
}
```

`LiveTVRootView(model:)`, a `GeometryReader` with a `ZStack`:

1. `Color.black`.
2. The video view: if `(model.player as? MPVPlayerController)?.videoView` exists, an `MPVVideoRepresentable(view:)`:
   - `.frame(width:height:)` and `.position(...)` from `CanvasGeometry.windowRect(forCanvasRect: Theme.guidePreviewRect, in: size)` in guide mode, or the full size in player mode.
   - No animation on frame changes (`.transaction { $0.animation = nil }`).
   - Hidden (`.opacity(0)`) in setup/loading/unavailable modes, but kept in the hierarchy.
   - Call `player.prepare()` in `.onAppear` so the GL context exists before the first `play`.
3. The overlay canvas (the same scale transform as `LauncherRootView`, transparent background) by mode:
   - **`.player`:** `PlayerOverlayView`:
     - The banner (bottom, gradient) when `model.banner != nil`.
     - The timeshift bar when `model.showsTimeshiftBar || phase == .paused`.
     - The behind-live badge (top right) when `timeshift?.isLive == false`.
     - A loading spinner when `phase == .loading`.
     - The error panel when `model.playbackError != nil`.
   - **`.guide`:** `GuideView(model: guide, library:, currentChannel:, phase:)`.
   - **`.setupNeeded`:** "Live TV isn't set up" / "Copy your playlist URL, then open Settings → Live TV → Paste Playlist URL." / hint "Select: open Settings · Back: return".
   - **`.loading`:** `ProgressView()` + "Loading channels…".
   - **`.unavailable(message)`:** "Can't load channels", the message, "Select: try again · Back: return".

Banner layout:

- Logo (`AsyncImage`, 96 pt, falling back to the channel name only).
- "\(number)  \(name)" (`liveBannerTitleFont`).
- `now.title` (`liveBannerProgrammeFont`), "7:00 – 8:30 PM" and a thin progress bar.
- "Next: \(next.title) · 8:30 PM" (`liveBannerDetailFont`).
- "No programme information" when there is no data.

Timeshift bar layout:

- A full-width track (`sideMargin` insets).
- The filled part = `buffered` scaled to the track. The playhead sits at `(position − rangeStart) / buffered`.
- `timeshift.label` on the left; a pause symbol when paused.
- Hint: "Left/Right: 10 s · Rewind/FF: 30 s · Play/Pause".

`GuideView` layout (canvas coordinates; tokens in Theme):

- **Info panel** at `(120, 60, 980 × 360)`:
  - The focused cell's title (`guideInfoTitleFont`).
  - "Channel name · 7:00 – 8:30 PM · S2 E1 · category" (`guideInfoDetailFont`).
  - The summary (`guideInfoDetailFont`, `secondaryText`, `lineLimit(4)`).
  - For a placeholder cell: the channel name and "No programme information".
- **Preview frame** at `Theme.guidePreviewRect` = `(1160, 60, 640 × 360)`:
  - A rounded 2 pt `focusHighlight` border drawn **over** the video.
  - "Nothing playing" text when the phase is idle.
- **Time header** at y `guideGridTop` (460), height 48: tick labels from `timeline.ticks`, formatted `.shortened` time.
- **Rows:** `GuideModel.visibleRows` × `guideRowHeight` (80), from y 508. Each row:
  - The channel column (`guideChannelColumnWidth` 340): number, logo 48 pt, name.
  - Programme cells via `timeline.span(...)` over `guideGridWidth` (1328), starting at x `guideGridLeading` (472).
  - The focused cell (grid focus, focused row) is filled `focusedRowFill` with `focusedRowText`, as in Settings. Other cells use `tileFill`.
  - Cell text: title (`guideCellFont`), then start time (`guideCellTimeFont`).
  - The current channel's row has a small "playing" symbol (`speaker.wave.2.fill`) by its name.
- **Now line:** a 2 pt `guideNowLine` line at now's x, from the header to the last row. Use `TimelineView(.everyMinute)`.
- **Group panel:** when `focus == .groups`, a `guideGroupPanelWidth` (420) panel over the channel column, with a dark fill. Groups as rows; the focused one is white with black text.
- **Hint** at the bottom: "Select: watch · Left at now: groups · Back: close".

### Settings additions

- **`SettingsPage`:** `.liveTV`, `.confirmRemoveIPTV`.
- **`SettingsAction`:** `.pasteIPTVURL(IPTVURLKind)`, `.useIPTVPlaylistGuide`, `.refreshIPTV`, `.removeIPTVSource`.
  - `nonisolated enum IPTVURLKind: Hashable, Sendable { case playlist, guide }`.

`IPTVSettingsStatus`:

```swift
nonisolated struct IPTVSettingsStatus: Equatable, Sendable {
    var hasPlaylist = false
    var playlistHost: String?            // url.host()
    var channelCount = 0
    var playlistLine: String = ""        // "Loading…", "Updated 10:42 PM", "Failed: Server error (HTTP 403)"
    var guideKind: GuideKind = .none     // .none, .playlist(host), .custom(host)
    var guideLine: String = ""           // "1,234 programmes · Updated 10:43 PM", "Loading…", "Failed: …", "No guide"
    enum GuideKind: Equatable, Sendable { case none, playlist(String), custom(String) }
}
```

`SettingsEnvironment` additions:

- `iptvStatus: () -> IPTVSettingsStatus`
- `pasteIPTVURL: (IPTVURLKind) -> String?`: reads the clipboard. Returns an error message, or nil on success; on success it starts the save + refresh.
- `useIPTVPlaylistGuide: () -> Void`
- `refreshIPTV: () -> Void`
- `removeIPTVSource: () -> Void`

`SettingsModel`:

- `private(set) var iptv: IPTVSettingsStatus` (init, `refreshStatus()`).
- `private(set) var pasteMessage: String?` is the last paste error. It shows as the paste row's detail and is cleared on any push/pop and on a successful paste.
- `perform`:
  - `.pasteIPTVURL(k)` → `pasteMessage = environment.pasteIPTVURL(k)`; then `refreshStatus()`.
  - `.useIPTVPlaylistGuide` → env.
  - `.refreshIPTV` → env.
  - `.removeIPTVSource` → `environment.removeIPTVSource(); pop()`.

**Root page:** a new section after "YouTube":

- **"Live TV":** row `liveTV` "Live TV", with value "\(n) Channels" when a playlist is set, else "Not Set Up". Disclosure; action `.push(.liveTV)`.

**`.liveTV` page** (title "Live TV", image `.symbol("tv")`, hint "Select: choose · Back: return"):

- **Section "playlist"** (title "Playlist"):
  - With a playlist: info row `iptv.playlist.info`, title = host, value "\(n) Channels", detail `playlistLine`.
  - Row `iptv.playlist.paste`:
    - Title "Paste Playlist URL", or "Replace with Clipboard URL" when one is set.
    - Detail: `pasteMessage`, else "Copy the M3U address on this Mac or your iPhone first".
    - Action `.pasteIPTVURL(.playlist)`.
- **Section "guide"** (title "Guide"), only with a playlist:
  - Info row `iptv.guide.info`:
    - Title "From the playlist: \(host)", "Custom: \(host)", or "No guide".
    - Detail `guideLine`, or for `.none` "Paste an XMLTV guide URL to see what's on".
  - Row `iptv.guide.paste` "Paste Guide URL" → `.pasteIPTVURL(.guide)`.
  - Row `iptv.guide.usePlaylist` "Use the Playlist's Guide" (only when `.custom`) → `.useIPTVPlaylistGuide`.
- **Section "manage"**, only with a playlist:
  - `iptv.refresh` "Refresh Now" → `.refreshIPTV`.
  - `iptv.remove` "Remove Live TV Source", disclosure → `.push(.confirmRemoveIPTV)`.
  - Footer: "Addresses are kept in the Keychain. The first paste may ask for permission; choose Allow."

**`.confirmRemoveIPTV` page:**

- Title "Remove Live TV Source?", image `.symbol("tv.slash")`, hint "Select: choose · Back: cancel".
- Rows `confirm.cancel` "Cancel" (`.pop`, focused first) and `confirm.removeIPTV` "Remove" (`.removeIPTVSource`).
- Footer: "Forgets the playlist and guide addresses and deletes the downloaded guide."

### AppDelegate wiring

- **At launch** (after `settingsModel` exists):
  - `let epgStore = try? EPGStore.open(at: EPGStore.defaultURL)` (log failure).
  - `let iptvState = JSONConfigFile(url: directory.appending(path: IPTVState.fileName), defaultValue: IPTVState())`.
  - `let overrides = JSONConfigFile(url: directory.appending(path: IPTVState.overridesFileName), defaultValue: [String: String]())`, where `IPTVState.overridesFileName = "epg-overrides.json"`.
  - `let library = IPTVLibrary(sources: .keychain, store: epgStore, network: .live, stateFile: iptvState, overridesFile: overrides)`.
  - `let player = MPVPlayerController()`.
  - `let liveTV = LiveTVModel(player: player, library: library)`.
  - Store them in properties.
- `AppRouter(..., liveTV: liveTV, ...)`; `LauncherRootView(router:youtube:liveTV:)`.
- `library.onStatusChange = { [weak router] in router?.settings.refreshStatus() }`.
- `if library.hasPlaylist { Task { await library.refreshAll() } }`, after the window is shown.
- **`makeSettingsEnvironment`** gains the five closures:
  - `iptvStatus` builds `IPTVSettingsStatus` from the library. Times are time-only, `Date.formatted(date: .omitted, time: .shortened)`. Counts use `formatted()`.
  - `pasteIPTVURL`:
    - Read `NSPasteboard.general.string(forType: .string)` and run `ClipboardURL.parse`.
    - On failure, return `ClipboardURL.message(for:)`.
    - On success, `Task { await library.setPlaylistURL(url) }` or `setGuideURL(url)`, and return nil.
    - Log the host only.
  - `useIPTVPlaylistGuide` → `Task { await library.setGuideURL(nil) }`.
  - `refreshIPTV` → `Task { await library.refreshAll() }`.
  - `removeIPTVSource` → `liveTV.leave(); Task { await library.removeSource() }`.
- **Wake:** `systemDidWake` already calls `goHome()`, which now leaves Live TV (stops playback).

### Theme additions

| Token | Value |
|---|---|
| `guidePreviewRect` | `CGRect(x: 1160, y: 60, width: 640, height: 360)` |
| `guideInfoRect` | `CGRect(x: 120, y: 60, width: 980, height: 360)` |
| `guideGridTop` | 460 |
| `guideTimeHeaderHeight` | 48 |
| `guideRowHeight` | 80 |
| `guideCellSpacing` | 4 (gap between cells and rows) |
| `guideChannelColumnWidth` | 340 |
| `guideGridLeading` | 472 |
| `guideGridWidth` | 1328 |
| `guideGroupPanelWidth` | 420 |
| `guideInfoTitleFont` | `Font.system(size: 44, weight: .semibold)` |
| `guideInfoDetailFont` | `Font.system(size: 24)` |
| `guideCellFont` | `Font.system(size: 24, weight: .medium)` |
| `guideCellTimeFont` | `Font.system(size: 18)` |
| `guideChannelFont` | `Font.system(size: 24, weight: .medium)` |
| `guideCellCornerRadius` | 10 |
| `guideNowLine` | `Color(red: 1, green: 0.27, blue: 0.23)` |
| `liveBannerTitleFont` | `Font.system(size: 40, weight: .semibold)` |
| `liveBannerProgrammeFont` | `Font.system(size: 30, weight: .medium)` |
| `liveBannerDetailFont` | `Font.system(size: 22)` |
| `liveBarHeight` | 8 |
| `liveOverlayGradient` | `LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)` |

## Implementation steps

After every step, build with `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build`, and run the tests whenever a step adds or changes tests. Logging uses `Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV" | "MPV")`. **Never log a full source or stream URL** (L2).

- [ ] **1. Add MPVKit and GRDB**: `MMTVL.xcodeproj/project.pbxproj`, `Package.resolved` (generated), `MMTVLTests/SmokeTests.swift`, `MMTVL/IPTV/Player/MPVOptions.swift`
  - Edit `project.pbxproj` exactly like this. These edits were tested on a scratch copy and resolved and built. Unused IDs start at `…50`.
    1. Add a `PBXBuildFile` section before `/* Begin PBXContainerItemProxy section */`:
       ```
       /* Begin PBXBuildFile section */
       		AA0000000000000000000050 /* MPVKit in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000000052 /* MPVKit */; };
       		AA0000000000000000000051 /* GRDB in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000000053 /* GRDB */; };
       /* End PBXBuildFile section */
       ```
    2. In the **app's** frameworks phase `AA0000000000000000000021`, `files = ( AA…50 /* MPVKit in Frameworks */, AA…51 /* GRDB in Frameworks */, );`.
    3. In target `AA0000000000000000000010` (MMTVL), `packageProductDependencies = ( AA…52 /* MPVKit */, AA…53 /* GRDB */, );`.
    4. In the project object `AA0000000000000000000001`, after `minimizedProjectReferenceProxies = 1;`, add `packageReferences = ( AA…54 /* XCRemoteSwiftPackageReference "MPVKit" */, AA…55 /* XCRemoteSwiftPackageReference "GRDB.swift" */, );`.
    5. Before the final `	};\n	rootObject = …`, add:
       ```
       /* Begin XCRemoteSwiftPackageReference section */
       		AA0000000000000000000054 /* XCRemoteSwiftPackageReference "MPVKit" */ = {
       			isa = XCRemoteSwiftPackageReference;
       			repositoryURL = "https://github.com/mpvkit/MPVKit.git";
       			requirement = {
       				kind = exactVersion;
       				version = 1.0.0;
       			};
       		};
       		AA0000000000000000000055 /* XCRemoteSwiftPackageReference "GRDB.swift" */ = {
       			isa = XCRemoteSwiftPackageReference;
       			repositoryURL = "https://github.com/groue/GRDB.swift.git";
       			requirement = {
       				kind = upToNextMajorVersion;
       				minimumVersion = 7.11.1;
       			};
       		};
       /* End XCRemoteSwiftPackageReference section */

       /* Begin XCSwiftPackageProductDependency section */
       		AA0000000000000000000052 /* MPVKit */ = {
       			isa = XCSwiftPackageProductDependency;
       			package = AA0000000000000000000054 /* XCRemoteSwiftPackageReference "MPVKit" */;
       			productName = MPVKit;
       		};
       		AA0000000000000000000053 /* GRDB */ = {
       			isa = XCSwiftPackageProductDependency;
       			package = AA0000000000000000000055 /* XCRemoteSwiftPackageReference "GRDB.swift" */;
       			productName = GRDB;
       		};
       /* End XCSwiftPackageProductDependency section */
       ```
  - **The test target gets no packages.** Tests reach GRDB and mpv only through app types (`EPGStore.inMemory()`). Linking the static libraries into the test bundle as well would duplicate them.
  - Run `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build -resolvePackageDependencies`. The first run downloads about 350 MB of MPVKit binaries. It writes `MMTVL.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; commit it.
  - Add `MPVOptions.swift` (*Key types*) with `import Libmpv`. Besides the option table, it holds `nonisolated enum LibraryVersions { static var mpvClientAPI: UInt { UInt(mpv_client_api_version()) } }`, so the package is linked and used from step 1.
  - `SmokeTests`: add `@Test func mpvLinks() { #expect(LibraryVersions.mpvClientAPI >= 0x0002_0005) }`. mpv's client API version is `(major << 16) | minor`; 2.5 is `0x20005`.
  - Done when the build and all tests pass and `Package.resolved` lists GRDB 7.11.x and MPVKit 1.0.0.

- [ ] **2. M3U parser and channels (pure)**: `IPTV/Sources/M3UParser.swift`, `IPTV/Sources/Channel.swift`, `MMTVLTests/M3UParserTests.swift`, `MMTVLTests/ChannelListTests.swift`
  - Implement as in *Key types*.
  - `M3UParserTests` covers:
    - A fixture shaped like the user's (bare `#EXTM3U`; entries like `#EXTINF:0 tvg-id="nbatv.us" tvg-logo="https://x/y.png" tvg-name="NBA TV" group-title="Live Channels",NBA TV`; a game entry with `tvg-type="movie" tvg-id="Philadelphia @ Tampa Bay-A" group-title="NHL Games"`; an entry with `tvg-id=""`).
    - A name containing a comma (`…,News, Weather` → "News, Weather").
    - A comma inside a quoted attribute (`tvg-name="A, B"`).
    - CRLF line endings and a BOM.
    - `#EXTGRP` (applies until changed; `group-title` wins).
    - The header `url-tvg="https://a/x.xml.gz,https://b/y.xml"` → 2 guide URLs; `x-tvg-url` too.
    - `#EXTVLCOPT` lines between `#EXTINF` and the URL are skipped.
    - A URL with no `#EXTINF` is ignored.
    - HTML → throws `.notAPlaylist`.
  - `ChannelListTests` covers:
    - ids (`id:nbatv.us`; an empty tvg-id → `name:red zone2`; a duplicate → `#2`).
    - Numbering.
    - `/movie/` and `.mp4` entries dropped, but `tvg-type="movie"` with an HLS URL **kept**.
    - A missing group → "Other".
    - `groups` order.
    - `guideGroups` adds "All Channels" only with more than one group.
    - `channels(in:)`.
  - Done when the tests pass.

- [ ] **3. Source store, clipboard parsing, network, state**: `IPTV/Sources/IPTVSourceStore.swift`, `IPTV/Sources/ClipboardURL.swift`, `IPTV/Sources/IPTVNetwork.swift`, `IPTV/IPTVState.swift`, `MMTVLTests/IPTVSourceStoreTests.swift`, `MMTVLTests/ClipboardURLTests.swift`
  - `IPTVSourceStore.keychain` uses `Keychain.string/set/remove` with `Keychain.service` and the two accounts, and logs errors (category "IPTV").
  - `IPTVNetwork.live`:
    - `URLSession(configuration: .ephemeral)` (no cookies or cache on disk).
    - `fetchText`: `data(for:)` with `timeoutInterval = 30`; check `HTTPURLResponse.statusCode` in 200..<300; `String(decoding: data, as: UTF8.self)`.
    - `download`: `download(for:)` with 120 s, the same status check, then move the file into `FileManager.default.temporaryDirectory/<UUID>` and return that URL.
  - `IPTVState` decodes missing keys as nil (custom `init(from:)` with `decodeIfPresent`).
  - Tests:
    - `ClipboardURL`: nil/"" → `.empty`; `"  https://iptv.example/app2/abc\n"` → that URL; `"hello"` → `.notAWebAddress`; `"ftp://x"` → `.notAWebAddress`; a two-line text uses the first non-empty line.
    - `IPTVSourceStore.inMemory` round trip and `removeAll`.
    - A real-Keychain round trip using a test service. To allow that, the closure struct gets `static func keychain(service: String)`, and `.keychain` = `keychain(service: Keychain.service)`. Clean up at the end.
    - `IPTVState` decodes `{}`.
  - Done when the tests pass.

- [ ] **4. XMLTV parsing, gunzip, matching (pure)**: `IPTV/EPG/XMLTVDate.swift`, `IPTV/EPG/Programme.swift`, `IPTV/EPG/XMLTVParser.swift`, `IPTV/EPG/Gunzip.swift`, `IPTV/EPG/EPGMatcher.swift`, `MMTVLTests/XMLTVTests.swift`, `MMTVLTests/GunzipTests.swift`, `MMTVLTests/EPGMatcherTests.swift`
  - `Programme.swift` needs `import GRDB` (app target only).
  - `XMLTVParser` is a **`nonisolated final class`** (a MainActor delegate doesn't compile off main). Set `shouldResolveExternalEntities = false`. Use `XMLParser(contentsOf: fileURL)`.
  - `XMLTVTests`:
    - **Dates:** `"20261005143000 +0000"`; `"20261005143000 -0500"` (= 19:30 UTC); `"20261005143000"` (UTC); `"202610051430"`; garbage → nil.
    - **Parser,** on a fixture written to a temp file with a DOCTYPE, 3 channels and programmes:
      - Only wanted channels are kept.
      - The `wantedIDs` closure gets all 3 channels, is called once, and ids arrive lowercased.
      - Programmes outside the window are dropped.
      - A missing `stop` is filled from the next programme.
      - The first `title` wins.
      - `xmltv_ns` `1.0.0/1` → "S2 E1"; `onscreen` wins over it.
      - `desc` across several `foundCharacters` chunks (include an `&amp;` entity) is joined.
  - `GunzipTests`:
    - Write a text file, gzip it with `Process` running `/usr/bin/gzip -k` (tests are unsandboxed), decompress, and compare.
    - Two gzip members concatenated (`cat a.gz b.gz`) → both texts.
    - A plain file → `isGzip == false`.
  - `EPGMatcherTests`:
    - `normalize("FanDuel Sports Network Detroit HD") == normalize("FanDuel Sports Network Detroit")`.
    - "Telé 5" ↔ "Tele 5".
    - Id match ignores case (`NBATV.us` ↔ `nbatv.us`).
    - A name fallback is used when the tvg-id doesn't match.
    - No match → absent.
    - Of two EPG channels with the same name, the first wins.
    - `+`/`&`: "NBC Sports Bay Area+" matches display name "NBC Sports Bay Area Plus", **not** "NBC Sports Bay Area HD"; "A&E" ↔ "A and E".
    - **Overrides:**
      - A name key wins over a `tvg-id` match.
      - A `tvg-id` key works.
      - Keys and values are case-insensitive.
      - A target missing from the guide falls through to the normal rules.
    - **No fuzzy matching:** "Red Zone" does **not** match "Red TV", and "CBS" does not match "CBS News".
  - Done when the tests pass.

- [ ] **5. EPG store, importer and library**: `IPTV/EPG/EPGStore.swift`, `IPTV/EPG/GuideImporter.swift`, `IPTV/IPTVLibrary.swift`, `MMTVLTests/EPGStoreTests.swift`, `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/IPTVTestSupport.swift`
  - `EPGStore` as in *Key types* (GRDB, migration "v1"). `open(at:)` creates the directory.
  - `GuideImporter.importGuide` **must be `@concurrent`** (see *Research*: a plain nonisolated async function would run on main).
    - Write temporary files under `URL.cachesDirectory/MMTVL/` and remove them with `defer`.
    - Window: `DateInterval(start: now − 6 h, end: now + 4 d)`.
  - `IPTVLibrary` as in *Key types*:
    - Refresh policy L4/L5; guide source L3; `onStatusChange` after every status change.
    - `refreshAll` = `refreshPlaylist()` then `refreshGuide()`.
    - `guideProgrammeCount` comes from `store.programmeCount()` after an import and at init (in a task).
  - `IPTVTestSupport`:
    - A playlist fixture string and an XMLTV fixture string.
    - `IPTVNetwork.fake(texts: [URL: String], files: [URL: String])`, which writes files to temp, plus a call counter.
    - `makeLibrary(...)` with `EPGStore.inMemory()`, `IPTVSourceStore.inMemory`, and the state and overrides files in a temp directory.
  - `EPGStoreTests`:
    - `replaceAll` then the overlap query: a programme spanning the interval start is included; one ending exactly at the start is excluded.
    - Grouping by channel.
    - `replaceAll` again replaces.
    - `removeAll`.
    - Channels round-trip with `names` arrays.
  - `IPTVLibraryTests`:
    - **No playlist:** `hasPlaylist == false`, and refresh does nothing.
    - **`setPlaylistURL`** → channels loaded, status `.loaded`, `onStatusChange` called.
    - **HTTP failure** (`fake` throws `.http(403)`) → `.failed("Server error (HTTP 403)")`, and channels are unchanged.
    - **`refreshPlaylistIfStale`:** no second fetch within 10 min (injected `now`), a fetch after 11 min.
    - **Guide source:** a playlist with `url-tvg` → `.playlist`; `setGuideURL(custom)` → `.custom`; `setGuideURL(nil)` → back to `.playlist`.
    - **Guide import through the fake network:** `programmes(for:in:)` returns the matched channel's programmes; `guideRevision` increased.
    - **`refreshGuideIfStale`:** skipped within 12 h; runs when the guide URL changed (a different hash).
    - **Overrides:** writing `epg-overrides.json` and then `refreshPlaylist()` applies the mapping without a new guide import, as long as the target's programmes were imported. An override target added before an import has its programmes kept.
    - **`removeSource`:** clears channels, the store and the sources.
    - **`nowNext`.**
  - Done when the tests pass and the build has **no** "no 'async' operations occur within 'await'" warnings.

- [ ] **6. Settings: Live TV page**: `Settings/SettingsTypes.swift`, `Settings/SettingsEnvironment.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `App/AppDelegate.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Add everything in *Settings additions*. `IPTVSettingsStatus` and `IPTVURLKind` go in `SettingsTypes.swift`.
  - In `AppDelegate`, create the store, state file and library as in *AppDelegate wiring* (not the player or Live TV model yet), plus the five environment closures and the launch refresh.
  - `SettingsRecorder` gains:
    - `var iptv = IPTVSettingsStatus()`
    - `var pasteResult: String? = nil`
    - `pastes: [IPTVURLKind]`, `iptvRefreshes`, `iptvRemovals`, `playlistGuideUses`
  - Tests:
    - **Root:** `liveTV` value "Not Set Up", then "118 Channels" with a status.
    - **`.liveTV` page without a playlist:** only `iptv.playlist.paste` is focusable; Select records `.playlist`.
    - **A paste error** shows as the row detail and is cleared after pop/push.
    - **With a playlist and a custom guide:** focusable rows in order `iptv.playlist.paste`, `iptv.guide.paste`, `iptv.guide.usePlaylist`, `iptv.refresh`, `iptv.remove`. With a playlist guide, there's no `usePlaylist`.
    - **The remove confirm page** focuses Cancel; Remove records one removal and pops.
  - Done when:
    - The tests pass.
    - **Manual (windowed run):** copy the real playlist URL, then Settings → Live TV → Paste Playlist URL. It shows "Loading…", then the host and "118 Channels" (or the current count).
      - Note whether macOS showed a paste-permission alert, and record it in *Deviations*. If an alert appears, choose Allow. If it blocks remote-only use, see Risks.
    - Paste junk text → the error detail.
    - Refresh Now updates the time.
    - `security find-generic-password -s dev.mmtvl.launcher -a iptv-playlist-url` finds the item. Don't print it with `-w` in shared logs.
    - Remove clears it.

- [ ] **7. mpv handle, video view, player controller**: `IPTV/Player/MPVHandle.swift`, `IPTV/Player/MPVVideoView.swift`, `IPTV/Player/Timeshift.swift`, `IPTV/Player/SleepAssertion.swift`, `IPTV/Player/LivePlayer.swift`, `MMTVLTests/TimeshiftTests.swift`
  - Implement as in *Key types*:
    - `MPVHandle` and `MPVVideoLayer` are **`nonisolated final class … @unchecked Sendable`**. `MPVVideoView` is a normal (MainActor) `NSView`.
    - The wakeup callback is `Unmanaged.passUnretained(self)` (the handle lives for the app's lifetime). It only does `queue.async { drain() }`. `drain()` loops `mpv_wait_event(handle, 0)` until `MPV_EVENT_NONE` and maps events. Read `mpv_event_end_file` from `event.data`.
    - `MPV_EVENT_LOG_MESSAGE` text goes through `MPVHandle.redact` before logging.
    - **Don't call any mpv function inside the wakeup callback.**
  - `Timeshift.parse` decodes the JSON with `JSONSerialization`; the keys contain dashes.
  - `TimeshiftTests`:
    - Parse the spike sample in *Research* (cache-end 92.05, range 0…91.44, time-pos 18.1 → `behindLive ≈ 59`, not live, `label == "−0:59"`).
    - time-pos 78 with the same cache → live, `label == "LIVE"`.
    - `target(seekingBy: -1000)` → `rangeStart + 1`; `+1000` → `cacheEnd − 10`.
    - JSON without `seekable-ranges` → nil.
    - Several ranges → the one containing the position.
    - `label` at 3725 s behind → "−1:02:05".
  - Nothing calls the player yet.
  - Done when the tests pass and it builds.

- [ ] **8. Live TV screen: play full screen** *(first playback)*: `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `Launcher/AppRouter.swift`, `Launcher/PlaceholderView.swift` (delete), `App/AppDelegate.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/FakeLiveTV.swift`, `MMTVLTests/FakePlayer.swift`, `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - **Model:** `LiveTVModel` with modes `.setupNeeded`, `.loading`, `.unavailable`, `.player` and the player-mode commands (Up/Down zap, Back, playPause, Left/Right/RW/FF seeks), banner, bar and L13. The guide arrives in step 10, so in this step:
    - Select in the player only retries on an error.
    - `open()` with no matching last channel plays the **first** channel. Step 10 changes this to the guide.
  - **Views:** `LiveTVRootView` with the video view, `PlayerOverlayView` (banner, bar, badge, spinner, error), the setup/loading/unavailable screens, `CanvasGeometry`, and the Theme `live*` tokens.
  - **Router:** *Router changes*, including removing the placeholder. `AppDelegate` creates the player and model.
  - **Test doubles:**
    - `FakePlayer: LivePlayer` records `played: [URL]`, `stops`, `pauses`, `seeks: [Double]`, `liveSeeks`, and has a settable `state`. It calls `onFailure` on demand (`fail()`).
    - `FakeLiveTV: LiveTVHosting` records opens, leaves and handled commands, and returns a settable outcome.
  - `AppRouterTests`:
    - The Live TV tile → `.liveTV`, `opens == 1`.
    - Home → `.home`, `leaves == 1`.
    - Outcome `.leave` → home.
    - `.openSettings` without a PIN → `.settings`; with a PIN → `.pin(.openSettings)`.
    - Commands are forwarded.
  - `LiveTVModelTests` (with `makeLibrary` from step 5 and `FakePlayer`; await `model.pendingTask?.value`):
    - **No playlist** → `.setupNeeded`; Select → `.openSettings`; Back → `.leave`.
    - **Playlist, no last channel** → `.player` with the first channel (changed to `.guide` in step 10).
    - **Playlist with `lastChannelID` stored** → `.player`, `played == [that URL]`, banner set.
    - **Up/Down** zap within the remembered group and wrap; the channel is remembered (`library.state.lastChannelID`).
    - **Left/Right/RW/FF** → `seeks == [-10, 10, -30, 30]`.
    - **Play/Pause** → `pauses == 1`.
    - **Back** with the banner shown → `.handled` and the banner hidden; Back again → `.leave`.
    - **`fail()` once** → playlist refetched (network counter +1) and played again; `fail()` again → `playbackError` set; Select → plays again.
    - **`leave()`** → `stops == 1`.
  - Done when:
    - The tests pass.
    - **Manual (windowed, with the playlist set in step 6):**
      - The Live TV tile shows "Loading channels…", then plays the first channel (or the last one watched).
      - Video plays, sharp at Retina resolution (`contentsScale`).
      - Up/Down change channel with a banner.
      - Left/Right skip.
      - Space pauses; after 30 s it resumes from the same frame.
      - Back twice → home, and playback stops: the CPU goes idle and audio stops.
      - **Leave and re-enter 3 times → video still shows.** This checks the `releaseCGLContext` / `copyCGLContext` handling; if it's black, see Risks.
      - In Terminal, while playing, `pmset -g assertions | grep MMTVL` shows "MMTVL Live TV"; when paused, it's gone.

- [ ] **9. Guide timeline and model (pure)**: `IPTV/Guide/GuideTimeline.swift`, `IPTV/Guide/GuideModel.swift`, `MMTVLTests/GuideTimelineTests.swift`, `MMTVLTests/GuideModelTests.swift`
  - Implement as in *Key types*.
  - `GuideTimelineTests`:
    - `halfHourFloor(14:47) == 14:30`.
    - `span` clips a programme starting before the window to x = 0.
    - A programme after the window → nil.
    - Width for 30 min = width/4.
    - `reveal` moves the window forward when focus starts at window + 1.5 h, and never before `halfHourFloor(now)`.
    - `ticks` → 4 labels.
  - `GuideModelTests` (fixed `now`, 3 groups, programmes built in the test):
    - init focuses `focusedChannelID`'s row in the remembered group, and falls back to "All Channels" when the channel isn't in it.
    - Up/Down clamp and scroll `firstVisibleRow` (with 10 channels: Down ×7 → `firstVisibleRow == 2`).
    - Right walks programmes and moves the window. Left goes back; Left on the now-cell → `.groups(groupIndex)`.
    - Groups: Down + Select → `.groupChanged`, row 0, grid focus. Back in groups → grid, no change.
    - A row without programmes has one placeholder cell, and Right does nothing.
    - Select → `.play(id)`. Back → `.close`.
    - Up/Down keep `focusTime`: from a future programme on row 0, Down focuses the cell covering the same time on row 1.
  - Done when the tests pass.

- [ ] **10. Guide view and integration**: `IPTV/Guide/GuideView.swift`, `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - Add the guide mode to `LiveTVModel` (Select → `openGuide()`; guide command handling; `loadProgrammes`; `guideDataChanged()`; `setChannels`). `open()` with no last channel → `.guide`.
  - Add `GuideView` and the Theme `guide*` tokens. The video frame moves to `guidePreviewRect` in guide mode (L16).
  - `LiveTVModelTests`:
    - Select in the player → `.guide`, with the guide focused on the current channel.
    - Select on another row → `.player` with that channel played.
    - Select on the current channel's row → `.player`, with no new `play` call.
    - Back in the guide → `.player`; Back in the guide with nothing playing → `.leave`.
    - `.groupChanged` → `library.state.lastGroup` updated.
    - No last channel → `open()` ends in `.guide`, with nothing played.
    - Programmes loaded for the guide's channels (fixture guide).
  - Done when:
    - The tests pass.
    - **Manual (windowed):** Select opens the guide. Video continues in the top-right preview; check for a black preview and see Risks.
      - The grid shows channels, times and a now line.
      - Paste the US2 guide URL (*The chosen guide*). With MMTVL running, write the draft `epg-overrides.json` to `~/Library/Application Support/MMTVL/`, then Settings → Live TV → Refresh Now.
      - Expect programmes on about 58 of the 97 live channels (e.g. NFL Network, Fox Sports 1, MSG, Root Sports NW) and "No information" on the FanDuel regionals and international channels.
      - Up/Down/Left/Right move focus. Left at now opens the groups; choosing "NBA Games" shows only those.
      - Select plays a channel full screen.
      - Overlays draw **above** the video in both modes.

- [ ] **11. Docs wrap-up**: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - **CLAUDE.md:**
    - Keychain accounts `iptv-playlist-url` and `iptv-guide-url`.
    - `iptv-state.json` (last channel/group, guide import bookkeeping; hand edits are allowed while MMTVL is quit).
    - `guide.sqlite` in the D10 directory: the EPG cache, safe to delete.
    - `epg-overrides.json` (L17): `{ "<channel name or tvg-id>": "<EPG channel id>" }`. Hand-edited; applied by Settings → Live TV → Refresh Now. To find EPG ids, run `gzip -dc guide.xml.gz | grep -o '<channel id="[^"]*"'`.
    - "Never log full IPTV URLs (they carry tokens)".
    - Packages: MPVKit (LGPL product only) and GRDB, app target only; `Package.resolved` is committed.
    - mpv logs: `log stream --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "MPV"'`.
  - **Master plan:** M4 → Done; check that D22/D23 and D7's buffer numbers match what was built.
  - Tick this plan's boxes and fill in the Manual verification results.
  - Done when the docs match the code.

- [ ] **12. Full test run and kiosk pass**: no files
  - `xcodebuild … test` passes.
  - Run every *Manual verification* item in kiosk mode, ideally on the Mac mini and TV.
  - Done when they're all ticked or recorded in Deviations.

## Tests

| File | Asserts |
|---|---|
| `MMTVLTests/SmokeTests.swift` (extend) | libmpv links (client API ≥ 2.5). |
| `MMTVLTests/M3UParserTests.swift` | Parser rules, the user's playlist shape, quirks. |
| `MMTVLTests/ChannelListTests.swift` | ids, VOD filtering, groups, "All Channels". |
| `MMTVLTests/ClipboardURLTests.swift` | Clipboard validation and messages. |
| `MMTVLTests/IPTVSourceStoreTests.swift` | In-memory and real-Keychain (test service) round trips. |
| `MMTVLTests/XMLTVTests.swift` | Dates, parser filtering, window, stop fill, episode text, chunked text. |
| `MMTVLTests/GunzipTests.swift` | gzip, concatenated members, plain detection. |
| `MMTVLTests/EPGMatcherTests.swift` | Normalization, id and name matching. |
| `MMTVLTests/EPGStoreTests.swift` | Replace, overlap queries, removal (in-memory GRDB). |
| `MMTVLTests/IPTVLibraryTests.swift` | Refresh policies, statuses, guide sources, import, removal. |
| `MMTVLTests/IPTVTestSupport.swift` | Fixtures, fake network, `makeLibrary`. |
| `MMTVLTests/TimeshiftTests.swift` | cache-state JSON parsing, behind-live, clamping, labels. |
| `MMTVLTests/GuideTimelineTests.swift` | Window, spans, reveal, ticks. |
| `MMTVLTests/GuideModelTests.swift` | Guide navigation and groups. |
| `MMTVLTests/FakePlayer.swift`, `FakeLiveTV.swift` | Test doubles. |
| `MMTVLTests/LiveTVModelTests.swift` | Modes, zapping, seeks, failures, guide integration. |
| `MMTVLTests/AppRouterTests.swift` (extend) | Live TV routing, Settings handoff with/without PIN. |
| `MMTVLTests/SettingsModelTests.swift` (extend) | Live TV page, paste messages, confirm page. |

Commands (see CLAUDE.md):

```sh
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test -only-testing:'MMTVLTests/M3UParserTests'
```

Tests never touch the network or mpv. The only exceptions are the real-Keychain test (test service) and `/usr/bin/gzip` in `GunzipTests`.

## Manual verification

Run in kiosk mode unless noted, ideally on the Mac mini and TV:

- [ ] Settings → Live TV: paste the playlist URL from the iPhone (Universal Clipboard) → the channel count shows. Record whether macOS asked for paste permission.
- [ ] Paste the US2 guide URL; the guide line shows a programme count. With `epg-overrides.json` installed, about 58 of the 97 live channels show programmes (e.g. NBA TV, MLB Network, Fox Sports 1, MSG).
- [ ] The Live TV tile resumes the last channel full screen in under ~3 s. The first time ever, it opens the guide.
- [ ] Up/Down change channel with the banner (now/next). Picture and sound are fine at the TV's resolution, with no stutter.
- [ ] **Rewind:** after 6+ minutes on a channel, hold Left/Rewind back **5 minutes**. It plays from there, and the bar shows "−5:xx". Fast-forward returns to "LIVE".
- [ ] Pause for 2 minutes, resume → it continues from the paused frame, behind live.
- [ ] The guide: preview video top right, the grid, the now line, the group list, Select plays. The overlays are readable from the couch.
- [ ] Home from the player and from the guide → the home screen, with playback stopped. The tile resumes.
- [ ] Sleep/wake while playing → home, stopped. The display didn't sleep during a long playback without input (the assertion).
- [ ] A Require PIN set on the Live TV tile asks for the PIN.
- [ ] Network down while playing → retries, then "Can't play this channel"; Select retries after reconnecting.
- [ ] A controller works the player and guide (D-pad, A, B, X = play/pause, shoulders = ±30 s).
- [ ] Activity Monitor: MMTVL memory while playing stays under about 1.2 GB, and CPU is low (hardware decoding).

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Video is black after leaving and re-entering Live TV (render context not recreated) | Step 8 re-entry check | Keep `MPVVideoView` alive: in `LauncherRootView`, keep `LiveTVRootView`'s video view in the hierarchy at `.opacity(0)` outside Live TV instead of removing it, so CA never releases its GL context. Record it in Deviations. |
| SwiftUI overlays don't draw above the OpenGL layer | Banner or guide hidden behind video | Put the video view in its own `NSView` under the `NSHostingView`. In `KioskWindowController`, add a container whose bottom subview is the video view and whose top subview is the hosting view with a clear background. Ask before restructuring. |
| The guide preview window is black or stretched | Step 10 | The render API follows bounds (verified in the spike). Check `needsDisplayOnBoundsChange` and that the frame change isn't animated. As a last resort, use the full window in guide mode with a dimmed background (no preview), and record it. |
| macOS paste-permission alert can't be answered with the remote | An alert over the kiosk window on first paste | It appears once. Click Allow with the mouse, or set System Settings → Privacy & Security → Paste from Other Apps → MMTVL → Allow. Document it in CLAUDE.md. |
| Pausing longer than the forward buffer (~8 min) breaks the stream | After a long pause: EOF and a reload, losing the buffer | Acceptable (L13 reloads at live). If it's common, raise `demuxer-max-bytes`. |
| Stream tokens rotate or expire | 403 on play | L13 refreshes the playlist once. If URLs expire often, lower the 10-minute staleness. |
| The provider blocks the URLSession or mpv user agent | Playlist or stream 403 | Make the user agent configurable: `settings.json` `iptvUserAgent`, applied to `IPTVNetwork` and mpv `user-agent`. Ask before adding. |
| A guide file is huge (hundreds of MB) | Long import, memory | Parsing streams at ~100 MB/s with flat memory. Only matched channels' programmes are kept. If imports take more than a minute, show "Updating guide…" and leave it; no change needed. |
| Name matching mismatches channels | Wrong programmes on a channel | Add or fix the channel in `epg-overrides.json` (L17), then Refresh Now. Matching stays exact (no fuzzy rules). Manual matching UI is M6. |
| US2 renames or drops channel ids | Channels lose guide data after a refresh | Overrides with missing targets fall through harmlessly. Update `epg-overrides.json` with the new ids. |
| `@concurrent` is forgotten and parsing blocks the UI | A beach ball during guide refresh | Mark `GuideImporter.importGuide` `@concurrent` (covered by review). |
| MPVKit binary download fails or Xcode re-resolves slowly | Package resolution errors | Retry `-resolvePackageDependencies`; the cache is in `~/Library/Caches/org.swift.swiftpm`. Don't switch to the GPL product. |
| HDR or 4K streams later | Washed-out colors | Out of scope; current streams are 720p SDR. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-10-06 (planner):** the user's provider was examined with redacted scripts and the spike (see *Research*).
- **2026-10-06 (planner):** the user chose guide-source US2 as the guide. Matching was measured against it, which added L17 (`epg-overrides.json`) and the `+`/`&` normalization to L6. Coverage is 58/97 live channels. The FanDuel regionals and international channels need a second guide source (M6), or the much larger ALL_SOURCES1 file.
