# M7f — TV findings: Plex on the TV, stream format

| | |
|---|---|
| Status | Done (2026-11-08) |
| Depends on | M7c (archived: foreground ladder, kiosk lock, item 20 logs) |
| Master plan decisions used | D18 (wake), D35 (foregrounding), D22 (mpv); from 2026-11-02 also D2 (focus), D14 (Multiview), D20 (PIN), D23 (playlist), D24 (phone remote), D26 (guides), D29 (glass), D38 (home layout); from step 6 D40 (IPTV refresh timer), D41 (on-screen keyboard) |
| Planned | 2026-10-14; trimmed 2026-11-02; findings 3–13 added 2026-11-02 |

## Goal

The user found four problems on the Mac mini (2026-10-14, build 18). **On 2026-11-02 the user reported that two of them no longer happen** (the dead remote after the TV was off, and Plex HTPC's Back after a video ends). They are parked: see *Parked findings* below. This milestone covers the other two:

1. **Plex HTPC was blank after the TV was off** and had to be quit. The cause is unknown. **User choice (2026-10-14): diagnose first.** MMTVL gets logging for display sleep and wake and for the windows of the app it opens. The next blank screen is captured, and the user decides on a fix after that (step 5).
2. **Stream format in the banner.** Live TV's channel banner shows the stream's format next to the channel name, e.g. **"1080i · 29.97 fps"** or **"720p · 59.94 fps"**.

**On 2026-11-02 the user added 11 more findings (3–13).** Research for each is below (*Research & findings* §3–13). Step 6 (2026-11-03) designed them with the user as L5–L13, except §12, which waits for its capture. Step 4's test build also captures what the TV shows for the guide, the groups, the second phone and the battery, and step 6 designs the findings with the user:

3. **On-screen keyboard.**
4. **Search in Live TV.**
5. **The guide has no info** for any channel.
6. **Channel groups go stale:** old games stay until MMTVL is relaunched.
7. **A Teams group:** every live game, on any channel, for the user's favorite teams.
8. **A larger home screen clock.**
9. **A little more glass.**
10. **PWA tiles reload** their page when opened.
11. **Multiview: Left/Right on the main window rotates the small windows' channels into it.**
12. **A second phone remote didn't work.**
13. **Siri Remote battery level** on the home screen.

## Out of scope

- **Any Plex fix before the capture in step 4.** The user decides after the capture. Implementing a fix is a follow-up step added to this plan.
- **Building any of findings 3–13 before its design is agreed in step 6.**
- **Typing in other apps** with the on-screen keyboard (Plex HTPC, the browser). Unless the user asks for it in step 6, the keyboard is for MMTVL's own screens.
- **The parked findings** (the remote after display sleep, Plex Back after playback). Re-plan them only if they come back.
- **The format on Multiview's chip.** Ask the user if they want it after step 4.
- **Deinterlacing.** `MPVOptions` stays as it is.
- **The Siri Remote driver spike and Q21:** [M7e](M7e-siri-remote-spike.md).
- **Going Home on display wake.** D18's go-home stays for system wake only.

## Research & findings

### 1. Plex blank after the TV was off: cause unknown

- **What a tile does.** It only calls `NSWorkspace.openApplication(at:configuration:)` with `activates = true` (`Launcher/AppLauncher.swift:213-235`). It does this whether or not the app is running. Nothing checks that an already-running Plex shows a window on the active Space.
- **Full screen.** Plex's tile has no `launchFullScreen`, so `WindowFullScreener` doesn't run for it. Plex HTPC does its own full screen.
- **Nothing on display changes.** No display-wake or screen-change handling touches other apps. `didChangeScreenParametersNotification` only refits MMTVL's window (`App/KioskWindowController.swift:59-79`, info level, so `log show` doesn't keep it). The item 20 Dock check (`ensureOnScreen`, `KioskWindowController.swift:132-175`) only checks MMTVL's own window, after an MMTVL `show`.
- **Display sleep and wake.** Only system wake is observed (`NSWorkspace.didWakeNotification`, `App/AppDelegate.swift:534-558`). Display sleep only stops the Live TV preview (`AppDelegate.swift:575-581`). Nothing observes `NSWorkspace.screensDidWakeNotification`.
- **MMTVL's home UI stays hidden.** `leaveHome(untilInactive:)` (`AppRouter.swift:326-347`) hides it once MMTVL is inactive, so nothing notices a blank Plex.
- **Two candidate causes:**
  - Plex's own bug: a [Plex forum report](https://forums.plex.tv/t/blank-grey-screen-on-macos/857573) describes a blank grey screen after the Mac wakes that only a relaunch clears. It started after Plex for Mac 1.67.2, and the thread has no answer.
  - A stale full-screen Space after HDMI drops, the same family as [M7c item 20](M7c-punchlist.md), where the Dock held a dead Space.
- **Logs today** only show "Launching tv.plex.htpc" (`AppLauncher`, notice). That's **Q22**.
- **Plex's own log** is `~/Library/Logs/Plex HTPC/Plex HTPC.log`.
- **Plex blank capture (TV check 2026-11-03, build 19).** The TV was **not** off: the user came back to Plex from other viewing and got pure black, with the mouse and Plex HTPC's menu bar working. Quitting Plex and opening it again is the only cure so far. Captured over SSH while black (script: window list via `CGWindowListCopyWindowInfo`, the L1 `log show` line, the Plex log tail):
  - **Plex's window was there, on screen, full screen and in front**: pid 12683, on-screen windows `1920×1080` at 0,0 and `1920×44` at 0,−44 (the hidden full-screen title bar). The probe agreed on all three opens (01:56:15, 01:56:37, 02:06:06): `tv.plex.htpc opened (was running: yes): frontmost yes, on-screen windows 2 [1920×44, 1920×1080], full screen yes`.
  - **No Dock problem**: every Home after it logged `window on the active Space true, visible true`, and no Dock restart ran. No `Displays slept`/`Displays woke` in 12 h.
  - **Plex had been in the background about 5 h 40 min**: MMTVL opened it fresh at 20:15:35 on 2026-11-02 and went Home at 20:16:16. MMTVL itself was relaunched twice meanwhile (00:39, 01:56).
  - **Plex's web client was alive while black**: the last 300 lines of its log (01:48–02:08) are only `[Web] … [Server Retry]` connection tests, every few seconds. No errors, nothing native.
  - **Conclusion:** not a stale Space. Plex's renderer stops drawing while the page keeps running, the same family as the forum report. Fix choice is step 5.
