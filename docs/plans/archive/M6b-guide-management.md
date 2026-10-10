# M6b — IPTV guide management

| | |
|---|---|
| Status | Done |
| Depends on | M4 (Live TV: library, EPG store, matcher, guide), M6 (guide channel menu, `LiveMenu`) |
| Master plan decisions used | D2, D3, D8, D9, D10, D14, D19, D20, D23, D26 (new) |
| Planned | 2026-10-06 |

## Goal

From the couch, with only the remote, the Live TV guide can be tidied and completed:

- **More than one guide.** Settings → Live TV → *Guides* lists every XMLTV guide that was added. *Add Guide from Clipboard* adds another, up to 6. Each guide has its own page with *Move Up*, *Move Down* and *Remove Guide*. When two guides have the same channel, the higher one wins. So the user can keep **guide-source US2** and add **FANDUEL1** for the FanDuel regionals, **CA2** for TSN, and so on.
- **Match Guide.** In the guide, Left from the programme airing now, then Select, opens the channel menu (M6). It gains *Match Guide*. That opens a list: *Automatic*, *No Guide*, then up to 30 guide channels from every guide, ranked by how well their names fit. Choosing one gives the channel that guide data, and it stays across relaunches.
- **Favorites.** The channel menu gains *Add to Favorites* / *Remove from Favorites*. A **Favorites** group appears first in the guide's group list while it has channels. Favorites are in the order they were added. While the guide shows Favorites, the menu also has *Move Up* and *Move Down*. A star marks favorites in the guide.
- **Hiding.** The channel menu gains *Hide Channel*. Settings → Live TV → *Groups* hides or shows whole groups (say "NHL Games"). Settings → Live TV → *Hidden Channels* brings hidden channels back. Hidden channels and groups are gone from the guide, its groups and channel zapping.

## Out of scope

