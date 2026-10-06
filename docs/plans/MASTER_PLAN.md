# MMTVL — Master Plan

A personal, native macOS media launcher that looks and behaves like tvOS. It runs full screen on a Mac mini (M4) connected over HDMI to an AV receiver and TV, and is driven by a remote, a keyboard/mouse, or a phone.

This file is the **single source of truth** for vision, decisions, architecture, and milestone status. Each milestone gets its own detailed sub plan (see [How planning works](#how-planning-works)).

---

## 1. Goals

- Full-screen, tvOS-style home screen that launches media apps and built-in experiences.
- Fully usable with a D-pad remote (arrows / select / back / home / play-pause) and with keyboard + mouse.
- Built-in experiences where third-party options are poor: **YouTube (TV UI)** and **IPTV (TiviMate-class)**.
- A **Home** button that returns to the launcher from any app.
- Always possible to drop to the normal macOS desktop (local keyboard/mouse or Apple Remote Desktop).
- Phone-based virtual remote (iOS + Android) with text entry.

## 2. Non-goals

- App Store distribution or sandboxing. Personal use only.
- Recording / DVR.
- Acting as a Google Cast (Chromecast) receiver (Google limits this to certified devices).
- Re-skinning third-party apps (Plex, Prime Video). They are launched as-is.

## 3. Environment & constraints

| Item | Value |
|---|---|
| Target hardware | Mac mini M4, HDMI → AV receiver → TV |
| Deployment target | macOS 26.0 (dev machine: macOS 27 / Xcode 27). Revisit if the mini runs an older OS. |
| Language / UI | Swift 6 (MainActor default isolation), SwiftUI hosted in AppKit windows |
| Distribution | Local build, signed **Apple Development, team H846CY8RB4** (from M2), **no App Sandbox, no hardened runtime** (for now) |
| IPTV provider | the IPTV provider: a plain M3U URL with an embedded token (**not** Xtream; verified 2026-10-06). About 118 entries (97 US sports channels + game event streams), all live HLS (720p H.264, ~3–4 Mb/s, 40 s server window), no built-in EPG. **5 concurrent streams** observed. |
| EPG | User-supplied XMLTV sources (multiple) |
| Volume | HDMI output has no macOS volume. **SoundSource** (Rogue Amoeba, installed on the mini) provides it; see D25. |
| Remote | Not purchased. Candidates: Siri Remote + Remote Buddy 2, WeChip G20S Pro, Flirc + IR remote. The app must work with any remote that emits key events. |

## 4. Key decisions

Record every architecture-level decision here. Sub plans may make local decisions but must not contradict these without updating this table.

| ID | Decision | Rationale |
|---|---|---|
| D1 | Launcher window is an **AppKit-owned borderless window covering the screen**, with `NSApp.presentationOptions` hiding the Dock and menu bar. **Not** native fullscreen Spaces. | Avoids Space-switch animations when jumping to/from Plex and other fullscreen apps. Presentation options auto-revert when another app is frontmost. |
| D2 | **Custom focus engine** (a focus model plus key-command routing), not SwiftUI's built-in focus traversal. | Directional (arrow-key) focus movement is a tvOS-only SwiftUI behavior. On macOS we must drive focus ourselves. |
| D3 | All input is normalized into a `RemoteCommand` enum by a central `InputRouter`. Sources: local key events (M1), global event tap, remappable bindings, game controllers (M2), phone remote (M5). | One place for remapping. Every remote type works the same way. |
| D4 | Global Home button uses a **CGEventTap**, which requires Accessibility permission. | Needed to steal a key/button back from Plex, browsers, etc. Acceptable for a personal unsandboxed app. Signing must be stable so the TCC grant survives rebuilds: Apple Development cert, team **H846CY8RB4** (the user's own team; verified to build without a provisioning profile). |
| D5 | YouTube = `youtube.com/tv` in a **WKWebView inside the launcher**, with a TV user agent (PS4/Cobalt 25, verified 2026-10-05; see D21). Profile PIN protection relies on YouTube's own **Parent code**. Fallback: launcher-level profiles with isolated `WKWebsiteDataStore`s and the launcher PIN (D20). | Best remote UX. Keeps the user inside the launcher. Parent code matches the desired child-profile behavior. |
| D6 | IPTV is **built in**. Player engine = **libmpv via MPVKit** (Swift package). | IPTV streams are often raw MPEG-TS that AVPlayer handles poorly. mpv plays nearly everything and supports a back-buffer for rewind. |
| D7 | IPTV **rewind buffer** uses mpv's in-memory demuxer back-cache (`cache=yes`, `demuxer-max-back-bytes=512MiB`, `demuxer-max-bytes=256MiB`; M4 L8), targeting **≥ 5 minutes** per live stream (~17 min at the measured bitrate). Multiview windows use 160 MiB back + 64 MiB forward (~5 min each), switched at runtime as a window goes full screen or back (M6 L6). | Meets "cache a few minutes to rewind" without a DVR. Verified in an M4 spike: seeking 60 s back on live HLS (beyond the 40 s server window) and pausing both work from the cache. |
| D8 | EPG and channel data are stored in **SQLite (GRDB)**. XMLTV is stream-parsed and refreshed on a schedule. | XMLTV files can be 100MB+. The guide grid needs fast time-range queries. |
| D9 | Secrets (IPTV URL/credentials, PINs) live in the **Keychain**, never in config files or the repo. | — |
| D10 | Non-secret config (launch items, bindings, settings, EPG channel overrides, `plex.json`) is JSON in `~/Library/Application Support/MMTVL/`; custom tile pictures are files in its `tile-art/` folder (M7). IPTV source and guide URLs and Plex tokens are Keychain items (D23, D28). | Easy to inspect and back up. |
| D11 | The phone remote is a **web page served by the launcher** (Network.framework HTTP + WebSocket on the LAN), protected by a pairing code. A native iOS app is optional later. Details in D24. | Works on iOS and Android with no install. Supports text entry. |
| D12 | Casting: **AirPlay = macOS's built-in AirPlay Receiver** (a setting, no code). Plex = Plex HTPC as a Plex Companion player. YouTube = "Link with TV code" in the TV UI. No Chromecast receiver. | Zero/low code and reliable. |
| D13 | Prime Video and the generic browser are launched as **external apps** (Prime Video Mac app or Safari/Chrome). | DRM (Widevine/FairPlay) does not work reliably in our WKWebView. |
| D14 | Multiview: up to **5 windows** in six layouts (**1 + 4** default, 1 + 3, 2 × 2, 1 + 2, Side by Side, Picture in Picture). Each window is its own mpv core, taken from a pool of at most 5 that is reused and never destroyed. Sound follows the highlighted window; the others are muted. Entered from the guide's channel menu. The playing channel keeps its player (no reconnect) when Multiview opens or closes. (M6) | User choice (2026-10-06): the 1 + 4 layout from their TV setup. It uses all 5 of the provider's streams, leaving none for another device; accepted. The guide picker reuses a window's video, so it needs no extra stream. |
| D15 | Launched apps open **full screen**. M1: Chromium browsers get `--start-fullscreen` (only works on a cold launch). M2: a general path that sets `AXFullScreen` on the app's main window through the Accessibility API, covering Safari, Prime Video and apps that are already running. The browser tile opens the **system default browser** (Brave). | TV use needs no window chrome. Accessibility is already required for D4, so the general path adds no new permission. |
| D16 | Input bindings are **data**: `key-bindings.json` maps key / media-key / controller-button triggers to `RemoteCommand`s, each with an `isGlobal` flag. App settings live in `settings.json`. Both are in the D10 directory, read at launch. Settings and launch items are edited in the M2b Settings screen; bindings in Settings → Remote Buttons (M7, D27). | A new remote needs no code change. Unbound key codes are logged (only while MMTVL is frontmost) to help mapping. |
| D17 | **One active CGEventTap** handles global input: it always consumes `isGlobal` bindings (Home) and consumes media keys **only while the launcher is frontmost**; it never logs keys. Game controllers use GameController with `shouldMonitorBackgroundEvents`; in the background only global bindings act. All global input is off in `-windowed` mode. | Keeps other apps (Plex, browsers) fully usable while Home always works. Avoids keylogging. Protects the dev Mac's Home key. |
| D18 | **Home from an external app leaves it running** (tvOS semantics); **system wake** always returns to the launcher home screen. | User choice (2026-10-05). Instant return to Plex and the like; predictable state from the couch. |
| D19 | A **remote-navigable Settings screen** (a Settings tile, M2b) edits the D10 JSON files in place and applies changes **live where possible**; otherwise the row shows "Relaunch needed" and Settings offers a Relaunch MMTVL action. Entry point: a **Settings tile** that is always present (movable, never hidden or removed; re-added at launch if missing). A gear by the clock was built in M2b and dropped after use (user choice 2026-10-05). Later milestones add their own sections (M3 YouTube, M4 IPTV sources/EPG); secrets entered there go to the Keychain (D9). The learn-button bindings editor comes later (M7). M2b has **no Settings PIN** (user choice 2026-10-05); the launcher PIN arrives in M3 (D20). | User choice (2026-10-05): GUI settings early instead of hand-editing JSON. One settings framework that later milestones only add rows to. |
| D20 | An optional 4-digit **launcher PIN** (Keychain, D9; the legacy keychain, because the data-protection keychain needs a provisioning profile) guards **Settings**, **Exit to Desktop**, and tiles with **Require PIN** on (`requiresPIN` in `launch-items.json`). It is entered on a **privacy keypad** like Google TV's: Up/Down moves a visible row highlight, and Left/Select/Right enters that row's first/middle/last digit with no on-screen sign of which. 5 wrong tries lock entry for 60 s. Recovery is Mac-side (`security delete-generic-password`). | User choice (2026-10-05). Keeps a kid away from the desktop, the browser and Settings, and resists anyone watching the TV. |
| D21 | YouTube hosting: **one persistent WKWebView** (default website data store), created on first open and **kept alive and paused** while away (D18 semantics). The page is told it is always visible, so coming back doesn't trigger YouTube's resume screens (found in M3 step 3). Remote commands reach leanback as **JS key events** (arrows, 13, 27, 179 play/pause, 228/227 FF/RW). Home always leaves; Back goes to the page; leanback's own exit (`window.close`) returns home. Top-level navigation is limited to YouTube/Google hosts. The UA can be overridden in `settings.json` (`youtubeUserAgent`). | Verified in a WKWebView spike (2026-10-05): leanback, 4K playback and these key codes work. One code path serves keyboard, controller and the phone remote. The UA override survives YouTube changes without a rebuild. |
| D22 | mpv video is drawn with the **libmpv render API (OpenGL) in a `CAOpenGLLayer`** (`vo=libmpv`, `hwdec=videotoolbox`), via **MPVKit 1.0.0, LGPL product**. One core per player; players are pooled (up to 5 for Multiview) and never destroyed (M6 L2). `video-timing-offset=0`, so render calls on the main thread don't block for frame timing (M6 L7). Not MPVKit's Metal/MoltenVK `wid` path. | Verified in an M4 spike: picture, VideoToolbox decoding and live resizing (needed for the guide's preview window) work. The MoltenVK path ignores layer resizes (MPVKit #3) and is an unofficial patch; mpv recommends the render API over `wid`. IINA uses the same approach. |
| D23 | IPTV **channels are not persisted**: the playlist is fetched at launch, when Live TV opens (if older than 10 min) and on demand, and kept in memory. Only the **EPG** goes to SQLite (D8). Source and guide URLs are Keychain items (D9; the guides as one JSON list from M6b); full source/stream URLs are never logged. Settings may show a guide's file name when it looks like a guide file (M6b L2). | Stream URLs embed the account token (D9). The playlist is ~30 KB and its game entries change daily. |
| D24 | Phone remote (M5): **two `NWListener`s**, plain HTTP on `phoneRemotePort` (8765) for the page and WebSocket on port + 1 (Network.framework's WebSocket listener can't serve HTTP). Auth by first message with a token from **QR/4-digit pairing on Settings → Phone Remote → Pair a Phone** (token hashes in the Keychain, D9). Phone buttons are `RemoteCommand`s: while MMTVL is frontmost they go through `InputRouter`; otherwise Home uses the global-Home path and the rest are **posted as tagged synthetic key/media events** to the frontmost app (Accessibility, D4). Phone text is diffed and posted as Unicode key events. MMTVL's input code ignores its own tagged events. | One remote for MMTVL and the external apps (user choice 2026-10-06). Verified 2026-10-06: the WebSocket listener rejects plain HTTP; incoming LAN connections need no Local Network permission (TN3179). |
| D25 | Phone volume goes **SoundSource first, then system, then in-app**. If SoundSource is running, MMTVL posts volume keys for its Super Volume Keys. Otherwise it sets the CoreAudio output volume when settable. Otherwise, while MMTVL is frontmost, it uses MMTVL's own volume (mpv + YouTube page). `settings.json` `phoneRemoteVolume` can force a route. | HDMI has no macOS volume (verified 2026-10-06). The user runs SoundSource on the mini and wants a fallback without it (2026-10-06). |
| D26 | **Several XMLTV guides** (M6b), up to 6, in priority order. Each guide's rows in `guide.sqlite` carry a `sourceID` (SHA-256 of its URL). Matching runs **rule by rule, then guide by guide** (an exact `tvg-id` anywhere beats a name match), and each import keeps what that guide matches on its own, so reordering or removing guides never downloads. Manual matches from Live TV's **Match Guide** (ranked suggestions, no text search) are written to `epg-overrides.json` (`""` = no guide). Favorites (order added, movable) and hidden channels/groups are `iptv-channels.json`; every Live TV list goes through one lineup. | The user's playlist needs US2 plus small per-network files (FANDUEL1 110 KB) instead of the 192 MB ALL_SOURCES1. Exact automatic matching stays (M4: fuzzy matching gave wrong channels); suggestions only rank. User choices 2026-10-06: suggestions only, favorites in order added with Move Up/Down, groups hidden in Settings only. |
| D27 | Three more `RemoteCommand`s (M7): **`menu`** (channel menu in Live TV, window menu in Multiview, closes menus), **`channelUp`/`channelDown`** (zap in the player and in a Multiview window; page through lists). Channel Up moves **up the list like the Up arrow** by default; `settings.json` `channelUpMovesUpList` (Settings → Remote & Input → Channel Up) switches it to the higher channel number (user choice 2026-10-06). Defaults: Page Up/Down, Tab and the PC Menu key, controller triggers and Y, phone buttons. New default bindings reach existing `key-bindings.json` once, through `settings.json` `keyBindingsRevision`. **Settings → Remote Buttons** edits the bindings: a learn mode captures the next key, media key or controller button (never ⌘-combos, never phone commands), the last button of an arrow/Select/Back can't be removed, and only Home bindings can work in other apps. | User choice (2026-10-06): Menu and Channel commands. Learning is the only way to map an unknown remote (Q1) without hand-editing JSON. |
| D28 | **Top shelf** (M7): the area above the tiles shows the focused tile's content: Live TV "On Now" cards (favorites, else recent channels), Plex "Continue Watching", else a banner of the tile's art; Up from the first row enters it; PIN-protected tiles show only a banner. **Plex** is read from the user's Plex Media Server: sign-in by **plex.tv/link PIN** in Settings → Plex, tokens in the Keychain (`plex-token`, `plex-server-token`), server found through plex.tv resources, **https (`plex.direct`) connections only**, local first. Selecting a Plex card opens Plex HTPC (no deep link yet, Q11). MMTVL declares `NSLocalNetworkUsageDescription`. | User choice (2026-10-06). The PIN link flow suits a remote (no typing). https avoids App Transport Security exceptions for LAN IPs. |
| D29 | **Tile art and Liquid Glass** (M7 addendum): app tiles get **designed art drawn by MMTVL** (brand gradient + the app's own icon; colors from the icon for unknown apps), no logo files in the repo; custom pictures in `tile-art/` still win, and **Settings → a tile → Tile Art** chooses the style or a picture from Downloads/Pictures/Desktop (copied into `tile-art/`). The UI follows tvOS 26/27 **Liquid Glass** everywhere (SwiftUI `glassEffect`, glass rims on tiles, solid fallback with Reduce Transparency); the top shelf art fills the screen behind the tiles. | User choice (2026-10-06). tvOS icons have no public source (App Store APIs serve square iOS icons only). |

## 5. Architecture overview

```
MMTVL.app
├─ App/            AppDelegate, kiosk window controller, lifecycle, login item, sleep assertions
├─ Input/          RemoteCommand, InputRouter, key bindings, global event tap, game controllers
├─ DesignSystem/   tvOS-style tokens, focusable tile/button styles, parallax, glass
├─ Launcher/       Home screen, LaunchItem model + store, AppLauncher (NSWorkspace), focus model, tile art, top shelf
├─ YouTube/        WKWebView host (D21), TV user agent, key map, profile fallback
├─ PIN/            Launcher PIN (D20): Keychain store, privacy keypad, flows, entry screen
├─ IPTV/
│   ├─ Sources/    M3U parser, channel list, Keychain source URLs
│   ├─ EPG/        XMLTV parser, matcher, GRDB store, refresh scheduler
│   ├─ Player/     mpv wrapper (MPVKit), timeshift controls, OSD
│   ├─ Guide/      Grid guide UI, channel list, favorites/groups
│   └─ Multiview/  Tile layouts, audio focus
├─ Plex/           plex.tv link sign-in, server discovery, Continue Watching (M7, D28)
├─ RemoteServer/   HTTP + WebSocket server, pairing, served web remote assets
└─ Settings/       Remote-navigable settings screens
```

Data flow for input: `remote/keyboard/phone → InputRouter → RemoteCommand → active screen's handler` (the launcher, YouTube host, IPTV player, …). When an external app is frontmost, only the **global** Home command is intercepted. Everything else passes through to that app.

## 6. Milestones

Status values: `Not planned` → `Planned` → `In progress` → `Done` (or `Blocked`).

| ID | Milestone | Depends on | Status | Sub plan |
|---|---|---|---|---|
| M0 | Project bootstrap: Xcode project, test target, planning system, CLAUDE.md | — | Done | — |
| M1 | Launcher shell & kiosk: borderless fullscreen window, home screen tiles, custom focus, launching external apps, Exit to Desktop | M0 | Done | [M1-launcher-shell.md](M1-launcher-shell.md) |
| M2 | Input layer: remappable bindings, global Home (event tap + Accessibility onboarding), game controllers, cursor auto-hide, launch at login, sleep/wake behavior, signing with personal team, full screen for launched apps via Accessibility (D15) | M1 | Done | [M2-input-layer.md](M2-input-layer.md) |
| M2b | Settings screen: an always-present Settings tile; remote-navigable settings screen on the custom focus model (D2); toggles for `settings.json` applied live where possible; Accessibility status with a grant action; home tile editing (reorder, hide, full screen, add any installed app) | M2 | Done | [M2b-settings-screen.md](M2b-settings-screen.md) |
| M3 | YouTube: WKWebView `youtube.com/tv`, TV user agent, key mapping, **verify Parent code**, profile fallback if needed, verify Link-with-TV-code casting, launcher PIN with privacy keypad (D20) | M2b | Done | [M3-youtube-and-pin.md](M3-youtube-and-pin.md) |
| M4 | Live TV (IPTV core): clipboard-pasted M3U source in the Keychain, channel import, single XMLTV guide source, grid guide with preview, mpv player (D22), **rewind buffer**, Settings → Live TV. (Xtream dropped: the provider is plain M3U.) | M2b | Done | [M4-live-tv.md](M4-live-tv.md) |
| M5 | Phone remote: LAN web server, QR pairing, D-pad/media/volume/text entry, control of external apps | M2, M2b, M3, M4 | Done | [M5-phone-remote.md](M5-phone-remote.md) |
| M6 | Multiview: up to 5 windows in six layouts (1 + 4, 1 + 3, 2 × 2, 1 + 2, Side by Side, Picture in Picture), sound follows the highlight, per-window rewind, window menu and picker guide, guide channel menu | M4, M5 | Done | [M6-multiview.md](M6-multiview.md) |
| M6b | IPTV guide management: multiple EPG sources + manual channel ↔ EPG matching, favorites, hidden channels/groups (adds items to M6's guide channel menu). Catch-up dropped: the provider has none (Q3). | M6 | In progress | [M6b-guide-management.md](M6b-guide-management.md) |
| M7 | Launcher polish & remote buttons: home rows scroll (more than two rows), parallax/specular tile effect, custom and designed tile art, top shelf (Live TV On Now, Plex Continue Watching with plex.tv/link sign-in), Menu/Channel Up/Down commands, learn-button bindings editor in Settings, Chromium web app tiles (launch safety net, per-tile start page) | M2b, M3–M6b | Done | [M7-launcher-polish.md](M7-launcher-polish.md) |
| M7b | Phone & casting: phone remote home-screen icon, phone trackpad mode, YouTube DIAL discovery, casting setup checklist (AirPlay/Plex/YouTube), on-TV QA pass for M7 + M7b | M7 | Not planned | — ([research notes](M7b-notes.md)) |

## 7. Open questions

| # | Question | Blocks |
|---|---|---|
| Q1 | Which remote will be purchased? Its Home button must emit a key macOS can see (or be mapped to one by Remote Buddy/Flirc). M2 makes bindings remappable and logs unbound key codes, so this only affects `key-bindings.json`. | Nothing (bindings are data) |
| Q2 | ~~Does `youtube.com/tv` in a WKWebView expose Parent code and child profiles?~~ **Yes (verified with the user 2026-10-05):** a kid account works, the Parent code is required to leave it, and sign-in, profile and code survive a relaunch. D5's primary path holds; no launcher profiles needed. | — |
| Q3 | ~~Does the provider expose the Xtream API and HLS output, and does it offer catch-up?~~ **No Xtream, HLS yes, no catch-up (verified 2026-10-06).** The playlist is plain M3U; streams are live HLS with a 40 s window. M6 catch-up is moot unless the provider changes. | — |
| Q4 | Prime Video: Mac App Store app or browser? (test which is more remote-friendly) | M1 default launch item only |
| Q5 | Final app name / display name (currently "MMTVL") | Nothing |
| Q6 | macOS version on the Mac mini | Deployment target |
| Q7 | ~~Which XMLTV guide URL for Live TV?~~ **guide-source US2** (user, 2026-10-06). With M4's hand-edited `epg-overrides.json`, it covers 58/97 live channels. The FanDuel regionals and international channels need a second source: **M6b** multiple EPG sources. Small guide-source files cover most of them (verified 2026-10-06): FANDUEL1 (FanDuel regionals, FanDuel TV/Racing), CA2 (TSN), IN1 (Star Sports), MY1 (Astro Cricket), UK1 (Premier Sports). How many match by name, and which one "TVG" is, is checked in M6b. | — |
| Q8 | ~~Does SoundSource's Super Volume Keys react to MMTVL's **synthetic** volume keys?~~ **Yes on the dev Mac (2026-10-06):** a phone volume button showed SoundSource's HUD for a USB DAC with no macOS volume. Confirm over HDMI on the mini; if it fails there, set `phoneRemoteVolume: "app"`. | — |
| Q9 | Does "Add to Home Screen" open the http phone remote standalone (no browser bar) on iOS 26 / Android? Unverified, cosmetic. | Nothing |
| Q10 | ~~Does the provider really serve 5 streams at once to the mini, and does a channel change free its stream at once?~~ **Yes (user, 2026-10-06):** five windows in 1 + 4 played, and Change Channel on a full 1 + 4 worked 3 times in a row (M6 step 7). | — |
| Q11 | Can Plex HTPC be opened on a specific item (its `plex` URL scheme, or Plex Companion `playMedia`)? Unverified; M7 only launches Plex from a Continue Watching card. | Nothing (a later improvement) |
| Q12 | Does the Plex PIN link flow (plex.tv calls it "legacy") keep working, and does the user's router allow `plex.direct` names (DNS-rebinding protection)? Checked in M7 steps 11–12; fallbacks in the M7 plan. | M7 Plex shelf |

## How planning works

1. **Master plan (this file):** reviewed by the user. Holds goals, decisions, architecture, milestone status.
2. **Sub plans (`docs/plans/M<n>-<slug>.md`):** created from [TEMPLATE.md](TEMPLATE.md) when a milestone is about to start, via `/plan-milestone M<n>`. Written with high effort and research. They contain everything an implementer needs: file paths, types, ordered steps, acceptance checks, and known pitfalls.
3. **Execution:** `/build-plan docs/plans/M<n>-<slug>.md` implements a sub plan step by step. It can run on a smaller model or lower effort. Executors follow the plan and do not redesign. If a step is wrong or ambiguous, they stop, record it in the sub plan's *Deviations & questions* section, and ask.
4. **Status:** executors tick step checkboxes in the sub plan and update the milestone row above. New decisions discovered during planning are added to §4.
