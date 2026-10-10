# M3 — YouTube (TV UI) and launcher PIN

| | |
|---|---|
| Status | Done |
| Depends on | M2b |
| Master plan decisions used | D2, D3, D5, D9, D10, D12, D16, D17, D18, D19, D20 (new), D21 (new) |
| Planned | 2026-10-05 |

## Goal

From the couch, with only the remote:

- The **YouTube** tile opens the real YouTube TV interface (`youtube.com/tv`, "leanback") full screen inside MMTVL. The remote's D-pad, Select, Back and play/pause/fast-forward/rewind drive it like a smart TV app. Sign-in, accounts, kid accounts and YouTube's own **Parent code** work as on a TV, and stay signed in across relaunches.
- **Home** leaves YouTube and pauses the video. The YouTube tile returns to the same place (tvOS semantics, as D18). If YouTube itself exits (its "Exit YouTube?" prompt), MMTVL goes home.
- A phone can cast to it with YouTube's **Link with TV code** (D12).
- An optional 4-digit **launcher PIN** (Keychain, D9) guards **Settings**, **Exit to Desktop**, and any tile set to **Require PIN** (e.g. Browser, Prime Video). It is entered on a **privacy keypad**: Up/Down moves a visible row highlight over `1 2 3 / 4 5 6 / 7 8 9 / 0`, and Left / Select / Right enters the first / middle / last digit of that row. Nothing on screen shows which column was pressed, so someone watching the TV can't read the PIN.
- Settings gains a **PIN** section (Set, Change, Turn Off), a per-tile **Require PIN** toggle, and a **YouTube** section (Reload YouTube; Sign Out & Clear YouTube Data).

## Out of scope

- **Launcher-level YouTube profiles** (separate data stores, profile picker). This is D5's fallback, built only if the step 5 gate shows that Parent code doesn't work in the web view. It is outlined in *Fallback F* but not scheduled.
- YouTube ad blocking, SponsorBlock, DeArrow and similar page patches (VacuumTube has them). Possibly M7, if wanted.
- DIAL discovery, so the phone's YouTube app finds MMTVL on the LAN without a TV code (VacuumTube implements it). Link with TV code covers casting (D12). Possibly M7.
- Text entry beyond YouTube's on-screen keyboard. Phone text entry is **M5**.
- IPTV settings and parental controls (**M4/M6**). They reuse the PIN from this milestone.
- The learn-button bindings editor (**M7**).

## Research & findings

### youtube.com/tv in WKWebView (verified on the dev Mac, 2026-10-05, macOS 27, by a throwaway spike)

The spike was a 100-line AppKit program: a `WKWebView` in a window, `customUserAgent` set, `mediaTypesRequiringUserActionForPlayback = []`, and a non-persistent data store. Results:

- **User agent:** `Mozilla/5.0 (PS4; Leanback Shell) Cobalt/25.lts.40.1035033; compatible` gets the leanback UI. The page title is "YouTube on TV", `window._yttv` exists, and the body class is `WEB_PAGE_TYPE_WELCOME`. This is the UA the actively maintained Electron wrapper **VacuumTube** uses ([source](https://github.com/shy1132/VacuumTube/blob/main/src/index.js), commit `3fa684e`, 2026-09-17). Its comments say: the PS4 UA gives the newest UI; "using the latest [Cobalt] seems to trigger playback issues"; Tizen/Bravia UAs often cap at 720p. A third-party write-up says Cobalt/26 stops playback after about 45 s.
- **Playback:** as a guest, a 4K video played at **3840×2160** and was still playing at **99 s**, so the 45 s cutoff doesn't happen with the Cobalt/25 UA. WebKit reports `MediaSource.isTypeSupported` true for VP9, AV1 and H.264.
- **Key input works from JavaScript.** Leanback acts on synthetic events with no trust check:
  ```js
  for (const t of ['keydown','keyup']) { const e = new Event(t); e.keyCode = 40; document.dispatchEvent(e); }
  ```
  (This is also what VacuumTube's `controller-support.js` does.) Native `NSEvent` key events sent through `window.sendEvent` also worked (Down moved the focus).
- **Key codes verified in the spike:**

  | Key code | Effect |
  |---|---|
  | 37/38/39/40 | Arrows: move focus |
  | 13 | Enter: select |
  | 27 | Escape: back. From a watch page it went back. On the signed-out welcome page it did nothing. |
  | 179 | Media play/pause: toggles |
  | 19 | Pause: pauses |
  | 228 / 227 | Media fast-forward / rewind: pause and enter leanback's scrub mode. Right moves the scrub point, Enter resumes there: 228, 228, 227, Right, Right, Enter jumped 12 s → 33 s. This is how a TV remote behaves. |
  | 415 | Play: **didn't resume**. Not used. |
  | 417 / 412 | No visible effect. Not used. |

- **Exit hook:** a user script injected at document start that replaces `window.close` with `window.webkit.messageHandlers.mmtvl.postMessage('close')` delivered the message when the page called `window.close()`. VacuumTube's `fix-exit.js` shows leanback's EXIT_APP path ends in `window.close()`. **Verified with the user, signed in (2026-10-05):** confirming leanback's "Exit YouTube?" prompt reached the hook. Leanback calls it again on every confirm, so `onExit` must be safe to call repeatedly (going home is idempotent).
- **Sign-in:** "Get started" → Enter opened Google's TV sign-in page (`accounts.google.com/signin/ytlrtec…`, on-screen keyboard) **inside the web view**. Escape returned to `/tv`. VacuumTube disables "direct sign-in" because it is buggy in Electron. Leanback also offers phone sign-in with a code at `yt.be/activate`. **Verified with the user in MMTVL (2026-10-05): phone sign-in works.**
- **Kid accounts and Parent code: verified with the user (2026-10-05).** The test harness used the planned UA and a persistent `WKWebsiteDataStore(forIdentifier:)`. The user signed in, added a kid account and set a Parent code. On the kid profile, switching to the adult account or to guest **required the Parent code**. After quitting and relaunching, they were **still signed in, on the same profile, and the Parent code was still enforced**. Q2 is answered "yes", so D5's primary path holds and Fallback F isn't needed.
- **Parent code:** a 4-digit code set in the YouTube TV app under Settings → Parent code. It is needed to watch signed out, to switch to accounts of people over 13, and to remove accounts. It is opt-in and per device ([Google: Watch YouTube Kids on your TV](https://support.google.com/youtubekids/answer/9618031)). Being per device, it most likely lives in the web view's website data, so clearing YouTube data may remove it.
- **Encrypted-content risk:** VacuumTube sends an older client UA (`Cobalt/19.lts.0-qa`) "so that youtube doesn't automatically assume widevine is supported". It also replaces leanback's `unknown-player-error` popup with an "encryption error" notice. WKWebView has no Widevine. Guest playback was fine. **Checked with the user in MMTVL (2026-10-05):** signed-in and kid playback worked with no errors. If it ever fails, see Risks: the UA can be overridden in `settings.json`.

### WebKit APIs (SDK headers, MacOSX27.0.sdk)

- `WKWebViewConfiguration.mediaTypesRequiringUserActionForPlayback` (macOS 10.12+).
- `WKWebView.isInspectable` (13.3+).
- `WKWebView.pauseAllMediaPlayback(completionHandler:)` (12.0+).
- `WKUIDelegate.webViewDidClose(_:)` and `WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:)` (10.11+).
- `WKWebsiteDataStore.default()` persists cookies and local storage between launches. `WKWebsiteDataStore(forIdentifier:)`, `remove(forIdentifier:)` and `allDataStoreIdentifiers` (macOS 14+) give isolated persistent stores (Fallback F only).
- `removeData(ofTypes:modifiedSince:)` with `WKWebsiteDataStore.allWebsiteDataTypes()` and `.distantPast` clears everything.
- `WKUserContentController.add(_:name:)` **retains** its handler strongly, so use a small delegate object that holds the controller weakly.

### Keychain (verified on the dev Mac with a test binary)

- Generic-password `SecItemAdd`, `SecItemUpdate`, `SecItemCopyMatching` and `SecItemDelete` in the **legacy (file-based) login keychain** work for a non-sandboxed binary with no entitlements: add, update, read and delete all returned 0, and a read after delete returned `errSecItemNotFound` (-25300).
- Adding `kSecUseDataProtectionKeychain: true` fails with **-34018** (`errSecMissingEntitlement`), because it needs a provisioning profile. **Don't use the data-protection keychain.**
- Legacy items are tied to the creating app's code signature. The stable Apple Development signing (D4) keeps access across rebuilds.
- **Verified in step 6:** the test host (`xcodebuild test`) uses the login keychain with no prompt.

### Privacy keypad

User request (2026-10-05): a shoulder-surfing-resistant "privacy keypad" like Google TV's. It works by **ambiguous row/column selection**: the row is chosen on screen and visible, and the column is chosen blind with the remote's Left/Center/Right.

The user sent a photo of Google TV's "Verify your identity" screen. Its layout:

- **Left half:** the title ("Verify your identity") and the account.
- **Right half, top:** a small caps label ("ENTER GOOGLE PIN"), then **4 underline slots**. The slot for the next digit has a brighter, thicker underline.
- **Right half, below:** "Forgot PIN" and "Help" buttons. MMTVL omits them; recovery is Mac-side (L11).
- **Center right:** a **large white circle drawn like the remote's D-pad ring**. It shows the current row's three digits at its left, center and right (`1  2  3`), with small up and down tick marks at its top and bottom.
- **Far right:** a **small keypad column** (`1 2 3` / `4 5 6` / `7 8 9` / `0`). The current row is outlined with a capsule.

The circle tells the user which remote direction enters which digit. Nothing shows which direction was pressed.

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL/YouTube/YouTubeConfig.swift` | new | Start URL, default UA, UA override resolution, navigation host policy (pure). |
| `MMTVL/YouTube/YouTubeKeyMap.swift` | new | `RemoteCommand` → leanback key code, the JS to dispatch it, the exit-hook user script (pure). |
| `MMTVL/YouTube/YouTubeController.swift` | new | Owns the one `WKWebView`; load, send command, pause, reload, clear data, exit/crash/failure handling. `YouTubeHosting` protocol. |
| `MMTVL/YouTube/YouTubeView.swift` | new | SwiftUI host for the web view plus the "Can't reach YouTube" overlay. |
| `MMTVL/App/Keychain.swift` | new | Generic-password helpers (legacy keychain). Reused by M4 for IPTV secrets. |
| `MMTVL/PIN/PINStore.swift` | new | Loads/saves/removes the launcher PIN (Keychain). An in-memory variant for tests. |
| `MMTVL/PIN/PINPad.swift` | new | Pure privacy-keypad state: highlighted row, entered digits. |
| `MMTVL/PIN/PINFlow.swift` | new | Pure flow state machine (verify / enter new / confirm), `PINPurpose`, `PINLockout`. |
| `MMTVL/PIN/PINEntryModel.swift` | new | `@Observable` glue: pad + flow + lockout + messages, driven by `RemoteCommand`s. |
| `MMTVL/PIN/PINEntryView.swift` | new | The PIN screen on the 1920×1080 canvas. |
| `MMTVL/Launcher/LaunchItem.swift` | changed | `requiresPIN: Bool?`, `isExitToDesktop`, `isPINProtected`. |
| `MMTVL/Launcher/LaunchItem+Editing.swift` | changed | `settingRequiresPIN(_:id:)`. |
| `MMTVL/Launcher/AppRouter.swift` | changed | `.youtube` and `.pin(PINPurpose)` screens, PIN gating of tiles, the YouTube host, `LauncherRootView` showing the web view outside the canvas. |
| `MMTVL/Launcher/PlaceholderView.swift` | changed | Doc comment only (YouTube no longer uses it). |
| `MMTVL/App/AppSettings.swift` | changed | `youtubeUserAgent: String?` (hand-edited override). |
| `MMTVL/App/AppDelegate.swift` | changed | Create `YouTubeController` and `PINStore`, wire them into the router and Settings, pause YouTube on wake. |
| `MMTVL/Settings/SettingsTypes.swift` | changed | New actions and page. |
| `MMTVL/Settings/SettingsEnvironment.swift` | changed | `hasPIN`, `startPINFlow`, `reloadYouTube`, `clearYouTubeData`. |
| `MMTVL/Settings/SettingsModel.swift` | changed | `hasPIN` status, new actions. |
| `MMTVL/Settings/SettingsModel+Pages.swift` | changed | PIN and YouTube sections, Require PIN row, clear-data confirmation page. |
| `MMTVL/DesignSystem/Theme.swift` | changed | PIN tokens. |
| `MMTVLTests/…` | new/changed | See *Tests*. |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | changed | Wrap-up. |

`MMTVL/YouTube/` and `MMTVL/PIN/` are new folders. File-system-synchronized groups pick them up, so don't touch `project.pbxproj`. WebKit and Security are system frameworks and need no package. If the linker complains, add `import WebKit` / `import Security` in the files that use them; Swift auto-links system frameworks.

### Local decisions

- **L1. Commands reach leanback as JS key events, not native NSEvents.** Both worked. JS covers keys with no Mac key code (179 play/pause, 228/227 FF/RW), is one code path for keyboard, controller and the later phone remote, and the mapping is a pure, testable table. Every bound command is consumed by the router (returns true), so the native key never also reaches the page. Unbound keys (letters) still reach the web view natively, because it is first responder.
- **L2. Home always leaves YouTube; Back always goes to the page.** Leanback handles Back itself (closing panels, leaving the player, its exit prompt). When leanback exits (`window.close()` → script message, or `webViewDidClose`), MMTVL goes home. ~~On the signed-out welcome page, where leanback ignores Escape, Back also goes home (a body-class check).~~ Dropped in step 4: Back at leanback's top level (the welcome page included) makes leanback exit itself through the `window.close` hook, so no special case is needed (see Deviations).
- **L3. One persistent web view, kept alive while away (D18 semantics).** The page is told it's always visible (`alwaysVisibleScript`, added in step 3; see Deviations), so returning doesn't trigger leanback's resume screens. It is created on the first YouTube open, not at launch, so a launch without YouTube costs nothing. Leaving YouTube calls `pauseAllMediaPlayback`. Returning shows it as it was. System wake goes home (M2 L9) and pauses it. The web view uses `WKWebsiteDataStore.default()`. No other MMTVL web view exists, so "Clear YouTube Data" can clear the whole default store.
- **L4. The web view is laid out outside the 1920×1080 scaled canvas**, at the window's real size. Leanback is responsive (it laid out fine at 1280×720), and `scaleEffect` on an `NSViewRepresentable` would scale the rendered layer, not the page.
- **L5. Top-level navigation is limited** to `youtube.com`, `google.com` and `gstatic.com` hosts and their subdomains, over https (sign-in needs `accounts.google.com`). Subframes are unrestricted, since ads and sign-in use iframes. Popups (`window.open`) are ignored and logged. A remote can't escape into the open web through YouTube.
- **L6. The UA is a constant, overridable by `settings.json` `youtubeUserAgent`** (hand-edited; not in the Settings UI). If YouTube breaks the UA, it can be fixed without a rebuild.
- **L7. The PIN is 4 digits, stored as-is in the Keychain** (service `dev.mmtvl.launcher`, account `launcher-pin`). Hashing a 4-digit PIN adds nothing against an attacker who can read the Keychain. D9 is met.
- **L8. PIN scope** (user choice, 2026-10-05). When a PIN is set it guards: opening **Settings** (Settings tile), the **Exit to Desktop** tile, and tiles with **Require PIN** on. Inside Settings, which was already unlocked, the Exit to Desktop row doesn't ask again, but Change PIN and Turn Off PIN ask for the current PIN. Each guarded entry asks every time; there is no unlocked session.
- **L9. Privacy keypad behavior.**
  - Rows `[1 2 3] [4 5 6] [7 8 9] [0]`. The highlight starts on the top row and stays where it is after each digit. Up/Down clamp at the ends, with no wrap.
  - Left/Select/Right enter column 0/1/2 of the highlighted row. On the `0` row only Select enters 0 (the D-pad circle shows `0` in the center, as on Google TV); Left/Right are ignored there.
  - Back deletes the last digit, and on an empty entry cancels. The fourth digit submits automatically.
  - The only feedback for a digit is one more filled dot. Pressed keys never flash.
  - A mouse click on a digit in the small keypad enters it (someone at the Mac).
  - The layout follows the user's Google TV photo (see *Privacy keypad* research).
- **L10. Lockout:** 5 wrong PINs in a row lock entry for 60 s (in memory; a relaunch resets it). The message shows the remaining seconds. Only the verify stage counts toward it.
- **L11. PIN recovery** is a Mac-side command, documented in CLAUDE.md and not shown on the TV: `security delete-generic-password -s dev.mmtvl.launcher -a launcher-pin`.
- **L12. Debug builds set `webView.isInspectable = true`**, so Safari → Develop can inspect leanback while building. Release builds don't.

### Key types

```swift
// YouTube/YouTubeConfig.swift
nonisolated enum YouTubeConfig {
    static let startURL = URL(string: "https://www.youtube.com/tv")!
    /// Verified 2026-10-05 (see M3 research). Don't move to Cobalt/26: reported to stop playback after ~45 s.
    static let defaultUserAgent = "Mozilla/5.0 (PS4; Leanback Shell) Cobalt/25.lts.40.1035033; compatible"
    /// `settings.json` `youtubeUserAgent` if non-empty (after trimming whitespace), else the default.
    static func userAgent(override: String?) -> String
    /// L5. Subframes: always true. Main frame: https and host is youtube.com/google.com/gstatic.com or a subdomain
    /// (compare lowercased host: `host == d || host.hasSuffix("." + d)`). "about:blank" is allowed.
    static func allowsNavigation(to url: URL, isMainFrame: Bool) -> Bool
}
```

```swift
// YouTube/YouTubeKeyMap.swift
nonisolated enum YouTubeKeyMap {
    /// up 38, down 40, left 37, right 39, select 13, back 27, playPause 179, fastForward 228, rewind 227; home → nil.
    static func keyCode(for command: RemoteCommand) -> Int?
    /// keydown + keyup on `document`, as `new Event(type)` with `keyCode` set (verified to work in leanback).
    /// Must end in an expression evaluateJavaScript can return (`'ok'`; `undefined` makes WebKit report an error).
    static func dispatchScript(keyCode: Int) -> String
    /// JS returning true on the signed-out welcome page, where leanback ignores Back (L2).
    static let isWelcomePageScript = "document.body.classList.contains('WEB_PAGE_TYPE_WELCOME')"
    /// Injected at document start, main frame only: routes window.close() to the "mmtvl" message handler.
    static let exitHookScript = "window.close = function () { window.webkit.messageHandlers.mmtvl.postMessage('close'); };"
    static let messageHandlerName = "mmtvl"
}
```

```swift
// YouTube/YouTubeController.swift
/// What the router needs from YouTube; tests use a fake.
protocol YouTubeHosting: AnyObject {
    /// Creates the web view and loads the start URL on first call; later calls keep the current state.
    func open()
    func send(_ command: RemoteCommand)
    /// Pauses all media (Home, wake). No-op before the first open.
    func pause()
    /// Leanback exited (window.close / webViewDidClose). Set by the app.
    var onExit: (() -> Void)? { get set }
}

@Observable
final class YouTubeController: YouTubeHosting {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }
    private(set) var phase: Phase = .idle
    private(set) var webView: WKWebView?
    @ObservationIgnored var onExit: (() -> Void)?
    @ObservationIgnored private let userAgent: String
    @ObservationIgnored private let delegate: YouTubeWebDelegate   // NSObject; holds `weak var controller`

    init(userAgent: String)
    func open()
    func send(_ command: RemoteCommand)
    func pause()
    /// Loads startURL again (resets the leanback route). No-op before the first open.
    func reload()
    /// Removes all website data from the default store, then reload() if the web view exists.
    func clearData() async
}
```

`YouTubeWebDelegate` (private, same file) is an `NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler`. It forwards to the controller:

- `decidePolicyFor navigationAction` → `YouTubeConfig.allowsNavigation(to:isMainFrame:)` (`navigationAction.targetFrame?.isMainFrame ?? true`). Log and `.cancel` when denied.
- `didFinish` → `phase = .ready`.
- `didFailProvisionalNavigation` / `didFail` → ignore `NSURLErrorCancelled` (-999); otherwise `phase = .failed(error.localizedDescription)`.
- `webViewWebContentProcessDidTerminate` → log and `reload()`.
- `webViewDidClose` and the script message `"close"` → `onExit?()`.
- `createWebViewWith…` → log and return `nil`.

Web view setup in `open()`:

```swift
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .default()
configuration.mediaTypesRequiringUserActionForPlayback = []
configuration.userContentController.addUserScript(WKUserScript(
    source: YouTubeKeyMap.exitHookScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
configuration.userContentController.add(delegate, name: YouTubeKeyMap.messageHandlerName)
let webView = WKWebView(frame: .zero, configuration: configuration)
webView.customUserAgent = userAgent
webView.navigationDelegate = delegate
webView.uiDelegate = delegate
webView.allowsBackForwardNavigationGestures = false
webView.underPageBackgroundColor = .black
#if DEBUG
webView.isInspectable = true
#endif
phase = .loading
webView.load(URLRequest(url: YouTubeConfig.startURL))
```

```swift
// App/Keychain.swift: legacy keychain only (never kSecUseDataProtectionKeychain, which fails with -34018).
nonisolated enum Keychain {
    static let service = "dev.mmtvl.launcher"
    enum KeychainError: Error { case unexpectedStatus(OSStatus) }
    /// nil when missing (errSecItemNotFound). Throws on other errors.
    static func string(account: String, service: String = service) throws -> String?
    /// Update if the item exists, else add.
    static func set(_ value: String, account: String, service: String = service) throws
    /// No error when missing.
    static func remove(account: String, service: String = service) throws
}
```

```swift
// PIN/PINStore.swift: closure struct, matching SettingsEnvironment's style.
struct PINStore {
    var load: () -> String?          // Keychain errors: log, return nil
    var save: (String) throws -> Void
    var remove: () throws -> Void
    static let account = "launcher-pin"
    static let keychain: PINStore    // Keychain.service / account
    /// Tests.
    static func inMemory(_ initial: String? = nil) -> PINStore   // backed by a small final class box
}
```

```swift
// PIN/PINPad.swift
nonisolated struct PINPad: Equatable, Sendable {
    static let length = 4
    static let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9], [0]]
    enum Event: Equatable, Sendable { case changed, submitted(String), cancelled, ignored }
    private(set) var row = 0
    private(set) var digits: [Int] = []
    /// up/down: move the row (clamped; .ignored if unchanged). left/select/right: column 0/1/2 → enter
    /// (on the 0 row, only select enters 0; left/right → .ignored).
    /// back: delete (.changed) or, when empty, .cancelled. Everything else: .ignored.
    mutating func handle(_ command: RemoteCommand) -> PINPad.Event
    /// Mouse (small keypad). Column is clamped to the row's length. Also moves the highlight to `row`.
    mutating func enter(row: Int, column: Int) -> PINPad.Event
    /// After a wrong PIN or between stages: digits = [], row = 0.
    mutating func clear()
}
```
- `enter` appends the digit. At `length` digits it returns `.submitted(digits as a String)` and keeps the digits until `clear()`. While the pad is full, further digit input is `.ignored`.

```swift
// PIN/PINFlow.swift
nonisolated enum PINPurpose: Hashable, Sendable {
    case openSettings, openTile(id: String), exitToDesktop   // verify, then continue
    case setNew, change, turnOff                             // Settings PIN section
}

nonisolated struct PINFlow: Equatable, Sendable {
    enum Stage: Equatable, Sendable { case verify, enterNew, confirmNew(String) }
    enum Outcome: Equatable, Sendable { case next, wrongPIN, mismatch, verified, newPIN(String), removed }
    let purpose: PINPurpose
    private(set) var stage: Stage            // .enterNew for .setNew, else .verify
    init(purpose: PINPurpose)
    mutating func submit(_ code: String, storedPIN: String?) -> Outcome
}
```

`submit` rules:

- **`.verify`:**
  - `storedPIN == nil` → `.verified` (defensive; the router never asks without a PIN).
  - Code matches:
    - `.change` → stage = `.enterNew`, return `.next`.
    - `.turnOff` → `.removed`.
    - Anything else → `.verified`.
  - Code doesn't match → `.wrongPIN`.
- **`.enterNew`:** stage = `.confirmNew(code)`, return `.next`.
- **`.confirmNew(first)`:** code == first → `.newPIN(code)`. Otherwise stage = `.enterNew`, return `.mismatch`.

```swift
nonisolated struct PINLockout: Equatable, Sendable {
    static let maxFailures = 5
    static let duration: TimeInterval = 60
    private(set) var failures = 0
    private(set) var lockedUntil: Date?
    /// Seconds left (rounded up), or nil when not locked. Clears an expired lock.
    mutating func remaining(at now: Date) -> Int?
    /// The 5th failure locks until now + duration and resets failures to 0.
    mutating func recordFailure(at now: Date)
    mutating func recordSuccess()   // failures = 0, lockedUntil = nil
}
```

```swift
// PIN/PINEntryModel.swift
@Observable
final class PINEntryModel {
    enum Result: Equatable { case cancelled, verified, newPIN(String), removed }
    let purpose: PINPurpose
    private(set) var pad = PINPad()
    private(set) var flow: PINFlow
    private(set) var lockout: PINLockout
    /// "Wrong PIN", "The PINs didn't match. Try again.", "Too many tries. Try again in 42 s."
    private(set) var message: String?
    private(set) var shakeTrigger = 0
    @ObservationIgnored private let storedPIN: String?
    @ObservationIgnored private let now: () -> Date

    init(purpose: PINPurpose, storedPIN: String?, lockout: PINLockout, now: @escaping () -> Date = Date.init)
    var title: String
    func handle(_ command: RemoteCommand) -> Result?
    func enter(row: Int, column: Int) -> Result?   // mouse
}
```

`title` by stage:

| Stage | Title |
|---|---|
| `.verify`, purpose `.change` / `.turnOff` | "Enter Current PIN" |
| `.verify`, other purposes | "Enter PIN" |
| `.enterNew` | "Enter a New PIN" |
| `.confirmNew` | "Enter the New PIN Again" |

`handle(_:)` / `enter(row:column:)` logic:

1. **Lockout.** If `flow.stage == .verify` and `lockout.remaining(at: now())` is non-nil, and the input would enter a digit (left/select/right, or a click), set `message` to the lockout text and return nil. Up/Down and Back still work.
2. **Pass to the pad.** `.cancelled` → return `.cancelled`. `.submitted(code)` → `flow.submit(code, storedPIN:)`:
   - `.next` → `pad.clear()`, `message = nil`.
   - `.wrongPIN` → `lockout.recordFailure(at: now())`, `shakeTrigger += 1`, `pad.clear()`. `message` is the lockout text if now locked, else "Wrong PIN".
   - `.mismatch` → `shakeTrigger += 1`, `pad.clear()`, `message` = mismatch text.
   - `.verified` → `lockout.recordSuccess()`, return `.verified`.
   - `.removed` → `lockout.recordSuccess()`, return `.removed`.
   - `.newPIN(code)` → return `.newPIN(code)`.
3. Any other pad event: clear `message` on the first new digit after an error; return nil.

### Router changes (`Launcher/AppRouter.swift`)

```swift
enum Screen: Equatable {
    case home
    case placeholder(LaunchItem)
    case accessibilityOnboarding
    case settings
    case youtube
    case pin(PINPurpose)
}

private(set) var pinEntry: PINEntryModel?
@ObservationIgnored let youtube: any YouTubeHosting
@ObservationIgnored private let pinStore: PINStore
@ObservationIgnored private var pinLockout = PINLockout()
/// Where Back/cancel returns from the PIN screen: .home or .settings.
@ObservationIgnored private var screenBeforePIN: Screen = .home

init(items: [LaunchItem], launcher: AppLauncher, settings: SettingsModel, youtube: any YouTubeHosting, pinStore: PINStore)

var hasPIN: Bool { pinStore.load() != nil }
func requestPIN(_ purpose: PINPurpose)       // records screenBeforePIN, creates pinEntry, screen = .pin(purpose)
func pinEnter(row: Int, column: Int)          // mouse; same result handling as handle()
```

- **`activate(_:)`:**
  - If `hasPIN && item.isPINProtected`, call `requestPIN(...)` and return:
    - `isSettingsTile` → `.openSettings`.
    - `isExitToDesktop` → `.exitToDesktop`.
    - Otherwise → `.openTile(id: item.id)`.
  - Otherwise `open(item)`. This is a new private func holding today's `switch item.kind`. In it, `.internalDestination(.youtube)` → `openYouTube()` (`youtube.open(); screen = .youtube`). `.iptv` still shows the placeholder.
  - `open(item)` re-checks nothing. It is also what a verified `.openTile` calls.
- **`route(_:)`:**
  - **`.youtube`:** `.home` → `goHome()`. Anything else → `youtube.send(command)`. Always return true.
  - **`.pin`:**
    - `.home` → `pinLockout = pinEntry.lockout`, `pinEntry = nil`, `goHome()`.
    - Anything else → `let result = pinEntry?.handle(command)`, `pinLockout = pinEntry.lockout`, then `finishPIN(result)` when non-nil.
    - Always return true.
- **`finishPIN(_:)`:**
  - `.cancelled` → `screen = screenBeforePIN`.
  - `.verified`, by purpose:
    - `.openSettings` → `openSettings()`.
    - `.openTile(id)` → `screen = .home`, then `open(item)` if the id still exists.
    - `.exitToDesktop` → `screen = .home`, `onExitToDesktop?()`.
  - `.newPIN(code)` → `try pinStore.save(code)` (log errors), `screen = .settings`, `settings.refreshStatus()`.
  - `.removed` → `try pinStore.remove()`, `screen = .settings`, `settings.refreshStatus()`.
  - Always set `pinEntry = nil`.
- **`goHome()`:** `if screen == .youtube { youtube.pause() }`. Then `pinEntry = nil` and `screen = .home`.
- **`LauncherRootView`** takes `youtube: YouTubeController` too:
  - When `router.screen == .youtube`, show `YouTubeView(controller: youtube)` full window, outside the canvas (L4).
  - Otherwise show today's scaled canvas.
  - The `.pin` case in `content` shows `PINEntryView(model:onEnter:)` when `router.pinEntry` is non-nil.

### LaunchItem additions

```swift
var requiresPIN: Bool?   // after isHidden; nil/false = no; stored as nil when off
var isExitToDesktop: Bool { kind == .system(.exitToDesktop) }
/// Asks for the PIN when one is set (L8).
var isPINProtected: Bool { isSettingsTile || isExitToDesktop || requiresPIN == true }
```
```swift
// LaunchItem+Editing.swift
func settingRequiresPIN(_ on: Bool, id: String) -> [LaunchItem]   // stores `on ? true : nil`
```

### Settings additions

- **`SettingsAction`:** `.startPIN(PINPurpose)`, `.toggleTileRequiresPIN(id: String)`, `.reloadYouTube`, `.clearYouTubeData`.
- **`SettingsPage`:** `.confirmClearYouTube`.
- **`SettingsEnvironment`:** `hasPIN: () -> Bool`, `startPINFlow: (PINPurpose) -> Void`, `reloadYouTube: () -> Void`, `clearYouTubeData: () -> Void`. The last one is fire-and-forget; the app wraps the async call in a `Task`.
- **`SettingsModel`:** `private(set) var hasPIN: Bool`, set in `init` and in `refreshStatus()`.
  - `perform`: `.startPIN(p)` → `environment.startPINFlow(p)`.
  - `.toggleTileRequiresPIN(id)` → `updateItems(items.settingRequiresPIN(!(item.requiresPIN == true), id: id))`. Ignore it for the Settings and Exit tiles.
  - `.reloadYouTube` → `environment.reloadYouTube()`.
  - `.clearYouTubeData` → `environment.clearYouTubeData(); pop()`.
- **Root page:** new sections between "Home Screen" and "System":
  - **"PIN"**, without a PIN:
    - `pin.set` "Set PIN", detail "Guards Settings, Exit to Desktop and tiles set to Require PIN", action `.startPIN(.setNew)`.
  - **"PIN"**, with a PIN:
    - `pin.change` "Change PIN" → `.startPIN(.change)`.
    - `pin.off` "Turn Off PIN" → `.startPIN(.turnOff)`.
  - **"YouTube":**
    - `youtube.reload` "Reload YouTube" → `.reloadYouTube`.
    - `youtube.clear` "Sign Out & Clear YouTube Data", disclosure → `.push(.confirmClearYouTube)`.
    - Footer: "To keep kids in their own profile, set a Parent code in YouTube → Settings → Parent code."
- **`.confirmClearYouTube` page:**
  - Title "Sign Out of YouTube?", image `.symbol("play.rectangle")`, hint "Select: choose · Back: cancel".
  - Rows `confirm.cancel` "Cancel" (`.pop`, focused first) and `confirm.clearYouTube` "Sign Out & Clear" (`.clearYouTubeData`).
  - Footer: "Signs every account out of YouTube on this Mac and deletes its watch data. YouTube's Parent code may be removed too."
- **Tile page:**
  - For tiles other than Settings and Exit, add `tile.requiresPIN` "Require PIN", value On/Off, action `.toggleTileRequiresPIN(id:)`. Detail is "Set a PIN in Settings first" when `!hasPIN`.
  - The Exit tile's page gets the footer "Exit to Desktop always asks for the PIN when one is set."
  - The Settings tile's footer becomes "Settings is always on the Home screen and asks for the PIN when one is set."

### AppDelegate wiring

- `let youtube = YouTubeController(userAgent: YouTubeConfig.userAgent(override: settings.youtubeUserAgent))`, stored in a property.
- `AppRouter(..., youtube: youtube, pinStore: .keychain)`.
- `LauncherRootView(router: router, youtube: youtube)`.
- `youtube.onExit = { [weak router] in if router?.screen == .youtube { router?.goHome() } }`.
- `makeSettingsEnvironment`:
  - `hasPIN: { PINStore.keychain.load() != nil }`
  - `startPINFlow: { [weak self] in self?.router?.requestPIN($0) }`
  - `reloadYouTube: { [weak youtube] in youtube?.reload() }`
  - `clearYouTubeData: { [weak youtube] in Task { await youtube?.clearData() } }`
- `systemDidWake()` already calls `router?.goHome()`, which now pauses YouTube.

## Implementation steps

Build after every step (`xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build`) and run the tests whenever a step adds or changes tests.

- [x] **1. YouTube config and key map (pure)**: `YouTube/YouTubeConfig.swift`, `YouTube/YouTubeKeyMap.swift`, `App/AppSettings.swift`, `MMTVLTests/YouTubeConfigTests.swift`, `MMTVLTests/YouTubeKeyMapTests.swift`
  - Implement both enums as in *Key types*.
  - Add `var youtubeUserAgent: String?` to `AppSettings` (nil = use the built-in UA). Decode it with `decodeIfPresent` in the existing custom `init(from:)`. The synthesized `encode(to:)` already omits nil optionals, so encoding needs no change.
  - Done when the tests pass:
    - The key map table (all ten commands, with `home` → nil).
    - `dispatchScript` contains `keydown`, `keyup`, the code and ends with `'ok'`.
    - The UA override: nil, "", and "  " → default; a custom string → itself.
    - Navigation: `https://www.youtube.com/tv` yes; `https://accounts.google.com/x` yes; `https://evil.com` no; `http://www.youtube.com` no; `https://notyoutube.com` no; any URL with `isMainFrame: false` yes; `about:blank` yes.
    - `AppSettings` decodes a file without `youtubeUserAgent`, and round-trips one with it.

- [x] **2. YouTube controller and view**: `YouTube/YouTubeController.swift`, `YouTube/YouTubeView.swift`
  - Implement `YouTubeHosting`, `YouTubeController` and its private `YouTubeWebDelegate` as in *Key types*.
  - `send(_:)`:
    - If `phase` is `.failed`, `.select` calls `reload()` and every other command is ignored.
    - Otherwise, if there's a key code, `webView?.evaluateJavaScript(YouTubeKeyMap.dispatchScript(keyCode:))` and log errors at debug level.
    - L2's welcome-page Back rule is added in step 4, not here.
  - `pause()`: `webView?.pauseAllMediaPlayback(completionHandler: nil)`. Use the non-deprecated `pauseAllMediaPlayback(completionHandler:)` (Swift may import it as `async`; use `Task { await webView.pauseAllMediaPlayback() }` if so).
  - `YouTubeView`: a `ZStack` of `Color.black`, then `YouTubeWebView(webView:)` (an `NSViewRepresentable` returning the existing instance from `makeNSView`), then the overlay for `.failed(message)`:
    - "Can't reach YouTube" (`Theme.settingsTitleFont`), the message (`Theme.settingsDetailFont`), and "Select: try again · Home: leave" (`Theme.settingsHintFont`).
    - Center the overlay in the window. It isn't on the scaled canvas, so use font sizes that read well at the window's real size.
    - In `makeNSView`, after returning the view, make it first responder: `DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }`.
    - `.ignoresSafeArea()`.
  - Nothing calls it yet.
  - Done when it builds.

- [x] **3. YouTube screen in the router** *(plus the always-visible script; see Deviations)*: `Launcher/AppRouter.swift`, `App/AppDelegate.swift`, `Launcher/PlaceholderView.swift`, `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/FakeYouTube.swift`
  - Add `Screen.youtube`, the `youtube` init parameter, the `.youtube` routing, the YouTube open from `activate`, the pause in `goHome()`, and the `LauncherRootView` switch (L4). Don't add `pinStore` yet; it arrives in step 9.
  - Wire it in `AppDelegate` as in *AppDelegate wiring*, minus the PIN parts.
  - Update the `PlaceholderView` doc comment to "IPTV → M4".
  - `FakeYouTube`: a test class recording `opens`, `sent: [RemoteCommand]` and `pauses`, plus `onExit`. Update `makeRouter` in `AppRouterTests` to pass it.
  - Done when:
    - New tests pass: the YouTube tile → `screen == .youtube` and `opens == 1`; arrows/select/back/playPause → forwarded and consumed; `.home` → `.home` and `pauses == 1`; opening twice → `opens == 2` (the controller, not the router, keeps state).
    - Windowed run (`open build/Build/Products/Debug/MMTVL.app --args -windowed YES`): the YouTube tile shows leanback. Arrow keys move its focus, Return selects, Escape goes back, and Space toggles play/pause in a video (as a guest is fine). Home (fn+← is global, but global input is off in windowed mode, so test Home in kiosk mode) returns to the tiles, the video pauses, and the YouTube tile returns to the same video.

- [x] **4. Exit, Back on the welcome page, crashes and failures** *(no welcome-page rule needed; the network-down check is in the user's manual list; see Deviations)*: `YouTube/YouTubeController.swift`, `App/AppDelegate.swift`
  - Wire `onExit` as in *AppDelegate wiring*.
  - L2 welcome-page Back: in `send(.back)`, evaluate `YouTubeKeyMap.isWelcomePageScript`. If the result is `true` (Bool), call `onExit?()`; otherwise dispatch key 27. Use the async `evaluateJavaScript`; a JS error counts as "not the welcome page".
  - Confirm `webViewWebContentProcessDidTerminate` reloads, and that `didFailProvisionalNavigation` shows the overlay.
  - Done when:
    - With networking off (Wi-Fi off, Ethernet unplugged), the YouTube tile shows "Can't reach YouTube". Select after reconnecting loads leanback.
    - On the signed-out welcome page, Back goes home.
    - In Safari → Develop → [Mac] → MMTVL's page (Debug build, L12), running `window.close()` in the console goes home.

- [x] **5. GATE: verify YouTube on the user's account (needs the user)**: no code; record the results in *Research & findings* (replace the **Unverified** markers) and in *Deviations & questions*
  - **Pre-checked by the planner with the user (2026-10-05) in a throwaway harness:** items 2–5 and 8 pass (kid account, Parent code enforced, survives relaunch, exit prompt reaches the hook). In MMTVL itself, re-run only items 1, 6 and 7, plus a quick repeat of item 5 (the app uses the default data store, not the harness's).
  - Stop and ask the user to run, in kiosk mode on the Mac (ideally the Mac mini on the TV):
    1. **Sign in** with their Google account. Try both of leanback's ways (on-screen "Sign in" and phone code at `yt.be/activate`) and note which works.
    2. **Add a kid account** (supervised child) from the account selector.
    3. In YouTube → Settings → **Parent code**: set a code.
    4. As the kid profile, try to switch to the adult profile or to "Watch as guest". The Parent code must be required.
    5. Quit MMTVL (⌘Q), relaunch, open YouTube. They should still be signed in, the active profile is remembered, and the Parent code is still enforced.
    6. Play a video signed in, both adult and kid. Watch for "unknown player error" / encryption errors (see Risks).
    7. **Link with TV code**: YouTube → Settings → Link with TV code. On the phone's YouTube app, Cast → Link with TV code. Cast a video and control play/pause from the phone.
    8. **Exit prompt**: on the signed-in home, press Back until leanback asks "Exit YouTube?", then confirm. MMTVL should go home (`window.close` hook). If nothing happens, note it.
  - **If steps 3–5 pass**: Q2 is answered "yes"; D5's primary path holds. Continue with step 6.
  - **If Parent code is missing or not enforced**: stop. Record it, and ask the user whether to build *Fallback F* now (it then becomes its own steps after step 13) or defer it.
  - If step 8 fails (no exit), it is only a convenience: Home always works. Record it and continue.
  - Done when the results are recorded and the user has confirmed the branch.

- [x] **6. Keychain and PIN store**: `App/Keychain.swift`, `PIN/PINStore.swift`, `MMTVLTests/KeychainTests.swift`
  - `Keychain` as in *Key types*:
    - The query is `kSecClass: kSecClassGenericPassword`, `kSecAttrService`, `kSecAttrAccount`.
    - Read with `kSecReturnData: true`, `kSecMatchLimit: kSecMatchLimitOne`.
    - `set` = `SecItemUpdate` and, on `errSecItemNotFound`, `SecItemAdd` with `kSecValueData`.
    - **Never set `kSecUseDataProtectionKeychain`.**
  - `PINStore.keychain` uses `Keychain.service` / `PINStore.account` and logs errors in `load` (category "PIN").
  - Tests use service `dev.mmtvl.launcher.tests` and a UUID account, and remove the item at the end:
    - set → read → update → read → remove → read nil.
    - Removing a missing item doesn't throw.
    - `PINStore.inMemory` round-trips.
  - Done when the tests pass. If the keychain test fails in the test host with an interaction or permission error, see Risks.

- [x] **7. PIN models (pure)**: `PIN/PINPad.swift`, `PIN/PINFlow.swift`, `PIN/PINEntryModel.swift`, `MMTVLTests/PINPadTests.swift`, `MMTVLTests/PINFlowTests.swift`, `MMTVLTests/PINEntryModelTests.swift`
  - Implement as in *Key types*. `PINLockout` lives in `PINFlow.swift`.
  - Done when the tests pass.
  - **`PINPadTests`:**
    - Up at row 0 → `.ignored`; Down ×5 stops at row 3.
    - Left/Select/Right on row 1 enter 4/5/6.
    - On row 3, Select enters 0, and Left/Right → `.ignored` with no digit added.
    - The 4th digit → `.submitted("…")`; a 5th digit → `.ignored`.
    - Back deletes, and on empty → `.cancelled`.
    - `clear()` resets digits and row.
    - `enter(row:column:)` clamps the column and moves the highlight.
  - **`PINFlowTests`:**
    - Verify: right → `.verified`; wrong → `.wrongPIN`; nil stored → `.verified`.
    - `.change`: current → `.next` → new → `.next` → confirm → `.newPIN`.
    - `.setNew` mismatch → `.mismatch` and back to `.enterNew`.
    - `.turnOff`: right → `.removed`.
  - **`PINLockout` tests:**
    - 4 failures → not locked; the 5th → `remaining == 60`.
    - At +59.5 s → 1; at +60 s → nil.
    - `recordSuccess` clears.
  - **`PINEntryModelTests`** (injected `now`):
    - Typing the right PIN → `.verified`.
    - A wrong PIN → message "Wrong PIN", `shakeTrigger` incremented, the pad cleared.
    - 5 wrong → digits are refused with the lockout message; after 60 s (advance `now`) they're accepted.
    - Back on empty → `.cancelled`.
    - The set-new flow → `.newPIN`.
    - The titles per stage.

- [x] **8. PIN screen**: `PIN/PINEntryView.swift`, `DesignSystem/Theme.swift`
  - Layout follows the user's Google TV photo (*Privacy keypad* research).
  - Add Theme tokens:

    | Token | Value |
    |---|---|
    | `pinTitleFont` | `Font.system(size: 56, weight: .semibold)` |
    | `pinLabelFont` | `Font.system(size: 20, weight: .semibold)` (small caps label) |
    | `pinSlotWidth` | 90 |
    | `pinSlotSpacing` | 18 |
    | `pinSlotHeight` | 4 |
    | `pinActiveSlotHeight` | 6 |
    | `pinDialSize` | 340 (circle diameter) |
    | `pinDialDigitFont` | `Font.system(size: 48, weight: .regular)` |
    | `pinDialFill` | `Color.white` |
    | `pinDialText` | `Color.black.opacity(0.6)` |
    | `pinKeypadFont` | `Font.system(size: 30, weight: .semibold)` |
    | `pinKeypadColumnSpacing` | 20 |
    | `pinKeypadRowSpacing` | 24 |
    | `pinColumnSpacing` | 80 (circle ↔ small keypad) |

  - `PINEntryView(model: PINEntryModel, onEnter: (Int, Int) -> Void)` on the canvas, as an `HStack` of two halves:
    - **Left half** (leading-aligned, top padding about 160): a `lock.fill` symbol and `model.title` (`pinTitleFont`). Below it, `model.message` (`Theme.settingsDetailFont`, `Theme.secondaryText`) when set.
    - **Right half, top:**
      - The label "ENTER PIN" (`pinLabelFont`, `Theme.secondaryText`, `.textCase(.uppercase)`, tracking 2).
      - Under it, 4 **underline slots** (`Capsule` bars, `pinSlotWidth` wide):
        - Filled slots (digit entered) are white.
        - The next slot is white at `pinActiveSlotHeight`.
        - The others are `Theme.secondaryText` at `pinSlotHeight`.
        - Never show the digits.
      - Apply the same `keyframeAnimator` shake as `AppTileView` to the slots row, keyed on `model.shakeTrigger`.
    - **Right half, below:** an `HStack(spacing: pinColumnSpacing)` of:
      - **The D-pad circle:** a `Circle` filled `pinDialFill` with a soft white glow (`.shadow(color: .white.opacity(0.35), radius: 40)`), `pinDialSize` square. It shows `PINPad.rows[model.pad.row]`:
        - A 3-digit row shows its digits at left, center and right, each about 28% of the diameter from the center.
        - The `0` row shows `0` in the center only.
        - Small "–" tick marks at the top and bottom (`pinDialText`), hinting Up/Down.
        - Digits in `pinDialDigitFont` and `pinDialText`.
        - The circle never reacts to Left/Select/Right; it only changes when the row changes, with `Theme.focusAnimation`.
      - **The small keypad:** a `VStack(spacing: pinKeypadRowSpacing)` of the 4 rows, each an `HStack(spacing: pinKeypadColumnSpacing)` of digits (`pinKeypadFont`, white). The `0` row is centered.
        - The current row is outlined with `Capsule().strokeBorder(.white, lineWidth: 3)`, padded about 12 × 6 around its digits.
        - Each digit has `.onTapGesture { onEnter(row, column) }` (mouse).
    - **Bottom hint** (`Theme.settingsHintFont`, centered): "Up/Down: row · Left, Select, Right: digit · Back: delete".
    - **No per-key focus or press highlight anywhere** (L9).
  - Wired in step 9.
  - Done when it builds. In step 10, compare the screen with the photo and record any intended differences in Deviations.

- [x] **9. PIN gating in the router**: `Launcher/LaunchItem.swift`, `Launcher/LaunchItem+Editing.swift`, `Launcher/AppRouter.swift`, `App/AppDelegate.swift`, `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/LaunchItemEditingTests.swift`
  - Add the `LaunchItem` and editing additions.
  - Add the router's PIN members, `Screen.pin`, `requestPIN`, `pinEnter`, `finishPIN` and the `activate`/`open` split exactly as in *Router changes*. Show `PINEntryView` for `.pin` in `LauncherRootView`.
  - Pass `pinStore: .keychain` from `AppDelegate`; tests pass `.inMemory(...)`.
  - Done when the tests pass:
    - Editing: `settingRequiresPIN` stores true/nil; `isPINProtected` for Settings, Exit, a flagged tile and a plain tile.
    - **Router, no PIN:** the Settings tile opens Settings directly.
    - **Router, PIN "1357":**
      - The Settings tile → `.pin(.openSettings)`. Entering 1357 → `.settings`. Write a test helper `enterPIN(_ code: String)` that, for each digit, finds its row and column in `PINPad.rows`, issues Up/Down from the current row, then Left/Select/Right (column 0/1/2; `0` is Select on row 3). For 1357: row 0 Left (1), row 0 Right (3), row 1 Select (5), row 2 Left (7).
      - A wrong PIN stays on `.pin`.
      - Back on empty returns `.home`. Home returns `.home`.
      - The Exit tile → after the PIN, `onExitToDesktop` is called once.
      - The YouTube tile with `requiresPIN = true` → after the PIN, `screen == .youtube`.
      - A plain tile without the flag → no PIN.
    - No manual check here: setting a PIN needs the Settings rows from step 10, so the manual PIN checks are there.

- [x] **10. Settings: PIN section and Require PIN** *(tests pass; the manual PIN checks are in the user's list, see Deviations)*: `Settings/SettingsTypes.swift`, `Settings/SettingsEnvironment.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `App/AppDelegate.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Add the PIN parts of *Settings additions*: actions, environment closures, `hasPIN`, root PIN section, the tile `Require PIN` row and footers.
  - Extend `SettingsRecorder` with `var hasPIN = false`, `pinFlows: [PINPurpose]`, `youtubeReloads`, `youtubeClears`, and `makeSettingsModel(hasPIN:)`.
  - After a PIN flow from Settings completes or is cancelled, the router returns to `.settings` with the same page stack. It must not call `openSettings()`, which resets it.
  - Done when:
    - Tests pass:
      - Without a PIN the root shows `pin.set`; with one, `pin.change` and `pin.off`.
      - Select on them records `.setNew` / `.change` / `.turnOff`.
      - The tile page has `tile.requiresPIN` for Plex but not for the Settings or Exit tiles.
      - Toggling it applies items with `requiresPIN == true`, then nil.
      - The detail text depends on `hasPIN`.
    - Manual (windowed):
      - Set PIN → enter it twice → the root shows Change/Turn Off. Leave Settings; the Settings tile now asks for the PIN.
      - A wrong PIN shakes; 5 wrong ones lock for 60 s.
      - Change PIN works.
      - Turn Off PIN → the Settings tile opens directly.
      - Require PIN on Browser → the Browser tile asks first.
      - `security find-generic-password -s dev.mmtvl.launcher -a launcher-pin` shows the item while a PIN is set and errors after Turn Off.

- [x] **11. Settings: YouTube section** *(tests pass; manual check in the user list)*: `Settings/SettingsTypes.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `App/AppDelegate.swift`, `MMTVLTests/SettingsModelTests.swift`
  - Add the YouTube section, the `.confirmClearYouTube` page and its actions, wired to `reloadYouTube` / `clearYouTubeData`.
  - Done when:
    - Tests pass: the root has `youtube.reload` and `youtube.clear`. The confirm page focuses Cancel first. "Sign Out & Clear" records one clear and pops back to the root. Reload records one reload.
    - Manual: after signing in, Sign Out & Clear → YouTube opens at the welcome page, signed out. Reload YouTube from Settings, then open YouTube → it is at its home route.

- [x] **12. Docs wrap-up** : `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - **CLAUDE.md:**
    - Add `youtubeUserAgent` to the `settings.json` keys ("optional; overrides the YouTube TV user agent").
    - Add `requiresPIN` to the per-item `launch-items.json` keys.
    - Add a Keychain note: legacy keychain, service `dev.mmtvl.launcher`; PIN account `launcher-pin`; the recovery command (L11).
    - Add "Debug builds: Safari → Develop inspects the YouTube web view."
    - Add "YouTube website data lives in WebKit's default store for `dev.mmtvl.launcher`" (check the actual folder under `~/Library/WebKit/` or `~/Library/Containers/` after signing in, and write the real path).
  - **Master plan:** set M3 to `Done`. Make sure D20/D21 match what was built. Update Q2 with the gate result.
  - Tick this plan's boxes, and fill in Manual verification results.
  - Done when the docs match the code.

- [x] **13. Full test run and kiosk pass**: no files
  - `xcodebuild … test` passes.
  - Run every *Manual verification* item in kiosk mode.
  - Done when they're all ticked or recorded in Deviations.

## Tests

| File | Asserts |
|---|---|
| `MMTVLTests/YouTubeConfigTests.swift` | UA override resolution; the navigation allow-list (step 1 cases). |
| `MMTVLTests/YouTubeKeyMapTests.swift` | Command → key code table; dispatch script shape. |
| `MMTVLTests/AppSettingsTests.swift` (extend) | `youtubeUserAgent` optional decode/round-trip. |
| `MMTVLTests/FakeYouTube.swift` | Test double for `YouTubeHosting`. |
| `MMTVLTests/AppRouterTests.swift` (extend) | YouTube routing (step 3); PIN gating (step 9). |
| `MMTVLTests/KeychainTests.swift` | Real legacy-keychain round trip under a test service; in-memory PIN store. |
| `MMTVLTests/PINPadTests.swift` | Keypad rules (L9). |
| `MMTVLTests/PINFlowTests.swift` | Flow outcomes per purpose; `PINLockout`. |
| `MMTVLTests/PINEntryModelTests.swift` | Messages, shake, lockout with injected time, titles. |
| `MMTVLTests/LaunchItemEditingTests.swift` (extend) | `settingRequiresPIN`, `isPINProtected`, old JSON without `requiresPIN` decodes. |
| `MMTVLTests/SettingsModelTests.swift` (extend) | PIN section, Require PIN row, YouTube section and confirm page. |

Commands (see CLAUDE.md):
```sh
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test -only-testing:'MMTVLTests/PINPadTests'
```

## Manual verification

Run in kiosk mode unless noted, ideally on the Mac mini and TV:

- [x] YouTube opens from its tile and fills the screen with no window chrome. The D-pad, Select, Back, play/pause, and FF/RW (scrub, then Select to resume) work from the keyboard, a game controller and media keys.
- [x] Home from YouTube → home screen, with the video paused. The YouTube tile → the same video, paused where it was.
- [x] Global Home from another app still works, and the YouTube tile still resumes.
- [x] Sleep/wake while in YouTube → home screen, with the video paused.
- [x] The signed-in session, active profile and Parent code survive ⌘Q and relaunch (step 5 gate).
- [x] Kid profile: switching to an adult account or guest needs the Parent code (step 5 gate).
- [x] Link with TV code: the phone casts and controls playback (step 5 gate).
- [x] Leanback's "Exit YouTube?" → MMTVL home (or recorded as not working).
- [x] Network down → "Can't reach YouTube"; Select retries.
- [x] PIN: set, change and turn off. Settings, Exit to Desktop and Require PIN tiles ask; others don't. Wrong-PIN shake; lockout after 5 tries.
- [x] Privacy keypad from the couch: a watcher sees only the row highlight and dots, never the column.
- [x] Sign Out & Clear YouTube Data signs out. Reload YouTube resets to home.
- [x] A controller works the PIN pad (D-pad, A = select, B = back).
- [x] Text sizes on the PIN screen are readable from the couch. Adjust the Theme tokens if not.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| YouTube stops serving leanback to this UA, or playback stops after ~45 s | Redirect to desktop YouTube, "unsupported browser", or playback halts | Put a new UA in `settings.json` `youtubeUserAgent` (no rebuild). Check VacuumTube's current `src/index.js` for the UA it uses and its notes. Update `YouTubeConfig.defaultUserAgent` and the research note. |
| Signed-in or kid playback fails with an encryption/"unknown player error" (Widevine assumed) | Error popup on some videos only when signed in | Try VacuumTube's split: client UA `Mozilla/5.0 (PS4; Leanback Shell) Cobalt/19.lts.0-qa; compatible` (set through `youtubeUserAgent`). If that fixes it but breaks sign-in or quality, record it and ask. A per-request header split, as VacuumTube does, isn't possible in WKWebView without a proxy. |
| Parent code missing or not enforced in the web view (Q2) | Step 5 gate fails | Stop and ask (step 5). *Fallback F* below. |
| On-screen Google sign-in refused ("browser may not be secure") | Sign-in page error | Use leanback's phone sign-in (`yt.be/activate` code). Record which path works in step 5. |
| `window.close` hook never fires for leanback's exit | Exit prompt does nothing | Acceptable: Home always works. Optionally hook leanback's EXIT_APP signal like VacuumTube's `fix-exit.js` (patching `_yttv…resolveCommand`). That is fragile; only with user approval. |
| JS key events stop working (YouTube adds an `isTrusted` check) | Arrows do nothing in YouTube | Switch `send(_:)` to native events: build `NSEvent.keyEvent(with:…keyCode:)` keyDown/keyUp (kVK codes for the arrows, Return 36, Escape 53) and pass them to `webView.window?.sendEvent(_:)`, which was verified to move leanback focus. Keep JS only for 179/228/227. |
| The web view isn't first responder after returning | Letter keys don't reach leanback search | Call `makeFirstResponder(webView)` again in `YouTubeController.open()` when the web view already exists and has a window. |
| Keychain test fails in the test host (user-interaction or `errSecInteractionNotAllowed`) | KeychainTests red | Mark the real-keychain test `.disabled("needs login keychain")` with a note. Keep the in-memory tests, and verify the real keychain manually in step 10 with `security find-generic-password`. |
| `@Observable` on `YouTubeController` with an `NSObject` delegate causes isolation warnings | Swift 6 errors around delegate callbacks | The delegate class is `@MainActor` (the default); WebKit delegate methods are main-actor in the SDK. If a callback is `nonisolated`, hop with `MainActor.assumeIsolated` as `ControllerInput` does. |
| PIN screen visuals still differ from the user's Google TV photo | User feedback | Adjust only `PINEntryView`/Theme. The pad semantics (L9) stay unless the user asks; then update L9 and the tests. |

### Fallback F: launcher profiles (only if the step 5 gate fails and the user approves)

Outline for a follow-up sub plan section. Don't build it without approval.

- `youtube-profiles.json` (D10): `[{ "id": UUID, "name": String, "isProtected": Bool }]`.
- Each profile gets `WKWebsiteDataStore(forIdentifier: id)` (macOS 14+) and its own `YouTubeController` (one web view per profile, created lazily; only the active one stays loaded).
- Opening YouTube shows a profile picker (the Settings-style list or tiles). Protected profiles ask for the launcher PIN (`PINPurpose.openYouTubeProfile(id)`).
- Settings → YouTube → Profiles: add (name via M5 phone text entry, or presets "Adults"/"Kids" until then), protect/unprotect, remove (`WKWebsiteDataStore.remove(forIdentifier:)`).

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-10-05, step 3 (executor): returning to YouTube doesn't keep the place (L3).** Windowed run, signed out: the YouTube tile shows leanback, Down moves its focus, and Home returns to the tiles with YouTube focused. But each return showed a different leanback screen ("Welcome back" sign-in choices, then a "Try Premium for 1 month" offer) instead of the page left. The Return key-release is not the cause: with "Sign in with your remote" focused, returning did not open sign-in. Likely cause (unconfirmed): removing the web view from the window makes the page hidden, and leanback treats hidden → visible as an app resume. VacuumTube's `pause-on-blur.js` swallows `visibilitychange` events for this reason. Options: (a) inject a document-start script that stops `visibilitychange` / `webkitvisibilitychange` propagation (VacuumTube's approach); (b) keep the web view in the window, behind the opaque launcher canvas, so the page never becomes hidden (costs rendering while away); (c) accept leanback's resume screens. Asked the user.
  - **Resolved (user chose (a), 2026-10-05):** `YouTubeKeyMap.alwaysVisibleScript` (document start, main frame) makes `document.hidden` / `visibilityState` (and the webkit-prefixed ones) always report visible and stops `visibilitychange` events. `YouTubeController.open()` injects it next to the exit hook. Re-tested windowed: leave with Home and return (also after 20 s away) shows the same leanback page with the same focus. Playback is still paused natively on leave (`pauseAllMediaPlayback`).
- **2026-10-05, step 4 (executor): no welcome-page Back rule.** The planned check (`WEB_PAGE_TYPE_WELCOME` → leave) was wrong: leanback's "Get started" panel opens over the welcome page with the same body class, so Back there left YouTube instead of closing the panel. Tracing it showed leanback **itself** calls `window.close()` when Back is pressed on the bare welcome page (the planning spike had no close hook, so it looked as if Back was ignored). `send(_:)` now just dispatches the key for every command; `isWelcomePageScript` was removed. Verified windowed: Get started → Back returns to the welcome page; Back on the welcome page → home (log: "YouTube exited" from the hook). Not checked by the executor: the network-down overlay (turning networking off would cut the session); it is in the manual list.
- **2026-10-05, step 5 (executor): remaining gate items moved to the end.** The gate's deciding items (kid account, Parent code, persistence, exit) already passed with the user before implementation, so the branch question is settled. The remaining items (sign in inside MMTVL, which method works, signed-in and kid playback, Link with TV code, persistence in MMTVL's own store) don't affect steps 6–11. They are done with the user at the end, together with the other manual checks. Step 5 stays unticked until then.
- **2026-10-05, step 6 (executor):** the real-keychain test passes in the test host with no prompt; the "Keychain test fails in the test host" risk did not happen.
- **2026-10-05, steps 8–10 (executor): manual UI checks handed to the user.** While the executor was driving the windowed app with synthesized keys, another app (Terminal) came to the front, so the keys may have gone there. The executor stopped synthesized-key checks. No PIN was stored. The PIN screen visuals (step 8), the Set/Change/Turn Off flows and Require PIN (step 10) are covered by unit tests (router and Settings) and are in the user's manual list. Two extra router tests cover returning to the same Settings page after a PIN flow.
- **2026-10-05 (user):** built from Xcode on `m3-plan`; the YouTube tile opens YouTube's TV interface and it works. The other manual checks are still open.
- **2026-10-05 (user): all manual checks pass.** Phone sign-in (`yt.be/activate`) worked inside MMTVL; the Parent code works in MMTVL's own store; every item in *Manual verification* behaved as expected. Steps 5 and 13 ticked; M3 is Done. 162 tests pass.
- **2026-10-05 (planner):** the step 5 gate was mostly run before implementation, in a throwaway harness (same UA and user script, persistent `WKWebsiteDataStore(forIdentifier:)`): kid account, Parent code, persistence across relaunch and the exit hook all pass. Still open: which sign-in method worked (on-screen or `yt.be/activate`), signed-in and kid playback errors, and Link with TV code.
- **2026-10-05 (planner):** the user's Google TV photo ("Verify your identity", D-pad circle plus small keypad) arrived while the plan was being written. L9, `PINPad`'s `0` row and step 8 follow it. MMTVL leaves out "Forgot PIN" and "Help" (recovery is Mac-side, L11).