- **Text search** in Match Guide (user choice, 2026-10-06: suggestions only). Phone text still reaches only YouTube inside MMTVL (M5 L7).
- Hiding a group from the guide itself (user choice: Settings only).
- Catch-up (Q3: the provider has none).
- Reordering guides by anything other than *Move Up*/*Move Down*; renaming guides.
- Reordering normal groups or channels; custom channel numbers; renaming channels.
- A Settings page for the manual matches. They are reset with *Automatic* in Match Guide, or by hand in `epg-overrides.json`.
- PIN protection for the channel menu's items (L12).
- M7 items (bindings editor, polish).

## Research & findings

### guide-source files that cover the gaps (verified 2026-10-06 from [the file listing](https://guide-source.online/guide-source/))

M4 left **39 of the 97 live channels** without guide data on US2 (M4 *The chosen guide*). guide-source publishes per-country/per-network files, each with a `.txt` list of its channel ids next to it (`guide-source_<NAME>.txt`). Sizes are of the `.xml.gz` file.

| File | Size | Covers (checked in its `.txt` list) |
|---|---|---|
| `guide-source_US2.xml.gz` | 6.5 MB | The current guide (M4). Has `NESN+.New.England.Sports.Network.Plus.us2` but not plain NESN. |
| `guide-source_FANDUEL1.xml.gz` | **110 KB** | 45 channels: the FanDuel Sports Network regionals, `FanDuel.TV.us`, `Fanduel.Racing.us`. 4,233 programmes from Oct 5 to Oct 9 (about 4 days ahead). |
| `guide-source_CA2.xml.gz` | 6.5 MB | `TSN.1.ca2` … `TSN.5.ca2` (and HD variants), Sportsnet. |
| `guide-source_IN1.xml.gz` | 4.0 MB | `Star.Sports.1.in`, `Star.Sports.2.HD.in`, `Star.Sports.First.in` and language feeds. |
| `guide-source_MY1.xml.gz` | 0.5 MB | `Astro.Cricket.my`. |
| `guide-source_UK1.xml.gz` | 2.8 MB | `Premier.Sports.1.HD.uk`, `Premier.Sports.2.HD.uk`, some Sky Sports. **Not** Sky Sports Cricket or Golf. |
| `guide-source_ZA1.xml.gz` | 0.2 MB | Only `SuperSport.School.HD.za`, not the main SuperSport channels. |
| `guide-source_ALL_SOURCES1.xml.gz` | 192 MB | Everything (27,393 channels, about 2 GB unzipped). **Don't recommend it:** every refresh downloads 192 MB and unzips 2 GB to Caches. |

FANDUEL1's display names (exact, from the file):

- "FanDuel Sports Network Detroit HD", "FanDuel Sports Network Florida", "FanDuel Sports Network North", "FanDuel Sports Network Ohio - Cleveland", "FanDuel Sports Network SoCal", "FanDuel Sports Network Southwest", "FanDuel Sports Network Wisconsin", "FanDuel Sports Network West", "FanDuel Sports Network Great Lakes", "FanDuel Sports Network Oklahoma", "FanDuel Sports Network San Diego" …
- But also "**FanDuel Sports Indiana**", "FanDuel Sports New Orleans", "FanDuel Sports Southeast - Georgia", "FanDuel Sports Southwest - Houston", "Fanduel Sports Sun" (no "Network").
- So L6's exact matching will match some regionals by name (for example, "FanDuel Sports Network Detroit" → "fanduelsportsnetworkdetroit", since "HD" is dropped) and miss others. Those are what Match Guide's suggestions are for.
- **Unverified:** the playlist's exact FanDuel names. The planner tried to read the playlist through a script that never prints the URL, but the Keychain access prompt wasn't answered, so it was stopped. Step 3's and step 8's manual checks count channels with guide data before and after adding FANDUEL1 (Settings shows "Guide data for N of M channels").
- **Unverified:** whether the playlist's "TVG" is "FanDuel TV" (TVG's 2022 rename) or "Fanduel Racing" (TVG2's). Both are in FANDUEL1; the user picks with Match Guide.
- Not covered anywhere small: Red Zone2, PAC 12 (defunct), Sky Sports Cricket/Golf, SuperSport (main), plain NESN.

### GRDB (verified 2026-10-06 in the checked-out GRDB 7.11 sources, `build/SourcePackages/checkouts/GRDB.swift`)

- `TableDefinition.primaryKey(_ columns: [String], onConflict:)` declares a composite primary key over columns already added with `t.column(...)` (`GRDB/QueryInterface/Schema/TableDefinition.swift:321`).
- `Database.drop(table:)` exists (`Database+SchemaDefinition.swift:321`). Dropping a table drops its indexes (SQLite).
- `DatabaseMigrator` runs each registered migration once, in order. M4's `"v1"` stays; M6b adds `"v2"`.

### This codebase (read 2026-10-06; don't re-read to plan, read to implement)

- `EPGMatcher.match(_:to:overrides:)` returns `[Channel.ID: String]` (lowercased EPG id) over **one** list of `EPGChannel`. `GuideImporter` uses it to choose the wanted ids while parsing; `IPTVLibrary.rematch()` uses it over everything in the store.
- `EPGStore` has one `epgChannel` table (primary key `id`) and one `programme` table, replaced as a whole by `replaceAll`.
- `IPTVSourceStore` holds one guide URL (Keychain account `iptv-guide-url`). `IPTVLibrary.guideSource` is `.custom` (pasted) else `.playlist` (first `url-tvg`) else `.none` (M4 L3).
- `IPTVState` keeps `lastGuideImport` and `lastGuideSourceHash` (SHA-256 of the URL, `IPTVLibrary.hash`).
- `GuideModel` builds its groups with `ChannelList.guideGroups(of:)` and its rows with `ChannelList.channels(in:of:)`. `LiveTVModel.zap` uses `ChannelList.channels(in:of:)` too.
- `LiveMenu` draws every item; it has no scrolling. Its items are `id`, `title`, `value`, `layout`, `action`.
- `LiveTVView` calls `model.channelsChanged()` on `.onChange(of: model.library.channels)` and `model.guideDataChanged()` on `guideRevision`.
- Settings pages are data (`SettingsPage`, `SettingsAction`, `SettingsRow`), drawn by one scrolling list. Long lists work (Add Tile lists every installed app).

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL/IPTV/EPG/Programme.swift` | changed | `sourceID` on `Programme` and `EPGChannel`; new `EPGRef`. |
| `MMTVL/IPTV/EPG/EPGStore.swift` | changed | Migration `v2` (per-source tables); per-source replace/remove/count; queries by `EPGRef`. |
| `MMTVL/IPTV/EPG/EPGMatcher.swift` | changed | Multi-source matching (L3); `""` override = no guide (L6); `tokens(_:)`. |
| `MMTVL/IPTV/EPG/GuideImporter.swift` | changed | Imports one source, by id. |
| `MMTVL/IPTV/EPG/GuideSource.swift` | new | `GuideSource`: URL, id, labels (L2). |
| `MMTVL/IPTV/EPG/EPGSuggester.swift` | new | Pure ranking for Match Guide (L7). |
| `MMTVL/IPTV/EPG/GuideMatch.swift` | new | `GuideMatchChoice`, `GuideCandidate`, `GuideMatchOptions`. |
| `MMTVL/IPTV/Sources/IPTVSourceStore.swift` | changed | A list of guide URLs (Keychain `iptv-guide-urls`), migrating `iptv-guide-url` (L1). |
| `MMTVL/IPTV/Sources/ChannelPreferences.swift` | new | `ChannelPreferences` (persisted) and `ChannelLineup` (pure: groups and rows after favorites/hiding). |
| `MMTVL/IPTV/IPTVState.swift` | changed | `guideImports: [String: Date]` replaces `lastGuideImport`/`lastGuideSourceHash`. |
| `MMTVL/IPTV/IPTVLibrary.swift` | changed | Guide sources, per-source refresh and status, preferences and lineup, match options, manual matches. |
| `MMTVL/IPTV/Guide/GuideModel.swift` | changed | Built from a `ChannelLineup`. |
| `MMTVL/IPTV/Guide/GuideView.swift` | changed | Star on favorites. |
| `MMTVL/IPTV/LiveMenu.swift` | changed | Scrolling (8 visible rows), `isWide`, new actions. |
| `MMTVL/IPTV/LiveMenuView.swift` | changed | Draws the visible window and scroll chevrons; wide panel. |
| `MMTVL/IPTV/LiveTVModel.swift` | changed | Channel menu items; Match Guide menu; zapping with the lineup. |
| `MMTVL/IPTV/LiveTVView.swift` | changed | `onChange(of: lineup)`; passes favorites to `GuideView`. |
| `MMTVL/Settings/SettingsTypes.swift`, `SettingsModel.swift`, `SettingsModel+Pages.swift`, `SettingsEnvironment.swift` | changed | Guides list and guide page; Groups and Hidden Channels pages. |
| `MMTVL/App/AppDelegate.swift` | changed | Wiring: preferences file, status, new environment closures. |
| `MMTVL/DesignSystem/Theme.swift` | changed | `liveMenuWideWidth`, `guideFavoriteSymbolSize`. |
| `MMTVLTests/…` | new/changed | See *Tests*. |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | changed | Step 10. |

New files under `MMTVL/` and `MMTVLTests/` are picked up by the file-system-synchronized groups. **Don't edit `project.pbxproj`.**

### Local decisions

- **L1. Guide URLs are a list in the Keychain** (D9, D23): account **`iptv-guide-urls`**, a JSON array of URL strings, in paste order.
  - At most **6** pasted guides (`IPTVLibrary.maxGuideSources`). The *Add* row disappears at 6.
  - **Migration:** `guideURLs()` reads `iptv-guide-urls`; if that account is missing, it reads M4's `iptv-guide-url` and returns `[that]` (or `[]`). `setGuideURLs(_:)` writes `iptv-guide-urls` (or removes it when empty) and always removes `iptv-guide-url`. `removeAll()` removes all three accounts.
  - **Which guides are used** (M4 L3, extended): the pasted list when it's not empty, else **all** of the playlist's `url-tvg`/`x-tvg-url` guides (`M3UPlaylist.guideURLs`), else none. Adding the first pasted guide therefore replaces the playlist's guides; removing the last brings them back.
  - A pasted URL already in the list (same `IPTVLibrary.hash`) is refused with "That guide is already added".
- **L2. A guide's id and labels.** `GuideSource.id = IPTVLibrary.hash(url)` (SHA-256 hex; the database and state file never hold a URL).
  - `label`: `"<host> · <file name>"` when the URL's `lastPathComponent` ends in `.xml`, `.xml.gz` or `.gz` (case-insensitive) and is at most 64 characters; else the host alone. Example: "guide-source.online · guide-source_US2.xml.gz".
  - `shortLabel`: that file name without `.xml.gz`/`.xml`/`.gz` ("guide-source_US2"), else the host.
  - This **changes M4 L2** for guides only: Settings may show a guide's file name. A token in a URL's query is never shown (it's not part of `lastPathComponent`), and a token-like path segment isn't either (no guide-file extension). **Logs still use the host only.** Playlist and stream URLs are unchanged: host only, everywhere.
- **L3. Per-source storage and priority.**
  - Every `epgChannel` and `programme` row carries `sourceID`. Importing a guide replaces only its own rows. Rows of guides no longer in use are deleted after each refresh (`removeSources(keeping:)`).
  - Migration `v2` **drops and recreates** both tables (the guide is a cache, D8). The next launch re-imports every guide, because `IPTVState.guideImports` starts empty.
  - **Matching is per rule, then per guide** (`EPGMatcher.match(_:sources:overrides:)`): for each playlist channel, try rule 1 in every guide in list order, then rule 2 in every guide, then rule 3. So an exact `tvg-id` in a lower guide beats a name match in a higher one. Within a rule, the higher guide wins. Rules are M4 L6's, unchanged.
  - **Import keeps more than the final match needs:** a guide's import keeps programmes for every channel that guide would match **on its own** (M4 behavior per guide), plus override targets in it. So moving or removing a guide only re-matches; it never downloads.
- **L4. Refresh per guide.** `IPTVState.guideImports[id]` is the last successful import time of each guide.
  - `refreshGuideIfStale()` imports the guides whose time is missing or more than 12 h old (M4 L5's interval).
  - `refreshGuide()` (Refresh Now) imports every guide; `refreshGuide(sourceIDs:)` imports some. Imports run **one at a time** through a queue: a request made while a run is going adds to the queue, and the running loop picks it up. A run ends with pruning and one `rematch()`.
  - A failing guide keeps its old rows and shows "Failed: …" on its row; the others still import.
  - Imports still need channels: while `channels` is empty, the queue is kept and the run returns (M4 deviation, step 6).
- **L5. Favorites and hiding live in `iptv-channels.json`** (D10), `ChannelPreferences`: `favorites` (channel ids, order added), `hiddenChannels` (ids), `hiddenGroups` (group names, case-sensitive as in the playlist).
  - Hand-editable while MMTVL is quit. Undecodable keys read as empty (tolerant decoding per key). A corrupt file → `.bak` + defaults, as every `JSONConfigFile`.
  - Ids are `Channel.ID`s (M4: `id:<tvg-id>` or `name:<name>`, `#2` for duplicates). Ids not in the playlist are kept in the file and ignored, so a channel that comes back keeps its favorite/hidden state.
  - *Remove Live TV Source* keeps this file and `epg-overrides.json`.
- **L6. Manual matches are written to `epg-overrides.json`** (M4 L17: "M6's matching UI will write the same file").
  - Match Guide writes the key **`channel.name`** (as in the playlist), after removing every key equal, ignoring case, to the channel's name or its non-empty `tvg-id`.
  - A value of **`""`** means **No Guide**: rule 1 stops there and the channel gets no guide data. This is new; M4 ignored unknown targets, and still does for non-empty values.
  - *Automatic* only removes those keys.
  - The value is the EPG id alone (lowercased, as stored). If two guides have the same id, the higher guide's wins. guide-source ids carry a per-file suffix (`.us2`, `.ca2`, `.in`), so this doesn't happen in practice.
  - After a choice: if the chosen channel's programmes aren't stored (it wasn't wanted at import), that guide is re-imported (`refreshGuide(sourceIDs: [ref.sourceID])`, about 10 s for US2). Otherwise only `rematch()` runs.
  - The file is rewritten sorted and pretty-printed by `JSONConfigFile.save`. Hand edits made while MMTVL runs can be overwritten, as for every config file.
- **L7. Match Guide suggestions** (`EPGSuggester`, user choice: suggestions only).
  - **Tokens** (`EPGMatcher.tokens(_:)`): M4's normalization without the final join: fold case and diacritics, `&` → "and", `+` → "plus", split on non-alphanumerics, drop `hd fhd uhd sd 4k hevc`, then de-duplicate keeping order.
  - **Channel tokens:** the union of the tokens of `name`, `tvgName`, and `tvgID` with its **last** token dropped when it has 2 or more ("nflnetwork.us" → "nflnetwork").
  - **Guide channel tokens:** the union of the tokens of every display name and of its id with its last token dropped the same way ("FanDuel.Sports.Indiana.us" → fanduel, sports, indiana).
  - **Score:** with `N` = guide channels across all guides and `df(t)` = how many contain token `t`, `idf(t) = ln(1 + N / df(t))` (a token in none uses `df = 1`). `score = Σ idf(shared tokens) / Σ idf(channel tokens)`, between 0 and 1.
  - **Order:** score descending; then fewer guide-channel tokens that the channel doesn't have; then guide order; then id ascending. Only `score > 0`. At most **30**.
  - It's for **suggestions only**. Automatic matching stays exact (M4 L6: fuzzy matching was measured and gave wrong channels).
- **L8. The channel menu** (M6 L8) in the **watch** guide, in this order:

  | id | Title | When |
  |---|---|---|
  | `watch` | Watch | always |
  | `addToMultiview` | Add to Multiview / Show in Multiview | always (M6) |
  | `favorite` | Add to Favorites / Remove from Favorites | always |
  | `moveUp` | Move Up | the guide shows Favorites and the channel isn't first there |
  | `moveDown` | Move Down | the guide shows Favorites and the channel isn't last there |
  | `matchGuide` | Match Guide (value: the matched guide's `shortLabel`, or "None") | always |
  | `hide` | Hide Channel | always |

  - *Move Up/Down* keep the menu open (rebuilt with the same item focused, or the nearest one if it disappeared), so several moves need no reopening.
  - The other items close the menu. *Add/Remove Favorites* and *Hide Channel* update the guide at once; the guide keeps its focus by channel id, else the same row.
  - The picker guide (M6 L11) is unchanged: Select on the channel cell still puts the channel in the window, with no menu.
- **L9. The Match Guide menu** is a wide, scrolling `LiveMenu` titled "Guide for <channel name>":
  - `match.automatic` **Automatic** (value "Selected" when no override applies).
  - `match.none` **No Guide** (value "Selected" when the override is `""`).
  - Then the candidates: the channel's **current match first** (if any), then the suggestions without it. id `match.<sourceID>.<epgID>`, title = the guide channel's first display name (else its id), value = the guide's `shortLabel`, plus " · Selected" when it's the manual choice, or " · Automatic" when it's the automatic match in use.
  - The focus starts on the "Selected" row (Automatic when none is marked).
  - The menu opens after its options load (an async store read and ranking, under 100 ms for US2). Nothing shows meanwhile.
- **L10. `LiveMenu` scrolls.** At most **8** rows show (`LiveMenu.visibleRows`). `firstVisibleIndex` keeps the focus in view, moving the window only when the focus would leave it. The view shows a chevron above/below when rows are hidden that way. `isWide` panels use `Theme.liveMenuWideWidth` (1040).
- **L11. The lineup** (`ChannelLineup`) is what every Live TV list uses: the guide's groups and rows, zapping, and the Multiview picker guide.
  - **Visible channels:** playlist order, without hidden channels and without channels of hidden groups.
  - **Favorites:** `preferences.favorites` in that order, keeping visible playlist channels only.
  - **Groups:** `["Favorites"]` when there are visible favorites, then `ChannelList.guideGroups(of: visibleChannels)` (so "All Channels" when more than one group is visible).
  - `channels(in:)`: Favorites → favorites; All Channels → visible channels; a group → its visible channels; an unknown group → `[]`.
  - The guide's default group (no remembered group) is the first one, so **Favorites when it exists**.
  - A playlist group literally named "Favorites" would merge with ours. Accepted (not in the user's playlist).
  - Channel numbers stay the playlist's (hiding doesn't renumber).
  - **Zapping** (M4 Up/Down in the player): the remembered group's list if it holds the current channel; else the current channel's group; else all visible channels. If the current channel isn't in the list (it was hidden while playing), Down plays the list's first and Up its last.
  - Hidden channels still play when already playing, when they are the last channel at launch, or when they are in a Multiview window. Hiding stops nothing.
- **L12. No PIN for the channel menu.** Favorites, Match Guide and Hide Channel act at once. Hidden channels and groups come back only in Settings, which the launcher PIN guards (D20).
- **L13. No new `RemoteCommand`s** (M4 L10, M6 L16).

### Key types

```swift
// IPTV/EPG/Programme.swift (changes)
nonisolated struct Programme: … {           // unchanged conformances
    // … existing stored properties unchanged …
    /// GuideSource.id. Last, with a default, so XMLTVParser's memberwise calls still compile.
    var sourceID: String = ""
    enum Columns { /* existing + */ static let sourceID = Column(CodingKeys.sourceID) }
}
nonisolated struct EPGChannel: … {
    var id: String
    var names: [String]
    var sourceID: String = ""
}
/// One guide channel in one guide.
nonisolated struct EPGRef: Hashable, Codable, Sendable {
    var sourceID: String
    /// Lowercased EPG channel id.
    var epgID: String
}
```

```swift
// IPTV/EPG/EPGStore.swift (new API; replaceAll and channels() go)
func replaceSource(_ sourceID: String, channels: [EPGChannel], programmes: [Programme]) async throws
    // one transaction: delete rows with this sourceID, insert all with sourceID set (programme.id = nil)
