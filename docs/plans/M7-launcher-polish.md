# M7 — Launcher polish, top shelf & remote buttons

| | |
|---|---|
| Status | In progress |
| Depends on | M2 (input layer, bindings), M2b (Settings), M3 (YouTube, PIN), M4/M6/M6b (Live TV, lineup, menus), M5 (phone remote page) |
| Master plan decisions used | D1, D2, D3, D9, D10, D15, D16, D17, D19, D20, D23, D24, D26; new **D27** (Menu/Channel commands, bindings editor), **D28** (top shelf, Plex link) |
| Planned | 2026-10-06 |

## Goal

From the couch, the home screen feels like tvOS and the remote is fully configurable:

- **All tiles are reachable.** With more than two rows of tiles, the rows scroll as focus moves down (the top shelf fades away), as on tvOS. The mouse wheel moves focus by a row. (Today a third row is drawn below the screen: reported by the user on 2026-10-06.)
- **Tiles move.** The focused tile lifts, tilts toward the direction focus came from and settles, with a moving specular shine. With the mouse, it tilts under the pointer. Tiles show **art**: a 5:3 picture you drop in `~/Library/Application Support/MMTVL/tile-art/<tile id>.png`, else designed gradient art for the built-in tiles, else the app icon on a blurred backdrop of itself.
- **Top shelf.** The top of the home screen shows what the focused tile offers:
  - **Live TV:** "On Now" cards for your favorites (else recent channels): logo, programme, time left, progress. Press Up into the shelf, pick a card, Select: Live TV opens on that channel.
  - **Plex:** "Continue Watching" from your Plex Media Server. Sign in once in Settings → Plex by entering a 4-character code at plex.tv/link (or scanning a QR code). Select on a card opens Plex HTPC (it can't jump to the item yet; Q11).
  - **Every other tile:** a large banner of its art.
- **Three new remote commands:** **Menu** (the channel menu in Live TV, the window menu in Multiview), **Channel Up** and **Channel Down** (zap in the player and in a Multiview window, page through lists). By default Channel Up moves **up the channel list, like the Up arrow**; Settings → Remote & Input → *Channel Up* can switch it to "higher channel number". They have default keys (Page Up/Down, Tab, the PC Menu key), controller buttons (triggers, Y) and phone buttons.
- **Settings → Remote Buttons.** Every command lists its buttons. *Add a Button* asks you to press one on any remote, keyboard or controller, then confirms; *Remove* and *Works in Other Apps* (Home only) per button; *Restore Default Buttons*. Changes apply at once; `key-bindings.json` no longer needs hand-editing.
- **Web app tiles (Chromium PWAs** such as YouTube Music and Google Photos) keep working when the browser hands the launch off: MMTVL no longer jumps back, and a web app that can't open shakes its tile. A web app tile can have its own **start page**: the Google Meet tile opens straight on `meet.google.com/home?calling=1`.

## Out of scope

- **M7b (planned after M7):** phone remote home-screen icon, phone trackpad mode, YouTube DIAL discovery, the casting setup checklist (AirPlay/Plex/YouTube), and the **on-TV QA pass** for M7 + M7b. Research already done for M7b is in [M7b-notes.md](M7b-notes.md).
- Jumping Plex HTPC to a specific item (`plex://` deep link; unverified, Q11). Plex shelf cards only open Plex.
- Plex's newer JWT sign-in (the PIN flow is "legacy" but works; see *Research*).
- YouTube top shelf content (there is no API without an account integration). YouTube gets a banner.
- A top shelf for the Settings and Exit tiles (banner only), and for PIN-protected tiles (banner only, L12).
- Editing a binding's trigger in place (remove + add instead), `.media` triggers other than the five existing media keys, modifier-only keys.
- Showing new commands in YouTube: leanback has no Menu/Channel keys; YouTube ignores them (L5).
- Idle motion (tvOS has none without a touch surface), layered (LSR) art.

## Research & findings

### Chromium web app tiles (PWA) — reproduced on the dev Mac, 2026-10-06

- The user's tile `com.brave.Browser.app.cinhimbnkkaeohfgghhklpknlkffjgod` (YouTube Music) is a Chromium **app shim**: `~/Applications/Brave Browser Apps.localized/YouTube Music.app`, executable `app_mode_loader`, ad-hoc signed. Its Info.plist has `CrAppModeShortcutID` (the app id), `CrAppModeShortcutName`, `CrAppModeShortcutURL`, `CrBundleIdentifier` (`com.brave.Browser`).
- MMTVL's log at 14:16: `Launching com.brave…cinhim…`, then **0.3 s later** `Launched app 14423 quit; returning to launcher`, then `Gave up making pid 14423 full screen after 15.0 seconds`, three times. The shim connected to Brave (`AppShim: Connection received from pid …` in Brave's log) and exited by itself; `open -b <id>` from Terminal did the same. So **MMTVL's "launched app quit → come back" (M1 L5) fires on a shim that hands off**, and `WindowFullScreener` targets the dead shim pid.
- Contributing cause on that day: a headless Brave run from this session's earlier screenshot job was alive and registered as "Brave Browser" with LaunchServices, so Brave and its web apps didn't open normally even from the Dock. After it exited, Brave worked again; a "YouTube Music" window was then **owned by the Brave process** (CGWindowList owner "Brave Browser"), and the shim was gone (the user had removed the web app).
- The user then had to `sudo killall "Brave Browser"`; after that, web apps worked again (YouTube Music and Google Photos are installed).
- **Healthy case, verified 2026-10-06 after the restart:** `open -b com.brave.Browser.app.cinhimbnkkaeohfgghhklpknlkffjgod` → the shim process (`app_mode_loader`) **stays running and owns the "YouTube Music" window** (CGWindowList owner "YouTube Music", the shim's pid). So MMTVL's normal path (launch, track the pid, `AXFullScreen` on that pid) works for a healthy web app.
- Conclusion: the failure was the stuck browser, not MMTVL. Step 13 only adds a **safety net** for a shim that hands off and quits (the 14:16 case): don't treat that quit as "app closed", look for the window for 10 s, else shake the tile.
- **Opening a web app on a chosen page (verified 2026-10-06 with the user's Google Meet web app):** Meet's shim has `CrAppModeShortcutURL = https://meet.google.com/landing?lfhs=2` (its start page). Running
  `open -n -a "Brave Browser" --args --app-id=kjgfgldnnfoeklkmfkjfagphfepbbdan "--app-launch-url-for-shortcuts-menu-item=https://meet.google.com/home?calling=1"`
  while Brave was running made Brave launch the Meet shim (`app_mode_loader --launched-by-chrome-process-id=<Brave pid>`), which owned a new "Google Meet" window, and **the user confirmed it landed on the calling screen**. `--app-launch-url-for-shortcuts-menu-item` is the switch Chromium uses for a web app's shortcut-menu items. `-n` (a new instance) is needed so the arguments reach Brave: the new process hands them to the running Brave and exits.
  - **Unverified:** the same with Brave not running (cold start), and with the Meet app already open (a second window, or the existing one?). Step 13's manual check covers both.
- Web apps (PWAs) are the recommended way to put YouTube Music and Google Photos on the home screen: they get their own icon, window and full screen, and Add Tile already lists them (it scans `~/Applications/Brave Browser Apps.localized`).

### Plex (research 2026-10-06; sources: [developer.plex.tv/pms](https://developer.plex.tv/pms/), [python-plexapi](https://github.com/pkkid/python-plexapi), live calls to plex.tv)

- **PIN link sign-in** (the docs call it "Traditional Token Authentication (Legacy)"; it still works):
  - `POST https://plex.tv/api/v2/pins` with headers `Accept: application/json`, `X-Plex-Product`, `X-Plex-Client-Identifier` (and the other `X-Plex-*` below). **No `strong=true`** → a **4-character code**, `expiresIn: 900` (15 min). Tested live.
  - Response JSON: `id` (Int), `code`, `expiresAt` (ISO 8601), `expiresIn`, `authToken` (null until claimed), `qr` (a PNG URL), `clientIdentifier`, …
  - The user enters the code at **https://plex.tv/link**. For a QR code, use `https://plex.tv/link/?pin=<code>` (docs: "For 4-digit pins, you need to use the link page").
  - Poll `GET https://plex.tv/api/v2/pins/{id}` (docs: once per second) **with the same `X-Plex-Client-Identifier`**; another id gives 404 (tested). `authToken` becomes non-null when claimed. **Unverified:** an expired PIN's response (treat 404 or `expiresAt` passed as "make a new code").
  - Token check: `GET https://plex.tv/api/v2/user` → 200 valid, 401 invalid; other statuses are errors, not invalidity.
- **Servers:** `GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=0` with `X-Plex-Token: <user token>`. A JSON array of resources: `name`, `product`, `provides` (comma string; keep those containing `server`), `clientIdentifier` (= the server's machine id), **`accessToken` (use this for the server, not the user token)**, `owned`, `presence`, `httpsRequired`, `connections[]` (`protocol`, `address`, `port`, `uri`, `local`, `relay`, `IPv6`).
  - Pick a connection: local before remote, https before http, never relay; check with `GET {uri}/identity` (no auth; `MediaContainer.machineIdentifier` must equal the resource's `clientIdentifier`).
- **Continue Watching:** documented `GET {server}/hubs/continueWatching?count=N` → `MediaContainer.Hub[]`; the hub with `hubIdentifier == "home.continue"` holds `Metadata[]`. python-plexapi uses `/hubs/continueWatching/items` (flat `MediaContainer.Metadata[]`, not in the spec) — the fallback on 404.
  - `Metadata`: `type` ("episode", "movie", …), `title`, `grandparentTitle`, `parentIndex` (season), `index` (episode), `thumb`, `art`, `grandparentThumb`, `grandparentArt`, `viewOffset`, `duration` (ms), `ratingKey`, `year`. **Confirm against a live response** (step 11's manual check; decode everything optional).
  - JSON only with `Accept: application/json` (the default is XML).
- **Images:** `GET {server}/photo/:/transcode?url=<thumb path, percent-encoded>&width=W&height=H&minSize=1&upscale=1` with `X-Plex-Token` as a header (keeps the token out of URLs).
- **Headers** on every call: `X-Plex-Client-Identifier` (a stable UUID we store), `X-Plex-Product: MMTVL`, `X-Plex-Version` (app version), `X-Plex-Platform: macOS`, `X-Plex-Platform-Version`, `X-Plex-Device: Mac`, `X-Plex-Device-Name` (the Mac's name), plus `X-Plex-Token` where needed. The product name shows in the user's Plex "Authorized Devices".
- **HTTPS / ATS:** `*.plex.direct` connections have real certificates, so default `URLSession` trust works. Plain `http://<LAN IP>:32400` would hit App Transport Security (no IP-address exceptions by default; needs `NSAllowsLocalNetworking`, a dictionary key that `INFOPLIST_KEY_*` can't set). **L16: https connections only.** A router with DNS-rebinding protection can block `plex.direct` names (fallback in *Risks*).
- **Local Network privacy** ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)): outgoing connections to a LAN address need the user's Local Network permission on macOS 15+ (listening for TCP doesn't, which is why M5 never asked). The first attempt may fail while the alert shows; retry. Add `NSLocalNetworkUsageDescription` (L17).
- **Plex HTPC** 1.71.1 (`tv.plex.htpc`) registers the `plex` URL scheme. How it maps a URL to an item is **unverified** (Q11); M7 only launches the app.
- No Plex Media Server runs on the dev Mac (`127.0.0.1:32400` refused). Where it runs on the user's network is unknown; discovery through plex.tv handles any location.

### Apple APIs (known, used by this plan)

- `rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`, `onContinuousHover(coordinateSpace:perform:)` (macOS 13+), `ImageRenderer` (macOS 13+), `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` (downsampling).
- `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` + `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
- `GCExtendedGamepad.leftTrigger` / `.rightTrigger` are `GCControllerButtonInput` (pressed past the threshold), so they bind like buttons.
- Carbon key codes: `kVK_PageUp` 116, `kVK_PageDown` 121, `kVK_Tab` 48, `kVK_ContextualMenu` 110, `kVK_Home` 115, `kVK_End` 119, `kVK_ForwardDelete` 117, `kVK_Help` 114, F1…F20 (`kVK_F1` 122 …), keypad `kVK_ANSI_Keypad0` 82 …. The full list is in `Carbon.framework/…/HIToolbox.framework/Headers/Events.h` (`find "$(xcrun --show-sdk-path)" -name Events.h -path "*HIToolbox*"`).
- `NSEvent.isARepeat` for key repeats. A local monitor sees ⌘-combos before the menu, so capture must skip them (L8) or ⌘Q would be captured.

### This codebase (read 2026-10-06; don't re-read to plan, read to implement)

- `RemoteCommand` (10 cases) is switched exhaustively in: `LauncherFocusModel.move`, `AppRouter.route`, `SettingsModel.handle`, `PINPad` (via `PINEntryModel`), `LiveMenu.handle`, `GuideModel.handleGrid/handleChannel/handleGroups`, `LiveTVModel.handlePlayer/handleMultiview` (+ `handle`'s mode switches use `default`), `MultiviewLayout.Direction.init?`, `YouTubeKeyMap.keyCode`, `ExternalKeyMap.key`, `ThumbstickDirection`, `ControllerInput.dpadButton` (default). Adding cases breaks every exhaustive switch: step 2 fixes them all.
- `KeyBindings` lookups are "first match wins"; `GlobalEventTap.decide` and `ControllerInput` read `inputRouter.bindings` on every event, so assigning `inputRouter.bindings` applies live everywhere.
- `key-bindings.json` is loaded in `AppDelegate.applicationDidFinishLaunching` with an inline `JSONConfigFile`; nothing saves it today.
- Settings pages are data (`SettingsPage`, `SettingsAction`, `SettingsRow`) drawn by one list (`SettingsView`); side-effects go through `SettingsEnvironment`. Pairing (`syncPairing`) is the pattern for "active exactly while page X shows".
- `HomeView` lays tiles from `Theme.rowsTopFraction` (0.45 → y 486) down; the area above is reserved for the top shelf. The clock is top-right at y 60.
- `IPTVLibrary`: `lineup.favorites`, `nowNext(for:at:)`, `rememberChannel(_:)`, `state.lastChannelID`. `LiveTVModel.open()` plays the last channel or restores Multiview.
- `AppLauncher.launch` tracks launched pids (`launchedPIDs`) and calls `onReturnToLauncher` when one quits while nothing else is frontmost.

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL/Input/RemoteCommand.swift` | changed | `menu`, `channelUp`, `channelDown`; `title` for Settings. |
| `MMTVL/Input/InputBinding.swift` | changed | `ControllerButton.leftTrigger/rightTrigger`; `Trigger.matches(_:)`, `Trigger.normalized`. |
| `MMTVL/Input/KeyBindings.swift` | changed | New defaults; `revision`; `addingDefaults(for:)`. |
| `MMTVL/Input/KeyBindings+Editing.swift` | new | Pure editing: add/remove/global/restore, `canRemove`. |
| `MMTVL/Input/TriggerName.swift` | new | Pure: human name of a trigger ("Page Up", "Controller A"). |
| `MMTVL/Input/InputRouter.swift` | changed | `captureHandler` + `capture(_:)` (learn mode); `onScrollWheel` (L21). |
| `MMTVL/Input/GlobalEventTap.swift` | changed | Captures while learning. |
| `MMTVL/Input/ControllerInput.swift` | changed | Triggers; captures while learning. |
| `MMTVL/Input/ExternalKeyMap.swift` | changed | Channel Up/Down → Page Up/Down for other apps. |
| `MMTVL/App/AppSettings.swift` | changed | `keyBindingsRevision`, `channelUpMovesUpList`. |
| `MMTVL/App/AppDelegate.swift` | changed | Bindings file + migration, editor wiring, top shelf, tile art, Plex. |
| `MMTVL/Settings/*` | changed | Remote Buttons pages, learn flow; Plex pages; tile art row. |
| `MMTVL/IPTV/LiveTVModel.swift`, `Guide/GuideModel.swift`, `LiveMenu.swift` | changed | Menu/Channel behavior; `open(channelID:)`. |
| `MMTVL/IPTV/IPTVState.swift`, `IPTVLibrary.swift` | changed | `recentChannelIDs`. |
| `MMTVL/YouTube/YouTubeKeyMap.swift`, `PIN/PINPad.swift` | changed | Ignore new commands. |
| `MMTVL/RemoteServer/Web/remote.html/.css/.js` | changed | Menu, CH+, CH− buttons. |
| `MMTVL/DesignSystem/ParallaxFocus.swift` | new | The focus effect modifier (L1). |
| `MMTVL/DesignSystem/Theme.swift` | changed | Parallax, art, shelf tokens. |
| `MMTVL/Launcher/TileArt.swift` | new | `TileArt`, `TileArtStore` (L3, L4). |
| `MMTVL/Launcher/TileArtView.swift` | new | Draws a tile's art (custom, built-in gradient, icon backdrop). |
| `MMTVL/Launcher/HomeLayout.swift` | new | Pure row geometry and scroll offset (L21). |
| `MMTVL/Launcher/AppTileView.swift`, `HomeView.swift` | changed | Scrolling rows; art + parallax; shelf on top. |
| `MMTVL/Launcher/TopShelf.swift` | new | `ShelfCard`, `ShelfContent`, `TopShelfProviding`, `TopShelfModel`. |
| `MMTVL/Launcher/TopShelfView.swift` | new | Banner and card row. |
| `MMTVL/Launcher/ShelfImageLoader.swift` | new | In-memory image cache with header-auth fetches (Plex). |
| `MMTVL/Launcher/AppRouter.swift` | changed | Shelf focus, focus motion, open channel from the shelf. |
| `MMTVL/Launcher/AppLauncher.swift`, `WindowFullScreener.swift` | changed | Chromium web app shims (L18), web app start pages (L23). |
| `MMTVL/Launcher/LaunchItem.swift`, `LaunchItem+Editing.swift` | changed | `startURL` (L23). |
| `MMTVL/Plex/PlexAPI.swift` | new | Pure: request building + JSON decoding. |
| `MMTVL/Plex/PlexNetwork.swift` | new | Injectable transport (like `IPTVNetwork`). |
| `MMTVL/Plex/PlexConfig.swift` | new | `plex.json` (non-secret) + Keychain token accounts. |
| `MMTVL/Plex/PlexAccount.swift` | new | `@Observable`: link flow, server choice, Continue Watching. |
| `MMTVL.xcodeproj/project.pbxproj` | changed | `INFOPLIST_KEY_NSLocalNetworkUsageDescription` (both app configs). Build settings only. |
| `MMTVLTests/…` | new/changed | See *Tests*. |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | changed | Step 15. |

New files under `MMTVL/` and `MMTVLTests/` are picked up by the synchronized groups. **Don't add file references to `project.pbxproj`.** Create the new `MMTVL/Plex/` folder on disk; it joins the target automatically.

### Local decisions

- **L1. Parallax focus effect** (`ParallaxFocus.swift`), for tiles and shelf cards:
  - Focused: scale `Theme.focusScale` (1.1, unchanged), shadow (unchanged), **specular**: a white radial gradient (opacity 0.35 → 0, radius 0.9 × tile width) overlaid with `.blendMode(.plusLighter)`, clipped to the tile shape, its center at `(0.5 + tilt.x × 0.35, 0.15 + tilt.y × 0.35)` in unit coordinates.
  - **Tilt** is a `CGSize` in −1…1. Rendering: `rotation3DEffect(.degrees(tilt.width × Theme.parallaxMaxDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.6)` then `rotation3DEffect(.degrees(-tilt.height × Theme.parallaxMaxDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.6)`; `parallaxMaxDegrees = 7`. The art's foreground layer (icon or symbol, not a full-bleed picture) is offset by `tilt × Theme.parallaxLayerOffset` (8 pt) for depth.
  - **Nudge** (remote/keyboard): when focus arrives by Left/Right/Up/Down, the newly focused tile starts tilted **toward the side it came from** (`tilt = −direction × 0.6`, e.g. moving right starts at x = −0.6) and springs to 0 (`.spring(response: 0.45, dampingFraction: 0.55)`). A **press** (Select) scales the tile to 0.95 for 0.1 s and back.
  - **Pointer**: while the mouse hovers a focused tile, tilt follows the pointer (`onContinuousHover`, location normalized to −1…1 over the tile, y down = positive), animated with `.interactiveSpring`; leaving resets to 0.
  - **Reduce Motion** (System Settings → Accessibility → Display): no tilt, no nudge, no press scale; scale and a static specular stay. Read `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in `ParallaxFocus` through `@Environment(\.accessibilityReduceMotion)` (SwiftUI exposes it on macOS).
  - Unfocused tiles: no tilt, no specular.
- **L2. Focus motion is router state.** `AppRouter.focusMotion: FocusMotion` (`direction: RemoteCommand?`, `generation: Int`) is bumped on every home Left/Right/Up/Down that moved focus and on Select (`direction: .select`). The focused tile's view reacts in `.onChange(of: focusMotion)`. Hover moves don't bump it.
- **L3. Custom tile art** is a file per tile id in `~/Library/Application Support/MMTVL/tile-art/` (D10's directory, new subfolder). Accepted: `<id>.png`, `.jpg`, `.jpeg`, `.heic` (first found in that order). Ideal 5:3 (e.g. 1500 × 900); any size is drawn `scaledToFill` and cropped. Downsampled to at most 1500 px on load (`CGImageSource` thumbnail). Hand-placed; no Settings import. The folder is created at launch (empty) so it's easy to find. The tile's Settings page shows an info row: "Art: plex.png" or "Add a 5:3 picture named plex.png to …/MMTVL/tile-art".
  - `TileArtStore.reloadIfChanged()` lists the folder and compares file names + modification dates with the last scan; it runs when the home screen appears (`HomeView.onAppear`, and when `router.screen` becomes `.home`). Cheap: one directory listing.
- **L4. Art for tiles without a custom picture:**
  - Built-in destinations get **gradient art**: a diagonal two-color gradient + the tile's SF Symbol in white at 45 % of the tile height. YouTube: `#FF3B30 → #B3001B`, `play.rectangle.fill`. Live TV: `#0A84FF → #003A8C`, `tv`. Settings: `#636366 → #2C2C2E`, `gearshape.fill`. Exit to Desktop: `#3A3A3C → #1C1C1E`, `rectangle.portrait.and.arrow.right`. Colors are `Theme` tokens.
  - Apps get **icon art**: the app icon drawn huge (2.2 × tile width), blurred (radius 40), darkened (black 0.35 overlay) as the background, with the icon itself at `Theme.tileIconFraction` on top (the foreground layer for parallax).
  - `.url` tiles and missing icons: the gradient art of Exit (neutral) with `item.iconSymbol ?? "globe"`.
  - "Not installed" keeps M1 L6 (dimmed art + caption).
- **L5. New commands** (D27): `menu`, `channelUp`, `channelDown` (raw values as written; `key-bindings.json` names them). What each screen does:

  | Screen | Menu | Channel Up | Channel Down |
  |---|---|---|---|
  | Home | not handled | not handled | not handled |
  | Settings | not handled (passes) | focus 8 rows up (clamped) | focus 8 rows down |
  | PIN | ignored | ignored | ignored |
  | YouTube | consumed, not sent (no leanback key) | consumed, not sent | consumed, not sent |
  | Live TV player | channel menu for the playing channel | `zap(-1)` (up the list, like the Up arrow; L22 flips it) | `zap(+1)` (L22 flips it) |
  | Live TV guide (watch) | channel menu for the focused row's channel (from the grid or the channel cell; in the groups column: nothing) | rows −6 (a page, clamped) | rows +6 |
  | Guide (Multiview picker) | nothing | rows −6 | rows +6 |
  | Multiview | window menu of the highlighted window (as Select on a filled window; empty window: nothing) | the highlighted window steps up the list (L6, L22) | steps down the list (L6, L22) |
  | Any open `LiveMenu` | closes it | focus 8 up (a page) | focus 8 down |
  | Setup needed / loading / unavailable | nothing | nothing | nothing |

  - **Channel Up moves up the list by default** (user choice 2026-10-06: match the Up arrow, M4's `zap(-1)`). The setting in L22 makes it the higher channel number instead. Documented in CLAUDE.md.
  - In the guide and in lists, Channel Up always pages **up** (the setting only affects zapping).
  - The channel menu from the player has no *Move Up/Down* (they need the Favorites group shown in the guide; M6b L8 already gates them on `guide?.selectedGroup`).
  - **Other apps** (phone remote, M5 L5 `ExternalKeyMap`): Channel Up → `kVK_PageUp`, Channel Down → `kVK_PageDown`, Menu → nothing (no toast).
- **L6. Multiview channel zapping:** the highlighted window's channel steps through the same list `zap` uses (remembered group if it holds the channel, else its group, else all visible), **skipping channels already in another window**, and is assigned with the existing `assignWindow(_:to:)` (the M6 path that frees the old stream first; Q10 verified it on a full 1 + 4). No window or empty window: nothing. Sound stays on the highlighted window.
- **L7. Default bindings for the new commands** (appended to `KeyBindings.defaultBindings`, after the existing ones, labels as shown):
  - Keys: `kVK_PageUp` → channelUp "Page Up", `kVK_PageDown` → channelDown "Page Down", `kVK_Tab` → menu "Tab", `kVK_ContextualMenu` → menu "Menu key". (Tab as Menu confirmed by the user, 2026-10-06.)
  - Controller: `rightTrigger` → channelUp, `leftTrigger` → channelDown, `y` → menu (label "Controller <button>").
  - **Migration:** `AppSettings.keyBindingsRevision` (Int). A `settings.json` without the key decodes as **1**; `AppSettings()` (fresh) is **`KeyBindings.currentRevision` = 2**. At launch, if `settings.keyBindingsRevision < 2`: `bindings = bindings.addingDefaults(for: [.menu, .channelUp, .channelDown])` (each default binding of those commands whose trigger isn't already bound to anything), save `key-bindings.json`, set the revision to 2, save `settings.json`. So a user who later removes them doesn't get them back.
- **L8. Learning a button** (the editor's *Add a Button*):
  - While the page `.learnButton(command)` shows, `InputRouter.captureHandler` is set. The **first** trigger pressed is captured instead of being dispatched:
    - Keys (local monitor, or the event tap when it runs): key down, **not a repeat**, without ⌘. ⌘-combos pass through untouched (⌘Q must still quit). Modifiers ⌥⌃⇧ are kept (`.key(code, modifiers)`, normalized).
    - Media keys (system-defined, subtype 8): key down, not a repeat, one of the five `MediaKey`s. The key-up is swallowed too while capturing.
    - Controller buttons: press (not release). The left stick feeds D-pad buttons as today.
    - Capture happens only while MMTVL is active (`NSApp.isActive`); otherwise everything behaves as before.
  - **Phone remote commands are never captured** (they're `RemoteCommand`s, not triggers), so the phone can always navigate and its Back cancels learning.
  - Learning ends after **10 s** with no press (`SettingsModel.learnTimeout`), popping back to the command page with the detail "No button pressed". The mouse can click *Cancel*.
  - After a capture: the page is replaced by `.confirmLearn(command, trigger)`: title "Use <name> for <command>?", rows **Use This Button** (detail when the trigger is bound elsewhere: "Now used for Back; it moves to Up"), **Try Again**, **Cancel**. The confirm page **ignores Select for 0.6 s** after it appears (a held key's auto-repeat mustn't confirm by itself).
  - Using it: `bindings.adding(trigger, for: command)` removes every binding whose trigger matches (L9), then appends the new one (`isGlobal = command == .home`, `label = TriggerName.describe(trigger)`), applies and saves, and pops to the command page.
- **L9. Trigger identity.** Two key triggers match when key codes are equal and modifier **sets** are equal (as lookups do). Media and controller triggers match by equality. The editor writes modifiers sorted in `KeyModifier.allCases` order (`Trigger.normalized`). A hand-edited file with duplicate triggers keeps working (first match wins); the editor lists every binding, and *Remove* removes all bindings matching that trigger.
- **L10. Removing buttons.** `canRemove(trigger)`: false when that trigger's command is one of **up, down, left, right, select, back** and it is that command's only binding. The row then shows "The last button for Select can't be removed" and has no action. Every other binding can go (Home too: the phone remote and the mouse always work; *Restore Default Buttons* brings everything back).
- **L11. Works in Other Apps** (`isGlobal`) is offered **only on Home bindings** (`handleGlobal` ignores other global commands, and a global non-Home key would be swallowed in Plex and the browser for nothing). New Home bindings are global; others are written `isGlobal: false`. Hand-edited global flags on other commands are kept and shown as "Works in other apps" in the detail, without a toggle.
- **L12. Top shelf focus and content.**
  - The shelf shows the content of the **focused tile** (any row). `TopShelfProviding.content(for: LaunchItem) -> ShelfContent`.
  - `ShelfContent.cards(title:, [ShelfCard])` makes the shelf focusable; `.banner` doesn't.
  - **Up** from a tile in the **first row** enters the shelf when it has cards (`shelfIndex = 0`). In the shelf: Left/Right move (clamped), **Down** or **Back** return to the tile, **Select** runs the card's action, Up does nothing. While in the shelf the owner tile keeps its focus (drawn without the focus scale; the card is focused).
  - **PIN-protected tiles** (`item.isPINProtected && hasPIN`) always get a banner, never cards.
  - Not-installed apps: banner.
  - If the content changes while in the shelf (refresh), clamp `shelfIndex`; if it has no cards anymore, return to the tile.
  - Mouse: hovering a card focuses it (with the pointer-moved rule, M1 L8); clicking runs it.
- **L13. Live TV shelf.** Title "On Now". Up to **10** cards: `lineup.favorites`; when empty, `state.recentChannelIDs` (visible channels only, most recent first); when also empty, nothing (banner).
  - Each card: the channel logo (`AsyncImage`, as the guide does) centered on a dark 16:9 card; caption line 1 = the programme on now (else the channel name); line 2 = "<channel name> · 25 min left" (else "No guide data"); a progress bar under the card when there is a programme.
  - Data: `IPTVLibrary.nowNext(for:at:)` per channel, refreshed when the home screen appears and every 60 s while it shows (`TimelineView`-independent task in `TopShelfModel`). Only when a playlist is set and channels are loaded.
  - Select: `AppRouter.openLiveTV(channelID:)` → `LiveTVHosting.open(channelID:)`: Live TV plays that channel full screen, **leaving Multiview** if the snapshot was active (the snapshot is kept with `isActive = false`, M6 L13's inactive path).
  - `IPTVState.recentChannelIDs: [String]` (max 10, most recent first) is updated by `rememberChannel`. Missing in older files → `[]`.
- **L14. Plex shelf** (the tile whose kind is `.application(bundleID: "tv.plex.htpc")`; the default "plex" tile). Title "Continue Watching". Up to **12** cards from Continue Watching:
  - Episode: line 1 `grandparentTitle`, line 2 "S\(parentIndex) E\(index) · \(title)"; image `grandparentArt ?? art ?? thumb`.
  - Movie and others: line 1 `title`, line 2 `year` (else empty); image `art ?? thumb`.
  - Progress `viewOffset / duration` when both exist.
  - Select: launch the owner tile (the same path as selecting the tile, so PIN and full screen apply). Deep linking is Q11.
  - Not signed in, no server or a failed load with nothing cached: banner. A failed refresh keeps the old cards.
  - Refreshed when the home screen appears if older than **2 min**, and when Plex is focused if older than 2 min.
- **L15. Plex sign-in** (Settings → Plex, D28):
  - Keychain (D9): account **`plex-token`** (user token), account **`plex-server-token`** (the chosen server's `accessToken`).
  - `plex.json` (D10, non-secret): `clientIdentifier` (UUID string, created once), `serverID`, `serverName`, `connections` (the chosen server's https connection URIs, best first), `lastConnection` (the URI that worked last).
  - **Link page** (`.plexLink`): on open, `POST /api/v2/pins`; shows the code as the page title row value and a QR code (`RowImage.qrCode("https://plex.tv/link/?pin=<code>")`) in the side column; polls every 1 s while the page shows (like pairing, `syncPlexLink`). A 404 or a passed `expiresAt` makes a new PIN. When `authToken` arrives: save it, load servers, then:
    - 0 servers: page shows "No Plex Media Server on this account".
    - 1 server: choose it (connect, L16) and pop to `.plex`.
    - more: replace the page with `.plexServers` (owned first, then by name), Select chooses.
  - **Plex page** (`.plex`): signed out: row "Sign In" (→ `.plexLink`). Signed in: "Server" (value name; disclosure → `.plexServers` when the account has more than one), "Status" info row ("Connected · 7 items", "Can't reach the server", "Sign in again" on 401), "Sign Out" (→ confirm page `.confirmPlexSignOut`: removes both Keychain items and resets `plex.json` except `clientIdentifier`).
  - **Never log tokens, PIN codes or full connection URIs**; log the server name and URI host only.
- **L16. Server connection:** try the chosen server's connections whose `protocol == "https"` and `relay == false`, **local first**, in API order, with `GET {uri}/identity` (timeout 4 s) checking `machineIdentifier`. The first that answers becomes `lastConnection`; later calls start with `lastConnection`, then the rest. No http, no relay (ATS, *Research*). If none answers: status "Can't reach the server".
- **L17. `NSLocalNetworkUsageDescription`** = "MMTVL connects to your Plex Media Server on this network." via `INFOPLIST_KEY_NSLocalNetworkUsageDescription` in the app target's Debug and Release build settings. The first Plex call may fail while macOS asks; the Plex page's Status row then reads "Allow Local Network access, then try again", and opening the Plex page or the home screen retries.
- **L18. Chromium web app tiles: a safety net.** An `.application` tile is a **web app** when its bundle's Info.plist has `CrAppModeShortcutID`. The healthy path is unchanged (the shim stays and owns the window; *Research*). Only when a web app's launched pid **quits within 5 s of its launch**:
  - `applicationDidTerminate` does **not** return to the launcher for it (remember web-app pids with their launch time and bundle info in a small dictionary next to `launchedPIDs`);
  - instead, for up to 10 s, poll every 300 ms for (a) a running app with the tile's bundle ID (a relaunched shim) that has a standard window, else (b) a window of the browser (`CrBundleIdentifier`) whose `AXTitle` begins with `CrAppModeShortcutName`;
  - found (a): add its pid to `launchedPIDs`, full-screen it if wanted. Found (b): full-screen that window if wanted (no pid tracking);
  - nothing: log "Web app <bundle id> didn't open; check the browser" and call a new `onLaunchFailed(itemID)` callback, which `AppRouter` turns into the tile's shake.
  - `WindowFullScreener` gains `makeFullScreen(window: AXUIElement)` and `findWindow(pid:titlePrefix:) -> AXUIElement?`.
  - The full-screen task already started on the dead pid just times out (harmless); cancel it if convenient.
- **L19. No new screens for the editor's learn state in the router.** All of it lives in `SettingsModel` (pages) + `SettingsEnvironment.setButtonLearning`.
- **L20. Settings row ids and titles** for new rows are listed in step 5 and step 11; keep them, tests use them.
- **L21. The home screen scrolls** (fixes the current bug: tile rows are laid on a fixed 1080-point canvas from y 486, so a third row is drawn off screen and can't be reached by scrolling).
  - Fixed row pitch: the tile title gets a fixed height `Theme.tileTitleHeight = 36` (`.frame(height:)`, still hidden when unfocused), so a row is `tileSize.height (180) + 24 + 36 = 240` tall and rows are `Theme.tileRowPitch = 240 + Theme.rowSpacing (72) = 312` apart.
  - Pure `nonisolated enum HomeLayout`: `rowTop(_ row: Int) -> CGFloat = canvas.height × rowsTopFraction + row × tileRowPitch`; `scrollOffset(focusedRow: Int) -> CGFloat` = `0` for rows 0 and 1, else `rowTop(row) + 240 + Theme.homeBottomMargin (40) − 1080` (the focused row sits at the bottom with rows above it visible). No hysteresis; a deterministic offset per row.
  - `HomeView` offsets the tile rows **and the top shelf** by `−scrollOffset` (animated with `Theme.focusAnimation`); the clock stays put. The shelf's opacity is `max(0, 1 − offset / 200)`. When the focus is in the shelf, the focused row is 0, so the offset is 0.
  - **Mouse wheel** (only on the home screen): `InputRouter`'s local monitor also watches `.scrollWheel` and calls `onScrollWheel?(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)`; `AppRouter.scrollWheel(deltaY:precise:)` accumulates and moves focus one row (as `.up`/`.down`) per 40 points (precise trackpad) or per 1 line (wheel), resetting the accumulator after 0.3 s without events. Other screens ignore it (Settings' list already scrolls natively).
  - Hover keeps working for whatever is on screen; tiles scrolled off can't be hovered (reach them with the wheel or the keys).
- **L23. Web app start page** (user request 2026-10-06, Google Meet):
  - `LaunchItem.startURL: URL?` (Optional so older files decode; stored as nil when unset), only used when the tile is a **web app** (`webAppInfo` finds `CrAppModeShortcutID`). Hand-editable: `"startURL": "https://meet.google.com/home?calling=1"` in `launch-items.json`.
  - **Launch with a start page:** find the browser with `NSWorkspace.urlForApplication(withBundleIdentifier: CrBundleIdentifier)`, then `openApplication(at: browserURL, configuration:)` with `createsNewApplicationInstance = true`, `activates = true` and `arguments = WebApp.launchArguments(appID:startURL:)` = `["--app-id=<id>", "--app-launch-url-for-shortcuts-menu-item=<url.absoluteString>"]`. The returned process is the short-lived forwarding instance: **don't track its pid**. Then wait for the web app's own window exactly as L18's search does ((a) a running app with the tile's bundle ID and a standard window, else (b) a browser window titled with the app name), up to 10 s; track/full-screen what is found, else `onLaunchFailed` (shake).
  - The `LaunchCancellation` (Home during a launch) uses the **tile's** bundle ID, so Home still cancels the web app coming forward.
  - Without `startURL`, web apps launch as today (L18).
  - **Settings**, tile page, web app tiles only, after "Open Full Screen": row `tile.startURL` "Start Page", value = the URL's host + path (+ "?" + query), cut to 48 characters with "…" (no secrets expected, but don't log it: logs show the host only), or "App's Own" when unset; detail "Copy a page address on this Mac or your iPhone, then select"; action `.pasteTileStartURL(id:)`. When set, a second row `tile.startURL.clear` "Use the App's Own Start Page" → `.clearTileStartURL(id:)`.
  - Paste rules: reuse `ClipboardURL.parse` (http/https); additionally the host must equal the host of the app's `CrAppModeShortcutURL`, else the row's detail shows "Use a page on <host>" (a page outside the app's site would open in a browser tab instead). The error shows as the row's detail like `pasteMessage` (clear it on push/pop).
  - `SettingsEnvironment` gains `webAppInfo: (LaunchItem) -> WebAppInfo?` (to know whether to show the rows and the allowed host) and `pasteURL: () -> Result<URL, ClipboardURL.Problem>` (reads the clipboard; tests fake it). `LaunchItem+Editing` gains `settingStartURL(_:id:)`.
- **L22. Channel Up direction is a setting** (user choice 2026-10-06): `settings.json` key **`channelUpMovesUpList`** (Bool, default **true**: Channel Up = `zap(-1)`, up the list, like the Up arrow; false: Channel Up = `zap(+1)`, the higher channel number). Channel Down is always the opposite. It affects zapping in the player and in a Multiview window only, never list paging.
  - Settings root, section "Remote & Input", after "Remote Buttons": row `channelUp` "Channel Up", value **"Up the List"** / **"Higher Number"**, detail "Changes channel in Live TV", action `.toggle(.channelUpMovesUpList)` (a new `SettingKey`; this row shows its own value instead of On/Off). Applied live.
  - `LiveTVModel.channelUpMovesUpList: Bool` (`@ObservationIgnored var`, default true). `AppDelegate` sets it at launch and in `applySettings`.

### Key types

```swift
// Input/RemoteCommand.swift
nonisolated enum RemoteCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case up, down, left, right, select, back, home, playPause, fastForward, rewind
    case menu, channelUp, channelDown          // M7 (D27); keep this order (CaseIterable order = Settings order)

    /// Settings → Remote Buttons.
    var title: String   // "Up", "Down", "Left", "Right", "Select", "Back", "Home", "Play/Pause",
                        // "Fast Forward", "Rewind", "Menu", "Channel Up", "Channel Down"
}

// Input/InputBinding.swift
nonisolated enum ControllerButton: String, Codable, Hashable, Sendable, CaseIterable {
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case a, b, x, y, leftShoulder, rightShoulder, menu, options, home
    case leftTrigger, rightTrigger            // M7
}
extension InputBinding.Trigger {
    /// L9: key codes equal and modifier sets equal; otherwise ==.
    func matches(_ other: InputBinding.Trigger) -> Bool
    /// Key modifiers sorted in KeyModifier.allCases order, duplicates removed.
    var normalized: InputBinding.Trigger { get }
}

// Input/KeyBindings.swift (additions)
extension KeyBindings {
    static let currentRevision = 2
    /// Appends each default binding of `commands` whose trigger matches no existing binding. Order: defaults' order.
    func addingDefaults(for commands: Set<RemoteCommand>) -> KeyBindings
}

// Input/KeyBindings+Editing.swift
nonisolated extension KeyBindings {
    static let essentialCommands: Set<RemoteCommand> = [.up, .down, .left, .right, .select, .back]
    /// In file order.
    func bindings(for command: RemoteCommand) -> [InputBinding]
    /// The first binding whose trigger matches.
    func binding(matching trigger: InputBinding.Trigger) -> InputBinding?
    /// L8: removes every matching binding, appends {trigger.normalized, command, isGlobal: command == .home,
    /// label: TriggerName.describe(trigger)}.
    func adding(_ trigger: InputBinding.Trigger, for command: RemoteCommand) -> KeyBindings
    /// Removes every binding matching `trigger`.
    func removing(_ trigger: InputBinding.Trigger) -> KeyBindings
    /// Sets isGlobal on every binding matching `trigger`.
    func settingGlobal(_ isGlobal: Bool, for trigger: InputBinding.Trigger) -> KeyBindings
    /// L10.
    func canRemove(_ trigger: InputBinding.Trigger) -> Bool
}

// Input/TriggerName.swift
nonisolated enum TriggerName {
    /// "Page Up", "⌥⇧ F5", "Media Play/Pause", "Controller A", "Controller Left Trigger", "Key 200".
    /// Modifiers as symbols in ⌃⌥⇧⌘ order, then a space, then the key name.
    static func describe(_ trigger: InputBinding.Trigger) -> String
    /// "Keyboard", "Media key", "Game controller".
    static func kind(_ trigger: InputBinding.Trigger) -> String
    /// Table from Carbon kVK_* codes: letters/digits/punctuation (US names, e.g. "A", "1", "-"),
    /// Return, Tab, Space, Delete, Escape, Forward Delete, Home, End, Page Up, Page Down, arrows (← → ↓ ↑),
    /// F1…F20, keypad ("Keypad 1", "Keypad Enter", …), Menu key (110), Help, Caps Lock, volume keys.
    static func keyName(_ code: UInt16) -> String?
}

// Input/InputRouter.swift (additions)
@ObservationIgnored var captureHandler: ((InputBinding.Trigger) -> Void)?
/// L8: nil handler or MMTVL inactive → false. Otherwise calls the handler once and returns true (consume).
@discardableResult func capture(_ trigger: InputBinding.Trigger) -> Bool

// Launcher/TileArt.swift
enum TileArt: Equatable {
    case picture(NSImage)                         // L3
    case gradient(top: Color, bottom: Color, symbol: String)   // L4 built-in
    case icon(NSImage)                            // L4 apps
}
@Observable final class TileArtStore {
    static var defaultDirectory: URL { LaunchItemStore.defaultDirectory.appending(path: "tile-art", directoryHint: .isDirectory) }
    init(directory: URL = TileArtStore.defaultDirectory)
    /// Custom picture name for the Settings row, e.g. "plex.png"; nil when none.
    func customFileName(for itemID: String) -> String?
    func art(for item: LaunchItem, icon: NSImage?) -> TileArt
    /// L3: re-lists the folder; reloads changed files. Creates the folder if missing.
    func reloadIfChanged()
    /// Pure, for tests: the file chosen for an id among names in the folder.
    nonisolated static func fileName(for itemID: String, in names: [String]) -> String?
}

// Launcher/TopShelf.swift
nonisolated struct ShelfCard: Identifiable, Equatable, Sendable {
    enum Image: Equatable, Sendable {
        case channelLogo(URL?)
        /// Fetched by ShelfImageLoader with these headers (Plex token); the URL holds no secret.
        case remote(URL, headers: [String: String])
    }
    enum Action: Equatable, Sendable { case playChannel(Channel.ID), openTile(id: String) }
    var id: String
    var title: String
    var subtitle: String
    var image: Image
    /// 0…1.
    var progress: Double?
    var action: Action
}
nonisolated enum ShelfContent: Equatable, Sendable {
    case banner
    case cards(title: String, [ShelfCard])
    var cards: [ShelfCard] { get }   // [] for .banner
}
protocol TopShelfProviding: AnyObject {
    func content(for item: LaunchItem) -> ShelfContent
    /// The home screen appeared or a tile got focus; implementations refresh what is stale.
    func refresh(focusing item: LaunchItem?)
}
final class NoTopShelf: TopShelfProviding { /* always .banner; refresh does nothing */ }
@Observable final class TopShelfModel: TopShelfProviding {
    init(library: IPTVLibrary, plex: PlexAccount, now: @escaping () -> Date = Date.init)
    private(set) var liveCards: [ShelfCard]
    // Plex cards come from plex.continueWatching.
}

// Launcher/AppRouter.swift (additions)
struct FocusMotion: Equatable { var direction: RemoteCommand?; var generation = 0 }
private(set) var focusMotion = FocusMotion()
/// nil = tiles; index into the focused tile's shelf cards.
private(set) var shelfIndex: Int?
@ObservationIgnored let topShelf: any TopShelfProviding    // init param, default NoTopShelf()
func openLiveTV(channelID: Channel.ID?)
func hoverShelfCard(_ index: Int)
func activateShelfCard(_ index: Int)

// IPTV/LiveTVModel.swift
protocol LiveTVHosting: AnyObject {
    func open(channelID: Channel.ID?)   // replaces open(); nil = M4/M6 behavior
    func leave()
    func handle(_ command: RemoteCommand) -> LiveTVOutcome
}

// Plex/PlexAPI.swift (pure, nonisolated)
enum PlexAPI {
    struct ClientInfo: Sendable { var identifier: String; var version: String; var deviceName: String; var platformVersion: String }
    struct PIN: Decodable, Equatable, Sendable { var id: Int; var code: String; var expiresAt: Date?; var authToken: String? }
    struct Resource: Decodable, Equatable, Sendable {
        struct Connection: Decodable, Equatable, Sendable { var uri: String; var local: Bool; var relay: Bool; var `protocol`: String }
        var name: String; var provides: String; var clientIdentifier: String; var accessToken: String?
        var owned: Bool?; var presence: Bool?; var connections: [Connection]
        var isServer: Bool { provides.split(separator: ",").contains("server") }
    }
    struct Metadata: Decodable, Equatable, Sendable {
        var ratingKey: String?; var type: String?; var title: String?; var grandparentTitle: String?
        var parentIndex: Int?; var index: Int?; var year: Int?
        var thumb: String?; var art: String?; var grandparentThumb: String?; var grandparentArt: String?
        var viewOffset: Int?; var duration: Int?
    }
    static func headers(_ client: ClientInfo, token: String?) -> [String: String]
    static func createPINRequest(_ client: ClientInfo) -> URLRequest            // POST https://plex.tv/api/v2/pins
    static func checkPINRequest(id: Int, _ client: ClientInfo) -> URLRequest    // GET  …/pins/{id}
    static func resourcesRequest(token: String, _ client: ClientInfo) -> URLRequest
    static func identityRequest(connection: URL) -> URLRequest                   // GET {uri}/identity, 4 s
    static func continueWatchingRequest(server: URL, token: String, _ client: ClientInfo, flat: Bool) -> URLRequest
    static func imageURL(server: URL, path: String, width: Int, height: Int) -> URL   // /photo/:/transcode…
    static func decodePIN(_ data: Data) throws -> PIN                 // ISO 8601 dates
    static func decodeResources(_ data: Data) throws -> [Resource]
    static func decodeIdentity(_ data: Data) throws -> String         // machineIdentifier
    /// Hub form (home.continue, else the first hub) or flat form.
    static func decodeContinueWatching(_ data: Data) throws -> [Metadata]
    static func linkURL(code: String) -> String                       // "https://plex.tv/link/?pin=<code>"
    /// L14: card lines and image path.
    static func card(_ item: Metadata) -> (title: String, subtitle: String, imagePath: String?, progress: Double?)
}

// Plex/PlexNetwork.swift
nonisolated struct PlexNetwork: Sendable {
    /// Returns body and HTTP status (no throw on non-2xx). Throws on transport errors.
    var send: @Sendable (URLRequest) async throws -> (Data, Int)
    static let live: PlexNetwork   // ephemeral URLSession, like IPTVNetwork
}

// Plex/PlexAccount.swift
@Observable final class PlexAccount {
    enum Status: Equatable { case signedOut, linking, noServer, connecting, connected, unreachable, localNetworkDenied, signInAgain }
    private(set) var status: Status
    private(set) var linkCode: String?
    private(set) var servers: [PlexAPI.Resource]          // after sign-in
    private(set) var serverName: String?
    private(set) var continueWatching: [ShelfCard]
    init(network: PlexNetwork, configFile: JSONConfigFile<PlexConfig>, tokens: PlexTokenStore, client: PlexAPI.ClientInfo? = nil)
    func setLinking(_ active: Bool)                      // L15: true while .plexLink shows
    func chooseServer(id: String) async
    func signOut()
    func refreshIfStale(maxAge: Duration) async          // L14
    var imageHeaders: [String: String] { get }           // X-Plex-Token for ShelfImageLoader
    @ObservationIgnored var onChange: (() -> Void)?      // Settings refreshStatus
}
nonisolated struct PlexTokenStore: Sendable {            // like PINStore: .keychain and .inMemory() for tests
    var userToken: () -> String?; var setUserToken: (String?) -> Void
    var serverToken: () -> String?; var setServerToken: (String?) -> Void
}
```

### Settings changes

New pages, in `SettingsPage` (all `Hashable`/`Sendable`; `InputBinding.Trigger` already is):

```swift
case remoteButtons, remoteCommand(RemoteCommand), remoteBinding(RemoteCommand, InputBinding.Trigger)
case learnButton(RemoteCommand), confirmLearn(RemoteCommand, InputBinding.Trigger), confirmRestoreButtons
case plex, plexLink, plexServers, confirmPlexSignOut
```

New actions: `startLearning(RemoteCommand)`, `useLearned(RemoteCommand, InputBinding.Trigger)`, `removeBinding(InputBinding.Trigger)`, `toggleBindingGlobal(InputBinding.Trigger)`, `restoreDefaultButtons`, `choosePlexServer(id: String)`, `signOutOfPlex`.

New `SettingsEnvironment` members:

```swift
/// Apply to InputRouter + save key-bindings.json.
var applyBindings: (KeyBindings) -> Void
/// L8: non-nil while learning; nil stops.
var setButtonLearning: ((@escaping (InputBinding.Trigger) -> Void)?) -> Void
var plexStatus: () -> PlexSettingsStatus
var setPlexLinking: (Bool) -> Void
var choosePlexServer: (String) -> Void
var signOutOfPlex: () -> Void
/// L3: e.g. "plex.png", nil when none.
var tileArtFileName: (String) -> String?
```

`PlexSettingsStatus` (in `SettingsTypes.swift`): `isSignedIn`, `linkCode: String?`, `linkURL: String?`, `serverName: String?`, `servers: [(id, name, detail)]` as a struct array, `statusLine: String`, `itemCount: Int`.

`SettingsModel.init` gains `bindings: KeyBindings = .defaults` (default keeps test call sites compiling); `private(set) var bindings`.

## Implementation steps

Ordered; the project must build and the existing tests pass after every step. Run the full test command after steps 2, 5, 9, 12 and 16; the touched suites after the others.

- [x] **1. Home screen rows scroll (bug fix)**: `Launcher/HomeLayout.swift` (new), `Launcher/HomeView.swift`, `Launcher/AppTileView.swift`, `Launcher/AppRouter.swift`, `Input/InputRouter.swift`, `App/AppDelegate.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/HomeLayoutTests.swift` (new), `MMTVLTests/AppRouterTests.swift`
  - L21. Theme: `tileTitleHeight = 36`, `tileRowPitch` (computed: `tileSize.height + 24 + tileTitleHeight + rowSpacing`), `homeBottomMargin = 40`, `homeScrollStep: CGFloat = 40`. Use `24` from a new token `tileTitleSpacing` in `AppTileView`'s `VStack(spacing:)` so the pitch has one source.
  - `HomeView`: wrap the rows `VStack` (and, from step 8, the shelf) in an `.offset(y: -HomeLayout.scrollOffset(focusedRow: focus.position.row))` with `.animation(Theme.focusAnimation, value: focus.position.row)`. Clip nothing (the canvas clips at the window edge already; check that the rows don't draw over the clock: if they do, add `.zIndex(1)` to the clock and a top gradient fade behind it).
  - Mouse wheel per L21: `InputRouter.onScrollWheel` (local monitor matches `.scrollWheel` too; return the event untouched), wired in `AppDelegate` to `router.scrollWheel(deltaY:precise:)`. Scroll direction: positive `scrollingDeltaY` (content moves down, natural scrolling) → focus **up**.
  - Tests: `HomeLayout.scrollOffset` for rows 0–4 (0, 0, 310, 622, 934 with the tokens above: `486 + 2×312 + 240 + 40 − 1080 = 310`); router wheel accumulation (two 25-point precise deltas move one row; a 1-line wheel delta moves one row; deltas on another screen do nothing).
  - Done when: tests pass; on the Mac (windowed), with 3+ rows of tiles, moving focus down scrolls the rows so the focused row is fully visible, moving back to row 0/1 returns to the top, and the mouse wheel moves focus between rows. The user's Settings tile on the third row is reachable.

- [x] **2. New commands everywhere (neutral) + defaults + migration**: `Input/RemoteCommand.swift`, `Input/InputBinding.swift`, `Input/KeyBindings.swift`, `Input/ControllerInput.swift`, `Input/ExternalKeyMap.swift`, `App/AppSettings.swift`, `App/AppDelegate.swift`, every file with an exhaustive `RemoteCommand` switch (see *Research → This codebase*), `MMTVLTests/KeyBindingsTests.swift`, `MMTVLTests/AppSettingsTests.swift`
  - Add `menu, channelUp, channelDown` and `title` (L5 names). Add `leftTrigger, rightTrigger` to `ControllerButton` (and make it `CaseIterable`); bind `gamepad.leftTrigger`/`rightTrigger` in `ControllerInput.configure` and clear them in `unconfigure`.
  - Make every exhaustive switch compile with **no behavior yet** for the new cases: treat them like `.playPause` is treated in that switch where "not handled" (`return false` / `.none` / `.ignored` / `nil`). Exceptions already final in this step: `YouTubeKeyMap.keyCode` → nil for all three (L5); `ExternalKeyMap.key`: channelUp → `.key(kVK_PageUp)`, channelDown → `.key(kVK_PageDown)`, menu → nil; `AppRouter.route` `.youtube` already consumes everything (unchanged).
  - `KeyBindings.defaultBindings`: append L7's seven bindings. Add `currentRevision = 2` and `addingDefaults(for:)`. Add `Trigger.matches(_:)` and `normalized` (L9) — `addingDefaults` uses `matches`.
  - `AppSettings.keyBindingsRevision`: property default `KeyBindings.currentRevision`; `init(from:)` decodes a missing key as **1**.
  - `AppDelegate`: keep the bindings file in a property `bindingsFile: JSONConfigFile<[InputBinding]>`. After loading settings and bindings, run L7's migration (save both files; log "Added default buttons for Menu and Channel Up/Down").
  - Tests: defaults contain the seven new bindings and no duplicate triggers; `addingDefaults` adds only unbound triggers and is idempotent; `matches` ignores modifier order; `AppSettings` without the key decodes revision 1, `AppSettings()` has 2.
  - Done when: it builds, all tests pass, and launching with an old `key-bindings.json` (copy of the defaults before this step) adds the seven bindings once (check the file, relaunch, check no duplicates).

- [x] **3. Behavior of the new commands**: `IPTV/LiveTVModel.swift`, `IPTV/Guide/GuideModel.swift`, `IPTV/LiveMenu.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, `App/AppSettings.swift`, `App/AppDelegate.swift`, `RemoteServer/Web/remote.html/.css/.js`, `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/LiveTVModelTests.swift`, `MMTVLTests/GuideModelTests.swift`, `MMTVLTests/LiveMenuTests.swift`, `MMTVLTests/MultiviewLiveTVTests.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Implement L5's table.
    - `GuideModel`: new `Action` is not needed — Menu returns the existing `.channelMenu(focusedChannel.id)` from `.grid` and `.channel` focus. Channel Up/Down move `row` by ∓`visibleRows` (clamped) and `keepRowVisible()`; in `.groups` focus move the group focus by ∓6 (clamped).
    - `LiveMenu.handle`: `.menu` → `.close`; `.channelUp/.channelDown` → move focus by ∓`visibleRows` (clamped), same window logic as Up/Down.
    - `LiveTVModel.handlePlayer`: `.menu` → `menu = channelMenu(for: currentChannel.id)` when there is a current channel; `.channelUp` → `zap(channelUpMovesUpList ? -1 : 1)`; `.channelDown` → the opposite (L22). `handleGuide` forwards to `GuideModel` as today (the `.channelMenu` action path already opens the channel menu in the watch guide and assigns in the picker; **in the picker, Menu must do nothing**: check `guidePurpose` and ignore `.menu` before forwarding).
    - `handleMultiview`: `.menu` → as `.select` on a filled window only; `.channelUp/.channelDown` → L6 (`zapWindow(_ step: Int)`, new private), with the same L22 direction.
    - L22's setting: `AppSettings.channelUpMovesUpList` (tolerant decode, default true), `SettingKey.channelUpMovesUpList`, the root row, `LiveTVModel.channelUpMovesUpList` wired in `AppDelegate` (launch + `applySettings`). Tests: both directions in the player and in Multiview; the row's value text; decoding a file without the key gives true.
    - `SettingsModel.handle`: `.channelUp/.channelDown` → `ListFocus.move(…, by: ∓8)`; `.menu` → `return false`.
  - Phone page: add a row with **CH−**, **Menu**, **CH+** buttons (`data-command="channelDown"`, `"menu"`, `"channelUp"`; CH± with `data-repeat`) under the D-pad's Back/Home/Play row. Labels "CH −", "☰", "CH +" (use `&#xFE0E;` text presentation like the others), `aria-label`s "Channel down", "Menu", "Channel up". Keep the current button style; check the page still fits a 390 × 760 viewport without scrolling (reduce `.row` gap if needed). The server already accepts any `RemoteCommand` raw value.
  - Tests: each row of L5's table for Live TV (player, guide watch/picker, Multiview zapping skips channels in other windows, menu close/page), Settings paging.
  - Done when: tests pass; with `-windowed YES`, Tab in the player opens the channel menu, Page Up zaps up the list (and down the list after switching Settings → Channel Up to Higher Number), and the phone shows the three buttons and they work.

- [x] **4. Trigger names, editing helpers and capture**: `Input/TriggerName.swift` (new), `Input/KeyBindings+Editing.swift` (new), `Input/InputRouter.swift`, `Input/GlobalEventTap.swift`, `Input/ControllerInput.swift`, `MMTVLTests/TriggerNameTests.swift` (new), `MMTVLTests/KeyBindingsEditingTests.swift` (new)
  - `TriggerName` per *Key types*. Build the key table from `Events.h` (copy the `kVK_*` names; US layout names). Unknown codes → "Key <code>". Media: "Media Play/Pause", "Media Next", "Media Previous", "Media Fast Forward", "Media Rewind". Controller: "Controller " + a readable name ("D-pad Up", "A", "Left Shoulder", "Left Trigger", "Menu", "Options", "Home").
  - `KeyBindings+Editing` per *Key types* and L8–L11.
  - Capture (L8):
    - `InputRouter`: `captureHandler`, `capture(_:)`. In the local monitor, **before** binding lookup: keyDown → if `captureHandler != nil`: if the event has ⌘ → return the event (pass through); if `event.isARepeat` → swallow (return nil); else `capture(.key(keyCode, modifiers sorted))` and swallow. systemDefined → if capturing and it parses as a media key: on non-repeat key down `capture(.media(key))`; swallow down and up.
    - `GlobalEventTap.decide`: at the top of `.key` and `.media`, if `inputRouter.captureHandler != nil && NSApp.isActive`: same rules, but the capture call goes through `DispatchQueue.main.async` (like dispatch) and the event is consumed (return true), except ⌘ keys (return false).
    - `ControllerInput.buttonChanged`: on press, `if inputRouter.capture(.controller(button)) { stopRepeat(); return }`.
    - `capture` clears nothing itself; the Settings model stops learning by setting the handler to nil (step 5).
  - Tests: names for a dozen codes incl. modifiers ("⌥⇧ F5"), unknown code, media, controller; editing: `adding` moves a trigger from another command and normalizes modifiers; `removing` removes all duplicates; `canRemove` false for the last Select, true for the last Home and for a second Select; `settingGlobal`; `bindings(for:)` order. `capture` returns false without a handler.
  - Done when: tests pass. (Capture is exercised in step 5.)

- [x] **5. Settings → Remote Buttons**: `Settings/SettingsTypes.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsEnvironment.swift`, `App/AppDelegate.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsRemoteButtonsTests.swift` (new)
  - Root page, section "Remote & Input": insert after "Game Controllers": row `remoteButtons` "Remote Buttons", disclosure, `.push(.remoteButtons)`.
  - `.remoteButtons` page (title "Remote Buttons", image `.symbol("appletvremote.gen4")`): section "Commands": one row per `RemoteCommand.allCases`: id `command.<raw>`, title `command.title`, value = names of its first two bindings joined by " · " plus " +N" when more (no bindings: "None"), disclosure, `.push(.remoteCommand(c))`. Section "manage": `restoreButtons` "Restore Default Buttons" → `.push(.confirmRestoreButtons)`. Footer: "Buttons apply at once. Phone remote buttons can't be changed."
  - `.remoteCommand(c)` page (title `c.title`): section "Buttons": one row per binding (`bindings(for: c)`): id `binding.<index>` (index in that list), title `TriggerName.describe`, detail `TriggerName.kind` (+ " · Works in other apps" when `isGlobal`), disclosure, `.push(.remoteBinding(c, trigger))`. Empty: info row `binding.none` "No buttons". Then row `learn` "Add a Button" → `.startLearning(c)`. Footer for Home: "Home buttons can work in other apps too (needs Accessibility)."; for essential commands: "Keep at least one button for \(c.title)."
  - `.remoteBinding(c, t)` page (title `TriggerName.describe(t)`): when `c == .home`: row `binding.global` "Works in Other Apps" value On/Off → `.toggleBindingGlobal(t)`, detail "Needs Accessibility access" when not trusted. Row `binding.remove` "Remove Button" → `.removeBinding(t)` (pops after), or, when `!canRemove(t)`, an info row `binding.cantRemove` "The last button for \(c.title) can't be removed".
  - `.learnButton(c)` page (title "Press a Button", image `.symbol("hand.point.up.left")`): info row `learn.prompt` title "Press the button to use for \(c.title)", detail "On the remote, a keyboard or a game controller. Waits 10 seconds."; row `learn.cancel` "Cancel" → `.pop`. Hint "Waiting for a button…".
  - Learning: `syncLearning()` (called wherever `syncPairing()` is: push, pop, reset, `screenDidClose`) sets `environment.setButtonLearning(handler)` exactly while `.learnButton` is on top; the handler calls `learned(_:)` (main actor). `learned(trigger)` replaces the top page with `.confirmLearn(c, trigger)` (pop + push), records `learnConfirmShownAt = now`. A timeout `Task` started on entering `.learnButton` (cancelled on leaving) pops after `learnTimeout` (default 10 s; a settable `@ObservationIgnored var`) and sets the command page's message "No button pressed" (show it as the `learn` row's detail until the next push/pop, like `pasteMessage`).
  - `.confirmLearn(c, t)` page (title "Use \(describe(t)) for \(c.title)?"): rows `confirm.use` "Use This Button" (detail "Now used for X; it moves to \(c.title)" when `binding(matching: t)` exists for another command; "Already used for \(c.title)" when the same), `confirm.retry` "Try Again" → `.startLearning(c)` (replaces this page with `.learnButton(c)`), `confirm.cancel` "Cancel" → `.pop`. **Select is ignored for 0.6 s** after the page appeared (L8; use an injectable `now` closure on the model for tests, default `Date.init`).
  - `.useLearned(c, t)`: `bindings = bindings.adding(t, for: c)`, `environment.applyBindings(bindings)`, pop, focus the new binding's row.
  - `.confirmRestoreButtons`: rows Cancel / "Restore Defaults" (`.restoreDefaultButtons` → `KeyBindings.defaults`, apply, pop). Footer "Replaces every button with the defaults."
  - `AppDelegate`: `applyBindings` sets `inputRouter.bindings` and saves `bindingsFile` (log errors); `setButtonLearning` sets `inputRouter.captureHandler` (wrap the handler so it runs on the main actor). Pass `bindings` into `SettingsModel`.
  - Tests (fake environment captures the handler): open learn page → handler set; invoking it → confirm page; Select before 0.6 s ignored, after → binding added and applied; Back on learn page → handler cleared; timeout pops with message; Try Again; remove/can't remove rows; Home global toggle; restore; Home (router `goHome`) clears the handler.
  - Done when: tests pass; with `-windowed YES` on the Mac: add F5 to Select, press F5 on the home screen → selects; ⌘Q during learning quits MMTVL; the change survives a relaunch (`key-bindings.json` has it).

- [x] **6. Parallax focus effect**: `DesignSystem/ParallaxFocus.swift` (new), `DesignSystem/Theme.swift`, `Launcher/AppTileView.swift`, `Launcher/HomeView.swift`, `Launcher/AppRouter.swift`, `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/ParallaxTests.swift` (new)
  - `ParallaxFocus` as a `ViewModifier` + `View.parallaxFocus(isFocused:motion:cornerRadius:foregroundOffset:)` per L1. Split pure math into `nonisolated enum ParallaxMath { static func nudge(for direction: RemoteCommand) -> CGSize; static func tilt(hover: CGPoint, in size: CGSize) -> CGSize; static func specularCenter(tilt: CGSize) -> UnitPoint }` for tests.
  - `AppRouter`: `focusMotion` (L2): bump in the `.home` arrow case when `focus.move` returned true, and on Select.
  - `AppTileView`: replace the scale/shadow block with `.parallaxFocus(…)`; keep the shake keyframes **outside** (after) the parallax so they still offset the whole tile. Foreground layer offset: pass a binding/value so the artwork's icon uses `tilt × parallaxLayerOffset` (expose tilt to the content through a closure `content(tilt)` or an environment value `\.parallaxTilt`; the environment value is simplest).
  - Theme: `parallaxMaxDegrees = 7`, `parallaxLayerOffset: CGFloat = 8`, `parallaxNudgeAmount = 0.6`, `parallaxSpring = Animation.spring(response: 0.45, dampingFraction: 0.55)`, `specularOpacity = 0.35`, `pressScale = 0.95`.
  - Tests: `ParallaxMath` values; router bumps `focusMotion` on a moving arrow and not on a blocked one.
  - Done when: on the Mac (windowed), moving focus tilts and settles, the shine moves, mouse hover tilts, Reduce Motion turns tilt off; no visible stutter.

- [x] **7. Tile art**: `Launcher/TileArt.swift` (new), `Launcher/TileArtView.swift` (new), `Launcher/AppTileView.swift`, `Launcher/HomeView.swift`, `Launcher/AppRouter.swift`, `DesignSystem/Theme.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsEnvironment.swift`, `App/AppDelegate.swift`, `MMTVLTests/TileArtTests.swift` (new), `MMTVLTests/SettingsTestSupport.swift`
  - `TileArtStore` per L3 (pure `fileName(for:in:)`: case-insensitive match of `<id>.png|jpg|jpeg|heic` in that priority). `art(for:icon:)` per L4. Keep the store on `AppRouter` (`let tileArt: TileArtStore`, an init param; `AppDelegate` passes `TileArtStore()`, and `AppRouterTests` pass a store on an empty temporary directory so tests never read the real folder). Call `reloadIfChanged()` in `goHome()` and once at init.
  - `TileArtView(art:, tilt:)` draws the three kinds at the tile size, clipped to the rounded rect. `AppTileView` uses it; "Not installed" overlay stays.
  - Settings tile page: info row `tile.art` per L3 (`environment.tileArtFileName(id)`).
  - Theme: gradient colors (L4), `tileIconBackdropBlur = 40`, `tileIconBackdropScale = 2.2`, `tileArtMaxPixels = 1500`.
  - Tests: file choice priority and case-insensitivity; `reloadIfChanged` picks up a new file and a removed one (temp dir); built-in item → gradient; app with icon → icon art.
  - Done when: putting `plex.png` in the folder and going Home shows it on the Plex tile; removing it brings the icon art back; built-ins show gradients.

- [x] **8. Top shelf frame (banners, focus)**: `Launcher/TopShelf.swift` (new), `Launcher/TopShelfView.swift` (new), `Launcher/HomeView.swift`, `Launcher/AppRouter.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/FakeTopShelf.swift` (new)
  - Types per *Key types*; `NoTopShelf`. `AppRouter` takes `topShelf: any TopShelfProviding = NoTopShelf()` (last init param). Implement L12's focus rules in `route(.home)`: `shelfIndex`, entering on Up from row 0 when `content(for: focusedItem).cards` isn't empty, Left/Right/Down/Back/Select in the shelf. Call `topShelf.refresh(focusing:)` on focus change and in `goHome()`.
  - `HomeView`: draws `TopShelfView` in the region `y 0 … Theme.shelfHeight (440)` behind the clock. Banner: the focused tile's `TileArtView` at 1920 × 440 (`scaledToFill`, `.blur(radius: 30)` for icon art only), with a bottom gradient into the background and the tile title at bottom-left (`Theme.shelfTitleFont`). Cards: title at x 120, y 96 (`Theme.shelfTitleFont`, secondary), a horizontal row of `Theme.shelfCardSize` (352 × 198) cards with 40 pt spacing at y 140, captions under each card (two lines, `Theme.shelfCaptionFont` / `shelfDetailFont`), progress bar 4 pt. `ScrollViewReader` keeps the focused card visible. Cards use `.parallaxFocus`. While the shelf has focus the owner tile drops its focus scale (pass `isFocused: focus.index == index && shelfIndex == nil`).
  - Crossfade the shelf when the focused tile changes (`.animation(.easeInOut(duration: 0.25), value: focusedItemID)`).
  - Theme: `shelfHeight = 440`, `shelfCardSize = CGSize(width: 352, height: 198)`, `shelfCardSpacing = 40`, `shelfTitleFont = .system(size: 30, weight: .semibold)`, `shelfCaptionFont = .system(size: 24, weight: .medium)`, `shelfDetailFont = .system(size: 20)`, `shelfProgressHeight = 4`.
  - `FakeTopShelf` (tests): returns configured content per item id.
  - Tests (router): Up from row 0 enters only with cards; Down/Back return; Left/Right clamp; Select on `.playChannel` calls Live TV `open(channelID:)` (fake), `.openTile` activates that tile (PIN asked when set); PIN-protected owner never enters; content shrinking clamps / exits.
  - Done when: tests pass; every tile shows a banner on the Mac.

- [x] **9. Live TV shelf**: `IPTV/IPTVState.swift`, `IPTV/IPTVLibrary.swift`, `IPTV/LiveTVModel.swift`, `Launcher/TopShelf.swift`, `Launcher/AppRouter.swift`, `App/AppDelegate.swift`, `MMTVLTests/FakeLiveTV.swift`, `MMTVLTests/LiveTVModelTests.swift`, `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/TopShelfModelTests.swift` (new)
  - `IPTVState.recentChannelIDs` (tolerant decode → `[]`); `rememberChannel` moves the id to the front, max 10 (save even when it's already `lastChannelID` but not first).
  - `LiveTVHosting.open(channelID:)` replaces `open()`; update `AppRouter.openLiveTV()` → `openLiveTV(channelID: nil)` and callers, `FakeLiveTV` (record the ids). In `LiveTVModel.open(channelID:)`, after the playlist check: if `channelID` names a loaded channel, mark an active Multiview snapshot inactive (as the existing inactive branch does) and `play(channel)`; else the current logic.
  - `TopShelfModel` (Live TV half): L13; a 60 s refresh `Task` runs while `refresh` has been called within the last 2 min (cancel otherwise) — simpler: `refresh(focusing:)` reloads Live TV cards if older than 60 s; `HomeView` calls `router.topShelf.refresh(focusing:)` from a `TimelineView(.everyMinute)` tick. Cards: id `live.<channel id>`, action `.playChannel`. Content for the Live TV tile (`kind == .internalDestination(.iptv)`): `.cards(title: "On Now", liveCards)` when non-empty, else `.banner`.
  - Make the model generic enough to test: inject `nowNext: (Channel) async -> (Programme?, Programme?)` and `channels: () -> (lineup: ChannelLineup, recent: [String])` closures in a `LiveShelfSource` struct instead of `IPTVLibrary` directly (the app builds it from the library).
  - Wire in `AppDelegate`: `TopShelfModel` created after `iptvLibrary`; passed to `AppRouter`.
  - Tests: favorites first, recents fallback (hidden channels skipped), max 10, "25 min left" text, progress, banner without playlist; `open(channelID:)` plays it and deactivates an active Multiview snapshot; recents order/max.
  - Done when: tests pass; on the Mac, Live TV's shelf shows favorites with what's on, Select plays the channel.

- [x] **10. Plex API (pure)**: `Plex/PlexAPI.swift` (new), `Plex/PlexNetwork.swift` (new), `MMTVLTests/PlexAPITests.swift` (new), `MMTVLTests/Fixtures` as inline JSON strings in the test file
  - Everything in *Key types* for `PlexAPI` and `PlexNetwork`. Requests: `timeoutInterval` 10 s (identity 4 s); `Accept: application/json`; `X-Plex-*` headers from `ClientInfo` (*Research → Headers*); `X-Plex-Token` header only when a token is given. `createPINRequest` POSTs to `https://plex.tv/api/v2/pins` with no body and no `strong` parameter. `resourcesRequest` uses `https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=0`. `continueWatchingRequest(flat: false)` → `/hubs/continueWatching?count=12`, `flat: true` → `/hubs/continueWatching/items?X-Plex-Container-Size=12` (put the size in the header `X-Plex-Container-Size` instead, and `X-Plex-Container-Start: 0`). `imageURL` builds `/photo/:/transcode?width=704&height=396&minSize=1&upscale=1&url=<path>` with `URLComponents` (percent-encodes the path).
  - Decoders: `JSONDecoder` with `.iso8601` dates for PINs (fall back to nil when the date doesn't parse: decode `expiresAt` as String and parse with `ISO8601DateFormatter` allowing fractional seconds). Every `Metadata` field optional. Resources: tolerate missing `connections` (→ `[]`).
  - `card(_:)` per L14.
  - Tests with inline fixtures shaped like *Research*: PIN with/without token; resources filtering (`isServer`), connection fields; continue-watching hub form picks `home.continue`, flat form; card lines for an episode and a movie; image URL encoding; headers contain the client id and no token when nil.
  - Done when: tests pass.

- [x] **11. Plex account + Settings → Plex**: `Plex/PlexConfig.swift` (new), `Plex/PlexAccount.swift` (new), `Settings/*`, `App/AppDelegate.swift`, `MMTVL.xcodeproj/project.pbxproj` (build setting only), `MMTVLTests/PlexAccountTests.swift` (new), `MMTVLTests/SettingsPlexTests.swift` (new), `MMTVLTests/SettingsTestSupport.swift`
  - `PlexConfig` (Codable, tolerant decoding) and `PlexTokenStore` (`.keychain`: accounts `plex-token`, `plex-server-token`; `.inMemory()`).
  - `PlexAccount` per L15/L16/L17 with an injected `PlexNetwork` and `sleep: (Duration) async -> Void` (tests pass an immediate one) for the 1 s poll. States: start `signedOut` if no user token, else `connecting` and `refreshIfStale` on first use. 401 from the server or plex.tv user check → `signInAgain` (keep tokens until Sign Out). URLError `.notConnectedToInternet`/`.cannotConnectToHost` on every connection → `unreachable`. A failure code that looks like Local Network denial (`URLError` with underlying `NSPOSIXErrorDomain` 65 "No route to host" / 1 "EPERM" — **unverified**, check on the Mac) → `localNetworkDenied`.
  - `continueWatching` → `[ShelfCard]` (id `plex.<ratingKey>`, image `.remote(imageURL, headers: [X-Plex-Token])`, action `.openTile(id: <owner tile id>)` — the account doesn't know tiles: use a placeholder id `"plex"` and let `TopShelfModel` rewrite the action to the actual owner tile's id).
  - Settings: root page gets section "Plex" (after YouTube): row `plex` "Plex", value "Signed In" / "Not Signed In", disclosure → `.plex`. Pages per L15 with row ids: `.plex`: `plex.signIn`, `plex.server`, `plex.status`, `plex.signOut`; `.plexLink`: `plexLink.code` (title "Code", value the code or "…"), `plexLink.where` (title "plex.tv/link", detail "On a phone or computer, open plex.tv/link and enter the code, or scan the QR code"), `plexLink.cancel`; side image = QR of `PlexAPI.linkURL(code:)`; `.plexServers`: `plexServer.<id>` rows (value "Selected" for the chosen one) → `.choosePlexServer(id)`; `.confirmPlexSignOut`: Cancel / "Sign Out" (`.signOutOfPlex`). `syncPlexLink()` next to `syncPairing()`.
  - `AppDelegate`: create `PlexAccount` (`ClientInfo` from `plex.json`'s `clientIdentifier`, created and saved on first launch; version from the bundle; device name `Host.current().localizedName ?? "Mac"`; platform version `ProcessInfo.processInfo.operatingSystemVersionString`). `onChange` → `router.settings.refreshStatus()`.
  - Build setting (L17): add `INFOPLIST_KEY_NSLocalNetworkUsageDescription = "MMTVL connects to your Plex Media Server on this network.";` to the app target's **Debug and Release** configurations (next to `INFOPLIST_KEY_CFBundleDisplayName`). Verify: `plutil -p build/Build/Products/Debug/MMTVL.app/Contents/Info.plist | grep NSLocalNetwork`.
  - Tests: link flow (PIN created, polling until token, new PIN on 404, stops when `setLinking(false)`), server choice (1 server auto, several listed owned first), connection order (local https first, http/relay skipped, `lastConnection` first next time), 401 → `signInAgain`, sign out clears tokens and keeps `clientIdentifier`; Settings rows per state.
  - Done when: tests pass; on the Mac: Settings → Plex → Sign In shows a code and QR; entering it at plex.tv/link signs in; the server is chosen; Status shows "Connected · N items". Record the real `Metadata` fields seen (log the field **names** of the first item once at debug level, never values with tokens) and fix the decoder if needed.

- [x] **12. Plex shelf + images**: `Launcher/ShelfImageLoader.swift` (new), `Launcher/TopShelf.swift`, `Launcher/TopShelfView.swift`, `App/AppDelegate.swift`, `MMTVLTests/TopShelfModelTests.swift`, `MMTVLTests/ShelfImageLoaderTests.swift` (new)
  - `ShelfImageLoader` (`@Observable`, main actor): `image(for: ShelfCard.Image) -> NSImage?` returns a cached image or starts one fetch (ephemeral `URLSession`, headers applied, downsample to 704 px wide), keyed by URL string; at most 60 entries (drop oldest). Failed fetches are remembered for 5 min (no retry storm). `.channelLogo` keeps `AsyncImage`.
  - `TopShelfModel`: content for the Plex tile (`kind == .application(bundleID: "tv.plex.htpc")`): `.cards(title: "Continue Watching", cards with action .openTile(id: item.id))` when non-empty and the item isn't PIN-protected, else `.banner`. `refresh(focusing:)` calls `plex.refreshIfStale(maxAge: .seconds(120))` in a Task.
  - Tests: Plex content mapping (owner id rewrite, banner when empty), loader caches and limits (inject a fake fetch closure).
  - Done when: tests pass; the Plex tile's shelf shows Continue Watching with art; Select launches Plex HTPC full screen.

- [x] **13. Chromium web app tiles: safety net and start page**: `Launcher/AppLauncher.swift`, `Launcher/WindowFullScreener.swift`, `Launcher/AppRouter.swift` (sets `launcher.onLaunchFailed` in `init` to bump that tile's shake trigger), `MMTVLTests/AppLauncherTests.swift`
  - L18. Detection: `nonisolated struct WebAppInfo: Equatable, Sendable { var appID: String; var name: String; var startURL: URL?; var browserBundleID: String }` and `nonisolated enum WebApp { static func info(bundleURL: URL) -> WebAppInfo?; static func launchArguments(appID: String, startURL: URL) -> [String] }`, reading `CrAppModeShortcutID`, `CrAppModeShortcutName`, `CrAppModeShortcutURL`, `CrBundleIdentifier` from `Bundle(url:)?.infoDictionary` (pure; testable with a temp bundle containing an Info.plist). `AppLauncher.webAppInfo(for: LaunchItem) -> WebAppInfo?` resolves the tile's bundle URL first.
  - L23: `LaunchItem.startURL`, the start-page launch path, the Settings rows (`Settings/SettingsTypes.swift`, `SettingsModel.swift`, `SettingsModel+Pages.swift`, `SettingsEnvironment.swift`, `App/AppDelegate.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsModelTests.swift`, `MMTVLTests/LaunchItemEditingTests.swift`, `MMTVLTests/LaunchItemStoreTests.swift`).
  - `launch(_:)` and `applicationDidTerminate` for web apps: as L18. Log with the bundle id only.
  - Keep the pure part testable: `nonisolated struct WebAppHandoff { static let quickQuit: TimeInterval = 5; static func isHandoff(launchedAt: Date, quitAt: Date) -> Bool }`.
  - **Manual check (with the user):** the YouTube Music and Google Photos tiles open full screen and MMTVL stays behind them (healthy path). To exercise the safety net, quit Brave entirely first and launch the tile (the shim may hand off while Brave starts); record what happened in *Deviations*.
  - Tests: `WebApp.info` on a fake bundle; a normal app has none; `launchArguments`; `isHandoff` boundaries; `LaunchItem` decodes without `startURL` and round-trips with it; Settings rows shown only for web apps, paste accepted for the app's host and refused for another host, clear.
  - **Manual check for L23 (with the user):** paste `https://meet.google.com/home?calling=1` on the Google Meet tile; the tile opens Meet on the calling screen, full screen, (1) with Brave running, (2) with Brave quit, (3) with Meet already open. Record (2) and (3) in *Deviations*; if a cold start ignores the page, fall back to launching Brave first, waiting until it runs, then the `-n` launch.
  - Done when: both web app tiles open full screen and MMTVL doesn't jump back; a web app whose browser can't open shakes its tile within ~15 s; the Meet tile lands on the calling screen.

- [ ] **14. Kiosk check on the TV (with the user)**: no files
  - Kiosk mode on the Mac mini (or the dev Mac in kiosk mode): parallax smoothness at 4K (no dropped frames visible while moving focus quickly), shelf legibility from the couch, the new buttons on the actual remote (or keyboard), learning a remote button, Plex shelf. Record problems in *Deviations*; small token tweaks (sizes, colors, timings) are allowed here without asking.
  - Done when: the user has seen it and agreed, or the list of issues is recorded.

- [x] **15. Docs wrap-up**: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - CLAUDE.md: `key-bindings.json` is now edited in Settings → Remote Buttons (hand edits only with MMTVL quit; `keyBindingsRevision` in `settings.json`); new commands `menu`, `channelUp`, `channelDown` and controller `leftTrigger`/`rightTrigger`; `settings.json` `channelUpMovesUpList` (default true: Channel Up = up the list like the Up arrow); `tile-art/` folder; `launch-items.json` `startURL` for web app tiles (L23); `plex.json` and the Keychain accounts `plex-token`/`plex-server-token` with the `security delete-generic-password` reset lines; never log Plex tokens/codes; a `log stream` line for category `Plex`; `NSLocalNetworkUsageDescription`.
  - Master plan: M7 → Done; check D16, D27, D28 and §5 (planning already added `Plex/`, the top shelf, D27/D28) still match what was built; resolve Q12.
  - Done when: docs match the code.

- [x] **16. Full test run**: no files
  - `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`.
  - Done when: all tests pass.

## Addendum (2026-10-06): designed app art, Tile Art picker, Liquid Glass

User request after steps 1–16: (1) art for app tiles that MMTVL ships with (user chose "bundled artwork" over hand-placed pictures, keeping custom pictures); (2) browse and choose a tile's art from Settings; (3) the tvOS 26/27 **Liquid Glass** look. User choices (2026-10-06): glass **everywhere** (home, Settings, Live TV, PIN); the top shelf becomes **full-screen art** behind the tiles, as on tvOS 26/27; Settings picks pictures from **Mac folders** (no phone upload).

### Research (2026-10-06)

- No public source for tvOS (5:3) app icons: the iTunes Lookup/Search API returns the square iOS icon only (`appletvScreenshotUrls` empty for Plex), and apps.apple.com pages carry only square `AppIcon` variants (all four on Plex's page are 1024×1024). The tvOS icon is only in Apple's private `amp-api` (needs a web token). Not used.
- tvOS 26/27: layered Liquid Glass app icons with specular highlights; the Top Shelf art fills the screen behind the icon rows; sidebars, Top Shelf and Control Center are glass; Reduce Transparency removes the see-through ([Wikipedia: Liquid Glass](https://en.wikipedia.org/wiki/Liquid_Glass), [Geeky Gadgets: tvOS 27](https://www.geeky-gadgets.com/tvos-27-rc-release-features/), [MacStories](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/4)).
- macOS 26 SDK (checked in `SwiftUICore.swiftinterface`): `View.glassEffect(_ glass: Glass = .regular, in: some Shape)`, `Glass.regular/.clear/.identity`, `.tint(_:)`, `.interactive(_:)`, `GlassEffectContainer`, `glassEffectID`/`glassEffectUnion`, `.buttonStyle(.glass)`. Available at our deployment target (26.0).
- `~/Downloads` and `~/Desktop` are protected folders (TCC): the first listing asks for permission; `~/Pictures` isn't (except the Photos library package, which is skipped).

### Local decisions

- **L24. Designed app art ("option 2")** is drawn by MMTVL, not shipped as logo files: `AppArtCatalog` (pure) maps a tile to a brand style, a two-color diagonal gradient, and the foreground is the app's **own installed icon** (a parallax layer with a glass rim), else an SF Symbol. Known styles (bundle id, or `webapp:<CrAppModeShortcutID>` for Chromium web apps in any browser): Plex `#2D2A26 → #0B0A09` (accent ring `#E5A00D`), Prime Video `#00A8E1 → #0F171E`, Brave `#FB542B → #2B0F0A`, Safari `#1E90FF → #0A2A5C`, Chrome `#4285F4 → #0D2B6B`, FaceTime `#34C759 → #0B4D22`, YouTube Music (`webapp:cinhimbnkkaeohfgghhklpknlkffjgod`) `#FF0033 → #1A0006`, Google Photos (`webapp:ncmjhecbjeaamljdfahankockkkdmedg`) `#4285F4 → #0F9D58`, Google Meet (`webapp:kjgfgldnnfoeklkmfkjfagphfepbbdan`) `#00897B → #0B3D35`. Built-ins keep L4's gradients. **Any other app** gets colors from its icon: the average of its opaque, not-near-white/black pixels (32 × 32 sample), as `top = that color at 0.9 brightness`, `bottom = 0.25 brightness` (pure `IconPalette.colors(fromRGBA:width:height:)`, tested).
  - Art order: custom picture (L3) → the tile's **art style**: `designed` (default) or `icon` (L4's blurred icon backdrop). `LaunchItem.artStyle: String?` (`"designed"` | `"icon"`; nil = designed; unknown = designed).
- **L25. Settings → tile → Tile Art** (`.tileArt(id)`, from a `tile.art` row that becomes a disclosure row). Sections: "Style": `art.designed` "Designed", `art.icon` "App Icon" (apps only), value "Selected" on the current one; "Your Picture" (when one is set): `art.custom` info "<file name>" + `art.removeCustom` "Remove Picture" (deletes every `<id>.*` in `tile-art/`); "Pictures on This Mac": up to 40 newest images (png, jpg, jpeg, heic) directly in `~/Downloads`, `~/Pictures`, `~/Desktop` (no recursion, no packages, no hidden files), rows `art.file.<n>` title file name, detail "Downloads · Oct 6", a small thumbnail. Select copies the file to `tile-art/<id>.<ext lowercased>` after removing the tile's other pictures, reloads the store, shows "Selected" on it. The side column previews the **focused** option at tile size (`RowImage.tileArt(id, TileArtChoice)`, drawn with `TileArtView`). Listing runs when the page opens (background), "Looking for pictures…" meanwhile; none → info row "No pictures in Downloads, Pictures or Desktop". Footer: "You can also put a 5:3 picture named <id>.png in …/MMTVL/tile-art." `NSDownloadsFolderUsageDescription` and `NSDesktopFolderUsageDescription` ("MMTVL lists pictures here so you can use one as tile art.").
- **L26. Glass system** (`DesignSystem/Glass.swift`): `.glassPanel(cornerRadius:)` = `glassEffect(.regular, in: RoundedRectangle)`; `.glassRim(cornerRadius:isFocused:)` = a 1.5-pt stroke with a white gradient (top 0.55 → middle 0.08 → bottom 0.25; focused: brighter) plus a soft top sheen; with **Reduce Transparency** (`\.accessibilityReduceTransparency`) panels fall back to `Theme.solidPanelFill` (`#1C1C1E` at 0.92) and rims stay. Tokens in `Theme` (`glassCornerRadius` etc.).
- **L27. Full-screen top shelf** (replaces step 8's 440-pt banner): the focused tile's art fills the 1920 × 1080 canvas behind everything (picture: fill; designed: its gradient with the icon large and blurred-soft on the right third; icon style: the blurred icon), with a scrim: black 0 → 0.75 from y 45 % to the bottom, and 0.35 at the top-right behind the clock. Crossfades (0.35 s) when the focused tile changes. Cards (On Now, Continue Watching) keep their place (title y 96, cards y 140) over the art, on glass captions. Scrolling (L21) fades the art to the plain background with the same rule as before. The banner's tile title is dropped (the focused tile shows its title).
- **L28. Glass everywhere:** tiles and shelf cards get `glassRim`; the clock sits on a small glass capsule; Settings: the list sits in one glass panel, the focused row stays a bright white platter (legibility from the couch), the side image on glass; Live TV: banner, timeshift bar, Multiview chips, guide info box and channel menus on `glassPanel`; PIN keypad and Accessibility onboarding card on `glassPanel`. Video under glass is checked on the TV (step 14) for smoothness.

### Steps (addendum)

- [x] **17. Designed app art**: `Launcher/AppArtCatalog.swift` (new: brand table, `IconPalette`), `Launcher/TileArt.swift`, `Launcher/TileArtView.swift`, `Launcher/LaunchItem.swift`, `Launcher/LaunchItem+Editing.swift`, `MMTVLTests/TileArtTests.swift`, `MMTVLTests/AppArtCatalogTests.swift` (new)
  - `TileArt.designed(top:bottom:icon:symbol:)`; `TileArtStore.art(for:icon:webAppID:)` per L24; `LaunchItem.artStyle` + `settingArtStyle`.
  - Tests: catalog lookups (bundle id, web app id in another browser), palette from synthetic pixels (ignores white/black/transparent), art order (custom > icon style > designed), old items decode.
- [x] **18. Settings → Tile Art**: `Settings/*`, `Launcher/TileArt.swift` (copy/remove pictures), `Launcher/PictureFinder.swift` (new, pure listing + date label), `App/AppDelegate.swift`, `project.pbxproj` (two `INFOPLIST_KEY_*` folder usage descriptions), `MMTVLTests/SettingsTileArtTests.swift` (new), `MMTVLTests/PictureFinderTests.swift` (new)
  - Tests: rows per state, Select style saves `artStyle`, Select picture copies (fake environment), remove, listing order/limit/filters on a temp folder.
- [x] **19. Glass system + rims**: `DesignSystem/Glass.swift` (new), `DesignSystem/Theme.swift`, `Launcher/AppTileView.swift`, `Launcher/TopShelfView.swift`, `Launcher/HomeView.swift` (clock capsule)
- [x] **20. Full-screen top shelf**: `Launcher/TopShelfView.swift`, `Launcher/HomeView.swift`, `DesignSystem/Theme.swift`
- [x] **21. Glass everywhere**: `Settings/SettingsView.swift`, `Settings/SettingsRowView.swift`, `IPTV/LiveTVView.swift`, `IPTV/LiveMenuView.swift`, `IPTV/Guide/GuideView.swift`, `IPTV/Multiview/MultiviewView.swift`, `PIN/PINEntryView.swift`, `Launcher/AccessibilityOnboardingView.swift`
- [x] **22. Docs + full test run**: `CLAUDE.md` (art styles, Tile Art page, folder permissions, glass), master plan D29.
  - Manual (with step 14): designed art for each app tile, Tile Art page picks a Downloads picture (permission prompt), glass legibility on the TV, Reduce Transparency, video smoothness under glass panels.


## Tests

| File | Asserts |
|---|---|
| `KeyBindingsTests` (changed) | New defaults, no duplicate triggers, `addingDefaults` idempotent, `matches`. |
| `AppSettingsTests` (changed) | `keyBindingsRevision` missing → 1, fresh → 2, round-trip. |
| `KeyBindingsEditingTests` (new) | `adding` (moves, normalizes, isGlobal for Home), `removing`, `settingGlobal`, `canRemove`, `bindings(for:)`. |
| `TriggerNameTests` (new) | Key names with modifiers, unknown code, media, controller, kind. |
| `GuideModelTests`, `LiveMenuTests`, `LiveTVModelTests`, `MultiviewLiveTVTests` (changed) | L5 table, L6 window zapping, `open(channelID:)`. |
| `SettingsModelTests` (changed) | Paging with Channel Up/Down; Menu not handled. |
| `SettingsRemoteButtonsTests` (new) | Pages, learn flow, timeout, confirm delay, remove rules, restore, handler cleared on leave. |
| `ParallaxTests` (new) | `ParallaxMath`. |
| `AppRouterTests` (changed) | `focusMotion`, shelf focus rules, shelf actions, PIN owner. |
| `TileArtTests` (new) | File choice, reload, art kinds. |
| `IPTVLibraryTests` (changed) | `recentChannelIDs`. |
| `TopShelfModelTests` (new) | Live TV cards (favorites, recents, texts, progress), Plex mapping. |
| `PlexAPITests` (new) | Requests, headers, decoders, cards, image URL. |
| `PlexAccountTests` (new) | Link flow, server choice, connections, 401, sign out. |
| `SettingsPlexTests` (new) | Plex rows per state, link page sync. |
| `ShelfImageLoaderTests` (new) | Cache, limit, failure memory. |
| `AppLauncherTests` (changed) | `webAppInfo`. |

Run the suites touched in a step with `-only-testing:'MMTVLTests/<Suite>'`; the full run after steps 2, 5, 9, 12 and 16 (CLAUDE.md commands).

## Manual verification

- [ ] Three or more rows of tiles: every row is reachable with the arrows and the mouse wheel; the focused row is fully visible; back on the first rows the layout returns to the top.
- [ ] Old `key-bindings.json`: the seven new bindings appear once after the first launch; removing Menu's bindings in Settings survives a relaunch (not re-added).
- [ ] Remote Buttons: learn a key, a media key and a controller button; a key already used elsewhere moves (the confirm row says so); ⌘Q quits during learning; the phone's Back cancels learning; the last Select can't be removed; Restore Default Buttons.
- [ ] Learn a button on the real remote (or a Flirc) when available (Q1).
- [ ] Live TV: Menu in the player opens the channel menu; CH+ zaps up the list (like Up) and CH− down; after Settings → Channel Up → Higher Number, CH+ goes to the higher number; in the guide, Menu opens the channel menu, CH± page; in Multiview, CH± change the highlighted window's channel skipping ones already shown, Menu opens the window menu.
- [ ] Phone: CH−, Menu, CH+ work in MMTVL; CH± send Page Up/Down to Plex/the browser.
- [ ] Parallax: tilt/settle on moves, shine, mouse tilt, press, Reduce Motion off/on.
- [ ] Tile art: a custom picture appears after going Home; built-in gradients; icon art for apps.
- [ ] Top shelf: banners for every tile; Live TV "On Now" cards (favorites; with no favorites, recents); Up/Left/Right/Down/Back/Select; a card opens Live TV on that channel, leaving Multiview.
- [ ] Plex: sign in with the code and with the QR code; Local Network prompt allowed; Continue Watching cards with art and progress; Select opens Plex HTPC; Sign Out empties the shelf; a stopped server shows "Can't reach the server" and the banner.
- [ ] Web app tiles (YouTube Music, Google Photos) open full screen and stay.
- [ ] The Google Meet tile with its start page opens on the calling screen (Brave running, Brave quit, Meet already open).

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| `rotation3DEffect` + blur on 4K drops frames | Stutter when moving focus fast (step 14) | `.drawingGroup()` on the tile, lower `parallaxMaxDegrees`, drop the icon backdrop blur for a pre-blurred cached image (render once with `ImageRenderer`). |
| Local monitor sees a remote's key only as key-up or with odd modifiers | Learning never completes for that button | Log at debug what the monitor saw (code + modifiers only while learning); hand-edit `key-bindings.json` as before. |
| Event tap captures don't reach the main actor in time / double capture | Two confirm pages | `capture` returns false once the handler is nil; the model ignores a second `learned` while not on `.learnButton`. |
| Plex PIN flow retired (docs call it legacy) | `POST /pins` fails or the code isn't accepted at plex.tv/link | Implement the JWT flow (`clients.plex.tv/api/v2/pins` with an Ed25519 key, `MyPlexJWTLogin` in python-plexapi) as a follow-up; record in *Deviations*. |
| `plex.direct` names blocked by DNS-rebinding protection | Every connection fails, status "Can't reach the server" | Add a partial Info.plist (`INFOPLIST_FILE`) with `NSAppTransportSecurity.NSAllowsLocalNetworking = true` and allow local http connections (record a deviation; ask the user). |
| Local Network denied | All LAN connections fail with EPERM/no route | Status row text tells the user; System Settings → Privacy & Security → Local Network → MMTVL. |
| Continue Watching JSON differs | Empty shelf with a signed-in account | Fall back to `/hubs/continueWatching/items`; adjust decoder from the logged field names. |
| A web app window can't be found (title differs) | Shake after 10 s although it opened | Match by the browser's newest window created after the launch instead of the title; record the case. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-10-06, steps 1 and 6 (small fix, no stop):** `HomeLayout` and `ParallaxMath` are main-actor `enum`s, not `nonisolated`: it reads `Theme` tokens, which are main-actor isolated (Swift 6 rejects the access). Still pure; tests run on the main actor. The scroll accumulator also resets when the wheel changes direction (not in L21; avoids a stale remainder).
- **2026-10-06, step 3 (small fix, no stop):** the channel menu opened by Menu in the **player** includes *Match Guide*, but `LiveTVModel` only opened the match menu in guide mode, so it did nothing. The guard now also allows `.player`. *Hide Channel* from the player hides the playing channel and keeps it playing (as hiding does elsewhere).
- **2026-10-06, step 5 (small fix, no stop):** `SettingsEnvironment.setButtonLearning` is `(((InputBinding.Trigger) -> Void)?) -> Void`: Swift rejects `@escaping` inside an Optional (an optional closure is already escaping).
- **2026-10-06, step 8 (small reorder, no stop):** `LiveTVHosting.open(channelID:)` (and `LiveTVModel.open(channelID:)`, `FakeLiveTV.openedChannelIDs`) landed in step 8, not step 9, because step 8's router test for a `.playChannel` card needs it. The router caches "a PIN is set" (`hasPINCache`, refreshed at init, on going home and after PIN flows) so the shelf doesn't read the Keychain on every render. The banner for **icon** art is the icon scaled to fill and blurred (30), not `TileArtView`'s 2.2× backdrop at 1920 wide (cheaper at that size).
- **2026-10-06, step 11 (small additions, no stop):** `SettingsEnvironment.refreshPlex` (L17's "opening the Plex page retries": pushing `.plex` starts `PlexAccount.startRefresh`). `PlexAPI.userRequest` for the plex.tv token check (*Research*), run once per launch on the first refresh. `PlexAccount.Status.noServer` means "signed in, no server chosen" (none on the account, or several to choose from); `PlexSettingsStatus` gains `hasNoServer` and `needsServerChoice` so the link page knows whether to show the server list or say there's none. Choosing a server on `.plexServers` pops back to `.plex`. `PlexAccount.statusLine` adds "Choose a server", "Connecting…", "Waiting for the code…".
- **2026-10-06, step 12 (no stop):** the router (not `TopShelfModel`) turns a PIN-protected tile's shelf into a banner (L12 needs "a PIN is set", which the router knows), so `TopShelfModel` doesn't check `requiresPIN`. The `ShelfImageLoader` instance lives on `AppRouter` (`shelfImages`) and reaches `TopShelfView` through `HomeView`. `PlexAccount.onChange` also calls `router.shelfContentChanged()`.
- **2026-10-06, steps 1–16 (status):** ticked steps mark the code and automated tests (631 tests pass after step 16). Each step's on-Mac part of "done when" is still open in *Manual verification*. Step 14 (kiosk check on the TV) needs the user. So M7 stays **In progress** here and in the master plan until step 14 and the manual checks are done; Q12 (Plex PIN flow, `plex.direct` behind the router) is still open until the first real sign-in. Already seen on the dev Mac: the first launch of a step-2 build migrated the real `key-bindings.json` once (26 → 33 bindings, `keyBindingsRevision` 2 in `settings.json`).
- **2026-10-06, step 15 (no stop):** the parallax keyframe content closure is `@Sendable` in SwiftUI, so the per-frame rendering moved into a small `ParallaxRender` modifier fed plain values (no Swift 6 isolation warnings).
- **2026-10-06, addendum steps 17–22 (no stop):** built as planned; 648 tests pass. Not seen on screen yet (the user was running an Xcode build, so no second instance was started): the glass panels, rims and full-screen backdrop need a look on the Mac and the TV (with step 14). The designed art is the runtime-drawn style of L24 (no image files). The Settings tile's page now has two rows (Tile Art, Move); `settingsTileCanOnlyMove` expects both.
