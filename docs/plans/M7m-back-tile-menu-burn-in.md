# M7m — Live TV Back, the home tile menu, burn-in guards

| | |
|---|---|
| Status | Planned |
| Depends on | M7c (Live TV keys L11, the start tile L32, the home preview D37), M6 (Multiview), M7h (Siri Remote long press D43, power menu D45), M7l (the glass, My Teams) |
| Master plan decisions used | D14 (sound follows the highlight), D20 (PIN), D35 (foregrounding), D36 (kiosk lock), D37 (home preview), D43 (Siri Remote); new **D49** (Back never leaves Live TV), **D50** (home tile menu), **D51** (burn-in guards) |
| Planned | 2026-11-08 |

## Next session starts here

- **Next step:** step 1 (the MM probes, `[human]`) can run in parallel with steps 2–5 and 8–11; step 7 waits for step 1's answers.
- **Read:** this plan's *Design* and the step's own text; `CLAUDE.md` (build and test commands); the files the step names.
- **Verify:** `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test` from the repo root, and quote the result line.

## Goal

The user's findings (2026-11-08):

1. "live TV remove the back button from exiting to the home screen. Only the tv button takes you home. When in the guide the back button should keep going back to menu and eventually back to the live channel that is active"
2. "long press tile on home screen let's you reorder, quit app and restart, and other options"
3. "need to avoid the possibility of burn in as much as possible from static content especially on live tv in multiview. the audio icon on the active main screen isn't necessary since there is an indicator with the outline that it is active. What else can we do for the outline or other alternatives to indicate which box is active and to limit burn in"

The TV is a **Panasonic TC-P55VT50, a plasma** (CLAUDE.md, M7h), so anything that stays still on screen is a burn-in risk.

On the TV, when this is done:

- **Back never leaves Live TV.** From the player, Back hides the banner, else opens the guide. In the guide, Back closes the group list, then returns to the **channel that is playing**, full screen. In a submenu (Match Guide, Layout), Back goes to the menu that opened it. Search, Choose Teams, Multiview and the picker step back as they do now. When nothing plays (first open, no channel yet; Live TV not set up; a playlist that failed; loading), Back does nothing. **Only Home (the TV button) goes home.**
- **Holding Select on a home tile** (the Siri Remote's centre held 0.6 s; also Menu on the phone, Tab or the Menu key, a controller's Y) opens a **tile menu** over the home screen, titled with the tile's name: **Move**, **Quit *name*** and **Restart *name*** (while the app runs), **Reload YouTube** (the YouTube tile), **Hide from Home Screen**, **Start Here**, **Open Full Screen** On/Off, **Require PIN** On/Off and **Tile Settings…**. With a PIN set, the edits (Move, Hide, Start Here, the two toggles, Tile Settings) ask for it first; Quit, Restart and Reload never do.
- **Move** lifts the tile, which wiggles. The arrows move it through the grid (Left/Right one place, Up/Down one row), and Select or Back drops it there. The new order is saved to `launch-items.json`, as Settings → Home Screen saves it.
- **Multiview:** the speaker icon is gone. After any button press the focused window has today's bold white outline. 5 s later it fades to a **thin, faint outline** on the window with sound, which stays. When focus is on another window than the one with sound (an empty window), the bold outline is on the focused one and the thin one stays on the window with sound. The "Add Channel" and "Can't play this channel" text fades with the bold outline.
- **Paused:** the timeshift bar, the behind-live badge and Multiview's pause symbol fade **15 s** after the pause or the last press (Select shows them again).
- **The guide goes back to the channel:** after **3 minutes** in Live TV's guide, a Live TV menu, search or Choose Teams with no press, while a channel plays, MMTVL returns to that channel full screen (Multiview: back to Multiview).
- **Still screens dim, then the screen saver starts:** after **5 minutes** with no press on a screen where nothing moves (the home screen, Settings, paused or failed video, the guide with nothing playing, the PIN and power menu screens), MMTVL fades to dark. After **5 more minutes** it starts the **macOS screen saver**. Any press brings MMTVL back and does nothing else, except Power, the power menu and volume, which also act.

## Out of scope

