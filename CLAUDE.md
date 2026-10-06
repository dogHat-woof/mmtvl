# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

MMTVL is a personal, native macOS media launcher styled after tvOS. It runs full screen on a Mac mini (HDMI → AV receiver → TV) and is driven by a remote, keyboard/mouse, or phone. It launches external apps (Plex HTPC, Prime Video, a browser) and has built-in YouTube (TV UI) and IPTV experiences.

**Start every task by reading `docs/plans/MASTER_PLAN.md`.** It holds the goals, architecture decisions (D1…), and milestone status. Work is driven by per-milestone sub plans in `docs/plans/`.

## Planning workflow

- `/plan-milestone M<n>`: research and write a detailed sub plan (`docs/plans/M<n>-<slug>.md`) from `docs/plans/TEMPLATE.md`. Planning only, no app code. Best run with a strong model / high effort.
- `/build-plan docs/plans/M<n>-<slug>.md`: implement a sub plan step by step. It can run on a smaller model / lower effort.
- When implementing: follow the sub plan, tick its checkboxes, and keep the milestone status in the master plan current. Don't redesign. If the plan is wrong or ambiguous, record it under *Deviations & questions* in the sub plan and ask.
- Architecture-level changes must be reflected in the master plan's decisions table (§4).

## Commands

```sh
# Build (Debug)
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build

# Run all tests
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test

# Run a single test (Swift Testing: Target/Suite/test())
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test \
  -only-testing:'MMTVLTests/SmokeTests/appModuleLoads()'

# Launch the built app (kiosk mode hides Dock/menu bar; ⌘Q quits)
open build/Build/Products/Debug/MMTVL.app
# Launch in a normal window for development (no global input: event tap, login item, wake handling)
open build/Build/Products/Debug/MMTVL.app --args -windowed YES

# Watch the app's log (unbound keys show up here while MMTVL is frontmost)
/usr/bin/log stream --predicate 'subsystem == "dev.mmtvl.launcher"' --level info
# Only mpv's messages (Live TV playback; lines name the player, e.g. "(player 2)" in Multiview)
/usr/bin/log stream --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "MPV"' --level info
# Only the phone remote (server state, connections, pairing; never codes, tokens or typed text)
/usr/bin/log stream --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "PhoneRemote"' --level info
# Is the phone remote's page being served?
curl -i http://localhost:8765/
```

## Project setup notes