func removeSources(keeping ids: Set<String>) async throws   // deletes rows of every other sourceID
func channelsBySource() async throws -> [String: [EPGChannel]]
func programmes(refs: Set<EPGRef>, overlapping interval: DateInterval) async throws -> [EPGRef: [Programme]]
    // SQL filter: sourceID IN refs' sources AND channelID IN refs' ids AND overlap; then keep exact pairs; sorted by start
func programmeCounts() async throws -> [String: Int]       // SELECT sourceID, COUNT(*) … GROUP BY sourceID
func programmeCount(for ref: EPGRef) async throws -> Int
func programmeCount() async throws -> Int                   // unchanged: all rows
func removeAll() async throws                               // unchanged
```

Migration `v2` (after `v1`):

```swift
migrator.registerMigration("v2") { db in
    try db.drop(table: Programme.databaseTableName)
    try db.drop(table: EPGChannel.databaseTableName)
    try db.create(table: EPGChannel.databaseTableName) { t in
        t.column("sourceID", .text).notNull()
        t.column("id", .text).notNull()
        t.column("names", .text).notNull()
        t.primaryKey(["sourceID", "id"])
    }
    try db.create(table: Programme.databaseTableName) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("sourceID", .text).notNull()
        t.column("channelID", .text).notNull()
        t.column("start", .datetime).notNull()
        t.column("stop", .datetime).notNull()
        t.column("title", .text).notNull()
        t.column("subtitle", .text)
        t.column("summary", .text)
        t.column("category", .text)
        t.column("episode", .text)
    }
    try db.create(index: "programme_on_source_channel_start", on: Programme.databaseTableName,
                  columns: ["sourceID", "channelID", "start"])
}
```

```swift
// IPTV/EPG/EPGMatcher.swift (additions)
nonisolated struct EPGSourceChannels: Sendable {
    var sourceID: String
    var channels: [EPGChannel]
}
nonisolated enum EPGMatcher {
    static func normalize(_ name: String) -> String          // unchanged: tokens(name).joined()
    /// L7.
    static func tokens(_ name: String) -> [String]
    /// L3. `sources` in priority order. An override value "" means no guide (L6).
    static func match(_ channels: [Channel], sources: [EPGSourceChannels], overrides: [String: String] = [:]) -> [Channel.ID: EPGRef]
    /// One guide (the importer, M4 tests): match(channels, sources: [.init(sourceID: "", channels:)], overrides:).mapValues(\.epgID)
    static func match(_ channels: [Channel], to epgChannels: [EPGChannel], overrides: [String: String] = [:]) -> [Channel.ID: String]
}
```

- `normalize` must keep returning exactly what it returns now. Move its body into a private `rawTokens(_:) -> [String]` (everything before the join). Then `normalize = rawTokens(name).joined()` and `tokens = rawTokens(name)` de-duplicated, keeping the first occurrence. Don't build `normalize` from `tokens`: de-duplicating changes "NBA TV TV".
- `match(_:sources:overrides:)`, per channel:
  1. Override lookup as now (name, then `tvg-id`, lowercased keys). Value `""` → no match, next channel. Otherwise the **first** source whose ids contain the target → match. None → debug log, fall through.
  2. `tvgID.lowercased()`: the first source whose ids contain it.
  3. For each of `[tvgName, name]` (non-nil), for each source in order: that source's normalized-name map (first display name in file order wins, as now).

```swift
// IPTV/EPG/GuideSource.swift
nonisolated struct GuideSource: Identifiable, Equatable, Sendable {
    let url: URL
    let isFromPlaylist: Bool
    var id: String { IPTVLibrary.hash(url) }      // IPTVLibrary.hash must become nonisolated static
    var label: String                            // L2
    var shortLabel: String                       // L2
    init(url: URL, isFromPlaylist: Bool)
    /// L2: the file name when it looks like a guide file, else nil.
    static func fileName(of url: URL) -> String?
}
```

`IPTVLibrary.hash` is a `static func` on a MainActor class. Mark it `nonisolated static func hash(_:)` so `GuideSource` (nonisolated) can call it.

```swift
// IPTV/EPG/GuideMatch.swift
nonisolated enum GuideMatchChoice: Hashable, Sendable { case automatic, none, epg(EPGRef) }
nonisolated struct GuideCandidate: Identifiable, Equatable, Sendable {
    var ref: EPGRef
    var name: String              // first display name, else epgID
    var sourceLabel: String       // GuideSource.shortLabel
    var id: EPGRef { ref }
}
nonisolated struct GuideMatchOptions: Equatable, Sendable {
    var choice: GuideMatchChoice  // .automatic (no override applies), .none (""), .epg(current) (an override that resolved)
    var current: EPGRef?          // library.epgMatches[channel.id]
    var candidates: [GuideCandidate]   // L9: current first, then suggestions without it
}
```

```swift
// IPTV/EPG/EPGSuggester.swift
nonisolated enum EPGSuggester {
    struct Candidate: Equatable, Sendable { var ref: EPGRef; var name: String; var score: Double }
    /// L7. Runs off the main actor (ALL_SOURCES1 has 27k channels).
    @concurrent static func suggest(for channel: Channel, in sources: [EPGSourceChannels], limit: Int = 30) async -> [Candidate]
    /// The pure core, for tests.
    static func rank(_ channel: Channel, in sources: [EPGSourceChannels], limit: Int) -> [Candidate]
}
```

```swift
// IPTV/Sources/ChannelPreferences.swift
nonisolated struct ChannelPreferences: Codable, Equatable, Sendable {
    static let fileName = "iptv-channels.json"
    var favorites: [Channel.ID] = []
    var hiddenChannels: [Channel.ID] = []
    var hiddenGroups: [String] = []
    init(favorites: [Channel.ID] = [], hiddenChannels: [Channel.ID] = [], hiddenGroups: [String] = [])
    /// Each key decodeIfPresent via `try?`, flattened; missing or bad → [].
    init(from decoder: Decoder) throws
}

