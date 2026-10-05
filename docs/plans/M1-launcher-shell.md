# M1 — Launcher shell & kiosk

| | |
|---|---|
| Status | Done |
| Depends on | M0 |
| Master plan decisions used | D1, D2, D3, D10, D13 |
| Planned | 2026-10-05 |

## Goal

Launching MMTVL fills the screen with a dark, tvOS-style home screen: a clock, and rows of wide app tiles. The Dock and menu bar are hidden. Arrow keys move a visible focus (the focused tile grows and casts a shadow, and its name appears under it). Return/Enter opens the item. Esc/Delete goes back. Plex HTPC, Prime Video and a browser launch as external apps. When one of them quits, the launcher comes back to the front. YouTube and IPTV tiles open a "Coming soon" screen. An **Exit to Desktop** tile hides the launcher and restores the Dock and menu bar. Clicking the Dock icon brings the launcher back. Mouse hover moves focus and clicking activates.

## Out of scope

- Global Home key while another app is frontmost, remapping, media keys, game controllers, cursor auto-hide, launch at login, sleep handling → **M2**
- YouTube and IPTV screens → **M3 / M4**
- Parallax/specular tile effect, top shelf, settings UI, custom tile art → **M7**

## Research & findings

- **Directional focus is tvOS-only.** On macOS, SwiftUI's `.focusable()` + `@FocusState` move focus with Tab (and only with Full Keyboard Access). Arrow keys do not move focus between views. Hence D2: our own focus model, with focus *rendered* from model state rather than SwiftUI focus.
- **`NSApp.presentationOptions`** applies only while the app is active. The system restores the Dock/menu bar automatically when another app becomes frontmost and re-applies our options when we reactivate. `.hideMenuBar` must be combined with `.hideDock` (or `.autoHideDock`), or AppKit throws.
- **Borderless windows** return `false` from `canBecomeKey` by default, so they never receive key events. Subclass `NSWindow` and override `canBecomeKey` / `canBecomeMain` to return `true`.
- **Native fullscreen** (`toggleFullScreen`) creates a separate Space, causing slide animations when switching to Plex (which uses its own fullscreen Space). We avoid it (D1).
- **Local key monitor:** `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` sees key events destined for our app. Returning `nil` swallows the event. Events with ⌘ must be passed through so ⌘Q, ⌘Tab, etc. keep working.
- Key codes (`kVK_*` in Carbon `HIToolbox/Events.h`): Left 123, Right 124, Down 125, Up 126, Return 36, Keypad Enter 76, Space 49, Escape 53, Delete 51, Home 115.
- **Media keys** (play/pause, volume) arrive as `NSEvent.EventType.systemDefined`, not `keyDown`. M2 handles them.
- **Launching apps:** `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` resolves an installed app. `NSWorkspace.shared.openApplication(at:configuration:)` (async) launches/activates it and returns the `NSRunningApplication`. `NSWorkspace.didTerminateApplicationNotification` (on `NSWorkspace.shared.notificationCenter`, **not** `NotificationCenter.default`) reports quits. `userInfo[NSWorkspace.applicationUserInfoKey]` is the `NSRunningApplication`.
- **App icons:** `NSWorkspace.shared.icon(forFile: appURL.path)` returns the app's icon (square, macOS style).
- **Bundle IDs (unverified, verify on the Mac mini):** Plex HTPC `tv.plex.htpc`; Prime Video `com.amazon.aiv.AIVApp`; Safari `com.apple.Safari`. Verify with `osascript -e 'id of app "Plex HTPC"'`. Wrong IDs only make a tile show "Not installed". They are data, not code.
- **Point scale:** a 4K TV in the default HiDPI mode is 1920×1080 points. Design everything in a 1920×1080 point canvas and scale by `screenWidth / 1920` so 1080p and 4K look identical.
- Project uses Swift 6 with **MainActor default isolation**. All types are main-actor unless marked `nonisolated`. Mark pure model types/functions `nonisolated` where tests or background work need them.

## Design

### Files

