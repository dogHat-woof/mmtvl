# M2 — Input layer

| | |
|---|---|
| Status | Done |
| Depends on | M1 |
| Master plan decisions used | D3, D4, D10, D15, D16, D17, D18 |
| Planned | 2026-10-05 |

## Goal

The launcher works with any remote, keyboard, or game controller, and stays in charge of the TV:

- A **Home** button brings the launcher's home screen to the front from any app (Plex, Brave, Prime Video, the desktop). The app you left keeps running.
- Media keys (play/pause, next, previous) reach the launcher while it is in front.
- A game controller drives the launcher: D-pad/stick, A = select, B = back, Home = Home (even while another app is in front).
- Every button mapping lives in an editable `key-bindings.json`, so a newly bought remote can be supported without code changes.
- On first launch (kiosk mode), a remote-navigable screen asks for the Accessibility permission. Once it is granted, it survives rebuilds because the app is now signed with the personal team.
- Launched apps (Prime Video, the default browser) open full screen, even if they were already running.
- The mouse cursor hides itself when the remote is used.
- Optional launch at login (set in `settings.json`).
- After the Mac wakes from sleep, the launcher's home screen is in front.

## Out of scope

- Settings UI for bindings/settings (hand-edited JSON for now; a "learn button" UI) → **M7**
- Phone remote → **M5**
- Volume control. macOS usually can't set HDMI output volume; the AV receiver's remote handles volume. Volume media keys are passed through untouched.
- Choosing the physical remote (Q1). This milestone ships defaults that suit a keyboard and a game controller, plus the means to remap.
- Player-specific commands (channel up/down, OSD) → **M4**, which can add `RemoteCommand` cases.
- Holding sleep/display assertions during playback → **M4**.

## Research & findings

