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
| IPTV provider | the IPTV provider: M3U URL with embedded credentials (very likely also Xtream Codes). **5 concurrent streams** observed. |
| EPG | User-supplied XMLTV sources (multiple) |
| Remote | Not purchased. Candidates: Siri Remote + Remote Buddy 2, WeChip G20S Pro, Flirc + IR remote. The app must work with any remote that emits key events. |

## 4. Key decisions

Record every architecture-level decision here. Sub plans may make local decisions but must not contradict these without updating this table.

| ID | Decision | Rationale |
|---|---|---|
| D1 | Launcher window is an **AppKit-owned borderless window covering the screen**, with `NSApp.presentationOptions` hiding the Dock and menu bar. **Not** native fullscreen Spaces. | Avoids Space-switch animations when jumping to/from Plex and other fullscreen apps. Presentation options auto-revert when another app is frontmost. |
| D2 | **Custom focus engine** (a focus model plus key-command routing), not SwiftUI's built-in focus traversal. | Directional (arrow-key) focus movement is a tvOS-only SwiftUI behavior. On macOS we must drive focus ourselves. |
| D3 | All input is normalized into a `RemoteCommand` enum by a central `InputRouter`. Sources: local key events (M1), global event tap, remappable bindings, game controllers (M2), phone remote (M5). | One place for remapping. Every remote type works the same way. |
| D4 | Global Home button uses a **CGEventTap**, which requires Accessibility permission. | Needed to steal a key/button back from Plex, browsers, etc. Acceptable for a personal unsandboxed app. Signing must be stable so the TCC grant survives rebuilds: Apple Development cert, team **H846CY8RB4** (the user's own team; verified to build without a provisioning profile). |
| D5 | YouTube = `youtube.com/tv` in a **WKWebView inside the launcher**, with a TV user agent. Profile PIN protection relies on YouTube's own **Parent code**. Fallback: launcher-level profiles with isolated `WKWebsiteDataStore`s and a launcher PIN. | Best remote UX. Keeps the user inside the launcher. Parent code matches the desired child-profile behavior. |
| D6 | IPTV is **built in**. Player engine = **libmpv via MPVKit** (Swift package). | IPTV streams are often raw MPEG-TS that AVPlayer handles poorly. mpv plays nearly everything and supports a back-buffer for rewind. |
| D7 | IPTV **rewind buffer** uses mpv's demuxer back-cache (`demuxer-max-back-bytes`, optionally `cache-on-disk`), targeting **≥ 5 minutes** per live stream. | Meets "cache a few minutes to rewind" without a DVR. |
| D8 | EPG and channel data are stored in **SQLite (GRDB)**. XMLTV is stream-parsed and refreshed on a schedule. | XMLTV files can be 100MB+. The guide grid needs fast time-range queries. |
| D9 | Secrets (IPTV URL/credentials, PINs) live in the **Keychain**, never in config files or the repo. | — |
| D10 | Non-secret config (launch items, bindings, EPG source URLs, settings) is JSON in `~/Library/Application Support/MMTVL/`. | Easy to inspect and back up. |
| D11 | The phone remote is a **web page served by the launcher** (Network.framework HTTP + WebSocket on the LAN), protected by a pairing code. A native iOS app is optional later. | Works on iOS and Android with no install. Supports text entry. |
| D12 | Casting: **AirPlay = macOS's built-in AirPlay Receiver** (a setting, no code). Plex = Plex HTPC as a Plex Companion player. YouTube = "Link with TV code" in the TV UI. No Chromecast receiver. | Zero/low code and reliable. |
| D13 | Prime Video and the generic browser are launched as **external apps** (Prime Video Mac app or Safari/Chrome). | DRM (Widevine/FairPlay) does not work reliably in our WKWebView. |
| D14 | Multiview: up to **4 tiles** (2-up, 2×2), each its own mpv instance. Audio follows the focused tile. | Fits within the 5-connection limit with one spare for the guide preview. |
| D15 | Launched apps open **full screen**. M1: Chromium browsers get `--start-fullscreen` (only works on a cold launch). M2: a general path that sets `AXFullScreen` on the app's main window through the Accessibility API, covering Safari, Prime Video and apps that are already running. The browser tile opens the **system default browser** (Brave). | TV use needs no window chrome. Accessibility is already required for D4, so the general path adds no new permission. |
| D16 | Input bindings are **data**: `key-bindings.json` maps key / media-key / controller-button triggers to `RemoteCommand`s, each with an `isGlobal` flag. App settings live in `settings.json`. Both are in the D10 directory, read at launch. Hand-edited until the M2b Settings screen (settings and launch items); bindings stay hand-edited until the M7 learn-button editor. | A new remote needs no code change. Unbound key codes are logged (only while MMTVL is frontmost) to help mapping. |
| D17 | **One active CGEventTap** handles global input: it always consumes `isGlobal` bindings (Home) and consumes media keys **only while the launcher is frontmost**; it never logs keys. Game controllers use GameController with `shouldMonitorBackgroundEvents`; in the background only global bindings act. All global input is off in `-windowed` mode. | Keeps other apps (Plex, browsers) fully usable while Home always works. Avoids keylogging. Protects the dev Mac's Home key. |
| D18 | **Home from an external app leaves it running** (tvOS semantics); **system wake** always returns to the launcher home screen. | User choice (2026-10-05). Instant return to Plex and the like; predictable state from the couch. |
| D19 | A **remote-navigable Settings screen** (a Settings tile, M2b) edits the D10 JSON files in place and applies changes **live where possible**; otherwise the row shows "Relaunch needed" and Settings offers a Relaunch MMTVL action. Entry points: an always-present gear by the clock (reached with Up) **and** an optional regular tile. Later milestones add their own sections (M3 YouTube, M4 IPTV sources/EPG); secrets entered there go to the Keychain (D9). The learn-button bindings editor comes later (M7). | User choice (2026-10-05): GUI settings early instead of hand-editing JSON. One settings framework that later milestones only add rows to. |

## 5. Architecture overview

```
MMTVL.app
├─ App/            AppDelegate, kiosk window controller, lifecycle, login item, sleep assertions
├─ Input/          RemoteCommand, InputRouter, key bindings, global event tap, game controllers
├─ DesignSystem/   tvOS-style tokens, focusable tile/button styles, parallax, glass
├─ Launcher/       Home screen, LaunchItem model + store, AppLauncher (NSWorkspace), focus model
├─ YouTube/        WKWebView host, TV user agent, profile fallback
├─ IPTV/
│   ├─ Sources/    M3U + Xtream clients, channel import
│   ├─ EPG/        XMLTV parser, matcher, GRDB store, refresh scheduler
│   ├─ Player/     mpv wrapper (MPVKit), timeshift controls, OSD
│   ├─ Guide/      Grid guide UI, channel list, favorites/groups
│   └─ Multiview/  Tile layouts, audio focus
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
| M2b | Settings screen: gear by the clock plus an optional Settings tile; remote-navigable settings screen on the custom focus model (D2); toggles for `settings.json` applied live where possible; Accessibility status with a grant action; home tile editing (reorder, hide, full screen) | M2 | Not planned | — |
| M3 | YouTube: WKWebView `youtube.com/tv`, TV user agent, key mapping, **verify Parent code**, profile fallback if needed, verify Link-with-TV-code casting | M2 | Not planned | — |
| M4 | IPTV core: Keychain-stored M3U/Xtream source, channel import, single EPG source, grid guide, mpv player, **rewind buffer** | M2 | Not planned | — |
| M5 | Phone remote: LAN web server, pairing, D-pad/media/volume/text entry | M2 | Not planned | — |
| M6 | IPTV advanced: multiple EPG sources + manual matching, multiview (2-up/2×2), favorites/groups/hidden, catch-up (if provider supports) | M4 | Not planned | — |
| M7 | Polish: parallax/specular tile effect, top shelf, learn-button bindings editor in Settings, casting setup checklist (AirPlay/Plex/YouTube), on-TV QA pass | M2b, M3–M6 | Not planned | — |

## 7. Open questions

| # | Question | Blocks |
|---|---|---|
| Q1 | Which remote will be purchased? Its Home button must emit a key macOS can see (or be mapped to one by Remote Buddy/Flirc). M2 makes bindings remappable and logs unbound key codes, so this only affects `key-bindings.json`. | Nothing (bindings are data) |
| Q2 | Does `youtube.com/tv` in a WKWebView expose Parent code and child profiles? | M3 design branch |
| Q3 | Does the provider expose the Xtream API (`player_api.php`) and HLS output, and does it offer catch-up? | M4 source design, M6 catch-up |
| Q4 | Prime Video: Mac App Store app or browser? (test which is more remote-friendly) | M1 default launch item only |
| Q5 | Final app name / display name (currently "MMTVL") | Nothing |
| Q6 | macOS version on the Mac mini | Deployment target |

## How planning works

1. **Master plan (this file):** reviewed by the user. Holds goals, decisions, architecture, milestone status.
2. **Sub plans (`docs/plans/M<n>-<slug>.md`):** created from [TEMPLATE.md](TEMPLATE.md) when a milestone is about to start, via `/plan-milestone M<n>`. Written with high effort and research. They contain everything an implementer needs: file paths, types, ordered steps, acceptance checks, and known pitfalls.
3. **Execution:** `/build-plan docs/plans/M<n>-<slug>.md` implements a sub plan step by step. It can run on a smaller model or lower effort. Executors follow the plan and do not redesign. If a step is wrong or ambiguous, they stop, record it in the sub plan's *Deviations & questions* section, and ask.
4. **Status:** executors tick step checkboxes in the sub plan and update the milestone row above. New decisions discovered during planning are added to §4.