- Xcode project with **file-system-synchronized groups**: any file placed under `MMTVL/` or `MMTVLTests/` is automatically part of that target. Don't add file references to `project.pbxproj` by hand. It only needs editing for build settings, new targets, or Swift package dependencies.
- No `Info.plist` file: it is generated from `INFOPLIST_KEY_*` build settings. Add Info.plist keys there.
- Swift 6 with **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**: types are main-actor by default. Mark pure models/helpers `nonisolated` when they must be used off the main actor.
- Not sandboxed, no hardened runtime. Signed `Apple Development` with the personal team **H846CY8RB4** (no provisioning profile needed), so the Accessibility (TCC) grant for the global event tap and AX full screen survives rebuilds. To re-test onboarding: `tccutil reset Accessibility dev.mmtvl.launcher`.
- Deployment target: macOS 26.0. Bundle ID: `dev.mmtvl.launcher`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), hosted in the app (`@testable import MMTVL`).
- Swift packages (M4): **MPVKit 1.0.0** (the LGPL `MPVKit` product only, never `MPVKit-GPL`; `import Libmpv`) and **GRDB 7.11.x**, linked to the **app target only**. Tests reach them through app types (`EPGStore.inMemory()`), never by importing them. `MMTVL.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is committed. The first resolve downloads about 350 MB of MPVKit binaries. `MPVVideoView.swift` shows OpenGL deprecation warnings by design (D22). Multiview (M6) runs up to 5 mpv players, one per window, from a pool in `LiveTVModel` that is reused and never torn down.

## Conventions

- Logging: `os.Logger(subsystem: "dev.mmtvl.launcher", category: "<Component>")`.
- Secrets (IPTV URL/credentials, PINs) go in the Keychain via `App/Keychain.swift`: the **legacy login keychain**, service `dev.mmtvl.launcher` (never `kSecUseDataProtectionKeychain`, which fails with -34018 without a provisioning profile). The launcher PIN (D20) is account `launcher-pin`. Forgotten PIN, from the Mac: `security delete-generic-password -s dev.mmtvl.launcher -a launcher-pin`. The Live TV playlist URL is account `iptv-playlist-url`; the pasted guide URLs (M6b, up to 6, in priority order) are account **`iptv-guide-urls`**, a JSON array (M4's single `iptv-guide-url` is migrated on the next save and removed). All are pasted from the clipboard in Settings → Live TV. They carry account tokens: **never log or show a full IPTV source or stream URL**, only its host. Exception (M6b L2): Settings may show a guide's file name when it looks like a guide file (`.xml`, `.xml.gz`, `.gz`, at most 64 characters), never its query; logs still show the host only. Paired phones (M5) are account `phone-remote-phones`: a JSON array of names and token SHA-256 hashes (never the tokens). Reset from the Mac: `security delete-generic-password -s dev.mmtvl.launcher -a phone-remote-phones`. Non-secret config is JSON in `~/Library/Application Support/MMTVL/`, read at launch. Missing files are written with defaults; a corrupt file is moved to `<name>.bak` and replaced with defaults:
  - `launch-items.json`: home screen tiles, in order. Per item, optional `launchFullScreen` (D15), `isHidden` and `requiresPIN` (D20; Settings and Exit to Desktop always ask when a PIN is set).
  - `settings.json`: `globalInputEnabled`, `controllersEnabled`, `cursorAutoHide`, `launchAtLogin` (kiosk mode only). Optional hand-edited `youtubeUserAgent` overrides the YouTube TV user agent (D21). `phoneRemoteEnabled` (Settings → Phone Remote). Hand-edited `phoneRemotePort` (default 8765, the page; the WebSocket uses port + 1; outside 1024…65534 falls back to 8765) and `phoneRemoteVolume` (`auto` | `keys` | `system` | `app`, D25; unknown values read as `auto`). Missing keys use defaults.
  - The **Settings screen** (the Settings tile, which is always on the home screen and can be moved but not hidden or removed) edits `settings.json` and `launch-items.json` live and saves each change at once. Hand edits made while MMTVL runs are overwritten by the next Settings change, so edit those files with MMTVL quit. Settings → Relaunch MMTVL picks up hand edits.
  - `iptv-state.json`: Live TV's last channel and group, `guideImports` (guide id = SHA-256 of its URL → last successful import; replaces M4's `lastGuideImport`/`lastGuideSourceHash`, which are ignored), and the Multiview snapshot `multiview` (layout, channel ids per window, highlighted window, whether Live TV was left in Multiview). An undecodable snapshot reads as none. Hand edits are fine while MMTVL is quit.
  - `epg-overrides.json` (M4 L17): `{ "<channel name or tvg-id>": "<EPG channel id>" }` for channels the guide doesn't match by id or exact name. Keys match the playlist's channel name first, then its `tvg-id`, ignoring case. A value of `""` means no guide. Also written by Live TV's **Match Guide** (M6b: in the guide, Left on the programme airing now, Select, Match Guide), keyed by channel name; *Automatic* removes the channel's keys. Hand edits: Settings → Live TV → Refresh Now applies them (no relaunch); edit with MMTVL quit, since Match Guide rewrites the file. To find EPG ids: `gzip -dc guide.xml.gz | grep -o '<channel id="[^"]*"'`.
  - `iptv-channels.json` (M6b L5): `favorites` (channel ids, in order), `hiddenChannels` (channel ids), `hiddenGroups` (group names as in the playlist). Set from the guide's channel menu and Settings → Live TV → Groups / Hidden Channels. Ids not in the playlist are kept and ignored. Hand edits while MMTVL is quit. Kept by Remove Live TV Source.
  - `guide.sqlite` (+ `-wal`/`-shm`): the EPG cache (GRDB, D8). Rows are per guide (`sourceID` = SHA-256 of the guide URL, D26). Safe to delete; the next guide refresh rebuilds it. Channels are never stored; the playlist is re-fetched at launch and when Live TV opens (D23).
  - `key-bindings.json` (still hand-edited; a learn-button editor comes in M7): an array of `{ "trigger", "command", "isGlobal", "label" }`. Triggers are `{"key": {"keyCode": 115, "modifiers": []}}`, `{"media": {"key": "playPause"}}` or `{"controller": {"button": "a"}}`. Modifiers must match exactly. `isGlobal` bindings also act while another app is frontmost (keys need Accessibility). To find a new remote's key codes, run the `log stream` command above with MMTVL frontmost and press the buttons: each unbound key logs `Unbound key <code> modifiers [...]`.
- YouTube (D5, D21) is `youtube.com/tv` in one persistent WKWebView (`YouTube/`). Its website data (sign-ins, profiles, Parent code) is in `~/Library/WebKit/dev.mmtvl.launcher/WebsiteData`; Settings → Sign Out & Clear YouTube Data wipes it. In Debug builds, Safari → Develop → this Mac inspects the YouTube page.
- Phone remote (D11, D24, M5) lives in `RemoteServer/`: plain HTTP on `phoneRemotePort` serves the page, a WebSocket on port + 1 carries the remote. The phone opens `http://<Mac IP>:8765/`, so give the Mac mini a DHCP reservation on the router. Pairing is only on Settings → Phone Remote → Pair a Phone (QR code + 4-digit code). The page's files are in `MMTVL/RemoteServer/Web/` (`remote.html/.css/.js`, unique names because they ship flat in `Contents/Resources`); `RemoteWebAssets` allow-lists them. **Never log tokens, pairing codes, typed text or raw messages.**
- Synthetic input (M5 L6): phone keys for other apps and phone text are posted by `Input/SyntheticInput.swift`, tagged with `eventSourceUserData = SyntheticInput.marker`. MMTVL's input code (`InputRouter`'s local monitor, `GlobalEventTap`) must keep passing `SyntheticInput.isOwn` events through untouched, or typed Delete becomes Back.
- UI is designed on a 1920×1080-point canvas (a 4K TV in HiDPI mode) and scaled to the screen. Use the tokens in `DesignSystem/Theme.swift`, not literals.
- All input flows through `InputRouter` as `RemoteCommand`s. Screens handle commands, not raw key events.