| Path | Responsibility |
|---|---|
| `MMTVL/MMTVLApp.swift` | `@main`. `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Body is `Settings { EmptyView() }` only (no SwiftUI-managed window). |
| `MMTVL/App/AppDelegate.swift` | Builds the object graph (store, launcher, router, input), creates `KioskWindowController`, handles `applicationShouldHandleReopen`. |
| `MMTVL/App/KioskWindow.swift` | `NSWindow` subclass: borderless, `canBecomeKey/Main = true`. |
| `MMTVL/App/KioskWindowController.swift` | Sizes the window to the screen, applies/removes presentation options, re-fits on screen changes, `show()`, `exitToDesktop()`. Honors the windowed debug flag. |
| `MMTVL/App/AppEnvironment.swift` | `windowedMode` flag read from `UserDefaults` (`-windowed YES` launch argument). |
| `MMTVL/Input/RemoteCommand.swift` | `enum RemoteCommand { up, down, left, right, select, back, home, playPause }` |
| `MMTVL/Input/KeyBindings.swift` | Pure `nonisolated` mapping `(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> RemoteCommand?`. |
| `MMTVL/Input/InputRouter.swift` | `@Observable` class. Installs the local key monitor, converts events via `KeyBindings`, forwards to the current `handler: ((RemoteCommand) -> Bool)?`. Swallows the event only if the handler returns `true`. |
| `MMTVL/Launcher/LaunchItem.swift` | `Codable` model (below). Includes the default item list. |
| `MMTVL/Launcher/LaunchItemStore.swift` | Loads/saves `launch-items.json` in a given directory (default `~/Library/Application Support/MMTVL/`). Seeds defaults if missing or corrupt (keeps a `.bak` of the corrupt file). |
| `MMTVL/Launcher/AppLauncher.swift` | Resolves install state and icons. Launches apps/URLs. Observes termination of apps it launched and reactivates the launcher. |
| `MMTVL/Launcher/LauncherFocusModel.swift` | Pure `nonisolated struct` for grid focus (below). |
| `MMTVL/Launcher/AppRouter.swift` | `@Observable` current screen: `.home` / `.placeholder(LaunchItem)`. Owns command dispatch to the active screen. |
| `MMTVL/Launcher/HomeView.swift` | Background, clock, tile rows. Renders focus from the model. |
| `MMTVL/Launcher/AppTileView.swift` | One tile: 5:3 rounded rect, icon, focused/unfocused/not-installed states. |
| `MMTVL/Launcher/PlaceholderView.swift` | "Coming soon" screen for internal destinations. |
| `MMTVL/DesignSystem/Theme.swift` | Tokens: colors, corner radius, tile size, spacing, focus scale/shadow, animation, the 1920-point canvas scale helper. |

### Key types

```swift
nonisolated struct LaunchItem: Codable, Identifiable, Hashable {
    enum Kind: Codable, Hashable {
        case application(bundleID: String)
        case url(URL, browserBundleID: String?)   // nil = default browser
        case internalDestination(InternalDestination)
        case system(SystemAction)
    }
    enum InternalDestination: String, Codable { case youtube, iptv, settings }
    enum SystemAction: String, Codable { case exitToDesktop }

    var id: String            // stable slug, e.g. "plex"
    var title: String
    var kind: Kind
    var iconSymbol: String?   // SF Symbol for internal/system items
}
```

Default items, in order (one row of 5, then a second row):
1. `plex`: Plex: `.application("tv.plex.htpc")`
2. `youtube`: YouTube: `.internalDestination(.youtube)`, symbol `play.rectangle.fill`
3. `iptv`: Live TV: `.internalDestination(.iptv)`, symbol `tv`
4. `prime`: Prime Video: `.application("com.amazon.aiv.AIVApp")`
5. `browser`: Safari: `.application("com.apple.Safari")`
6. `exit`: Exit to Desktop: `.system(.exitToDesktop)`, symbol `rectangle.portrait.and.arrow.right`

```swift
nonisolated struct LauncherFocusModel: Equatable {
    var rows: [Int]                 // item count per row
    var position: (row: Int, column: Int)   // use a small Equatable struct instead of a tuple
    mutating func move(_ command: RemoteCommand) -> Bool  // true if position changed
}
```

Rules: left/right clamp within the row (no wrap). Up/down move to the adjacent row, keeping the column clamped to that row's last index. Empty rows are skipped. `rows` comes from chunking items into rows of `Theme.tilesPerRow` (5).

### Local decisions

- **L1:** Rows are a fixed chunking of the item list (5 per row, like tvOS). No user-defined rows in M1.
- **L2:** Tiles show the app's own icon centered on a dark tile background. Proper tvOS-style wide art is M7.
- **L3:** `-windowed YES` launch argument runs the launcher in a normal resizable 1280×720 window without presentation options. Add it to the scheme's Run arguments **unchecked** for convenience.
- **L4:** ⌘-modified keys are never consumed by `InputRouter`, so ⌘Q / ⌘Tab / ⌘H always work as escape hatches.
- **L5:** After an external app we launched terminates, reactivate the launcher **only if** no other regular app has become frontmost in the meantime (check `NSWorkspace.shared.frontmostApplication` is nil or is us). This avoids yanking focus if the user deliberately switched to something else.
- **L6:** "Not installed" tiles stay visible but dimmed with a caption. Selecting one does nothing except a short shake animation.

## Implementation steps

- [x] **1. App delegate + windowed flag**: `MMTVLApp.swift`, `App/AppDelegate.swift`, `App/AppEnvironment.swift`
  - Replace the `WindowGroup` with `Settings { EmptyView() }` and an `@NSApplicationDelegateAdaptor`.
  - `AppEnvironment.windowedMode = UserDefaults.standard.bool(forKey: "windowed")`.
  - Done when: app builds and launches with no window (temporary state) and a Dock icon.

- [x] **2. Kiosk window**: `App/KioskWindow.swift`, `App/KioskWindowController.swift`, `AppDelegate.swift`
  - Kiosk mode: `styleMask = [.borderless]`, `backgroundColor = .black`, `level = .normal`, `collectionBehavior = [.fullScreenNone]`, frame = `NSScreen.screens.first!.frame` (the menu-bar screen). Set `NSApp.presentationOptions = [.hideDock, .hideMenuBar]`.
  - Windowed mode: titled/resizable/closable 1280×720 centered window, presentation options untouched.
  - Observe `NSApplication.didChangeScreenParametersNotification` → re-fit frame (HDMI/AVR handshakes change modes).
  - `show()`: `makeKeyAndOrderFront`, `NSApp.activate()`. `exitToDesktop()`: set presentation options `[]`, `orderOut`, `NSApp.hide(nil)`.
  - `applicationShouldHandleReopen` → `show()` and re-apply presentation options. Return `true`.
  - Content for now: `NSHostingView(rootView: Color.black)`.
  - Done when: launch fills the screen with black, no Dock/menu bar. ⌘Tab to Finder shows Dock/menu bar again. ⌘Tab back hides them. `-windowed YES` gives a normal window.

- [x] **3. Commands, bindings, router**: `Input/RemoteCommand.swift`, `Input/KeyBindings.swift`, `Input/InputRouter.swift`, `MMTVLTests/KeyBindingsTests.swift`
  - `KeyBindings.command(keyCode:modifiers:)`: arrows → directions. Return/Keypad Enter → select. Esc/Delete → back. Space → playPause. Home (115) → home. Any `.command` modifier → `nil`.
  - `InputRouter.start()` installs the local monitor and keeps the token. `stop()` removes it.
  - Tests: each mapping, ⌘+arrow → nil, unknown key → nil.
  - Done when: tests pass.

- [x] **4. Launch items + store**: `Launcher/LaunchItem.swift`, `Launcher/LaunchItemStore.swift`, `MMTVLTests/LaunchItemStoreTests.swift`
  - `LaunchItemStore(directory: URL)` with `load() -> [LaunchItem]` and `save(_:)`. Pretty-printed, sorted-keys JSON. Create the directory if needed.
  - Tests (temp directory): missing file → defaults written and returned. Round-trip save/load. Corrupt file → defaults returned and `launch-items.json.bak` exists.
  - Done when: tests pass.

- [x] **5. App launcher**: `Launcher/AppLauncher.swift`
  - `isInstalled(_ item:) -> Bool`, `icon(for item:) -> NSImage?` (cache by bundle ID).
  - `launch(_ item:) async throws`: `.application` → resolve URL, `openApplication` with `activates = true`, remember the returned PID. `.url` → `NSWorkspace.shared.open([url], withApplicationAt:configuration:)` when a browser ID is given, else `open(url)`. Other kinds are not handled here.
  - Observe termination on `NSWorkspace.shared.notificationCenter`. If the PID is one we launched, apply L5 and call an injected `onReturnToLauncher` closure (wired to `KioskWindowController.show()`).
  - Log with `Logger(subsystem: "dev.mmtvl.launcher", category: "AppLauncher")`.
  - Done when: builds. Behavior is verified in step 9.

- [x] **6. Theme**: `DesignSystem/Theme.swift`
  - Tokens (in 1920×1080 points): tile 300×180 (5:3), corner radius 16, tile spacing 48, row spacing 72, side margin 120, focus scale 1.1, focus shadow radius 30 / y-offset 20 / opacity 0.5, spring `response 0.3, dampingFraction 0.8`, background gradient `#1C1C1E → #000000`, `tilesPerRow = 5`.
  - `Theme.scale(for size: CGSize) -> CGFloat = size.width / 1920`. Apply once at the root with `.scaleEffect` on a fixed 1920×1080 canvas, **or** multiply tokens. Pick canvas + `scaleEffect` (simpler, crisp because SwiftUI re-rasterizes text).
  - Done when: builds.

- [x] **7. Focus model**: `Launcher/LauncherFocusModel.swift`, `MMTVLTests/LauncherFocusModelTests.swift`
  - Implement the rules above, with `init(itemCount:perRow:)`.
  - Tests: clamping at edges (returns false). Down from column 4 into a shorter row clamps to its last index. Up/down past first/last row → false. A single item never moves. Zero items is safe.
  - Done when: tests pass.

- [x] **8. Home screen**: `Launcher/HomeView.swift`, `Launcher/AppTileView.swift`, `AppDelegate.swift`
  - Layout on the 1920×1080 canvas: background gradient. Clock top-right (`TimelineView(.everyMinute)`, `.title2`, secondary color, short time style). Tile rows start ~45% down the screen (the top area is reserved for the M7 top shelf).
  - Tile: rounded rect with a subtle material/gray fill and the icon (60% of tile height) or SF Symbol. Focused: `scaleEffect(1.1)`, shadow, white 2pt inner highlight stroke at 30% opacity, title label fades in below. Not installed: 40% opacity + "Not installed" caption.
  - Mouse: `.onHover { if $0 { focus = index } }`, `.onTapGesture { activate(index) }`.
  - Replace the black hosting view with `HomeView`.
  - Done when: arrows move focus with the spring animation. Hover moves focus.

- [x] **9. Router, activation, placeholder, exit**: `Launcher/AppRouter.swift`, `Launcher/PlaceholderView.swift`, `AppDelegate.swift`
  - `AppRouter.handle(_ command:) -> Bool`: on `.home`, directions/select go to the focus model and activation. `.back` is consumed and does nothing on home. On `.placeholder`, `.back`/`.home` return to `.home` (restoring the previous focus position).
  - Activation by kind: `.application`/`.url` → `AppLauncher.launch`. `.internalDestination` → `.placeholder(item)`. `.system(.exitToDesktop)` → `KioskWindowController.exitToDesktop()`.
  - Placeholder: centered SF Symbol, item title, "Coming soon", hint "Press Back to return".
  - Set `inputRouter.handler = router.handle`.
  - Done when: the manual verification checklist below passes.

- [x] **10. Wrap-up**: `docs/plans/MASTER_PLAN.md`, this file
  - Tick steps, set M1 status to `Done` in the master table, and note any deviations.

## Tests

- New: `KeyBindingsTests`, `LaunchItemStoreTests`, `LauncherFocusModelTests` (Swift Testing, `@testable import MMTVL`).
- Run all: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`
- Run one: append `-only-testing:'MMTVLTests/LauncherFocusModelTests/<testName>()'`

## Manual verification

On the dev Mac (kiosk mode, i.e. without `-windowed`):
- [ ] Launch: full screen, no Dock/menu bar, clock correct, first tile focused.
- [ ] Arrows move focus with animation. Focus can't leave the grid. Down/up between rows clamps the column.
- [ ] Return on Safari launches Safari. Quitting Safari (⌘Q) returns to the launcher with Dock/menu bar hidden.
- [ ] Launch Safari, ⌘Tab to Finder, quit Safari → launcher does **not** steal focus (L5).
- [ ] YouTube / Live TV → placeholder. Esc returns to home with focus on the same tile.
- [ ] Not-installed tile (e.g. Plex on the dev Mac) is dimmed and does nothing harmful.
- [ ] Exit to Desktop → desktop with Dock/menu bar. Clicking the Dock icon → launcher back, full screen.
- [ ] ⌘Q quits the app. ⌘Tab works at all times.
- [ ] Change display resolution in System Settings → launcher re-fits.
- [ ] Hover moves focus. Click launches.

On the Mac mini / TV (when available):
- [ ] Verify bundle IDs for Plex HTPC and Prime Video and fix the defaults if wrong.
- [ ] Text and tiles are legible from the couch at 4K (HiDPI 1920×1080) and with the AVR in the chain.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Borderless window doesn't cover the notch area / menu-bar strip on some displays | Gap at top | Use `screen.frame` (not `visibleFrame`). If still gapped, set `level = .mainMenu + 1` while active and drop to `.normal` on resign-active. |
| Presentation options exception | Crash on launch mentioning `presentationOptions` | Ensure `.hideMenuBar` is always paired with `.hideDock`. Set them after the window is shown. |
| Local key monitor misses keys when no view is first responder | Arrows beep, nothing moves | Make `KioskWindow` key, and set `initialFirstResponder`/`makeFirstResponder` to the hosting view. |
| `scaleEffect` canvas blurs text | Soft text at 4K | Switch to multiplying tokens by the scale factor instead of `scaleEffect`. |

## Deviations & questions

- **2026-10-05, step 2:** Added the `-windowed YES` Run argument (unchecked) to the shared scheme here, per L3. No step named a file for it.
- **2026-10-05, steps 8/9:** `HomeView` needs the router's focus/items state, so the "replace the black hosting view" wiring landed with step 9. Added `LauncherRootView` (the 1920×1080 canvas + `scaleEffect` + screen switch) at the bottom of `Launcher/AppRouter.swift`. The files table had no root view.
- **2026-10-05, step 7:** `LauncherFocusModel` also has `init(rows:)`, `index` (flat index) and `focus(index:)`, which mouse hover/click need. `Position` is a small `Equatable` struct, as the plan suggests.
- **2026-10-05, step 5 (L5):** Return-to-launcher also accepts `frontmostApplication` being the app that just terminated, in case frontmost is still stale when the notification arrives. Otherwise it follows the plan: nil or us → reactivate, anything else → stay put.
- **2026-10-05, step 9:** Command handling the plan left open: on home, `.home` is consumed (no-op) and `.playPause` passes through. On the placeholder, everything other than back/home passes through.
- **2026-10-05, step 6:** Extra Theme tokens: fonts (`clockFont` = `.title2` as planned, tile title/caption, symbol size), `rowsTopFraction`, `unavailableOpacity`, `shakeDistance`, `tileFill`, text colors.
- **2026-10-05, test hosting:** Tests are hosted in the app, so `xcodebuild test` used to launch MMTVL in kiosk mode and take over the screen. With the user's OK, `AppDelegate` now skips building the window and input wiring when `AppEnvironment.isRunningTests` is true (`XCTestConfigurationFilePath` is set).
- **2026-10-05, verification notes:** Automated in windowed mode on the dev Mac (keys sent via System Events, results read from the unified log). Verified: arrows/Return/Esc reach `AppRouter`. Safari launches, and quitting it returns MMTVL to the front. Launch Safari → Finder → quit Safari leaves Finder frontmost (L5). Exit to Desktop hides the app, and reopening shows it again. A home screen render through `NSHostingView` matched the design. Kiosk-mode checks (Dock/menu bar hiding, animation feel, resolution change, hover/click) still need a human.
