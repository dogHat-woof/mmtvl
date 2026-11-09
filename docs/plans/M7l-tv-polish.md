# M7l — TV polish: glass, the home dock, college teams

| | |
|---|---|
| Status | Not planned (research only; plan with `/plan-milestone M7l`) |
| Depends on | M7f (glass L9, Teams L13), M7h (step 13h's shared video layer) |
| Master plan decisions used | D29 (glass), D38 (home layout); from M7f L13 the Teams group |
| Planned | — (requests and research 2026-11-08) |

## Goal

The user's requests from the M7f TV check (2026-11-08, builds 20–28):

1. "tone down glass effect on live TV channel info"
2. "be able to dial in and adjust the glass effect for the whole app or follow system glass setting"
3. "home screen container around first row of app doesn't move when going to the second row"
4. "favorite teams selection should include teams for college football, college basketball, and college baseball. These should be selectable from the guide and not just in settings"

The sections below are research only: no design has been agreed. `/plan-milestone M7l` asks the open questions, then writes the design and steps.

## Research & findings

Paths are under `MMTVL/` unless they start with `MMTVLTests/` or `docs/`. Researched 2026-11-08 on `m7h-siri-remote-and-receiver` (after step 16), by reading the code and the SDK interfaces.

### 1. The Live TV banner's glass

- **Now:** the banner (channel, now/next) and the timeshift bar share one panel in `PlayerOverlayView` (`IPTV/LiveTVView.swift:149-168`). It uses `.glassPanel()` (`:162`, `Theme.glassCornerRadius` 28) over `.background(Theme.liveOverlayGradient)` (`:167`; clear to black 0.85, `DesignSystem/Theme.swift:335`). The behind-live badge (`:141`, capsule) and the error panel (`:195`) use glass too.
- **`GlassPanel`** (`DesignSystem/Glass.swift:6-21`): a `GlassRimLayer` background, then `.glassEffect(Theme.panelGlass, in: shape)`. With Reduce Transparency it draws `Theme.solidPanelFill` instead.
- **Tokens** (`Theme.swift:185-200`):
  - `panelGlass = Glass.clear.tint(.black.opacity(0.22))`;
  - the M7f L9 rim: width 2, top 0.70, middle 0.08, bottom 0.32, sheen 0.14 (before L9: `.regular`, width 1.5, top 0.55, sheen 0.10; see `docs/plans/archive/M7f-tv-findings.md`, L9).
- **Every panel shares `panelGlass`:** the guide (`IPTV/Guide/GuideView.swift:231`), the menu (`LiveMenuView:29`), search (`LiveSearchView:52`), Multiview (`MultiviewView:45/78/94/138`). Changing the token changes them all.
- **SwiftUI's `Glass` (SDK-verified, the SwiftUICore swiftinterface of the Xcode 27.0 and 27.2 SDKs):** only `.regular`, `.clear`, `.identity`, `.tint(Color?)` and `.interactive()`. There's no strength value.
- **Knobs for the banner alone:**
  - `.regular` instead of `.clear`: frosted glass, which bends the moving video less;
  - a darker tint (0.35–0.5);
  - no rim or sheen;
  - a dark scrim inside the glass, as the toast does (`DesignSystem/OverlayToast.swift:167-168`, `Theme.toastScrim` black 0.3, `Theme.swift:425`);
  - a lighter `liveOverlayGradient`.
- **Sketch:** a style parameter on `glassPanel` (a `Glass` value and rim on/off; `.standard` by default) and banner tokens (e.g. `liveBannerGlass`), passed only at `LiveTVView.swift:162` (and maybe `:141`).
- **Open (user):**
  - Does "tone down" mean more frosted and less see-through, or fainter?
  - Is the bright rim the problem?
  - Should the badge and the error panel change too?

### 2. An app-wide glass setting, or following the system

- **Centralised:**
  - Panels go through `GlassPanel` and one `Theme.panelGlass`.
  - Tiles, cards and keys go through `glassRim`/`GlassRimLayer` (`Glass.swift:24-55`) and the rim tokens.
  - Extras: Settings rows sit in a `GlassEffectContainer` (`Settings/SettingsColumnView.swift:157`) with `settingsRowCapsuleFill`/`settingsInfoRowFill` (`Theme.swift:270-273`), and the toast has its own window and scrim.
  - `GlassRim` doesn't check Reduce Transparency; only panels do (`Glass.swift:8-11`).
  - The tokens are `static let`.
- **One setting can't scale glass continuously** (no strength in the API). It can map steps to variant + tint + a rim/sheen multiplier + solid, e.g. Clear (today), Frosted (`.regular`, light tint), Tinted (`.regular`, heavier tint), Solid (`solidPanelFill`).
- **Plumbing precedent:** an `EnvironmentValues` `@Entry` like `parallaxTilt` (`DesignSystem/ParallaxFocus.swift:45-47`, set at `:147`). It would be set on the root view in `Launcher/AppRouter.swift` (~988–1040, covering the canvas and `LiveTVRootView`) and on the toast's hosting view, and applied from `AppDelegate.applySettings` (`App/AppDelegate.swift:1160`).
- **The system setting:**
  - Public API covers only Reduce Transparency (SwiftUI `accessibilityReduceTransparency`; `NSWorkspace.accessibilityDisplayShouldReduceTransparency`, `NSAccessibility.h:94-100`), which MMTVL already follows.
  - Nothing public for the Liquid Glass Clear/Tinted choice in the 27.0 or 27.2 SDKs. `NSGlassEffectView.h` has `Style` regular/clear, `tintColor`, `cornerRadius` and `effectIsInteractive`.
  - **Unverified:** the dev Mac's global defaults (macOS 27.2) hold the undocumented keys `NSGlassTintAmount` (0.389…), `NSGlassBuddyTintAmount` and `NSGlassEverEditedInBuddy`. They look like System Settings → Appearance's Liquid Glass slider. Reading them would rely on undocumented keys.
  - **Unverified:** whether the system's own rendering follows that slider, and whether MMTVL's explicit `.clear.tint(…)` overrides it.
  - How to check, on the mini (macOS 26.6): move the slider, `defaults read -g NSGlassTintAmount`, relaunch MMTVL, compare its panels with Finder's.
- **Settings fit:** today's toggles are Bool `SettingKey`s (`Settings/SettingsTypes.swift:195-240`). A choice follows the receiver brand pattern:
  - `glassStyle` in `App/AppSettings.swift`, decoded leniently like `receiverBrand` (`:125-128`);
  - a `SettingsPage` and `SettingsAction`;
  - a choice page like `receiverMaxVolumeSections` (`Settings/SettingsModel+Pages.swift:1228-1241`);
  - a row under System (`:231`) or a new Appearance category (`rootSections`, `:140`).
  - Settings is itself glass, so changes show live.
- **Open (user):**
  - Named steps or a slider?
  - "Follow System" as the default (needs the undocumented key)?
  - Also the tile rims and the toast?
  - Should Solid be a choice?

### 3. Bug: the home dock doesn't move to the second row

- **Now:**
  - The dock is a sibling in the home `ZStack`, not part of the rows (`Launcher/HomeView.swift:72-80`): `Color.clear.glassPanel(in: RoundedRectangle(40))`, `.frame(dockFrame.size)`, `.offset(x: dockFrame.minX, y: dockFrame.minY - scrollOffset)`, `.animation(Theme.focusAnimation, value: focus.position.row)`, then `HomeExitMotion`.
  - The rows' `VStack` (`:82-96`) gets the same `.offset(y: -scrollOffset)` and animation.
  - `HomeLayout.scrollOffset` (`Launcher/HomeLayout.swift:16-19`): row 1 gives 1044 − 520 = 524 pt. `dockFrame` is at `:32-36`.
  - D38 says the dock scrolls away with row 0 (`docs/plans/archive/M7c-punchlist.md:136`); the TV accepted that at build 17 (`:445`).
- **Possible causes (unverified):**
  - **(a) A rendering regression since build 17.** M7f L9 moved panels to `Glass.clear.tint` with the rim inside `glassEffect`, and M7h 13h put the home content over the shared video layer inside `.scaleEffect` (`AppRouter.swift:1027-1040`). A platform-backed `glassEffect` may not follow an animated `.offset`. Against it: if the dock still slides away with `HomeExitMotion` (also an offset) when Live TV opens, offsets work.
  - **(b) The user expects the dock to follow focus.** By the code, after Down the dock moves up with row 0 (to y ≈ 256–458) while focus is on row 1 at y = 520, which has no container.
- **How to check:** `open build/Build/Products/Debug/MMTVL.app --args -windowed YES`, press Down, screenshot (or a photo from the TV).
- **Sketch:**
  - (a): draw the dock as row 0's `HStack` `.background` inside the rows' `VStack`, so it shares the offset by construction. `HomeLayout.dockFrame` stays for the carousel dots (`Launcher/ShelfCarouselView.swift:107`) and `MMTVLTests/HomeLayoutTests.swift:27`.
  - (b): move or morph the dock to the focused row, or fade it out in the grid (opacity keyed on the row, like `heroOpacity`).
- **Open (user):**
  - Does the panel stay fixed while the tiles slide through it, or slide up with row 0 without wrapping the row you're on?
  - In the grid, should the dock follow the focused row, scroll away, or fade?

### 4. College teams, picked from the guide

- **Now:**
  - `IPTV/Teams/TeamCatalog.swift`: `TeamLeague` nfl/nba/nhl/mlb with league words (`:2-16`); `Team` id `"league.abbr"`, name, nickname, aliases (`:19-39`); 124 teams (`:42`).
  - `IPTV/Teams/TeamMatcher.swift`:
    - game groups contain "games" but not "replay" (`:33-36`);
    - names are "Away @ Home" with a feed suffix (`:39-55`; `-H`/`-A` spelled out in `IPTV/Sources/Channel.swift:51-59`);
    - each side must equal a full name or alias in `fullNameIndex`, one team per name (`:58-61, 128-136`);
    - network programmes match by full name, or nickname plus a league word (`:70-81`); pre/postgame shows are excluded (`:84-87`).
  - Settings → Live TV → Teams: leagues, then a flat team list (`Settings/SettingsModel+Pages.swift:591-618`).
  - The guide's channel menu: "Add/Remove <Team> to/from Teams" for up to 2 teams of the game or the programme on now (`IPTV/LiveTVModel.swift:665-670, 725-727, 747-754`).
  - The Teams group only exists while a picked team has a live match (`IPTV/Sources/ChannelPreferences.swift:57-61`), so there's no way to pick a team that isn't playing from the guide.
- **College needs:**
  - **Size:** about 136 FBS football, ~364 D-I basketball, ~300 D-I baseball programmes. A flat list per league doesn't work with a remote: pick by school (per-sport toggles), group by conference, or filter by typing with the on-screen keyboard (`Input/OnScreenKeyboard.swift`; the guide's Search row, `IPTV/Guide/GuideView.swift:221`, `GuideModel.swift:85, 248`).
  - **Names:** "Michigan Wolverines", "Michigan", "Mich."; nicknames collide (Tigers, Bulldogs, Wildcats; Louisville vs. Arizona Cardinals).
  - **Sport:** one school name across three sports collides in `fullNameIndex`. The provider's game group has been just "Live-Games" since 2026-11-03 (archive M7f §7), so the sport must come from the programme category or the season, unless a school is picked for all its sports.
  - **League words:** college matching should need "college"/"NCAA"/"NCAAF"/"NCAAB", and those words should keep "football"/"basketball" from counting for the NFL/NBA.
  - **Unverified:** how the provider names college games. Neither sample playlist had any (`docs/plans/archive/M4-live-tv.md:46-48`; M7f's 8 pro games), and the tests have only pro names. College games may only be on networks (ESPN, SEC, Big Ten), matched through guide titles. How to check: on a Saturday in season, dump the playlist's `group-title`s and names, and query a copy of `guide.sqlite` for titles like '%College%' or '%NCAA%' (copy it with its `-wal` first).
- **"Selectable from the guide":** a Teams row always in the guide's group list (like Search) that opens a Teams editor (leagues → teams, filtered with the keyboard), or teams in search results with an Add action. Reuse: the Settings pages and `IPTVLibrary.setTeamPicked` (`IPTV/IPTVLibrary.swift:556`).
- **Open (user):**
  - FBS only, or FCS too? All of D-I basketball and baseball? Women's sports?
  - Pick a school for all its sports, or per sport?
  - Pick teams from the guide when they aren't playing?
  - Can the user share a Saturday playlist and guide sample with college games?