nonisolated struct ChannelLineup: Equatable, Sendable {
    static let favoritesGroup = "Favorites"
    private(set) var groups: [String]
    /// Playlist order, without hidden channels and hidden groups (L11).
    private(set) var visibleChannels: [Channel]
    /// preferences.favorites order, visible only.
    private(set) var favorites: [Channel]
    init(channels: [Channel], preferences: ChannelPreferences = ChannelPreferences())
    func channels(in group: String) -> [Channel]
    func isVisible(_ id: Channel.ID) -> Bool
}
```

```swift
// IPTV/Sources/IPTVSourceStore.swift (guide members replaced)
static let guideListAccount = "iptv-guide-urls"
static let legacyGuideAccount = "iptv-guide-url"          // was guideAccount
var guideURLs: () -> [URL]                                 // L1 migration on read
var setGuideURLs: ([URL]) throws -> Void                   // [] removes; always removes the legacy account
static func inMemory(playlist: URL? = nil, guides: [URL] = []) -> IPTVSourceStore
```

- The Keychain value is `String(decoding: try JSONEncoder().encode(urls.map(\.absoluteString)), as: UTF8.self)`. Reading decodes `[String]` and keeps those that parse as URLs. A value that doesn't decode is logged (no contents) and reads as `[]`.

```swift
// IPTV/IPTVState.swift
nonisolated struct IPTVState: Codable, Equatable, Sendable {
    var lastChannelID: String?
    var lastGroup: String?
    /// GuideSource.id → last successful import (L4). Replaces lastGuideImport / lastGuideSourceHash.
    var guideImports: [String: Date]
    var multiview: MultiviewSnapshot?
    init(lastChannelID: String? = nil, lastGroup: String? = nil, guideImports: [String: Date] = [:], multiview: MultiviewSnapshot? = nil)
    // decoding: guideImports = (try? decodeIfPresent([String: Date].self)) ?? [:]; old keys are ignored and dropped on the next save
}
```

```swift
// IPTV/IPTVLibrary.swift (changes)
@Observable final class IPTVLibrary {
    static let maxGuideSources = 6
    enum AddGuideProblem: Equatable { case duplicate, full }
    struct GuideSourceInfo: Equatable {
        var status: Status = .idle
        var programmeCount = 0
        var matchedChannels = 0
    }

    private(set) var guideSources: [GuideSource] = []            // L1; recomputed from customGuideURLs / playlistGuideURLs
    private(set) var guideSourceInfo: [String: GuideSourceInfo] = [:]
    private(set) var preferences: ChannelPreferences
    private(set) var lineup = ChannelLineup(channels: [])
    @ObservationIgnored private(set) var epgMatches: [Channel.ID: EPGRef] = [:]   // was epgIDs
    var customGuideCount: Int                                   // customGuideURLs.count
    var matchedChannelCount: Int                                // epgMatches.count
    // guideStatus stays: .loading during a run; then .loaded(now) or, when every guide of the run failed, .failed(first message)
    // guideProgrammeCount stays: the sum over guideSourceInfo
    // guideSource / GuideSource enum / setGuideURL(_:) go

    init(sources:, store:, network:, stateFile:, overridesFile:,
         preferencesFile: JSONConfigFile<ChannelPreferences>, now:)

    // Guides
    func guideAddProblem(_ url: URL) -> AddGuideProblem?
    func addGuideURL(_ url: URL) async                     // append, save, refreshGuide(sourceIDs: [id])
    func removeGuideSource(_ id: String) async             // remove, save, delete its rows and guideImports[id], rematch;
                                                           // if now empty and the playlist has guides: refreshGuideIfStale()
    func moveGuideSource(_ id: String, by step: Int) async // clamp, save, rematch (no download)
    func refreshGuide() async                              // every guide (Refresh Now)
    func refreshGuide(sourceIDs: Set<String>) async
    func refreshGuideIfStale() async                       // L4
    func refreshAll() async                                // playlist, then refreshGuide()

    // Channels (L5, L11). Each saves iptv-channels.json, recomputes `lineup` and calls onStatusChange.
    func isFavorite(_ id: Channel.ID) -> Bool
    func setFavorite(_ id: Channel.ID, _ isFavorite: Bool)    // add appends; remove deletes
    func moveFavorite(_ id: Channel.ID, by step: Int)         // swaps with the neighbor among lineup.favorites
    func setChannelHidden(_ id: Channel.ID, _ hidden: Bool)
    func setGroupHidden(_ group: String, _ hidden: Bool)

    // Matching (L6, L9)
    func guideMatchOptions(for channel: Channel) async -> GuideMatchOptions
    func setGuideMatch(_ choice: GuideMatchChoice, for channel: Channel) async
    func guideLabel(for ref: EPGRef) -> String?               // the source's shortLabel

