# M2b — Settings screen

| | |
|---|---|
| Status | Planned |
| Depends on | M2 |
| Master plan decisions used | D1, D2, D3, D4, D10, D15, D16, D17, D19 |
| Planned | 2026-10-05 |

## Goal

From the couch, with only the remote:

- Pressing **Up** from the top row of tiles focuses a **gear** next to the clock. Select opens **Settings**. A regular **Settings tile** exists too and can be hidden or removed (the gear always stays, so you can't lock yourself out).
- Settings looks like tvOS Settings: a page title, a large image on the left, and a list of rows on the right. Up/Down moves, Select changes or opens a row, Back goes up a level and then home.
- **Remote & Input:** Global Home & Media Keys, Game Controllers, and Hide Pointer During Remote Use toggle **live**, with no relaunch.
- **Permissions:** shows whether Accessibility is allowed. Select opens the system prompt and the Privacy pane. When access is granted, MMTVL comes back to the front and the status updates.
- **Startup:** Launch at Login toggles live. If macOS needs approval, a row opens the Login Items settings.
- **Home Screen:** reorder tiles, hide or show them, turn Open Full Screen on or off per app, remove tiles, re-add removed default tiles, **add a tile for any installed app** (picked from a list with icons), and restore the defaults (after a confirmation).
- **System:** Relaunch MMTVL and Exit to Desktop.
- Every change is written to `settings.json` / `launch-items.json` at once. There is no Save button.

## Out of scope

- A Settings PIN or parental lock. It comes with the YouTube/IPTV profile work (**M3/M4**), per the user on 2026-10-05.
- The learn-button key-bindings editor. `key-bindings.json` stays hand-edited (**M7**, D16).
- Website (URL) tiles and renaming tiles, which need text entry. Phone text entry arrives in **M5**; until then, hand-edit `launch-items.json`.
- YouTube and IPTV settings sections (**M3**, **M4**). They add pages and rows to this framework.
- Parallax and visual polish (**M7**).
- Per-tile custom artwork.

## Research & findings

- **Relaunch helper (verified locally, 2026-10-05):** a `Process` running `/bin/sh -c '<script>' sh <pid> <args…>` keeps running after the parent process exits. The script polled `kill -0 <pid>` until the parent was gone, then ran, and it got the forwarded arguments (`-windowed YES`) intact. This was tested with a command-line Swift binary that called `exit(0)`. **Unverified for an AppKit app quitting through `NSApp.terminate`.** That path also ends in `exit()` and macOS doesn't kill child processes when the parent exits, so it should behave the same. It is checked in step 5.
- **Listing apps (verified on the dev Mac):**
  - `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` on `/Applications` returns the `.app` bundles, including Safari.
  - `/System/Applications` holds the Apple apps, with a `Utilities` subfolder.
  - `~/Applications` holds folders such as `Brave Browser Apps.localized` (web-app shims), so scanning one level into non-`.app` folders is useful.
  - `Bundle(url:)?.bundleIdentifier` works on real apps and on a fake `Foo.app/Contents/Info.plist`, so tests can build fixture bundles.
  - `FileManager.default.displayName(atPath:)` returned `"Calendar.app"` *with* the extension in a non-GUI process. Strip a trailing `.app`.
- **Login Items pane:** `SMAppService.openSystemSettingsLoginItems()` is a class method, macOS 13+ (`ServiceManagement/SMAppService.h`; [Apple docs](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems())). `SMAppService.mainApp.status` gives `.enabled / .requiresApproval / .notRegistered / .notFound` (see M2 research).
- **Refreshing Accessibility status:** you can't observe `AXIsProcessTrusted()` for changes. After the user grants access in System Settings, they come back to MMTVL, either through the existing M2 wait task, which calls `windowController.show()`, or with Home or ⌘Tab. So re-reading the status in `NSApplicationDelegate.applicationDidBecomeActive(_:)` and whenever Settings opens is enough. No polling is needed.
- **Game controller handlers stay attached** after `ControllerInput.stop()`. The current `stop()` (code reading, `Input/ControllerInput.swift`) only removes the connect/disconnect observers. The `pressedChangedHandler` and `valueChangedHandler` closures stay on each `GCController`'s elements and keep dispatching. Turning controllers off live therefore has to set those handlers to `nil`.
- **The event tap can be stopped and restarted:** `GlobalEventTap.stop()` invalidates the port and sets it to nil, and `start()` creates a new tap when `port == nil` (code reading). Turning global input off and on needs no new tap code.
- **SwiftUI scrolling (SDK check, Xcode 27):** `ScrollViewReader` / `proxy.scrollTo(_:anchor:)`, `scrollPosition(id:anchor:)` and `scrollClipDisabled(_:)` are all present in the macOS SDK. The plan uses `ScrollViewReader`, the simplest of these with explicit control. `scaleEffect` on the root canvas (M1) only changes rendering, so the list lays out in 1920×1080 canvas points.
- **Swift 6:** `nonisolated extension` (SE-0449, Swift 6.1+) marks every member of an extension `nonisolated`. If the compiler rejects it, mark each member `nonisolated` instead.

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL/Launcher/LaunchItem.swift` | changed | `isHidden: Bool?`, `isVisible`, `supportsFullScreen`, `kindDescription`; a default Settings tile. |
| `MMTVL/Launcher/LaunchItem+Editing.swift` | new | Pure `[LaunchItem]` edit helpers (move, hide, full screen, remove, insert, missing defaults). |
| `MMTVL/Launcher/HomeFocusModel.swift` | new | Pure focus over gear + tile grid. Wraps `LauncherFocusModel`. |
| `MMTVL/Launcher/GearButtonView.swift` | new | The gear next to the clock. |
| `MMTVL/Launcher/HomeView.swift` | changed | Gear + clock header, `HomeFocusModel`, empty-home hint. |
| `MMTVL/Launcher/AppRouter.swift` | changed | Mutable items + visible items, `HomeFocusModel`, `.settings` screen, `openSettings()`, `setItems(_:)`, gear/row hover. |
| `MMTVL/Launcher/AppLauncher.swift` | changed | `icon(forApplicationAt:)` (shares the icon cache). |
| `MMTVL/Launcher/InstalledApps.swift` | new | Scans the Applications folders for app bundles. |
| `MMTVL/Input/ControllerInput.swift` | changed | `stop()` detaches element handlers and background monitoring. |
| `MMTVL/App/KioskWindowController.swift` | changed | `hidesCursor` becomes `var`. |
| `MMTVL/App/LoginItem.swift` | changed | `LoginItemStatus`, `status`, `openSystemSettings()`. |
| `MMTVL/App/AppRelauncher.swift` | new | Relaunch MMTVL through a `/bin/sh` helper. |
| `MMTVL/App/AppDelegate.swift` | changed | Live `applySettings`, `applyItems`, `requestAccessibility`, wait-task refactor, Settings wiring, `applicationDidBecomeActive`. |
| `MMTVL/Settings/SettingsTypes.swift` | new | `SettingsPage`, `SettingKey`, `SettingsAction`, `RowImage`, `SettingsRow`, `SettingsSection`, `ListFocus`. |
| `MMTVL/Settings/SettingsEnvironment.swift` | new | Side-effect closures injected into the model (live apply, permissions, relaunch…). |
| `MMTVL/Settings/SettingsModel.swift` | new | Navigation stack, focus, command handling, `perform(_:)`. |
| `MMTVL/Settings/SettingsModel+Pages.swift` | new | Builds the sections/rows for each page. |
| `MMTVL/Settings/SettingsView.swift` | new | Page layout (title, side image, scrolling list, hint). |
| `MMTVL/Settings/SettingsRowView.swift` | new | One row, plus `RowImageView`. |
| `MMTVL/DesignSystem/Theme.swift` | changed | Gear and Settings tokens. |
| `MMTVLTests/…` | new | See *Tests*. |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | changed | Wrap-up. |

`MMTVL/Settings/` is a new folder. File-system-synchronized groups pick it up automatically, so don't touch `project.pbxproj`.

### Key types

```swift
// Launcher/LaunchItem.swift (additions)
var isHidden: Bool?            // nil/false = shown. Optional so older files decode; stored as nil when shown.
var isVisible: Bool { isHidden != true }
/// Kinds whose window AppLauncher can make full screen (D15).
var supportsFullScreen: Bool   // true for .application and .defaultBrowser only
/// Second line in the tile list: "App", "Default browser", "Built in", "System", or the URL's host.
var kindDescription: String
```
- Add `isHidden` **after** `launchFullScreen`, so the synthesized memberwise init keeps working for the existing defaults.
- New default, inserted before `exit`: `LaunchItem(id: "settings", title: "Settings", kind: .internalDestination(.settings), iconSymbol: "gearshape.fill")`.
- Existing installs keep their `launch-items.json` and get this tile through Add Tile → MMTVL (L9).

```swift
// Launcher/LaunchItem+Editing.swift: every function returns a new array; unknown ids return self unchanged.
nonisolated extension Array where Element == LaunchItem {
    var visible: [LaunchItem] { filter(\.isVisible) }
    func movingItem(id: String, by offset: Int) -> [LaunchItem]      // target index clamped to bounds
    func settingHidden(_ hidden: Bool, id: String) -> [LaunchItem]   // stores `hidden ? true : nil`
    func settingFullScreen(_ fullScreen: Bool, id: String) -> [LaunchItem]  // sets launchFullScreen explicitly
    func removingItem(id: String) -> [LaunchItem]
    func insertingTile(_ item: LaunchItem) -> [LaunchItem]           // before the first `.system` item, else at the end
    var missingDefaults: [LaunchItem]                                // LaunchItem.defaults whose id isn't present, default order
    var applicationBundleIDs: Set<String>                            // bundle IDs of `.application` items
}
```

```swift
// Launcher/HomeFocusModel.swift
/// Focus on the home screen (D2): the tile grid plus the gear by the clock, which sits "above" the top row.
nonisolated struct HomeFocusModel: Equatable, Sendable {
    private(set) var tiles: LauncherFocusModel
    private(set) var isGearFocused: Bool
    init(tileCount: Int, perRow: Int)          // isGearFocused = (tileCount == 0)
    var tileIndex: Int? { isGearFocused ? nil : tiles.index }
    /// Tiles: directions move inside the grid. Up on the top row (tiles.move(.up) == false) focuses the gear → true.
    /// Gear: .down leaves the gear (back to the same tile) if there are tiles → true; every other direction → false.
    /// Non-directional commands → false.
    @discardableResult mutating func move(_ command: RemoteCommand) -> Bool
    /// Focuses a tile (also leaves the gear). False if the index is out of range or nothing changed.
    @discardableResult mutating func focusTile(index: Int) -> Bool
    @discardableResult mutating func focusGear() -> Bool        // false if already focused
    @discardableResult mutating func leaveGear() -> Bool        // false if not focused or there are no tiles
}
```

```swift
// Launcher/InstalledApps.swift
nonisolated struct InstalledApp: Hashable, Sendable, Identifiable {
    let bundleID: String
    let name: String       // display name without ".app"
    let url: URL
    var id: String { bundleID }
}
nonisolated enum InstalledApps {
    /// /Applications, /System/Applications, ~/Applications.
    static var defaultDirectories: [URL]
    /// Scans each directory, plus one level into non-.app subfolders (Utilities, "Brave Browser Apps.localized").
    /// Skips hidden files, unreadable/missing directories and bundles without a bundle ID.
    /// Dedupe by bundle ID (first directory wins); sort by name with localizedStandardCompare.
    static func scan(directories: [URL] = defaultDirectories, excludingBundleIDs: Set<String> = []) -> [InstalledApp]
    /// `scan` on a detached task (it reads ~100 Info.plists).
    static func scanInBackground(excludingBundleIDs: Set<String>) async -> [InstalledApp]
}
```
- Treat an entry as an app when `url.pathExtension.lowercased() == "app"`, whatever `isDirectoryKey` says (app entries can be symlinks).
- Only for other entries, check `resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true` and scan their children (depth 1, no deeper).
- Name: `FileManager.default.displayName(atPath: url.path)`, then drop a trailing `.app` (case-insensitive).
- Don't touch `Bundle.main` inside `scan`. The caller passes MMTVL's own bundle ID in `excludingBundleIDs`.

```swift
// App/LoginItem.swift (additions)
nonisolated enum LoginItemStatus: Sendable { case enabled, requiresApproval, notRegistered, notFound }
static var status: LoginItemStatus { … map SMAppService.mainApp.status; @unknown default → .notFound }
static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
```

```swift
// App/AppRelauncher.swift
enum AppRelauncher {
    /// Waits up to 10 s for `$1` (our PID) to exit, then reopens `$2` as a new instance with the remaining args.
    /// Exits without relaunching if the old process is still alive (avoids two kiosk instances / two event taps).
    nonisolated static let script = """
        i=0
        while /bin/kill -0 "$1" 2>/dev/null; do
          i=$((i+1)); [ "$i" -gt 50 ] && exit 1
          /bin/sleep 0.2
        done
        app="$2"; shift 2
        if [ "$#" -gt 0 ]; then exec /usr/bin/open -n "$app" --args "$@"; else exec /usr/bin/open -n "$app"; fi
        """
    nonisolated static func processArguments(pid: Int32, appPath: String, arguments: [String]) -> [String] {
        ["-c", script, "sh", String(pid), appPath] + arguments
    }
    /// Spawns /bin/sh with processArguments(pid: own PID, appPath: Bundle.main.bundleURL.path,
    /// arguments: Array(ProcessInfo.processInfo.arguments.dropFirst())), then NSApp.terminate(nil).
    /// If process.run() throws: log the error and don't terminate.
    static func relaunch()
}
```
- Forwarding the arguments keeps `-windowed YES` in windowed mode.
- `$((…))` in a Swift string literal is fine. Only `\(` interpolates.

```swift
// Settings/SettingsTypes.swift
nonisolated enum SettingsPage: Hashable, Sendable {
    case root, homeScreen, tile(id: String), addTile, confirmRestoreDefaults
}

nonisolated enum SettingKey: String, CaseIterable, Sendable {
    case globalInputEnabled, controllersEnabled, cursorAutoHide, launchAtLogin
    var keyPath: WritableKeyPath<AppSettings, Bool> { switch self { case .globalInputEnabled: \.globalInputEnabled … } }
}

/// What Select does on a row. Data, not closures, so pages are Equatable and testable.
nonisolated enum SettingsAction: Hashable, Sendable {
    case toggle(SettingKey)
    case requestAccessibility
    case openLoginItemsSettings
    case push(SettingsPage)
    case relaunch
    case exitToDesktop
    case toggleTileVisible(id: String)
    case toggleTileFullScreen(id: String)
    case startMove(id: String)
    case removeTile(id: String)
    case addDefaultTile(id: String)
    case addApp(InstalledApp)
    case restoreDefaults
    case pop
}

nonisolated enum RowImage: Hashable, Sendable {
    case symbol(String)     // SF Symbol
    case item(LaunchItem)   // app icon via AppLauncher.icon(for:), else item.iconSymbol, else "app.dashed"
    case app(URL)           // AppLauncher.icon(forApplicationAt:)
}

nonisolated struct SettingsRow: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var value: String? = nil          // right-aligned: "On", "Off", "Allowed", "Hidden"…
    var detail: String? = nil         // second line, smaller
    var image: RowImage? = nil        // leading icon
    var showsDisclosure = false       // trailing chevron.right
    var isDimmed = false              // hidden tiles
    var isLifted = false              // the tile being moved
    var needsRelaunch = false         // D19 badge "Relaunch needed"; no M2b row sets it (L3)
    var action: SettingsAction? = nil // nil = info row: shown, never focused
}

nonisolated struct SettingsSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String? = nil
    var rows: [SettingsRow]
    var footer: String? = nil
}

