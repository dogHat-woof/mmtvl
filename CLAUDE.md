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
```

## Project setup notes

- Xcode project with **file-system-synchronized groups**: any file placed under `MMTVL/` or `MMTVLTests/` is automatically part of that target. Don't add file references to `project.pbxproj` by hand. It only needs editing for build settings, new targets, or Swift package dependencies.
- No `Info.plist` file: it is generated from `INFOPLIST_KEY_*` build settings. Add Info.plist keys there.
- Swift 6 with **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**: types are main-actor by default. Mark pure models/helpers `nonisolated` when they must be used off the main actor.
- Not sandboxed, no hardened runtime. Signed `Apple Development` with the personal team **H846CY8RB4** (no provisioning profile needed), so the Accessibility (TCC) grant for the global event tap and AX full screen survives rebuilds. To re-test onboarding: `tccutil reset Accessibility dev.mmtvl.launcher`.
- Deployment target: macOS 26.0. Bundle ID: `dev.mmtvl.launcher`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), hosted in the app (`@testable import MMTVL`).

## Conventions

- Logging: `os.Logger(subsystem: "dev.mmtvl.launcher", category: "<Component>")`.
- Secrets (IPTV URL/credentials, PINs) go in the Keychain. Non-secret config is JSON in `~/Library/Application Support/MMTVL/`, read at launch. Missing files are written with defaults; a corrupt file is moved to `<name>.bak` and replaced with defaults:
  - `launch-items.json`: home screen tiles, in order. Per item, optional `launchFullScreen` (D15) and `isHidden`.
  - `settings.json`: `globalInputEnabled`, `controllersEnabled`, `cursorAutoHide`, `launchAtLogin` (kiosk mode only). Missing keys use defaults.
  - The **Settings screen** (the Settings tile, which is always on the home screen and can be moved but not hidden or removed) edits `settings.json` and `launch-items.json` live and saves each change at once. Hand edits made while MMTVL runs are overwritten by the next Settings change, so edit those files with MMTVL quit. Settings → Relaunch MMTVL picks up hand edits.
  - `key-bindings.json` (still hand-edited; a learn-button editor comes in M7): an array of `{ "trigger", "command", "isGlobal", "label" }`. Triggers are `{"key": {"keyCode": 115, "modifiers": []}}`, `{"media": {"key": "playPause"}}` or `{"controller": {"button": "a"}}`. Modifiers must match exactly. `isGlobal` bindings also act while another app is frontmost (keys need Accessibility). To find a new remote's key codes, run the `log stream` command above with MMTVL frontmost and press the buttons: each unbound key logs `Unbound key <code> modifiers [...]`.
- UI is designed on a 1920×1080-point canvas (a 4K TV in HiDPI mode) and scaled to the screen. Use the tokens in `DesignSystem/Theme.swift`, not literals.
- All input flows through `InputRouter` as `RemoteCommand`s. Screens handle commands, not raw key events.