- **Plex blank history (TV check 2026-11-03, `plex-history.sh`).** MMTVL's log store only reaches back to 2026-11-02 13:29. Plex keeps 6 log files, one per run. Every run ends in `[Application] Terminated.` (the user's quit). Plex's `[DisplayManager] Found 1 Display(s)` lines mark display changes it saw:

  | Black open (MMTVL) | Plex in the background since | Display change Plex saw before it |
  |---|---|---|
  | 2026-11-01 ~16:49 (quit 16:49:01; no MMTVL log that old) | unknown | 16:47:52: a new display id (0x46, one 1920×1080 mode), back to 0x2 at 16:47:59 |
  | 2026-11-02 13:29:42 (quit 13:29:55) | unknown | 13:28:57: new id 0x11 (one 1920×1080 mode), back to 0x3 at 13:29:03, **45 s before the open** |
  | 2026-11-02 20:15:21 (quit 20:15:33) | 15:54 (4 h 21 min) | 18:10:48: new id 0x14 (one 1920×1080 mode), back to 0x3 at 18:10:54 |
  | 2026-11-03 01:56:13 (quit 02:13:21) | 20:16 (5 h 40 min) | 00:38:48 (mode list at MMTVL's build 19 install) and 00:51:18: new id 0x15 with 4K modes, while System Settings was in front |

  - **Every black open followed a display change while Plex was in the background.** The one-mode 1920×1080 display that appears for about 6 s looks like the receiver or TV re-sending its EDID (HDMI hot-plug: TV or receiver power, or an input switch). On 2026-11-03 it was a display settings change in System Settings. MMTVL's `Displays slept`/`Displays woke` didn't fire, because a hot-plug isn't display sleep.
  - **Time alone isn't shown to matter:** the 13:29 case went black 45 s after the display change. The history has no long background stretch without a display change, so no time limit can be read from it.

### 2. Stream format: nothing reads it today

**Not read anywhere** in `MMTVL/` or `MMTVLTests/`: `video-params`, `container-fps`, `estimated-vf-fps`, `video-frame-info` or `deinterlace`.

**`MPVHandle` (`IPTV/Player/MPVHandle.swift`):**
- It has no `mpv_observe_property` calls.
- It has synchronous getters `string(_:)` (`:67`) and `double(_:)` (`:74`), both called on the main thread.
- There's no int64 getter. Read sizes as strings and convert with `Int(...)`.

**`MPVPlayerController` (`IPTV/Player/LivePlayer.swift:32`):**
- It is `@Observable`, MainActor.
- `phaseDidChange()` (`:285-296`) runs a 0.5 s timer while playing or paused. That timer calls `pollTimeshift()` (`:298-306`).
- `pollTimeshift()` reads `time-pos` and `demuxer-cache-state`, and assigns `state.timeshift` only on change.
- **`PlayerState` (`:5-9`):** `nonisolated struct PlayerState: Equatable, Sendable { phase; timeshift }`. It is reset on `play()` (`:111`), `stop()` (`:124`) and failure (`:274`).

**mpv properties** (mpv manual, *Property List*):
- `video-params/w` and `video-params/h`: the decoded size.
- `container-fps`: the frame rate the container or stream reports.
- `estimated-vf-fps`: measured after filters. Used as the fallback.
- `video-frame-info/interlaced`: `yes` or `no`, from the current frame's flags.
- **Unverified:**
  - Whether `video-frame-info/interlaced` is filled with `hwdec=videotoolbox`.
  - Whether a 1080i stream reports 29.97 (frames) or 59.94 (fields) in `container-fps`.

  Step 4 records both. The label shows mpv's value as is (L3).

**TV check 2026-11-03 (build 19, mini):** the banner shows `720p` with a frame rate on the channels opened, as expected. So `video-frame-info/interlaced` is filled with VideoToolbox (the letter shows). Labels seen: `720p · 59.94 fps` and `720p · 29.97 fps`. **No 1080 channel found** in the playlist, so whether a 1080i stream reports 29.97 or 59.94 stays unverified; the label shows mpv's value as is (L3), so nothing changes. Format check done.

**Provider facts:**
- **the provider** is mostly 720p H.264 (master plan §3).
- Other formats need other channels to check. Use whatever the playlist has, and record what was seen.

**The banner:**
- **`LiveBannerView`** (`IPTV/LiveTVView.swift:205-255`):
  - Its channel line is `Text("\(banner.channel.number)  \(banner.channel.name)")` (`:215`), in `Theme.liveBannerTitleFont`.
  - Its details use `Theme.liveBannerDetailFont` (22) and `Theme.secondaryText`.
- **`PlayerOverlayView`** (`:123-202`) reads `model.player.state` (`:126`) and builds `LiveBannerView(banner:)`.
- **The pattern to copy** is `Timeshift` (`IPTV/Player/Timeshift.swift`), a `nonisolated` value type with a static parser and a `label`. Its tests are in `MMTVLTests/TimeshiftTests.swift`.

### 3. On-screen keyboard: no text entry exists

Paths in §3–13 are under `MMTVL/` unless they start with `MMTVLTests/` or `archive/` (= `docs/plans/archive/`).

- **No text fields anywhere.** There's no `TextField`, `SecureField`, `NSTextField` or `.searchable`. `RemoteCommand` (`Input/RemoteCommand.swift:3-6`) has no character command.
- **Text entry today:**
  - **PIN (D20):** digits only, with the D-pad. `PIN/PINPad.swift:3-72` (rows `[[1,2,3],[4,5,6],[7,8,9],[0]]`), `PIN/PINEntryView.swift`, `PIN/PINEntryModel.swift:44-54`. Its privacy design (it doesn't show which column was pressed) makes it a poor base for letters.
  - **URLs come from the clipboard:** playlist and guides at `Settings/SettingsModel+Pages.swift:414-466`, a tile's Start Page at `:309`, checked by `IPTV/Sources/ClipboardURL.swift`.
  - **Phone text:** the page sends the whole field (`RemoteServer/Web/remote.js:99-110`). The Mac diffs it (`RemoteServer/TextEdit.swift`) and types it with `SyntheticInput` (`Input/SyntheticInput.swift:73-92`). Inside MMTVL it's accepted only on YouTube (`App/AppDelegate.swift:230`); other screens get "Nothing to type into here".
  - **YouTube** uses leanback's own on-screen keyboard.
- **Features put off for lack of text entry:** URL tiles and renaming tiles (`archive/M2b-settings-screen.md:27, 484`), typing IPTV URLs (`archive/M4-live-tv.md:36`). Match Guide has no text search on purpose (D26).
- **The pattern for a new screen:** `AppRouter.Screen` (`Launcher/AppRouter.swift:15-21`) and `route(_:)` (`:500-600`). The `.pin` case (`:592-598`, `requestPIN`/`finishPIN` at `:629-700`) is the closest model: a modal screen that takes commands and returns a result. Grid focus: `Launcher/LauncherFocusModel.swift:53`. Custom focus (D2).
- **Other apps:** while another app is in front, `InputRouter.dispatch` only acts on global bindings (`Input/InputRouter.swift:73-83`), so an MMTVL keyboard over Plex or the browser would need its own input path (out of scope unless asked).
- **The phone can type into an MMTVL field** if `AppDelegate.swift:230`'s YouTube-only check is widened. That gives search a second way in, besides the keyboard.
- **Open:** which screens get the keyboard first (Live TV search, §4); layout (alphabetical rows like tvOS, or QWERTY); whether a phone's text goes into the focused MMTVL field.
- **User choice (2026-11-03):** the **tvOS grid** (alphabetical rows), for MMTVL's own screens, Live TV search first; the phone's text types into it. Design: L11.

### 4. Search in Live TV: nothing to build on yet

- **No search today.** `EPGStore` queries by channel and time only: `programmes(refs:overlapping:)` (`IPTV/EPG/EPGStore.swift:121-135`). There's no FTS and no title query.
- **The channel list:** `ChannelLineup.init` (`IPTV/Sources/ChannelPreferences.swift:41-49`) drops hidden channels and groups and adds a synthetic **Favorites** group first, then `ChannelList.guideGroups` ("All Channels" plus the playlist's groups, `IPTV/Sources/Channel.swift:56-64`). `GuideModel` (`IPTV/Guide/GuideModel.swift:32-52`, `setLineup` `:93-106`) holds groups, channels and focus (`.grid/.channel/.groups`). A search can filter the lineup's channels in memory (the playlist is ~30 KB, D23).
- **Programme search** would be a new `EPGStore` query (title `LIKE`, or an FTS5 table built at import). It only finds channels that matched at import time (`IPTV/EPG/GuideImporter.swift:37-41`).
- **Depends on** §3 (or phone text).
- **Open:** channels only, or programmes too; where it opens (a Search row in the group list, or a key); what Select on a result does (tune, or jump in the guide).
- **User choice (2026-11-03):** **channels and programmes** (now through the next 24 h); Select on a channel or a programme on now tunes it, on a later programme it jumps the guide there. Where it opens was not asked: a Search row at the top of the guide's group list, and phone text. Design: L12.

### 5. The guide has no info: no refresh while MMTVL keeps running

- **Thresholds:** a guide is stale after 12 h, the playlist after 10 min (`IPTV/IPTVLibrary.swift:17-18`).
- **When a guide refresh runs:** at launch (`App/AppDelegate.swift:179-185`), each time Live TV opens (`refreshGuideIfStale()`, `IPTV/LiveTVModel.swift:134, 141`), and Settings → Live TV → Refresh Now (`refreshAll()`, `AppDelegate.swift:799-802`). **No timer; wake (`AppDelegate.swift:547-559`) doesn't touch IPTV.**
- **The import** keeps programmes in [now − 6 h, now + 4 d] (`IPTV/EPG/GuideImporter.swift:35`). `replaceSource` swaps a guide's rows in one transaction (`EPGStore.swift:88-104`). Nothing prunes by age, so Settings' "N programmes" count (`AppDelegate.swift:470`) includes expired rows and can look healthy while the grid is empty.
- **Ways it can end up empty:**
  - **The import is skipped while `channels` is empty** (`IPTVLibrary.swift:174`). On Live TV's open path the guide check runs before the playlist check (`LiveTVModel.swift:141-143`), so after a failed launch fetch that open skips the import.
  - **A failed import** keeps the old rows, doesn't touch `guideImports` and sets status `.failed` (`IPTVLibrary.swift:191-196`). The failure log is error level (kept). The success log, "Guide from host: N channels, M programmes, K matched" (`GuideImporter.swift:43`), is info level and isn't kept.
  - **The guide file is short:** on the dev Mac the last import (2026-10-09 20:41) had programmes only to 2026-10-12 10:00, about 2.5 days.
  - **Ids changed:** on the dev Mac `iptv-state.json` has ids like `id:fox sports 1` but `iptv-channels.json` favorites look like `id:foxsports1.us`. If the provider changed its `tvg-id`s, id matches (and favorites) are lost. Name overrides still match (`IPTV/EPG/EPGMatcher.swift:40-80`).
  - **Related:** the home Live TV preview skips the playlist check (§6). It doesn't skip the guide check.
- **Capture on the mini (step 4):** `guideImports` in `iptv-state.json`, Settings → Live TV's guide status and programme count, whether Refresh Now fixes it, and:
  ```sh
  /usr/bin/log show --last 24h --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "IPTV"' --info
  ```
- **Open:** whether a timed refresh (e.g. every 12 h, plus after wake) is enough, or the mini shows a failing import.
- **Step 6 (2026-11-03):** L5's 15-minute timer also runs `refreshGuideIfStale()` (12 h), so a guide can no longer go stale while MMTVL runs. If the TV still shows an empty guide after that, design a fix from the capture.
- **TV check 2026-11-03 (build 19):** the provider had changed the account's playlist path, and the old link got HTTP 403 (*Deviations*). With no channels, guide imports are skipped (`IPTVLibrary.swift:174`), which fits "no info for any channel". After the user pasted the new link, the guide shows info again. Settings → Live TV → Guides: one pasted guide, `guide-source.online · guide-source_US2.xml.gz`, 3,673 programmes, 49 channels, guide data for **49 of 214** channels (game channels have none, §7). The playlist header is a bare `#EXTM3U` (no `url-tvg`), so there's no playlist guide. Still open: whether the guide also goes stale while MMTVL keeps running (no refresh timer). Watch it over the next days before designing a timer.

### 6. Groups go stale: the home preview skips the playlist refresh

- **Cause, from the code:** `open()` calls `refreshPlaylistIfStale()` only on the non-preview path (`IPTV/LiveTVModel.swift:142-143`). When the muted home preview is playing (on by default, D37; it preloads on the whole home screen, `Launcher/AppRouter.swift:210-226`), `adoptPreview` returns early with no playlist check (`LiveTVModel.swift:131-136`). Leaving Live TV keeps the channel as the preview (`:267-294`), so every later open adopts it again. **The playlist is re-fetched only at launch, by Refresh Now, or after a playback failure** (`:1061, :1078`). That matches the user's report.
- **No timer** re-fetches the playlist either (D23 says "at launch, when Live TV opens (if older than 10 min) and on demand").
- **A re-fetch already updates an open guide** through `.onChange(of: library.lineup)` (`IPTV/LiveTVView.swift:55`) → `GuideModel.setLineup`. There's no separate group cache.
- **When channels go away:** the selected group falls back to index 0 (`IPTV/Guide/GuideModel.swift:98`), a missing last channel opens the guide (`LiveTVModel.swift:172-176`), Multiview slots become nil (`IPTV/Multiview/MultiviewModel.swift:33-37`), favorite ids are kept and ignored (`IPTV/Sources/ChannelPreferences.swift:3-4`).
- **Open:** the interval (D23's 10 min on open, plus a timer while MMTVL runs?), and whether a re-fetch should change the preview's channel when it's gone.
- **User choices (2026-11-03):** every Live TV open checks the playlist, plus a **timer every 15 minutes and after wake**. When a re-fetch removes the preview's channel, the preview **moves to the Live TV carousel's first page, falling back to the first favorite**. Design: L5.

### 7. A Teams group: game channels carry no guide data

- **What exists:** favorites are channel ids in order (`IPTV/Sources/ChannelPreferences.swift:9`). The only synthetic group is Favorites (`channels(in:)`, `:52-56`). This is where a Teams group would go.
- **Game channels** (M4 research, `archive/M4-live-tv.md:49, 68`) sit in groups like "NBA Games" and "NHL Games", have `tvg-type="movie"`, use the event name as `tvg-id` (e.g. `"Philadelphia @ Tampa Bay-A"`) and **have no guide data**. They change daily (D23). Nothing parses them: the id is `"id:" + tvgID.lowercased()` (`IPTV/Sources/Channel.swift:32`).
- **Network channels** (ESPN, FanDuel regionals) do have guide data. Programmes store `title`, `subtitle`, `summary`, the first `category` and `episode` (`IPTV/EPG/Programme.swift:9-23`). There's no "airing now on every channel" query; the top shelf loops `nowNext` per channel (`Launcher/TopShelf.swift:177-180`, `IPTV/IPTVLibrary.swift:455-479`).
- **Matching a team** therefore means: game channels by name (city or team, league from the group name, since "Philadelphia" alone is four teams), and network channels by the airing programme's title.
- **Open:** how teams are picked (a list per league built from the group names and channel names? the remote has no typing, §3); whether "live" means only now or also games starting soon; whether a game with several feeds (`-A`, `-B`) shows once.
- **The playlist on 2026-11-03 (dev Mac, redacted: names and groups only):** 202 entries in four groups: `Live-Channels` 96, **`Live-Games` 8**, `NFL-Replays` 71, `MLB-Replays` 27. The M4 groups ("NBA Games", "NHL Games"…) are gone, so the league isn't in the group name any more. But **game entries now use full team names**, two feeds each:
  - `Vegas Golden Knights @ Boston Bruins-H` and `…-A`, `Miami Heat @ Los Angeles Lakers-H`/`-A`, `Toronto Raptors @ Los Angeles Clippers-H`/`-A`, `Phoenix Suns @ Golden State Warriors-H`/`-A`. The `tvg-id` is the same text; `tvg-logo` is empty.
  - Replays have no suffix (`Kansas City Chiefs @ Denver Broncos`), and some repeat (`Milwaukee Brewers @ Tampa Bay Rays` three times, ids `#2`, `#3` by `ChannelList.make`).
  - So a full team name matches a game exactly. "Los Angeles" alone would be ambiguous (Lakers, Clippers, Rams, Chargers, Kings, Dodgers, Angels).
  - `-H`/`-A` are read as the home and away broadcasts (unverified, from the names).
- **User choices (2026-11-03):** teams are picked from a **built-in team list** in Settings **and** from a game in the guide; the Teams group shows **both feeds** (renamed, your team's feed first) **plus network channels** whose guide says one of your teams is on now. Design: L13.

### 8. Home clock: `.title2`, about 17 pt

- Drawn at `Launcher/HomeView.swift:140-144` (a `TimelineView(.everyMinute)` in `capsule(_:)`, `:147-155`: padding 20 × 8, `.glassPanel(in: Capsule())`, `.monospacedDigit()`).
- **Font:** `Theme.clockFont = Font.title2` (`DesignSystem/Theme.swift:35`), about 17 pt regular on the 1920 × 1080 canvas. Very small for across the room: the carousel title is 64 bold. The same token is used by the version capsule under the clock (`HomeView.swift:105`) and by `Launcher/AccessibilityOnboardingView.swift:18`, so the clock needs its own token.
- **Position:** top-right, a trailing `VStack` with `homeClockStackSpacing` 12, `.padding(.top, 60)` (a literal, not a token) and `Theme.sideMargin` 120 (`HomeView.swift:103-111`).
- **Neighbors:** the hero info is top-left (`Theme.carouselInfoOrigin` (120, 80), max width 900); shelf cards start at y = 140 (`Theme.swift:167-168`); the clock scrim has endRadius 480 (`Launcher/TopShelfView.swift:39-40`); the fade over scrolled rows is `homeClockFadeHeight` 160 (`Theme.swift:72`), and today's clock plus version is about 138 pt tall.
- **Open:** the size (tvOS's clock is about 38 pt on a 1080 canvas); whether the version line grows too.
- **User choice (2026-11-03): 38 pt.** The version line stays as it is. Design: L7.

### 9. Glass: `.regular` with a drawn rim

- `GlassPanel` (`DesignSystem/Glass.swift:5-16`) is `glassEffect(.regular, in: shape)`, with no tint or `.interactive()`. With Reduce Transparency it becomes `Theme.solidPanelFill` (#1C1C1E at 0.92, `Theme.swift:185`).
- `GlassRim` (`Glass.swift:19-40`) is an overlay: a `plusLighter` sheen (`glassSheen` 0.10, focused 0.18) and a gradient stroke, `glassRimWidth` 1.5:

  | Rim part | Normal | Focused |
  |---|---|---|
  | Top | 0.55 | 0.85 |
  | Middle | 0.08 | 0.08 |
  | Bottom | 0.25 | 0.40 |

  It has no Reduce Transparency branch. Tokens: `Theme.swift:175-183`.
- **Used by:** the dock (`Launcher/HomeView.swift:73`), the clock capsules (`:154`), tiles (`AppTileView.swift:62`), shelf cards (`TopShelfView.swift:168`), carousel info (`ShelfCarouselView.swift:96`), Settings, PIN, the guide, Live TV and Multiview panels.
- **Knobs:** the glass variant (`.clear` is more see-through), a tint, `.interactive()`, the sheen and rim opacities and the rim width.
- **Open:** which part "more glass" means (the dock and panels, or the tiles' rims). This needs a side-by-side check on the TV; a test build with two strengths is cheapest.
- **User choice (2026-11-03):** **both** the dock and panels and the tile rims. No compare toggle. Design: L9.

### 10. PWA tiles: an already-open web app is only activated

- **How they open:** `WebApp.info` (`Launcher/AppLauncher.swift:45-59`) reads the Chromium shim's `CrAppMode…` keys. Without a Start Page the shim is opened with `activates = true` (`:228-235`). With `startURL` the browser gets `--app-id=… --app-launch-url-for-shortcuts-menu-item=…` (`:62-64, 224-226, 275-288`). `findWebAppWindow` polls 10 s for the window (`:292-314`). **Nothing reloads** a web app that's already open.
- **Ways to reload:**
  - **⌘R to the app:** `SyntheticInput.postKey(_:flags:toPid:)` (`Input/SyntheticInput.swift:38-51`); precedent: ⌘W to Reflector (`Cast/ReflectorMonitor.swift:97`). The window can belong to the browser instead of the shim (hand-off, start page), so the pid comes from the window `findWebAppWindow` found.
  - **The View menu's Reload through AX:** `Launcher/BrowserToolbar.swift:19-51` presses a View menu item by title prefix, with retries. Its title is hard-coded and it runs only for browser tiles (`AppLauncher.swift:320-327`). Unknown whether a PWA window's menu bar has Reload.
- **Open:** reload on every open, or only when the web app was already running (a reload drops a Google Meet call in progress); which tiles (all web apps, or a per-tile setting like `launchFullScreen`).
- **User choice (2026-11-03):** reload **when the web app was already running**, for every web app tile **except calling apps as a category** (Meet, FaceTime and the like). Native apps never reload. Design: L10.

### 11. Multiview Left/Right: today they move the highlight

- **Today:** every arrow calls `moveFocus` (`IPTV/LiveTVModel.swift:770-774`) → `layout.neighbor` (`IPTV/Multiview/MultiviewLayout.swift:76-104`), and sound follows the highlight (`IPTV/Multiview/MultiviewModel.swift:73-78`). The main window is slot 0 in 1 + 4, 1 + 3, 1 + 2 and Picture in Picture, and there's none in 2 × 2 and Side by Side (`MultiviewLayout.swift:37-42`). From the main window:

  | Layout | Left | Right |
  |---|---|---|
  | 1 + 4 | nothing | nothing |
  | 1 + 3 | nothing | to slot 2 |
  | 1 + 2 | nothing | to slot 1 |
  | Picture in Picture | nothing | to slot 1 |

- **User choice (2026-11-02):** with the main window highlighted, Right puts the next small window's channel in the main window and the old main channel in that window; Left goes the other way. The highlight and sound stay on the main window.
- **To reuse:** `makeMain(slot)` (`MultiviewModel.swift:115-120`, the window menu's **Make Main**, `LiveTVModel.swift:574-578, 660-662`) and `assign`'s swap (`MultiviewModel.swift:101-112`). Players are keyed by channel id (`tilePlayers`), so a swap doesn't reconnect. Channel Up/Down already zaps the highlighted window (`zapWindow`, `LiveTVModel.swift:805-819`).
- **Open:**
  - In 1 + 3, 1 + 2 and Picture in Picture, Right is today's way from the main window to the small windows. Which key reaches them after the change (Up/Down? Back?)?
  - Rotation order and empty windows: rotate in slot order and skip empty slots?
  - 2 × 2 and Side by Side have no main window and keep today's moves.
- **User choices (2026-11-03):** Left/Right **rotate every window's channel** one place (Right: the first small window's channel goes into the main window and the main channel to the last small window). **Down** from the main window highlights the first small window. Design: L6.

### 12. A second phone didn't work: dead sockets can fill the 8 sessions

- **Several phones are allowed by design:**
  - `RemoteServer.maxSessions = 8` (`RemoteServer/RemoteServer.swift:16`), and each socket gets its own session (`:44, 270-272`).
  - Up to 10 phones can be paired (`RemoteServer/Pairing.swift:33-41`, `RemoteServer/PhoneRemote.swift:41, 219-222`).
  - A test covers two sessions (`MMTVLTests/PhoneRemoteTests.swift:132-137`), and Settings shows "N connected now" (`Settings/SettingsModel+Pages.swift:546-547`).
- **The user saw a second phone fail on the TV (2026-11-02).** How it failed isn't recorded yet.
- **Candidate cause (code read, unconfirmed):**
  - The server only answers pings (`autoReplyPing`, `RemoteServer.swift:106`) and never sends its own. Sockets have no idle timeout (only HTTP connections do, `:18, 205`).
  - A phone that locks or leaves Wi-Fi can leave a half-open socket in `sessions`. The page opens a new one on `visibilitychange` (`RemoteServer/Web/remote.js:183`) and after `onclose` (`:47-51`).
  - Sockets that never authenticate count too.
  - After a few lock and unlock cycles the 8 slots can fill, and the next phone is refused at accept (`RemoteServer.swift:265-269`). That log line ("Refused a phone connection: 8 already open") is info level, so `log show` doesn't keep it.
- **Other candidates:**
  - **Pairing is only open on Settings → Phone Remote → Pair a Phone.** A second phone opening the page later just sees the pairing screen.
  - **Both phones share one `PhonePointer` and click counter** (`Input/PhonePointer.swift:69-71`, `App/AppDelegate.swift:32`). Two trackpads fight over the cursor.
- **Capture (step 4):** with the second phone, note what its page shows (Connecting…, the pairing screen, or buttons that do nothing). Then run the `PhoneRemote` `log stream` line from CLAUDE.md and check Settings → Phone Remote's "N connected now".

### 13. Siri Remote battery: no battery code, and the remote's path is unknown

- **No battery code anywhere.** `Input/ControllerInput.swift` observes connects and disconnects (`:25-39`) and logs the vendor and profile (`:51-55`). It keeps no `GCController` and never reads `GCController.battery`. It runs only with `controllersEnabled` (`App/AppDelegate.swift:164-166`).
- **How the remote arrives:** the TV button works as Home because it was learned as **controller A** (CLAUDE.md, Siri Remote note). **M7e hasn't settled whether controller A is the Siri Remote itself or a virtual controller from Remote Buddy** ([M7e](M7e-siri-remote-spike.md), line 37). If it's virtual, `GCController.battery` is probably nil.
- **Ways to read it:**
  - `GCController.battery?.batteryLevel` and `batteryState`.
  - The IOKit registry: `AppleDeviceManagementHIDEventService` → `BatteryPercent`, what `ioreg` shows. IOKit is already imported (`IPTV/Player/SleepAssertion.swift:1`). The app isn't sandboxed, so this probably needs no permission (unverified).
  - IOBluetooth probably needs the Bluetooth permission. Avoid it.
- **M7e's probe** (line 59) prints the vendor, category and profile. Adding `battery` there answers the first two unknowns on the mini.
- **Where it would show:** the right-aligned stack under the clock (`Launcher/HomeView.swift:103-111`), fed the way the version label is (`AppRouter.homeVersionLabel`, `Launcher/AppRouter.swift:57, 894`; `AppDelegate.swift:154, 664`). It shares the space with §8's larger clock.
- **On the mini:** see whether the remote reports a value:
  ```sh
  ioreg -r -k BatteryPercent | grep -E '"Product"|BatteryPercent'
  ```
- **User choices (2026-11-03):** shown **always**; **below 15 %** it slowly flashes red; use the **private function**. It must work for **any** Siri Remote connected (a replacement), never one serial number.
  - So: match `Vendor ID` 76 and the Siri Remote product IDs (614, 621, 788, 789, from Apple's driver's `ProductIDArray`), never the name or serial. Several connected: show the lowest. A future remote model with a new product ID would need its ID added (it would show nothing until then).
  - With Reduce Motion, solid red instead of flashing (to confirm in step 6).
- **Open:** what to show when there's no value (no remote connected); the exact look (icon and percent) next to the larger clock (§8).
- **TV check 2026-11-03 (mini):** `ioreg -r -k BatteryPercent` printed nothing: no IOKit service on the mini reports `BatteryPercent`, so the IOKit way doesn't work as written. Then `system_profiler SPBluetoothDataType | grep -i -A12 remote` printed nothing (no paired Bluetooth device with "remote" in its name), and `ioreg -l` showed no remote product and no device battery (only NVRAM and power-management keys). ~~Nothing on the mini reports a remote battery today~~ **Correction (same day):** System Settings → Bluetooth lists the remote under its serial number, **`C08S29062330`, Connected, 88 %**, so it is paired with the mini by Bluetooth and macOS knows its battery. The `remote` greps missed it because of the name. Next: find where that 88 % can be read (`system_profiler SPBluetoothDataType`, the IORegistry entry for that device, `GCController.battery`).
  - `system_profiler SPBluetoothDataType`: `C08S29062330`, vendor `0x004C` (Apple), product `0x0315` (789), firmware `0x0021`, services `BLE`. **No battery line.**
  - IORegistry: the remote is a native Bluetooth HID device (Product and SerialNumber `C08S29062330`, VendorID 76, ProductID 789) with Apple's drivers `AppleEmbeddedBluetoothButtons`, `…Touch`, `…DeviceManagement`, `…Infrared`, `…Radio`, `…Audio`, `…Proximity` (`ProductIDArray` (614, 621, 788, 789)). **No battery key** in what was printed. With the earlier empty `ioreg -r -k BatteryPercent`, the registry doesn't seem to hold it.
  - **For M7e:** macOS drives the remote itself (Apple's HID drivers), so it isn't a Remote Buddy virtual device. Whether `GameController` also sees it (controller A) is still M7e's probe.
  - **`pmset -g accps` on the mini: ` -C08S29062330 (id=23860104)    88%; discharging present: true`.** The power-sources list has it. (`…DeviceManagement`'s properties have no battery key.)
- **How MMTVL can read it (tested on the dev Mac, 2026-11-03):**
  - The public `IOPSCopyPowerSourcesInfo()` + `IOPSCopyPowerSourcesList` returns **0 sources** on a desktop Mac: it lists internal batteries and UPSs, **not accessories**.
  - The **private** `IOPSCopyPowerSourcesByType(0)` (IOKit, exported, not in the public headers; reached with `dlsym`) returns the accessories. Read each with the public `IOPSGetPowerSourceDescription`. On the dev Mac it gave `Type = "Accessory Source"`, `Transport Type = "Bluetooth"`, `Vendor ID = 76`, `Product ID = 804` (Magic Trackpad), `Current Capacity = 85`, `Max Capacity = 100`, `Is Charging = 0`, `Power Source State = "Battery Power"`. Types 1–3 were empty.
  - **Identify the remote** by `Vendor ID` 76 and `Product ID` in (614, 621, 788, 789), the Siri Remote IDs from the remote's `ProductIDArray`. Not by name: the name is the serial number.
  - Percent = `Current Capacity` / `Max Capacity`. No permission needed (MMTVL isn't sandboxed).
  - **Risk:** a private function can change in a macOS update. If `dlsym` finds nothing, or the list has no remote, show nothing. Fallback without private API: run `/usr/bin/pmset -g accps` and parse the `-<name> (id=…) NN%;` lines (it has no product ID, so it would have to match the remote by elimination or by name).
  - **Updates:** poll (e.g. every 5 minutes and when the home screen appears). Whether `IOPSNotificationCreateRunLoopSource` also fires for accessories is unverified.
- **User choice (2026-11-03, step 6):** a **Siri Remote symbol with only the percent**, **to the right of the time**. Design: L8. Assumed (not asked): nothing shows when no remote reports a level.

### 14. Choose the provider's guide or the pasted guides (added 2026-11-03)

- **User request (2026-11-03):** a choice in Settings between the provider's guide and the pasted guide URLs, keeping the pasted URLs (in the Keychain) when they aren't in use.
- **What exists:** a guide named in the playlist header (`url-tvg` / `x-tvg-url`, `IPTV/Sources/M3UParser.swift:25-62`) is already used, but only when no guide is pasted (`IPTVLibrary.updateGuideSources()`, `IPTV/IPTVLibrary.swift:534-538`). Settings marks it **From Playlist** (`Settings/SettingsModel+Pages.swift:451-469`).
- **The provider today:** the new playlist's header is a bare `#EXTM3U`, the account page lists no EPG link, and 210 of 214 entries have a `tvg-id`. The provider's **website** shows programme info, from a source not yet known (probably an internal web API behind the account login).
- **So there's nothing to switch to yet.** A switch would need either the provider adding `url-tvg` (then a *Use Playlist's Guide* choice is cheap: `updateGuideSources` picks by a setting instead of "pasted wins"), or MMTVL reading the website's programme data (a new source type; needs research into what the site calls, whether it needs the login, and its format).
- **Open:** park it until the provider names a guide; build the cheap switch now (shown only when the playlist names a guide); or research the website's data.
- **User choice (2026-11-03): build the switch now** (L4). It shows once the playlist names a guide.

## Design

### Local decisions

- **L1 — Diagnostics. Every line is notice level, so `log show` keeps it.**
  - **New category `Display`**, in `AppDelegate` (`private static let displayLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Display")`):
    - "Displays slept": the existing `screensDidSleep` observer.
    - "Displays woke": a new observer of `NSWorkspace.screensDidWakeNotification` on the workspace notification center, in kiosk mode, next to `observeWake()`. **It only logs.** No foreground repair, no Home.
    - "Screen parameters changed: N screens, main W×H": a new observer of `NSApplication.didChangeScreenParametersNotification` in `AppDelegate`. The refit stays in `KioskWindowController`.
  - **`KioskWindowController.appDidResignActive`:** the notice becomes `"In the background (front: \(bundleID)); presentation options cleared"`, using `NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"`, with privacy `.public`. (This also helps if the parked remote finding comes back.)
  - **`AppLauncher` window probe**, for `.application` launches only (not web app hand-offs):
    - Before `openApplication`, set `let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty`.
    - After it returns, start `Task { try? await Task.sleep(for: .seconds(2)); logWindows(...) }`. It logs:

      `"<bundleID> opened (was running: yes/no): frontmost yes/no, on-screen windows N [W×H, …], full screen yes/no/unknown"`

      - **Windows:** `WindowSnapshot.onScreen(pid:)`, keeping layer-0 windows only.
      - **Full screen:** `WindowFullScreener.isFullScreen(pid:)`.
      - Sizes are rounded to whole points. **Never window titles.**
  - **`WindowSnapshot.onScreen(pid:)`** goes in `Cast/MirroringDetector.swift`, next to `WindowSnapshot`:
    - `nonisolated static func onScreen(pid: pid_t) -> [WindowSnapshot]`.
    - Move the `CGWindowListCopyWindowInfo` code out of `ReflectorMonitor.poll()` (`Cast/ReflectorMonitor.swift:175-186`), and have `poll()` call the new function. Behavior is unchanged.
  - **`WindowFullScreener.isFullScreen(pid:) -> Bool?`:** returns nil if the app has no window, using `mainWindow(of: AXUIElementCreateApplication(pid))` and the existing private `isFullScreen(_:)` (`Launcher/WindowFullScreener.swift:94-110`).
  - **CLAUDE.md:** add a `Display` line to the commands block:
    ```sh
    # Display sleep/wake and screen changes, kept in the log store (M7f)
    /usr/bin/log show --last 12h --predicate 'subsystem == "dev.mmtvl.launcher" AND (category == "Display" OR category == "Foreground" OR category == "KioskWindowController" OR category == "AppLauncher")' --info
    ```
- **L2 — `VideoFormat`**, a new file `IPTV/Player/VideoFormat.swift`:
  ```swift
  nonisolated struct VideoFormat: Equatable, Sendable {
      var width: Int
      var height: Int
      var fps: Double?
      /// nil when mpv doesn't say (unverified with VideoToolbox).
      var interlaced: Bool?

      /// Raw mpv property strings; nil without a positive size.
      static func parse(width: String?, height: String?, fps: String?, interlaced: String?) -> VideoFormat?
      var resolutionLabel: String   // "480i", "720p", "1080i", "4K", "1080" (interlaced nil)
      var fpsLabel: String?         // "29.97 fps", "60 fps", "23.98 fps"; nil without fps
      var label: String             // "1080i · 29.97 fps", or resolutionLabel alone
  }
  ```
  - **Resolution names, by height:**

    | Height | Name |
    |---|---|
    | below 400 | the height itself (e.g. "360") |
    | 400–500 | "480" |
    | 501–600 | "576" |
    | 601–800 | "720" |
    | 801–1200 | "1080" |
    | 1201–1600 | "1440" |
    | above 1600 | "4K" |

    A width of 3200 or more is also "4K". "4K" never gets a letter.
  - **The letter:** append "i" when `interlaced == true` and "p" when it's `false`. When it's nil, append nothing.
  - **`parse`:**
    - `interlaced` is `"yes"` → true, `"no"` → false, anything else → nil.
    - `fps` goes through `Double(...)`. Ignore values ≤ 0 or non-finite.
  - **`fpsLabel`:** `String(format: "%.2f", fps)`, then strip trailing zeros and a trailing ".". Append " fps".
  - Separator: " · " (U+00B7).
- **L3 — Reading and showing the format.**
  - **`PlayerState`** gets `var videoFormat: VideoFormat? = nil`. The resets in `play()`, `stop()` and failure clear it already, because they build a new `PlayerState`. Check each one.
  - **The poll.** At the end of `pollTimeshift()`:
    ```swift
    let format = VideoFormat.parse(width: mpv.string("video-params/w"), height: mpv.string("video-params/h"),
                                   fps: mpv.string("container-fps") ?? mpv.string("estimated-vf-fps"),
                                   interlaced: mpv.string("video-frame-info/interlaced"))
    if format != state.videoFormat { state.videoFormat = format }
    ```
    - The frame rate is shown as mpv reports it, with no field or frame conversion.
    - A mid-stream variant change (adaptive HLS) shows up within 0.5 s.
    - Log the first format of each channel once, at notice level, in the `MPV` category: "Format 1080i · 29.97 fps". There's nothing secret in it. This is so step 4 can read it after the fact.
  - **`LiveBannerView`** gets `var format: VideoFormat? = nil`.
    - The channel line becomes an `HStack(alignment: .firstTextBaseline)` with:
      - the existing title `Text`
      - `Spacer(minLength: 24)`
      - `if let format { Text(format.label).font(Theme.liveBannerDetailFont.monospacedDigit()).foregroundStyle(Theme.secondaryText) }`
    - `PlayerOverlayView` passes `format: state.videoFormat`.
    - The label shows only when known, and doesn't animate separately.
  - **Other uses.** If `LiveBannerView` is used anywhere other than `PlayerOverlayView` (grep), those callers keep the default nil.

- **L4 — Guide source switch (§14).**
  - **`settings.json` `usePlaylistGuide`** (Bool, default `false` = today: pasted guides win, the playlist's guide only without them). `AppSettings` key and `SettingKey.usePlaylistGuide`.
  - **`IPTVLibrary`:**
    - `var usePlaylistGuide = false { didSet { updateGuideSources() } }`, set by `AppDelegate` at launch before the first refresh.
    - `updateGuideSources()`: the playlist's guides when `usePlaylistGuide` and the playlist names one, or when nothing is pasted; else the pasted ones. The pasted URLs stay in the Keychain either way.
    - `var playlistNamesGuide: Bool { !playlistGuideURLs.isEmpty }` and `var customGuideSources: [GuideSource]` (every pasted guide, in order).
    - `func applyUsePlaylistGuide(_ use: Bool) async` (live change): set the flag; if `guideSources` changed, prune the guides no longer in use, rematch, tell Settings, then `refreshGuideIfStale()` (the newly used guide imports; its rows were pruned when it was last unused).
  - **`AppDelegate`:** sets `usePlaylistGuide` at launch; on a settings change calls `applyUsePlaylistGuide`. `IPTVSettingsStatus` gets `playlistNamesGuide`, and the guide list adds the **pasted guides not in use** after the ones in use (`GuideSourceStatus.isInUse = false`, line "Not in use (kept)").
  - **Settings → Live TV → Guides:**
    - First row **Guide Source**, value **Playlist** / **Pasted Guides**, detail "Your pasted guides are kept while the playlist's is used", `.toggle(.usePlaylistGuide)`. Shown only when `playlistNamesGuide` and at least one guide is pasted (otherwise there is no choice).
    - Pasted guides not in use keep their row (value "Off", dimmed) and their page (Move Up/Down, Remove).
  - **CLAUDE.md:** `usePlaylistGuide` in the `settings.json` list.

- **L5 — Playlist and guide refresh while MMTVL runs (§6, §5; D40).**
  - **The open path.** `LiveTVModel.open` (`IPTV/LiveTVModel.swift:131-136`): the adopt-preview branch also starts `Task { await library.refreshPlaylistIfStale() }`, next to its guide check. Playback isn't touched; a re-fetch reaches an open guide through `.onChange(of: library.lineup)` as today.
  - **The timer.** `IPTVLibrary`:
    - `static let autoRefreshInterval: TimeInterval = 15 * 60`.
    - `func refreshIfStale() async { await refreshPlaylistIfStale(); await refreshGuideIfStale() }`. The playlist goes first, so a guide import never runs with no channels (`IPTVLibrary.swift:174`).
    - `AppDelegate` starts a `Task` loop at launch (after the first refresh): sleep `autoRefreshInterval`, then `refreshIfStale()` when `library.hasPlaylist`; cancelled at terminate. In windowed mode too.
    - `systemDidWake()` (`AppDelegate.swift:581`) also calls `Task { await library.refreshIfStale() }`. The network may need a moment after wake; a failure is logged and the next tick retries.
    - The 10-minute playlist staleness stays, so a tick 15 minutes after an open always fetches.
  - **Logs.** The playlist's success line "Loaded N channels from host" becomes **notice** level (kept), so the TV check can see the refreshes. No URLs, host only (as today).
  - **The preview's channel is gone** (a game ended):
    - `LiveTVModel.defaultPreviewChannelID` (`:186-192`) returns Multiview's highlighted window or `lastChannelID` **only if that channel is still in `library.channels`**; otherwise the lineup's first favorite (`library.lineup.favorites.first?.id`); otherwise nil.
    - New `LiveTVModel.playlistDidChange()`: if `previewChannelID` isn't in `library.channels`, `stopPreview()`. `AppRouter` calls it from its existing lineup observation (or an `.onChange(of: library.lineup)` in the home view), then `updateLivePreview()`, which starts the new default.
    - The home carousel's pages start with the default channel (D38), so page 1 is then that channel. That's the user's "first page, then the first favorite".
    - `lastChannelID` is left alone. Live TV's open already handles a missing last channel (`LiveTVModel.swift:172-176`).
  - **Not changed:** the guide's 12 h staleness and the import window.

- **L6 — Multiview: Left/Right rotate the channels through the main window (§11).**
  - **`MultiviewModel.rotate(by step: Int)`** (`IPTV/Multiview/MultiviewModel.swift`):
    - Only with `layout.mainSlot` and at least 2 filled slots; otherwise a no-op that returns false.
    - Takes the filled slots in slot order (main first). Empty windows stay empty and are skipped.
    - `step = +1` (Right): each filled slot gets the channel of the next filled slot, and the last filled slot gets the old main channel (`A | B C D E` → `B | C D E A`). `-1` (Left) is the reverse (`A | B C D E` → `E | A B C D`).
    - `focusedSlot` and `audioSlot` stay on the main slot.
  - **`LiveTVModel.handleMultiview`** (`:770-774`), when `focusedSlot == layout.mainSlot`:
    - `.left`/`.right`: `rotate(by:)`, then `applyAudio()`, `showWindowChip()` and `saveSnapshot(true)` (as `assignWindow` does, `:880-892`). Players are keyed by channel id (`tilePlayers`), so nothing reconnects; each window just draws another player.
    - `.down`: highlight slot 1 (the first small window) in every layout with a main window, instead of `layout.neighbor`.
    - `.up`: unchanged (nothing).
  - From a small window, the arrows work as today (`layout.neighbor`), which reaches the main window again by position.
  - 2 × 2 and Side by Side have no main window: unchanged.
  - **Buffers (D7):** unchanged. Every window keeps its buffer profile; the main window isn't full screen.

- **L7 — Home clock 38 pt (§8).**
  - New token `Theme.homeClockFont = Font.system(size: 38, weight: .medium)`. The clock's capsule uses it. The version capsule and `AccessibilityOnboardingView` keep `Theme.clockFont`.
  - `capsule(_:)` (`Launcher/HomeView.swift:147-155`) takes the font as a parameter. Clock padding: 24 × 10.
  - The `.padding(.top, 60)` literal becomes `Theme.homeClockTop` (60).
  - `Theme.homeClockFadeHeight` 160 → **200**: the clock, the version and their spacing grow from about 138 to about 175 pt.
  - Check on the dev Mac in windowed mode that the clock doesn't touch the hero info (top-left, max width 900) or the Plex carousel's page dots.

- **L8 — Siri Remote battery to the right of the clock (§13).**
  - **`Input/RemoteBattery.swift`** (new):
    ```swift
    nonisolated enum RemoteBattery {
        /// Apple's Siri Remote product ids (its driver's ProductIDArray), vendor 76.
        static let productIDs: Set<Int> = [614, 621, 788, 789]
        /// The lowest percent of every connected Siri Remote; nil without one.
        static func level(from descriptions: [[String: Any]]) -> Int?
        /// Reads the private IOPSCopyPowerSourcesByType(0) through dlsym, then the public
        /// IOPSGetPowerSourceDescription. nil when the symbol is missing or nothing matches.
        static func current() -> Int?
    }
    ```
    - `level(from:)` keeps descriptions with `Type` "Accessory Source", `Vendor ID` 76 and a `Product ID` in `productIDs`. Percent = `Current Capacity` × 100 / `Max Capacity`, rounded, clamped to 0…100. Several remotes: the lowest. Never by name or serial number.
    - `current()` resolves the symbol once (`dlsym(dlopen(nil, RTLD_NOW), "IOPSCopyPowerSourcesByType")`; IOKit is already linked). It logs once at notice level (category `RemoteBattery`) when the symbol is missing, and when the first level is read ("Siri Remote battery N%"; no serial numbers).
  - **Polling.** `AppDelegate` reads it at launch, every 5 minutes, and when the home screen appears (`HomeView.onAppear` already calls `onRefreshShelf`; the router's handler also refreshes the battery). It sets `AppRouter.remoteBatteryLevel: Int?`, fed the way `homeVersionLabel` is.
  - **The view.** In `HomeView`'s top-right stack, the clock becomes an `HStack(spacing: 12)` of the clock capsule and, when the level isn't nil, a battery capsule in the same style and font (L7):
    - `Image(systemName: "appletvremote.gen4.fill")` and `Text("\(level)%")`, monospaced digits. Accessibility label "Siri Remote battery N percent".
    - **Below 15 %:** the capsule's content is `Theme.batteryLowColor` (system red) and slowly pulses (opacity 1 ↔ 0.35, 1.2 s, ease in and out, repeating). With Reduce Motion: solid red, no pulse.
    - The version capsule stays under the clock, right-aligned.
  - No value (no remote, or the private function is gone): nothing shows.
  - `controllersEnabled` doesn't matter: this doesn't use GameController.

- **L9 — More glass: the dock, panels and tile rims (§9).**
  - **Panels** (`GlassPanel`, `DesignSystem/Glass.swift:5-16`): `glassEffect(Theme.panelGlass, in: shape)` with `static let panelGlass = Glass.clear.tint(.black.opacity(0.22))` (more see-through than `.regular`; the tint keeps text readable). Panels also get a rim: `GlassPanel` overlays the same rim as `GlassRim` (unfocused values) when the shape is insettable, so the dock, clock, Settings and Live TV panels get an edge highlight. Reduce Transparency: unchanged (solid, no rim).
  - **Rims** (`Theme.swift:175-183`):

    | Token | Today | New |
    |---|---|---|
    | `glassRimWidth` | 1.5 | 2 |
    | `glassRimTop` | 0.55 | 0.70 |
    | `glassRimBottom` | 0.25 | 0.32 |
    | `glassRimTopFocused` | 0.85 | 1.0 |
    | `glassRimBottomFocused` | 0.40 | 0.50 |
    | `glassSheen` | 0.10 | 0.14 |
    | `glassSheenFocused` | 0.18 | 0.24 |

    `glassRimMiddle` stays 0.08.
  - **Legibility fallback:** if a text-heavy panel (Settings, the guide, menus) is hard to read on the TV, raise `panelGlass`'s tint before going back to `.regular`. All of these are tokens, so it's a one-line change per test build.

- **L10 — Web apps reload when opened again (§10).**
  - **When:** a web app tile (`WebApp.info != nil`) on the plain path (no Start Page) whose shim **was already running** (`wasRunning`, `Launcher/AppLauncher.swift:228`). A fresh launch loads anyway, and a Start Page launch already navigates.
  - **How:** after `openApplication` returns, a `Task` waits until the frontmost app is the shim or its browser (`WebAppInfo.browserBundleID`), polling every 0.1 s for at most 2 s, then posts **⌘R** to the session (`SyntheticInput.postKey(CGKeyCode(kVK_ANSI_R), flags: .maskCommand)`), which goes to the front window. If neither came forward, or Home cancelled the launch (`cancellation`), nothing is sent. Log at notice: "Reloaded web app <bundleID>".
  - **Calling apps never reload.** New `nonisolated enum CallingApps { static func isCalling(host: String) -> Bool }`, a built-in host list matched exactly or as a subdomain: `meet.google.com`, `teams.microsoft.com`, `teams.live.com`, `teams.cloud.microsoft`, `zoom.us`, `zoom.com`, `webex.com`, `whereby.com`, `discord.com`, `web.whatsapp.com`, `messenger.com`, `facetime.apple.com`, `web.skype.com`. The host is the tile's `startURL` host, else `WebAppInfo.startURL`'s. Log "Not reloading <bundleID>: a calling app". Native apps (FaceTime, Zoom) are never reloaded.
  - No per-tile setting.

- **L11 — On-screen keyboard (§3; D41).**
  - **`Input/OnScreenKeyboard.swift`** (new, `nonisolated struct OnScreenKeyboard: Equatable, Sendable`), the model:
    - `text: String` (at most 40 characters), `mode: .letters | .digits`, `focus: (row, column)`.
    - Letters, the tvOS grid: `a b c d e f g` / `h i j k l m n` / `o p q r s t u` / `v w x y z`, then a bottom row **Space** (3 columns wide), **Delete** (2), **123** (2). Digits mode: `1 2 3 4 5 6 7` / `8 9 0 & ' - .`, and **abc** in place of 123.
    - `mutating func handle(_ command: RemoteCommand) -> Outcome`, `enum Outcome { case none, changed, leaveRight, leaveUp, back }`:
      - Arrows move within the grid (no wrap); a short row clamps the column. Right from a row's last key returns `.leaveRight`, Up from the top row `.leaveUp`.
      - Select types the key (`.changed`); Delete removes the last character; 123/abc switches mode.
      - Play/Pause is Delete (a fast way to fix a typo). Back returns `.back`. Channel Up/Down and Menu: `.none`.
    - `mutating func apply(_ edit: TextEdit)` for phone text (deletions then insertion, clamped to 40).
  - **`DesignSystem/OnScreenKeyboardView.swift`** (new): the text field (a glass capsule showing `text` with a caret, or a dim placeholder) above the key grid. Keys are glass rims (L9); the focused key is white with dark text, like focused list rows. Sized for a ~600 pt-wide column on the 1920 canvas.
  - **Phone text into MMTVL.** `PhoneRemoteEnvironment.launcherAcceptsText` (`App/AppDelegate.swift:230`) is true on YouTube **or Live TV**. `typeEdit` and `postReturn` go to `LiveTVModel.typeText(_:)` / `submitText()` when the router's screen is `.liveTV` (no synthetic events); YouTube keeps `SyntheticInput`.
  - Only Live TV search uses it in M7f. Other apps: out of scope.

- **L12 — Live TV search (§4).**
  - **Opening it:** the guide's group list gets a **Search** row above the groups (`GuideModel`: a Search entry at index 0 of the list it shows; Select on it returns a new `Action.openSearch`). Phone text while Live TV is open (guide, player or Multiview) opens search with the text typed.
  - **`IPTV/Search/LiveSearchModel.swift`** (new, MainActor `@Observable`): `keyboard: OnScreenKeyboard`, `focus: .keyboard | .results(Int)`, `results: [Result]`.
    - `enum Result { case channel(Channel), programme(Channel, Programme) }`.
    - **Channels:** the lineup's visible channels (`library.lineup.visibleChannels`) whose name contains every typed word, ignoring case and diacritics; at most 8, in playlist order.
    - **Programmes:** new `EPGStore.searchProgrammes(words: [String], refs: Set<EPGRef>, interval: DateInterval, limit: Int) async throws -> [Programme]`: `title LIKE '%word%'` for every word (GRDB `like`, case-insensitive for ASCII), only the refs of matched channels (`library.epgMatches`), overlapping [now, now + 24 h], ordered by start, limit 40. Mapped back to channels through the reverse of `epgMatches` (a ref can serve several channels: one result per channel).
    - Results show from 2 characters. Channels update at once; the programme query runs 0.3 s after the last change (the previous query is cancelled).
  - **`LiveTVModel`:** `search: LiveSearchModel?`, shown over the guide; while it's set, every command goes to it (as `menu` does, `:299`). Back on the keyboard closes search (the guide comes back where it was); Back in the results returns to the keyboard. Right from the keyboard enters the results; Left from the results returns.
  - **Select on a result:**
    - A channel, or a programme on now: close search, `play(channel)`.
    - A later programme: close search and show the guide with that channel focused (All Channels if it isn't in the current group) and `focusTime` at the programme's start. New `GuideModel.focus(channelID:at:)`.
  - **The view** (`IPTV/Search/LiveSearchView.swift`, new): the keyboard on the left (L11), results on the right in one list, a programme row reading "On Now · ESPN · NBA Basketball" or "9:00 PM · ESPN · …" with the subtitle under it. Empty: "No channels or programmes match". Before 2 characters: "Type a channel, team or show".
  - Hidden channels and groups are never found (they aren't in the lineup).

- **L13 — Teams (§7).**
  - **`IPTV/Teams/TeamCatalog.swift`** (new, `nonisolated`): every **NFL, NBA, NHL and MLB** team as `Team(id: "nba.lal", league: .nba, name: "Los Angeles Lakers", nickname: "Lakers", aliases: [...])`. 124 teams, in league order then alphabetical. Aliases cover renames and city changes (e.g. the Athletics: "Athletics", "Oakland Athletics", "Sacramento Athletics"; "Utah Mammoth", "Utah Hockey Club"). Also a test that ids are unique and every name parses.
  - **Picked teams:** `iptv-channels.json` gets `teams: [String]` (team ids, in order added; read leniently like the other keys, `IPTV/Sources/ChannelPreferences.swift:21-27`). Kept by Remove Live TV Source, like favorites. CLAUDE.md's `iptv-channels.json` line names it.
  - **Feed names.** `ChannelList.make` (`IPTV/Sources/Channel.swift`) renames entries whose name matches `^(.+ @ .+)-([HA])$`: "… (Home Feed)" for H, "… (Away Feed)" for A. Ids still come from `tvg-id`, so favorites and Multiview are unaffected. Every list shows the new name.
  - **`IPTV/Teams/TeamMatcher.swift`** (new, `nonisolated`):
    - **Game entries:** channels in a group whose name contains "Games" (case-insensitive; never the Replays groups). The name (feed suffix stripped) splits on " @ " into away and home; each side matches a team when it equals the team's name or an alias, ignoring case. A game matches if either side is a picked team.
    - **Network channels:** the programme on now (from the guide) matches when its title or subtitle contains a picked team's full name or alias as whole words, or its nickname plus a league word in title, subtitle or category ("NFL"/"Football", "NBA"/"Basketball", "NHL"/"Hockey", "MLB"/"Baseball"). Titles with "Pregame", "Postgame", "Highlights", "Classic" or "Replay" never match.
    - Order: game entries first (playlist order; for each game, the feed of the picked team first: Home Feed when the picked team is the home side). Then network channels in playlist order.
  - **The group.** `ChannelLineup` gets `teamChannelIDs: [Channel.ID]` and puts a **Teams** group right after Favorites (before All Channels) when that list has a visible channel. `IPTVLibrary` computes it in `updateTeams()`:
    - after each playlist refresh, guide import or rematch, when the picked teams change, and every 5 minutes on the clock (the L5 timer task can drive a separate 5-minute tick);
    - network matches query the programmes on now for the matched refs (`programmes(refs:overlapping:)` over [now, now + 1 s]).
    - It assigns `lineup` only on change, so an open guide updates through its existing `.onChange`.
  - **Picking in Settings:** Settings → Live TV gets a **Teams** row (value "N teams" or "None") that opens a page with one row per league ("NFL", "NBA", "NHL", "MLB", value: the number picked), each opening the league's teams. Select on a team toggles it (value "On" or empty). Built like Groups / Hidden Channels (`Settings/SettingsModel+Pages.swift`, `.iptvGroups`).
  - **Picking from the guide:** the channel menu (`LiveTVModel.channelMenu`, `:541`) gets "Add <Team> to Teams" or "Remove <Team> from Teams" for each team in the channel's name (a game) or in the programme on now (a network channel), at most 2 items.
  - Home screen: unchanged (no Teams page in the Live TV carousel).

### Changed files

| File | Change |
|---|---|
| `MMTVL/App/AppDelegate.swift` | `Display` logs, display-wake observer (L1) |
| `MMTVL/App/KioskWindowController.swift` | resign-active line (L1) |
| `MMTVL/Launcher/AppLauncher.swift` | window probe (L1) |
| `MMTVL/Launcher/WindowFullScreener.swift` | `isFullScreen(pid:)` (L1) |
| `MMTVL/Cast/MirroringDetector.swift`, `MMTVL/Cast/ReflectorMonitor.swift` | `WindowSnapshot.onScreen(pid:)` (L1) |
| `MMTVL/IPTV/Player/VideoFormat.swift` | new (L2) |
| `MMTVL/IPTV/Player/LivePlayer.swift` | `PlayerState.videoFormat`, poll (L3) |
| `MMTVL/IPTV/LiveTVView.swift` | banner label (L3) |
| `CLAUDE.md` | `Display` log line; `usePlaylistGuide` (L4) |
| `MMTVL/App/AppSettings.swift`, `MMTVL/Settings/SettingsTypes.swift` | `usePlaylistGuide`, `SettingKey`, status fields (L4) |
| `MMTVL/IPTV/IPTVLibrary.swift` | guide source choice (L4) |
| `MMTVL/App/AppDelegate.swift` | apply the setting; status rows for unused pasted guides (L4) |
| `MMTVL/Settings/SettingsModel+Pages.swift` | Guide Source row, unused guide rows (L4) |

Findings 3–13, as step 6 designs them (§5's guide and §12's phone after their TV checks):

| File | Change |
|---|---|
| `MMTVL/IPTV/IPTVLibrary.swift` | `refreshIfStale`, notice-level playlist log (L5); `updateTeams`, `teamChannelIDs` (L13) |
| `MMTVL/IPTV/LiveTVModel.swift` | adopt path playlist check, preview fallback, `playlistDidChange` (L5); rotate and Down (L6); search and phone text (L11, L12); Teams menu items (L13) |
| `MMTVL/App/AppDelegate.swift` | refresh timer and wake refresh (L5); battery polling (L8); phone text into Live TV (L11) |
| `MMTVL/Launcher/AppRouter.swift` | `playlistDidChange` hook (L5); `remoteBatteryLevel` (L8) |
| `MMTVL/IPTV/Multiview/MultiviewModel.swift` | `rotate(by:)` (L6) |
| `MMTVL/Launcher/HomeView.swift`, `MMTVL/DesignSystem/Theme.swift` | clock 38 pt and tokens (L7); battery capsule (L8); glass tokens (L9) |
| `MMTVL/Input/RemoteBattery.swift` | new (L8) |
| `MMTVL/DesignSystem/Glass.swift` | clear tinted panels with a rim (L9) |
| `MMTVL/Launcher/AppLauncher.swift`, `MMTVL/Launcher/CallingApps.swift` (new) | web app reload (L10) |
| `MMTVL/Input/OnScreenKeyboard.swift`, `MMTVL/DesignSystem/OnScreenKeyboardView.swift` | new (L11) |
| `MMTVL/IPTV/Search/LiveSearchModel.swift`, `LiveSearchView.swift` | new (L12) |
| `MMTVL/IPTV/EPG/EPGStore.swift` | `searchProgrammes` (L12) |
| `MMTVL/IPTV/Guide/GuideModel.swift`, `GuideView.swift` | Search row, `focus(channelID:at:)` (L12) |
| `MMTVL/IPTV/Teams/TeamCatalog.swift`, `TeamMatcher.swift` | new (L13) |
| `MMTVL/IPTV/Sources/ChannelPreferences.swift`, `Channel.swift` | `teams`, Teams group, feed names (L13) |
| `MMTVL/Settings/SettingsModel+Pages.swift`, `SettingsTypes.swift` | Teams pages (L13) |
| `CLAUDE.md` | refresh timer (L5), `teams` in `iptv-channels.json` (L13), the keyboard (L11) |

## Implementation steps

- [x] **1. Diagnostics (L1)**: files: per the table, plus `CLAUDE.md`
  - Done when:
    - It builds, and `MirroringDetectorTests` and all other tests pass.
    - Opening a tile logs the `… opened (was running: …)` line 2 s later, with window sizes and no titles. Check with `log stream --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "AppLauncher"' --level info`.
    - `pmset displaysleepnow` logs "Displays slept" and waking logs "Displays woke" (category `Display`).

- [x] **2. `VideoFormat` (L2)**: files: `IPTV/Player/VideoFormat.swift` (new), `MMTVLTests/VideoFormatTests.swift` (new)
  - **Tests (`parse` then `label`):**

    | width | height | fps | interlaced | label |
    |---|---|---|---|---|
    | 720 | 480 | 29.97 | yes | `480i · 29.97 fps` |
    | 720 | 576 | 25 | no | `576p · 25 fps` |
    | 1280 | 720 | 59.94 | no | `720p · 59.94 fps` |
    | 1920 | 1080 | 29.97 | yes | `1080i · 29.97 fps` |
    | 1920 | 1080 | 60 | no | `1080p · 60 fps` |
    | 2560 | 1440 | | no | `1440p` |
    | 3840 | 2160 | 23.976 | no | `4K · 23.98 fps` |
    | 4096 | 2160 | | no | `4K` |
    | 1920 | 1080 | 29.97 | nil | `1080 · 29.97 fps` |
    | 640 | 360 | | no | `360p` |

    Also test that:
    - a nil size, "0" or garbage gives nil
    - an fps of `"0"` gives no fps label
  - Done when: `VideoFormatTests` passes.

- [x] **3. Poll and banner (L3)**: files: `IPTV/Player/LivePlayer.swift`, `IPTV/LiveTVView.swift`, `MMTVLTests/FakePlayer.swift` (only if `PlayerState`'s init changes the fake)
  - Done when:
    - All tests pass.
    - On the dev Mac, Live TV shows the label on the banner within about 1 s of Select, e.g. `720p · 59.94 fps` on the provider.
    - The `MPV` log has one "Format …" line per channel start.

- [x] **4. Test build and TV checks (with the user)**: files: this plan, `docs/plans/MASTER_PLAN.md`
  - Run `scripts/test-build.sh` (build 19 or the next number, never reused). The user installs it on the mini.
    - **2026-11-03: build 19 made** (`~/Desktop/MMTVL-1.1.0-build19.zip`), steps 1–3 in it. Waiting for the user's TV checks.
  - **Format:**
    - Open five or more channels.
    - Record the labels seen.
    - Record whether `video-frame-info/interlaced` ever came back nil (labels without a letter).
    - For any 1080i channel, record whether its fps reads 29.97 or 59.94.
  - **Plex blank:** the next time it happens, run the `log show` line from CLAUDE.md (L1) and paste the lines around "tv.plex.htpc opened". Also check:
    - whether Plex's window existed and its size
    - whether it was full screen
    - whether the Dock check ran
    - the last lines of `~/Library/Logs/Plex HTPC/Plex HTPC.log` from that time

    This can wait past the format check. Record it in *Research & findings* as "Plex blank capture".
    - **Plex blank: captured 2026-11-03** (§1, "Plex blank capture"): window there and full screen, no Dock problem, TV not off.
  - **Guide (§5):** before anything else, record Settings → Live TV's guide status, programme count and last import. Then press Refresh Now and say whether info comes back. Run the `IPTV` `log show` line from §5.
  - **Groups (§6):** check whether yesterday's games are still in the game groups after a day without a relaunch. The code says they will be.
  - **Second phone (§12):** run the capture from §12.
  - **Battery (§13):** run the `ioreg` line from §13 on the mini.
    - **Format: done 2026-11-03** (see §2's TV check).
  - Done when: the format results are recorded here, and the guide, groups, phone and battery results are added under §5, §6, §12 and §13 as "TV check <date>".
  - **Closed 2026-11-08:** guide §5 (TV check 2026-11-03, then L5's timer), groups §6 (the MM's log, 2026-11-08: `Loaded N channels` every 15 minutes all day, 194 → 210 channels as games came and went), battery §13 (built in step 10; the user confirmed it on the TV, 2026-11-08). The second phone §12 is parked (user, 2026-11-08; see *Parked findings*).

- [x] **5. Plex blank decision (with the user)**: files: this plan, `docs/plans/MASTER_PLAN.md`
  - From step 4's capture, propose one fix and ask the user to choose:
    - **Plex's window was there and full screen,** but showed nothing. That points to Plex's renderer. Fix: **restart Plex HTPC when its tile is opened after the displays slept** since Plex was last in front:
      - terminate it, wait up to 5 s, force terminate if needed
      - **remove its pid from `launchedPIDs` first**, so `applicationDidTerminate` doesn't send MMTVL home
      - open it fresh

      Or: quit Plex at display sleep when it's in the background.
    - **Plex had no on-screen window, or MMTVL's Dock check fired.** That points to a stale Space. Fix: after opening an already-running app, if `WindowSnapshot.onScreen(pid:)` is empty after 2 s, restart the Dock once (`KioskWindowController.restartDock`) and activate the app again.
    - **Not captured yet.** Leave the milestone open on this step, or, if the user prefers, move it to a later plan.
  - **2026-11-03:** captured, and it's the first case (Plex's renderer), but not after display sleep (§1). **The user's direction:** restart Plex when it has been in the background longer than a set maximum time. 10 minutes is too short. The time comes from the mini's history (`~/Desktop/plex-history.sh` on the dev Mac: 7 days of MMTVL's Plex opens, Home presses and launched-app quits, plus each Plex log file's first and last line): the longest time in the background that still drew versus the shortest that came back black.
  - **2026-11-03, later:** the history showed every black screen followed an HDMI hot-plug (§1, "Plex blank history"), so the user is trying to stop the hot-plug first. A Claude session on the mini works through the handoff `~/Desktop/mini-display-avr-handoff.md` (on the dev Mac; the user copies it over): a hot-plug detector built on Plex's `DisplayManager` lines; receiver and TV HDMI-CEC settings; BetterDisplay's EDID override and HDMI-CEC; App Nap off for Plex. It writes `~/Desktop/mini-display-avr-results.md`. The same session tests receiver volume and power control (Pioneer Elite VSX-01TXH: no network control, so HDMI-CEC, the path an NVIDIA Shield used here before; RS-232 through a USB adapter as the fallback) and TV power, for a later MMTVL feature; that feature is **not M7f scope** and needs its own plan item. The MMTVL fix (restart Plex after a display change, maybe with a maximum time) waits for those results.
  - Once the user chooses, add the fix here as step 6 (design, files, done when), implement it, and do one more test build.
  - Resolve Q22. Add a decision to the master plan if the Plex fix is architecture-level.
  - Done when: the Plex fix is chosen, built and on a test build, or the user moved the capture on.

- [x] **6. Design findings 3–13 (with the user)**: files: this plan, `docs/plans/MASTER_PLAN.md`
  - For each finding, write a design under *Design* (L4…) the way L1–L3 are written, ask the user its *Open* questions, and add implementation steps (7…) with files and *Done when*.
  - **Suggested order:**
    - the fixes first: §6 groups, §5 guide, §12 phone
    - then the small changes: §8 clock, §9 glass, §10 PWA reload, §11 Multiview
    - then the bigger features: §3 keyboard, §4 search, §7 Teams, and §13 battery after M7e's probe
  - New decisions go in the master plan's §4. Likely ones: a playlist and guide refresh timer (amends D23), and the keyboard as a new input screen.
  - Done when: every finding has a design and steps, or the user parked or moved it.
  - **2026-11-03:** started before step 4 was finished (user choice; step 4's guide, groups and phone checks need days on the TV). Designed with the user: §6 (L5), §11 (L6), §8 (L7), §13 (L8), §9 (L9), §10 (L10), §3 (L11), §4 (L12), §7 (L13), as steps 8–16. §5 is covered by L5's timer unless the TV check shows a failing import. **Still open: §12** (second phone), designed after its capture. **2026-11-08:** §12 parked by the user (it hasn't come back).

- [x] **7. Guide source switch (L4)**: files: per L4, plus `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/SettingsModelTests.swift`
  - **Tests:**
    - `IPTVLibraryTests`: with a playlist guide and a pasted guide, `applyUsePlaylistGuide(true)` uses the playlist's guide, keeps the pasted URL in the source store, prunes the pasted guide's rows and imports the playlist's; `false` goes back (imports the pasted one again). With no playlist guide, `true` keeps the pasted guides.
    - `SettingsModelTests`: the Guide Source row shows only with `playlistNamesGuide` and a pasted guide; its value follows the setting; an unused pasted guide's row says "Off" and still opens its page.
  - Done when: all tests pass. On the mini (today's playlist names no guide) Settings → Live TV looks as before, with no Guide Source row.
  - **2026-11-03:** built; 837 tests pass (4 new). The mini check is in *Manual verification*.

- [x] **8. Playlist and guide refresh (L5)**: files: `IPTV/IPTVLibrary.swift`, `IPTV/LiveTVModel.swift`, `App/AppDelegate.swift`, `Launcher/AppRouter.swift`, `CLAUDE.md`, `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - **Tests:**
    - `refreshIfStale()` fetches a stale playlist before the guide check; with a fresh playlist it fetches nothing.
    - Opening Live TV on an adopted preview with a stale playlist fetches it (the fake network counts the fetch) and keeps the same player.
    - `defaultPreviewChannelID`: the last channel when it's in the playlist; the first favorite when it isn't; nil with neither.
    - `playlistDidChange()` stops a preview whose channel left the playlist and leaves one that's still there.
  - Done when: all tests pass. On the dev Mac (windowed), the `IPTV` log shows "Loaded N channels" again 15 minutes after launch.
  - **2026-11-03:** built, no new warnings; 842 tests pass (5 new). The 15-minute log check is in *Manual verification*.

- [x] **9. Multiview rotate (L6)**: files: `IPTV/Multiview/MultiviewModel.swift`, `IPTV/LiveTVModel.swift`, `MMTVLTests/MultiviewModelTests.swift`, `MMTVLTests/MultiviewLiveTVTests.swift`
  - **Tests:** `rotate(by: 1)` on `A | B C D E` gives `B | C D E A`, `rotate(by: -1)` gives `E | A B C D`; empty slots stay empty and are skipped (`A | B nil D nil` → `B | D nil A nil`); focus and sound stay on the main slot; no-op in 2 × 2 and Side by Side, and with one filled window. In `LiveTVModel`: Right on the main window rotates without starting a player; Down highlights slot 1 in 1 + 3; Right from a small window moves the highlight as before.
  - Done when: all tests pass.
  - **2026-11-03:** built; 848 tests pass (6 new, one changed). Rotation on the TV is in step 16.

- [x] **10. Clock and Siri Remote battery (L7, L8)**: files: `Launcher/HomeView.swift`, `DesignSystem/Theme.swift`, `Input/RemoteBattery.swift` (new), `Launcher/AppRouter.swift`, `App/AppDelegate.swift`, `MMTVLTests/RemoteBatteryTests.swift` (new)
  - **Tests (`level(from:)`):** a Siri Remote (vendor 76, product 789, 88 of 100) gives 88; a Magic Trackpad (product 804) is ignored; two remotes give the lower level; a missing or zero `Max Capacity` is ignored; non-accessory sources are ignored; nothing gives nil.
  - Done when: all tests pass. On the dev Mac (no Siri Remote) the clock is 38 pt and no battery shows; `RemoteBattery.current()` returns nil there without crashing.
  - **2026-11-03:** built, no new warnings; 856 tests pass (8 new). On the dev Mac (windowed) the clock is 38 pt, the version capsule is unchanged under it, and no battery shows (the dev Mac's only Apple accessory is the Magic Trackpad, 804). The battery on the mini, and the red pulse, are in step 16.

- [x] **11. More glass (L9)**: files: `DesignSystem/Glass.swift`, `DesignSystem/Theme.swift`
  - Done when: it builds and all tests pass. On the dev Mac the dock, the clock capsule, Settings and the guide panels show the clearer glass with a rim, and text stays readable over a bright Plex backdrop.
  - **2026-11-03:** built; 856 tests pass. On the dev Mac (windowed) the dock and the clock capsule show the clearer glass with a rim. Legibility over a bright Plex backdrop, Settings and the guide on the TV are in step 16.

- [x] **12. Web app reload (L10)**: files: `Launcher/AppLauncher.swift`, `Launcher/CallingApps.swift` (new), `MMTVLTests/CallingAppsTests.swift` (new)
  - **Tests:** `isCalling(host:)` is true for `meet.google.com`, `us02web.zoom.us`, `teams.microsoft.com`; false for `mail.google.com`, `notzoom.us`, `youtube.com`.
  - Done when: all tests pass. On the dev Mac: open a web app tile, go Home, open it again: the page reloads ("Reloaded web app" in the `AppLauncher` log). A Google Meet web app tile doesn't reload.
  - **2026-11-03:** built; 858 tests pass (2 new, 10 cases). The dev Mac's web app tiles start on `music.youtube.com`, `photos.google.com` and `meet.google.com`, so Meet is the one skipped. The live reload check wasn't driven (it would send keys into the user's desktop); it's in *Manual verification* and step 16.

- [x] **13. On-screen keyboard (L11)**: files: `Input/OnScreenKeyboard.swift` (new), `DesignSystem/OnScreenKeyboardView.swift` (new), `MMTVLTests/OnScreenKeyboardTests.swift` (new)
  - **Tests:** Select types the focused letter; Delete and Play/Pause remove the last character; 123 switches to digits and abc back; the 40-character cap; arrows clamp on short rows; Right from a row's end gives `.leaveRight`, Up from the top row `.leaveUp`, Back `.back`; `apply(TextEdit)` deletes then inserts.
  - Done when: all tests pass.
  - **2026-11-03:** built; 867 tests pass (9 new). The view is first drawn on screen by step 14's search.

- [x] **14. Live TV search (L12, with L11's phone text)**: files: `IPTV/Search/LiveSearchModel.swift` (new), `IPTV/Search/LiveSearchView.swift` (new), `IPTV/EPG/EPGStore.swift`, `IPTV/Guide/GuideModel.swift`, `IPTV/Guide/GuideView.swift`, `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `App/AppDelegate.swift`, `MMTVLTests/LiveSearchTests.swift` (new), `MMTVLTests/EPGStoreTests.swift`, `MMTVLTests/GuideModelTests.swift`
  - **Tests:**
    - `searchProgrammes`: every word must be in the title; only the given refs; only [now, now + 24 h]; ordered by start; limit.
    - Channel results ignore case and diacritics and skip hidden channels.
    - Select on a channel or an airing programme plays it; on a later programme the guide focuses that channel at that time (`GuideModel.focus(channelID:at:)`).
    - The guide's Search row returns `.openSearch`; Back closes search and the guide keeps its group and row.
    - Phone text while Live TV is open opens search with that text; on YouTube it still posts synthetic keys.
  - Done when: all tests pass. On the dev Mac, typing "nba" with the remote shows NBA channels and programmes.
  - **2026-11-03:** built, no new warnings; 878 tests pass (11 new, one changed). Typing "nba" on the dev Mac wasn't driven (it would send keys into the user's desktop, and the dev Mac's playlist fetch was failing); it's in *Manual verification* and step 16.

- [x] **15. Teams (L13)**: files: `IPTV/Teams/TeamCatalog.swift` (new), `IPTV/Teams/TeamMatcher.swift` (new), `IPTV/Sources/ChannelPreferences.swift`, `IPTV/Sources/Channel.swift`, `IPTV/IPTVLibrary.swift`, `IPTV/LiveTVModel.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsTypes.swift`, `CLAUDE.md`, `MMTVLTests/TeamMatcherTests.swift` (new), `MMTVLTests/ChannelListTests.swift`, `MMTVLTests/ChannelLineupTests.swift`, `MMTVLTests/SettingsModelTests.swift`
  - **Tests:**
    - The catalog: 124 teams, unique ids, 32/30/32/30 per league.
    - Feed names: `Miami Heat @ Los Angeles Lakers-H` becomes `Miami Heat @ Los Angeles Lakers (Home Feed)`, `-A` becomes `(Away Feed)`, the id is unchanged; a replay without a suffix is unchanged.
    - Games: picking the Lakers matches both Heat @ Lakers feeds, Home Feed first; picking the Heat puts the Away Feed first; picking the Clippers doesn't match the Lakers game; replays never match.
    - Networks: "NBA Basketball" / "Miami Heat at Los Angeles Lakers" matches the Heat; "Kings" with category "Hockey" matches the LA Kings, not Sacramento; "Lakers Postgame" doesn't match.
    - The lineup: Teams comes right after Favorites, only with a visible match. `teams` in `iptv-channels.json` round-trips and a file without it reads as [].
    - Settings: the Teams row's value; a league page toggles a team.
    - The channel menu offers "Add Miami Heat to Teams" and "Add Los Angeles Lakers to Teams" on that game.
  - Done when: all tests pass. On the dev Mac with today's playlist, picking a team playing today shows the Teams group in the guide.
  - **2026-11-03:** built, no new warnings; 888 tests pass (10 new, one changed). The dev Mac check wasn't driven (it needs the remote in the app, and today's games); it's in *Manual verification* and step 16.

- [x] **16. Test build (with the user)**: files: this plan, `docs/plans/MASTER_PLAN.md`
  - Run `scripts/test-build.sh` (the next build number). On the mini, check: groups update without a relaunch, Multiview rotation, the clock and battery (and the red flash, if the remote is ever below 15 %), the glass, a web app reload (and Meet not reloading), search with the remote and the phone, Teams.
    - **2026-11-03: build 20 made** (`~/Desktop/MMTVL-1.1.0-build20.zip`), steps 1–3 and 7–15 in it. Waiting for the user's TV checks.
  - Done when: the user's results are recorded under each finding as "TV check <date>", and any changes are added as steps here.
  - **TV check 2026-11-08 (user, through builds 20–28):** search and Teams, Multiview rotation, the clock, the battery and the glass, and the web app reload all work. Groups update without a relaunch (the MM's log, step 4). The user's new requests from this check (toning down the Live TV banner's glass, an app-wide glass setting, the home dock not moving with the rows, college teams picked from the guide) go to **M7l** in the master plan, not M7f.

- [x] **Last. Close M7f**: files: this plan, `docs/plans/MASTER_PLAN.md`
  - Set M7f to `Done` and `git mv` this plan to `docs/plans/archive/`.
  - Done when: the master plan shows M7f `Done` with the archive link.

## Tests

- **New test files:**
  - `MMTVLTests/VideoFormatTests.swift` (step 2)
- **Unchanged, must pass:** `MirroringDetectorTests`, `ForegrounderTests`, `LiveTVModelTests`, `PhoneRemoteTests`, `KioskLockTests`, `MPVOptionsTests`.
- **Commands:**
  ```sh
  xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build
  xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
  xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test -only-testing:'MMTVLTests/VideoFormatTests'
  ```

## Manual verification

- [x] Dev Mac: `pmset displaysleepnow` and a wake log `Display` lines. *(Seen on the mini instead, 2026-11-08: `Displays slept`, `Displays woke`, displays added and removed.)*
- [x] Dev Mac: opening a tile logs the window probe line with no window titles. *(On the mini, 2026-11-08: `tv.plex.htpc opened (was running: no): frontmost yes, on-screen windows 2 [1920×44, 1920×1080], full screen yes`.)*
- [x] Mini: Live TV's banner shows the format on several channels.
- [x] Mini: the Plex blank screen was captured, or the user moved it on (step 5).
- [ ] *(Not checked when M7f closed: the provider's playlist still names no guide, so the row can't show; re-check if it ever does.)* Mini (L4): Settings → Live TV shows no Guide Source row with today's playlist. When the provider adds a guide to the playlist: the row appears, Playlist uses it, Pasted Guides goes back, and the pasted guide stays listed as Off.
- [x] Mini: the guide, groups, second phone and battery checks from step 4 are recorded (§5, §6, §12, §13). *(§12 parked.)*
- [x] *(User, on the TV, 2026-11-08.)* Dev Mac (L10, step 12): open the YouTube Music web app tile, Home, open it again: the page reloads and the `AppLauncher` log says "Reloaded web app …"; the same with Google Meet logs "Not reloading … a calling app".
- [x] *(User, 2026-11-08.)* Dev Mac or mini (L12, step 14): in the guide, Left to the groups, Up to Search, Select; type "nba" with the remote: NBA channels, then programmes; Right into the results, Select plays; a later programme opens the guide at its time. With the phone's text field in Live TV, search opens with the text.
- [x] *(User, 2026-11-08.)* Mini (L13, step 15): Settings → Live TV → Teams → NBA → pick a team playing today: the guide shows a Teams group after Favorites with both feeds, the team's own first, named "(Home Feed)"/"(Away Feed)"; a network channel airing the team's game shows too. In the guide, Menu on a game offers "Add <Team> to Teams".
- [x] *(The mini's log, 2026-11-08: every 15 minutes.)* Dev Mac (L5, step 8): launch windowed; 15 minutes later the `IPTV` log shows "Loaded N channels" again (or, with a dead playlist link, a "Playlist from … failed" line at that time, which still shows the timer ran): `/usr/bin/log show --last 30m --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "IPTV"' --info`.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| `video-frame-info/interlaced` is unavailable with VideoToolbox | Labels never get a letter ("1080") | Ask the user. Option: read `video-dec-params` or ffmpeg's field order through `track-list` (unverified). Don't guess "p". |
| The format label crowds a long channel name | The title is truncated on the banner | Give the title `.lineLimit(1)` and `.truncationMode(.tail)`, keeping the label. Add it only if seen. |
| The Plex blank screen doesn't happen again for a while | No capture by the end of the format check | Step 5: keep M7f open, or move the step to a later plan (user choice). |
| Findings 3–13 make M7f too large to finish | Step 6 adds more than about 10 steps | Ask the user to split: the fixes (§5, §6, §12) stay in M7f, the features (§3, §4, §7, §13) go to a new milestone. |

## Parked findings

The user reported on 2026-11-02 that these no longer happen with build 18 as it is. Nothing is built for them. If one comes back, re-plan it from these notes.

### The remote was dead after the TV was off (2026-10-14)

- **Symptom:** after a long time with the TV off, MMTVL was on screen but the Siri Remote (through Remote Buddy) did nothing until a phone remote button was pressed.
- **Likely cause (code read, never confirmed on the mini):** every physical input path needs `NSApp.isActive`. Non-global keys reach only `InputRouter`'s local monitor, media keys are consumed only while active (`GlobalEventTap.swift:162`), and `InputRouter.dispatch` drops non-global controller commands while inactive (`InputRouter.swift:74-82`). If display sleep left MMTVL inactive behind Finder or no app, only the phone's `repairForeground()` (`AppDelegate.swift:250-260`) brought it back.
- **Designed fix (not built):** a pure `ForegroundRepair.isOrphaned` helper. Bound keys, media keys and controller buttons while orphaned, and display wake, would call `repairForeground`. The first press would only wake MMTVL (0.8 s quiet period).
- **If it comes back:** L1's resign-active line now names the front app. Run the `log show` line from CLAUDE.md for the hours before the phone press, and look for a `repair:` Foreground line with no `wake:` before it.

### A second phone remote didn't work (2026-11-02, §12)

- **Parked 2026-11-08 by the user:** it hasn't come back. How it failed was never captured.
- **Research:** §12 above. Candidate cause: half-open sockets fill `RemoteServer.maxSessions` (8), because the server never pings and sockets have no idle timeout. Other candidates: pairing only opens on Settings → Pair a Phone, and two trackpads share one `PhonePointer`.
- **If it comes back:** note what the second phone's page shows, run the `PhoneRemote` `log stream` line from CLAUDE.md, and check Settings → Phone Remote's "N connected now". The "Refused a phone connection: 8 already open" line is info level, so it needs `log stream`, not `log show`.

### Plex HTPC's Back after a video ends (2026-10-14)

- **Symptom:** at the end of playback, Back showed only the background. More Back presses brought the UI back, and the only way out to Plex's home was selecting a Next Up or related show.
- **Possible causes:** (a) doubled input (Remote Buddy's Esc plus HIDRemote's Menu, Q21), (b) a long Esc, which Plex HTPC maps to `home` (`inputmaps/keyboard.json`: `"Back|Esc|…": { "short": "back", "long": "home" }`), or (c) Plex's own post-play bug.
- **If it comes back:** press Back once after playback, then run `grep -E "Input received|Emit input action|Sending actions" ~/Library/Logs/Plex\ HTPC/Plex\ HTPC.log | tail -20` on the mini. `source:` names the input (`Keyboard`, `AppleRemote`), and `(short)`/`(long)` shows the press. User overrides go in `~/Library/Application Support/Plex HTPC/inputmaps/` with the same `name` as the default map. Workaround in Plex's own map: a long Back or the `H` key goes to Plex's home.

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-11-03, step 1 (small, no stop):** the window probe skips Chromium web app shims too (`webApp != nil`), not only Start Page hand-offs, since a shim can hand its window to the browser. "Screen parameters changed" is logged in windowed mode too; "Displays woke" only in kiosk mode, as planned. The step's runtime checks (the probe line on a tile open, `pmset displaysleepnow`) need kiosk mode and are left to the manual checks below.
- **2026-11-03, step 4 (resolved, no code change):** on build 19 Live TV had no channels and no guide: the playlist fetch got **HTTP 403**. Not M7f: the old playlist link got 403 from curl with a browser User-Agent too. **The provider had changed the account's playlist path.** The new link (two forms, same 214-channel M3U with groups) works; the user pastes it in Settings → Live TV on the mini. Step 4's checks continue after that.
- **2026-11-03, step 3 (small, no stop):** the format is read at the start of `pollTimeshift()` (`pollFormat`), before its `time-pos`/cache guard, so it still updates when there's no timeshift data. The "Format" log is once per `play()` (retries don't log again). The dev Mac check couldn't run: the playlist fetch from iptv.example failed on the dev Mac at the time, so no stream played. Checked on the mini in step 4 instead.
- **2026-11-03, step 6 (user choice, no stop):** step 6 started before step 4 was finished; step 4's guide, groups and second-phone checks need days on the TV. Steps 4 and 5 stay open. Step 6 added 9 steps (8–16), just under the risk table's split threshold.
- **2026-11-03, step 8 (small, no stop):**
  - **The lineup hook.** `AppRouter` had no lineup observation to call `playlistDidChange()` from, and `HomeView` has no library. So `IPTVLibrary.onLineupChange` (fired by `updateLineup` when the lineup changes) is wired by `AppDelegate` to the new `AppRouter.playlistDidChange()`. That method calls `liveTV.playlistDidChange()`, refreshes the top shelf on the home screen (so the Live TV pages reload around the new default channel) and calls `updateLivePreview()`. It also fires on favorite and hiding changes; `playlistDidChange()` does nothing then.
  - `playlistDidChange()` was added to `LiveTVHosting`, so `MMTVLTests/FakeLiveTV.swift` (not in the step's files) got it too.
  - **The adopt path** runs `library.refreshIfStale()` (playlist, then guide) in place of its guide-only task, in `adoptRefreshTask`. Tests await that task. It isn't `pendingTask`, which leaving cancels.
  - `AppDelegate` had no `applicationWillTerminate`. It was added to cancel the timer task.
- **2026-11-03, step 9 (small, no stop):**
  - Down from the main window uses a new `MultiviewModel.focus(_:)`, which sets the highlight and moves the sound when the window is filled, as an arrow does.
  - `MultiviewLiveTVTests.arrowsMoveTheHighlightAndTheSound` expected Down from the main window in 1 + 4 to reach slot 2 (the old neighbor rule). It now expects slot 1, per L6.
  - When the main window is empty (a window was removed), Left/Right still rotate the filled small windows among themselves, and the main window stays empty. L6 doesn't cover this case.
- **2026-11-03, step 10 (small, no stop):**
  - The clock and the battery share a private `homeClockCapsule()` modifier (38 pt, padding 24 × 10, glass capsule); the version keeps `capsule(_:)` with `Theme.clockFont`. New tokens beside `homeClockFont`: `homeClockPadding`, `homeClockTop`, `homeBatterySpacing`, `batteryLowThreshold`, `batteryLowColor`, `batteryPulseOpacity`, `batteryPulseAnimation`.
  - The home screen's refresh (`onRefreshShelf`) also runs at each minute tick, so the battery is read then too while the home screen shows, not only on appear. The read is one cheap IOKit call; AppDelegate sets `remoteBatteryLevel` only when it changes.
- **2026-11-03, step 11 (small, no stop):** the panel rim is drawn **between the glass and the content** (`.background` inside `glassEffect`), not as an overlay, so its sheen doesn't lighten a focused white row's dark text. `glassPanel(in:)` now takes `some InsettableShape` (every caller passes a Capsule, Circle, Rectangle or RoundedRectangle). The rim drawing is shared by tiles and panels (`GlassRimLayer`).
- **2026-11-03, step 13 (small, no stop):**
  - The keyboard's sizes and fonts are `Theme.keyboard…` tokens (`DesignSystem/Theme.swift`, not in the step's files), per the no-literals convention.
  - Every row is laid out on 7 columns (Space spans 3, Delete and 123/abc span 2). Up/Down land on the key covering the focused key's first column, and a shorter row clamps to its last key. So Down from `z` reaches Delete, and Up from Delete reaches `y`. Switching mode keeps focus on the mode key. `handle` returns `.changed` only when the text changed (not for a mode switch).
- **2026-11-03, step 14 (small, no stop):**
  - **`IPTV/IPTVLibrary.swift`** (not in the step's files) got `searchProgrammes(words:channels:in:limit:)`: the search model reaches the store and `epgMatches` through the library, as the guide does. It maps refs back to channels (one result per channel).
  - `EPGStore.searchProgrammes` matches the exact refs (source and channel id) in SQL, so the limit isn't spent on rows the filter would drop. `%` and `_` in a typed word match literally.
  - **The Search row** is a guide focus of its own (`GuideModel.Focus.search`, above the groups: Up from the first group, Down back to it), not index 0 of `groups`, so group indices and their tests are unchanged. Focus stays on the Search row while search is open, so Back comes back to it. `GuideModelTests.groups` expected Up to stop at the first group; it now expects the Search row, then Down to the first group.
  - `GuideModel.focus(channelID:at:now:)` takes `now` (the timeline never starts before now).
  - **Search is drawn over whatever Live TV shows** (the guide, the player, Multiview), and closing it leaves that screen as it was (`mode` doesn't change while search is open).
  - **Not covered by L12, chosen here:** in the Multiview picker guide, a channel or an airing programme goes into the window being picked (a later programme focuses the picker guide). From Multiview itself (phone text), choosing a result leaves the windows (the layout is kept, inactive, as Watch from a top shelf card does) and then plays or shows the guide. The phone's **Return** chooses the first result.
  - The phone text path still needs post-event access (`PhoneRemote.canType`), which kiosk mode has anyway (Accessibility); `PhoneRemote.swift` wasn't changed. Text goes to Live TV only while MMTVL is active; otherwise it's typed into the front app as before.
  - Theme tokens `search…` (`DesignSystem/Theme.swift`). `LiveTVModel.searchDebounce` (0.3 s) lets tests skip the debounce. Typed words are folded for case and diacritics for channel names; programme titles use SQLite `LIKE` (ASCII case only), as L12 says.
- **2026-11-03, step 15 (small, no stop):**
  - **Files beyond the step's list:** `Settings/SettingsModel.swift` (the `toggleTeam` action), `Settings/SettingsEnvironment.swift` (`setTeamPicked`), `App/AppDelegate.swift` (the status's `teams`, the closure, the 5-minute Teams tick), `IPTV/LiveMenu.swift` (`LiveMenuAction.toggleTeam`), `MMTVLTests/SettingsTestSupport.swift`. The feed-name and lineup tests are in `TeamMatcherTests` rather than `ChannelListTests` / `ChannelLineupTests`, next to the playlist they use.
  - **Feed ids:** a game entry without a `tvg-id` keeps the id of its playlist name (`name:… -h`), so renaming never changes an id.
  - **Matching:** a one-word full name (the Athletics) counts only with a league word, so "World Athletics" doesn't match. "Pregame", "Postgame", "Highlights", "Classic" and "Replay" are checked in the title only (as L13 says). With both teams of a game picked, its feeds stay in playlist order.
  - `IPTVLibrary.updateTeams()` runs at the end of every rematch, which follows each playlist refresh, guide import and Match Guide change. Picking a team runs it as `teamUpdateTask` (tests await it).
  - **The channel menu** reads the programme on now from the guide's loaded programmes, else the player's banner. Selecting an item toggles the team; the menu closes.
  - **Default group:** the guide's default group (when none is remembered) is the first group, so with no favorites but a Teams match it's Teams. L13 didn't say; nothing else changed.
  - CLAUDE.md also got a short Live TV search note (L11/L12; the Changed files table lists CLAUDE.md for the keyboard).
- **2026-11-06, step 5 (Q22):** the Plex fix moved to [M7h](M7h-siri-remote-and-receiver.md) step 13 (D45): restart Plex HTPC on its next open after an HDMI hot-plug while it was in the background. Tried first, 2026-11-05 on the mini: a BetterDisplay virtual screen as the main display with HDMI as its hardware mirror. Plex drew after two TV power cycles (it logged no display change), but Prime Video refused to play ("doesn't meet HDCP content protection standards"), so it was removed and BetterDisplay uninstalled. Prime Video still shows that HDCP error through the receiver after a reboot (also in Safari): an HDMI-chain problem, still open. Step 5 here is done once M7h step 13 is. **Done 2026-11-06:** M7h step 13 is built (not yet checked on the TV; M7h step 15).