**Event taps and permissions**
- An **active** event tap (`CGEvent.tapCreate(... options: .defaultTap ...)`) that can consume events requires the **Accessibility** permission. A listen-only tap needs Input Monitoring. An app with Accessibility can also listen, so the Input Monitoring prompt never appears. `tapCreate` returns `nil` when the permission is missing. Source: [Apple forums 122492](https://developer.apple.com/forums/thread/122492), [Apple forums 828052](https://developer.apple.com/forums/thread/828052).
- `AXIsProcessTrusted()` reports the Accessibility grant. `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)` shows the system prompt and adds the app to the list in System Settings. **Swift 6 pitfall:** the imported constant `kAXTrustedCheckOptionPrompt` is a global `var` and fails strict concurrency checking. Use the string literal `"AXTrustedCheckOptionPrompt"`.
- Deep link to the pane: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (works through macOS 15; **unverified on 26**, but harmless if it only opens System Settings).
- Taps get disabled if the callback is slow (`.tapDisabledByTimeout`) or by the system (`.tapDisabledByUserInput`). The callback must re-enable with `CGEvent.tapEnable(tap:enable: true)`. Keep the callback fast: decide consume/pass synchronously and do any real work with `DispatchQueue.main.async`.
- **Secure Event Input** (password fields, Terminal's "Secure Keyboard Entry") hides keystrokes from all event taps. Global Home on a *keyboard* won't work while it is on. Controller Home still works.
- Verified locally (dev Mac, Swift 6): `CGEventType(rawValue: 14)` (NX_SYSDEFINED) is non-nil. `NX_KEYTYPE_PLAY/NEXT/PREVIOUS/FAST/REWIND` = 16/17/18/19/20 (`import IOKit.hidsystem`). The attribute string is `"AXFullScreen"`.
- **Unverified:** whether an event tap created right after the grant (without relaunching) receives events. Usually it works. If not, the fallback is in *Risks*.

**Media keys**
- Media keys arrive as `NSEvent.EventType.systemDefined` (CG type 14) with `subtype == 8` (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`). `data1`: key code = `(data1 & 0xFFFF0000) >> 16`; key state = `(data1 & 0xFF00) >> 8`, where `0xA` = down and `0xB` = up; bit 0 = repeat. Source: [mpv macosx_events.m](https://git.quad4.io/Mirrors/mpv/src/commit/213ad5d6c41f32cf9086fa377cd6d6df1236bb76/osdep/macosx_events.m), [MediaKeyTap](https://github.com/the0neyouseek/MediaKeyTap).
- If not consumed, media keys also go to the system's Now Playing routing (it may start Music). The tap consumes them only while the launcher is frontmost. While Plex is frontmost, they pass through to Plex.

**Game controllers**
- `GCController.shouldMonitorBackgroundEvents` (macOS 11.3+, default `false`) lets the app receive controller input while another app is frontmost ([Apple docs](https://developer.apple.com/documentation/gamecontroller/gccontroller/shouldmonitorbackgroundevents)). It was broken in macOS 15.4.1 and fixed in 15.5 ([Apple forums 782461](https://developer.apple.com/forums/thread/782461)).
- SDL found that enabling it **before the first `GCControllerDidConnect`** can crash with MFi controllers on macOS ([SDL commit](https://skia.googlesource.com/external/github.com/libsdl-org/SDL/+/09086aefaa4e74407d95c7886d3182778118b68f)). Enable it in the connect handler.
- macOS 26 opens the **Game Overlay** on the controller Home button. Opt out per element with `buttonHome.preferredSystemGestureState = .disabled`. This has been flaky in some releases ([Apple forums 743753](https://developer.apple.com/forums/thread/743753)). **Unverified on 26:** if the overlay still appears, users can map Menu (≡) to Home instead (Menu is bound to Home by default too).
- Controller handlers run on `GCController.handlerQueue`, which defaults to the main queue.
- **Unverified:** whether a Siri Remote paired over Bluetooth shows up on macOS as a `GCMicroGamepad`. The plan handles `microGamepad` if it appears. The primary Siri Remote route is Remote Buddy mapping buttons to keys (D3).

**Launch at login**
- `SMAppService.mainApp.register()` / `.unregister()` / `.status` (macOS 13+). `.requiresApproval` is normal; the user approves in System Settings → General → Login Items. `SMAppService.openSystemSettingsLoginItems()` opens that pane ([Apple docs](https://developer.apple.com/documentation/servicemanagement/smappservice)). The login item points at the app's current path, so install MMTVL in `/Applications` on the Mac mini before enabling it. Dev Mac status today: `3` (`.notFound`).

**Signing (verified on the dev Mac)**
- The only identity is `Apple Development: Derek Wolcott (93R37R2L88)`, team **H846CY8RB4**. It is the user's own individual team and its use was approved on 2026-10-05.
- A build with `DEVELOPMENT_TEAM=H846CY8RB4 CODE_SIGN_IDENTITY="Apple Development" CODE_SIGN_STYLE=Automatic` succeeded **without a provisioning profile**, and all 21 tests passed.
- The designated requirement is `identifier "dev.mmtvl.launcher" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: Derek Wolcott (93R37R2L88)" ...`. It depends on the bundle ID and the certificate name, not a hash, so TCC grants survive rebuilds and yearly certificate renewal.

**Accessibility full screen (D15)**
- Read or set `"AXFullScreen"` (a CFBoolean) on another app's window with `AXUIElementCopyAttributeValue` / `AXUIElementSetAttributeValue`. This needs Accessibility and no sandbox (we have neither restriction).
- Get the window from `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute`, else `kAXMainWindowAttribute`, else the first `kAXWindowsAttribute` element whose `kAXSubroleAttribute` is `kAXStandardWindowSubrole`.
- **Swift 6 pitfall:** `kCFBooleanTrue` is a global `var`. Use `true as CFBoolean`. The `kAX…Attribute` constants are fine.

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL.xcodeproj/project.pbxproj` | changed | Signing: team H846CY8RB4, `Apple Development`, for the app and test targets (Debug + Release). |
| `MMTVL/App/JSONConfigFile.swift` | new | Generic load/save of one JSON config file with defaults and `.bak` on corruption. |
| `MMTVL/App/AppSettings.swift` | new | `settings.json` model with per-key defaults. |
| `MMTVL/App/AppDelegate.swift` | changed | Wires settings, bindings, event tap, controllers, onboarding, login item, wake handling. |
| `MMTVL/App/KioskWindowController.swift` | changed | Hides the cursor on `show()` when enabled. |
| `MMTVL/App/LoginItem.swift` | new | Applies `launchAtLogin` via `SMAppService.mainApp`. |
| `MMTVL/Launcher/LaunchItemStore.swift` | changed | Re-implemented on `JSONConfigFile` (same API, same tests). |
| `MMTVL/Input/RemoteCommand.swift` | changed | `String`-backed and `Codable`. New cases `fastForward` and `rewind`. |
| `MMTVL/Input/InputBinding.swift` | new | `InputBinding`, `Trigger`, `KeyModifier`, `MediaKey`, `ControllerButton`. |
| `MMTVL/Input/KeyBindings.swift` | changed | From a static enum to a struct holding `[InputBinding]`; default table; lookups. |
| `MMTVL/Input/MediaKeyEvent.swift` | new | Pure parser for system-defined media key events. |
| `MMTVL/Input/InputRouter.swift` | changed | Single `dispatch(_:isGlobal:)` entry point for all sources; local monitor also handles media keys; logs unbound keys. |
| `MMTVL/Input/AccessibilityPermission.swift` | new | Trust check, prompt, open the Settings pane, wait-until-trusted. |
| `MMTVL/Input/GlobalEventTap.swift` | new | The CGEventTap: global bindings always, media keys while the launcher is active. |
| `MMTVL/Input/ControllerInput.swift` | new | GameController: button and stick mapping, D-pad repeat, background monitoring. |
| `MMTVL/Input/ThumbstickDirection.swift` | new | Pure stick → direction with hysteresis. |
| `MMTVL/Launcher/LaunchItem.swift` | changed | Optional `launchFullScreen`; computed `wantsFullScreen`; Prime Video default set to full screen. |
| `MMTVL/Launcher/WindowFullScreener.swift` | new | Puts another app's main window into full screen through AX. |
| `MMTVL/Launcher/AppLauncher.swift` | changed | Calls `WindowFullScreener` after launching items that want full screen. |
| `MMTVL/Launcher/AppRouter.swift` | changed | New `.accessibilityOnboarding` screen, `goHome()`, new commands, hover guard. |
| `MMTVL/Launcher/AccessibilityOnboardingView.swift` | new | The permission screen. |
| `MMTVL/Launcher/LauncherFocusModel.swift` | changed | Handles new `RemoteCommand` cases (no movement). |
| `MMTVLTests/…` | new/changed | See *Tests*. |

### Key types

```swift
// App/JSONConfigFile.swift
nonisolated struct JSONConfigFile<Value: Codable & Sendable>: Sendable {
    let url: URL
    let defaultValue: Value
    /// Missing → writes and returns defaultValue. Corrupt → moves the file to "<name>.bak",
    /// writes and returns defaultValue. Creates the directory if needed.
    func load() -> Value
    /// Pretty-printed, sorted keys, atomic write. Creates the directory if needed.
    func save(_ value: Value) throws
}
```
Pitfall: generic types can't have `static let` stored properties, so the `Logger` must be a file-scope `private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Config")`.

```swift
// App/AppSettings.swift: every key optional in the file; missing keys fall back to defaults.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    var globalInputEnabled = true   // event tap (global Home, media keys). Ignored in -windowed mode.
    var controllersEnabled = true
    var cursorAutoHide = true
    var launchAtLogin = false       // kiosk mode only
    init() {}
    init(from decoder: Decoder) throws  // decodeIfPresent(...) ?? default for each key
    static let fileName = "settings.json"
}
```

```swift
// Input/RemoteCommand.swift
nonisolated enum RemoteCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case up, down, left, right, select, back, home, playPause, fastForward, rewind
}
```

```swift
// Input/InputBinding.swift
nonisolated enum KeyModifier: String, Codable, Hashable, Sendable, CaseIterable {
    case command, option, control, shift
    /// Only these four count. .function, .numericPad and .capsLock are ignored (arrow keys carry .function/.numericPad).
    static func set(from flags: NSEvent.ModifierFlags) -> Set<KeyModifier>
    static func set(from flags: CGEventFlags) -> Set<KeyModifier>   // .maskCommand/.maskAlternate/.maskControl/.maskShift
}
nonisolated enum MediaKey: String, Codable, Hashable, Sendable { case playPause, next, previous, fastForward, rewind }
nonisolated enum ControllerButton: String, Codable, Hashable, Sendable {
    case dpadUp, dpadDown, dpadLeft, dpadRight   // left thumbstick feeds these too
    case a, b, x, y, leftShoulder, rightShoulder, menu, options, home
}
nonisolated struct InputBinding: Codable, Hashable, Sendable {
    enum Trigger: Codable, Hashable, Sendable {
        case key(keyCode: UInt16, modifiers: [KeyModifier])   // array for stable JSON; matched as a Set
        case media(key: MediaKey)
        case controller(button: ControllerButton)
    }
    var trigger: Trigger
    var command: RemoteCommand
    var isGlobal = false   // also acts while another app is frontmost (key: needs Accessibility; controller: background monitoring)
    var label: String?     // free text for humans editing the JSON
    // init(from:) uses decodeIfPresent for isGlobal and label.
}
```
Resulting JSON for one binding (the user edits this file by hand):
```json
{ "command" : "home", "isGlobal" : true, "label" : "Home key (fn+←)",
  "trigger" : { "key" : { "keyCode" : 115, "modifiers" : [ ] } } }
```

```swift
// Input/KeyBindings.swift
nonisolated struct KeyBindings: Equatable, Sendable {
    var bindings: [InputBinding]
    init(_ bindings: [InputBinding])
    static let defaultBindings: [InputBinding]       // table below
    static let defaults: KeyBindings
    static let fileName = "key-bindings.json"        // file content = [InputBinding]
    /// Exact modifier match: Set(binding.modifiers) == KeyModifier.set(from: modifiers). First match wins.
    func binding(keyCode: UInt16, modifiers: Set<KeyModifier>) -> InputBinding?
    func binding(media: MediaKey) -> InputBinding?
    func binding(controller: ControllerButton) -> InputBinding?
    /// Convenience kept for tests and the local monitor.
    func command(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> RemoteCommand?
}
```
Exact modifier matching generalizes M1's L4: no default binding has ⌘, so ⌘-combos never match and always pass through.

Default bindings (`kVK_*` from `Carbon.HIToolbox`):

| Trigger | Command | Global |
|---|---|---|
| key ←/→/↓/↑ (123/124/125/126) | left/right/down/up | |
| key Return (36), Keypad Enter (76) | select | |
| key Escape (53), Delete (51) | back | |
| key Space (49) | playPause | |
| key Home (115) = fn+← on Mac keyboards | home | ✓ |
| media playPause / next / previous / fastForward / rewind | playPause / fastForward / rewind / fastForward / rewind | |
| controller dpadUp/Down/Left/Right | up/down/left/right | |
| controller a / b / x | select / back / playPause | |
| controller leftShoulder / rightShoulder | rewind / fastForward | |
| controller home, menu | home | ✓ |

```swift
// Input/MediaKeyEvent.swift
nonisolated enum MediaKeyEvent {
    struct Parsed: Equatable, Sendable { var key: MediaKey; var isKeyDown: Bool; var isRepeat: Bool }
    /// nil unless subtype == 8 and the key code is PLAY(16)/NEXT(17)/PREVIOUS(18)/FAST(19)/REWIND(20).
    /// Volume/mute/brightness return nil, so they pass through.
    static func parse(subtype: Int16, data1: Int) -> Parsed?
}
```

```swift
// Input/InputRouter.swift (changed)
@Observable final class InputRouter {
    @ObservationIgnored var handler: ((RemoteCommand) -> Bool)?          // active screen (AppRouter.handle)
    @ObservationIgnored var onGlobalCommand: ((RemoteCommand) -> Void)?   // global binding fired while another app is front
    @ObservationIgnored var onCommandDispatched: (() -> Void)?            // cursor auto-hide hook
    @ObservationIgnored var bindings: KeyBindings
    init(bindings: KeyBindings)
    func start()   // local monitor for [.keyDown, .systemDefined]
    func stop()
    /// The single entry point for every input source. Returns true if consumed.
    /// - App active: onCommandDispatched?(); return handler?(command) ?? false
    /// - App inactive and isGlobal: onGlobalCommand?(command); return true
    /// - Otherwise: return false
    @discardableResult func dispatch(_ command: RemoteCommand, isGlobal: Bool) -> Bool
}
```
Local monitor:
- `.keyDown`: look up the binding and call `dispatch(binding.command, isGlobal: binding.isGlobal)`. If consumed, swallow the event. With no binding, log `"Unbound key \(keyCode) modifiers \(…)"` at `.info`. This is how the user discovers a new remote's key codes. Only the local monitor logs keys (L6).
- `.systemDefined`: run `MediaKeyEvent.parse(subtype: event.subtype.rawValue, data1: event.data1)`. On key-down with a binding, dispatch and swallow. Swallow the matching key-up too.

```swift
// Input/GlobalEventTap.swift
final class GlobalEventTap {
    init(inputRouter: InputRouter)
    var isRunning: Bool { get }
    @discardableResult func start() -> Bool   // false if tapCreate returns nil (not trusted)
    func stop()
    func ensureEnabled()                       // re-enable after wake if the system disabled it
}
```
- Tap: `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`. Mask: `(1 << CGEventType.keyDown.rawValue) | (1 << 14)`. Add the run-loop source to `CFRunLoopGetMain()` in `.commonModes`.
- The callback is a **file-scope `nonisolated` function** (C function pointers can't capture or be actor-isolated). It turns `userInfo` back into the tap object with `Unmanaged<GlobalEventTap>.fromOpaque(...).takeUnretainedValue()`.
- In that nonisolated callback, extract **Sendable** data into a small `nonisolated enum TapEvent { case key(code: UInt16, flags: UInt64, isRepeat: Bool), media(subtype: Int16, data1: Int), disabled, other }`:
  - Key code: `event.getIntegerValueField(.keyboardEventKeycode)`.
  - Repeat: `.keyboardEventAutorepeat`.
  - Media: `NSEvent(cgEvent:)` → `subtype` and `data1`.
- Then call `MainActor.assumeIsolated { tapObject.decide(tapEvent) }` (the callback runs on the main run loop), which returns `Bool` = consume. The callback returns `nil` to consume, else `Unmanaged.passUnretained(event)`.
- Swift 6 note: don't capture `CGEvent` or `NSEvent` inside `assumeIsolated`. They aren't Sendable; this was the M1 build error.
- `decide` rules:
  - `.disabled` → `CGEvent.tapEnable(tap: port, enable: true)`; return false.
  - `.key`: if `bindings.binding(keyCode:modifiers:)` is non-nil **and** `isGlobal`:
    - Not a repeat → `DispatchQueue.main.async { inputRouter.dispatch(cmd, isGlobal: true) }`.
    - Return true (autorepeats are consumed too, without dispatching).
    - Non-global keys → return false; the local monitor handles them when we're active.
  - `.media`: parse it. If `NSApp.isActive` and a binding exists:
    - On key-down (not a repeat), dispatch async.
    - Return true for both down and up.
    - Otherwise return false, so Plex and other apps get media keys.
  - Never log key codes in the tap (L6).

```swift
// Input/AccessibilityPermission.swift
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    /// Shows the system prompt (adds MMTVL to the Accessibility list) and opens the Privacy pane.
    static func request()
    /// Polls once a second until trusted or cancelled.
    static func waitUntilTrusted() async
}
```

```swift
// Input/ThumbstickDirection.swift
nonisolated enum ThumbstickDirection {
    static let pressThreshold: Float = 0.6
    static let releaseThreshold: Float = 0.3
    /// Direction held after this sample. Keeps `current` while its axis magnitude is ≥ releaseThreshold
    /// (in the same sign). Otherwise picks the dominant axis if its magnitude is ≥ pressThreshold.
    /// y > 0 = up, x > 0 = right.
    static func resolve(x: Float, y: Float, current: RemoteCommand?) -> RemoteCommand?
}
```

```swift
// Input/ControllerInput.swift
final class ControllerInput {
    init(inputRouter: InputRouter, monitorInBackground: Bool)
    func start()   // configure GCController.controllers(); observe .GCControllerDidConnect / .GCControllerDidDisconnect
    func stop()
}
```
- `configure(_ controller: GCController)` handles `extendedGamepad` first, else `microGamepad`:
  - Set `pressedChangedHandler` on: `dpad.up/down/left/right`, `buttonA`, `buttonB`, `buttonX`, `buttonY`, `leftShoulder`, `rightShoulder`, `buttonMenu`, and the optional `buttonOptions` and `buttonHome`.
  - Set `leftThumbstick.valueChangedHandler`, routed through `ThumbstickDirection` into the same path as the D-pad.
  - Set `buttonHome?.preferredSystemGestureState = .disabled`.
  - For `microGamepad`: `reportsAbsoluteDpadValues = false`; map `buttonA` → `.a`, `buttonX` → `.x`, `buttonMenu` → `.menu`, plus the D-pad.
- Handler closures only capture `[weak self]` plus Sendable values (`Bool`, `Float`), then call `MainActor.assumeIsolated { … }`.
- `buttonChanged(_ button: ControllerButton, pressed: Bool)`:
  - On press: look up the binding → `inputRouter.dispatch(command, isGlobal: binding.isGlobal)`.
  - If the command is a direction, start the repeat task: wait 450 ms, then dispatch every 120 ms until release. Use a `Task` stored in `repeatTask`; cancel it on release, disconnect, or a new press.
- Background monitoring (L4): in the **connect** handler (never before), if `monitorInBackground`, set `GCController.shouldMonitorBackgroundEvents = true`. In the background, `dispatch` ignores non-global commands, so only Home acts.

```swift
// Launcher/WindowFullScreener.swift
final class WindowFullScreener {
    /// Polls every 300 ms until the app's main window reports AXFullScreen == true, or the timeout passes.
    /// No-op if not trusted. Uses AXUIElementSetMessagingTimeout(app, 1.0).
    func makeFullScreen(pid: pid_t, timeout: Duration = .seconds(15)) async
}
```
Loop body:
1. Find the window (see Research).
2. Read `"AXFullScreen"`. If true, return.
3. Otherwise set it with `true as CFBoolean`, then sleep 300 ms.
4. On timeout, log and give up.

```swift
// Launcher/LaunchItem.swift (additions)
var launchFullScreen: Bool?   // Optional → decodes from older files
var wantsFullScreen: Bool {    // computed
    if case .defaultBrowser(let fullScreen) = kind { return launchFullScreen ?? fullScreen }
    return launchFullScreen ?? false
}
```
The `prime` default gets `launchFullScreen: true`. `plex` stays `nil`: Plex HTPC manages its own full screen, so verify on the mini before forcing it. Existing installs keep their old `launch-items.json`; delete it to pick up the new defaults.

```swift
// Launcher/AppRouter.swift (changes)
enum Screen: Equatable { case home, placeholder(LaunchItem), accessibilityOnboarding }
var onRequestAccessibility: (() -> Void)?   // @ObservationIgnored
func goHome()                                // screen = .home; keeps focus position
func showAccessibilityOnboarding()
```
- `handle` on `.accessibilityOnboarding`:
  - `.select` → `onRequestAccessibility?()`; return true.
  - `.back`/`.home` → `goHome()`; return true.
  - Everything else → false.
- The new commands (`fastForward`, `rewind`) return false on every screen.
- **Hover guard (L8):** store `NSEvent.mouseLocation` in `pointerLocationAtLastCommand` whenever `handle` consumes a command. `hover(_:)` returns early while `NSEvent.mouseLocation == pointerLocationAtLastCommand`. This stops a hidden, stationary cursor from stealing focus when the screen re-lays out (e.g. returning from the placeholder).

### Wiring (AppDelegate, final shape)

```swift
func applicationDidFinishLaunching(_:) {
    guard !AppEnvironment.isRunningTests else { return }
    let dir = LaunchItemStore.defaultDirectory
    settings = JSONConfigFile(url: dir.appending(path: AppSettings.fileName), defaultValue: AppSettings()).load()
    let bindings = KeyBindings(JSONConfigFile(url: dir.appending(path: KeyBindings.fileName),
                                              defaultValue: KeyBindings.defaultBindings).load())
    inputRouter = InputRouter(bindings: bindings)
    let kiosk = !AppEnvironment.windowedMode
    // router, launcher, windowController as in M1 (windowController gets hidesCursor: settings.cursorAutoHide)
    inputRouter.handler = router.handle
    inputRouter.onGlobalCommand = { [weak self] command in self?.handleGlobal(command) }
    inputRouter.onCommandDispatched = { if settings.cursorAutoHide { NSCursor.setHiddenUntilMouseMoves(true) } }
    inputRouter.start()
    if kiosk && settings.globalInputEnabled { startGlobalInput() }    // tap now, or onboarding + wait
    if settings.controllersEnabled { controllers = ControllerInput(inputRouter:, monitorInBackground: kiosk); controllers.start() }
    if kiosk { LoginItem.apply(enabled: settings.launchAtLogin); observeWake() }
    windowController.show()
}

func handleGlobal(_ command: RemoteCommand) {      // another app is frontmost
    guard command == .home else { return }        // only Home is global by default; ignore others for now
    router.goHome(); windowController.show()       // D18: the other app keeps running
}

func startGlobalInput() {
    if eventTap.start() { return }
    router.showAccessibilityOnboarding()
    router.onRequestAccessibility = { AccessibilityPermission.request() }
    Task {
        await AccessibilityPermission.waitUntilTrusted()
        eventTap.start()
        if router.screen == .accessibilityOnboarding { router.goHome() }
        windowController.show()   // come back from System Settings
    }
}
```
- `observeWake()`: on `NSWorkspace.didWakeNotification` (on `NSWorkspace.shared.notificationCenter`), after a 2 s delay (HDMI/AVR re-handshake): `router.goHome()`, `windowController.show()`, `eventTap.ensureEnabled()`.
- Only system wake does this, not display-only wake (`screensDidWake`). Otherwise a paused Plex whose display slept would be yanked away (L9).

### Local decisions

- **L1:** Bindings and settings are hand-edited JSON in `~/Library/Application Support/MMTVL/` (D10/D16), read at launch. Edit, then ⌘Q and relaunch. A Settings UI comes in M7.
- **L2:** Global input (event tap, onboarding, background controller input, login item, wake handling) is **off in `-windowed` mode**. Otherwise the dev Mac would lose its Home key (fn+←) in every app. `settings.json` → `globalInputEnabled: false` also disables it in kiosk mode.
- **L3:** Global Home leaves the external app running and only brings the launcher home screen forward (D18, user choice 2026-10-05).
- **L4:** Only bindings marked `isGlobal` act while another app is frontmost, for keys and controllers alike. Everything else passes through to that app.
- **L5:** Media keys are consumed only while the launcher is frontmost. Volume, mute and brightness are never touched.
- **L6:** Key codes are logged only by the local monitor, i.e. when MMTVL is frontmost. The global tap never logs keys, so passwords typed in other apps can't end up in the unified log.
- **L7:** The Accessibility onboarding appears at launch in kiosk mode when not trusted. "Not now" (Back) dismisses it until the next launch. Granting it later still activates the tap automatically, because the wait task keeps polling.
- **L8:** Hover only moves focus after the pointer has actually moved since the last remote command.
- **L9:** System wake → launcher home screen (user choice 2026-10-05). Display-only wake does nothing beyond the existing screen-change re-fit.
- **L10:** `launchAtLogin` defaults to `false` (user choice 2026-10-05). Enable it on the Mac mini in `settings.json`. `.requiresApproval` is logged; the user approves once in Login Items.
- **L11:** No new `RemoteCommand`s beyond `fastForward`/`rewind`. M4 adds player-specific ones.

## Implementation steps

- [x] **1. Personal-team signing**: `MMTVL.xcodeproj/project.pbxproj`
  - In all four target build configurations (app Debug/Release, tests Debug/Release), set `CODE_SIGN_IDENTITY = "Apple Development";` (replacing `"-"`) and add `DEVELOPMENT_TEAM = H846CY8RB4;`. Keep `CODE_SIGN_STYLE = Automatic`.
  - Clear the stale ad-hoc TCC entry: `tccutil reset Accessibility dev.mmtvl.launcher` (harmless if none exists).
  - Done when: the build succeeds, `codesign -dv build/Build/Products/Debug/MMTVL.app 2>&1 | grep TeamIdentifier` prints `H846CY8RB4`, and all tests pass. If xcodebuild asks for a provisioning profile, add `-allowProvisioningUpdates` to the commands in CLAUDE.md and note it under Deviations. (The planner's scratch build didn't need it.)

- [x] **2. JSON config + settings**: `App/JSONConfigFile.swift`, `App/AppSettings.swift`, `Launcher/LaunchItemStore.swift`, `MMTVLTests/JSONConfigFileTests.swift`, `MMTVLTests/AppSettingsTests.swift`
  - Implement `JSONConfigFile` (see Key types). Move the logic out of `LaunchItemStore`: it keeps `fileName`, `defaultDirectory`, `directory`, `fileURL`, `load()`, `save(_:)`, but delegates to `JSONConfigFile<[LaunchItem]>`.
  - Implement `AppSettings` with a custom `init(from:)` using `decodeIfPresent` for every key.
  - Tests: JSONConfigFile with missing / round-trip / corrupt → `.bak` (on a small `Codable` test struct). AppSettings: `{}` decodes to defaults; `{"launchAtLogin": true}` keeps the other defaults.
  - Done when: all tests pass, including the unchanged `LaunchItemStoreTests`.

- [x] **3. RemoteCommand Codable + new cases**: `Input/RemoteCommand.swift`, `Launcher/AppRouter.swift`, `Launcher/LauncherFocusModel.swift`, `MMTVLTests/LauncherFocusModelTests.swift`
  - Make `RemoteCommand` `String`-backed with `Codable` and `CaseIterable`, and add `fastForward` and `rewind`.
  - Fix the exhaustive switches: the new cases return `false` in `LauncherFocusModel.move` and in both `AppRouter.handle` screens.
  - Add the new cases to `nonDirectionalCommandsDoNotMove`.
  - Done when: it builds and tests pass.

- [x] **4. Bindings model + defaults**: `Input/InputBinding.swift`, `Input/KeyBindings.swift`, `MMTVLTests/KeyBindingsTests.swift`
  - Implement the types and the default table exactly as above. `InputBinding.init(from:)` uses `decodeIfPresent` for `isGlobal` (default false) and `label`.
  - Rewrite `KeyBindingsTests` against `KeyBindings.defaults`:
    - Every key mapping from M1 still works.
    - ⌘ + arrow → nil.
    - `[.function, .numericPad]` + arrow → left.
    - Home (115) → `.home` and `isGlobal`.
    - Media playPause → `.playPause`.
    - Controller `.a` → `.select`, `.home` → global `.home`.
    - Unknown key → nil.
    - Decoding the JSON sample from this plan gives the expected binding.
    - Encoding then decoding `defaultBindings` round-trips.
  - Done when: tests pass. (`InputRouter` still compiles: update its call to `bindings.command(...)` using a stored `KeyBindings.defaults` for now.)

- [x] **5. Router dispatch + media keys (local)**: `Input/MediaKeyEvent.swift`, `Input/InputRouter.swift`, `App/AppDelegate.swift`, `MMTVLTests/MediaKeyEventTests.swift`
  - Implement `MediaKeyEvent.parse`.
  - Refactor `InputRouter` to `init(bindings:)`, add `dispatch(_:isGlobal:)`, add `onGlobalCommand` and `onCommandDispatched`, and extend the local monitor to `[.keyDown, .systemDefined]` with unbound-key logging.
  - In `AppDelegate`, load `settings.json` and `key-bindings.json` through `JSONConfigFile` (see Wiring), and build `InputRouter(bindings:)`.
  - Tests:
    - `(16 << 16) | (0xA << 8)` → playPause, down.
    - `0xB` → up.
    - Bit 0 → repeat.
    - Subtype 7 → nil.
    - Key code 0 (volume up) → nil.
  - Done when: tests pass. Launching in windowed mode creates both JSON files, arrows still work, and pressing an unbound key (e.g. `Q`) logs `Unbound key 12` (`/usr/bin/log stream --predicate 'subsystem == "dev.mmtvl.launcher"' --level info`).

- [x] **6. Accessibility helper + onboarding screen**: `Input/AccessibilityPermission.swift`, `Launcher/AccessibilityOnboardingView.swift`, `Launcher/AppRouter.swift`
  - `request()`: `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)`, then `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`.
  - `waitUntilTrusted()`: loop `while !isTrusted { try? await Task.sleep(for: .seconds(1)) }`, honoring cancellation.
  - View: on the 1920×1080 canvas (Theme tokens). It shows:
    - An SF Symbol `hand.raised.fill`.
    - The title "Allow MMTVL to control this Mac".
    - Body text: "MMTVL needs Accessibility access so the Home button works in every app, media keys reach MMTVL, and apps open full screen."
    - Two button-like capsules, "Open Settings" and "Not now". Use the M1 tile focus visuals; Open Settings is always shown as focused.
    - The hint "Select: Open Settings · Back: Not now".
    - Clicking each capsule calls the same actions.
  - Router: add the screen case, `showAccessibilityOnboarding()`, `goHome()`, `onRequestAccessibility`, and handling as specified. `LauncherRootView` renders the new screen.
  - Done when: it builds. A temporary call to `router.showAccessibilityOnboarding()` (removed before ticking) shows the screen, and Back returns home.

- [x] **7. Global event tap**: `Input/GlobalEventTap.swift`, `App/AppDelegate.swift`
  - Implement as specified, including the nonisolated C callback, `TapEvent` extraction, `decide`, re-enable on disable, and async dispatch.
  - `AppDelegate`: add `handleGlobal(_:)` and `startGlobalInput()` (see Wiring), and call it only when `kiosk && settings.globalInputEnabled`.
  - `KioskWindowController.show()`: call `NSApp.unhide(nil)` before activating. After Exit to Desktop the app is hidden, and global Home must bring it back. (M1 only came back through the Dock, which unhides automatically.)
  - Done when (kiosk mode, Accessibility granted; this needs a human):
    - From Safari or Finder, fn+← brings the launcher home screen to the front and Safari keeps running.
    - fn+← inside a TextEdit document no longer moves the caret (expected; it's global).
    - Play/pause while the launcher is front does not start Music.
    - Play/pause while Safari plays a YouTube video still pauses it.
  - The executor checks: build, tests, and that with Accessibility **revoked**, launch shows the onboarding screen and the log says the tap could not be created.

- [x] **8. Onboarding → tap without relaunch**: `App/AppDelegate.swift`
  - Wire `router.onRequestAccessibility` and the `waitUntilTrusted` task from `startGlobalInput()`.
  - Done when (human): with Accessibility revoked (`tccutil reset Accessibility dev.mmtvl.launcher`), launch shows onboarding. Select opens the prompt and System Settings. Toggling MMTVL on brings the launcher back to the home screen within about 2 s, and fn+← works from Finder. If the tap doesn't receive events until relaunch, follow the *Risks* fallback and record it.

- [x] **9. Full screen for launched apps**: `Launcher/WindowFullScreener.swift`, `Launcher/LaunchItem.swift`, `Launcher/AppLauncher.swift`, `MMTVLTests/AppLauncherTests.swift`
  - Add `launchFullScreen` and `wantsFullScreen`. Set `prime` to `launchFullScreen: true`.
  - In `AppLauncher.launch`, after a successful `.application` or `.defaultBrowser` launch, if `item.wantsFullScreen && AccessibilityPermission.isTrusted`, start `Task { await fullScreener.makeFullScreen(pid: app.processIdentifier) }`. Keep the Chromium `--start-fullscreen` flag.
  - Tests: `wantsFullScreen` for `.application` with nil/true/false, and for `.defaultBrowser(fullScreen: true)` with `launchFullScreen` nil and false. Old JSON without `launchFullScreen` decodes.
  - Done when: tests pass. (Human: with Brave already running and windowed, the Browser tile makes Brave's window full screen within a few seconds.)

- [x] **10. Game controllers**: `Input/ThumbstickDirection.swift`, `Input/ControllerInput.swift`, `App/AppDelegate.swift`, `MMTVLTests/ThumbstickDirectionTests.swift`
  - Implement as specified. Start it in `AppDelegate` when `settings.controllersEnabled`, with `monitorInBackground: kiosk`. Log connect/disconnect with `vendorName` and the profile type.
  - Tests:
    - (0.7, 0.1) from nil → right.
    - (0.4, 0) from right → right (hysteresis).
    - (0.2, 0) from right → nil.
    - (0.1, -0.8) → down.
    - (0.5, 0.5) from nil → nil (below press threshold).
    - (-0.7, 0.65) → left (dominant axis).
  - Done when: tests pass. (Human, with any Bluetooth controller: D-pad, stick and A/B navigate; holding the D-pad repeats; Home from inside Safari returns to the launcher.)

- [x] **11. Cursor auto-hide + hover guard**: `App/KioskWindowController.swift`, `App/AppDelegate.swift`, `Launcher/AppRouter.swift`
  - `KioskWindowController.init(rootView:windowed:hidesCursor:)`: `show()` calls `NSCursor.setHiddenUntilMouseMoves(true)` when `hidesCursor`.
  - Wire `onCommandDispatched` (see Wiring) and implement the hover guard.
  - Done when (human): pressing an arrow hides the cursor and moving the mouse shows it. With the cursor parked over a tile, opening and closing a placeholder with the keyboard leaves focus where the keyboard put it.

- [x] **12. Launch at login**: `App/LoginItem.swift`, `App/AppDelegate.swift`
  - `LoginItem.apply(enabled:)`:
    - If enabled and status isn't `.enabled`, `try SMAppService.mainApp.register()`.
    - If not enabled and status is `.enabled`, `try SMAppService.mainApp.unregister()`.
    - Log the resulting status. On `.requiresApproval`, log a hint to approve in System Settings → General → Login Items.
    - Errors are logged, never fatal.
  - Kiosk mode only.
  - Done when: it builds. With `launchAtLogin: true` in `settings.json`, a kiosk launch makes MMTVL appear in Login Items. Setting it back to false and relaunching removes it. (The executor may verify via the log status; leave the dev Mac with it **off**.)

- [x] **13. Wake handling**: `Input/GlobalEventTap.swift` (`ensureEnabled`), `App/AppDelegate.swift`
  - `observeWake()` as specified. Kiosk only.
  - Done when (human): in kiosk mode, open Safari, sleep the Mac (Apple menu → Sleep), and wake it. Within about 2 s the launcher home is in front, Safari is still running, and fn+← still works.

- [x] **14. Wrap-up**: `docs/plans/MASTER_PLAN.md`, this file, `CLAUDE.md`
  - In CLAUDE.md: document `settings.json` and `key-bindings.json` (with the key-code discovery tip via `log stream`), and that signing uses team H846CY8RB4.
  - Tick steps, set M2 to `Done`, and note deviations.

## Tests

- New:
  - `JSONConfigFileTests`
  - `AppSettingsTests`
  - `MediaKeyEventTests`
  - `ThumbstickDirectionTests`
- Rewritten: `KeyBindingsTests` (instance-based, with modifiers, global flag, media, controller, and JSON format).
- Extended:
  - `LauncherFocusModelTests` (new commands)
  - `AppLauncherTests` (`wantsFullScreen`)
- Unchanged and must still pass: `LaunchItemStoreTests`.
- Run all: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`
- Event tap, controllers, AX full screen, login item and wake can't be unit-tested. They are covered under *Manual verification*.

## Manual verification

On the dev Mac (kiosk mode unless noted):
- [x] First kiosk launch without Accessibility shows the onboarding screen. Back dismisses it. Select prompts, and granting it brings the launcher back.
- [x] After a rebuild (`xcodebuild … build`) and relaunch, Accessibility is still granted (no onboarding).
- [x] fn+← (Home) from Safari, Finder and the desktop (after Exit to Desktop) shows the launcher home. The other app is still running.
- [x] ⌘Q / ⌘Tab still work everywhere. fn+← does nothing extra in `-windowed` mode.
- [x] Media play/pause with the launcher in front doesn't open Music. With Safari playing video in front, it still pauses the video.
- [x] Unbound keys show up in `log stream` with their key code while MMTVL is front, and never while another app is front.
- [x] Editing `key-bindings.json` (e.g. bind F13 = key code 105 to `home`, global) and relaunching makes F13 work.
- [x] Prime Video (if installed) and the Browser tile open full screen, including when the browser was already running.
- [x] Cursor hides on remote input and reappears on mouse movement. Hover doesn't steal focus after keyboard use.
- [x] Game controller (if available): navigation, select/back, hold-to-repeat, Home from another app. The Game Overlay doesn't appear (or Menu works as Home if it does).
- [x] Sleep/wake returns to the launcher home screen.
- [x] `launchAtLogin: true` registers the login item; `false` removes it. Leave it off on the dev Mac. (Verified by the executor through the log; left off.)

On the Mac mini / TV (when available):
- [ ] Install to `/Applications`, set `launchAtLogin: true`, approve in Login Items, and enable automatic login for the user (System Settings → Users & Groups). Reboot → the launcher is up without touching anything.
- [ ] Grant Accessibility on the mini (once per machine).
- [ ] With the purchased remote (Q1): find each button's key code in the log and map them in `key-bindings.json`. Make Home global.
- [ ] Wake from sleep through the remote and AVR: the launcher home is in front and the window fits the screen.
- [ ] Plex HTPC: does it need `launchFullScreen`? Leave it `nil` if Plex already goes full screen on its own.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Tap created right after the grant receives no events | Onboarding returns home but fn+← does nothing until relaunch | After `waitUntilTrusted`, relaunch the app: `NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration:)` with `createsNewApplicationInstance = true`, then `NSApp.terminate(nil)`. |
| Tap callback too slow → disabled | Global Home stops working after a while; `.tapDisabledByTimeout` in the log | Already re-enabled in `decide`. Make sure all work is `async` and the callback does only lookups. |
| Secure Event Input active (password field, Terminal setting) | fn+← ignored in that app only | Expected. Document it. A controller Home still works. |
| Controller Home opens the macOS 26 Game Overlay despite `.disabled` | Overlay appears on Home | Use Menu (≡), which is bound to Home by default, and remove the `home` binding in JSON if it's disruptive. |
| `shouldMonitorBackgroundEvents` crash or no events | Crash on controller connect, or Home ignored in the background | Make sure it's only set inside the connect handler. If events still don't arrive, set `controllersEnabled` false and rely on the keyboard/remote. |
| AX `AXFullScreen` set is ignored by an app | Window stays windowed | Fallback for that app: `CGEvent` post of ⌃⌘F to its PID (`postToPid`). Record it in Deviations before adding. |
| Signing asks for a provisioning profile in xcodebuild | Build error mentioning profiles | Add `-allowProvisioningUpdates` to the build commands (planner's test didn't need it). |
| Global Home is the Home key, which apps use (text editors) | Annoying on the dev Mac | Kiosk only (L2), `globalInputEnabled: false`, or rebind to F13 or a remote-only key. |

## Deviations & questions

All entries 2026-10-05, from `/build-plan`. None changes a master-plan decision.

- **Steps 7–11, 13: human checks.** The "done when" checks that need a person (global Home from other apps, media keys vs. Music/Safari, onboarding → grant without relaunch, AX full screen, controller, cursor/hover, sleep/wake) were run by the user on the dev Mac and passed (2026-10-05). The Mac mini / TV checks remain open. Executor checks that were run: step 5 (windowed launch creates `settings.json` + `key-bindings.json`; `Q` logs `Unbound key 12 modifiers []`; an arrow key isn't logged as unbound), step 6 (temporary onboarding call shows the screen; Escape returns home), step 7 (kiosk launch without Accessibility logs `Event tap could not be created`, which leads to onboarding), step 12 (`launchAtLogin: true` → log `Login item status: enabled`; `false` → `notRegistered`; left **off**).
- **Step 1:** `-allowProvisioningUpdates` was not needed.
- **Step 2 (mechanical):** the file-scope `Logger` in `JSONConfigFile.swift` must be `nonisolated private let` under MainActor default isolation. The test target also defaults to MainActor, so the test's `Codable` struct is marked `nonisolated`.
- **Step 4 (small):** every default binding gets a `label` (e.g. "Return", "Controller a"), not just Home, to make the JSON easier to edit by hand.
- **Step 5 (interpretation):** the local monitor swallows a bound media key (down, repeat and up) whether or not the screen handled the command. This matches the tap's rule (L5) and keeps Music from starting.
- **Step 8 (small):** after `waitUntilTrusted()` the task re-checks `isTrusted`, so cancellation doesn't start the tap.
- **Step 9 (small):** an extra test checks that the `prime` default wants full screen.
- **Step 10 (interpretation):** controllers already connected when `start()` runs go through the same connect path (log, `shouldMonitorBackgroundEvents`, configure), because no `GCControllerDidConnect` arrives for them. A connect has already happened in that case, so the SDL ordering concern still holds. The D-pad repeat is cancelled on release of the *repeating* button (or a new press, or disconnect), not on release of any other button.
- **Step 13 (mechanical):** the wake work lives in `systemDidWake()` so `assumeIsolated` doesn't return an unused `Task` (compiler warning).