    // Queries: programmes(for:in:) and nowNext(for:at:) keep their signatures, now through epgMatches/refs
}
```

Library internals:

- `customGuideURLs: [URL]` (read at init from `sources.guideURLs()`), `playlistGuideURLs: [URL]` (from the last playlist). `updateGuideSources()` sets `guideSources = custom.isEmpty ? playlist.map { GuideSource(url: $0, isFromPlaylist: true) } : custom.map { …false }`. Call it at init, after a playlist load, and after every custom-list change.
- At init, the existing programme-count task becomes: `store.programmeCounts()` → fill `guideSourceInfo[id].programmeCount` and `guideProgrammeCount`.
- **The import queue** (L4): `@ObservationIgnored private var queuedSourceIDs: Set<String>`, `private var isImportingGuide = false`.

  ```text
  refreshGuide(sourceIDs ids):
    guard let store else { setGuideStatus(.failed("Guide storage unavailable")); return }
    queuedSourceIDs ∪= ids
    guard !isImportingGuide else { return }
    guard !channels.isEmpty else { return }            // queue kept for later
    isImportingGuide = true; setGuideStatus(.loading)
    var succeeded = 0, firstFailure: String?
    while let source = guideSources.first(where: { queuedSourceIDs.contains($0.id) }) {
        queuedSourceIDs.remove(source.id)
        set guideSourceInfo[source.id].status = .loading; onStatusChange
        do { outcome = try await GuideImporter.importGuide(from: source.url, sourceID: source.id, channels:, overrides: overridesFile.load(), store:, network:, now: now())
             info.programmeCount = outcome.programmeCount; info.status = .loaded(now()); updateState { $0.guideImports[source.id] = now() }; succeeded += 1 }
        catch { log host + redacted; info.status = .failed(message); firstFailure = firstFailure ?? message }
    }
    queuedSourceIDs = []                                // ids of guides removed meanwhile
    try? await store.removeSources(keeping: Set(guideSources.map(\.id)))   // log errors
    updateState { $0.guideImports = $0.guideImports.filter { ids in guideSources } }
    guideProgrammeCount = sum; await rematch()
    isImportingGuide = false
    setGuideStatus(succeeded > 0 || firstFailure == nil ? .loaded(now()) : .failed(firstFailure!))
  ```

  - With no guides at all, `refreshGuide()` prunes, rematches and sets `.idle` (M4: "Idle when there is no guide source").
  - `refreshGuideIfStale()`: ids of guides with `guideImports[id]` missing or older than `guideStaleness`; none → return.
- **`rematch()`:** `channelsBySource()` → `[EPGSourceChannels]` in `guideSources` order (skip ids not in use) → `EPGMatcher.match(channels, sources:, overrides: overridesFile.load())` → `epgMatches`. Then each `guideSourceInfo[id].matchedChannels` = how many matches point to it. `guideRevision += 1`.
- **`programmes(for:in:)`:** pairs `(channel.id, epgMatches[channel.id])`; `store.programmes(refs:overlapping:)`; map back to `Channel.ID`.
- **`guideMatchOptions(for:)`:**
  1. `bySource = store.channelsBySource()`; `sources` in `guideSources` order.
  2. `suggestions = await EPGSuggester.suggest(for: channel, in: sources)`.
  3. `current = epgMatches[channel.id]`. The override for the channel (`overridesFile.load()`, name then `tvg-id`, ignoring case): `""` → `.none`; non-empty and `current != nil` → `.epg(current!)`; else `.automatic`.
  4. Candidates: `current` (name looked up in `bySource`) first, then the suggestions whose ref ≠ current. `sourceLabel` from `guideSources`.
- **`setGuideMatch(_:for:)`:** per L6. Save errors are logged and stop there.
- **`refreshPlaylist()`:** after `channels = …`, also `playlistGuideURLs = playlist.guideURLs`, `updateGuideSources()`, `updateLineup()`.
- **`removeSource()`:** clears `customGuideURLs`, `playlistGuideURLs`, `guideSources`, `guideSourceInfo`, `epgMatches`, `lineup` (empty channels); keeps `preferences` (L5).
- `updateLineup()`: `lineup = ChannelLineup(channels: channels, preferences: preferences)`.

`GuideImporter.importGuide(from:sourceID:channels:overrides:store:network:now:)`: as now, but `EPGMatcher.match(channels, to: parsedChannels, overrides:)` (one guide; `""` values are no match, so never wanted) and `store.replaceSource(sourceID, …)`.

`GuideModel` changes:

```swift
init(lineup: ChannelLineup, group: String?, focusedChannelID: Channel.ID?, now: Date)
/// Tests and old callers: init(lineup: ChannelLineup(channels: allChannels), …).
init(allChannels: [Channel], group: String?, focusedChannelID: Channel.ID?, now: Date)
mutating func setLineup(_ lineup: ChannelLineup)              // was setChannels(allChannels:); same keep-group/row rules
mutating func setChannels(allChannels: [Channel])             // keep as a wrapper: setLineup(ChannelLineup(channels: allChannels))
```

- `groups = lineup.groups`; rows = `lineup.channels(in: selectedGroup)`.
- In `init`, when `focusedChannelID` isn't in the selected group's rows: switch to `ChannelList.allChannelsGroup` if `groups` has it; else to the channel's own group if `groups` has it; else keep. (M4 switched only when All Channels was first, which is no longer true with Favorites.)

`LiveMenu` changes:

```swift
nonisolated enum LiveMenuAction: Hashable, Sendable {
    // … M6 cases …
    case toggleFavorite(Channel.ID)
    case moveFavorite(Channel.ID, by: Int)
    case openMatchGuide(Channel.ID)
    case matchGuide(Channel.ID, GuideMatchChoice)
    case hideChannel(Channel.ID)
}
nonisolated struct LiveMenu {
    static let visibleRows = 8
    var isWide = false
    private(set) var firstVisibleIndex = 0
    init(title:, items:, focusedIndex: = 0, isWide: Bool = false)
        // focusedIndex clamped as now; firstVisibleIndex = min(focusedIndex, max(0, items.count − visibleRows))
    var visibleRange: Range<Int>        // firstVisibleIndex ..< min(firstVisibleIndex + visibleRows, items.count)
    var hasHiddenAbove: Bool            // firstVisibleIndex > 0
    var hasHiddenBelow: Bool            // visibleRange.upperBound < items.count
    // handle: after Up/Down, if focusedIndex < first → first = focusedIndex; if focusedIndex ≥ first + visibleRows → first = focusedIndex − visibleRows + 1
}
```

### LiveTVModel changes

- **`channelMenu(for id:, focusing itemID: String? = nil)`**: L8's items. `inFavorites = guide?.selectedGroup == ChannelLineup.favoritesGroup`; position from `library.lineup.favorites`. `matchGuide`'s value is `library.epgMatches[id].flatMap(library.guideLabel(for:)) ?? "None"`. `focusing` picks the item with that id, else the item at the same index clamped (for Move Up/Down, L8).
- **`perform`**, new cases:
  - `.toggleFavorite(id)` → `library.setFavorite(id, !library.isFavorite(id))`; `channelsChanged()`.
  - `.moveFavorite(id, step)` → `library.moveFavorite(id, by: step)`; `channelsChanged()`; `menu = channelMenu(for: id, focusing: step < 0 ? "moveUp" : "moveDown")`.
  - `.hideChannel(id)` → `library.setChannelHidden(id, true)`; `channelsChanged()`.
  - `.openMatchGuide(id)` → `pendingTask = Task { options = await library.guideMatchOptions(for: channel); guard !Task.isCancelled, mode == .guide, menu == nil else { return }; menu = matchMenu(channel, options) }`.
  - `.matchGuide(id, choice)` → `pendingTask = Task { await library.setGuideMatch(choice, for: channel) }`. The guide reloads through `guideRevision` (the view) when the rematch lands.
- **`matchMenu(_ channel:, _ options:)`**: L9's items, `isWide: true`, focus on the "Selected" row.
- **`channelsChanged()`**: `guide?.setLineup(library.lineup)`; if `.guide`, `loadProgrammes()`. The view calls it on `onChange(of: model.library.lineup)` (replacing the `channels` onChange). The model's own calls make tests independent of the view; calling it twice is harmless.
- **`openGuide()` / `openPicker(slot:)`**: `GuideModel(lineup: library.lineup, …)`.
- **`zap(_:)`**: L11.

### Settings

`SettingsPage` gains `guideSource(id: String)`, `iptvGroups`, `iptvHiddenChannels`. `SettingsAction`: remove `useIPTVPlaylistGuide`; add `moveGuideSource(id: String, by: Int)`, `removeGuideSource(id: String)`, `toggleIPTVGroupHidden(String)`, `unhideIPTVChannel(id: String)`.

`IPTVSettingsStatus` (remove `guideKind`, `guideLine`, `GuideKind`):

```swift
var guideSources: [GuideSourceStatus] = []
var customGuideCount = 0
var matchedChannelCount = 0
var groups: [GroupStatus] = []
var hiddenChannels: [HiddenChannelStatus] = []