/// Vertical list focus by row id (ids are stable when rows appear/disappear or move).
nonisolated enum ListFocus {
    /// `current` if it's in `ids`, else the first id, else nil.
    static func resolve(ids: [String], current: String?) -> String?
    /// The id `step` positions from the resolved current one, clamped to the ends.
    static func move(ids: [String], current: String?, by step: Int) -> String?
}
```

```swift
// Settings/SettingsEnvironment.swift: everything with side effects; tests pass fakes.
struct SettingsEnvironment {
    var isKiosk: Bool
    var versionString: String
    var applySettings: (AppSettings) -> Void          // apply live + save settings.json
    var applyItems: ([LaunchItem]) -> Void            // router.setItems + save launch-items.json
    var isAccessibilityTrusted: () -> Bool
    var requestAccessibility: () -> Void
    var loginItemStatus: () -> LoginItemStatus
    var openLoginItemsSettings: () -> Void
    var scanInstalledApps: () async -> [InstalledApp]
    var relaunch: () -> Void
    var exitToDesktop: () -> Void
    var tileTitle: (LaunchItem) -> String             // AppLauncher.title(for:)
    var isInstalled: (LaunchItem) -> Bool             // AppLauncher.isInstalled(_:)
}
```

```swift
// Settings/SettingsModel.swift
@Observable
final class SettingsModel {
    struct PageState: Equatable { var page: SettingsPage; var focusedRowID: String? }

