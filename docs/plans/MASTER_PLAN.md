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
| Distribution | Local build, ad-hoc or personal-team signed, **no App Sandbox, no hardened runtime** (for now) |
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
| D4 | Global Home button uses a **CGEventTap**, which requires Accessibility permission. | Needed to steal a key/button back from Plex, browsers, etc. Acceptable for a personal unsandboxed app. Signing must be stable (personal team) so the TCC grant survives rebuilds. |
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
| M1 | Launcher shell & kiosk: borderless fullscreen window, home screen tiles, custom focus, launching external apps, Exit to Desktop | M0 | Planned | [M1-launcher-shell.md](M1-launcher-shell.md) |
| M2 | Input layer: remappable bindings, global Home (event tap + Accessibility onboarding), game controllers, cursor auto-hide, launch at login, sleep/wake behavior, signing with personal team | M1 | Not planned | — |
| M3 | YouTube: WKWebView `youtube.com/tv`, TV user agent, key mapping, **verify Parent code**, profile fallback if needed, verify Link-with-TV-code casting | M2 | Not planned | — |
| M4 | IPTV core: Keychain-stored M3U/Xtream source, channel import, single EPG source, grid guide, mpv player, **rewind buffer** | M2 | Not planned | — |
| M5 | Phone remote: LAN web server, pairing, D-pad/media/volume/text entry | M2 | Not planned | — |
| M6 | IPTV advanced: multiple EPG sources + manual matching, multiview (2-up/2×2), favorites/groups/hidden, catch-up (if provider supports) | M4 | Not planned | — |
| M7 | Polish: parallax/specular tile effect, top shelf, settings UI, casting setup checklist (AirPlay/Plex/YouTube), on-TV QA pass | M3–M6 | Not planned | — |

## 7. Open questions

| # | Question | Blocks |
|---|---|---|
| Q1 | Which remote will be purchased? (affects default key bindings and Remote Buddy integration) | M2 defaults (not M2 itself) |
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