struct GuideSourceStatus: Identifiable, Equatable, Sendable { var id: String; var label: String; var line: String; var isFromPlaylist: Bool }
struct GroupStatus: Identifiable, Equatable, Sendable { var name: String; var channelCount: Int; var isHidden: Bool; var id: String { name } }
struct HiddenChannelStatus: Identifiable, Equatable, Sendable { var id: String; var number: Int; var name: String; var group: String }
```

`SettingsEnvironment`: remove `useIPTVPlaylistGuide`; add

```swift
var moveGuideSource: (String, Int) -> Void        // Task { await library.moveGuideSource(id, by:) }
var removeGuideSource: (String) -> Void           // Task { await library.removeGuideSource(id) }
var setIPTVGroupHidden: (String, Bool) -> Void    // library.setGroupHidden
var unhideIPTVChannel: (String) -> Void           // library.setChannelHidden(id, false)
```

`SettingsModel`:

- `pasteMessageKind: IPTVURLKind?` is set with `pasteMessage` in `.pasteIPTVURL(kind)` and cleared with it. The playlist paste row shows `pasteMessage` only when the kind is `.playlist`; the guide add row only when `.guide`.
- `.moveGuideSource(id, step)` → environment; `refreshStatus()`.
- `.removeGuideSource(id)` → environment; `pop()`; `refreshStatus()`.
- `.toggleIPTVGroupHidden(name)` → `environment.setIPTVGroupHidden(name, !(iptv.groups.first { $0.name == name }?.isHidden ?? false))`; `refreshStatus()`.
- `.unhideIPTVChannel(id)` → environment; `refreshStatus()`. Focus falls to the first row (ListFocus) when the row goes.

Pages (`SettingsModel+Pages.swift`):

- **Live TV, "Guides" section** (replaces "Guide"; only when there is a playlist):
  - Per `iptv.guideSources` element `s` at index `i`: row `"iptv.guide.\(s.id)"`, title `s.label`, value `s.isFromPlaylist ? "From Playlist" : "\(i + 1)"`, detail `s.line`. Pasted guides: `showsDisclosure: true`, action `.push(.guideSource(id: s.id))`. Playlist guides: info rows (no action).
  - No guides: info row `"iptv.guide.none"` "No guide", detail "Copy an XMLTV guide address, then add it below".
  - While `customGuideCount < IPTVLibrary.maxGuideSources`: `"iptv.guide.add"` "Add Guide from Clipboard", detail `pasteMessage` (kind `.guide`) ?? "Copy an XMLTV address on this Mac or your iPhone first", action `.pasteIPTVURL(.guide)`.
  - Footer: "Guide data for \(matched) of \(channelCount) channels. A channel uses the first guide in this list that has it."
- **Live TV, "Channels" section** (after Guides, before the manage section; only with a playlist):
  - `"iptv.groups"` "Groups", value "All Shown" or "\(n) Hidden", disclosure, `.push(.iptvGroups)`.
  - `"iptv.hiddenChannels"` "Hidden Channels", value "None" or "\(n)", disclosure, `.push(.iptvHiddenChannels)`.
  - Footer: "To favorite, hide or match one channel: in the guide, press Left on the programme airing now, then Select."
- **Guide page** (`.guideSource(id)`; title = the source's label, else "Guide"; image `.symbol("list.bullet.rectangle")`):
  - Info row `"guideSource.status"` "Status", detail the source's line.
  - `"guideSource.moveUp"` "Move Up" (not first) → `.moveGuideSource(id:, by: -1)`; `"guideSource.moveDown"` "Move Down" (not last) → `by: 1`.
  - `"guideSource.remove"` "Remove Guide" → `.removeGuideSource(id:)`.
  - Footer: "When two guides have the same channel, the higher one wins."
  - An id no longer in the list shows no sections.
- **Groups page** (`.iptvGroups`; title "Groups"; image `.symbol("folder")`): one row per `iptv.groups` (playlist order): id `"group.\(name)"`, title name, detail "\(n) channels", value "Shown"/"Hidden", `isDimmed` when hidden, action `.toggleIPTVGroupHidden(name)`. Footer: "Hidden groups and their channels don't show in the guide or when changing channels."
- **Hidden Channels page** (`.iptvHiddenChannels`; title "Hidden Channels"; image `.symbol("eye.slash")`): one row per hidden channel in the playlist: id `"hidden.\(id)"`, title "\(number)  \(name)", detail group, value "Show", action `.unhideIPTVChannel(id:)`. None: info row "No hidden channels". Footer: "Select a channel to show it again."
- Hints: the three new pages use "Select: choose · Back: return".

`AppDelegate.iptvSettingsStatus()` builds the new fields:

- Per `library.guideSources`: the line from `guideSourceInfo[id]`:
  - `.loading` → "Loading…"; `.failed(m)` → "Failed: \(m)";
  - `.loaded(d)` → "\(programmes) programmes · \(matched) channels · Updated \(time(d))";
  - `.idle` with `state.guideImports[id]` → the same with the import's abbreviated date and time; `.idle` without → "Not loaded yet".
- `groups` from `ChannelList.groups(of: library.channels)` with counts and `preferences.hiddenGroups`.
- `hiddenChannels` from `library.channels` whose id is in `preferences.hiddenChannels`, playlist order.
- `pasteIPTVURL(.guide)`: after parsing, `if let problem = library.guideAddProblem(url)` → return "That guide is already added" / "Up to 6 guides; remove one first". Else `Task { await library.addGuideURL(url) }`, nil.

### Theme additions

| Token | Value |
|---|---|
| `liveMenuWideWidth` | 1040 |
| `guideFavoriteSymbolSize` | 20 (the star in the channel cell) |

### Views

- **`LiveMenuView`:** width `menu.isWide ? Theme.liveMenuWideWidth : Theme.liveMenuWidth`. Rows: `ForEach(menu.visibleRange, id: \.self)` over `menu.items[i]`. Above the rows, when `hasHiddenAbove`, `Image(systemName: "chevron.up")` centered (`settingsDetailFont`, `secondaryText`); below them the same with `chevron.down` when `hasHiddenBelow`. Reserve both chevron lines' height always, so the panel doesn't jump.
- **`GuideView`:** new `var favoriteIDs: Set<Channel.ID> = []`. In `channelCell`, after the name, `Image(systemName: "star.fill")` at `Theme.guideFavoriteSymbolSize` (`focusedRowSecondaryText` when focused, else `secondaryText`) for favorites. `LiveTVRootView` passes `Set(model.library.preferences.favorites)`.

## Implementation steps

After every step, build with `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build`, and run the tests whenever a step changes them. **Never log or show a full playlist, stream or guide URL**; logs use the host (L2).

- [x] **1. Per-source guide storage and multi-source matching**: `IPTV/EPG/Programme.swift`, `IPTV/EPG/EPGStore.swift`, `IPTV/EPG/EPGMatcher.swift`, `IPTV/EPG/GuideImporter.swift`, `IPTV/IPTVState.swift`, `IPTV/IPTVLibrary.swift`, `MMTVLTests/EPGStoreTests.swift`, `MMTVLTests/EPGMatcherTests.swift`, `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/IPTVSourceStoreTests.swift`
  - `sourceID` and `EPGRef`; migration `v2`; the new store API (delete `replaceAll` and `channels()`).
  - `EPGMatcher`: `rawTokens`/`tokens`, `EPGSourceChannels`, `match(_:sources:overrides:)`, the one-guide wrapper, `""` overrides.
  - `GuideImporter` takes `sourceID`.
  - `IPTVState.guideImports` (drop the two old fields).
  - **Library, still with one guide:** keep M4's `guideSource` logic for now. Its id is `hash(url)`. `refreshGuide()` imports it with that id, records `guideImports[id]`, then `removeSources(keeping: [id])` and `rematch()`. `refreshGuideIfStale()` checks `guideImports[id]`. `epgIDs` becomes `epgMatches: [Channel.ID: EPGRef]`; `programmes(for:in:)` goes through refs.
  - Make `IPTVLibrary.hash` `nonisolated`.
  - Tests:
    - `EPGStoreTests`: update to `replaceSource`. Two sources stay separate: replacing one leaves the other's rows. `removeSources(keeping:)`. `programmes(refs:)` returns only exact pairs (same epg id in two sources, ask for one). `programmeCounts()` per source. `channelsBySource()`.
    - No unit test for the `v1` → `v2` migration: tests can't import GRDB to build a `v1` database. The manual check below covers it.
    - `EPGMatcherTests`: existing tests unchanged (the wrapper). New: override `""` → no match even with a matching `tvg-id`; rule 2 in a lower source beats rule 3 in a higher one; same rule → higher source wins; an override target only in source 2 → source 2; `tokens("NBC Sports Bay Area+ HD") == ["nbc", "sports", "bay", "area", "plus"]`; `tokens("NBA TV TV") == ["nba", "tv"]` while `normalize` is still "nbatvtv".
    - `IPTVLibraryTests`: replace `lastGuideImport`/`lastGuideSourceHash` with `guideImports[IPTVLibrary.hash(url)]`; `epgIDs[x] == "nbatv.us"` → `epgMatches[x]?.epgID == "nbatv.us"`. An `iptv-state.json` with the old keys loads (other fields kept, `guideImports` empty).
    - `IPTVSourceStoreTests` line ~48 builds an `IPTVState` with the old fields: update.
  - Done when:
    - The build and tests pass.
    - **Manual (windowed):** with M4's `guide.sqlite` in place, launch. The `IPTV` log shows the guide imported again (the migration emptied it). The guide shows programmes as before.

- [x] **2. A list of guides**: `IPTV/Sources/IPTVSourceStore.swift`, `IPTV/EPG/GuideSource.swift`, `IPTV/IPTVLibrary.swift`, `MMTVLTests/IPTVSourceStoreTests.swift`, `MMTVLTests/IPTVTestSupport.swift`, `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/GuideSourceTests.swift` (new), `App/AppDelegate.swift`, `Settings/*` (only to keep compiling)
  - `IPTVSourceStore` per L1 (lists, migration, `inMemory(playlist:guides:)`).
  - `GuideSource` per L2.
  - Library: `guideSources`, `guideSourceInfo`, `customGuideURLs`, the queue (L4), `addGuideURL`, `guideAddProblem`, `removeGuideSource`, `moveGuideSource`, `refreshGuide(sourceIDs:)`, `refreshGuideIfStale()` per guide, `rematch()` over all guides, per-guide matched counts. Remove `guideSource`, `GuideSource` enum, `setGuideURL`.
  - **Keep the app compiling** with the smallest changes: `AppDelegate.iptvSettingsStatus()` shows the first guide's host as `.custom`/`.playlist` (old `guideKind`) and `guideStatus`; `.guide` paste calls `addGuideURL`; *Use the Playlist's Guide* removes every pasted guide. Step 3 replaces all of this.
  - Test support: `IPTVFixtures.secondGuideURL = "https://guide.example/second.xml.gz"`; `IPTVFixtures.secondGuide(now:)` with channels `("RedZone.Alt.us", "Red Zone")` and `("NBA.TV.Alt.us", "NBA TV")`, hour-long programmes titled "<name> alt <hour>" over the same 4 hours. `makeLibrary(… guides: [URL] = [] …)` replaces `guide:`; files serve both fixtures.
  - Tests:
    - `IPTVSourceStoreTests` (Keychain, test service): a list round-trips in order; `[]` removes the account; **migration**: with only the legacy account set, `guideURLs() == [legacy]`; after `setGuideURLs([a, b])` the legacy account is gone; `removeAll()` removes all three.
    - `GuideSourceTests`: `…/guide-source_US2.xml.gz` → label "guide-source.online · guide-source_US2.xml.gz", shortLabel "guide-source_US2"; `…/xmltv.php?username=u&password=p` → "host" (no query text anywhere in the label); `https://provider.example/app2/<18 chars>` → host; a 70-character `.xml` name → host.
    - `IPTVLibraryTests`:
      - Two guides `[custom, second]`: Red Zone → second (name), NBA TV → custom (`tvg-id`), NFL Network → custom (name). `guideSourceInfo` has two entries with `matchedChannels` 2 and 1, and `guideImports` has both ids.
      - `moveGuideSource(second, by: -1)`: NBA TV stays on custom (rule 2 beats rule 3, L3); no new download (`downloadCount` unchanged).
      - `removeGuideSource(custom)`: NBA TV and Red Zone now match second, with programmes ("NBA TV alt 1" found via `programmes(for:in:)`), and **no download**. The store has no rows for custom.
      - `refreshGuideIfStale()`: only the stale guide downloads (advance the clock 13 h after importing one, then add another).
      - A failing guide (`setError` on second) → its status `.failed`, the other `.loaded`, `guideStatus` `.loaded`; both failing → `.failed`.
      - **Queue:** start `refreshGuide()` and, before awaiting it, call `refreshGuide(sourceIDs: [second])`; both finish with `downloadCount` as expected and one run (the second call returns at once).
      - `guideAddProblem`: duplicate; full at 6.
      - Playlist `url-tvg` guides are used while no guide is pasted; adding one replaces them; removing it brings them back.
  - Done when the tests pass and the app builds.

- [x] **3. Settings → Live TV → Guides**: `Settings/SettingsTypes.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsEnvironment.swift`, `App/AppDelegate.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsModelTests.swift`
  - The Guides section, the guide page, `pasteMessageKind`, the actions and environment closures for moving/removing guides, the new status fields (groups/hidden ones can stay empty until step 5). Remove `useIPTVPlaylistGuide` everywhere.
  - `AppDelegate`: status lines per *Settings*; paste problems; the closures.
  - Tests (`SettingsModelTests`, replacing the `guideKind` ones):
    - Two pasted guides → rows `iptv.guide.<id>` with values "1" and "2" and their lines, then `iptv.guide.add`. With `matchedChannelCount` 3 and `channelCount` 5 in the fake status, the footer starts "Guide data for 3 of 5 channels.".
    - A playlist guide → an info row with value "From Playlist".
    - At 6 pasted guides there is no add row.
    - A paste error on the guide row shows on that row only.
    - Guide page: first guide has no Move Up; Move Down calls `moveGuideSource(id, 1)`; Remove calls `removeGuideSource(id)` and pops.
  - Done when:
    - The tests pass.
    - **Manual (windowed):** paste US2 (if it migrated, it's already there) and FANDUEL1 (`https://guide-source.online/guide-source/guide-source_FANDUEL1.xml.gz`). Both rows show programmes and channels. The footer count goes up. Move FANDUEL1 up, then remove it; the count returns. Record the before/after counts in *Deviations*.

- [x] **4. Channel preferences and the lineup**: `IPTV/Sources/ChannelPreferences.swift`, `IPTV/IPTVLibrary.swift`, `IPTV/Guide/GuideModel.swift`, `IPTV/LiveTVModel.swift`, `IPTV/LiveTVView.swift`, `App/AppDelegate.swift`, `MMTVLTests/IPTVTestSupport.swift`, `MMTVLTests/ChannelLineupTests.swift` (new), `MMTVLTests/GuideModelTests.swift`, `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - `ChannelPreferences`, `ChannelLineup` (L5, L11).
  - Library: `preferencesFile` init parameter, `preferences`, `lineup`, `updateLineup()`, the favorite/hide methods. `AppDelegate` passes `JSONConfigFile(url: directory.appending(path: ChannelPreferences.fileName), defaultValue: ChannelPreferences())`; `makeLibrary` gains `preferences: ChannelPreferences? = nil`.
  - `GuideModel(lineup:…)`, `setLineup`; `LiveTVModel` builds guides from `library.lineup`, `channelsChanged()` uses it, `zap` per L11. `LiveTVView`: `onChange(of: model.library.lineup)`.
  - Tests:
    - `ChannelLineupTests` (fixture channels): no preferences → M4's groups. Favorites `[nba, nfl]` → groups start with "Favorites" and `channels(in: "Favorites")` is NBA TV, NFL Network. A hidden favorite isn't in Favorites. Hiding "NBA Games" removes the group and its channels from All Channels, and leaves one visible group, so "All Channels" disappears. Favorite ids not in the playlist are ignored. A hidden channel isn't in `visibleChannels`.
    - `ChannelPreferences` decoding: `{"favorites": 3, "hiddenGroups": ["x"]}` → favorites `[]`, hiddenGroups `["x"]`.
    - `IPTVLibraryTests`: `setFavorite`/`moveFavorite`/`setChannelHidden`/`setGroupHidden` save `iptv-channels.json` and update `lineup`; `moveFavorite` past either end does nothing; `removeSource()` keeps preferences.
    - `GuideModelTests`: with favorites, the default group is Favorites; a focused channel outside it opens All Channels; `setLineup` that drops the focused channel keeps the row index (clamped).
    - `LiveTVModelTests`: zapping skips a hidden channel; with remembered group "Favorites", Down from the last favorite wraps to the first; a playing channel that gets hidden zaps to the list's first (Down).
  - Done when the tests pass.

- [x] **5. Settings → Groups and Hidden Channels**: `Settings/*`, `App/AppDelegate.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsModelTests.swift`
  - The Channels section, the two pages, the two actions and closures, `groups`/`hiddenChannels` in the status.
  - Tests: values "All Shown"/"1 Hidden", "None"/"2"; Select on a group calls `setIPTVGroupHidden(name, true)` for a shown group and `false` for a hidden one; Select on a hidden channel calls `unhideIPTVChannel(id)`; the empty Hidden Channels page has only the info row.
  - Done when:
    - The tests pass.
    - **Manual (windowed):** hide "NHL Games" in Settings; the guide's group list no longer has it, and All Channels lacks its channels. Show it again.

- [x] **6. Scrolling menus and the channel menu**: `IPTV/LiveMenu.swift`, `IPTV/LiveMenuView.swift`, `IPTV/LiveTVModel.swift`, `IPTV/Guide/GuideView.swift`, `IPTV/LiveTVView.swift`, `DesignSystem/Theme.swift`, `MMTVLTests/LiveMenuTests.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - `LiveMenu` scrolling and `isWide` (L10); the view.
  - The new actions; `channelMenu(for:focusing:)` per L8 **without** `matchGuide` (step 7 adds it); `perform` for favorites, moves and hide.
  - `GuideView` favorite star; theme tokens.
  - Tests:
    - `LiveMenuTests`: 20 items: init with focus 15 → `firstVisibleIndex` 12 (min(15, 20 − 8)); Down to the end keeps the last row visible; Up from 0 to the top scrolls back; 3 items → `visibleRange` 0..<3, no hidden rows.
    - `LiveTVModelTests` (open the menu: Select (guide), Left, Select):
      - Items `["watch", "addToMultiview", "favorite", "hide"]` outside Favorites.
      - "Add to Favorites" → `library.isFavorite`; the guide's groups now start with "Favorites"; reopening shows "Remove from Favorites".
      - In Favorites with two favorites, on the first: items include `moveDown`, not `moveUp`. Move Down → order swapped, the menu still open with the focus on `moveUp` (the item at the same index after rebuild), and the guide's focused channel is still that channel.
      - Hide Channel → the row is gone from the guide; the guide focuses the next channel; the player still plays.
  - Done when:
    - The tests pass.
    - **Manual (windowed):** favorite three channels; Favorites appears first with stars; reorder them; hide one channel; zap past where it was.

- [x] **7. Match Guide**: `IPTV/EPG/EPGSuggester.swift`, `IPTV/EPG/GuideMatch.swift`, `IPTV/IPTVLibrary.swift`, `IPTV/LiveTVModel.swift`, `MMTVLTests/EPGSuggesterTests.swift` (new), `MMTVLTests/IPTVLibraryTests.swift`, `MMTVLTests/LiveTVModelTests.swift`
  - `EPGSuggester` (L7); `GuideMatch` types; `guideMatchOptions`, `setGuideMatch`, `guideLabel(for:)`.
  - The `matchGuide` item in the channel menu; `.openMatchGuide`, `.matchGuide`; `matchMenu`.
  - Tests:
    - `EPGSuggesterTests` (one source, ids/names like FANDUEL1): "FanDuel Sports Network Indiana" → first is `fanduel.sports.indiana.us` ("FanDuel Sports Indiana"). A guide channel sharing no token is never returned. `limit` is honored. Equal scores order by fewer extra tokens, then source order, then id. `tvgID` "nflnetwork.us" contributes "nflnetwork", not "us".
    - `IPTVLibraryTests`:
      - Fixture guide only: Red Zone has no match. `setGuideMatch(.epg(EPGRef(custom, "nfl.redzone.hd.us2")), for: redZone)` writes `{"Red Zone": "nfl.redzone.hd.us2"}`, re-downloads that guide (`downloadCount` + 1; its programmes weren't kept), and Red Zone gets "NFL RedZone 1".
      - `.none` on NBA TV → `""` in the file; NBA TV has no match despite its `tvg-id`.
      - `.automatic` removes keys for the name and the `tvg-id` (seed `{"nbatv.us": "x", "NBA TV": ""}`) → NBA TV matches by `tvg-id` again, without a download.
      - `guideMatchOptions` for NFL Network: `choice == .automatic`, `current` its ref, the first candidate is it.
    - `LiveTVModelTests`:
      - The channel menu's `matchGuide` value is "custom" for NFL Network (the fixture guide's `shortLabel`: `custom.xml` → "custom") and "None" for Red Zone.
      - Select on it, `await pendingTask` → `menu?.title == "Guide for Red Zone"`, `isWide`, items start `["match.automatic", "match.none", …]`, focus on Automatic (value "Selected").
      - Choosing the NFL RedZone candidate → after `await pendingTask`, `library.epgMatches[redZone]` is set.
  - Done when:
    - The tests pass.
    - **Manual (windowed):** for a FanDuel channel with no guide, Match Guide lists the right FanDuel guide channel in the first few rows; choose it; within ~15 s the guide row shows programmes. Relaunch: still matched. *Automatic* undoes it.

- [x] **8. Kiosk check on the TV**: no files
  - Run *Manual verification* in kiosk mode on the Mac mini and TV. Record results and counts in *Deviations*.

- [x] **9. Docs wrap-up**: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - **CLAUDE.md:**
    - Keychain: guide URLs are account **`iptv-guide-urls`** (a JSON array; M4's `iptv-guide-url` is migrated and removed). Settings shows a guide's host and, when it looks like a guide file, its file name (L2); logs still show the host only.
    - New config file **`iptv-channels.json`**: `favorites` (channel ids, in order), `hiddenChannels`, `hiddenGroups`. Hand edits while MMTVL is quit.
    - `iptv-state.json`: `guideImports` (guide id → last import) replaces `lastGuideImport`/`lastGuideSourceHash`.
    - `epg-overrides.json`: now also written by Live TV's Match Guide (keys are channel names); `""` means no guide.
    - `guide.sqlite`: rows are per guide (`sourceID` = SHA-256 of the guide URL).
  - **Master plan:** M6b → Done once step 8 passes; D23 and D26 match what was built; Q7 updated with the guides the user added and the final coverage.
  - Tick this plan's boxes.
  - Done when the docs match the code.

- [x] **10. Full test run**: no files
  - `xcodebuild … test` passes.
  - Done when every *Manual verification* item is ticked or recorded in *Deviations*.

## Tests

| File | Asserts |
|---|---|
| `MMTVLTests/EPGStoreTests.swift` (changed) | Per-source replace/remove, ref queries, counts, `channelsBySource`. |
| `MMTVLTests/EPGMatcherTests.swift` (changed) | Multi-source rule order and priority; `""` overrides; `tokens`. |
| `MMTVLTests/GuideSourceTests.swift` (new) | Labels never show queries or token-like paths. |
| `MMTVLTests/IPTVSourceStoreTests.swift` (changed) | Guide list, legacy migration, removal. |
| `MMTVLTests/IPTVLibraryTests.swift` (changed) | Several guides: priority, move/remove without download, per-guide staleness and failure, queue, add problems, playlist guides; preferences; manual matches. |
| `MMTVLTests/ChannelLineupTests.swift` (new) | Favorites, hidden channels/groups, groups list, tolerant decoding. |
| `MMTVLTests/GuideModelTests.swift` (changed) | Lineup groups, default Favorites, focus fallback. |
| `MMTVLTests/LiveMenuTests.swift` (changed) | Scrolling window. |
| `MMTVLTests/EPGSuggesterTests.swift` (new) | Ranking, limit, ties, tokens. |
| `MMTVLTests/LiveTVModelTests.swift` (changed) | Channel menu items and actions; Match Guide menu; zapping with the lineup. |
| `MMTVLTests/SettingsModelTests.swift` (changed) | Guides section and page, Channels section, Groups and Hidden Channels pages. |
| `MMTVLTests/IPTVTestSupport.swift`, `SettingsTestSupport.swift` (changed) | Second guide fixture, `guides:`/`preferences:` parameters, new recorder fields. |

Commands (see CLAUDE.md):

```sh
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test -only-testing:'MMTVLTests/IPTVLibraryTests'
```

Tests never touch the network or mpv. Keychain tests use their own service, as in M4.

## Manual verification

In kiosk mode on the Mac mini and TV:

- [x] After the update, the migrated US2 guide is listed under Settings → Live TV → Guides and the guide has programmes again.
- [x] Add FANDUEL1 (and, if wanted, CA2/IN1/MY1/UK1 from *Research*). Each row shows programmes and channels. Record "Guide data for N of M channels" before and after.
- [x] Move a guide up/down; remove one; the counts follow without a long wait (no download).
- [x] Match Guide on a FanDuel channel and on "TVG": the right channel is among the first suggestions. Programmes appear within ~15 s. They survive a relaunch. *Automatic* and *No Guide* work.
- [x] Favorites: add four channels; Favorites is the first group, with stars; Move Up/Down reorder it; zapping in Favorites wraps.
- [x] Hide Channel from the guide; Settings → Hidden Channels shows it; Show brings it back.
- [x] Settings → Groups: hide "NHL Games" and "MLB Games"; they're gone from the guide and from zapping; show them again.
- [x] Multiview's picker guide shows the Favorites group and respects hiding.
- [x] Refresh Now imports every guide; a guide with a bad URL shows "Failed: …" while the others still load.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| The `v2` migration fails on an existing `guide.sqlite` | "Guide database unusable, recreating it" in the log | Already handled: `EPGStore.open` deletes and recreates the cache. Check that it then imports. |
| Suggestions miss the right channel | The right guide channel isn't in Match Guide's 30 rows | Hand-edit `epg-overrides.json` (M4 L17) and record the case in *Deviations*. Text search (out of scope) would be the next step; ask the user. |
| A manual match's re-import is slow | The guide row stays empty for long after choosing | Expected for large guides (about 10 s for US2). If it's ALL_SOURCES1, recommend the smaller per-country files (*Research*). |
| Two guides share an EPG id | A manual match lands on the other guide's channel | L6 accepts it; record the ids. Fix by removing or reordering one guide. |
| The Match Guide menu opens late | A noticeable pause after Select with a large guide | Fine below ~0.5 s. Above that, show the menu at once with only Automatic/No Guide and fill in the candidates when ready; ask first. |
| Hand edits of `epg-overrides.json` lost | Entries gone after a Match Guide choice | Expected while MMTVL runs (L6). Edit with MMTVL quit, as for every config file. |
| A hidden channel still plays at launch | The last channel was hidden | By design (L11): hiding stops nothing. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-10-06 (planner):** the user chose suggestions only for Match Guide (no text search), favorites in the order added with Move Up/Move Down in the channel menu, and hiding groups in Settings only.
- **2026-10-06 (planner):** the playlist's FanDuel channel names couldn't be read (the Keychain prompt for the planner's script went unanswered), so how many FANDUEL1 matches by name is unknown until step 3's manual check.
- **2026-10-06 (step 2, small):** `GuideSource`'s `id`, `label` and `shortLabel` are stored `let`s computed in `init` instead of computed properties. Same values.
- **2026-10-06 (step 6, small):** `GuideMatch.swift` (the `GuideMatchChoice` type) was created in step 6, not step 7, because step 6's `LiveMenuAction.matchGuide` needs it. `channelMenu(for:focusing:)` gained `at index:` (the item's index before the move) so Move Up/Down can fall back to "the item at the same index".
- **2026-10-06 (step 7, fix):** *Automatic* after *No Guide* left the channel without programmes until the next refresh: with `""`, the import doesn't keep that channel's programmes, and L6 only re-imports for a chosen guide channel. `setGuideMatch(.automatic)` now also re-imports the guide of the resulting automatic match when its programmes aren't stored (test `automaticReimportsWhenNoGuideKeptNothing`). The plan's "no download" test for *Automatic* still holds when the programmes are stored (`noGuideAndAutomatic`).
- **2026-10-06 (step 7, small):** `guideMatchOptions` reports `.epg(current)` only when the override's target is the current match (an override that didn't resolve reads as `.automatic`, per "an override that resolved").
- **2026-10-06 (step 7, tests):** with the test fixture, "NFL RedZone" shares no token with "Red Zone" (`redzone` vs `red`, `zone`), so it isn't a suggestion for Red Zone. The LiveTVModel test chooses NFL RedZone from **NFL Network**'s Match Guide menu instead (they share `nfl`); Red Zone's menu is still checked for title, wide panel, first rows and focus. On real data this means a guide name written as one word ("RedZone") won't be suggested for a playlist name written as two ("Red Zone"); the fallback is `epg-overrides.json` (Risks).
- **2026-10-06 (executor, status):** steps 1–7 are ticked on their automated tests (full run: 484 tests pass). Their **manual (windowed)** checks (steps 1, 3, 5, 6, 7) and step 8 (kiosk on the TV) need the user and are not done. Step 9's CLAUDE.md part is done; its master-plan part (M6b → Done, Q7 with the guides added and the final coverage) waits for step 8's counts. Step 10's test run passes; it stays open until *Manual verification* is ticked. Status stays **In progress**.
- **2026-10-10 (user):** every manual check (steps 1, 3, 5, 6, 7 windowed; step 8 kiosk on the TV; *Manual verification*) is done and passed. The "Guide data for N of M channels" counts weren't recorded. Steps 8–10 ticked; status **Done**; plan archived.