    private(set) var settings: AppSettings
    private(set) var items: [LaunchItem]                 // all tiles, stored order (hidden included)
    private(set) var stack: [PageState] = [PageState(page: .root, focusedRowID: nil)]   // never empty
    private(set) var movingTileID: String?               // move mode on the homeScreen page
    private(set) var isAccessibilityTrusted: Bool
    private(set) var loginItemStatus: LoginItemStatus
    private(set) var installedApps: [InstalledApp]?      // nil = loading (addTile page)
    @ObservationIgnored let environment: SettingsEnvironment

    init(settings: AppSettings, items: [LaunchItem], environment: SettingsEnvironment)
        // reads isAccessibilityTrusted / loginItemStatus from the environment

    var page: SettingsPage { stack[stack.count - 1].page }
    var sections: [SettingsSection]          // built for `page` (SettingsModel+Pages.swift)
    var focusableRowIDs: [String]            // rows with a non-nil action, in display order
    var focusedRowID: String?                // ListFocus.resolve(ids: focusableRowIDs, current: stack.last.focusedRowID)
    var pageTitle: String
    var pageImage: RowImage
    var hint: String

    func reset()                             // stack = [root], movingTileID = nil, refreshStatus()
    func refreshStatus()                     // re-read accessibility + login item status
    /// Returns false only for commands it doesn't use, and for Back on the root page (the router then goes home).
    func handle(_ command: RemoteCommand) -> Bool
    func focus(rowID: String)                // mouse hover: sets the top page's focusedRowID if focusable
    func activate(rowID: String)             // mouse click: ends move mode if active; else focus + perform its action
    func perform(_ action: SettingsAction)
    func loadInstalledApps() async           // installedApps = await environment.scanInstalledApps()
}
```

`handle(_:)` rules:

| Command | Move mode (homeScreen, `movingTileID != nil`) | Otherwise |
|---|---|---|
| `.up` / `.down` | Move the tile by −1/+1 (`updateItems(items.movingItem(id:by:))`). Focus stays on `"tile.<id>"`. → true | Store `ListFocus.move(… by: ∓1)` in the top `PageState`. → true |
| `.left` / `.right` | → true (no-op) | → true (no-op, L13) |
| `.select` | `movingTileID = nil` → true | Perform the focused row's action, if any. → true |
| `.back` | `movingTileID = nil` → true | `stack.count > 1` ? pop → true : **false** |
| `.home`, `.playPause`, `.fastForward`, `.rewind` | → false | → false |

`perform(_:)` rules:
- `.toggle(key)`: `var s = settings; s[keyPath: key.keyPath].toggle(); settings = s; environment.applySettings(s); refreshStatus()`.
- `.requestAccessibility` → `environment.requestAccessibility()`. `.openLoginItemsSettings`, `.relaunch` and `.exitToDesktop` call their closures.
- `.push(page)`: append `PageState(page: page, focusedRowID: nil)`. For `.addTile`, also set `installedApps = nil` and `Task { await loadInstalledApps() }`.
- `.pop`: pop if `stack.count > 1`.
- `.toggleTileVisible(id)` / `.toggleTileFullScreen(id)`: `updateItems(items.settingHidden(!item.isHidden…))` / `settingFullScreen(!item.wantsFullScreen, id:)`.
- `.startMove(id)`: pop to the homeScreen page, `movingTileID = id`, top focus = `"tile.<id>"`.
- `.removeTile(id)`: the neighbor is the item after it, else the item before it. `updateItems(items.removingItem(id:))`, pop, top focus = `"tile.<neighbor>"` (or nil).
- `.addDefaultTile(id)` / `.addApp(app)`: build the item, `updateItems(items.insertingTile(item))`, pop, top focus = `"tile.<newID>"`.
  - A default tile is the `LaunchItem.defaults` entry with that id.
  - An app tile is `LaunchItem(id: "app.\(app.bundleID)", title: app.name, kind: .application(bundleID: app.bundleID))`.
- `.restoreDefaults`: `updateItems(LaunchItem.defaults)`, pop.
- `private func updateItems(_ new: [LaunchItem])`: `items = new; environment.applyItems(new)`.

### Pages (SettingsModel+Pages.swift)

Row ids are stable strings. Values for toggles are `"On"` / `"Off"`.

**`.root`**: title "Settings", image `.symbol("gearshape")`, hint "Select: choose · Back: return"
- Section `input`, "Remote & Input":
  - `globalInput` "Global Home & Media Keys" → `.toggle(.globalInputEnabled)`. Detail:
    - not kiosk → "Applies in kiosk mode only"
    - else if on and not trusted → "Needs Accessibility access"
    - else nil
  - `controllers` "Game Controllers" → `.toggle(.controllersEnabled)`
  - `cursorAutoHide` "Hide Pointer During Remote Use" → `.toggle(.cursorAutoHide)`
- Section `permissions`, "Permissions":
  - `accessibility` "Accessibility". Value "Allowed" / "Not Allowed". Detail "Needed for Home in other apps, media keys and full-screen apps". Action `.requestAccessibility`.
- Section `startup`, "Startup":
  - `launchAtLogin` "Launch at Login" → `.toggle(.launchAtLogin)`. Detail:
    - not kiosk → "Applies in kiosk mode only"
    - else if on and status `.requiresApproval` → "Waiting for approval in System Settings → General → Login Items"
    - else nil
  - `approveLoginItem` "Open Login Items Settings" → `.openLoginItemsSettings`. **Only shown** when kiosk && launchAtLogin && status == `.requiresApproval`.
- Section `home`, "Home Screen":
  - `editHome` "Edit Home Screen", disclosure → `.push(.homeScreen)`
- Section `system`, "System", footer "MMTVL \(versionString) · Saved in ~/Library/Application Support/MMTVL":
  - `relaunch` "Relaunch MMTVL" → `.relaunch`
  - `exit` "Exit to Desktop" → `.exitToDesktop`

**`.homeScreen`**: title "Home Screen", image `.symbol("square.grid.2x2")`. Hint:
- in move mode: "Up/Down: move · Select or Back: done"
- otherwise: "Select: edit tile · Back: return"

Rows:
- Section `tiles`, "Tiles", footer "Hidden tiles stay here but don't show on the Home screen."
  - One row per item, **all** items in stored order. Id `"tile.<item.id>"`, title `environment.tileTitle(item)`, image `.item(item)`, disclosure.
  - Value "Hidden" if hidden. Detail: `item.kindDescription`, plus " · Not installed" when `!environment.isInstalled(item)`.
  - `isDimmed: !item.isVisible`, `isLifted: movingTileID == item.id`. Action `.push(.tile(id: item.id))`.
- Section `manage` (no title):
  - `addTile` "Add Tile", disclosure → `.push(.addTile)`
  - `restoreDefaults` "Restore Default Tiles", disclosure → `.push(.confirmRestoreDefaults)`

**`.tile(id)`**: title = `tileTitle(item)`, image `.item(item)`, hint "Select: choose · Back: return". If the item is missing: no sections, title "Tile".
- Section `options`:
  - `tile.visible` "Show on Home Screen" → `.toggleTileVisible`
  - `tile.fullScreen` "Open Full Screen" → `.toggleTileFullScreen`. **Only when** `item.supportsFullScreen`. Value from `item.wantsFullScreen`. Detail "Needs Accessibility access" when not trusted.
  - `tile.move` "Move" → `.startMove`
  - `tile.remove` "Remove from Home Screen" → `.removeTile`. Detail for default ids: "You can add it back from Add Tile".

**`.addTile`**: title "Add Tile", image `.symbol("plus.app")`, hint "Select: add · Back: return"
- Section `builtIn`, "MMTVL" (only if `items.missingDefaults` is non-empty): `"add.default.<id>"` rows with title `tileTitle(item)`, image `.item(item)`, action `.addDefaultTile(id:)`.
- Section `apps`, "Applications":
  - `installedApps == nil` → info row `apps.loading` "Loading…" (no action).
  - Otherwise, apps whose bundle ID is not in `items.applicationBundleIDs` ∪ `items.missingDefaults.applicationBundleIDs`.
    - Each app is a row `"add.app.<bundleID>"` with title `app.name`, image `.app(app.url)`, action `.addApp(app)`.
    - If none are left: info row `apps.none` "No other apps found".

**`.confirmRestoreDefaults`**: title "Restore Default Tiles?", image `.symbol("arrow.counterclockwise")`, hint "Select: choose · Back: cancel"
- Section `confirm`, footer "Replaces every tile with the defaults. Added apps, hidden tiles and the order are reset.":
  - `confirm.cancel` "Cancel" → `.pop` (**first**, so it's focused by default)
  - `confirm.restore` "Restore Defaults" → `.restoreDefaults`

### Router and home screen

```swift
// Launcher/AppRouter.swift (changes)
enum Screen: Equatable { case home, placeholder(LaunchItem), accessibilityOnboarding, settings }
private(set) var items: [LaunchItem]          // all, stored order
private(set) var visibleItems: [LaunchItem]   // items.visible; HomeView and activate(_:) use these
private(set) var focus: HomeFocusModel        // replaces LauncherFocusModel
let settings: SettingsModel                   // added in step 8
init(items: [LaunchItem], launcher: AppLauncher, settings: SettingsModel)
func openSettings()                           // settings.reset(); screen = .settings
func setItems(_ items: [LaunchItem])          // see below
func hoverGear()                              // guarded (L8) → focus.focusGear()
func activateGear()                           // openSettings()
func hoverSettingsRow(_ id: String)           // guarded (L8) → settings.focus(rowID:)
```
- `.home` routing:
  - Directions → `withAnimation(Theme.focusAnimation) { _ = focus.move(command) }`; return true.
  - `.select` → gear focused ? `openSettings()` : `activate(tileIndex)`; return true.
  - `.back` → `focus.leaveGear()` (animated); return true.
  - `.home` → true. Media commands → false.
- `.settings` routing:
  - `.home` → `goHome()`; true.
  - Else if `settings.handle(command)` → true.
  - Else if `.back` → `goHome()`; true.
  - Else false.
- `activate(_:)`: `.internalDestination(.settings)` → `openSettings()`. Other internal destinations still show the placeholder.
- Hover guard (M2 L8): factor out `private var pointerMovedSinceLastCommand: Bool { NSEvent.mouseLocation != pointerLocationAtLastCommand }`. Use it in `hover(_:)`, `hoverGear()` and `hoverSettingsRow(_:)`. This matters more now: keyboard scrolling moves rows under a parked pointer.
- `setItems(_:)`:
  1. Remember the focused visible item's id, the old tile index, and whether the gear was focused.
  2. Set `items` and `visibleItems`. Build `HomeFocusModel(tileCount: visibleItems.count, perRow: Theme.tilesPerRow)`.
  3. Restore focus: the gear if it was focused; else the same item id if it's still visible; else `min(oldIndex, count − 1)`.

`HomeView` header: an `HStack(spacing: 32) { GearButtonView(isFocused:); clock }`, top-right where the clock is now. `GearButtonView` is a circle of `Theme.gearButtonSize` showing `gearshape.fill` at `Theme.gearSymbolSize`:
- Unfocused: `secondaryText`, no fill.
- Focused: `tileFill` fill, `focusHighlight` stroke, `focusScale`, focus shadow, and `primaryText`. These are the same visuals as the tiles.
- `.onHover` → `onHoverGear`; `.onTapGesture` → `onActivateGear`.

When there are no visible tiles, show a centered `secondaryText` hint where the rows would be: "No tiles. Select the gear to open Settings."

### Live apply (AppDelegate)

```swift
private var settingsFile: JSONConfigFile<AppSettings>!     // set first thing in didFinishLaunching
private var accessibilityWaitTask: Task<Void, Never>?

