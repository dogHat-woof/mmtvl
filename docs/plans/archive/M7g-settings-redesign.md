# M7g — Settings redesign

| | |
|---|---|
| Status | Done (2026-11-08) |
| Depends on | M7f (its uncommitted Settings changes, the Teams pages and the Guide Source row, must be committed first) |
| Master plan decisions used | D2, D19, D20, D29, D42 |
| Planned | 2026-11-04 |

## Goal

Settings looks and moves like tvOS 27 Settings, without a big decorative icon taking up the left side.

- **Root page:** a short list of categories, **centered** on the screen. Nothing shows beside it (user choice 2026-11-04: no dimmed preview of the focused category).
- **Opening a category:** the root list slides left and dims, and the category's page slides in on the right with focus. Back (or Left) to the root slides the list back to the center while the category's page slides away to the right and fades.
- **Going deeper:** the columns slide left. The page you came from stays on the left, dimmed, with the row you picked marked.
- **Pages with a QR code or tile art** show that visual on the left instead of the parent list.
- **Rows:** every row is its own glass capsule. Sections have small uppercase headers. The white focus highlight slides between rows.
- **Description:** a short description of the focused setting shows in a band at the bottom of the screen.

## Out of scope

- New settings or behavior changes. Every row, action, file and Keychain item stays as it is. Only the layout, the grouping, the navigation keys (Left/Right) and the copy change.
- Search in Settings, and a Settings entry from the phone remote.
- The PIN entry screen (`PIN/`) and the accessibility onboarding screen keep their own layouts.

## Research & findings

Verified in the code on 2026-11-04, on branch `m7f-tv-findings` with M7f's work uncommitted.

### The current screen

- **View.** `Settings/SettingsView.swift` draws the title (`model.pageTitle`), then an `HStack` of `RowImageView(model.pageImage)` at `Theme.settingsPageImageSize` (280) in a 600-pt side column (`settingsSideColumnWidth`), then the list (`settingsListWidth` 1000), clipped and on **one** `.glassPanel()`. Below them sits `model.hint`. The list is a `ScrollViewReader` that centers `model.focusedRowID` with `withAnimation(Theme.focusAnimation)`.
- **Rows.** `SettingsRowView` is clear when unfocused and white (`Theme.focusedRowFill`) with dark text when focused or lifted. It scales by `settingsRowFocusScale` (1.03) and casts a shadow, animated per row with `.animation(Theme.focusAnimation, value: isHighlighted)`. There is no sliding highlight and no `matchedGeometryEffect` anywhere in the app. Info rows (`action == nil`) never highlight. Rows show an image, a title and `detail` (second line), then the "Relaunch needed" badge, the `value`, the lifted icon and the chevron.
- **Hosting.** `SettingsView` is built in `AppRouter.swift` around lines 924–930 with `onHoverRow: router.hoverSettingsRow` (which only acts after the pointer moved) and `onActivateRow: router.settings.activate`.
- **Input.** In `AppRouter.handle(_:)` for `.settings`: Home goes home, everything else goes to `settings.handle`, and an unhandled Back on the root goes home to the start tile (M7c L32). `SettingsModel.handle` swallows `.left` and `.right` ("L13: no value cycling", from M2b).
- **Opening and closing.** `AppRouter` calls `settings.reset()` when Settings opens (line 745), which resets the stack to the root. A PIN flow started from Settings (`startPIN`) returns to `.settings` without a reset (`screenBeforePIN`, around line 642), so the stack and the focus survive. Moving the PIN rows to a deeper page is safe.
- **Model.** `SettingsModel` keeps `stack: [PageState(page, focusedRowID)]`. `sections`, `pageTitle`, `pageImage` and `hint` (in `SettingsModel+Pages.swift`) switch on the top `page` only. Most builders already take the page's argument (`tileSections(id:)`, `remoteCommandSections(_:)`…). Those that read model state (`plex`, `casting`, `iptv`, `phoneRemote`, `movingTileID`, `pasteMessage`, `learnMessage`…) are pure reads.
- **Side effects live in `push()`, not in the builders.** `push()` handles the `.addTile` app scan, the `.tileArt` picture scan, `syncPairing`, `syncLearning`, `syncPlexLink`, `refreshPlex` and `refreshCasting`. So calling a builder for a page that isn't on top (a preview or a parent) is safe.
- **Root rows today** (`rootSections`):
  - Remote & Input: `globalInput`, `controllers`, `remoteButtons`, `channelUp`, `cursorAutoHide`, `phoneRemote`;
  - Permissions: `accessibility`;
  - Startup: `launchAtLogin`, `approveLoginItem`;
  - Home Screen: `editHome`;
  - PIN: `pin.set`, or `pin.change` and `pin.off` (`pinSection`);
  - YouTube: `youtube.reload`, `youtube.clear`;
  - Casting: `casting`; Plex: `plex`; Live TV: `liveTV`;
  - System: `relaunch`, `kioskLock`, `exit`;
  - About: `about.version`, `about.build`, `about.showOnHome`, plus the "Settings are saved in…" footer.
- **Theme tokens.** `Theme.swift` lines 244–262 hold the Settings fonts and sizes. `focusAnimation` is `.spring(response: 0.3, dampingFraction: 0.8)` (line 361). Glass is `.glassPanel()` / `.glassPanel(in:)` (`Glass.swift`, solid with Reduce Transparency). `ParallaxFocus` and `ShelfCarouselView` read `accessibilityReduceMotion`, which is the pattern to copy.
- **Tests that pin the current layout.** These need updating in the steps below:
  - `SettingsModelTests.swift`: the root tests at lines 8–100 press counts and row ids on the root; line 377 checks `iptv.homePreview` detail; line 463 checks `iptv.guideSource` detail; line 723 checks `channelUp` detail; lines 267–286 cover the PIN rows on the root.
  - `pageImage` assertions: `SettingsPlexTests.swift:53`, `SettingsTileArtTests.swift:28–32`, `SettingsPhoneRemoteTests.swift:86, 93`.
  - `pageTitle` assertions in `SettingsTileArtTests.swift` and `SettingsPhoneRemoteTests.swift` keep working.
- **Detail strings that alternate with error messages stay in `detail`.** These are the paste rows (`iptv.playlist.paste`, `iptv.guide.add`, `iptv.guide.none`) and `tile.startURL`, which tests check at lines 433–572 and 760–795. Only pure explanations move to `description`.

### Centered root, no preview (added 2026-11-04, after step 8)

User request: "I am not a fan of showing the right side options even if they are dimmed out until you actually click on a menu setting." The root starts centered, slides left when a category opens, and slides back to the center on the way back. Verified in the code on 2026-11-04 at commit `56700f7` (Build 21):

- **Track position.** `SettingsView.swift:42–45`: `trackShift = max(0, stack.count − 2)` and `trackOffset = settingsSideMargin − trackShift × (settingsColumnWidth + settingsColumnGap)`. At depth 1 and depth 2 the offset is the same (80), which is why opening a category doesn't move anything today. Centering the root column needs offset `(canvas − settingsColumnWidth) / 2` = (1920 − 840) / 2 = **540** at depth 1, so 460 pt to the right of depth 2's 80.
- **Slide animation.** `SettingsView.swift:58` animates with `settingsPageAnimation` keyed on `trackShift`; `trackShift` is 0 at depths 1 and 2, so a category open or a return to the root runs no spring (step 7 chose that on purpose). The key has to become a value that differs between depth 1 and depth 2. Reduce Motion (`SettingsView.swift:52`) fades the whole track through on a change of the same key (`.id(reduceMotion ? trackShift : 0)`), so it follows the new key too.
- **The slot the category lands in already exists.** `SettingsModel.columns` (`SettingsModel.swift:117–128`) always draws `stack.count + 1` columns: at the root the trailing one is the preview, deeper it's `.empty`. Every column sits in one `HStack` that moves as a whole (`SettingsView.swift:61–82`), each with `.geometryGroup()` (step 5), so content fading into column 1 already moves with the track. With an `.empty` trailing column at the root, a category open is: column 1 goes `.empty → .current` (its content `.none → .list(page)` fades in with `settingsFadeInAnimation`, `SettingsColumnView.swift:60–64`) while the track slides 540 → 80, so the page slides in from x = 1460 (half off the right edge, clipped by `SettingsView.swift:57`) to x = 1000. A return to the root is `.current → .empty`: `isLeaving` (`SettingsColumnView.swift:56`) is already true for `.empty`, so the page fades out with `settingsLeaveFadeAnimation` (0.35 s) while the track slides back, as a pop from depth 3 does today.
- **What the preview owns, to remove:**
  - model: `Column.Role.preview` (`SettingsModel.swift:20`), the `.preview` branch of `columns` (line 125), `previewPage` (lines 130–135), `activatePreviewColumn()` (lines 155–159) and the "parent or preview" wording of `columnClickedAt` (line 72, the guard stays for parent clicks) and of `focus(rowID:on:)` (line 252);
  - view: `SettingsColumnView`'s `.preview` cases in `content` (line 27), `opacity` (line 42) and `onClick` (line 50), the preview scroll-to-top in `SettingsPageList`'s `onChange(of: role)` (lines 159–166), and the `onActivatePreview` parameter in `SettingsColumnView` (line 15), `SettingsView` (lines 15–16, 72) and `AppRouter.swift:934`;
  - theme: `settingsPreviewOpacity` (`Theme.swift:266`).