- Back elsewhere (YouTube, Settings): unchanged.
- A setting for the idle times or to turn the dimmer off (they're `Theme` tokens; a setting can follow if wanted).
- Right-click on a tile with the mouse, and held Select on a keyboard or controller (they'd need key-up / hold tracking in `InputRouter` and `ControllerInput`). Those inputs use their Menu binding (Tab, the Menu key, Y).
- Pixel-shifting MMTVL's own picture. The TV's **Pixel Orbiter** does that (step 1 checks it's on).
- Grey bars in Multiview's unused areas (offered, not chosen, 2026-11-08).
- Dimming over other apps (Plex HTPC, Prime Video, the browser) and over YouTube: MMTVL can't tell whether they're still.
- Removing a tile from the menu (Tile Settings… → Remove does that).

## Research & findings

Paths are under `MMTVL/` unless they start with `MMTVLTests/`, `docs/` or `scripts/`. Line numbers are from `master` at `173dc9c` (M7l merged), checked 2026-11-08.

### 1. Back in Live TV

- **The route:** every source sends the same `RemoteCommand.back` / `.home` (`Input/RemoteCommand.swift:4`): keyboard Escape/Delete (`Input/KeyBindings.swift:26-27`), controller B (`:40`), Siri Remote Back (`:55-56`; TV is `.home`), phone (`RemoteServer/Web/remote.html:49-50`, through `ExternalRouter.route`, `Input/ExternalRouter.swift:30-44`). `AppRouter.handle` (`Launcher/AppRouter.swift:518-553`) → `route`, Live TV case `:627-647`:
  ```swift
  if command == .home { goHome(); return true }   // 628-631: Home never reaches the model
  switch liveTV.handle(command) {
  case .handled: break
  case .leave: goHomeToStartTile()                // 635-637: the only way Back leaves
  case .openSettings: …                           // 638-645
  }
  ```
  `LiveTVOutcome { handled, leave, openSettings }` (`IPTV/LiveTVModel.swift:5`).
- **Every `.leave` from Back** in `LiveTVModel.handle` (`:321-377`):
  - `.setupNeeded`: `case .back: return .leave` (`:357`);
  - `.unavailable`: `case .back: return .leave` (`:365`);
  - `.loading`: `return command == .back ? .leave : .handled` (`:369`);
  - the watch guide: `GuideModel` returns `.close`, and `handleGuide` (`:509-553`) does `return .leave` (`:549`, comment "M7c L11: Back in the watch guide leaves Live TV"); also `guard var guide else { return .leave }` (`:516`, a fallback).
  - `handle(.home)` returns `.leave` (`:322`), but only tests reach it (the router takes Home first).
- **What already steps back (keep):**
  - player: `handlePlayer` (`:465-471`): `if banner != nil || showsTimeshiftBar { hideOverlays() } else { openGuide() }`;
  - `GuideModel` (`IPTV/Guide/GuideModel.swift`): `Focus { grid, channel, groups(Int), search }` (`:10`); groups and the Search row: `.back, .left: focus = .grid; return .none` (`:303-305`, `:325-327`); grid, channel cell, action rows: `.back: return .close` (`:244-245`, `:270-271`, `:351-352`);
  - the picker guide (`.pick`): `closePicker()` (`:545-548`, `:1090-1095`);
  - Multiview: `exitMultiview()` (`:1007-1008`, `:1040-1077`), full screen with the highlighted window; with no window filled, `removeAllWindows()` opens the watch guide (`:1124-1134`);
  - search: results → keyboard → `closeSearch()` (`IPTV/Search/LiveSearchModel.swift:71-97`); Choose Teams: `picker.pop()`, then `closeTeamPicker()` (`:663-699`).
- **Menus close all at once:** `if var menu { … case .close: self.menu = nil }` (`:327-340`). The submenus are opened by `perform`: `.chooseLayout: menu = layoutMenu()` (`:770-771`, from the window menu, `:869`), `.openMatchGuide(id)` (`:802-814`, from the channel menu `:743`, opened asynchronously, guarded by `self.menu == nil`). So Back from Match Guide or Layout closes everything today.
- **Returning to the channel:** `watch(_:)` (`:573-582`): `if channel.id == currentChannel?.id && isPlaying { mode = .player; guide = nil; showBanner() } else { play(channel) }`. `isPlaying` (`:438-440`): `currentChannel != nil && phase != .idle && phase != .failed`.
- **When there's no channel:** first open with no `lastChannelID` (`open`, `:186-190`, test `noLastChannelOpensTheGuide`); `.setupNeeded`/`.unavailable`/`.loading`. After Multiview's last window is removed, `currentChannel` may be stale and the player idle; after a stream error `currentChannel` is set and the phase `.failed` (the player view shows the error panel; Select retries, `:457-458`).
- **Hints to change:** `IPTV/Guide/GuideView.swift:46-66` (`hint(focus:isPicking:row:)`, "Back: leave Live TV" four times); `IPTV/LiveTVView.swift:74` ("Select: open Settings · Back: return"), `:83` ("Select: try again · Back: return"). Already right: `MultiviewView.swift:131` "Back: full screen", `LiveMenuView.swift:22`, `LiveSearchView.swift:31,37`.
- **Tests that assert Back leaves (change):** `MMTVLTests/LiveTVModelTests.swift` `noPlaylistNeedsSetup` (`:29`), `noLastChannelOpensTheGuide` (`:41`), `emptyPlaylistIsUnavailable` (`:59`), `backInTheGuideLeaves` (`:334`); `MultiviewLiveTVTests.swift` `removeWindowsUntilEmpty` (`:675`); `GuideViewHintTests.swift:6-14`. `AppRouterTests` (`backToHomeGoesToTheStartTile` `:141-148`, `leavingLiveTVKeepsTheChannelPlaying` `:607-620`, `withThePreviewOffLeavingLiveTVStopsIt` `:622-631`, `leaveOutcomeGoesHome` `:1126-1133`) use `FakeLiveTV.outcome = .leave` (`FakeLiveTV.swift:10`); the router still handles `.leave`, so they stay valid. Only their Back-based comments change.
- **Old decisions this replaces:** M7c L11 (`docs/plans/archive/M7c-punchlist.md:127`: guide Back "leaves Live TV") and L32 (`:150`). M4's original rule was close to the new one (`docs/plans/archive/M4-live-tv.md:344`: guide Back "back to the player (or leave when nothing plays)"). `CLAUDE.md` "Live TV keys (M7c L11)" and `homeStartTile` ("when Back reaches the home screen") change in the docs step.

### 2. The home tile menu

- **A long press exists only on the Siri Remote, and it's already `menu`:** `Input/SiriRemote/SiriRemoteGestures.swift:9` `centreLongPress = 0.6`; the centre doesn't send on press (`:60-63`); `tick()` sends the long press while still held, once (`:135-138`); `longPressEvent` (`:116-119`): `.select: isTrackpadMode ? .click(.right) : .command(.menu, isRepeat: false)`. Tests `SiriRemoteGesturesTests.swift` (`longCentreSendsMenuOnceAndNoSelect` `:32`).
- **Other sources:** keyboard `Tab` and the Menu key → `.menu` (`KeyBindings.swift:35-36`); no key-up reaches the router (`InputRouter.swift:50-53`, key-down only with `isARepeat`, `:153`). Controller Y → `.menu` (`:39`); A never repeats (`ControllerInput.swift:137-150`). The phone has a Menu button (`remote.html:55`, `data-command="menu"`), and `PhoneRemote.swift:98-104` only drops `power`/`powerMenu`.
- **`.menu` on the home screen does nothing today:** `AppRouter.route` home case (`:587-589`) returns false for it; the shelf too (`routeShelf`, `:510-511`). → L5: the tile menu opens on `.menu`.
- **Home focus:** `LauncherFocusModel` (`Launcher/LauncherFocusModel.swift`), a value type: `init(itemCount:perRow:)` (`:20`), `index` (`:30`), `focus(index:)` (`:37`), `move(_:)` (`:53`). `Theme.tilesPerRow = 6` (`Theme.swift:65`). `AppRouter.items` (all, `:30`), `visibleItems` (`:32`, `:154`), `setItems(_:)` (`:166-180`) keeps focus on the same tile id. The home case of `route` (`:557-590`): Up from row 0 enters the shelf (`:561`), arrows → `focus.move` + `bumpFocusMotion`/`topShelf.refresh`/`syncCarousel` (`:566-574`), Select → `activate(index)` (`:575-580`), Back → start tile (`:581-584`).
- **Views:** `HomeView` (`Launcher/HomeView.swift`), `tile(at:)` (`:175`) builds `AppTileView` (`Launcher/AppTileView.swift`; `isFocused`, a keyframe `shakeTrigger` `:20-26`, no lifted state). Built in `LauncherRootView.content` (`AppRouter.swift:1098-1122`).
- **Pure tile edits:** `Launcher/LaunchItem+Editing.swift` on `[LaunchItem]`: `visible` (`:5`), `movingItem(id:by:)` (`:8`, within the **full** array, hidden ones included), `settingHidden` (`:19`), `settingFullScreen` (`:23`), `settingRequiresPIN` (`:28`). `LaunchItem` (`Launcher/LaunchItem.swift`): kinds `.application(bundleID:)`, `.url(URL, browserBundleID:)`, `.defaultBrowser(fullScreen:)`, `.internalDestination(.youtube/.iptv/.settings)`, `.system(.exitToDesktop)` (`:12-18`); `isSettingsTile` (`:40`), `isExitToDesktop` (`:42`), `isPINProtected` (`:45`), `supportsFullScreen` (`:48`, `.application`/`.defaultBrowser` only), `wantsFullScreen` (`:67`).
- **Settings' tile actions** (`Settings/SettingsModel.swift`, `perform(_:)` `:356`, callable by the router through `router.settings`, `AppRouter.swift:114`): `.setStartTile(id)` (`:364`, visible tiles only, via `environment.applySettings`), `.toggleTileVisible(id)` (`:383`, refuses Settings), `.toggleTileFullScreen(id)` (`:386`), `.toggleTileRequiresPIN(id)` (`:410`, refuses Settings and Exit), `.reloadYouTube` (`environment.reloadYouTube()`). **Don't call** `.startMove` or `.removeTile` from home: they `pop()` the Settings stack (`:389-397`). `SettingsModel` keeps its own `items` copy (`:34`) and `updateItems(_:)` (`:945`) calls `environment.applyItems`, which is `AppDelegate.applyItems` (`App/AppDelegate.swift:1253-1260`: `router?.setItems` + `LaunchItemStore().save`). So home edits that go through `settings.perform` keep both in sync. `tileSections(id:)` (`Settings/SettingsModel+Pages.swift:335`) is the per-tile page; `reset()` (`SettingsModel.swift:174`) sets the stack to the root; `stack: [PageState(page:focusedRowID:)]` (`:7-10`, `:36`); `push` is private (`:848`); `openSettings()` calls `settings.reset()` (`AppRouter.swift:882`).
- **Quit/restart:** `AppLauncher` (`Launcher/AppLauncher.swift`): `launch(_:)` (`:267`) skips apps in `restarting` (`:273`) and calls `onOpened` (`:281`, the kiosk guard's session apps). `restartAfterHotplug = ["tv.plex.htpc"]` (`:154`), waits `restartQuitWait` 5 s, `restartForceWait` 1 s, `restartPoll` 100 ms (`:156-158`). `restartIfMarked` (`:391-415`): insert into `restarting`; for each running app `launchedPIDs.remove(pid)`, drop `webAppLaunches[pid]`, `terminate()`; `waitUntilTerminated(apps, for: 5 s)` (`:418`); then `forceTerminate()` and 1 s more; then open. Seams for tests: `LauncherRunningApp` (`:79`), `LauncherWorkspace` (`:90`: `appURL`, `runningApps`, `openApplication`, `sleep`); `bundleID(for:)` (`:233`, handles the default browser and `url` tiles' browser), `webAppInfo(for:)` (`:262`). No "is running" API yet (inline `workspace.runningApps(bundleID)`, `:291`, `:358`). A tracked pid quitting brings MMTVL forward after 1 s (`applicationDidTerminate`, `:538`, `:564-567`), harmless at home and avoided by removing the pid first. A web app shim quitting within 5 s is treated as a hand-off (`:539-546`); drop `webAppLaunches[pid]` first. Tests: `AppLauncherTests.swift` (`openingAMarkedPlexQuitsItThenLaunchesItAgain` `:276`, `aPlexThatDoesNotQuitIsForceQuitAfterFiveSeconds` `:301`).
- **YouTube reload:** `YouTubeController.reload()` (`YouTube/YouTubeController.swift:130-133`, no-op before the first open); the router's `youtube: any YouTubeHosting` (`AppRouter.swift:115`) protocol (`YouTubeController.swift:6-16`) has no `reload()` yet.
- **Menu UI to copy:** the power menu: `Launcher/PowerMenu.swift` (`PowerMenuAction` `:4` with `needsPIN` `:8`; `struct PowerMenu` `:23`, `Outcome {none, close, choose}` `:30`, `handle` `:46`: Up/Down clamp, Select, Back and Menu close; `choose(index:)` `:62`, `focus(index:)` `:69`), drawn in-view by `LauncherRootView.powerMenuOverlay` (`AppRouter.swift:1006-1022`: `Theme.menuDim` + `PowerMenuView` scaled to the canvas, `Theme.menuFadeAnimation`), router state `powerMenu` (`:107`), `openPowerMenu` (`:668`), `closePowerMenu` (`:676`), `hoverPowerMenuItem` (`:692`), `routePowerMenu` (`:700`), `perform(outcome)` (`:707`, closes before acting so a PIN screen isn't under it). `PowerMenuView` (`Launcher/PowerMenuView.swift`): glass panel `Theme.liveMenuWidth` (720), lock symbol when `hasPIN && needsPIN` (`:44`). `LiveMenu.Item.value` (`IPTV/LiveMenu.swift:32`) shows a right-aligned value ("On").
- **PIN:** `PINPurpose` (`PIN/PINFlow.swift:4-13`): `openSettings, openTile(id:), exitToDesktop, quit, relaunch, restartMac, setNew, change, turnOff`; `PINFlow.submit` (`:36`, exhaustive switch `:48`); titles `PIN/PINEntryModel.swift:29-38`; router `hasPIN` (`:760`), `requestPIN(_:)` (`:763`, remembers `screenBeforePIN`), `finishPIN` (`:787-831`, exhaustive). `activate(_:)` (`:927-943`) asks for protected tiles.
- **tvOS:** holding the clickpad on an app opens its options (Move to…, Delete App); in move mode the app is dragged and a press drops it ([Apple: Customize the Apple TV Home Screen](https://support.apple.com/en-ae/guide/tv/atvbad14dc6a/tvos), [tvOS 17 guide](https://support.apple.com/ur-in/guide/tv/customise-the-home-screen-atvbad14dc6a/17.0/tvos/17.0)). tvOS has no "restart"; it's the user's request.

### 3. Burn-in

- **The TV:** Panasonic plasmas have a **Pixel Orbiter** (Auto or On; not in THX modes) and a **Scrolling Bar** that clears retention, which stops on any key or after ~15 min ([Panasonic support](https://help.na.panasonic.com/answers/does-the-tv-have-a-feature-to-help-reduce-image-retention), [Sound & Vision on the VT50](https://www.soundandvision.com/node/99076), [Sound & Vision, fixing retention](https://www.soundandvision.com/node/98383)). The VT50's own menu path is **unverified** (step 1).
- **Multiview** (`IPTV/Multiview/MultiviewView.swift`, `windowOverlay` `:25-67`): the highlight `if isFocused { Rectangle().strokeBorder(Theme.multiviewFocusBorder, lineWidth: Theme.multiviewFocusBorderWidth) }` (`:62-65`; white, 6 pt, `Theme.swift:398-406`) is **permanent**, also on an empty window, with no animation (the view's animations `:20-21` are keyed on `banner`/`showsTimeshiftBar`). The **speaker badge** (`:47-49`, `:69-83`: `speaker.wave.2.fill`, 20 pt, glass capsule, 12 pt from the top-right) is on `audioSlot` whenever 2+ windows are filled, permanently. The chip (`:58-61`, `:117-140`) shows while `model.banner != nil` (5 s after `nowNext` returns). Also permanent: the pause symbol (`:40-46`, while paused), the failed window's "Can't play this channel" on black 0.6 (`:31-37`), the empty window's plus and "Add Channel" (`:102-115`).
- **Focus vs sound:** `MultiviewModel` (`IPTV/Multiview/MultiviewModel.swift`) `focusedSlot` (`:19`) and `audioSlot: Int?` (`:20-21`). Sound only moves to filled windows (`moveFocus` `:73-78`: `if slots[next] != nil { audioSlot = next }`; `focus` `:81-85`). So with focus on an empty window, the badge is today the only sign of where the sound is. → L13.
- **Single player** (`IPTV/LiveTVView.swift`, `PlayerOverlayView` `:124-203`): the banner fades 5 s after `nowNext` (`showBanner(for:)`, `LiveTVModel.swift:1228-1243`; `overlayDuration = .seconds(5)` `:123`); the timeshift bar 5 s (`showTimeshiftBar()` `:1246-1255`), but the view keeps it **while paused**: `showsTimeshift = model.showsTimeshiftBar || state.phase == .paused` (`LiveTVView.swift:183-186`), which also keeps the behind-live badge (`:137-154`). The error panel (`:188-202`) stays until retry.
- **Sleep:** live players hold `kIOPMAssertionTypePreventUserIdleDisplaySleep` ("MMTVL Live TV", `IPTV/Player/SleepAssertion.swift:10-27`) while loading or playing (`LivePlayer.swift:70`, `:177-179`, `:311-312`), **also in the guide** (its preview is the same player) and in Multiview. Paused and failed players release it; the home preview doesn't hold it (`setHoldsSleepAssertion(false)`, `LiveTVModel.swift:222`). Whether the assertion also stops the screen saver is **unverified** (not needed: MMTVL only starts the saver on still screens, where nothing holds it).
- **Idle signals:** `InputRouter.onCommandDispatched` (`Input/InputRouter.swift:17`) fires for every command while MMTVL is active (keys, controllers, the phone, the Siri Remote); wired to `router?.noteActivity()` (`AppDelegate.swift:190-193`). `AppRouter.noteActivity()` (`:316-322`) restarts the home preview's 10-minute idle timer (`restartIdleTimer` `:342-352`, `Theme.previewIdleTimeout` `:167`); `screensDidSleep()` (`:325-330`) and the screen saver start/stop (`:333-340`) come from `AppDelegate.observeScreensSleep` (`:1119-1139`, distributed `com.apple.screensaver.didstart` / `didstop`). Mouse moves aren't commands.
- **Home** (`Launcher/HomeView.swift`): the clock (`:147-154`), battery (`:217-246`) and version (`:111`) top-right are always on; the dock (`:75-81`) while row 0 has focus. After the preview's 10 minutes only the video stops; the Plex carousel cycles forever (`AppRouter.swift:408-444`).
- **The screen saver (verified 2026-11-08):** `/System/Library/CoreServices/ScreenSaverEngine.app`, bundle id `com.apple.ScreenSaver.Engine`, `LSUIElement = 1`, on this Mac (macOS 27.2) **and on the MM** (macOS 26.6.2, over SSH). `LSUIElement` means it isn't a regular app, so the kiosk guard ignores it (`App/KioskLock.swift:105`: `guard isEnabled, isRegular, !isSelf, …`).
- **The MM's settings (read over SSH, 2026-11-08):** `pmset -g`: `displaysleep 0` (never; "display sleep prevented by MMTVL" at the time), `sleep 1` (prevented by coreaudiod, powerd); screen saver `idleTime = 1800` (30 min, default module, no `moduleDict`); `sysadminctl -screenLock status`: **off** (no password after the screen saver).
- **Unverified (step 1):**
  - (a) whether the seized Siri Remote's presses count as user activity for macOS (`HIDIdleTime`); if not, macOS's own 30-minute screen saver can start while the remote is in use on a still screen;
  - (b) how a press ends a screen saver that MMTVL started: the remote is seized, so macOS never sees its presses. The candidates are `IOPMAssertionDeclareUserActivity` (`SystemPower.declareUserActivity()`, `AVControl/PowerController.swift:451-465`) or terminating `ScreenSaverEngine`;
  - (c) whether `NSWorkspace.openApplication` of `ScreenSaverEngine.app` starts it from MMTVL;
  - (d) the screen saver module the user wants (a moving one).

## Design

### Local decisions

- **L1 — Back never returns `.leave`.** `LiveTVModel.handle` returns `.leave` only for `.home`, which the router already takes. `.setupNeeded`, `.unavailable` and `.loading` ignore Back. `LiveTVOutcome.leave` and the router's `.leave` branch stay, so `FakeLiveTV` tests keep working.
- **L2 — The watch guide's Back goes to the channel.** On `GuideModel.Action.close` with purpose `.watch`: if `currentChannel != nil`, `watch(currentChannel.id)`. That is the playing channel without a reconnect, a failed channel's error panel, or the last channel again after Multiview emptied. With no channel, nothing happens (the guide stays, focus on the grid). The nil-guide fallback (`:516`) returns `.handled`.
- **L3 — Submenus remember their parent.** `LiveTVModel` gets `private var menuParent: LiveMenu?`, set when a choice from a menu opens another (`.chooseLayout`, `.openMatchGuide`). `.close` on a menu with a parent restores the parent (with its own focus) instead of closing. A choice that does something else, Home and `leave` clear it. Match Guide's async open keeps its `self.menu == nil` guard: the parent is held in `menuParent`, not `menu`.
- **L4 — Hints:** the guide's "Back: leave Live TV" becomes "Back: back to the channel" when `currentChannel != nil`, and is dropped otherwise (`hint(…)` gets `hasChannel: Bool`). Setup and error hints lose "Back: return" and say "Home: leave Live TV".
- **L5 — The tile menu opens on `.menu`** on a focused home tile (not the top shelf, not during move mode). That gives the Siri Remote's held centre, the phone's Menu, Tab, the Menu key and Y with no new input code, and matches Live TV's Menu.
- **L6 — Menu contents** (in this order; items that don't apply are left out):

  | Item | Shown for | PIN (when set) |
  |---|---|---|
  | Move | every tile | yes |
  | Quit *title* | `.application`, `.defaultBrowser`, `.url` with a browser, while `launcher.isRunning(item)` | no |
  | Restart *title* | same as Quit | no (the reopen asks like a normal open when the tile is protected) |
  | Reload YouTube | the YouTube tile, once YouTube has been opened | no (the open asks like a normal open when protected) |
  | Hide from Home Screen | every tile but Settings | yes |
  | Start Here (value "On" when it is the start tile; choosing it then does nothing) | every tile but Exit to Desktop | yes |
  | Open Full Screen (value On/Off) | `supportsFullScreen` | yes |
  | Require PIN (value On/Off) | every tile but Settings and Exit | yes |
  | Tile Settings… | every tile | yes (one prompt: it's Settings' own) |

  Without a PIN, nothing asks. Rationale: user choice 2026-11-08 ("Edits ask").
- **L7 — Quit and Restart.** `AppLauncher` gets `isRunning(_:)`, `quit(_:) async` and the shared terminate-and-wait from `restartIfMarked` (5 s, then force quit, then 1 s). Restart = quit, then `activate` the tile as Select would (PIN, full screen, kiosk guard session). A browser tile's Quit quits the whole browser. A web app tile (PWA) quits its shim app when it runs; when the page only runs as a window of the browser, Quit/Restart aren't shown (**unverified** how often that is; step 12 checks). Plex's hot-plug mark is cleared by a manual restart. Reload YouTube = `youtube.reload()`, then open YouTube like Select.
- **L8 — Move mode on home.** `AppRouter.movingTileID`. Arrows move the tile to the neighbouring **visible** place (Left/Right ±1, Up/Down ±`Theme.tilesPerRow`, clamped to the visible range); hidden tiles keep their order relative to their visible neighbours. Each step saves through `settings.moveTile(id:toVisibleIndex:)`, a new method using `updateItems`. Select, Back and Menu end it; Home ends it and goes home; Up never enters the shelf. Focus follows the tile, and the rows scroll as usual.
- **L9 — PIN purpose** `case tileAction(id: String, action: TileMenuAction)`; `finishPIN` runs the action. Tile Settings… uses it too and then opens Settings at the tile's page without asking again.
- **L10 — Settings at a tile:** `SettingsModel.openTile(_ id:)` sets `stack` to root (focus on the Home Screen category) → `.homeScreen` (focus on the tile's row, `SettingsModel.tileRowID(id)`) → `.tile(id:)`, after doing what `reset()` does. `AppRouter.openSettings(atTile:)` calls it instead of `reset()`.
- **L11 — Hide gives feedback:** a 2 s toast "Hidden · Settings → Home Screen shows it again" through `OverlayToast`'s `show(_:symbol:)` (`DesignSystem/OverlayToast.swift:28`), symbol `eye.slash`.
- **L12 — Multiview outlines.** `LiveTVModel.multiviewHighlightVisible: Bool`, true on every Multiview command and when Multiview opens, false `Theme.multiviewHighlightDuration` (5 s) after the last one (generation-counted like `showBanner`). The view draws a **bold** outline (6 pt white, today's tokens) on `focusedSlot` while visible, and a **resting** outline (`Theme.multiviewRestingBorderWidth` 2 pt, `Theme.multiviewRestingBorder` white 0.4) on `audioSlot` whenever the bold one isn't on the same window. Both fade with `Theme.multiviewHighlightFade` (0.6 s ease-out). The speaker badge is deleted. User choice 2026-11-08: "obvious outline during selection … fades to a thin outline always".
- **L13 — With focus on an empty window,** the bold outline is there and the thin one stays on the window with sound. That replaces what the badge told.
- **L14 — Static text in Multiview fades with the highlight.** The empty window's plus and "Add Channel" and the failed window's text show while `multiviewHighlightVisible` or the window is focused, else fade to 0. The empty fill and the failed window's dark scrim stay. The pause symbol follows L15.
- **L15 — Paused overlays fade after 15 s.** `LiveTVModel.pausedOverlayVisible`, true on pause and on every command while paused, false `Theme.pausedOverlayDuration` (15 s) after. The single player shows the bar and badge when `showsTimeshiftBar || (phase == .paused && pausedOverlayVisible)`. In Multiview the pause symbol and timeshift label of a paused window follow the same flag. Select while paused shows them again (the existing toggle shows the bar). User choice 2026-11-08: 15 s.
- **L16 — Guide idle return.** `LiveTVModel` restarts `guideIdleTask` on every `handle`; after `Theme.guideIdleReturn` (3 min) it runs `returnToVideo()`:
  - Live TV not in front: nothing.
  - Menu, search, Choose Teams open: close them (with `menuParent`).
  - In the watch guide with `isPlaying`: `watch(currentChannel.id)`.
  - In the picker guide: `closePicker()`.
  - In Multiview or the player: nothing more.
  It doesn't run while nothing plays; the dimmer handles that.
- **L17 — Still screens.** `AppRouter.isStillScreen: Bool` (computed):
  - true: the home screen (always, since the dock and clock stay put even with the preview), Settings, the PIN screen, the power menu;
  - Live TV: `!liveTV.isShowingVideo`, a new `LiveTVHosting` property: `mode == .player && isPlaying && phase != .paused`, `mode == .guide && isPlaying`, or `mode == .multiview` with any window loading or playing;
  - false: YouTube, and when MMTVL isn't active (other apps, Exit to Desktop).
- **L18 — The idle dimmer** is a pure `StillScreenIdle` state machine (`App/StillScreenIdle.swift`) with an injected clock. Inputs: `activity(at:)`, `stillnessChanged(_:at:)`, `tick(at:)`. Output `phase: .awake | .dimmed | .screenSaver`. It dims at `Theme.stillScreenDimAfter` (5 min) after the later of the last command and the screen becoming still, and asks for the screen saver `Theme.screenSaverAfterDim` (5 min) after dimming. A screen that starts moving again wakes it (a channel resuming). The router owns it and draws `Color.black.opacity(Theme.idleDimOpacity /*0.8*/)` over everything in `LauncherRootView`, animated by `Theme.idleDimAnimation` (2 s ease-in-out); dimmed counts as the home preview being idle (it stops). User choice 2026-11-08: "dim first and then activate macos screensaver".
- **L19 — Waking.** While `.dimmed` or `.screenSaver`, `AppRouter.handle` wakes the dimmer and **swallows** the command (returns true). Exceptions: `power` and `powerMenu` wake and still act; volume never reaches the router, so it acts anyway. The wake is logged. Mouse moves don't wake (out of scope); a click goes through the local monitor as a command only where it already does.
- **L20 — The screen saver** is started by `ScreenSaver.start()` (`App/ScreenSaver.swift`): `NSWorkspace.shared.openApplication(at: URL(filePath: "/System/Library/CoreServices/ScreenSaverEngine.app"), configuration: .init())`, a fixed path. It's ended on a press by the method step 1 finds works (b). `didstart`/`didstop` keep the phase in sync: `didstop` → `.awake` + activity.
- **L21 — macOS's own screen saver** (30 min on the MM): if step 1 (a) shows the seized remote doesn't reset `HIDIdleTime`, every command while MMTVL is active also calls `SystemPower.declareUserActivity()`, at most once a minute and only while the displays are awake. That way macOS never starts its saver while MMTVL is being used.
- **L22 — No new settings keys.** All the times are `Theme` tokens. New log category **`Idle`**: "Dimmed (<screen>)", "Started the screen saver", "Woke by <command>", "Ended the screen saver (<method>)". The tile menu logs under `AppLauncher` (quit/restart, bundle ids only) and `Home` (the menu: "Tile menu: <tile id> <action>").

### New and changed files

| File | Change |
|---|---|
| `IPTV/LiveTVModel.swift` | L1–L3, L12, L14–L17 (`isShowingVideo`, `multiviewHighlightVisible`, `pausedOverlayVisible`, `menuParent`, `guideIdleTask`) |
| `IPTV/Guide/GuideView.swift`, `IPTV/LiveTVView.swift` | L4 hints; L15 paused overlay |
| `IPTV/Multiview/MultiviewView.swift` | L12–L15: outlines, no badge, fading text |
| `DesignSystem/Theme.swift` | tokens: `guideIdleReturn`, `multiviewHighlightDuration`, `multiviewHighlightFade`, `multiviewRestingBorderWidth`, `multiviewRestingBorder`, `pausedOverlayDuration`, `stillScreenDimAfter`, `screenSaverAfterDim`, `idleDimOpacity`, `idleDimAnimation`, `tileMoveLiftScale`, `tileJiggleAngle`, `tileJiggleDuration` |
| `App/StillScreenIdle.swift` (new) | L18, pure, `nonisolated` |
| `App/ScreenSaver.swift` (new) | L20: start, end, running state |
| `Launcher/AppRouter.swift` | dimmer (L17–L19), tile menu (L5, L6, L9), move mode (L8), `openSettings(atTile:)` |
| `Launcher/TileMenu.swift` (new) | `TileMenuAction`, `TileMenu` (pure, like `PowerMenu`) |
| `Launcher/TileMenuView.swift` (new) | the panel (like `PowerMenuView`, with a value column and lock symbols) |
| `Launcher/AppLauncher.swift` | L7: `isRunning`, `quit`, shared terminate-and-wait |
| `Launcher/LaunchItem+Editing.swift` | `movingVisibleItem(id:toVisibleIndex:)` |
| `Launcher/HomeView.swift`, `Launcher/AppTileView.swift` | move mode's lifted, wiggling tile and hint |
| `Settings/SettingsModel.swift` | `moveTile(id:toVisibleIndex:)`, `openTile(_:)` |
| `PIN/PINFlow.swift`, `PIN/PINEntryModel.swift` | `tileAction` purpose and title |
| `YouTube/YouTubeController.swift` | `reload()` in `YouTubeHosting` (and `hasOpened: Bool`) |
| `App/AppDelegate.swift` | wiring: screen saver notifications to the dimmer, `isRunning`/`quit` closures, L21 if needed |

Key sketches:

```swift
// Launcher/TileMenu.swift
nonisolated enum TileMenuAction: Hashable, Sendable {
    case move, quit, restart, reloadYouTube, hide, startHere, toggleFullScreen, toggleRequiresPIN, tileSettings
    var needsPIN: Bool { switch self { case .quit, .restart, .reloadYouTube: false; default: true } }
}
nonisolated struct TileMenu: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable { var action: TileMenuAction; var title: String; var value: String?; var id: TileMenuAction { action } }
    enum Outcome: Equatable, Sendable { case none, close, choose(TileMenuAction) }
    let tileID: String
    let title: String
    private(set) var items: [Item]
    private(set) var focusedIndex = 0
    /// L6's table. `isRunning`: the tile's app runs; `youTubeOpened`: the web view exists.
    static func make(for item: LaunchItem, isStartTile: Bool, isRunning: Bool, youTubeOpened: Bool) -> TileMenu
    mutating func handle(_ command: RemoteCommand) -> Outcome   // Up/Down clamp, Select chooses, Back/Menu close
    mutating func focus(index: Int)
    func choose(index: Int) -> Outcome
}

// App/StillScreenIdle.swift
nonisolated struct StillScreenIdle: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case awake, dimmed, screenSaver }
    var dimAfter: Duration, saverAfterDim: Duration
    private(set) var phase: Phase = .awake
    mutating func activity(at now: ContinuousClock.Instant)
    mutating func stillnessChanged(_ isStill: Bool, at now: ContinuousClock.Instant)
    /// Returns true when the phase changed.
    mutating func tick(at now: ContinuousClock.Instant) -> Bool
    mutating func screenSaverStopped(at now: ContinuousClock.Instant)
}
```

## Implementation steps

- [ ] **1. Probes on the MM** `[human]` (no build needed; MMTVL running as installed). Run these from this Mac over SSH, with the user at the TV:
  - (a) `ssh mm 'ioreg -c IOHIDSystem -d 4 | grep -m1 HIDIdleTime'`, press Siri Remote arrows in MMTVL's Settings for 10 s, run it again within 2 s of the last press. Answer: did the value drop to under ~3 s (in ns: < 3000000000)? → L21 needed if **no**.
  - (b) `ssh mm 'open -a ScreenSaverEngine'`: does the screen saver show on the TV? Then press a Siri Remote button: does it end? If not, `ssh mm 'caffeinate -u -t 2'`: does that end it? If not, `ssh mm 'killall ScreenSaverEngine'`. Record the first that worked → L20's end method (`declareUserActivity` for caffeinate, `terminate()` of the running app for killall).
  - (c) Does MMTVL's home preview stop while the saver runs, and does MMTVL show again when it ends (it should; `didstart`/`didstop`)?
  - (d) The user chooses a screen saver in System Settings → Screen Saver on the MM, a **moving** one (no "Message", no static photo). Write down which.
  - (e) On the TV: Menu → Picture (or Setup) → **Pixel Orbiter**: set **On** (or Auto); note where the **Scrolling Bar** is. Not in a THX picture mode (Pixel Orbiter doesn't run there).
  - Done when: the answers to (a)–(e) are written under *Deviations & questions* with the date.

- [ ] **2. Back never leaves Live TV** `[implementer]`: files: `IPTV/LiveTVModel.swift`, `IPTV/Guide/GuideView.swift`, `IPTV/LiveTVView.swift`, `MMTVLTests/LiveTVModelTests.swift`, `MMTVLTests/MultiviewLiveTVTests.swift`, `MMTVLTests/GuideViewHintTests.swift`
  - L1: `.setupNeeded`, `.unavailable`: `case .back: return .handled`; `.loading`: `return .handled`. `handleGuide`'s nil-guide fallback returns `.handled`.
  - L2: in `handleGuide`'s `.close` for `.watch`: `if let id = currentChannel?.id { watch(id) }` and return `.handled`. Update the comment (M7m L2, D49).
  - L4: `GuideView.hint(focus:isPicking:row:hasChannel:)`: in the four non-picking "Back: leave Live TV" strings, use "Back: back to the channel" when `hasChannel`, else drop the "· Back: …" part. The view passes `model.currentChannel != nil` (find where `hint` is called). `LiveTVView.swift:74,83`: "… · Home: leave Live TV".
  - Tests: change `noPlaylistNeedsSetup`, `emptyPlaylistIsUnavailable` (Back → `.handled`, mode unchanged), `noLastChannelOpensTheGuide` (Back → `.handled`, still `.guide`), rename `backInTheGuideLeaves` → `backInTheGuideReturnsToTheChannel` (from the player: Back opens the guide, Back again → `.handled`, `mode == .player`, the same player, no new `play` call, the banner shows). Add `backWhileLoadingDoesNothing`, `backInTheGuideAfterAStreamErrorShowsTheErrorPanel` (phase `.failed` → mode `.player`), `backFromTheGroupListGoesToTheGridThenTheChannel`. `removeWindowsUntilEmpty`: the final Back → `.handled` and mode `.player` playing the last window's channel (L2, stale `currentChannel` plays again); if the fake shows `currentChannel == nil` there, expect `.guide`. `GuideViewHintTests`: both variants.
  - Done when: `xcodebuild … test` passes and `grep -n 'return .leave' MMTVL/IPTV/LiveTVModel.swift` shows only the `.home` line.

- [ ] **3. Back from a submenu to its menu** `[implementer]`: files: `IPTV/LiveTVModel.swift`, `MMTVLTests/LiveTVModelTests.swift`, `MMTVLTests/MultiviewLiveTVTests.swift`
  - L3: in `handle`'s menu branch, on `.choose(let action)` where the action is `.chooseLayout` or `.openMatchGuide`, set `menuParent = menu` (the menu as it was, focus included) before `perform`. On `.close`: `self.menu = menuParent; menuParent = nil` (nil → closes as before). Clear `menuParent` on any other choice, in `leave`, and when a menu is opened fresh (`channelMenu`/`windowMenu` assignments). Match Guide's async open: if its guard fails, clear `menuParent`.
  - Tests: `backFromMatchGuideReturnsToTheChannelMenu` (focus on the Match Guide row), `backFromTheLayoutMenuReturnsToTheWindowMenu`, `choosingALayoutClosesBothMenus`, `backFromTheChannelMenuClosesIt` (existing `backClosesTheChannelMenu` stays).
  - Done when: the suite passes.

- [ ] **4. The guide goes back to the channel after 3 minutes** `[implementer]`: files: `IPTV/LiveTVModel.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/LiveTVModelTests.swift`, `MMTVLTests/MultiviewLiveTVTests.swift`
  - L16. `Theme.guideIdleReturn: Duration = .seconds(180)`; `LiveTVModel` takes it as an init parameter (`guideIdleReturn: Duration = Theme.guideIdleReturn`, like `overlayDuration`, `:123`) so tests pass milliseconds. Restart the task at the top of `handle` and in `open`/`openGuide`; cancel in `leave`.
  - Tests: `idleGuideReturnsToThePlayingChannel`, `idleGuideWithNothingPlayingStays`, `idleChannelMenuInThePlayerCloses`, `idleSearchOverTheGuideReturnsToTheChannel`, `idlePickerReturnsToMultiview`, `aPressRestartsTheGuideIdleTimer`.
  - Done when: the suite passes.

- [ ] **5. Multiview outlines, no speaker, paused overlays fade** `[designer]`: files: `IPTV/Multiview/MultiviewView.swift`, `IPTV/LiveTVView.swift`, `IPTV/LiveTVModel.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/MultiviewLiveTVTests.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - L12–L15. Tokens: `multiviewHighlightDuration = .seconds(5)`, `multiviewHighlightFade = Animation.easeOut(duration: 0.6)`, `multiviewRestingBorderWidth: CGFloat = 2`, `multiviewRestingBorder = Color.white.opacity(0.4)`, `pausedOverlayDuration = .seconds(15)`. Model: `multiviewHighlightVisible`, `pausedOverlayVisible` (observable; generation-counted tasks; durations as init parameters for tests). Delete `soundBadge` and its use. Animate the outlines with `.animation(Theme.multiviewHighlightFade, value: model.multiviewHighlightVisible)` and on `focusedSlot`/`audioSlot`.
  - Tests: `theHighlightShowsOnAPressAndHidesAfterItsTime`, `enteringMultiviewShowsTheHighlight`, `pausedOverlayHidesAfter15sAndAPressShowsItAgain` (single player and a Multiview window), `pausedOverlayDoesntAffectTheBannerTimer`.
  - Done when: the suite passes, and in `-windowed YES` Multiview (2+ windows) shows the bold outline after an arrow, fading to a thin outline on the window with sound after 5 s; no speaker icon; with focus moved to an empty window, bold on it and thin on the window with sound; paused, the bar fades after 15 s. Screenshot each state for the orchestrator.

- [ ] **6. Still screens dim** `[implementer]`: files: `App/StillScreenIdle.swift` (new), `Launcher/AppRouter.swift`, `IPTV/LiveTVModel.swift` (`isShowingVideo`, in `LiveTVHosting`), `MMTVLTests/FakeLiveTV.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/StillScreenIdleTests.swift` (new), `MMTVLTests/AppRouterTests.swift`
  - L17–L19, L22. Tokens: `stillScreenDimAfter = .seconds(300)`, `screenSaverAfterDim = .seconds(300)`, `idleDimOpacity = 0.8`, `idleDimAnimation = Animation.easeInOut(duration: 2)`. The router runs a 1 s tick task while MMTVL is active (stop it when inactive; `noteActivity` and stillness changes feed the state machine). Recompute stillness on screen changes and on a Live TV observation (`isShowingVideo`). Dimmed: the overlay in `LauncherRootView` above the power menu overlay, `allowsHitTesting(false)`; the home preview stops as when idle. The step-7 hook: on `.screenSaver` the router calls an injected `startScreenSaver: () -> Void` (a no-op until step 7).
  - Tests (`StillScreenIdleTests`): `dimsFiveMinutesAfterTheLastPress`, `dimsFiveMinutesAfterBecomingStill` (a long playback, then a pause), `movingAgainWakes`, `asksForTheScreenSaverFiveMinutesAfterDimming`, `activityWakesFromEitherPhase`, `screenSaverStoppedWakes`. `AppRouterTests`: `aPressWhileDimmedOnlyWakes` (Select doesn't open the tile), `powerWhileDimmedWakesAndActs`, `liveTVPlayingNeverDims`, `youTubeNeverDims`.
  - Done when: the suite passes; in `-windowed YES` with the tokens temporarily at 10 s, the home screen darkens after 10 s and an arrow brings it back without moving focus (revert the tokens).

- [ ] **7. The screen saver** `[implementer]` (after step 1): files: `App/ScreenSaver.swift` (new), `App/AppDelegate.swift`, `Launcher/AppRouter.swift`, `MMTVLTests/AppRouterTests.swift`
  - L20 with the end method from step 1 (b); L21 only if step 1 (a) says the remote doesn't reset `HIDIdleTime`. `ScreenSaver` is a small class with `start()`, `end()` and `isRunning` (set from `didstart`/`didstop` in `observeScreensSleep`, `AppDelegate.swift:1119-1139`, which also calls `router.screenSaverDidStart/Stop`). A press while `isRunning` calls `end()` and is swallowed (L19). Logs under `Idle`.
  - Tests: `screenSaverPhaseStartsIt` (an injected closure is called once), `aPressDuringTheScreenSaverEndsItAndIsSwallowed`, `didstopWakesTheDimmer`.
  - Done when: the suite passes; with the tokens at 10 s in `-windowed YES` on this Mac, the screen saver starts ~20 s after the last press, and a key ends it (revert the tokens).

- [ ] **8. Quit, restart and reload** `[implementer]`: files: `Launcher/AppLauncher.swift`, `YouTube/YouTubeController.swift`, `MMTVLTests/AppLauncherTests.swift`, the YouTube fake in `MMTVLTests/`
  - L7. `func isRunning(_ item: LaunchItem) -> Bool` (`bundleID(for:)` → `!workspace.runningApps(id).isEmpty`; false for internal and system tiles). `func quit(_ item: LaunchItem) async` (factor `restartIfMarked`'s remove-pid / drop-web-app / terminate / wait / force into `terminateAndWait(_ apps:) async`; both use it; also clears the hot-plug mark for that bundle id). `YouTubeHosting` gains `func reload()` and `var hasOpened: Bool`. Log `Quit <bundle id> (tile menu)` / `… force quit` under `AppLauncher`.
  - Tests: `isRunningForAnAppTileAndNotForInternalTiles`, `quitTerminatesAndForgetsThePid` (no return-to-launcher callback afterwards), `quitForceQuitsAfterFiveSeconds`, `quitClearsThePlexHotplugMark`, the existing hot-plug tests unchanged.
  - Done when: the suite passes.

- [ ] **9. The tile menu** `[implementer]` `[security]` (PIN gating, D20): files: `Launcher/TileMenu.swift` (new), `Launcher/AppRouter.swift`, `Settings/SettingsModel.swift`, `PIN/PINFlow.swift`, `PIN/PINEntryModel.swift`, `MMTVLTests/TileMenuTests.swift` (new), `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/PINFlowTests.swift`
  - L5, L6, L9–L11. Router: `tileMenu: TileMenu?`, opened on `.menu` in the home case of `route` (tiles only, not the shelf); while open it takes every command but Home (Home closes it, then goes home), like `routePowerMenu`. `perform` closes it first, then:
    - with `hasPIN && action.needsPIN`: `requestPIN(.tileAction(id:action:))`;
    - otherwise run: `.move` → step 10's entry point (until then, a stub that logs); `.quit` → `Task { await launcher.quit(item) }`; `.restart` → quit, then `activate(index)`; `.reloadYouTube` → `youtube.reload()` + `activate`; `.hide` → `settings.perform(.toggleTileVisible(id))` + toast; `.startHere` → `settings.perform(.setStartTile(id))`; the toggles → `settings.perform(.toggleTileFullScreen/.toggleTileRequiresPIN(id))`; `.tileSettings` → `openSettings(atTile:)`.
    - `PINFlow`'s verify list and `PINEntryModel`'s title: "Enter PIN to change this tile", or "Enter PIN to open Settings" for `.tileSettings`.
  - `SettingsModel.openTile(_:)` (L10).
  - Tests (`TileMenuTests`): one per row of L6's table (which tiles get which items, values, order), `upDownClampAndSelectChooses`, `backAndMenuClose`. `AppRouterTests`: `menuOnATileOpensItsMenu`, `menuInTheShelfDoesNothing`, `withAPINHideAsksFirstThenHides`, `withAPINQuitDoesntAsk`, `withoutAPINEditsRunAtOnce`, `tileSettingsOpensSettingsAtTheTileWithOnePIN`, `restartQuitsThenOpensLikeSelect` (a protected tile asks when it opens), `homeClosesTheTileMenuAndGoesHome`, `hidingTheStartTileFallsBackToTheFirst`. `PINFlowTests`: the new purpose verifies.
  - Done when: the suite passes; in `-windowed YES`, Tab on the Plex tile opens the menu with Quit/Restart only while Plex runs.

- [ ] **10. Move mode on the home screen** `[implementer]`: files: `Launcher/LaunchItem+Editing.swift`, `Settings/SettingsModel.swift`, `Launcher/AppRouter.swift`, `MMTVLTests/LaunchItemEditingTests.swift`, `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/SettingsModelTests.swift`
  - L8. `func movingVisibleItem(id: LaunchItem.ID, toVisibleIndex: Int) -> [LaunchItem]` puts the item right before the visible item now at that index (or after the last visible one), and leaves hidden items in place relative to the others. `SettingsModel.moveTile(id:toVisibleIndex:)` → `updateItems`. Router: `movingTileID`, `startMoving(id)`; in the home case, while moving: arrows compute the target index (`±1`, `±Theme.tilesPerRow`, clamped), call `settings.moveTile`, and keep focus on the tile (`setItems` already does); Select/Back/Menu end; Home ends and goes home; Up from row 0 stays.
  - Tests: `movingVisibleItemKeepsHiddenTilesInPlace`, `movingVisibleItemToTheEnd`, `moveRightSwapsWithTheNeighbour`, `moveDownJumpsARow`, `moveClampsAtTheEdges`, `selectEndsMoveAndTheOrderIsSaved` (the `applyItems` fake saw the new order), `upInMoveModeDoesntEnterTheShelf`, `settingsSeesTheNewOrder`.
  - Done when: the suite passes.

- [ ] **11. The tile menu and move mode, drawn** `[designer]`: files: `Launcher/TileMenuView.swift` (new), `Launcher/AppRouter.swift` (`LauncherRootView` overlay), `Launcher/HomeView.swift`, `Launcher/AppTileView.swift`, `DesignSystem/Theme.swift`
  - The menu: like `PowerMenuView` (glass panel, `Theme.liveMenuWidth`, the tile's title, rows with the value column right-aligned like `LiveMenuView`, a lock symbol on `needsPIN` rows when a PIN is set, the hint "Select: choose · Back: close"), over `Theme.menuDim`, faded with `Theme.menuFadeAnimation`; hover and click like the power menu's. Move mode: the moving tile lifted (`Theme.tileMoveLiftScale`) and wiggling (`Theme.tileJiggleAngle` ~1.5°, `Theme.tileJiggleDuration` ~0.25 s, no wiggle with Reduce Motion), the other tiles' titles hidden, and a hint capsule at the bottom: "Arrows: move · Select: done".
  - Done when: in `-windowed YES` the menu and a move look right next to the power menu; screenshots for the orchestrator.

- [ ] **12. TV check (one test build)** `[human]`: after steps 1–11 are committed and the user says yes to a test build (`scripts/test-build.sh`, then `scripts/deploy-mm.sh`).
  - **Back:** in Live TV, Back from the player → guide → (group list → grid) → the same channel, full screen, no reconnect, banner shows. Back from Match Guide → the channel menu; from Layout → the window menu. Back in Multiview → full screen. Back never reaches the home screen anywhere in Live TV; TV button always does.
  - **Tile menu:** hold the remote's centre on Plex (running): Quit Plex, then hold again: no Quit/Restart. Open Plex, Home, Restart Plex: Plex quits and opens again full screen. Move a tile two places right and a row down; quit and relaunch MMTVL: the order stays. Hide a tile (toast), show it again in Settings. Start Here, Open Full Screen, Require PIN toggles. Tile Settings… opens the tile's page. With the PIN set, an edit asks once; Quit doesn't. Phone Menu opens the menu too. Reload YouTube.
  - **Burn-in:** Multiview 1 + 4: bold outline after a press, thin outline 5 s later, no speaker icon; focus on an empty window: bold there, thin on the window with sound. Pause: bar and badge fade after 15 s. Leave the guide alone for 3 min: back to the channel. Leave the home screen 5 min: it dims; 5 more: the screen saver (step 1's choice). A remote press ends it and MMTVL is back where it was, with nothing else done.
  - Logs: `ssh mm "/usr/bin/log show --last 1h --predicate 'subsystem == \"dev.mmtvl.launcher\" AND (category == \"Idle\" OR category == \"AppLauncher\" OR category == \"Home\")' --info"`.
  - Done when: the user ticks each line or records what failed under *Deviations & questions*.

- [ ] **13. Docs** `[doc]`: files: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan
  - `CLAUDE.md`: replace "Live TV keys (M7c L11)" with the new rule (D49) and fix `homeStartTile` ("after every Home press", no longer "when Back reaches the home screen"); add the tile menu (D50: the trigger, the items, the PIN rule) to the Home screen bullet; add burn-in (D51: Multiview outlines, paused overlays 15 s, guide 3 min, dim 5 min, screen saver 5 more, the `Idle` log category and its `log show` line under Commands); note Pixel Orbiter on the TV.
  - Master plan: M7m `Done`, the plan moved to `docs/plans/archive/` with `git mv` and the link updated.
  - Done when: `git diff --stat` shows the docs and the plan's move; links resolve.

## Tests

- New suites: `MMTVLTests/StillScreenIdleTests.swift`, `MMTVLTests/TileMenuTests.swift`.
- Changed: `LiveTVModelTests`, `MultiviewLiveTVTests`, `GuideViewHintTests`, `AppRouterTests`, `AppLauncherTests`, `LaunchItemEditingTests`, `SettingsModelTests`, `PINFlowTests`, plus the YouTube and Live TV fakes (`FakeLiveTV.swift`: `isShowingVideo`; the YouTube fake: `reload`, `hasOpened`).
- Each step names its tests. Full suite: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`.

## Manual verification

- This Mac, `-windowed YES`: steps 5, 6, 7, 9 and 11's "done when".
- The MM and the TV: step 1 (probes) and step 12 (one test build).

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| The seized Siri Remote can't end the screen saver | Step 1 (b): the saver stays on a press, and neither caffeinate nor killall works | Skip the screen saver; keep the dim only (L18 without `.screenSaver`), and ask the user |
| macOS's own 30-min saver starts while the remote is in use | Step 1 (a): `HIDIdleTime` keeps growing | L21: declare user activity on commands |
| The thin outline still burns in over months | Faint outline ghost on the TV | Lower `multiviewRestingBorder` opacity, or fade it too (a token change) |
| Swallowing the waking press feels like a lost press | User feedback at step 12 | Let Select/arrows through on the dimmed (not screen saver) phase |
| Quit of a browser tile closes tabs the user wanted | User feedback | Hide Quit/Restart for browser tiles |
| A web app (PWA) running in the browser window shows no Quit | Step 12 | Quit the window through the browser's AX close button (as `ReflectorMonitor` ends mirroring) in a follow-up |
| Restart races the app's own relaunch (Plex HTPC) | Two Plex windows, or none | `restarting` already blocks a double open; extend the wait |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