private func applySettings(_ new: AppSettings) {
    let old = settings; settings = new
    do { try settingsFile.save(new) } catch { log error }   // UI keeps the new value regardless
    let kiosk = !AppEnvironment.windowedMode
    if kiosk && new.globalInputEnabled != old.globalInputEnabled {
        new.globalInputEnabled ? startGlobalInput(showOnboarding: false) : eventTap?.stop()
    }
    if new.controllersEnabled != old.controllersEnabled {
        if new.controllersEnabled { startControllers() } else { controllers?.stop(); controllers = nil }
    }
    windowController?.hidesCursor = new.cursorAutoHide
    if kiosk && new.launchAtLogin != old.launchAtLogin { LoginItem.apply(enabled: new.launchAtLogin) }
}

private func applyItems(_ items: [LaunchItem]) {
    router?.setItems(items)
    do { try LaunchItemStore().save(items) } catch { log error }
}

private func startControllers()       // ControllerInput(inputRouter:, monitorInBackground: kiosk).start(); keep it
private func startGlobalInput(showOnboarding: Bool) {
    let tap = eventTap ?? GlobalEventTap(inputRouter: inputRouter); eventTap = tap
    if tap.start() { return }
    if showOnboarding { router.showAccessibilityOnboarding() }
    startAccessibilityWait()
}
private func requestAccessibility() { AccessibilityPermission.request(); startAccessibilityWait() }
/// Idempotent. When trust arrives: start the tap if kiosk && globalInputEnabled, leave onboarding,
/// refresh Settings, and bring the launcher back from System Settings.
private func startAccessibilityWait() {
    guard accessibilityWaitTask == nil, !AccessibilityPermission.isTrusted else { return }
    accessibilityWaitTask = Task { [weak self] in
        await AccessibilityPermission.waitUntilTrusted()
        guard let self, AccessibilityPermission.isTrusted else { return }
        accessibilityWaitTask = nil
        if !AppEnvironment.windowedMode && settings.globalInputEnabled { eventTap?.start() ?? startGlobalInput(showOnboarding: false) }
        if router?.screen == .accessibilityOnboarding { router?.goHome() }
        router?.settings.refreshStatus()
        windowController?.show()
    }
}
func applicationDidBecomeActive(_ notification: Notification) { router?.settings.refreshStatus() }
```
- `onCommandDispatched` must read the current value, `{ [weak self] in if self?.settings.cursorAutoHide == true { NSCursor.setHiddenUntilMouseMoves(true) } }`, instead of the value captured at launch.
- `router.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }`.
- `startAccessibilityWait()` also runs in windowed mode, so granting from Settings still brings MMTVL back. It starts the tap only in kiosk mode (M2 L2).
- The `eventTap?.start() ?? …` line is shorthand. Write it as plain `if let`, and create the tap if it doesn't exist yet.

### Local decisions

- **L1:** No Settings PIN in M2b (user, 2026-10-05). It comes with the M3/M4 profile protection, and secrets go in the Keychain (D9).
- **L2:** Settings can add a tile for **any installed app** (user, 2026-10-05). Apps come from a scan of `/Applications`, `/System/Applications` and `~/Applications`, one level deep. New tiles are inserted before the first system tile (Exit to Desktop). URL tiles and renaming need text entry (M5).
- **L3:** All four `settings.json` keys apply live. The D19 "Relaunch needed" badge (`SettingsRow.needsRelaunch`) exists for M3/M4 rows but no M2b row sets it. The Relaunch MMTVL row is always present, which is also handy after hand-editing `key-bindings.json`.
- **L4:** Pages are data. Sections, rows and `SettingsAction` enums are built from the model state, and `perform(_:)` interprets them. This keeps the model unit-testable and lets later milestones add pages and rows without new UI plumbing.
- **L5:** The gear is focused by pressing Up on the top tile row, and Down returns to the same tile. It's always visible, and it's auto-focused when there are no visible tiles. This guarantees Settings can be reached even with every tile hidden or removed.
- **L6:** Any tile can be hidden or removed, including Settings and Exit to Desktop. Removed default tiles can be re-added from Add Tile → MMTVL. Restore Default Tiles asks for confirmation, with Cancel focused.
- **L7:** Every change is saved at once. A hand edit made while MMTVL runs gets overwritten by the next Settings change, so edit the JSON with MMTVL quit.
- **L8:** In `-windowed` mode, kiosk-only rows (global input, launch at login) still toggle and save, but aren't applied, and their detail line says so.
- **L9:** The Settings tile is a new default (before Exit). Existing installs see it under Add Tile → MMTVL, and their file is never auto-merged.
- **L10:** The Accessibility and login item status are re-read when Settings opens, after each toggle, and in `applicationDidBecomeActive`. No polling.
- **L11:** Relaunch goes through a `/bin/sh` helper. It waits for our PID to exit (at most 10 s), then runs `open -n` with the same arguments. This avoids two instances with two event taps fighting over presentation options.
- **L12:** Global Home while Settings is showing goes to the home screen (M2's `handleGlobal`, unchanged).
- **L13:** Left/Right do nothing in Settings, and Select toggles. This matches tvOS Settings and keeps the D-pad mapping simple.
- **L14:** Turning global input on from Settings without Accessibility doesn't show the onboarding screen. The Accessibility row right there shows the status, and the wait task starts the tap once access is granted.
- **L15:** Turning game controllers off detaches every element handler and turns off background monitoring. Turning them on again reconfigures connected controllers through the existing connect path.

## Implementation steps

- [ ] **1. Tile model: hidden flag, Settings tile, edit helpers**: `Launcher/LaunchItem.swift`, `Launcher/LaunchItem+Editing.swift`, `MMTVLTests/LaunchItemEditingTests.swift`
  - Add `isHidden`, `isVisible`, `supportsFullScreen` and `kindDescription` (see Key types). Insert the `settings` default before `exit`.
  - Implement the `[LaunchItem]` helpers.
  - Tests (`LaunchItemEditingTests`), on a small fixture array `[a(app), b(app), c(internal), exit(system)]`:
    - `movingItem(id: "a", by: 1)` → b, a, …
    - Moving the first item by −1 or the last by +1 leaves the array unchanged.
    - An unknown id leaves it unchanged.
    - `settingHidden(true, id:)` → `isHidden == true`, `isVisible == false`. `settingHidden(false, id:)` → `isHidden == nil`.
    - `visible` drops hidden items.
    - `settingFullScreen(false, id:)` on the `prime` default → `wantsFullScreen == false`.
    - `removingItem` works.
    - `insertingTile(x)` puts x before `exit`, and appends it when there's no system item.
    - `missingDefaults` on `LaunchItem.defaults.removingItem(id: "settings")` == [settings default].
    - Old JSON without `isHidden` decodes with `isVisible == true`. Encoding a visible item emits no `isHidden` key (check the JSON string with `!contains("isHidden")`).
    - `supportsFullScreen` is true only for `.application` and `.defaultBrowser`.
    - `LaunchItem.defaults` contains `settings` right before `exit`.
  - Done when: it builds and all tests pass (the existing `LaunchItemStoreTests` and `AppLauncherTests` unchanged).

- [ ] **2. Home focus model**: `Launcher/HomeFocusModel.swift`, `MMTVLTests/HomeFocusModelTests.swift`
  - Implement as specified, delegating grid moves to `LauncherFocusModel`.
  - Tests (7 tiles, 5 per row):
    - Starts on tile 0, gear not focused.
    - Up from row 0 → gear focused, `tileIndex == nil`, returns true.
    - Down from the gear → back on the same tile (e.g. focus index 3, Up, Down → 3).
    - Left/Right/Up on the gear → false, still the gear.
    - Up from row 1 → row 0, not the gear.
    - `tileCount: 0` → gear focused, Down → false, `leaveGear()` → false.
    - `focusTile(index: 6)` from the gear → tile 6, not the gear. `focusTile(index: 99)` → false.
    - Non-directional commands → false.
  - Done when: tests pass.

- [ ] **3. Gear on the home screen; mutable tiles in the router**: `Launcher/AppRouter.swift`, `Launcher/HomeView.swift`, `Launcher/GearButtonView.swift`, `DesignSystem/Theme.swift`
  - Theme tokens (MARK: Settings): `gearButtonSize: CGFloat = 72`, `gearSymbolSize: CGFloat = 36`, `headerSpacing: CGFloat = 32`.
  - Router: `items`/`visibleItems`, `HomeFocusModel`, `setItems(_:)`, `hoverGear()`, `activateGear()`, the factored hover guard, and the new `.home` routing. Add `openSettings()` **temporarily** as `screen = .placeholder(LaunchItem.defaults.first { $0.id == "settings" }!)`. Step 8 replaces it. `activate(_:)` uses `visibleItems`, and `.internalDestination(.settings)` calls `openSettings()`.
  - Don't add the `settings` init parameter yet.
  - `HomeView`: take `items` (visible), `focus: HomeFocusModel`, `onHoverGear` and `onActivateGear`. Use `focus.tiles.rows` for `rowRanges` and `focus.tileIndex` for `isFocused`. Add the header HStack and the empty-home hint.
  - `LauncherRootView` passes `router.visibleItems` and the new closures.
  - Done when: it builds and tests pass.
    - Windowed launch: Up from the top row lights the gear, Down returns to the same tile, Select on the gear shows the "Settings — Coming soon" placeholder, and Back returns.
    - Hovering the gear focuses it, and clicking it opens the placeholder.

- [ ] **4. Live-apply plumbing**: `Input/ControllerInput.swift`, `App/KioskWindowController.swift`, `App/LoginItem.swift`, `App/AppDelegate.swift`
  - `ControllerInput.stop()`:
    - Also call `GCController.controllers().forEach(unconfigure)`. `unconfigure` sets `pressedChangedHandler = nil` on every element `configure` binds, for extended and micro gamepads alike, and `leftThumbstick.valueChangedHandler = nil`.
    - Set `GCController.shouldMonitorBackgroundEvents = false`.
    - `start()` after `stop()` must work again. `observers` is emptied, and existing controllers go through `controllerDidConnect`.
  - `KioskWindowController`: `var hidesCursor: Bool` (was `let`).
  - `LoginItem`: add `LoginItemStatus`, `status` and `openSystemSettings()`. Reuse the status mapping for `describe`.
  - `AppDelegate`: implement *Live apply* as specified:
    - Store `settingsFile`.
    - `onCommandDispatched` reads `self.settings`.
    - Add `startControllers()`, `startGlobalInput(showOnboarding:)`, `requestAccessibility()`, `startAccessibilityWait()`, `applySettings(_:)`, `applyItems(_:)` and `applicationDidBecomeActive(_:)` (the last calls nothing yet; `router.settings` doesn't exist until step 8).
    - Launch uses `startGlobalInput(showOnboarding: true)`, which keeps today's behavior, and `startControllers()`.
    - `applySettings`/`applyItems` are unused until step 8; private unused methods don't warn.
  - Done when: it builds and tests pass. Kiosk launch behaves exactly as in M2: onboarding when not trusted, fn+← from Finder works, and the controller works if available.

- [ ] **5. App scanner, relauncher, icon by URL**: `Launcher/InstalledApps.swift`, `App/AppRelauncher.swift`, `Launcher/AppLauncher.swift`, `MMTVLTests/InstalledAppsTests.swift`, `MMTVLTests/AppRelauncherTests.swift`
  - Implement `InstalledApps` and `AppRelauncher` as specified.
  - `AppLauncher.icon(forApplicationAt url: URL) -> NSImage` uses `iconCache`. `icon(for:)` calls it.
  - `InstalledAppsTests` builds a temp directory (`FileManager.default.temporaryDirectory/UUID`, removed afterwards) containing:
    - `Zed.app` and `alpha.app`, each with `Contents/Info.plist` holding `CFBundleIdentifier`. Write the plist with `PropertyListSerialization` or a dictionary's `write(to:)`.
    - `Utilities/Tool.app`.
    - `Deep/Nested/Too.app` (must **not** be found).
    - `NoID.app` without a bundle ID, `.Hidden.app`, and a plain file `readme.txt`.
    - A second directory containing a `Dup.app` with the same bundle ID as `Zed.app`.
  - Expect:
    - Names `["alpha", "Tool", "Zed"]`, sorted case-insensitively.
    - The duplicate is dropped (first directory wins).
    - `excludingBundleIDs` removes an app.
    - A missing directory returns `[]` without crashing.
  - `AppRelauncherTests`: `processArguments(pid: 42, appPath: "/A.app", arguments: ["-windowed", "YES"]) == ["-c", AppRelauncher.script, "sh", "42", "/A.app", "-windowed", "YES"]`.
  - Done when: tests pass. Manual (temporary code, removed before ticking): call `AppRelauncher.relaunch()` from a temporary binding (e.g. in `applicationDidFinishLaunching` behind `UserDefaults.standard.bool(forKey: "testRelaunch")`, removed afterwards), or verify it in step 8 via the Relaunch row instead. Either way, record the result. Expected: the app quits and a new instance opens within about 1 s, in the same mode (windowed stays windowed). If the new instance never appears, see *Risks*.

- [ ] **6. Settings model: types, root page, focus, toggles**: `Settings/SettingsTypes.swift`, `Settings/SettingsEnvironment.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `MMTVLTests/SettingsModelTests.swift`, `MMTVLTests/ListFocusTests.swift`
  - Implement the types, `ListFocus`, the environment, and `SettingsModel` with the `.root` page fully.
  - For the other pages, return **empty sections with their titles** for now. Implement `perform` for `.toggle`, `.requestAccessibility`, `.openLoginItemsSettings`, `.push`, `.pop`, `.relaunch` and `.exitToDesktop`. The tile actions can be empty `break`s until step 9 (mark them `// step 9`).
  - Tests use a `makeModel(kiosk:trusted:loginStatus:)` helper that builds a `SettingsEnvironment` whose closures record calls into local arrays/flags (a small `final class Recorder` in the test file).
  - `ListFocusTests`:
    - `resolve` with a missing current → first.
    - `move` clamps at both ends.
    - Empty ids → nil.
  - `SettingsModelTests`:
    - Initial focus is `globalInput`.
    - Down ×3 → `accessibility`. Up from the first stays.
    - Select on `controllers` → `applySettings` was called once with `controllersEnabled == false`, `model.settings.controllersEnabled == false`, and the row's value is "Off".
    - Select on `accessibility` → `requestAccessibility` was called.
    - `approveLoginItem` is absent by default. With kiosk, `launchAtLogin` on and status `.requiresApproval`, it's present.
    - Windowed: the `launchAtLogin` and `globalInput` details are "Applies in kiosk mode only".
    - Select on `editHome` → page `.homeScreen`. Back → `.root` with focus restored to `editHome`. Back again → returns false.
    - `refreshStatus()` after the fake flips to trusted → `accessibility` value "Allowed".
    - `.home` → false.
  - Done when: tests pass (the model isn't on screen yet).

- [ ] **7. Settings views**: `Settings/SettingsView.swift`, `Settings/SettingsRowView.swift`, `DesignSystem/Theme.swift`
  - Theme tokens:
    - Fonts: `settingsTitleFont = Font.system(size: 48, weight: .semibold)`, `settingsSectionFont = Font.system(size: 24, weight: .semibold)`, `settingsRowFont = Font.system(size: 30, weight: .medium)`, `settingsDetailFont = Font.system(size: 22)`, `settingsHintFont = Font.system(size: 22)`.
    - Layout: `settingsSideColumnWidth: CGFloat = 600`, `settingsListWidth: CGFloat = 1000`, `settingsColumnSpacing: CGFloat = 80`, `settingsRowMinHeight: CGFloat = 80`, `settingsRowCornerRadius: CGFloat = 12`, `settingsRowSpacing: CGFloat = 8`, `settingsSectionSpacing: CGFloat = 40`, `settingsRowIconSize: CGFloat = 48`, `settingsPageImageSize: CGFloat = 280`.
    - Focus: `settingsRowFocusScale: CGFloat = 1.03`, `focusedRowFill = Color.white`, `focusedRowText = Color.black`, `focusedRowSecondaryText = Color.black.opacity(0.6)`.
    - The literal sizes are deliberate. The semantic macOS fonts are too small on the 1920-point TV canvas.
  - `SettingsView(model:launcher:onHoverRow:onActivateRow:)` on the 1920×1080 canvas:
    - `pageTitle` centered at the top (padding top 60).
    - Below the title, an HStack:
      - Left column (`settingsSideColumnWidth`, vertically centered): `RowImageView(image: model.pageImage, size: settingsPageImageSize)`.
      - Right column: a `ScrollViewReader { ScrollView(.vertical) { LazyVStack/VStack … } }` of width `settingsListWidth` with `.scrollIndicators(.hidden)`.
    - Each section shows its optional header (`settingsSectionFont`, `secondaryText`), its rows (`.id(row.id)`), and its optional footer (`settingsDetailFont`, `secondaryText`).
    - Pad the scroll content vertically 40 and horizontally 24, so scaled, shadowed focused rows aren't clipped.
    - `.onChange(of: model.focusedRowID) { _, id in withAnimation(Theme.focusAnimation) { proxy.scrollTo(id, anchor: .center) } }`, plus a non-animated `scrollTo` in `.onChange(of: model.page)` and `.onAppear`.
    - `model.hint` at the bottom (`settingsHintFont`, `secondaryText`, padding bottom 48).
  - `SettingsRowView(row:isFocused:launcher:)`:
    - HStack: optional `RowImageView` (`settingsRowIconSize`); a VStack with the title (`settingsRowFont`) and the optional detail (`settingsDetailFont`); Spacer; then, if set, a "Relaunch needed" capsule (`needsRelaunch`), the value, and a `chevron.right` (`showsDisclosure`). If `isLifted`, also an `arrow.up.arrow.down` symbol.
    - Min height `settingsRowMinHeight`, padding horizontal 32, `RoundedRectangle(cornerRadius: settingsRowCornerRadius, style: .continuous)` background.
    - Unfocused: clear background, `primaryText` / `secondaryText`.
    - Focused (or lifted): `focusedRowFill`, `focusedRowText` / `focusedRowSecondaryText`, `settingsRowFocusScale`, and the focus shadow.
    - Dimmed: opacity `unavailableOpacity` when not focused.
    - Info rows (no action) never look focused.
    - `.contentShape(Rectangle())`, `.onHover { if $0 { onHover } }`, `.onTapGesture { onActivate }`, `.animation(Theme.focusAnimation, value: isFocused)`.
  - `RowImageView(image:launcher:size:)`:
    - `.symbol` → `Image(systemName:)` at `size * 0.8` points, `primaryText`.
    - `.item(item)` → `launcher.icon(for: item)` resized to `size`, else its `iconSymbol` or `"app.dashed"`.
    - `.app(url)` → `launcher.icon(forApplicationAt: url)`.
    - When focused rows turn white, a symbol image in a row uses `focusedRowText`. Pass a `foreground` color in.
  - Done when: it builds. Optionally render it with a temporary `#Preview` using a fake environment, and remove that before ticking.

- [ ] **8. Wire Settings into the app**: `Launcher/AppRouter.swift`, `App/AppDelegate.swift`, `MMTVLTests/AppRouterTests.swift`
  - Router: add `case settings`, the `settings` init parameter, real `openSettings()`, `.settings` routing, and `hoverSettingsRow(_:)`. `LauncherRootView` renders `SettingsView(model: router.settings, launcher: router.launcher, onHoverRow: router.hoverSettingsRow, onActivateRow: router.settings.activate)`.
  - AppDelegate: build the `SettingsModel` before the router, with a `SettingsEnvironment` whose closures capture `[weak self]` or `launcher`:
    - `isKiosk: kiosk`
    - `versionString: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"`
    - `applySettings` / `applyItems` → the step 4 methods
    - `requestAccessibility` → `self?.requestAccessibility()`
    - `loginItemStatus: { LoginItem.status }`, `openLoginItemsSettings: { LoginItem.openSystemSettings() }`
    - `scanInstalledApps: { await InstalledApps.scanInBackground(excludingBundleIDs: [Bundle.main.bundleIdentifier ?? ""]) }`
    - `relaunch: { AppRelauncher.relaunch() }`
    - `exitToDesktop: { self?.router?.goHome(); self?.windowController?.exitToDesktop() }`
    - `tileTitle` / `isInstalled` → `launcher`
  - `applicationDidBecomeActive` calls `router?.settings.refreshStatus()`.
  - `AppRouterTests` (with `AppLauncher()` and a fake environment, as in step 6; move the `Recorder`/`makeModel` helper into `MMTVLTests/SettingsTestSupport.swift` so both suites share it):
    - Up then Select from the home screen → `screen == .settings`.
    - Back on the root → `.home`, with the gear still focused.
    - `.home` in Settings → `.home`.
    - `setItems` keeps focus on the same item id when an earlier item is hidden.
    - Hiding the focused item moves focus to the clamped index.
    - Hiding everything → the gear is focused.
  - Done when: tests pass, and on the dev Mac (windowed, then kiosk):
    - Gear → Settings shows the root page.
    - The toggles flip and `settings.json` changes on disk.
    - Turning Game Controllers off makes a connected controller stop navigating at once, and turning it on restores it (if a controller is available).
    - Turning Hide Pointer off stops the cursor hiding on arrow keys.
    - Kiosk: turning Global Home off makes fn+← from Finder do nothing, and on restores it, without a relaunch.
    - The Accessibility row says "Allowed".
    - Relaunch MMTVL restarts the app in the same mode.
    - Exit to Desktop works.
    - With the cursor parked over the list, keyboard scrolling doesn't jump focus.

- [ ] **9. Home Screen editing pages**: `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Implement the `.homeScreen`, `.tile(id)` and `.confirmRestoreDefaults` pages, move mode in `handle`, `activate(rowID:)` ending move mode, and the `perform` cases `.toggleTileVisible`, `.toggleTileFullScreen`, `.startMove`, `.removeTile` and `.restoreDefaults`.
  - Tests:
    - homeScreen lists every item (hidden too) with `"tile.<id>"` ids. A hidden item has value "Hidden" and `isDimmed`.
    - Tile page for `plex` has `tile.fullScreen`; for `youtube` it doesn't.
    - Toggle visible → `applyItems` received items with that tile hidden.
    - `startMove("plex")` → page `.homeScreen`, `movingTileID == "plex"`, focus `tile.plex`. Down → items order has plex second, focus still `tile.plex`, and `applyItems` was called. Select → `movingTileID == nil`.
    - Back in move mode ends move mode without leaving the page.
    - Remove `youtube` → page `.homeScreen`, youtube gone, focus on the next item's row.
    - Confirm page: initial focus `confirm.cancel`. Select on `confirm.restore` → items == `LaunchItem.defaults`, page `.homeScreen`.
  - Done when: tests pass, and on the dev Mac:
    - Hide a tile → Back → Back: it's gone from the home screen.
    - Show it again: it's back in the same place.
    - Move a tile: the home order matches.
    - Turn Open Full Screen off for the Browser: Brave opens windowed. Turn it on again.
    - Restore Defaults works.
    - `launch-items.json` reflects every change.

- [ ] **10. Add Tile page**: `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Implement the `.addTile` page, `loadInstalledApps()`, and `.addDefaultTile` / `.addApp`.
  - Tests, with a fake `scanInstalledApps` returning `[InstalledApp(bundleID: "tv.plex.htpc", …), InstalledApp(bundleID: "com.example.new", name: "New", …)]` and items = defaults minus `settings`:
    - Before loading, `apps.loading` is present.
    - After `await model.loadInstalledApps()`, Plex is excluded (already a tile), "New" is present, and the MMTVL section has `add.default.settings`.
    - Select on "New" → a new item `app.com.example.new` is inserted before `exit`, the page is `.homeScreen`, and the focus is `tile.app.com.example.new`.
    - Select on `add.default.settings` → the settings tile is inserted before `exit`.
    - With no apps left → `apps.none`.
  - Done when: tests pass, and on the dev Mac:
    - Add Tile lists the installed apps with icons; scrolling with held arrows is smooth.
    - Adding e.g. Calculator creates a tile that launches it.
    - The Settings tile can be added on the existing install, and selecting it opens Settings.
    - Removing the added tile works.

- [ ] **11. Wrap-up**: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - CLAUDE.md:
    - Under the config bullets, note that the Settings screen (gear by the clock / Settings tile) edits `settings.json` and `launch-items.json` live, and that hand edits made while MMTVL runs are overwritten. Edit them with MMTVL quit.
    - Document the `launch-items.json` per-item keys `launchFullScreen` and `isHidden`.
    - Note that `key-bindings.json` is still hand-edited.
  - Tick steps, set M2b to `Done` in the master plan, and record deviations.

## Tests

- New:
  - `LaunchItemEditingTests`
  - `HomeFocusModelTests`
  - `InstalledAppsTests`
  - `AppRelauncherTests`
  - `ListFocusTests`
  - `SettingsModelTests`
  - `AppRouterTests`
  - `SettingsTestSupport.swift` (shared fake environment)
- Unchanged and must still pass: every M1/M2 suite (`LauncherFocusModelTests`, `LaunchItemStoreTests`, `AppLauncherTests`, `KeyBindingsTests`, `JSONConfigFileTests`, `AppSettingsTests`, `MediaKeyEventTests`, `ThumbstickDirectionTests`, `SmokeTests`).
- The test target defaults to MainActor too, so `@Observable` models can be used directly in tests. Mark test-only `Codable` helpers `nonisolated` if needed (M2 deviation, step 2).
- Run all: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`
- Single suite: `-only-testing:'MMTVLTests/SettingsModelTests'`

## Manual verification

On the dev Mac:
- [ ] Up from the top row focuses the gear, and Down returns to the same tile. Mouse hover and click on the gear work.
- [ ] Settings opens from the gear and from the Settings tile. Back walks up the pages and then goes home. Home goes straight home.
- [ ] Each Remote & Input toggle takes effect without a relaunch (global Home in kiosk mode, controllers, pointer hiding), and `settings.json` updates.
- [ ] Windowed mode: the kiosk-only rows say "Applies in kiosk mode only".
- [ ] Accessibility: after `tccutil reset Accessibility dev.mmtvl.launcher`, a kiosk launch → Not now → gear → Settings shows "Not Allowed". Select → prompt and pane. Allowing access brings MMTVL back, the row shows "Allowed", and fn+← works from Finder.
- [ ] Launch at Login on (kiosk) → the row status or approval row appears if approval is needed, and Open Login Items Settings opens the pane. Turn it **off** again on the dev Mac.
- [ ] Hide, show, move and remove tiles; Open Full Screen per app; Restore Defaults (Cancel focused first). The home screen and `launch-items.json` match.
- [ ] Hide every tile: the home screen shows the gear focused and the hint. Settings is still reachable.
- [ ] Add Tile: the app list with icons; an added app launches; the Settings tile can be re-added.
- [ ] Relaunch MMTVL restarts in the same mode. Exit to Desktop works, and Home brings the launcher back.
- [ ] Pointer parked over the Settings list: keyboard scrolling doesn't steal focus. Moving the mouse does.

On the Mac mini / TV (when available):
- [ ] Settings text is readable from the couch (row font 30 pt on the 1920 canvas). Adjust the Theme tokens if not.
- [ ] Add the real apps (Plex HTPC, Prime Video) from Add Tile if their bundle IDs differ from the defaults.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| The relaunch helper dies with the app, or `open -n` fails | The app quits and doesn't come back | Spawn it detached: run `/usr/bin/nohup /bin/sh -c …`, or wrap it in `/bin/sh -c '( … ) &'`. If `open -n` is refused, use `open` without `-n` (the old instance is already gone). Record it in Deviations. |
| Two instances briefly overlap (old one slow to quit) | Double Home, presentation flicker | The script refuses to relaunch until our PID is gone. Raise the 10 s cap if `applicationShouldTerminate` work ever grows. |
| `scrollTo` fights the scaled canvas or jumps | Focused row off screen or jittery | Switch to `.scrollPosition(id: $binding, anchor: .center)` bound to the focused id (macOS 14+). As a last resort, compute a manual offset (row index × row height). |
| Focused-row scale or shadow clipped by the ScrollView | Edges cut off | Increase the content padding, or add `.scrollClipDisabled()` with an outer `.clipped()` on a slightly larger frame. |
| App scan slow (network or huge folders) | "Loading…" for seconds | It already runs detached. Cap the depth (already 1) and skip non-local volumes. Acceptable as is. |
| Controller handlers keep firing after "off" | Navigation still works with the toggle off | Confirm `unconfigure` covers every element `configure` binds, including micro gamepads. As a belt-and-braces fix, add an `isEnabled` guard in `buttonChanged`. |
| `nonisolated extension` rejected by the compiler | Build error | Mark each member `nonisolated` instead. |
| Display names localized oddly or with `.app` | Odd titles in Add Tile | Fall back to `CFBundleDisplayName` / `CFBundleName` from the bundle. |
| Restarting the event tap leaves a stale run-loop source | Double events, or Home dead after on/off | `stop()` already removes the source and invalidates the port. If not, log it and use "Relaunch needed" for that row (D19). |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