- **Tests that pin the preview** (`MMTVLTests/SettingsModelTests.swift`, suite `SettingsColumnsTests` from line 805): `previewPageFollowsRootFocus` (806–818) goes; `columnsRoles` (820–832) expects `[.current, .empty]` and pages `[.root, nil]` at depth 1; `parentAndPreviewColumnsActivate` (943–955) keeps only the parent half; `sectionsForPreviewHasNoSideEffects` (957–) still matters (the parent column builds `sections(for:)` of a page that isn't on top) and is renamed; `rowClickRightAfterAColumnClickIsIgnored` (1045–1069) opens System with `activatePreviewColumn()` in its first half, which becomes a parent click from a depth-3 page; `rowsOfOtherPagesIgnoreThePointer` (1071–1093) drops its "preview's rows" part. No other test file reads the Settings columns or the preview (`grep previewPage\|activatePreviewColumn MMTVLTests`).
- **Unaffected:** the PIN flow returns to `.settings` without a reset (above), so coming back from Restrictions → Set PIN shows the Restrictions page with the root on the left, not centered. `reset()` puts the root back at depth 1, and the view appears centered with no animation (the track's `.animation(_:value:)` only runs on a change). No accessory page sits at depth 2 (`.pairPhone`, `.plexLink`, `.tile`, `.tileArt` and `.learnButton` are all at depth 3 or more), so the parent column at depth 2 is always the root's list. The title and the band are already centered on the canvas.

### tvOS 27 reference (user's screenshots, 2026-11-04)

- Gray page title at the top center.
- Rows are full-height pill capsules in translucent gray. The focused row is white with black text and slightly larger. The chevron is a light gray.
- Section headers are small, uppercase, bold and gray ("DEFAULT", "ADDITIONAL", "PREFERENCES").
- The focused row's description is centered under the left image, in gray, a few lines long.
- The left image is decorative. The user doesn't want it taking that much space.

## Design

### Layout on the 1920 × 1080 canvas

```
Root (depth 1):
      ┌──────────────────────── title (gray, centered) ─────────────────────────┐
      │              540 │ root column (840)               │ 540                │
      │                  │ (● focused category        ›)   │                    │
      │                  │ ( category                 ›)   │                    │
      └──────────────────────────────────────────────────────────────────────────┘

Category and deeper (depth ≥ 2):
      ┌──────────────────────── title (gray, centered) ─────────────────────────┐
  80 │ column A (840)              80 │ column B (840)                        │ 80
      │  SECTION                         │  SECTION                              │
      │ (● selected row capsule     ›)  │ (● focused row capsule     value ›)  │
      │ ( row capsule               ›)  │ ( row capsule              value  )  │
      └──────────────────────────────────────────────────────────────────────────┘
                 description band (≤ 1400 wide, ≤ 3 lines, centered)
```

- **The track (L1).** Columns sit side by side on a horizontal track. Column *i* shows `stack[i]`, and after the stack comes one **empty** column. Every column is `settingsColumnWidth` (840) wide with `settingsColumnGap` (80) between them. The track's x offset is:
  - depth 1 (the root): `settingsRootColumnLeading` = `(canvas − width) / 2` = 540, so the root list is centered and the empty column to its right is off screen or blank;
  - depth ≥ 2: `settingsSideMargin` (80, step 5) `− max(0, depth − 2) × (width + gap)`, where `depth = stack.count`.

  Its container is `.clipped()` to the canvas. (Changed 2026-11-04 after step 8: the root was on the left with a dimmed preview of the focused category on the right; see step 9.)

| State | Left column | Right column | Movement |
|---|---|---|---|
| Root (depth 1) | — (the root list is centered, current) | — | — |
| Category (depth 2) | root, dimmed, the opening row selected | the category page, current | the track slides left by 460 (root from center to left); the page fades in as it slides in from the right |
| Back to the root | — | — | the track slides right by 460 (root back to center, brightening); the category page slides off to the right and fades |
| Deeper (depth ≥ 3) | `stack[n−2]`, dimmed, selected row | `stack[n−1]`, current | the track slides left by one column |
| Pop (depth ≥ 3) | reverse | | the track slides right; the removed page fades |
| Replace (learn → confirm, Plex link → servers) | unchanged | same column | content crossfades (`.id(page)` plus an opacity transition) |

- **Accessory (L2).** When `accessory(for: page)` isn't nil, the left column shows that image, centered, instead of the parent's list, crossfading in. The current column stays on the right. Accessories:
  - `.pairPhone`: the QR code, else `.symbol("iphone")`;
  - `.plexLink`: the QR code, else `.symbol("play.square.stack")`;
  - `.tileArt(id)`: `.tileArt(itemID:, tileArtPreviewChoice)`;
  - `.tile(id)`: `.tileArt(itemID: id, .current)`, the tile as it looks now (today it's the app icon);
  - `.learnButton`: `.symbol("hand.point.up.left")`.

  Every other page has no accessory, and its decorative symbol from `pageImage` is dropped.
- **Description band (L3).** Its height is reserved (`settingsBandHeight` 104) so the columns never move. The text is centered, at most `settingsBandMaxWidth` (1400) wide and 3 lines, in `Theme.secondaryText` at `settingsDescriptionFont` (28). It crossfades when the text changes. The content is `bandText`:
  1. the mode hint: move mode "Up/Down: move · Select or Back: done", or on `.learnButton` "Waiting for a button…";
  2. else the focused row's `description`;
  3. else nothing.

  The old `hint` and its generic "Select: choose · Back: return" go away. Pair a Phone and the Plex link have Done and Cancel rows, so they need no hint.
- **Title.** `title(for: page)` uses `settingsTitleFont` in `Theme.secondaryText`, centered, with the same top padding as today.

### Rows and sections (L4)

- **Rows.** Each row is its own capsule:
  - shape: `Capsule()` when the row has no second line, else `RoundedRectangle(cornerRadius: settingsRowCornerRadius)` with the radius raised to 40 so it reads as a pill;
  - height at least `settingsRowMinHeight` (72), so the root's nine categories fit with About fully visible; the second line, badges, chevrons and section footers use `settingsRowDetailFont` (24);
  - unfocused: `.glassPanel(in:)` with `settingsRowCapsuleFill` (white at 0.075) over the glass, under the content, so rows read as translucent gray; the column is wrapped in a `GlassEffectContainer(spacing: Theme.settingsRowSpacing)`;
  - focused: the white `Theme.focusedRowFill` with `focusedRowText`, as today;
  - info rows: a quieter fill (`settingsInfoRowFill`, white at about 0.05) with no glass.
- **Selected in the parent column.** The row in the parent column that opened the current page draws `settingsSelectedRowFill` (white at 0.4) with primary text. Selected ↔ focused flips at once (no crossfade), so the capsule never goes blank, like tvOS's gray "you came from here" row.
- **Sliding highlight (L5).** The white fill is one view per column with `.matchedGeometryEffect(id: "focus", in: columnNamespace)`, drawn behind whichever row has focus. The column animates with `.animation(Theme.focusAnimation, value: focusedRowID)`. The focused row keeps its 1.03 scale and shadow.
  - With **Reduce Motion**: no matched geometry. The fill crossfades per row (today's behavior) and page changes crossfade instead of sliding.
- **Sections.** Headers use `title.uppercased()` in `settingsSectionFont` (22, bold) and `Theme.secondaryText`, indented to the row text. Footers stay small and secondary under their section, one plain sentence each. Each list scrolls inside a top and bottom fade the height of its vertical padding (`settingsListVerticalPadding` 32) instead of a hard clip. Sections are `settingsSectionSpacing` (40) apart.
- **Dimming.** The parent column draws at `settingsDimmedColumnOpacity` (0.55), with no white highlight. (There's no preview column any more, step 9.)

### Root categories (L6)

The root's rows are categories, each opening a page. Root row ids are new (except `liveTV`, `plex` and `casting`). Rows inside pages keep their ids.

| Root row (id) | Value | Opens | Its rows (existing ids) |
|---|---|---|---|
| Home Screen (`homeScreen`) | — | `.homeScreen` (existing) | tiles, `addTile`, `restoreDefaults` |
| Live TV (`liveTV`) | channel count / Not Set Up | `.liveTV` | unchanged |
| Plex (`plex`) | Signed In / Not Signed In | `.plex` | unchanged |
| YouTube (`youtube`) | — | **new** `.youtube` | `youtube.reload`, `youtube.clear` + the Parent code footer |
| Casting (`casting`) | — | `.casting` | unchanged |
| Remote & Input (`remoteInput`) | — | **new** `.remoteInput` | `globalInput`, `controllers`, `remoteButtons`, `channelUp`, `cursorAutoHide`, `phoneRemote` |
| Restrictions (`restrictions`) | PIN On / Off | **new** `.restrictions` | section "PIN" (`pinSection`), section "Other Apps" (`kioskLock`) |
| System (`system`) | — | **new** `.system` | section "Permissions" (`accessibility`), section "Startup" (`launchAtLogin`, `approveLoginItem`), section "MMTVL" (`relaunch`, `exit`) |
| About (`about`) | the version | **new** `.about` | `about.version`, `about.build`, `about.showOnHome` + the "Settings are saved in…" footer |

Page titles: "Home Screen", "Live TV", "Plex", "YouTube", "Casting", "Remote & Input", "Restrictions", "System", "About". The `editHome` id goes away; `homeScreen` replaces it.

### Model (`SettingsModel.swift`, `SettingsModel+Pages.swift`, `SettingsTypes.swift`)

```swift
// SettingsTypes.swift
nonisolated enum SettingsPage { …; case youtube, remoteInput, restrictions, system, about }
nonisolated struct SettingsRow { …; /// The band's text when focused (L3).
    var description: String? = nil }

// SettingsModel+Pages.swift
func sections(for page: SettingsPage) -> [SettingsSection]   // pure; `sections` = sections(for: page)
func title(for page: SettingsPage) -> String                  // `pageTitle` = title(for: page)
func accessory(for page: SettingsPage) -> RowImage?           // replaces `pageImage`
var bandText: String?

// SettingsModel.swift
/// L1: what the view draws, left to right.
struct Column: Identifiable, Equatable { let index: Int; let page: SettingsPage?; let role: Role
    enum Role { case parent, current, empty, hidden }; var id: Int { index } }
var columns: [Column]
/// `stack[count - 2].focusedRowID`, resolved against that page's rows.
var parentSelectionRowID: String?
func activateParentColumn()   // mouse: pop
```

- `columns` holds every stack page plus one trailing `empty` column (at the root too, step 9). Roles: `current` for the top page, `parent` for the one below it, `hidden` for older pages (off screen to the left), then `empty`. Steps 4–8 also had `Role.preview`, `previewPage` and `activatePreviewColumn()` for the root's preview; step 9 removes them.
- **Left and Right (L7)** in `handle(_:)`:
  - `.right`: when not in move mode and the focused row's action is `.push`, perform it (like Select).
  - `.left`: when not in move mode, `stack.count > 1` and the page isn't `.learnButton`, `pop()`.
  - Both still return `true` everywhere, so the router never acts on them. Left on the root does nothing.
  - Only a fresh press counts: `handle(_:isRepeat:)` swallows a held key's or controller button's repeats of Left and Right (review fixes, 2026-11-04). Up/Down/Back repeat as before.

  This replaces M2b L13 for Settings. Value rows still don't cycle on Left/Right.
- **Detail versus description (L8).** `detail` keeps status and messages that can change. Pure explanations move to `description` (table below). Paste rows and `tile.startURL` keep their instruction in `detail`, because errors replace it there.

### Descriptions (L8)

One or two plain sentences each. The executor may polish the wording but keeps the meaning and the length (at most about 160 characters).

| Row id | Description |
|---|---|
| `homeScreen` | Arrange, hide and add tiles, and choose each tile's art and the tile MMTVL opens on. |
| `liveTV` | The playlist and guides, channel groups, hidden channels, teams and the Home screen preview. |
| `plex` | Continue Watching from your Plex server on the Home screen. |
| `youtube` | Reload YouTube, or sign every account out of it. |
| `casting` | Casting from the YouTube app, AirPlay from iPhones, Android mirroring through Reflector, and Plex HTPC. |
| `remoteInput` | Remote buttons, game controllers, the pointer and the phone remote. |
| `restrictions` | The PIN, and keeping other apps from taking over the TV. |
| `system` | Accessibility access, starting at login, relaunching MMTVL and leaving to the desktop. |
| `about` | The version and build of MMTVL. |
| `globalInput` | Home and the media keys also work while another app is in front. Needs Accessibility access. |
| `controllers` | Use game controllers as remotes. The Siri Remote's TV button works through this too. |
| `remoteButtons` | See which buttons do what, and teach MMTVL the buttons of a new remote. |
| `channelUp` | Changes channel in Live TV. Up the List moves up the list like the Up arrow; Higher Number goes to the next number. |
| `cursorAutoHide` | Hides the pointer while you use the remote. It comes back when the mouse moves. |
| `phoneRemote` | Control MMTVL and other apps from a phone's browser, with typing and a trackpad. |
| `youtube.reload` | Reloads the YouTube page. Try this if YouTube stops responding. |
| `youtube.clear` | Signs every account out of YouTube on this Mac and deletes its watch data. |
| `pin.set` | A 4-digit PIN that guards Settings, Exit to Desktop and tiles set to Require PIN. |
| `pin.change` | Choose a new PIN. You'll enter the current one first. |
| `pin.off` | Removes the PIN. Settings, Exit to Desktop and protected tiles open without it. |
| `kioskLock` | ⌘Tab, Force Quit and other apps can't take over the TV, and ⌘Q asks for the PIN when one is set. Exit to Desktop is the way out. |
| `accessibility` | Needed for Home in other apps, the media keys, full-screen apps and the phone remote in other apps. |
| `launchAtLogin` | Opens MMTVL when this Mac starts up. |
| `approveLoginItem` | macOS asks you to allow MMTVL in System Settings → General → Login Items. |
| `relaunch` | Quits and reopens MMTVL. Picks up changes made by hand to its settings files. |
| `exit` | Leaves MMTVL for the macOS desktop. Home brings MMTVL back. |
| `about.showOnHome` | Shows the version and build under the clock, for testing builds. |
| `iptv.homePreview` | Loads the channel, muted, while the Home screen shows; you see it when Live TV is focused. |
| `iptv.guideSource` | Use the guide the playlist names, or your pasted guides. Your pasted guides are kept either way. |
| `iptv.refresh` | Downloads the playlist and the guides again now. |
| `iptv.groups` / `iptv.hiddenChannels` / `iptv.teams` | Which playlist groups show · Channels hidden from the guide · Your teams' live games, in the guide's Teams group. |
| `plex.signIn` | Shows Continue Watching on the Home screen. Uses a code at plex.tv/link; no password is typed here. |
| `cast.youtube.enabled` | Phones on this network list MMTVL in the YouTube app's Cast menu. |
| `cast.airplay.receiver` | Opens AirDrop & Handoff in System Settings, where AirPlay Receiver is turned on. |
| `cast.android.autostart` | Keeps Reflector running hidden, so Android phones can mirror at any time. |
| `phone.enabled` | Serves the phone remote's page on this Mac's network address. |
| `phone.accessibility` | Needed to type from the phone and to control Plex, Prime Video and the browser. |
| `tile.visible` · `tile.fullScreen` · `tile.requiresPIN` · `tile.start` · `tile.art` · `tile.move` · `tile.remove` | Show this tile on the Home screen · Open the app full screen · Ask for the PIN before opening · MMTVL opens on this tile, and Home returns to it · Designed art, the app icon, or your own picture · Move the tile with Up and Down · Removes the tile. Built-in tiles can be added back from Add Tile. |
| `binding.global` | This button also brings MMTVL back while another app is in front. Needs Accessibility access. |

The details these replace are removed:
- `channelUp` "Changes channel in Live TV";
- `accessibility` "Needed for Home…";
- `kioskLock` "⌘Tab, ⌘Q and the Dock…";
- `about.showOnHome` "Under the clock…";
- `pin.set` "Guards…";
- `iptv.homePreview` "Loads the channel…";
- `iptv.guideSource` "Your pasted guides are kept…";
- `plex.signIn` "Shows Continue Watching…";
- `cast.airplay.receiver` "Opens AirDrop…";
- `phone.accessibility` "Needed to type…";
- `tile.start`'s default "MMTVL opens on this tile…". Its status "Show it on the Home screen first" stays.

Also drop the PIN section's footer, which now duplicates `pin.set`'s description.

### View (`SettingsView.swift`, new `SettingsColumnView.swift`, `SettingsRowView.swift`)

- `SettingsView` is a `VStack` of the title, the track (`HStack(spacing: gap) { ForEach(model.columns) { SettingsColumnView(…) } }` with `.offset(x:)`, `.frame(width: canvas, alignment: .leading)`, `.clipped()` and `.animation(reduceMotion ? nil : Theme.settingsPageAnimation, value: trackPosition)`) and the band. `trackPosition` (step 9) is `-1` at the root and `max(0, depth − 2)` deeper, so a category open and a return to the root run the slide too.
- `SettingsColumnView(model:, column:, …)`:
  - for `.current`, the list with focus;
  - for `.parent`, either `accessory(for: current page)` centered, or that page's sections with `parentSelectionRowID` drawn as selected;
  - for `.empty`, `.hidden`, or a nil page, `Color.clear`.

  Its content gets `.id(column.page)` with `.transition(.opacity)`, so replaced and popped pages fade. Each list has its own `ScrollViewReader`, centering the focused row (current) or the selected row (parent). A column draws no hover highlight unless it's current.
- **Mouse:**
  - Current column: hover and click call `onHoverRow` and `onActivateRow` with the row's id and its column's page; the model ignores rows that aren't on the current page (review fixes). A row click within the system's double-click interval of a parent column click is ignored.
  - Parent column: a click anywhere calls `onActivateParent` (router to `settings.activateParentColumn()`).
  - Scroll-wheel focus stays as the router does it today.
- **`SettingsRowView`** takes `style: .focused / .selected / .normal` instead of `isFocused`, plus an optional `highlightNamespace`. Info rows draw the quiet fill.
- **Theme tokens** to add:
  - `settingsColumnWidth` (840), `settingsColumnGap` (80), `settingsSideMargin` (120);
  - `settingsBandHeight` (104), `settingsBandMaxWidth` (1400), `settingsDescriptionFont` (28);
  - `settingsSelectedRowFill` (0.4), `settingsRowCapsuleFill` (0.075), `settingsInfoRowFill`;
  - `settingsDimmedColumnOpacity` (0.55), `settingsPreviewOpacity` (0.45);
  - `settingsPageAnimation` (`.spring(response: 0.45, dampingFraction: 0.85)`), `settingsAccessorySymbolSize` (240).

  Remove `settingsSideColumnWidth`, `settingsListWidth`, `settingsPageImageSize` and `settingsHintFont` once nothing uses them.

  Step 9 adds `settingsRootColumnLeading` (derived, `(canvasSize.width − settingsColumnWidth) / 2` = 540) and removes `settingsPreviewOpacity`.

### Local decisions

- **L1** A two-column sliding track (user choice 2026-11-04: "sliding columns"). The root list starts centered with nothing beside it; opening a category slides it left and the category in on the right, and going back to the root slides it back to the center (user choice 2026-11-04, after step 8: no dimmed preview of the focused category, which steps 4–8 built).
- **L2** A visual that does real work (QR code, tile art, the learn prompt) replaces the parent column. Decorative page symbols are dropped (the user doesn't want a big icon).
- **L3** The bottom description band shows a mode hint, else the focused row's description. The generic hint line is dropped, as on tvOS.
- **L4** Rows are separate glass capsules with uppercase section headers, as on tvOS 27, instead of one panel.
- **L5** One white highlight per column slides between rows (`matchedGeometryEffect`). Reduce Motion crossfades.
- **L6** The root holds only categories (user choice 2026-11-04). The rows inside keep their ids.
- **L7** Right on a disclosure row opens it, and Left goes back a page. This replaces M2b L13 for Settings.
- **L8** `detail` holds status and changing messages; `description` holds explanations.

## Implementation steps

The project must build, and `xcodebuild … test` must pass, after every step.

- [x] **1. Page-parametrized builders**: files `Settings/SettingsModel+Pages.swift`, `Settings/SettingsView.swift`
  - Change `sections` to `sections(for:)`, `pageTitle` to `title(for:)` and `pageImage` to `accessory(for:)`, keeping `sections` and `pageTitle` as wrappers for the top page. `accessory` returns nil except for the five L2 pages. `.tile` changes from the app icon to `.tileArt(itemID:, .current)`.
  - The view uses `accessory(for: page) ?? .symbol("gearshape")` for now.
  - Update the `pageImage` assertions to `accessory(for: model.page)` in `SettingsPlexTests.swift:53`, `SettingsTileArtTests.swift:28–32` and `SettingsPhoneRemoteTests.swift:86, 93`.
  - Done when: the tests pass and Settings looks as before.
- [x] **2. Root categories**: files `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, `MMTVLTests/SettingsModelTests.swift`, `MMTVLTests/SettingsTestSupport.swift` if a helper helps
  - Add the five pages, split `rootSections` into `remoteInputSections`, `youtubeSections`, `restrictionsSections`, `systemSections` and `aboutSections`, and make the new root (L6 table, with values and titles).
  - Tests:
    - the root tests open the category first (add a helper `model.open(_ page:)` = `perform(.push(page))`);
    - `initialFocusIsFirstRow` expects `homeScreen`;
    - `upDownMovesAndClamps` runs on `.remoteInput` (clamps at `phoneRemote`);
    - `accessibilityRowRequestsAccess` runs on `.system`;
    - `pushAndPopRestoresFocus` uses `homeScreen`;
    - the PIN tests and `kioskLock` (around line 732) run on `.restrictions`;
    - `relaunch` and `exit` (around line 95) run on `.system`.
  - Add `rootListsCategories`: the ids in order, and each row's action `.push` of the right page.
  - Done when: the tests pass. In the windowed app the root shows nine categories, and each opens its page.
- [x] **3. Descriptions and the band text**: files `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, tests
  - Add `SettingsRow.description`, fill in the L8 table and remove the replaced details and the PIN footer. Add `bandText` and remove `hint`.
  - The view shows `bandText ?? ""` where the hint was.
  - Tests: lines 377, 463 and 723 assert `description`; `bandTextPrefersModeHint` covers move mode, `.learnButton`, and otherwise the focused row's description or nil.
  - Done when: the tests pass.
- [x] **4. Columns and Left/Right**: files `Settings/SettingsModel.swift`, `Launcher/AppRouter.swift` (closures only), tests
  - Add `Column`, `columns`, `previewPage`, `parentSelectionRowID`, `activateParentColumn()`, `activatePreviewColumn()` and the L7 Left/Right handling.
  - Tests:
    - `previewPageFollowsRootFocus`: nil below the root, and nil when the focused root row doesn't push;
    - `columnsRoles`: depth 1 is [current, preview], depth 3 is [hidden, parent, current, empty];
    - `rightOpensDisclosureRow` and `rightIgnoresToggle`;
    - `leftPopsExceptRootAndLearn`;
    - `leftAndRightInertInMoveMode`;
    - `parentSelectionIsOpeningRow`;
    - `sectionsForPreviewHasNoSideEffects`: building `sections(for: .plex)` and `(.casting)` from the root records no `refreshPlex` or `refreshCasting` in `SettingsTestSupport`'s recorder.
  - Done when: the tests pass.
- [x] **5. Column track view, accessory and band**: files `Settings/SettingsView.swift`, new `Settings/SettingsColumnView.swift`, `DesignSystem/Theme.swift`, `Launcher/AppRouter.swift`
  - Build the L1 track, the L2 accessory in the parent column, the L3 band and the gray title, using the new tokens. Pass `onActivateParent` and `onActivatePreview` from the router. Rows keep today's look for now.
  - Done when, in the windowed app:
    - the root shows the list on the left and the preview on the right;
    - Select or Right opens a category with no slide;
    - deeper pages slide;
    - Back or Left reverses;
    - Pair a Phone and Sign In to Plex show the QR code on the left, and Tile Art shows its preview.
- [x] **6. Row capsules, headers and the sliding highlight**: files `Settings/SettingsRowView.swift`, `Settings/SettingsColumnView.swift`, `DesignSystem/Theme.swift`
  - Apply L4 and L5: the capsule shapes in a `GlassEffectContainer`, the selected style in the parent, the info-row fill, uppercase headers, the matched-geometry highlight, and the Reduce Motion and Reduce Transparency paths. Remove the unused old tokens.
  - Done when: the highlight slides on Up/Down (and on Channel Up/Down paging); with Reduce Motion it crossfades; with Reduce Transparency the rows are solid.
- [x] **7. Motion tuning**: files `Settings/SettingsView.swift`, `Settings/SettingsColumnView.swift` (tuned by judgment per user choice 2026-11-04; user reviews on the TV in step 10)
  - Tune `settingsPageAnimation`, the page fade on push and pop, the replace crossfade (learn → confirm; Plex link → servers when signed in) and the band crossfade, until no column pops in or out abruptly.
  - Record the final values here under *Deviations & questions*.
  - Done when: the user approves the motion in the windowed app.
- [x] **8. Docs**: files `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan
  - Update the Settings paths in `CLAUDE.md`:
    - "Settings root → Keep Other Apps Out" (twice) becomes "Settings → Restrictions → Keep Other Apps Out";
    - "Settings root → About" becomes "Settings → About";
    - "Settings → Remote & Input → Channel Up" stays (now a page);
    - "Settings → Relaunch MMTVL" becomes "Settings → System → Relaunch MMTVL";
    - "Settings → Sign Out & Clear YouTube Data" becomes "Settings → YouTube → Sign Out & Clear".
  - Also mention the layout in the "UI is designed…" bullet (D42).
  - Check the master plan and the open sub plans for old paths (`grep -n "Settings root\|Settings → Relaunch\|Settings → Sign Out"`).
  - Done when: the grep finds no stale paths.
- [x] **9. Centered root, no preview**: files `Settings/SettingsModel.swift`, `Settings/SettingsView.swift`, `Settings/SettingsColumnView.swift`, `DesignSystem/Theme.swift`, `Launcher/AppRouter.swift` (one closure), `MMTVLTests/SettingsModelTests.swift`, `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan (user request 2026-11-04; see *Research & findings → Centered root, no preview*)
  - **Model.** `columns` appends an `.empty` column at every depth (drop the root's `.preview` branch). Remove `Column.Role.preview`, `previewPage` and `activatePreviewColumn()`. Keep `columnClickedAt` and the double-click guard for parent clicks; fix the comments that say "parent or preview" (lines 72 and 252).
  - **Track.** In `SettingsView`, replace `trackShift` with `trackPosition: Int` (`stack.count == 1 ? -1 : max(0, stack.count − 2)`) and compute `trackOffset` from it: `Theme.settingsRootColumnLeading` at `-1`, else `Theme.settingsSideMargin − CGFloat(trackPosition) × (width + gap)`. Key the track's `.animation(_:value:)` and the Reduce Motion `.id(…)` on `trackPosition`, so a category open and a return to the root slide (Reduce Motion: fade through). Update the doc comment on `trackShift`/L1.
  - **Columns.** In `SettingsColumnView`, remove the `.preview` cases (`content`, `opacity`, `onClick`), the `onActivatePreview` parameter, and the preview branch of `SettingsPageList`'s `onChange(of: role)` (it just calls `scroll(proxy, animated: true)`); fix the doc comments that mention the preview. Remove `onActivatePreview` from `SettingsView` and `AppRouter.swift:934`.
  - **Theme.** Add `settingsRootColumnLeading` (derived, 540, with a comment: the root column centered on the canvas); remove `settingsPreviewOpacity`.
  - **Motion.** Use the existing `settingsPageAnimation` (`.spring(response: 0.4, dampingFraction: 1)`) for the 460-pt slide. The category page fades in with `settingsFadeInAnimation` as it slides in, and fades out with `settingsLeaveFadeAnimation` as it slides away (both already apply: column 1 goes `.empty ↔ .current`). Watch it in the windowed app; if the page is fully opaque well before the slide ends, or the 460-pt move feels slower or faster than the 920-pt one deeper, tune by judgment (as in step 7) and record the values under *Deviations & questions*. Keep the root's dimming (`settingsFadeAnimation`, 0.25 s) as it is unless it visibly lags the slide.
  - **Tests** (`SettingsColumnsTests`):
    - remove `previewPageFollowsRootFocus`;
    - `columnsRoles`: depth 1 is `[.current, .empty]` with pages `[.root, nil]` and ids `[0, 1]`; depths 2 and 3 unchanged;
    - `parentAndPreviewColumnsActivate` → `parentColumnActivates` (open Live TV with `open(_:)`, then the parent half as today);
    - `sectionsForPreviewHasNoSideEffects` → `sectionsForOtherPagesHaveNoSideEffects` (same checks; the parent column builds pages that aren't on top);
    - `rowClickRightAfterAColumnClickIsIgnored`: the first half opens `.remoteInput` and `.remoteButtons`, clicks the parent column (back to Remote & Input) and checks that a row click on `.remoteInput` within the interval is ignored and one after it acts; the second half (back to the root) stays;
    - `rowsOfOtherPagesIgnoreThePointer`: drop the "preview's rows" part.
  - **Docs.** `MASTER_PLAN.md` D42 and the M7g row in §6 already describe the centered root (updated with this plan change). `CLAUDE.md`'s "UI is designed…" bullet: say the root list starts centered and slides left when a category opens.
  - Done when: the tests pass, and in the windowed app:
    - Settings opens with the root list centered and nothing beside it, and the list doesn't move while Up/Down walks the categories;
    - Select, Right or a click on a category slides the root left (dimming, the opening row selected) while the category slides in on the right with focus;
    - Back, Left or a click on the root column from a category slides the root back to the center (brightening, focused on the row it opened) while the category slides off to the right and fades;
    - deeper pages, their pops and the accessories (QR codes, tile art, the learn prompt) work as before;
    - Restrictions → Set PIN returns to the Restrictions page with the root on the left; leaving Settings and opening it again starts centered with no slide;
    - with Reduce Motion forced (as in step 7), a category open and a return to the root fade through instead of sliding.
- [x] **10. TV pass**: `scripts/test-build.sh` on the MM
  - Done when the user confirms, with the Siri Remote and with the phone, that:
    - the text is readable from the couch;
    - the band's descriptions are legible;
    - the root starts centered, and the slides to and from a category, the deeper slides and the sliding highlight are smooth on the mini;
    - every category is reachable;
    - the QR codes scan.
  - **Done 2026-11-08 (user):** the TV pass is done. Settings has run on the mini through builds 21–28; M7h's Settings pages (Audio & TV, Siri Remote) use the same columns.

## Tests

- `MMTVLTests/SettingsModelTests.swift`: the updated root tests and the new tests from steps 2–4.
- `MMTVLTests/SettingsPlexTests.swift`, `SettingsTileArtTests.swift`, `SettingsPhoneRemoteTests.swift`: `accessory(for:)` instead of `pageImage`.
- The other Settings test files (`SettingsCastingTests`, `SettingsRemoteButtonsTests`) push their pages directly and should pass unchanged.
- Step 9: `SettingsColumnsTests` loses the preview (`previewPageFollowsRootFocus` goes; `columnsRoles`, the column click and pointer tests change as listed in the step).
- Run: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`. For one suite: `-only-testing:'MMTVLTests/SettingsModelTests'`.

## Manual verification

*Closed 2026-11-08 with the user's TV pass (step 10): these behaviours were checked on the TV, not separately in a window on the dev Mac.*

- [x] Windowed (`open build/Build/Products/Debug/MMTVL.app --args -windowed YES`): the root list is centered with nothing beside it. Walk every root category with Up/Down: the list stays put, and the band shows each description.
- [x] Select and Right open a category: the root slides from the center to the left and the category slides in on the right. Going deeper slides left. Back and Left come back with the opening row still selected and focused, and back at the root the list slides to the center again.
- [x] Home Screen → a tile shows the tile's art on the left. Move mode shows its hint in the band, and Left/Right do nothing.
- [x] Remote & Input → Remote Buttons → Home → Add a Button: the hand symbol shows on the left, and the band reads "Waiting for a button…". Confirm → Try Again crossfades.
- [x] Phone Remote → Pair a Phone and Plex → Sign In: the QR codes show large on the left and scan.
- [x] Restrictions → Set PIN: the PIN screen returns to the Restrictions page.
- [x] Mouse: hover and click rows in the current column; click a category (opens it with the slide) and the parent column (goes back).
- [x] System Settings → Accessibility → Display: Reduce Motion (crossfades only) and Reduce Transparency (solid rows).
- [x] On the TV (step 10).

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Twenty or more glass capsules (in two columns) are slow on the mini | Focus moves stutter, or GPU time spikes in Instruments | Draw rows with `settingsRowCapsuleFill` (white at about 0.10) plus `GlassRimLayer` instead of `glassEffect`; keep glass only for the current column |
| `matchedGeometryEffect` glitches while the list scrolls (the highlight lags or jumps) | Visible during long lists (Add Tile, Remote Buttons) | Per-row focus animation as today, with the white fill appearing per row |
| 840-pt columns cramp long rows (guide labels, tile details) | Values truncated at the right | Asymmetric widths (parent 680, current 1000) with the same track math, using per-index x positions instead of a uniform stride |
| The track's insert and remove look abrupt | A column pops in before the slide | Always render `stack.count + 1` columns (the empty one), so a push fills an existing slot; fade the content with `.transition(.opacity)` |
| The 460-pt slide to or from the centered root looks abrupt next to the root's 0.25 s dimming, or the category is fully faded in long before it stops (step 9) | Seen in the windowed app or on the mini | Tune `settingsFadeInAnimation`'s delay or give the category open its own fade-in, by judgment as in step 7 |

## Deviations & questions

Executors append here: the date, the step, what happened, and what they need.

- **2026-11-04, step 1:** done as written. `accessory(for:)` uses a `default: nil` for the pages without an accessory. `tileArtPreviewChoice` still reads the top page's focused row, which is right while `.tileArt` is on top (the only time it shows today); step 5 should keep that in mind if the parent column ever shows `.tileArt`'s accessory with another page on top (it can't: `.tileArt` has no child pages).
- **2026-11-04, step 2 (mechanical):**
  - Root values as read from the L6 table: Restrictions shows "PIN On" / "PIN Off"; About shows the version only ("1.1.0"). The root is one untitled section (`categories`). The Home Screen row's title is "Home Screen" (was "Edit Home Screen").
  - Section ids and titles on the new pages: Remote & Input keeps section `input`, YouTube keeps `youtube` (with the Parent code footer) and About keeps `about` (with the "Settings are saved in…" footer), all three **without** a header, since it would repeat the page title. Restrictions: `pin` ("PIN") and new `otherApps` ("Other Apps"). System: `permissions` ("Permissions"), `startup` ("Startup") and new `mmtvl` ("MMTVL"). Row details are unchanged (step 3 moves them).
  - `hint` lists the five new pages with "Select: choose · Back: return" until step 3 removes it.
  - More tests pinned the old root than the step lists, and were moved onto their category with `open(_:)` the same way: `togglingAppliesSettings`, `globalInputNeedsAccessibilityDetail` (`.remoteInput`); `approveLoginItemRowOnlyWhenWaitingForApproval`, `refreshStatusRereadsAccessibility` (`.system`); `windowedModeMarksKioskOnlyRows` (both); `rootHasYouTubeRows` (`.youtube`); `aboutShowsTheVersionAndBuild` (`.about`); `channelUpRowTogglesTheDirection` (`.remoteInput`). Contrary to *Tests*, four other files pinned root rows and changed: `SettingsRemoteButtonsTests.rootHasTheRemoteButtonsRow` and `SettingsPhoneRemoteTests.rootRowShowsOnOff` open `.remoteInput`; `SettingsCastingTests` now expects Casting right after `youtube`, and `SettingsPlexTests` Plex right after `liveTV` (the L6 order).
  - Manual check left for the user: in the windowed app the root shows nine categories and each opens its page (`rootListsCategories` covers the ids and push targets).
- **2026-11-04, step 3 (mechanical):**
  - Descriptions as in the L8 table, each ending with a period; `iptv.homePreview`'s "home screen" became "Home screen". The tile rows' descriptions are the table's phrases as sentences (`tile.move` shares a `tileMoveRow(id:)` builder between the Settings tile and the others).
  - `bandText` shows the move hint whenever `movingTileID` is set (only ever on `.homeScreen`), then "Waiting for a button…" on `.learnButton`, then the focused row's `description`. `hint` is gone; the view shows `bandText ?? ""` with the old hint font until step 5.
  - Kept, since the "removed" list doesn't name them, though they now overlap their row's description: `iptv.teams`'s detail ("Live games and channels of your teams…"), `tile.remove`'s detail ("You can add it back from Add Tile", built-in tiles only) and the Plex page's signed-out footer ("Signing in uses a code at plex.tv/link…"). Drop them in step 6 if the user wants less repetition.
  - Test `bandTextPrefersModeHint` is next to `channelUpRowTogglesTheDirection`; the three detail tests now expect `detail == nil` plus the description.
- **2026-11-04, step 4 (mechanical):**
  - `AppRouter.swift` is unchanged: Left/Right already reach `settings.handle`, which returns `true` for both everywhere, and the mouse closures (`onActivateParent`, `onActivatePreview`) are wired in step 5 with the view. `pop()` is all Back does below the root, so Left runs the same teardown (pairing, learning and the Plex link stop; messages clear).
  - `activateParentColumn()` ends move mode first, like a row click in move mode (`activate(rowID:)`), then pops (nothing on the root). `activatePreviewColumn()` performs `.push(previewPage)`.
  - `previewPageFollowsRootFocus`: every root row pushes, so "nil when the focused row doesn't push" can't be reached on the root; the test checks nil below the root on a pushing row and on a toggle. Extra test `parentAndPreviewColumnsActivate` covers the two mouse functions; `leftPopsExceptRootAndLearn` also checks that Left ends pairing like Back.
- **2026-11-04, step 5 (mechanical):**
  - **Side margin 80, not 120.** 120 + 840 + 80 + 840 + 120 = 2000 > 1920, so with 120 the right column ended 40 from the edge. `settingsSideMargin` is derived, `(canvas − 2 × width − gap) / 2` = 80, so both sides match and the columns keep 840 (no truncation seen in the pages checked).
  - **`.geometryGroup()` on each column.** Without it, content fading in (the new page) appeared at its final place and fading-out content (the page going off to the left) stayed put while the track slid. With it, everything slides with its column and fades.
  - Extra token `settingsFadeAnimation` (ease-in-out 0.25 s) for the column content crossfade (keyed by what the column draws: nothing, a page's list, or the current page's accessory), the dim/brighten on role changes, the title and the band. Step 7 tunes it with `settingsPageAnimation`.
  - The **accessory is not dimmed** (the plan dims the parent column): a dimmed QR code scans worse and tile art should show its real colors. The parent list is dimmed (0.55), the preview 0.45.
  - Accessory sizes unchanged: QR codes at `settingsQRCodeSize` (440, nearest-neighbor, crisp); tile art at `settingsArtPreviewSize` (500 × 300), since picture previews are loaded at `tileArtPreviewPixels` (600 px) and would blur larger; symbols at `settingsAccessorySymbolSize` (240).
  - Interim selected style: `SettingsRowView` gained `isSelected` (fill `settingsSelectedRowFill`, white 0.28, primary text). Step 6 replaces `isFocused`/`isSelected` with `style`. Each list column still sits on one `.glassPanel()` (today's look); the panel dims with its column.
  - Parent and preview columns are covered by a clear click layer (parent → `activateParentColumn`, preview → `activatePreviewColumn`), so their rows get no hover or clicks; their row closures are inert too.
  - Removed `settingsSideColumnWidth`, `settingsListWidth`, `settingsPageImageSize` and the now unused `settingsColumnSpacing`. **`settingsHintFont` stays**: the PIN screen, YouTube, Live TV, the guide, the Live menu and Live TV search use it, so step 6 shouldn't remove it.
  - Checked in the windowed app: the root list and preview (the preview follows focus); Right opens a category with no slide (the preview brightens, the root dims with the opening row selected); a deeper push slides left with the new page fading in from the right; Back and Left reverse, Left on the root does nothing; Pair a Phone and Sign In to Plex show the QR code on the left; a tile shows its art, and Tile Art's preview follows the focused style; a click on the preview opens it and a click on the parent goes back. **Not checked:** hover in the current column (synthetic pointer moves didn't trigger it, and the user was using the Mac, so the check stopped), Reduce Motion (step 6), learn → confirm crossfade.
  - The root's nine rows are taller than the column with today's 80-pt rows, so About sits just below the fold until focused. Step 6's row sizes decide whether that stays.
- **2026-11-04, step 6 (mechanical):**
  - **Row shape.** `SettingsRowShape` (an `InsettableShape`, so `glassPanel(in:)` takes it): a capsule when the row has no `detail`, else a continuous rounded rectangle at `settingsRowCornerRadius`, now 28. The Live TV menu used that token for its 12-pt rows, so it got its own `liveMenuRowCornerRadius` (12) and looks as before (`IPTV/LiveMenuView.swift`, one line; not a file the step names).
  - **Layers.** The row's views are a `ZStack` of the fill and the content on one `.glassPanel(in:)` (info rows: `settingsInfoRowFill`, white 0.05, no glass). Only the fill and the content scale (1.03); the glass doesn't, so it never reaches the next row inside the `GlassEffectContainer`. The fill carries the shadow. Two things found on screen forced this: (1) with the whole row under `.scaleEffect`, `matchedGeometryEffect` drew the white fill at the unscaled size, shifted left, with the scaled glass showing at its right; (2) a glass layer as a sibling of the content (instead of its surface) was drawn over the text by the container. **No `zIndex` on the focused row:** changing it made the container rebuild both rows' glass, which shrank them to about 85 % and regrew them on every move.
  - **Highlight.** One `matchedGeometryEffect(id: "focus")` per current column (`@Namespace` in `SettingsPageList`); the content is animated with `Theme.focusAnimation` on the current column's focused row id. The parent and preview columns get no namespace (no white highlight there anyway). A lifted row that isn't focused (can't happen today) would draw a plain white fill.
  - **Headers** `title.uppercased()` in `settingsSectionFont`, now 22 bold; headers and footers are indented by the new `settingsRowTextInset` (32, the row text's padding). `settingsRowSpacing` (8) and `settingsSectionSpacing` (40) are unchanged. No old token became unused (`settingsHintFont` stays, see step 5).
  - **Root fold:** row height and spacing didn't change, so About is still just below the fold until focused (nine rows are about 864 pt with the list's padding; the column shows about 770).
  - Checked in the windowed app (driven by a temporary command-file hook in the router, since the user was using the Mac; removed before the commit): the highlight slides on Up and Down (mid-animation frames show it between rows), on Page Down (Channel Down) in Home Screen and in Add Tile while the list scrolls, and on quick repeated Downs; it lands on the right row each time, with no lag visible. Two-line rows are rounded rectangles, one-line rows capsules, info rows quiet; the parent column shows the opening row in the gray selected fill. With the namespace turned off (the Reduce Motion path), the fill crossfades per row. **Not checked:** the real Reduce Motion and Reduce Transparency settings (the user's system settings weren't changed). By the code, Reduce Motion passes no namespace (per-row crossfade, as before) and the track doesn't slide (step 5); Reduce Transparency makes each row's `glassPanel` the solid `solidPanelFill`. **Performance** on the mini (about 20 glass rows per column, plus the preview's) is for the TV pass (now step 10).
- **2026-11-04, step 7 (tuned by judgment, per the user's choice; the user reviews it on the TV in step 9):** watched in the windowed app as 60 fps window recordings, driven by a temporary command-file hook (removed before the commit). Final values, all in `Theme.swift`:

  | Token | Before | After |
  |---|---|---|
  | `settingsPageAnimation` (track slide) | `.spring(response: 0.45, dampingFraction: 0.85)` | `.spring(response: 0.4, dampingFraction: 1)` |
  | `settingsFadeAnimation` (now only a column dimming/brightening on a role change) | `.easeInOut(duration: 0.25)` | unchanged |
  | `settingsFadeOutAnimation` (new) | — | `.easeOut(duration: 0.12)` |
  | `settingsFadeInAnimation` (new) | — | `.easeOut(duration: 0.22).delay(0.06)` |
  | `settingsFadeThrough` (new transition) | `.opacity` crossfade | insertion `.opacity` with the fade-in, removal `.opacity` with the fade-out |
  | `settingsLeaveFadeAnimation` (new) | — | `.easeIn(duration: 0.35)` |
  | `focusAnimation` (highlight slide) | `.spring(response: 0.3, dampingFraction: 0.8)` | unchanged |

  - **Fade through instead of crossfade** (title, band, replaced or previewed page). Before, the old and new versions sat on top of each other for about 150 ms. On a category open the two titles overlapped ("Settings" over "Home Screen"). On a quick move in the root, the preview showed two lists at once and the band two descriptions. On learn → confirm, two white highlights showed in the same column ("Cancel" and "Use This Button"). Now the old version fades out in 0.12 s and the new one fades in after 0.06 s. What's left is at most one or two frames of faint overlap. The title is now an `.id(title)` view with this transition, keyed on the title text (it was `.contentTransition(.opacity)` keyed on the page). Plex link → servers is the same code path as learn → confirm (`pop()` then `push()` in one update; the column's content changes and the track doesn't move), so it was checked by code only.
  - **A page leaving the screen fades over the slide.** A column becoming `hidden` (pushed off to the left) or `empty` (popped off to the right) uses the transaction animation `settingsLeaveFadeAnimation` for its removal, so it visibly slides away and fades as it goes. Content replaced in place fades out in 0.12 s. Insertions always use the fade-in. A hidden column also keeps the parent's 0.55 dimming: before, its opacity went 0.55 → 1 while it faded out, so it brightened briefly as it left.
  - **Dimming scoped to the opacity.** The role animation is now `.animation(settingsFadeAnimation) { $0.opacity(opacity) }`, so it no longer competes with the content's transition animation (before, both `.animation(_:value:)` modifiers wrapped the whole column).
  - **Slide spring, critically damped.** Measured by tracking the new page's highlight edge frame by frame. Before: it settled in about 0.35 s with no visible overshoot (about 0.6 % in theory). With damping 1 at response 0.45 the tail dragged (6 % still left at 0.3 s), so response 0.4: about 11 % left at 0.22 s (same as before), 3 % at 0.33 s and settled by 0.45 s, moving in one direction only. The slide now keys on the track shift (`max(0, depth − 2)`), not `stack.count`, so a category open or a return to the root (no slide) doesn't run the spring.
  - **Reduce Motion:** before, the track jumped to its new place with no animation. Now the track gets `.id(trackShift)` with `settingsFadeThrough`, so it fades through on a level change instead of jumping. Checked by forcing the flag in the temporary hook; the system setting wasn't changed. Category opens are unchanged with Reduce Motion (no shift, in-place dimming), and the highlight still crossfades per row.
  - **Highlight next to the slide:** unchanged and fine. On a push, the new page's white highlight fades in while the page slides in, white by about 0.25 s. Up/Down slides stay within the column.
  - **Band during fast scrolling** (Up/Down every 80 ms): one description at partial strength, changing each step, with at most a faint second one for a frame or two. Before, up to three overlapped. It is fully legible about 0.25 s after the last move.
  - **Known, left as is:** when a row goes from selected (gray) to focused (white), or back, its text color crossfades from white to black over the gray-to-white fill. For about two frames the text is about the same gray as the fill, so the capsule looks blank. This happens on Back/Left onto the opening row and on a category open. It was there before step 7. Fixing it would mean changing how the row draws its colors, not only the motion.
  - **Incident, fixed:** while recording, the user's pointer was over the MMTVL window, and hover moved focus (the hook didn't block the pointer at first). One scripted Select then landed on About → Show Version on Home and turned it **off**. MMTVL was quit and `settings.json` set back to `"showVersionOnHome": true`, its value before. No other file changed: `launch-items.json` and `key-bindings.json` keep their old modification dates. After that, the hook ignored pointer hover, clicks and scrolls.
- **2026-11-04, review fixes** (after three read-only reviews: design, security, correctness; the user's decisions of 2026-11-04):
  - **User decisions:** ignore held Left/Right repeats in Settings; apply all of the design review's fixes; cut the long footers to one plain sentence each; the parent column's selected fill goes to white 0.4.
  - **Held Left/Right (commit A).** `InputRouter.dispatch(_:isGlobal:isRepeat:)` (default `false`) passes the flag to its handler, now `(RemoteCommand, isRepeat) -> Bool`; AppDelegate forwards it to `AppRouter.handle(_:isRepeat:)`, which gives it to `SettingsModel.handle(_:isRepeat:)` only. The local key monitor sets it from `NSEvent.isARepeat`, the controller's repeat task (D-pad and left stick) sets it to `true`; the phone, media keys and the event tap (which already drops repeats) leave it `false`, so they're fresh presses. `RemoteCommand` is unchanged. Settings swallows repeated Left/Right (returns `true`, nothing happens); every other screen ignores the flag. This also covers a key just learned for Left auto-repeating on the confirm page.
  - **Mouse guards (commit A).** One mechanism for the closing-column clicks: the row closures pass their column's page, and `focus(rowID:on:)`/`activate(rowID:on:)` ignore rows not on the current page (a page fading out after a pop or replace keeps its last role, so a role check in the view couldn't cover a replace). The `isCurrent` checks in the row closures went. `activate(rowID:on:)` also ignores clicks within `NSEvent.doubleClickInterval` (injectable `doubleClickInterval`, the model's `now` clock) of a parent or preview column click that changed the page. Hover isn't guarded: it never runs an action.
  - **Preview scroll (commit A).** A column that becomes the preview (Back from a long category page) scrolls to its top.
  - **Tests (commit A).** The column, Left/Right and band tests moved from `SettingsLiveTVTests` into a new `SettingsColumnsTests` suite; `rightIgnoresToggle` now also checks Relaunch and Exit to Desktop (non-push actions) and a page of info rows only (Add Tile while apps load: info rows never take focus, so Right has nothing to act on); the vacuous last check of `previewPageFollowsRootFocus` went (every root row pushes). New: `repeatedRightAndLeftDontChangePage`, `repeatedLeftStaysOnConfirmLearn`, `rowClickRightAfterAColumnClickIsIgnored`, `rowsOfOtherPagesIgnoreThePointer`, and `AppRouterTests.settingsIgnoresRepeatedLeftAndRight`. `InputRouter.dispatch` itself isn't tested (it needs `NSApp.isActive`).
  - **Fit, legibility, copy (commit B).** Token changes, all in `Theme.swift`:

    | Token | Before | After |
    |---|---|---|
    | `settingsRowMinHeight` (Settings only) | 80 | 72 |
    | `settingsBandHeight` | 130 | 104 |
    | list vertical padding (`SettingsColumnView`) | 40 (literal) | `settingsListVerticalPadding` 32 (new token) |
    | `settingsDescriptionFont` | 24 | 28 |
    | `settingsRowDetailFont` (new; Settings rows' second line, badges, chevrons, footers) | `settingsDetailFont` 22 | 24 |
    | `settingsDetailFont` (now only the PIN screen, YouTube and the Live TV menu) | 22 | unchanged |
    | `settingsRowCapsuleFill` (new; action rows, over the glass, under the content) | — | white 0.075 |
    | `settingsSelectedRowFill` | white 0.28 | white 0.4 |
    | `settingsRowCornerRadius` (Settings only) | 28 | 40 |

    - The list's hard `.clipped()` became a mask: a 32-pt fade at the top and bottom (the padding's height), extended 40 pt past the list at each side so the focused row's scale and shadow aren't cut. `scrollEdgeEffectStyle` wasn't used: the mask keeps the band and title clear the same way and is predictable.
    - `SettingsRowView`: `.animation(nil, value: style == .selected)` right after the row's `ZStack`, so selected ↔ focused flips at once (no blank capsule); normal ↔ focused still animates, and so does the column's dimming. Frame captures of Back onto the opening row and of a category open (60 fps) show the text dark on the brightening fill, or white on the gray, in every frame. The focused row's 1.03 scale snaps in that change too.
    - Root fit: with 72-pt rows, the nine categories end well above the band; About is fully visible with its description, unfocused and focused. The kiosk lock's description (the longest, 132 characters) takes 2 lines at 28 pt in the 1400-pt band; 3 lines fit in 104.
    - Copy: the kiosk lock description now says ⌘Q asks for the PIN when one is set (CLAUDE.md: without a PIN ⌘Q quits at once; the old text said ⌘Q and the Dock can't leave). Dropped the `iptv.teams` and `tile.remove` details and the signed-out Plex footer (they repeated descriptions); `tile.remove`'s description is "Removes the tile. Built-in tiles can be added back from Add Tile."; the Home Screen footer is "Hidden tiles stay here but don't show on the Home screen." (the start tile is `tile.start`'s description); the root `plex` description is "Continue Watching from your Plex server on the Home screen." Footers cut to one sentence: Teams "The guide's Teams group shows your teams' live games and the channels showing them now."; AirPlay "Turn on AirPlay Receiver and allow AirPlay for "Anyone on the Same Network" so iPhones list this Mac under Screen Mirroring."; Android "On an Android phone, open Quick Settings → Cast and choose MMTVL Screen Mirroring; Home on the remote ends it." (Reflector's preference checklist stays in CLAUDE.md); Plex HTPC "In the Plex app on a phone, tap Cast and choose Plex HTPC; it must be running, so open it once after a restart." No test asserted the old strings; new test `copyDoesntRepeatDescriptions`.
    - Checked in the windowed app with a temporary command-file hook (navigation only; Select only on rows that open pages; pointer hover, clicks and scrolls ignored; removed before the commit). `settings.json`, `launch-items.json` and `key-bindings.json` have the same modification dates and contents as before. Seen along the way, not changed: on Casting, the Plex HTPC row (an info row) sits below the fold and can't be scrolled to with the remote, since info rows never take focus (as before this fix); Remote Buttons' Fast Forward value wraps to two lines in the 840-pt column.
- **2026-11-04, after the review fixes: info rows at the end of a page.** On Casting, the Plex section (the Plex HTPC info row and its footer) sat below the fold and the remote couldn't reveal it: info rows never take focus, and the list only centered the last focusable row. Fixed for every page in `SettingsColumnView` (`SettingsPageList.scroll`): on the page's first focusable row the list scrolls to its top, on the last one to its end (the padded content's id with anchor `.top` / `.bottom`, same `Theme.focusAnimation`), else it centers the row as before; the parent column's selected row follows the same rule. Focus rules are unchanged (info rows stay unfocusable). The Casting YouTube footer, still three sentences, is now one: "In the YouTube app on a phone, tap Cast and choose MMTVL, or use Link with TV Code in YouTube's settings." No test asserted it. Not checked on screen. Left as they are (two sentences, two lines at 24 pt in the column): the Live TV addresses, guides ("Guide data for…"), Restore Default Tiles, Sign Out & Clear (YouTube), Phone Remote address, Pair a Phone and Plex Sign Out footers. Over two lines: only Tile Art's "Pictures on This Mac" footer (two sentences, three lines), left for the user to decide.
- **2026-11-04, step 8 (mechanical):**
  - `CLAUDE.md`: the plan's paths, using the real row titles: "Settings → Restrictions → Keep Other Apps Out" (twice), "Settings → About", "Settings → System → Relaunch MMTVL" (twice), and "Settings → YouTube → Sign Out & Clear YouTube Data" (the YouTube page's row keeps its full title; "Sign Out & Clear" is only the confirm page's button). Also the other paths the redesign moved: Edit Home Screen → **Home Screen** (Start Here, Start Page, Tile Art: "Settings → Home Screen → a tile → …"), Remote Buttons and Phone Remote (Pair a Phone, `phoneRemoteEnabled`) under **Remote & Input**. The Reflector checklist line no longer points at the Android footer (cut to one sentence in the review fixes). The "UI is designed…" bullet has one sentence on the Settings layout, and the input bullet says Settings ignores held Left/Right repeats.
  - `MASTER_PLAN.md`: the Remote Buttons and Pair a Phone paths in D16, D24 and D27; D42 says held Left/Right repeats are ignored (user choice, review fixes).
  - Left on purpose (historical records, written before today): `M7e-siri-remote-spike.md:33` (a finding from the mini, 2026-10-10, "Settings → Remote Buttons → Home → Add a Button learned…"), `M7f-tv-findings.md:248` and `:250` (research findings and the capture for M7f step 4, done 2026-11-03), and this plan's own step 8 list and findings. The grep finds only these. Not stale: M8's planned "Settings → Licenses" (where it goes in the new root, which holds only categories, is M8's to decide; About is the natural place).
- **2026-11-04, plan change after step 8 (user request):** the root's dimmed preview of the focused category goes. The root list starts centered with nothing beside it; opening a category slides it left while the category slides in on the right, and going back to the root slides it back to the center. Design updated (Goal, L1 track and table, model, view, mouse, tokens, Local decisions L1), research added under *Centered root, no preview*, new step 9 does it, and the TV pass is now step 10. Steps 4–8 stay as written: they record what was built (the preview), which step 9 removes. `MASTER_PLAN.md` D42 and the M7g row updated with this change.
- **2026-11-05, step 9** (an orchestrated pass: implementation, then windowed-app QA, a security review and a design review, each by its own agent):
  - **Code as written.** `columns` ends with `.empty` at every depth; `Role.preview`, `previewPage`, `activatePreviewColumn()`, `onActivatePreview` (model, both views, `AppRouter`) and `settingsPreviewOpacity` are gone; `trackPosition` (−1 at the root) drives the offset, the slide and the Reduce Motion fade-through; `settingsRootColumnLeading` (540) added. `CLAUDE.md`'s "UI is designed…" bullet says the root starts centered and slides left. `MASTER_PLAN.md` D42 and §6 were already current.
  - **Tests (mechanical).** `parentColumnActivates` keeps `press(.down)` before `open(.liveTV)`, because `open(_:)` doesn't move root focus and the back half expects `liveTV` focused. In `rowClickRightAfterAColumnClickIsIgnored`, the row clicked in the first half is `remoteButtons` on `.remoteInput`. Within the interval nothing happens; after it, Remote Buttons opens, so the second half takes two parent clicks to reach the root. Full suite: 904 tests in 106 suites pass.
  - **Motion: one change by judgment (design review).** The three plan criteria pass, so the step 7 tokens stay:
    - the 460-pt slide and the 920-pt one follow the same time curve, as tvOS springs do;
    - the category is opaque at 0.27 s, with 7–9 % of the slide left, the same as a deeper push;
    - the root's dimming finishes at 0.24 s, slightly ahead of the slide.

    One change: on a return to the root, the category moves only 460 pt and stays half on screen, so with `settingsLeaveFadeAnimation` (0.35 s ease-in) it lingered at about 57 % beside the settled root, two highlights at once. `SettingsColumnView.removalAnimation` now uses `settingsFadeAnimation` (0.25 s ease-in-out) for that column only (index 1 becoming `.empty`, which happens only at the root). Re-measured: gone at 0.24 s, together with the root's brightening; a deeper pop is unchanged (0.35 s, slides off).
  - **Windowed checks** (60 fps window recordings, driven by a temporary command-file hook that blocked pointer hover and clicks; removed before the hand-off; `settings.json`, `launch-items.json`, `key-bindings.json`, `iptv-state.json` and `iptv-channels.json` unchanged): all six "Done when" items pass.
    - The root list stays centered through an Up/Down walk of the nine categories.
    - Select, Right and a category click (through `activate(rowID:on:)`) slide it 460 pt left. Back, Left and a parent click (through `activateParentColumn()`) bring it back with the opening row focused.
    - Deeper push and pop slide 920 pt. Pair a Phone, Plex Sign In (QR codes), a tile's art, Tile Art and Add a Button (hand symbol, "Waiting for a button…") show their accessory.
    - Reopening starts centered with no slide. Restrictions → Set PIN → Back returns to Restrictions in place (no PIN was set; none set after).
    - Reduce Motion (forced in the hook) fades through.
  - **Not checked:** the real pointer, the system Reduce Motion setting, and the learn → confirm and Plex link → servers crossfades.
  - **Incident, no harm:** the first version of the hook blocked mouse events only with an `NSEvent` local monitor, which doesn't stop SwiftUI taps. A real click opened Home Screen from the root, and the next scripted Select opened a tile page (both pages that only open, no actions). The files were unchanged. The second version also guarded the click closures in `LauncherRootView`.
  - **Security review:** no findings. Only the parent column has a click layer, and it can only pop. The page and double-click guards in `activate`/`focus(rowID:on:)` are unchanged, and the PIN gate isn't touched.
  - **Left as they are (design review, low):**
    - With Reduce Motion, the whole-track fade-through shows both layouts faintly for 1–2 frames (step 7's `settingsFadeThrough` timing; a track-only transition with a longer delay would fix it).
    - The selected → focused text change on Back still reads briefly washed out (known since step 7).
    - The titles overlap for about two frames (accepted in step 7).
    - The band is empty on the Home Screen page, because the tile list rows have no description (the L8 table gives descriptions only to the rows inside a tile's page).
