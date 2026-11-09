# M7l — TV polish: glass, the home dock, college teams

| | |
|---|---|
| Status | Planned |
| Depends on | M7f (glass L9, Teams L13, Search L11/L12), M7g (Settings columns), M7h (the shared video layer, step 13h) |
| Master plan decisions used | D29 (glass), D38 (home layout), D41 (on-screen keyboard), D42 (Settings layout); new **D46** (glass style), **D47** (the dock fades in the grid), **D48** (college teams catalog) |
| Planned | 2026-11-08 (requests and first research 2026-11-08; designed with the user's answers the same day) |

## Goal

The user's requests from the M7f TV check (2026-11-08, builds 20–28):

1. "tone down glass effect on live TV channel info"
2. "be able to dial in and adjust the glass effect for the whole app or follow system glass setting"
3. "home screen container around first row of app doesn't move when going to the second row"
4. "favorite teams selection should include teams for college football, college basketball, and college baseball. These should be selectable from the guide and not just in settings"

On the TV, when this is done:

- The Live TV banner, the timeshift bar, the behind-live badge and the error panel sit on **frosted, darker glass** with a faint rim. The video blurs behind them and no longer bends through.
- **Settings → System → Glass** picks one of **Clear** (today's look, the default), **Light Tint**, **Frosted**, **Dark Frosted** and **Solid**. It changes every glass panel and tile rim in MMTVL at once, live. Reduce Transparency still forces Solid.
- On the home screen, **Down out of the first row fades the glass dock out** while the rows scroll; Up to the first row fades it back. Nothing suggests focus is still in the dock.
- **College teams** can be picked per sport: College Football (FBS and FCS), College Basketball (D-I men), Women's College Basketball (D-I) and College Baseball (D-I), grouped by conference. They're picked in Settings → Live TV → Teams, in the guide's new **Choose Teams** row (the same leagues → conferences → teams lists), and through the guide's **Search**, which also lists teams. The guide's Teams group then shows those teams' games on networks ("College Football", subtitle "Arkansas at Auburn") and in the playlist's game group.

## Out of scope

- A "Match macOS" glass choice that reads the system's Liquid Glass slider (undocumented `NSGlassTintAmount`). The user chose named steps (2026-11-08). The research is kept below in case it comes back.
- A continuous glass slider (the user chose named steps).
- Telling re-airs from live games by the guide's "Live:" title prefix (see Risks). Teams keeps M7f's rule: titles with pregame, postgame, highlights, classic or replay don't count.
- Team logos. The catalog has names and conferences only; MMTVL never fetches anything from ESPN at runtime (D48).
- Women's sports other than basketball; college hockey, soccer and volleyball (they're in the guide but weren't asked for).
- Antenna (M7j), software volume (M7k), inputs (M7i).

## Research & findings

Paths are under `MMTVL/` unless they start with `MMTVLTests/`, `docs/` or `scripts/`. First researched 2026-11-08 on `m7h-siri-remote-and-receiver` (after step 16); re-checked against `master` at `990f005` (M7h merged) on 2026-11-08. Line numbers are from `990f005`.

### 1. The Live TV banner's glass

- **Now:** the banner (channel, now/next) and the timeshift bar share one panel in `PlayerOverlayView` (`IPTV/LiveTVView.swift:149-168`). It uses `.glassPanel()` (`:162`, `Theme.glassCornerRadius` 28) over `.background(Theme.liveOverlayGradient)` (`:167`; clear to black 0.85, `DesignSystem/Theme.swift:335`). The behind-live badge (`:141`, capsule) and the error panel (`:195`) use glass too.
- **`GlassPanel`** (`DesignSystem/Glass.swift:6-21`): a `GlassRimLayer` background, then `.glassEffect(Theme.panelGlass, in: shape)`. With Reduce Transparency it draws `Theme.solidPanelFill` instead.
- **Tokens** (`Theme.swift:185-200`):
  - `panelGlass = Glass.clear.tint(.black.opacity(0.22))`;
  - the M7f L9 rim: width 2, top 0.70, middle 0.08, bottom 0.32, sheen 0.14 (before L9: `.regular`, width 1.5, top 0.55, sheen 0.10; see `docs/plans/archive/M7f-tv-findings.md`, L9).
- **Every panel shares `panelGlass`:** the guide (`IPTV/Guide/GuideView.swift:231`), the menu (`LiveMenuView:29`), search (`LiveSearchView:52`), Multiview (`MultiviewView:45/78/94/138`). Changing the token changes them all.
- **All glass goes through `DesignSystem/Glass.swift`** (verified 2026-11-08: `grep` finds `.glassEffect(` and `Theme.panelGlass` only there; 38 `glassPanel`/`glassRim` call sites). The one other glass API use is `GlassEffectContainer` around Settings' rows (`Settings/SettingsColumnView.swift:157`), which only groups the rows' `glassPanel`s.
- **SwiftUI's `Glass` (SDK-verified, the SwiftUICore swiftinterface of the Xcode 27.0 and 27.2 SDKs):** only `.regular`, `.clear`, `.identity`, `.tint(Color?)` and `.interactive()`. There's no strength value. The tint's opacity is continuous, so named steps are variant + tint + rim strength.
- **User decision (2026-11-08):** "tone down" means **frosted and darker**: `.regular` with a heavier dark tint and a faint rim. → L1.

### 2. An app-wide glass setting

- **Centralised:** panels through `GlassPanel` and one `Theme.panelGlass`; tiles, cards and keys through `glassRim`/`GlassRimLayer` (`Glass.swift:24-55`) and the rim tokens. The toast has its own window (`DesignSystem/OverlayToast.swift:86`, an `NSHostingView`) and scrim (`:167-168`, `Theme.toastScrim`). The only other hosting root is the kiosk window (`App/KioskWindowController.swift:55`), which hosts the router's root view. `GlassRim` doesn't check Reduce Transparency; only panels do (`Glass.swift:8-11`).
- **Plumbing precedent:** an `EnvironmentValues` `@Entry`, like `parallaxTilt` (`DesignSystem/ParallaxFocus.swift:47`, set at `:147`, read at `:175`). The router holds live settings set by AppDelegate (e.g. `homeLivePreview`, `Launcher/AppRouter.swift:62`); `AppDelegate.applySettings` is at `App/AppDelegate.swift:1160`.
- **Settings fit:** a choice follows the receiver brand pattern: a `String`-backed enum in `App/AppSettings.swift` decoded leniently with `try?` (`:125-128`, unknown → default); a `SettingsPage` and `SettingsAction`; a choice page like `receiverMaxVolumeSections` (`Settings/SettingsModel+Pages.swift:1228-1241`); a row on the System page (`systemSections`, `:231`). Settings is itself glass, so a change shows at once.
- **The system setting (kept for the record; not built, see Out of scope):** public API covers only Reduce Transparency (SwiftUI `accessibilityReduceTransparency`; `NSWorkspace.accessibilityDisplayShouldReduceTransparency`), which MMTVL already follows. Nothing public for the Liquid Glass slider in the 27.0 or 27.2 SDKs (`NSGlassEffectView.h`: `Style` regular/clear, `tintColor`, `cornerRadius`, `effectIsInteractive`). On the dev Mac (macOS 27.2, verified 2026-11-08 with `defaults read -g`): `NSGlassTintAmount = "0.3899079"`, `NSGlassBuddyTintAmount = "0.4"`, `NSGlassEverEditedInBuddy = 1`. **Unverified:** whether these exist on the mini (macOS 26.6) and whether MMTVL's explicit tint overrides the system's.
- **User decision (2026-11-08):** named steps, no "Match macOS". → D46, L2–L4.

### 3. The home dock in the grid

- **Now:**
  - The dock is a sibling in the home `ZStack`, not part of the rows (`Launcher/HomeView.swift:72-80`): `Color.clear.glassPanel(in: RoundedRectangle(40))`, `.frame(dockFrame.size)`, `.offset(x: dockFrame.minX, y: dockFrame.minY - scrollOffset)`, `.animation(Theme.focusAnimation, value: focus.position.row)`, then `HomeExitMotion`.
  - The rows' `VStack` (`:82-96`) gets the same `.offset(y: -scrollOffset)` and animation.
  - `HomeLayout.scrollOffset` (`Launcher/HomeLayout.swift:16-19`): row 1 gives 1044 − 520 = 524 pt, so row 0 moves to y ≈ 276 and **stays on screen above the focused row, still in its dock**. `dockFrame` is at `:32-36`; `heroOpacity`/`shelfOpacity` (`:22-29`) are the precedent for a per-row opacity.
  - D38 (M7c L19, `docs/plans/archive/M7c-punchlist.md:136`): "the dock panel scrolls away with row 0"; accepted on the TV at build 17 (`:445`).
- **Cause (user, 2026-11-08):** not a rendering bug. The dock does move with row 0, as coded, and that's the problem: "the screen dock stays with the first row when scrolling down. It makes it feel like my selection hasn't moved and like I'm still cycling through tiles that are highlighted by the dock." (Checking it on the dev Mac in `-windowed` mode failed: the Mac was at its lock screen.)
- **What tvOS 26/27 does there: unverified.** Apple's pages and reviews describe the glass dock but not the scroll into the grid ([AppleInsider tvOS 26 review](https://appleinsider.com/articles/25/09/14/tvos-26-review-high-on-polish-light-on-new-features-for-apple-tv), [AppleInsider hands-on](https://appleinsider.com/articles/25/06/18/tvos-26-hands-on-sleek-liquid-glass-redesign-new-control-center-and-more)). How to check: on an Apple TV with tvOS 26 or later, press Down from the top row.
- **User decision (2026-11-08):** fade the dock out when focus leaves row 0. → D47, L5.

### 4. College teams, picked from the guide

- **Now:**
  - `IPTV/Teams/TeamCatalog.swift`: `TeamLeague` nfl/nba/nhl/mlb with league words (`:2-16`); `Team` id `"league.abbr"`, name, nickname, aliases (`:19-39`); 124 teams in `static let` arrays (`:42`, 186 lines).
  - `IPTV/Teams/TeamMatcher.swift` (138 lines):
    - game groups contain "games" but not "replay" (`:33-36`);
    - names are "Away @ Home" with a feed suffix (`:39-55`; `-H`/`-A` spelled out in `IPTV/Sources/Channel.swift:51-59`);
    - each side must equal a full name or alias in `fullNameIndex`, one team per name (`:58-61, 128-136`);
    - network programmes (`teams(in:)`, `:66-81`) match a full name **as a substring** of title + subtitle, or a nickname plus a league word; **every catalog team is tested for every channel's programme on now** (`networkChannelIDs`, `:115-124`), then filtered to the picked ones;
    - pre/postgame shows are excluded (`:84-87`).
  - `IPTVLibrary.updateTeams()` (`IPTV/IPTVLibrary.swift:570-584`) recomputes `teamChannelIDs` after each playlist or guide refresh, when a team is picked (`setTeamPicked`, `:556`), and every 5 minutes. It logs nothing today.
  - Settings → Live TV → Teams (`Settings/SettingsModel+Pages.swift:573-616`): leagues (`iptvTeamsSections`), then a flat team list (`iptvLeagueSections`, `.toggleTeam(id:)`); pages `.iptvTeams`, `.iptvLeague(TeamLeague)` (`Settings/SettingsTypes.swift:7`), action at `:271`, handled at `Settings/SettingsModel.swift:433`.
  - The guide's channel menu (`IPTV/LiveTVModel.swift:665-670, 725-727, 747-754`): "Add/Remove <Team> to/from Teams" for up to 2 teams of the game or the programme on now.
  - The Teams group only exists while a picked team has a live match (`IPTV/Sources/ChannelPreferences.swift:57-61`), so there's no way to pick a team that isn't playing from the guide today.
  - The guide's group list has a **Search** row above the groups (`IPTV/Guide/GuideModel.swift:8-13, 216-218, 247-262`, focus `.search`, action `.openSearch`). `LiveSearchModel` (`IPTV/Search/LiveSearchModel.swift`) has `Result.channel` / `.programme`, results `channelResults + programmeResults`, outcome `.choose(Result)`; `LiveTVModel` keeps it (`IPTV/LiveTVModel.swift:69`, opened `:589`, phone Return picks `firstResult` `:582`).
  - `LiveMenu` (`IPTV/LiveMenu.swift`) is the pure list used for the channel menu, Match Guide and Multiview's menus: items with a title, an optional right-aligned `value` and a `LiveMenuAction`; 8 visible rows, Channel Up/Down page, Select → `.choose`, Back/Menu → `.close`.
- **How the guide names college games (verified 2026-11-08 on the dev Mac's `guide.sqlite`, one guide, 2,870 programmes, Nov 8–11, read from a copy):**
  - Titles: "College Football", "Live: College Basketball", "Live: Women's College Basketball", "College Hockey", "Live: Women's College Soccer"; category "Sports".
  - Subtitles name the teams by **school**: "Arkansas at Auburn", "Texas A&M at South Carolina", "Georgia at Ole Miss", "Grambling State at Texas", "Villanova at Princeton", and tournaments as "SEC Tournament: Georgia vs. Oklahoma".
  - Pro games look the same: "NHL Hockey" / "New Jersey Devils at Toronto Maple Leafs" (full names).
  - Studio shows: "College Football Live", "Inside College Football", "College Basketball Pregame" / "Postgame" (the last two are excluded by today's words).
  - Re-airs: Sunday's SEC Network rows "College Football | Arkansas at Auburn" have no "Live:" prefix; live games do ("Live: College Basketball | Appalachian State at Auburn"). NHL shows both forms of one game. See Risks.
  - **Substring matching breaks for schools:** normalized "texas a m at south carolina" contains " texas ", so M7f's full-name substring rule would match Texas for a Texas A&M game. College sides must be parsed and matched **exactly**.
  - College baseball runs February to June; none was in the guide (only "Baseball" shows), so baseball's naming is **unverified** (assumed "College Baseball"). How to check: in season, `sqlite3` a copy of `guide.sqlite` (with its `-wal`): `select distinct title, subtitle from programme where title like '%Baseball%'`.
- **How the playlist names college game entries: unverified.** M7f saw only pro entries ("Away @ Home" with full names, group "Live-Games"). How to check: step 8's TV check on a game day, with the log line step 5 adds (counts per kind), and the guide's Teams group.
- **A catalog source (verified 2026-11-08):** ESPN's public, undocumented site and core APIs (no key) list teams with `displayName` ("Auburn Tigers"), `shortDisplayName` ("Auburn"), `location` ("Auburn"), `name` ("Tigers"), `abbreviation`, `slug` ("auburn-tigers") and conferences:
  - `https://site.api.espn.com/apis/site/v2/sports/{football/college-football | basketball/mens-college-basketball | basketball/womens-college-basketball | baseball/college-baseball}/teams?limit=1000`: 763 (all divisions) / 365 / 363 / 437 teams.
  - `https://site.api.espn.com/apis/v2/sports/<sport>/standings?group=<id>`: conferences with their teams: football group 80 (FBS) 11 conferences, 124 teams; 81 (FCS) 14, 116; men's and women's basketball group 50 (D-I) 32 conferences, 365 and 363 teams; baseball group 26 only 10 conferences, 60 teams (incomplete).
  - `https://sports.core.api.espn.com/v2/sports/<sport path>/leagues/<league>/seasons/2026/types/2/groups/<id>/teams?limit=500` and `/children`: FBS 148 teams in 11 conferences, FCS 130 in 14, baseball group 26 436 teams in 15 (more than D-I's ~300).
  - Matching ESPN's displayName/shortDisplayName/location against the guide's 32 college sides: **29 matched**; the misses were "Appalachian State" (ESPN "App State"), "Grambling State" (ESPN "Grambling") and "TBA". So the catalog needs aliases: "State" for a trailing "St"/"St.", and a hand list.
  - The counts don't agree across endpoints (FBS 124 vs 148, baseball 60 vs 436), so the generator must report counts per conference for a check (step 4). ESPN's API is undocumented; it's used **once, by a script**, to write a committed catalog. School names are facts; no logos or other assets are copied.
- **User decisions (2026-11-08):** all of FBS and FCS football, D-I men's and women's basketball and D-I baseball; picked **per sport**; from the guide **both** through Search and through a Teams row with the full lists. → D48, L6–L12.

## Design

### Local decisions

- **L1 — The player's overlays use a "banner" glass role.** The banner + timeshift panel (`LiveTVView.swift:162`), the behind-live badge (`:141`) and the error panel (`:195`) all sit over moving video, so all three use it. The banner role is the app-wide step's look made at least as frosted and dark as **Dark Frosted**: `.regular`, tint ≥ 0.45, rim × 0.4, sheen 0. With **Solid** (or Reduce Transparency) it's solid like every panel. The `liveOverlayGradient` stays. The exact tint is a token, tuned on the TV (step 8).
- **L2 — Five named steps (D46).** `GlassStyle` raw values and their look (tokens in `Theme`, starting values; TV tuning may change the numbers, not the steps):

  | Step (`glassStyle`) | Title | Panel glass | Rim × | Sheen × |
  |---|---|---|---|---|
  | `clear` (default) | Clear | `.clear.tint(black 0.22)` (today) | 1.0 | 1.0 |
  | `light` | Light Tint | `.clear.tint(black 0.35)` | 0.8 | 0.7 |
  | `frosted` | Frosted | `.regular.tint(black 0.22)` | 0.6 | 0.5 |
  | `darkFrosted` | Dark Frosted | `.regular.tint(black 0.45)` | 0.4 | 0 |
  | `solid` | Solid | none: `Theme.solidPanelFill` | 0.3 | 0 |

  Tile/card rims (`glassRim`) scale their stroke opacities by "Rim ×" and their sheen by "Sheen ×", focused and not. Reduce Transparency makes panels Solid whatever the step, as today; it doesn't change tile rims (unchanged from today).
- **L3 — Where it lives:** Settings → **System** → **Glass** (value: the step's title) → a choice page with the five steps and a footer ("Changes every glass panel in MMTVL. Reduce Transparency in macOS's Accessibility settings always uses Solid."). System, because it's app-wide and not about one screen; no new category.
- **L4 — Plumbing:** an `EnvironmentValues` `@Entry var glassStyle: GlassStyle = .clear` (in `Glass.swift`). The router gets `var glassStyle: GlassStyle` (set by AppDelegate at launch and in `applySettings`, like `homeLivePreview`); the root view applies `.environment(\.glassStyle, router.glassStyle)` above both the canvas and `LiveTVRootView`. `OverlayToast` gets a `glassStyle` property (set by AppDelegate the same way) that its hosting root view applies. `GlassPanel` and `GlassRim` read it.
- **L5 — The dock fades in the grid (D47).** `HomeLayout.dockOpacity(focusedRow:)` = 1 for row 0, 0 otherwise. The dock keeps its offset (it still slides up as it fades, over the same `Theme.focusAnimation`). The carousel's page dots already hide with `shelfOpacity`. Nothing else in the grid changes.
- **L6 — Four college leagues:** `TeamLeague` gains `ncaaf` (title "College Football"), `ncaam` ("College Basketball"), `ncaaw` ("Women's College Basketball") and `ncaabase` ("College Baseball"), with `isCollege`. Football has FBS and FCS conferences together (conference titles say which, e.g. "Big Ten", "Big Sky (FCS)").
- **L7 — Team ids:** `"<league>.<ESPN slug>"`, e.g. `"ncaaf.michigan-wolverines"`, `"ncaaw.michigan-wolverines"`. Readable in `iptv-channels.json` `teams`, stable across seasons, and per sport by construction. Pro ids don't change.
- **L8 — The catalog is a committed JSON resource (D48):** `MMTVL/IPTV/Teams/college-teams.json`, written by `scripts/gen-college-teams.py` (Python 3, stdlib only) from ESPN's public endpoints, run by hand when conferences change (a yearly chore, not a build step). The file ships flat in `Contents/Resources` (unique name). `TeamCatalog` loads it once, lazily (`nonisolated`, `Bundle.main`), and adds the college teams after the pro ones. A missing or unreadable file means no college teams and a logged error, never a crash. Entry shape:
  ```json
  { "id": "ncaaf.michigan-wolverines", "league": "ncaaf", "name": "Michigan Wolverines",
    "school": "Michigan", "nickname": "Wolverines", "conference": "Big Ten",
    "aliases": ["Michigan"] }
  ```
  `aliases` holds ESPN's `shortDisplayName` and `location` when they differ from `name`, plus the generator's rules: a trailing " St" or " St." also gets " State" ("Grambling St" → "Grambling State"; never a leading "St." as in "St. John's"), and a hand table in the script (`"App State": ["Appalachian State"]`, `"Grambling": ["Grambling State"]`, `"Ole Miss": ["Mississippi"]`, `"UConn": ["Connecticut"]`, `"Miami": ["Miami (FL)"]`, and any found in step 4). A name that two schools of one league would share (e.g. two "Miami"s) is dropped from both schools' aliases, and the script prints it.
- **L9 — Baseball's conferences come from basketball.** ESPN's baseball grouping is incomplete (finding 4). The baseball list is ESPN's college-baseball teams **that are D-I basketball schools** (by ESPN team id), each under its basketball conference. A few baseball-only affiliate memberships will show under the wrong conference; acceptable, and the hand table can fix one.
- **L10 — College matching (in `TeamMatcher`):**
  - **Which sport:** from the programme's title + category, normalized: "women s college basketball" or "ncaaw" → `ncaaw`; else "college basketball" or "ncaab" or "ncaam" → `ncaam`; "college football" or "ncaaf" → `ncaaf`; "college baseball" → `ncaabase`; none of these → not a college programme.
  - **Which teams:** the subtitle, else the title's text after its first ":" ("Live: …" excluded). Drop a leading "<event>: " ("SEC Tournament: Georgia vs. Oklahoma" → "Georgia vs. Oklahoma"), split into exactly two sides on " at ", " vs. ", " vs " or " @ ", strip a leading ranking ("No. 5 ", "#5 ", "(5) "), then match **each side exactly** (normalized) against that league's index of `name` + `school` + `aliases`. No substring matches for college.
  - **Pro league words don't count in college programmes:** a programme whose normalized title says "college" or "ncaa" never matches a pro team by nickname + league word (the full-name rule still applies). This stops "basketball"/"football" in "College Basketball" from counting for the NBA/NFL.
  - **Game entries** (the playlist's game groups): each side is matched against the pro full-name index first, then the college index of **any** college league; the entry matches when that school is picked in any college sport (the entry's name doesn't say the sport). Unverified that college entries exist; see finding 4.
  - **Only picked teams are tested** in `networkChannelIDs`: today all 124 teams are tested per channel; with ~1,400 teams that's ~10× the work every 5 minutes. Matching picks first, then tests the programme against them.
- **L11 — Showing a college team:** `Team.pickTitle` is `name` for pro teams and `"\(name) (\(league.sportTitle))"` for college, where `sportTitle` is "Football", "Basketball", "Women's Basketball", "Baseball" (e.g. "Michigan Wolverines (Women's Basketball)"). Used in the channel menu, search results and the Choose Teams lists' values.
- **L12 — Picking from the guide:**
  - **Choose Teams row:** a second row under Search in the guide's group list (focus `.chooseTeams`; Up from it → Search, Down → the first group; Up from the first group → Choose Teams; Select or Right → `.openTeamPicker`). The Teams *group* (live games) is unchanged and keeps its name.
  - **The picker is a stack of `LiveMenu`s** built by a pure `TeamPicker` (`IPTV/Teams/TeamPicker.swift`): level 1 "Choose Teams": the 8 leagues (value: "2 On" or nil); a pro league → its teams (value "In Teams" or nil); a college league → its conferences (value "1 On" or nil) → their teams. Select on a team toggles it (`library.setTeamPicked`) and rebuilds that level with focus kept; Select on a league or conference pushes; Back pops; Back on level 1 closes to the guide with focus on Choose Teams. Menu titles: "Choose Teams", "College Football", "Big Ten". Drawn with `LiveMenuView` (8 visible rows; Channel Up/Down page).
  - **Search lists teams:** `LiveSearchModel.Result.team(Team)` results (at most `maxTeamResults` = 6) come **between** channels and programmes, matched when every typed word is in the team's `name + " " + school + " " + league.title + " " + conference`. A row shows `pickTitle` and "In Teams" when picked. Select toggles and keeps search open (the row updates). Phone Return (`firstResult`) skips team results.
  - The channel menu's Add/Remove (M7f) now covers college games through `teams(shownOn:)` and uses `pickTitle`.
- **L13 — Settings → Live TV → Teams:** the leagues page gets two sections, "Pro" (NFL, NBA, NHL, MLB) and "College" (the four), each row "N On" when any are picked. Pro leagues push a flat team list (unchanged). College leagues push a **conference** list (new page `.iptvConference(TeamLeague, String)`), whose rows show "N On", then the conference's teams (`.toggleTeam(id:)`, as today). Conference order: alphabetical, FBS before FCS for football. The Teams row's description becomes "Your teams' live games, pro and college, in the guide's Teams group."
- **L14 — Logging:** `updateTeams()` logs at notice level (category `IPTV`, kept by `log show`) when the Teams group's contents change: `Teams: <n> channels (<g> game entries, <m> network)`. Counts only, no team or channel names.

### New and changed files

| File | What |
|---|---|
| `DesignSystem/Glass.swift` | `GlassStyle`-aware `GlassPanel` and `GlassRim`; the `glassStyle` environment entry; `glassPanel(role: .banner)` overloads (L1). |
| `DesignSystem/GlassStyle.swift` (new) | `nonisolated enum GlassStyle: String, CaseIterable, Codable, Sendable` (L2) with `title`; `enum GlassRole { case standard, banner }`; a main-actor `GlassAppearance` (panel `Glass?`, rim and sheen scales) computed from style + role from `Theme` tokens. |
| `DesignSystem/Theme.swift` | Per-step tokens (L2) and banner tokens (L1); `panelGlass` stays as Clear's value. |
| `IPTV/LiveTVView.swift` | The banner panel, badge and error panel use the banner role. |
| `DesignSystem/OverlayToast.swift` | `glassStyle` applied to its hosting root. |
| `Launcher/AppRouter.swift`, `App/AppDelegate.swift` | `router.glassStyle`, set at launch and in `applySettings`; the environment on the root view; the toast's style. |
| `App/AppSettings.swift` | `glassStyle` (lenient `String` decode, default `clear`). |
| `Settings/SettingsTypes.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift` | System → Glass row and choice page; Teams' Pro/College sections, `.iptvConference` pages. |
| `Launcher/HomeLayout.swift`, `Launcher/HomeView.swift` | `dockOpacity(focusedRow:)` and its use on the dock (L5). |
| `scripts/gen-college-teams.py` (new) | Writes `college-teams.json` (L8, L9). |
| `IPTV/Teams/college-teams.json` (new, generated) | The college catalog. |
| `IPTV/Teams/TeamCatalog.swift` | New leagues, `Team.school`/`conference`/`pickTitle`, loading the JSON, conference helpers. |
| `IPTV/Teams/TeamMatcher.swift` | L10. |
| `IPTV/Teams/TeamPicker.swift` (new) | The pure picker stack (L12). |
| `IPTV/Guide/GuideModel.swift`, `IPTV/Guide/GuideView.swift` | The Choose Teams row. |
| `IPTV/Search/LiveSearchModel.swift`, `IPTV/Search/LiveSearchView.swift` | Team results. |
| `IPTV/LiveMenu.swift`, `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift` | Picker actions, its menu stack and drawing; channel menu titles. |
| `IPTV/IPTVLibrary.swift` | L14's log line. |

### Key types (sketches)

```swift
nonisolated enum GlassStyle: String, CaseIterable, Codable, Sendable {
    case clear, light, frosted, darkFrosted, solid
    var title: String { … }   // "Clear", "Light Tint", "Frosted", "Dark Frosted", "Solid"
}

enum GlassRole { case standard, banner }

struct GlassAppearance {           // main-actor: reads Theme
    var panelGlass: Glass?         // nil = solid fill
    var rimScale: Double
    var sheenScale: Double
    static func make(style: GlassStyle, role: GlassRole, reduceTransparency: Bool) -> GlassAppearance
}

extension EnvironmentValues { @Entry var glassStyle: GlassStyle = .clear }

extension View {
    func glassPanel(cornerRadius: CGFloat = Theme.glassCornerRadius, role: GlassRole = .standard) -> some View
    func glassPanel(in shape: some InsettableShape, role: GlassRole = .standard) -> some View
}

nonisolated enum TeamLeague: String, CaseIterable, Hashable, Sendable {
    case nfl, nba, nhl, mlb, ncaaf, ncaam, ncaaw, ncaabase
    var isCollege: Bool
    var title: String       // "NFL" … "College Football", "Women's College Basketball"
    var sportTitle: String  // college only: "Football", "Basketball", "Women's Basketball", "Baseball"
}

nonisolated struct Team {   // existing fields, plus:
    let school: String?      // college: "Michigan"
    let conference: String?  // college: "Big Ten"
    var pickTitle: String
}

nonisolated enum TeamCatalog {
    static let teams: [Team]                       // pro + college
    static func conferences(in league: TeamLeague) -> [String]
    static func teams(in league: TeamLeague, conference: String) -> [Team]
    static func collegeTeams(fromJSON data: Data) throws -> [Team]   // tests feed fixtures
}

nonisolated struct TeamPicker: Equatable, Sendable {
    enum Level: Equatable, Sendable { case leagues, league(TeamLeague), conference(TeamLeague, String) }
    private(set) var path: [Level]                  // starts [.leagues]
    func menu(picked: Set<Team.ID>, focusedIndex: Int) -> LiveMenu
    mutating func push(_ level: Level)
    mutating func pop() -> Bool                     // false = close the picker
}
// LiveMenuAction gains: .openTeamLeague(TeamLeague), .openTeamConference(TeamLeague, String)
// (Select on a team reuses .toggleTeam(Team.ID)).
```

## Implementation steps

The project must build after every step. Test command (whole suite): `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`. One test build for the TV (step 8); a second only if tuning is needed.

- [ ] **1. Glass styles and the banner role** `[designer]`: files: `DesignSystem/GlassStyle.swift` (new), `DesignSystem/Glass.swift`, `DesignSystem/Theme.swift`, `IPTV/LiveTVView.swift`, `MMTVLTests/GlassStyleTests.swift` (new)
  - Add `GlassStyle`, `GlassRole`, `GlassAppearance` (L2, L1) and the `glassStyle` environment entry (L4). Tokens per L2's table and L1 (`Theme.glassSteps…`/`Theme.bannerGlassTint` and so on; no literals in views).
  - `GlassPanel` reads `glassStyle` and Reduce Transparency, builds a `GlassAppearance` for its role: a nil `panelGlass` draws `solidPanelFill` (no rim, as today); otherwise the rim layer with the scales, then `.glassEffect(appearance.panelGlass!, in: shape)`. `GlassRimLayer` takes the scales. `GlassRim` (tiles) reads `glassStyle` for its scales.
  - `glassPanel` overloads take `role:` (default `.standard`), so the 38 call sites don't change.
  - In `LiveTVView.swift`, the banner panel (`:162`), the behind-live badge (`:141`) and the error panel (`:195`) pass `role: .banner`.
  - With the default (`clear`, standard role) every panel and rim must look exactly as before this step.
  - Tests (`GlassStyleTests`): `GlassStyle(rawValue:)` round-trips every case; `GlassAppearance.make` gives a nil panel for `.solid` and for any style with Reduce Transparency; `.banner` with `.clear` gives the Dark Frosted values (L1) and with `.solid` stays solid; `.clear` + `.standard` equals today's tokens (rim and sheen scale 1).
  - Done when: the suite passes, and in `open build/Build/Products/Debug/MMTVL.app --args -windowed YES` Live TV's banner (Select on a channel) is frosted and darker while the guide's panels look as before. Screenshot both for QA.

- [ ] **2. The Glass setting** `[implementer]`: files: `App/AppSettings.swift`, `Settings/SettingsTypes.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `Launcher/AppRouter.swift`, `App/AppDelegate.swift`, `DesignSystem/OverlayToast.swift`, `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/SettingsModelTests.swift`
  - `AppSettings.glassStyle: GlassStyle = .clear`, decoded like `receiverBrand` (`String` with `try?`, unknown → `.clear`), encoded as its raw value.
  - Settings: on the System page, a **Glass** row (value: the step's title; description "How see-through MMTVL's glass panels are.") pushing a new page `.glassStyle` with the five steps (checkmark/"On" on the current one, as `receiverMaxVolumeSections` does) and L3's footer. A new action (e.g. `.setGlassStyle(GlassStyle)`) saves at once.
  - L4's plumbing: `router.glassStyle`, set by AppDelegate at launch and in `applySettings`; `.environment(\.glassStyle, router.glassStyle)` on the root view so it covers the canvas, Live TV and the power menu; `OverlayToast`'s hosting root gets it too.
  - Tests: `AppSettingsTests`: a missing `glassStyle` reads `.clear`; `"frosted"` reads `.frosted`; `"bogus"` and `12` read `.clear` without sending the file to `.bak`; the value round-trips. `SettingsModelTests`: the System page has a Glass row showing "Clear"; choosing Frosted saves `glassStyle: frosted` and the row shows "Frosted".
  - Done when: the suite passes, and in `-windowed YES` Settings → System → Glass → Frosted changes the Settings panels at once, and `~/Library/Application Support/MMTVL/settings.json` has `"glassStyle" : "frosted"` (set it back to Clear afterwards).

- [ ] **3. The dock fades in the grid** `[implementer]`: files: `Launcher/HomeLayout.swift`, `Launcher/HomeView.swift`, `MMTVLTests/HomeLayoutTests.swift`
  - `HomeLayout.dockOpacity(focusedRow:)` per L5. In `HomeView`, the dock gets `.opacity(HomeLayout.dockOpacity(focusedRow: focus.position.row))` animated with `Theme.focusAnimation` on the row, before `HomeExitMotion` (so leaving for Live TV and coming back still animate as today). Update the comment at `:71` (D47).
  - Tests: `HomeLayoutTests`: `dockOpacity(focusedRow: 0) == 1`, `dockOpacity(focusedRow: 1) == 0`, `dockOpacity(focusedRow: 2) == 0`.
  - Done when: the suite passes, and in `-windowed YES` Down from the first row fades the dock out as the rows scroll (row 0's tiles stay, without a panel), and Up brings it back.

- [ ] **4. The college catalog** `[implementer]` `[security]` (new outward fetches in a script; check it never runs at build time and the app makes no new connections): files: `scripts/gen-college-teams.py` (new), `MMTVL/IPTV/Teams/college-teams.json` (new, generated)
  - The script (Python 3 stdlib: `urllib`, `json`; run with `python3 -I scripts/gen-college-teams.py`) fetches ESPN's public endpoints (finding 4) and writes the JSON per L8. Football: FBS (group 80) and FCS (group 81) conferences and their teams from the core API's `groups/<id>/children` and each child's `teams`; FCS conference titles get " (FCS)". Men's and women's basketball: group 50's conferences and teams. Baseball per L9. Each entry per L8, with `aliases` per L8's rules and hand table. Sorted by league, conference, name; pretty-printed with sorted keys so diffs stay readable.
  - It prints, for a check: the count per league, per conference, every dropped ambiguous alias, and any team without a conference. Expected roughly: football 250–280 (FBS ~136–148, FCS ~116–130), men's basketball ~365, women's ~363, baseball ~290–310. A league far outside its range stops the script with an error, and nothing is written.
  - Fetch with a plain `User-Agent: MMTVL-catalog-script` (no personal details), a 20 s timeout and up to 2 retries; no keys, no cookies.
  - Record the counts in this plan's *Deviations & questions* (date, counts).
  - Done when: the script runs, the counts are in range, `python3 -I -c "import json; d=json.load(open('MMTVL/IPTV/Teams/college-teams.json')); print(len(d), len({t['id'] for t in d}))"` prints two equal numbers, and `grep -c '"Appalachian State"' MMTVL/IPTV/Teams/college-teams.json` finds at least one alias.

- [ ] **5. College teams in the catalog and the matcher** `[implementer]`: files: `IPTV/Teams/TeamCatalog.swift`, `IPTV/Teams/TeamMatcher.swift`, `IPTV/IPTVLibrary.swift`, `IPTV/LiveTVModel.swift` (menu titles only), `MMTVLTests/TeamMatcherTests.swift`, `MMTVLTests/TeamCatalogTests.swift` (new)
  - `TeamLeague` per L6; `Team` gains `school`, `conference`, `pickTitle` (L11); the existing initializer stays for pro teams. `TeamCatalog.teams` = pro + `collegeTeams(fromJSON:)` of the bundled file (L8; a failure logs an error, category `IPTV`, and gives no college teams). `conferences(in:)`, `teams(in:conference:)`.
  - `TeamMatcher` per L10: sport detection, side parsing, exact per-league index for college, pro league words ignored in college programmes, game entries checking college schools too, and `networkChannelIDs` testing only picked teams.
  - The channel menu (`LiveTVModel.swift:665-670`) uses `team.pickTitle`.
  - `updateTeams()` logs L14's line when `teamChannelIDs` changes.
  - Tests (`TeamCatalogTests`, from a small JSON fixture in the test file, plus one check of the bundled file):
    - the bundled catalog loads, has all four college leagues, ids are unique and start with their league;
    - `collegeTeams(fromJSON:)` of the fixture builds `school`, `conference`, aliases; `pickTitle` is "Michigan Wolverines (Women's Basketball)" for `ncaaw`;
    - `conferences(in: .ncaaf)` is sorted with FBS before FCS.
  - Tests (`TeamMatcherTests`, with fixture teams so they don't depend on the bundled data): from this plan's verified guide rows:
    - "College Football" / "Texas A&M at South Carolina" matches Texas A&M and South Carolina football, **not** Texas;
    - "Live: College Basketball" / "Grambling State at Texas" matches Grambling (alias) and Texas men's basketball, not Texas football;
    - "Live: Women's College Basketball" / "Villanova at Princeton" matches the `ncaaw` teams only;
    - "Live: Women's College Soccer" / "SEC Tournament: Georgia vs. Oklahoma" matches nothing;
    - "College Basketball" / "No. 5 Duke vs. Kansas" strips the ranking and matches both;
    - "College Basketball Pregame" isn't a live game (existing rule);
    - "College Basketball" with a subtitle naming an NBA nickname doesn't match the NBA team by nickname + "basketball";
    - "NHL Hockey" / "New Jersey Devils at Toronto Maple Leafs" still matches both (pro unchanged), and every existing test still passes;
    - a game entry "Michigan @ Ohio State" in "Live-Games" matches when Michigan is picked in any college league;
    - `networkChannelIDs` with nothing picked from a league never tests that league (e.g. results equal with and without unpicked college teams in the catalog).
  - Done when: the suite passes.

- [ ] **6. College teams in Settings** `[implementer]`: files: `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `MMTVLTests/SettingsModelTests.swift`
  - L13: Pro and College sections; `.iptvConference(TeamLeague, String)` pages with "N On" values; page titles (league title, conference name); the Teams row's new description.
  - Tests: the Teams page has 4 Pro and 4 College rows; College Football pushes its conferences; a conference page lists its teams; toggling a team there adds `"ncaaf.<slug>"` to the library's teams and the conference row then shows "1 On" and the league row "1 On".
  - Done when: the suite passes, and in `-windowed YES` Settings → Live TV → Teams → College Football → a conference → a team toggles On/Off.

- [ ] **7. Picking teams from the guide** `[implementer]`: files: `IPTV/Teams/TeamPicker.swift` (new), `IPTV/LiveMenu.swift`, `IPTV/Guide/GuideModel.swift`, `IPTV/Guide/GuideView.swift`, `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `IPTV/Search/LiveSearchModel.swift`, `IPTV/Search/LiveSearchView.swift`, `MMTVLTests/TeamPickerTests.swift` (new), `MMTVLTests/GuideModelTests.swift`, `MMTVLTests/LiveSearchTests.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - **Choose Teams row** (L12): `GuideModel.Focus.chooseTeams`, `Action.openTeamPicker`; navigation Search ↔ Choose Teams ↔ first group; drawn like the Search row (`GuideView.swift:221`), with a `person.2`-style symbol (designer's choice of SF Symbol is fine) and the title "Choose Teams".
  - **Picker:** `TeamPicker` per the sketch; `LiveTVModel` keeps `teamPicker: TeamPicker?` and its `LiveMenu`, sends it every command but Home while open, and handles `.openTeamLeague`, `.openTeamConference`, `.toggleTeam` (rebuild, focus kept) and `.close` (pop; closing from level 1 returns to the guide on Choose Teams). Drawn with `LiveMenuView` where the channel menu is drawn.
  - **Search** (L12): `Result.team(Team)`, `maxTeamResults = 6`, matched at once (no debounce; the catalog is in memory) on every text change; `results` = channels + teams + programmes; `Outcome.toggleTeam(Team.ID)` keeps search open; `firstResult` skips teams. `LiveSearchView` draws a team row: `pickTitle`, detail = conference, value "In Teams" when picked. Update its hint for a focused team row ("Select: add to Teams · Left: keyboard").
  - Tests:
    - `TeamPickerTests`: level 1 lists 8 leagues with "N On" values; push a college league → conferences; push a conference → its teams with "In Teams" on picked ones; `pop()` from a team list returns to its parent and from level 1 returns false; a pro league goes straight to teams.
    - `GuideModelTests`: Up from the first group → `.chooseTeams`; Up from Choose Teams → `.search`; Down from Search → `.chooseTeams`; Select on Choose Teams → `.openTeamPicker`.
    - `LiveSearchTests`: typing "michigan" lists teams between channel and programme results; "michigan women" narrows to `ncaaw`; Select on a team result toggles it in the library and search stays open; `firstResult` is never a team.
    - Live TV model: opening the picker from the guide, toggling a team, Back twice returns to the guide with focus on Choose Teams.
  - Done when: the suite passes, and in `-windowed YES` (with a playlist set up) the guide's Choose Teams → College Basketball → a conference → a team toggles "In Teams", and Search "duke" lists Duke's teams with Select adding one.

- [ ] **8. TV check (one test build)** `[human]`: after steps 1–7 are committed and the user says yes to a test build (`scripts/test-build.sh`, then `scripts/deploy-mm.sh`). Best on a **college game day** (Saturday for football; any evening for basketball).
  - **Banner:** play a channel, Select: the banner and the bar are frosted and darker; the moving video blurs behind them rather than bending; text is easy to read. Seek back (timeshift) for the behind-live badge. Is it toned down enough, or too dark?
  - **Glass setting:** Settings → System → Glass, try each step and look at Settings itself, then the guide, a channel menu, Multiview, the home dock and a toast (press volume). Solid should have no see-through anywhere. Which step looks best? (Clear stays the default unless you say otherwise.) Set back the one you want.
  - **Home dock:** Down from the first row: the dock fades out while the rows scroll; focus is clearly on the second row. Up: it fades back. Open Live TV and come back: the dock still slides in.
  - **College in Settings:** Settings → Live TV → Teams shows Pro and College; pick a school in College Football and the same school in College Basketball; the counts show.
  - **From the guide:** the guide's group list: Search, then Choose Teams. Choose Teams → a league → a conference → a team toggles "In Teams"; Back goes up a level, then to the guide. Search: type a school, its teams show between channels and programmes; Select adds or removes one.
  - **The Teams group:** with a picked team playing, the guide's Teams group lists its game: a network channel whose programme says "College Football" / "<school> at <school>", and the playlist's game entry if the provider has one. Look at the log, from the dev Mac: `ssh mm "/usr/bin/log show --last 1h --predicate 'subsystem == \"dev.mmtvl.launcher\" AND category == \"IPTV\"' --info" | grep 'Teams:'`. Note whether college games appeared as **playlist game entries** (and how they were named; take a photo of the guide) or only on networks. That closes finding 4's unverified point.
  - **Check nothing broke:** a pro team's game still shows in Teams; the channel menu on a game shows "Add <Team> (Football) to Teams" for a college game.
  - Done when: the user reports each item; findings go in *Deviations & questions* with fixes as new steps (tuning tokens needs a second build).

- [ ] **9. Docs** `[doc]`: files: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan
  - `CLAUDE.md`: `settings.json` `glassStyle` (Settings → System → Glass; `clear` | `light` | `frosted` | `darkFrosted` | `solid`, default `clear`; unknown values read as `clear`; Reduce Transparency always Solid); the UI conventions line on glass (`glassPanel(role:)`, the banner role, the `glassStyle` environment); the home screen paragraph: the dock fades in the grid (D47); `iptv-channels.json` `teams` takes college ids (`"ncaaf.michigan-wolverines"`; leagues `ncaaf`, `ncaam`, `ncaaw`, `ncaabase`); the guide's Choose Teams row and team search results; `scripts/gen-college-teams.py` (when and how to re-run it; it's the only thing that talks to ESPN); the `IPTV` log line `Teams: …`.
  - Master plan: M7l's row → Done (after step 8), link to the archived plan; D46–D48 already added at planning.
  - `git mv docs/plans/M7l-tv-polish.md docs/plans/archive/` when Done, and fix its relative links.
  - Done when: `CLAUDE.md` mentions `glassStyle`, `gen-college-teams.py` and the Choose Teams row, and the master plan's M7l row links the archive.

## Tests

| Suite (file) | Asserts |
|---|---|
| `GlassStyleTests` (new) | raw values; `GlassAppearance` per style and role; Solid and Reduce Transparency give no glass; Clear standard = today's tokens; banner ≥ Dark Frosted (step 1) |
| `AppSettingsTests` | `glassStyle` default, valid, unknown and wrong-type values, round-trip (step 2) |
| `SettingsModelTests` | System → Glass row and page; Teams' Pro/College sections, conference pages, counts (steps 2, 6) |
| `HomeLayoutTests` | `dockOpacity` per row (step 3) |
| `TeamCatalogTests` (new) | bundled catalog loads, unique ids, fixture decoding, `pickTitle`, conference order (step 5) |
| `TeamMatcherTests` | the college cases in step 5, pro cases unchanged |
| `TeamPickerTests` (new) | levels, values, push/pop (step 7) |
| `GuideModelTests` | Choose Teams row navigation and action (step 7) |
| `LiveSearchTests` | team results, toggle keeps search open, `firstResult` skips teams (step 7) |
| Live TV model tests | picker open, toggle, Back to the guide (step 7) |

Run: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test` (quote the result line). One test: `-only-testing:'MMTVLTests/TeamMatcherTests'`.

## Manual verification

On this Mac, `open build/Build/Products/Debug/MMTVL.app --args -windowed YES` (the Mac must be unlocked; screenshots for QA):

- [ ] Live TV banner frosted and darker; guide panels unchanged with Clear (step 1).
- [ ] Settings → System → Glass changes panels live; `settings.json` saves it (step 2).
- [ ] Home: Down fades the dock, Up brings it back (step 3).
- [ ] Settings → Live TV → Teams → College … toggles (step 6).
- [ ] Guide: Choose Teams and Search team results (step 7).

On the TV: step 8.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| `.regular` glass over moving video costs GPU time on the mini | dropped frames or stutter with the banner up (step 8) | Banner role on `.clear` with the darker tint only (a token change) |
| A step looks the same as its neighbour on the TV | user can't tell Light Tint from Clear, or Frosted from Dark Frosted | Retune the step's tokens (second build); steps and raw values stay |
| ESPN's endpoints change or disappear | the generator fails or counts fall out of range | The committed JSON keeps working; fix the script when the catalog next needs updating, or switch the source to NCAA conference pages by hand |
| ESPN's names differ from the provider's guide | a picked team's game is missing from Teams | Add aliases in the script's hand table and regenerate; the step 8 log line and guide photo show the names |
| College game entries in the playlist use another format ("Michigan vs Ohio State", no "@") | network games show, game entries don't | A follow-up step: accept " vs. " in game entry names (small change in `TeamMatcher.game(from:)`) |
| Re-airs count as games (e.g. Sunday's "College Football · Arkansas at Auburn" on SEC Network, no "Live:") | Teams lists a channel showing yesterday's game | A follow-up (out of scope here): when a guide marks live games with a "Live:" prefix, require it for Teams; needs the user's call and data from more than one guide |
| ~1,400 teams in memory and in matching | slow guide refresh | L10 tests only picked teams; the catalog is loaded once |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
