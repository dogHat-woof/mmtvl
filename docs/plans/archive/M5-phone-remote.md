# M5 — Phone remote

| | |
|---|---|
| Status | Done |
| Depends on | M2 (input layer), M2b (Settings), M3 (YouTube), M4 (Live TV player) |
| Master plan decisions used | D3, D4, D9, D10, D11, D16, D17, D18, D19, D20, D21, D22, D24 (new), D25 (new) |
| Planned | 2026-10-06 |

## Goal

Any phone on the home network (iPhone or Android, no install) opens a web page served by MMTVL and gets a remote control:

- A D-pad with OK, Back, Home, Play/Pause, Rewind and Fast Forward. Holding an arrow repeats it.
- **Volume up, down and mute.** With SoundSource running (the Mac mini), they change the volume through SoundSource. Without it they set the Mac's output volume when the device allows it. Otherwise they change MMTVL's own playback volume (Live TV and YouTube).
- **A keyboard.** Typing on the phone types into YouTube's search, or into whatever app is in front (Plex, Brave, Prime Video). The phone's Enter key sends Return.
- The remote works in every app. While MMTVL is in front, buttons act exactly like the physical remote (PIN keypad included). While another app is in front, the buttons become arrow, Return and Escape keys and media keys for that app. Home always brings MMTVL back.
- Pairing: Settings → Phone Remote → Pair a Phone shows a QR code and a 4-digit code. Scanning the QR code with the phone's camera opens the remote, already paired. The phone stays paired until "Forget All Phones".
- Settings → Phone Remote turns the server on or off and shows the address, the paired and connected phone counts, and whether typing and other-app control are allowed (Accessibility).

## Out of scope

- A trackpad/pointer mode on the phone (not chosen, 2026-10-06) → possibly **M7**.
- A native iOS app, HTTPS, Bonjour discovery → not planned (D11).
- Home-screen icons and splash images for "Add to Home Screen" → **M7** polish.
- Network control of the AV receiver (the user uses SoundSource; see D25).
- Learn-button binding editor → **M7**. Phone buttons are fixed `RemoteCommand`s and don't go through `key-bindings.json`.
- Showing the MMTVL screen name or now-playing info on the phone. The phone only shows which app is in front.
- Waking the Mac from system sleep from the phone. A browser can't send Wake-on-LAN, so the server is unreachable while the Mac sleeps.

## Research & findings

Verified 2026-10-06 on the dev Mac (macOS 27.0.1, Apple Silicon) with throwaway probes in the scratchpad, unless marked **unverified**.

### Network.framework WebSocket server

- **A listener with `NWProtocolWebSocket.Options` in its stack can't also serve plain HTTP.** A plain `GET /index.html` to it got no response: the connection sat in `.preparing` until the client timed out. `NWConnection` can't switch protocols mid-stream ([forums 705328](https://developer.apple.com/forums/thread/705328)). So the page needs **a second, plain-TCP listener** (L1).
- **The upgrade request's path and query are not visible to the server.** `NWProtocolWebSocket.Options.setClientRequestHandler(_:handler:)` receives the requested subprotocols and the headers only ([docs](https://developer.apple.com/documentation/network/nwprotocolwebsocket/options); Quinn: known gap, [forums 659389](https://developer.apple.com/forums/thread/659389)). Hence auth by first message (L2).
- `autoReplyPing` exists and defaults to `false`. Set it `true`. `maximumMessageSize` defaults to `0` (believed to mean unlimited; **unverified**). Set it explicitly.
- **Every send needs WebSocket metadata.** A send without it failed with EIO and the connection went to `.failed`. This works:
  ```swift
  let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
  let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
  connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
  ```
- **Receive loop:** call `connection.receiveMessage { data, context, isComplete, error in … }` and re-arm it at the end of each callback. Read the opcode from `context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata`. When the client closes, the callback fires with `data == nil` and no error, and the next call fails with ENOMSG (POSIX 96). Stop on either: `data == nil && error == nil`, any `error`, or a `.close` opcode.

### Local Network privacy and firewall ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy))

- Listening for and accepting incoming TCP connections: **not covered** ("Required: no"). An `NWListener` serving phones needs no permission and no `NSLocalNetworkUsageDescription`.
- Outgoing TCP to a LAN address, resolving `.local` names and **all Bonjour operations, advertising included,** are covered. M5 does none of them (L15).
- Application Firewall: off on the dev Mac (`socketfilterfw` state 0). If it's on, macOS may ask once to allow incoming connections for MMTVL. Whether an Apple Development signature is auto-allowed is **unverified**. Check on the Mac mini: System Settings → Network → Firewall.

### Posting synthetic events (D4 Accessibility grant)

- `CGEvent.post` needs the **PostEvent** TCC privilege. It shows under Privacy & Security → Accessibility. Check it with `CGPreflightPostEventAccess()` and request it with `CGRequestPostEventAccess()` ([Quinn, forums 789896](https://developer.apple.com/forums/thread/789896)). A process with the Accessibility grant returned `CGPreflightPostEventAccess() == true` in the probe. Assume MMTVL's existing grant covers it, and confirm in step 1.
- **Typing text:** `CGEvent(keyboardEventSource:virtualKey: 0, keyDown:)` + `keyboardSetUnicodeString(stringLength:unicodeString:)`, posted down then up.
  - Apple warns that "application frameworks may ignore the Unicode string … and do their own translation based on the virtual keycode" ([docs](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:))).
  - The limit of **20 UTF-16 units per event** is community knowledge, not Apple's: KDE Connect's macOS code chunks at 20 and never splits a surrogate pair ([MR 467](https://invent.kde.org/network/kdeconnect-kde/-/merge_requests/467)). Chunk by `Character` (L7).
  - Whether Brave, Plex HTPC and Prime Video accept it is **unverified**; see *Manual verification*. In MMTVL's YouTube, unbound native keys already reach leanback, letters for search included (`YouTubeView.swift` comment, M3).
- **Tagging our own events:** setting `CGEventSource.userData = 0x4D4D54564C` and posting at `.cghidEventTap` made a `.cghidEventTap` listen tap read the same value from `.eventSourceUserData`. `.eventSourceUnixProcessID` also equalled the poster's PID. Whether an `NSEvent` local monitor sees the field through `event.cgEvent` is **unverified** but likely, since it's the same CGEvent. The plan checks both fields (L6).
- **Media and volume keys** (SDK `ev_keymap.h`):
  - Constants: `NX_SUBTYPE_AUX_CONTROL_BUTTONS = 8`, key down `0xA`, key up `0xB`. `SOUND_UP = 0`, `SOUND_DOWN = 1`, `MUTE = 7`, `PLAY = 16`, `NEXT = 17`, `PREVIOUS = 18`, `FAST = 19`, `REWIND = 20`.
  - Hammerspoon's working recipe ([libeventtap_event.m](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/libeventtap_event.m)) builds `NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | ((down ? 0xA : 0xB) << 8), data2: -1)` and posts its `.cgEvent`, once down and once up. This is undocumented, reverse-engineered behavior.
  - Media keys go to the system's Now Playing app, not necessarily the frontmost app (**unverified**).
  - MMTVL's own `MediaKeyEvent.parse` ignores volume codes (0, 1, 7), and the event tap passes media keys through while MMTVL isn't frontmost.

### Volume

- **The HDMI output has no macOS volume.** On the dev Mac, the "HDMI Audio" device (transport `hdmi`) has no `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, `kAudioDevicePropertyVolumeScalar` or `kAudioDevicePropertyMute`. The built-in speakers have all three, all settable. Expect the same on the Mac mini. Rogue Amoeba says macOS "will offer no volume adjustment" over HDMI/DisplayPort ([blog](https://weblog.rogueamoeba.com/2020/04/07/soundsource-gives-you-volume-control-of-any-audio-outputs-including-hdmi-and-displayport-devices/)).
- **SoundSource** gives HDMI devices a software volume, and its "Super Volume Keys" option makes the keyboard volume keys control it.
  - SoundSource 6.1.4 is installed and running on the dev Mac. Bundle ID **`com.rogueamoeba.soundsource`** (read from its Info.plist).
  - Whether Super Volume Keys reacts to **synthetic** volume keys posted at `.cghidEventTap` is **unverified**. Check it in step 6. If it doesn't, `phoneRemoteVolume: "app"` is the fallback (see *Risks*).
- CoreAudio, for the "system" route:
  - Default output device: `AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain), …)`.
  - Volume (`Float32`, 0…1): `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, scope `kAudioObjectPropertyScopeOutput`, element `kAudioObjectPropertyElementMain` (`import AudioToolbox`).
  - Mute (`UInt32`): `kAudioDevicePropertyMute`, same scope and element.
  - Check `AudioObjectHasProperty` and `AudioObjectIsPropertySettable` before use.
- In-app volume:
  - mpv has `volume` (0–100, the default range) and `mute` (`yes`/`no`) properties. They persist across `loadfile` in one core, and MMTVL keeps one core for its lifetime (D22).
  - YouTube: HTMLMediaElement `volume` (0…1) and `muted`. Media events (`play`, `loadedmetadata`) don't bubble, but a **capture** listener on `document` receives them.

### Phone browsers over plain `http://192.168.x.x`

- `ws://` from an `http://` page is fine; both are insecure, so there's no mixed-content issue.
  - Chrome's Local Network Access rules only restrict public→local and local→loopback requests, not LAN page → LAN IP ([Chrome blog](https://developer.chrome.com/blog/local-network-access)).
  - Safari traffic is exempt from Apple's Local Network privacy (TN3179).
- **Add to Home Screen** over http: whether iOS or Android opens it standalone (no browser bar) is **unverified and conflicting**. It may open as a normal tab. Either way the remote still works.
- `navigator.vibrate`: not on iOS Safari. On Android Chrome it needs a user gesture. Call it only if it exists.
- `localStorage`: Home Screen web apps on iOS have storage separate from Safari ([WebKit](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/)), so a phone that pairs in Safari and then adds to Home Screen may need to **pair again from the Home Screen icon** (open the page from the icon, enter the code). Persistence for an http origin is **unverified**. Losing it only means pairing again.
- `.local` names: Android support is partial. A raw IPv4 address in the URL and QR code is the safe choice (L12).
- Pointer events (`pointerdown`/`pointerup`/`pointercancel`) are supported on iOS 13+ and Android Chrome.

### App Transport Security (for the tests' URLSession client)

- "In iOS 17, iPadOS 17, and macOS 14, ATS no longer allows connections to IP addresses by default" ([NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)). Tests run hosted in the app (ATS applies), so the integration test uses **`localhost`** (an unqualified domain), not `127.0.0.1`. Whether ATS allows `http://localhost` on macOS 26 is **unverified**. If the test fails with an ATS error (−1022), use the fallback in step 5.
- The **server** is unaffected; ATS only governs the app's own outgoing URLSession loads.

### QR codes ([CIFilter.qrCodeGenerator](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/qrcodegenerator()))

- `import CoreImage.CIFilterBuiltins`; `let filter = CIFilter.qrCodeGenerator(); filter.message = Data(string.utf8); filter.correctionLevel = "M"`.
- The output is 1 pixel per module plus a 1-module border; a 44-byte URL gave 31×31. The QR spec wants a **4-module quiet zone**, so draw it on a white background with padding.
- Crisp scaling: `output.samplingNearest().transformed(by: CGAffineTransform(scaleX: 10, y: 10))`, then `CIContext().createCGImage(_:from:)`. In SwiftUI: `Image(decorative: cgImage, scale: 1).interpolation(.none).resizable()`.

### Swift 6 in this project (from M2/M4)

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Network callbacks are `@Sendable` closures. Start every `NWListener`/`NWConnection` on **`.main`** and wrap handler bodies in `MainActor.assumeIsolated { … }`, as `ControllerInput` does for notifications.
- `NWListener` and `NWConnection` are Sendable in the current SDK (**unverified**: if the compiler rejects capturing them, capture an `ObjectIdentifier`/session id and look the connection up in a dictionary instead).
- Global C `var` constants fail strict concurrency (M2: `kAXTrustedCheckOptionPrompt`). The CoreAudio `k…` selectors are enum constants and are fine.

## Design

### Files

| Path | New/changed | Responsibility |
|---|---|---|
| `MMTVL/Input/SyntheticInput.swift` | new | Posts tagged CGEvents: keys, media/volume keys, Unicode text chunks, backspaces. Recognizes our own events. |
| `MMTVL/Input/ExternalKeyMap.swift` | new | `RemoteCommand` → key or media key for an app other than MMTVL. |
| `MMTVL/Input/InputRouter.swift` | changed | The local monitor passes tagged (synthetic) events through untouched. |
| `MMTVL/Input/GlobalEventTap.swift` | changed | The tap passes tagged events through. |
| `MMTVL/RemoteServer/RemoteMessage.swift` | new | `ClientMessage`, `ServerMessage`, `VolumeAction`, JSON wire format. |
| `MMTVL/RemoteServer/TextEdit.swift` | new | `TextEdit.between(_:_:)`: backspaces + insertion from the old to the new field value. |
| `MMTVL/RemoteServer/LocalAddress.swift` | new | Picks the Mac's LAN IPv4 address. |
| `MMTVL/RemoteServer/HTTPRequest.swift` | new | Minimal HTTP/1.1 request-head parser and response builder. |
| `MMTVL/RemoteServer/RemoteWebAssets.swift` | new | Path → bundled web file + content type (allow-list). |
| `MMTVL/RemoteServer/Web/remote.html`, `remote.css`, `remote.js` | new | The phone page. |
| `MMTVL/RemoteServer/Pairing.swift` | new | `PairingCode`, `PairedPhone`, `PhoneToken`, `PairedPhoneStore` (Keychain). |
| `MMTVL/RemoteServer/RemoteServer.swift` | new | The two `NWListener`s (HTTP, WebSocket), sessions, send/close. |
| `MMTVL/RemoteServer/PhoneRemote.swift` | new | The coordinator: auth, pairing, command routing, text, volume, status pushes. |
| `MMTVL/App/Volume.swift` | new | `VolumeMode`, `VolumeRoute`, `AppVolume`, `SystemVolume` (CoreAudio), `VolumeController`. |
| `MMTVL/DesignSystem/QRCodeImage.swift` | new | `CGImage` QR code for a string. |
| `MMTVL/DesignSystem/Theme.swift` | changed | `settingsQRCodeSize`. |
| `MMTVL/App/AppSettings.swift` | changed | `phoneRemoteEnabled`, `phoneRemotePort`, `phoneRemoteVolume`. |
| `MMTVL/Settings/SettingsTypes.swift` | changed | Pages, `SettingKey.phoneRemoteEnabled`, `.forgetAllPhones`, `RowImage.qrCode`, `PhoneRemoteSettingsStatus`. |
| `MMTVL/Settings/SettingsEnvironment.swift` | changed | `phoneRemoteStatus`, `setPhonePairing`, `forgetAllPhones`. |
| `MMTVL/Settings/SettingsModel.swift` | changed | Status field, pairing lifecycle (`syncPairing`, `screenDidClose`). |
| `MMTVL/Settings/SettingsModel+Pages.swift` | changed | Root row and the three new pages. |
| `MMTVL/Settings/SettingsRowView.swift` | changed | `RowImageView` draws `.qrCode`. |
| `MMTVL/Launcher/AppRouter.swift` | changed | `goHome()` from Settings calls `settings.screenDidClose()`. |
| `MMTVL/IPTV/Player/LivePlayer.swift` | changed | `MPVPlayerController.setVolume(_:muted:)`. |
| `MMTVL/YouTube/YouTubeKeyMap.swift`, `YouTube/YouTubeController.swift` | changed | Volume user script, `setVolume(_:muted:)`. |
| `MMTVL/App/AppDelegate.swift` | changed | Creates and wires the server, coordinator and volume controller; applies settings live. |
| `MMTVLTests/…` | new/changed | See *Tests*. |
| `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` | changed | Docs (step 11). |

### Local decisions

- **L1. Two listeners.** HTTP on `phoneRemotePort` (default **8765**) serves the page. The WebSocket listener is on **port + 1** (8766). The page computes the socket URL as `ws://<location.hostname>:<location.port + 1>/`. A WebSocket listener can't serve HTTP (research), and two plain listeners are much less code than hand-written RFC 6455 framing.
- **L2. Auth by first message.** A new socket is unauthenticated and may only send `hello` (a saved token) or `pair` (the code).
  - Anything else from it is ignored. A failed `hello` gets `authFailed`, and the socket stays open so the page can pair on it.
  - At most **8** sockets at once (more are cancelled at accept). `maximumMessageSize` is 16 KB. Text values over 1,000 characters are ignored.
  - Rationale: the server can't see the upgrade URL. First-message auth is simpler than subprotocol tricks.
- **L3. Pairing happens only on Settings → Phone Remote → Pair a Phone** (user choice 2026-10-06), which the launcher PIN guards like all of Settings.
  - While that page shows, a random 4-digit code is valid. It ends when the page closes (Back, Home, Settings reset) or after **10 minutes**.
  - **5 wrong codes rotate it** (new code on the TV). Several phones can pair during one visit.
  - The QR code encodes `http://<ip>:<port>/#pair=<code>`. The code sits in the URL fragment, so it's never sent in an HTTP request.
- **L4. Tokens.**
  - Each pairing issues a random 32-byte token (base64url, no padding). The phone keeps it in `localStorage`.
  - The Mac keeps only its **SHA-256 hex** in the Keychain (D9): account **`phone-remote-phones`**, a JSON array of `PairedPhone`.
  - At most 10 phones; pairing an 11th drops the oldest.
  - Forget All Phones (Settings) clears the list and closes every authenticated socket. Mac-side reset: `security delete-generic-password -s dev.mmtvl.launcher -a phone-remote-phones`.
- **L5. Command routing (user choice 2026-10-06: the phone controls other apps).**
  - MMTVL frontmost (`NSApp.isActive`): `InputRouter.dispatch(command, isGlobal: false)`, exactly like the physical remote.
  - Otherwise, `.home`: `dispatch(.home, isGlobal: true)` (the existing global-Home path brings MMTVL back; D18).
  - Otherwise, any other command is posted to the frontmost app through `ExternalKeyMap` + `SyntheticInput`. This needs post-event access; without it the phone gets a toast.
- **L6. Synthetic events are tagged and never handled by MMTVL's own input code.**
  - Every event `SyntheticInput` posts carries `eventSourceUserData = SyntheticInput.marker` (`0x4D4D54564C`, "MMTVL").
  - `SyntheticInput.isOwn(_:)` is true when that field matches **or** `eventSourceUnixProcessID` equals our PID.
  - The local monitor and the event tap pass such events through untouched and unlogged.
  - So a typed Delete (backspace) isn't treated as Back, and typed text isn't logged as "Unbound key".
- **L7. Text entry.**
  - The phone sends the **whole field value** on every change. The server diffs it against the last value for that socket (`TextEdit.between`) and posts that many backspaces plus the inserted text.
  - This survives autocorrect, paste and deletions in the middle (a middle edit becomes backspaces back to the change, then retyping).
  - `textBegin` resets the last value to "" (keyboard opened). `submit` posts Return and resets it.
  - Inside MMTVL, only the YouTube screen accepts text. Elsewhere the phone gets the toast "Nothing to type into here", so unhandled keys don't beep.
  - Text goes out in chunks of at most 20 UTF-16 units, split at `Character` boundaries.
- **L8. Volume route** (user choice 2026-10-06), `VolumeRoute.choose`. `settings.json` `phoneRemoteVolume` (hand-edited) forces a route: `"keys"`, `"system"`, `"app"`, or the default `"auto"`. Auto:
  1. SoundSource is running → post volume keys (SoundSource's Super Volume Keys takes them).
  2. Else the default output device's volume is settable → set it through CoreAudio in 1/16 steps, and toggle its mute.
  3. Else MMTVL is frontmost → MMTVL's own volume (L9) in steps of 5.
  4. Else the toast "Volume can't be changed here".
- **L9. In-app volume** is one level (0–100, default 100) plus mute, in memory only (back to 100 at launch). Every change goes to both mpv (`volume`/`mute`) and the YouTube page (user script). Applying it while nothing plays is harmless and keeps both in sync.
- **L10. Phone Remote is on by default** (`phoneRemoteEnabled: true`), in kiosk and `-windowed` mode alike. Nothing works without pairing, and the page alone reveals nothing. The port is hand-edited only. The Settings toggle starts and stops both listeners live.
- **L11. The HTTP server is minimal.**
  - Only `GET`/`HEAD` (others → 405), only allow-listed paths (others → 404), and the request head is capped at 16 KB (→ 431).
  - Every response: `Connection: close`, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`.
  - Connections idle for more than 10 s are cancelled.
  - The web files ship as bundle resources with unique names (`remote.html`, `remote.css`, `remote.js`), because synchronized groups copy resources flat into `Contents/Resources`.
- **L12. The address is the Mac's IPv4.** Prefer `en0`, then `en1`, then any other up, running, non-loopback interface, skipping `169.254.*` (link-local). It's recomputed at each Settings refresh. No `.local` names: Android support is partial and they'd involve Bonjour. A DHCP reservation for the Mac mini keeps bookmarks working (documented in CLAUDE.md).
- **L13. Logging (category `PhoneRemote`).** Log phone names, counts, ports, the LAN IP and the server state. **Never** log tokens, pairing codes, typed text or raw messages.
- **L14. The phone page** is plain HTML/CSS/JS, dark and tvOS-like. It has a button D-pad with client-side repeat (450 ms delay, then every 120 ms, the same as `ControllerInput`), a keyboard panel and a pairing form. There are no swipe gestures or trackpad.
- **L15. No Bonjour advertising.** It would trigger the Local Network prompt (TN3179), and phone browsers don't browse Bonjour anyway.
- **L16. Status to the phone:** the frontmost app's name and whether MMTVL is frontmost. It's pushed after auth and on every `NSWorkspace.didActivateApplicationNotification`.
- **L17. Phone volume and text are not `RemoteCommand`s.** They don't come from bindable hardware and go straight to `VolumeController`/`SyntheticInput`. D3 still holds for button input: every phone button is a `RemoteCommand`.

### Key types

```swift
// Input/SyntheticInput.swift
import AppKit
import CoreGraphics

/// Posts tagged synthetic events (L6). Needs post-event access (the Accessibility grant, D4).
nonisolated enum SyntheticInput {
    /// "MMTVL" in ASCII; stored in kCGEventSourceUserData of every event we post.
    static let marker: Int64 = 0x4D4D54564C

    /// NX_KEYTYPE_* (ev_keymap.h).
    enum NXKey {
        static let soundUp: Int32 = 0, soundDown: Int32 = 1, mute: Int32 = 7
        static let play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18
    }

    /// CGPreflightPostEventAccess().
    static var canPost: Bool { get }
    /// CGRequestPostEventAccess(); shows the system prompt once.
    static func requestAccess()

    /// True for events this process posted: userData == marker, or source PID == our PID.
    static func isOwn(_ event: CGEvent) -> Bool

    /// keyDown + keyUp with no modifier flags (`event.flags = []`).
    static func postKey(_ keyCode: CGKeyCode)
    /// System-defined subtype 8, down then up (Hammerspoon recipe; see Research).
    static func postMediaKey(_ key: Int32)
    /// Text in ≤ 20-UTF-16-unit chunks: per chunk, virtualKey 0 keyDown with keyboardSetUnicodeString, then keyUp.
    static func type(_ text: String)
    /// `count` × postKey(kVK_Delete).
    static func deleteBackward(_ count: Int)

    /// Pure, tested: splits at Character boundaries, each chunk's utf16.count ≤ maxUTF16.
    /// A single Character longer than maxUTF16 (rare emoji sequences) becomes its own chunk.
    static func chunks(_ text: String, maxUTF16: Int = 20) -> [String]
}
```

Implementation notes:
- Build each event from one `CGEventSource(stateID: .hidSystemState)`. Set `source.userData = marker` **and** call `event.setIntegerValueField(.eventSourceUserData, value: marker)` on every event (the media-key events come from `NSEvent.cgEvent` and don't use the source).
- Post with `event.post(tap: .cghidEventTap)`.
- `postKey`/`type` set `event.flags = []` so a physically held modifier doesn't leak in.
- `keyboardSetUnicodeString`: `let utf16 = Array(chunk.utf16); event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)`.

```swift
// Input/ExternalKeyMap.swift
nonisolated enum ExternalKey: Equatable, Sendable {
    case key(CGKeyCode)
    case media(Int32)
}

nonisolated enum ExternalKeyMap {
    /// For an app other than MMTVL (L5). Arrows → kVK_*Arrow; select → kVK_Return; back → kVK_Escape;
    /// playPause → media PLAY; fastForward → media NEXT; rewind → media PREVIOUS; home → nil (handled by MMTVL).
    static func key(for command: RemoteCommand) -> ExternalKey?
}
```
`fastForward`/`rewind` → NEXT/PREVIOUS mirror the default bindings (media next → fastForward). Whether Plex HTPC treats them as seek or skip is checked in *Manual verification*. This table is the one place to change it.

```swift
// RemoteServer/RemoteMessage.swift
nonisolated enum VolumeAction: String, Codable, Sendable { case up, down, mute }

/// Phone → Mac.
nonisolated enum ClientMessage: Equatable, Sendable {
    case hello(token: String)
    case pair(code: String, name: String)
    case command(RemoteCommand)
    case textBegin
    case text(String)
    case submit
    case volume(VolumeAction)

    /// nil for malformed JSON, an unknown type, a missing field or an unknown command/action.
    static func decode(_ data: Data) -> ClientMessage?
}

/// Mac → phone.
nonisolated enum ServerMessage: Equatable, Sendable {
    case welcome
    case authFailed
    case paired(token: String)
    case pairFailed(String)
    case status(frontApp: String, launcherActive: Bool)
    case toast(String)
    /// level 0…1; nil level = unknown (volume keys were sent).
    case volume(level: Double?, muted: Bool?)

    /// One JSON object, sorted keys, nil fields omitted.
    func encoded() -> Data
}
```
Wire format: one JSON object per text frame, discriminated by `"type"`. Use a private `Codable` struct with every field optional (`type: String` plus `token`, `code`, `name`, `command`, `value`, `action`, `message`, `frontApp`, `launcherActive`, `level`, `muted`). Synthesized `Codable` omits nil optionals.

| Message | JSON |
|---|---|
| hello | `{"type":"hello","token":"…"}` |
| pair | `{"type":"pair","code":"1234","name":"iPhone"}` |
| command | `{"type":"command","command":"up"}` (a `RemoteCommand` raw value) |
| textBegin / submit | `{"type":"textBegin"}` / `{"type":"submit"}` |
| text | `{"type":"text","value":"star wa"}` |
| volume | `{"type":"volume","action":"up"}` |
| welcome / authFailed | `{"type":"welcome"}` / `{"type":"authFailed"}` |
| paired | `{"token":"…","type":"paired"}` |
| pairFailed / toast | `{"message":"…","type":"pairFailed"}` / `{"message":"…","type":"toast"}` |
| status | `{"frontApp":"Plex HTPC","launcherActive":false,"type":"status"}` |
| volume | `{"level":0.5,"muted":false,"type":"volume"}` |

```swift
// RemoteServer/TextEdit.swift
nonisolated struct TextEdit: Equatable, Sendable {
    var deletions: Int
    var insertion: String

    /// Common prefix by Character: deletions = old.count − prefix, insertion = new.dropFirst(prefix).
    static func between(_ old: String, _ new: String) -> TextEdit
    var isEmpty: Bool { deletions == 0 && insertion.isEmpty }
}
```

```swift
// RemoteServer/LocalAddress.swift
nonisolated enum LocalAddress {
    struct Interface: Equatable, Sendable { var name: String; var ipv4: String; var isUp: Bool; var isLoopback: Bool }
    /// getifaddrs → AF_INET entries (IFF_UP && IFF_RUNNING → isUp; IFF_LOOPBACK → isLoopback); inet_ntop for the string.
    static func interfaces() -> [Interface]
    /// L12. Pure, tested.
    static func pick(_ interfaces: [Interface]) -> String?
    static func primaryIPv4() -> String? { pick(interfaces()) }
}
```

```swift
// RemoteServer/HTTPRequest.swift
nonisolated struct HTTPRequestHead: Equatable, Sendable {
    var method: String
    /// Without the query string; percent-decoding not needed (allow-list match).
    var path: String

    enum ParseResult: Equatable { case incomplete, tooLarge, invalid, complete(HTTPRequestHead) }
    /// Looks for "\r\n\r\n" in `data` (max 16 KB, else .tooLarge), parses "METHOD SP target SP HTTP/1.x".
    static func parse(_ data: Data) -> ParseResult
}

nonisolated enum HTTPResponse {
    /// "HTTP/1.1 <status> <reason>\r\n" + Content-Type, Content-Length, Connection: close,
    /// Cache-Control: no-store, X-Content-Type-Options: nosniff, blank line, body (omitted for HEAD).
    static func make(status: Int, reason: String, contentType: String, body: Data, includeBody: Bool) -> Data
    static func error(_ status: Int, _ reason: String) -> Data   // text/plain body "<status> <reason>"
}
```

```swift
// RemoteServer/RemoteWebAssets.swift
nonisolated struct RemoteWebAsset: Equatable, Sendable { var resource: String; var ext: String; var contentType: String }

nonisolated enum RemoteWebAssets {
    /// "/" and "/index.html" → remote.html; "/remote.css"; "/remote.js". Anything else → nil (404).
    static func asset(forPath path: String) -> RemoteWebAsset?
    /// Bundle.main.url(forResource:withExtension:) → Data. Read per request (tiny files; no caching needed).
    static func data(for asset: RemoteWebAsset, bundle: Bundle = .main) -> Data?
}
```
Content types: `text/html; charset=utf-8`, `text/css; charset=utf-8`, `text/javascript; charset=utf-8`.

```swift
// RemoteServer/Pairing.swift
nonisolated struct PairingCode: Equatable, Sendable {
    static let lifetime: TimeInterval = 600
    static let maxFailures = 5
    var code: String          // 4 digits, "0000"…"9999"
    var expires: Date
    var failures = 0

    enum Check: Equatable { case accepted, rejected, rotated(PairingCode), expired }
    /// Wrong code: failures += 1; at maxFailures returns .rotated(fresh code via makeCode, same expiry).
    func check(_ attempt: String, now: Date, makeCode: () -> String) -> Check
    static func random() -> String   // String(format: "%04d", Int.random(in: 0...9999))
}

nonisolated struct PairedPhone: Codable, Equatable, Sendable {
    var id: String          // UUID string
    var name: String        // from the page ("iPhone", "Android phone"), trimmed to 40 chars
    var tokenHash: String   // SHA-256 hex of the token
    var pairedAt: Date
}

nonisolated enum PhoneToken {
    /// 32 bytes from SecRandomCopyBytes, base64url without padding.
    static func make() -> String
    /// CryptoKit SHA256, lowercase hex.
    static func hash(_ token: String) -> String
}

/// Closures like `PINStore`, so tests can use `.inMemory()`.
struct PairedPhoneStore {
    static let account = "phone-remote-phones"
    var load: () -> [PairedPhone]          // Keychain errors / bad JSON → logged, []
    var save: ([PairedPhone]) throws -> Void
    static let keychain: PairedPhoneStore
    static func inMemory(_ initial: [PairedPhone] = []) -> PairedPhoneStore
}
```
Keychain JSON uses `JSONEncoder` with `.iso8601` dates. Clear = `save([])`; there's no need to delete the item.

```swift
// RemoteServer/RemoteServer.swift
import Network

typealias RemoteSessionID = Int

protocol RemoteTransport: AnyObject {
    func send(_ message: ServerMessage, to session: RemoteSessionID)
    func close(_ session: RemoteSessionID)
}

/// L1: plain-TCP HTTP listener + WebSocket listener. Main queue throughout.
final class RemoteServer: RemoteTransport {
    enum State: Equatable { case stopped, starting, running, failed(String) }

    private(set) var state: State = .stopped
    var onStateChange: (() -> Void)?
    var onMessage: ((RemoteSessionID, Data) -> Void)?
    var onSessionClosed: ((RemoteSessionID) -> Void)?

    /// Actual ports once running (tests pass .any).
    var httpPort: UInt16? { get }
    var socketPort: UInt16? { get }

    func start(httpPort: NWEndpoint.Port, socketPort: NWEndpoint.Port)
    /// Cancels both listeners and every connection; fires onSessionClosed for each session.
    func stop()
    func send(_ message: ServerMessage, to session: RemoteSessionID)
    func close(_ session: RemoteSessionID)
}
```

Server behavior:
- **Parameters.**
  - HTTP: `NWParameters.tcp`.
  - WebSocket: `let p = NWParameters.tcp`, then `p.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)`, where `ws = NWProtocolWebSocket.Options()`, `ws.autoReplyPing = true`, `ws.maximumMessageSize = 16_384`.
  - Both: `allowLocalEndpointReuse = true`, so Relaunch MMTVL doesn't hit `EADDRINUSE` from sockets in TIME_WAIT.
- **States.**
  - `state` is `.running` when both listeners report `.ready`.
  - Either listener `.failed(error)`: cancel both, set `.failed(message)` and retry `start` after **10 s** while not stopped. The message is "Port 8765 is in use" for POSIX `EADDRINUSE`, else `error.localizedDescription`.
  - `.waiting` counts as `.starting`.
- **HTTP connection.**
  1. Accumulate `receive(minimumIncompleteLength: 1, maximumLength: 16_384)` until `HTTPRequestHead.parse` is not `.incomplete`.
  2. `.tooLarge` → 431. `.invalid` → 400. Method other than GET/HEAD → 405. Unknown path → 404.
  3. Otherwise 200 with the asset.
  4. `send(content:completion: .contentProcessed { _ in connection.cancel() })`.
  5. Also cancel after 10 s regardless.
- **WebSocket connection.**
  - Assign the next `RemoteSessionID` and keep `[RemoteSessionID: NWConnection]`.
  - Over 8 open: cancel immediately.
  - Receive loop as in *Research*. `.text` → `onMessage(id, data)`. Ignore binary. Close/error/EOF → remove, cancel, `onSessionClosed(id)`.
  - `.failed`/`.cancelled` state → same cleanup (only once per session).
- `send`: encode, text metadata (research). Unknown session → no-op.

```swift
// RemoteServer/PhoneRemote.swift
/// Everything PhoneRemote does to the outside world. The app wires the real thing; tests pass fakes.
struct PhoneRemoteEnvironment {
    var isLauncherActive: () -> Bool                       // NSApp.isActive
    var dispatch: (RemoteCommand, Bool) -> Void            // InputRouter.dispatch(_:isGlobal:)
    var canPostEvents: () -> Bool                          // SyntheticInput.canPost
    var postExternal: (ExternalKey) -> Void                // SyntheticInput.postKey / postMediaKey
    var typeEdit: (TextEdit) -> Void                       // deleteBackward + type
    var postReturn: () -> Void                             // SyntheticInput.postKey(kVK_Return)
    var launcherAcceptsText: () -> Bool                    // router.screen == .youtube
    var frontAppName: () -> String                         // frontmostApplication?.localizedName ?? "Mac"
    var volume: (VolumeAction) -> VolumeFeedback           // VolumeController.perform
    var now: () -> Date
    var makeCode: () -> String                             // PairingCode.random
    var makeToken: () -> String                            // PhoneToken.make
}

@Observable
final class PhoneRemote {
    init(transport: RemoteTransport, store: PairedPhoneStore, environment: PhoneRemoteEnvironment)

    /// Pairing started/rotated/ended, a phone paired, a session opened/closed or authenticated, forget-all.
    @ObservationIgnored var onStatusChange: (() -> Void)?

    private(set) var pairing: PairingCode?
    /// Name of the last phone paired during the current pairing; cleared when pairing starts or ends.
    private(set) var lastPairedName: String?
    var pairedCount: Int { get }            // store.load().count, cached after load/save
    var connectedCount: Int { get }         // authenticated sessions

    // From RemoteServer
    func receive(_ data: Data, from session: RemoteSessionID)
    func sessionClosed(_ session: RemoteSessionID)

    // From Settings (L3)
    func setPairing(_ active: Bool)
    func forgetAll()

    /// App activation changed: push .status to every authenticated session (L16).
    func frontAppChanged()
    /// Server stopped: drop all session state.
    func reset()
}
```

`PhoneRemote.receive` rules. Per session state: `phoneID: String?` (nil = unauthenticated) and `lastText: String`.

| Message | Unauthenticated | Authenticated |
|---|---|---|
| `hello(token)` | hash matches a stored phone → set `phoneID`, send `.welcome` then `.status`; else `.authFailed` | same (re-auth) |
| `pair(code, name)` | no `pairing` or expired → `.pairFailed("Open Settings → Phone Remote → Pair a Phone on the TV")`. `.rejected` → `.pairFailed("Wrong code")`. `.rotated` → store it, `.pairFailed("Wrong code. A new code is on the TV")`. `.accepted` → token, store `PairedPhone` (drop oldest over 10), set `phoneID`, `lastPairedName`, send `.paired(token)` then `.status` | same |
| `command(c)` | ignored | L5 (below) |
| `textBegin` | ignored | `lastText = ""` |
| `text(v)` | ignored | L7 (below) |
| `submit` | ignored | if allowed (L7 rule) → `postReturn()`; `lastText = ""` |
| `volume(a)` | ignored | `volume(a)` → `.volume(level:muted:)` or `.toast(message)` |
| undecodable | ignored | ignored |

- **Command (L5):**
  - `isLauncherActive()` → `dispatch(c, false)`.
  - `c == .home` → `dispatch(.home, true)`.
  - `canPostEvents()` → `ExternalKeyMap.key(for: c).map(postExternal)`.
  - Else `.toast("Allow Accessibility for MMTVL on the Mac to control other apps")`.
- **Text (L7):**
  - `v.count > 1000` → ignore.
  - `edit = TextEdit.between(lastText, v)`; `lastText = v`.
  - If `edit.isEmpty`, stop.
  - If MMTVL is frontmost and `!launcherAcceptsText()` → `.toast("Nothing to type into here")`.
  - Else if `!canPostEvents()` → the Accessibility toast.
  - Else `typeEdit(edit)`.
- Every state change that Settings shows calls `onStatusChange?()`.
- `setPairing(true)` creates a fresh `PairingCode(code: makeCode(), expires: now() + lifetime)` and clears `lastPairedName`. `setPairing(false)` clears both. Calling `setPairing(true)` while already pairing keeps the current code.
- `forgetAll()`: `store.save([])`. Send `.authFailed` to and **close** every authenticated session, so the page shows pairing.

```swift
// App/Volume.swift
nonisolated enum VolumeMode: String, Sendable { case auto, keys, system, app }
nonisolated enum VolumeRoute: Equatable, Sendable { case keys, system, app, unavailable }

extension VolumeRoute {
    /// L8. Pure, tested.
    static func choose(mode: VolumeMode, soundSourceRunning: Bool, systemSettable: Bool, launcherActive: Bool) -> VolumeRoute
    // auto: SS → keys; settable → system; active → app; else unavailable
    // keys → keys; system → settable ? system : unavailable; app → active ? app : unavailable
}

nonisolated enum VolumeFeedback: Equatable, Sendable {
    case level(Double, muted: Bool)   // 0…1
    case sentKeys
    case unavailable(String)
}

nonisolated struct AppVolume: Equatable, Sendable {
    var level = 100                   // 0…100
    var muted = false
    /// up/down ±5 clamped to 0…100 and unmute; mute toggles.
    mutating func apply(_ action: VolumeAction)
}

/// CoreAudio default output device (research). Reads the device on every call (HDMI may come and go).
nonisolated enum SystemVolume {
    static var isSettable: Bool { get }           // VirtualMainVolume exists and is settable
    static func level() -> Float32?
    static func setLevel(_ level: Float32)        // clamped 0…1
    static func isMuted() -> Bool?
    static func setMuted(_ muted: Bool)           // no-op if the mute property is missing/unsettable
    /// Pure, tested: up/down by 1/16 clamped to 0…1, snapped to the nearest 1/16.
    static func step(_ level: Float32, _ action: VolumeAction) -> Float32
}

final class VolumeController {
    static let soundSourceBundleID = "com.rogueamoeba.soundsource"
    init(mode: @escaping () -> VolumeMode, isLauncherActive: @escaping () -> Bool,
         applyAppVolume: @escaping (AppVolume) -> Void)
    private(set) var appVolume = AppVolume()
    func perform(_ action: VolumeAction) -> VolumeFeedback
}
```

`perform`:
- **keys:**
  - `SyntheticInput.canPost` → `postMediaKey(soundUp/soundDown/mute)`, then `.sentKeys`.
  - Else `.unavailable("Allow Accessibility for MMTVL on the Mac")`.
- **system:** up/down → `setLevel(step(level() ?? 0.5, action))`, and also unmute. mute → `setMuted(!(isMuted() ?? false))`. Return `.level(Double(level() ?? 0), muted: isMuted() ?? false)`.
- **app:** `appVolume.apply(action)`, `applyAppVolume(appVolume)`, then `.level(Double(level)/100, muted:)`.
- **unavailable:** `.unavailable("Volume can't be changed here")`.

SoundSource is detected with `NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == soundSourceBundleID }`.

`PhoneRemote` maps `VolumeFeedback`:
- `.level` → `.volume(level:, muted:)`
- `.sentKeys` → `.volume(level: nil, muted: nil)`
- `.unavailable(m)` → `.toast(m)`

```swift
// DesignSystem/QRCodeImage.swift
import CoreImage.CIFilterBuiltins
nonisolated enum QRCodeImage {
    /// Black modules on white, nearest-neighbor scaled ×10, no extra quiet zone (the view pads it).
    static func make(_ string: String) -> CGImage?
}
```

```swift
// Settings/SettingsTypes.swift additions
nonisolated enum SettingsPage { … case phoneRemote, pairPhone, confirmForgetPhones }
nonisolated enum SettingKey { … case phoneRemoteEnabled }            // keyPath \.phoneRemoteEnabled
nonisolated enum SettingsAction { … case forgetAllPhones }
nonisolated enum RowImage { … case qrCode(String) }

nonisolated struct PhoneRemoteSettingsStatus: Equatable, Sendable {
    var isRunning = false
    /// "Port 8765 is in use", "No network connection", "Starting…"; nil when fine.
    var problem: String?
    /// "http://192.168.1.20:8765"; nil without a LAN address.
    var address: String?
    /// While Pair a Phone shows.
    var pairingCode: String?
    /// address + "/#pair=" + code.
    var pairingURL: String?
    var lastPairedName: String?
    var pairedCount = 0
    var connectedCount = 0
    /// SyntheticInput.canPost.
    var canControlOtherApps = false
}
```

```swift
// App/AppSettings.swift additions (decodeIfPresent ?? default, like the others)
var phoneRemoteEnabled = true
/// Hand-edited. HTTP port; the WebSocket uses port + 1. Values outside 1024…65534 fall back to 8765.
var phoneRemotePort = 8765
/// Hand-edited "auto" | "keys" | "system" | "app" (L8). Stored as String; unknown values read as "auto".
var phoneRemoteVolume = "auto"
var volumeMode: VolumeMode { VolumeMode(rawValue: phoneRemoteVolume) ?? .auto }
var validatedPhoneRemotePort: Int { (1024...65534).contains(phoneRemotePort) ? phoneRemotePort : 8765 }
```
**Pitfall:** keep `phoneRemoteVolume` a `String` in the file. Decoding a typo'd enum would throw, and `JSONConfigFile` would then move the whole `settings.json` to `.bak` and reset every setting.

### Settings additions

Root page, section `input` ("Remote & Input"), a new last row:
- `SettingsRow(id: "phoneRemote", title: "Phone Remote", value: settings.phoneRemoteEnabled ? "On" : "Off", showsDisclosure: true, action: .push(.phoneRemote))`

**`.phoneRemote`** (title "Phone Remote", image `.symbol("iphone")`, hint "Select: choose · Back: return"):
- **Section `phone.server`:**
  - `phone.enabled` "Phone Remote", value On/Off, `.toggle(.phoneRemoteEnabled)`. Detail = `phoneRemote.problem`.
  - If enabled: info row `phone.address` "Address", value `address ?? "No network connection"`.
  - If enabled and running: `phone.pair` "Pair a Phone", disclosure, `.push(.pairPhone)`.
  - Footer: "Open the address in the phone's browser. The phone must be on the same network as this Mac."
- **Section `phone.phones`, title "Phones":**
  - Info row `phone.count` "Paired Phones", value `"\(pairedCount)"`, detail `"\(connectedCount) connected now"` when > 0.
  - If `pairedCount > 0`: `phone.forget` "Forget All Phones", disclosure, `.push(.confirmForgetPhones)`.
- **Section `phone.access`, title "Typing & Other Apps":**
  - Row `phone.accessibility` "Accessibility", value "Allowed"/"Not Allowed". Action `.requestAccessibility` (also when allowed, as on the root page).
  - Detail: "Needed to type from the phone and to control Plex, Prime Video and the browser".
  - Footer: "Volume buttons use SoundSource when it's running, else the Mac's volume when the output allows it, else MMTVL's own volume."

**`.pairPhone`** (title "Pair a Phone"; hint "Back: done"):
- Image: `.qrCode(pairingURL)` when `pairingURL` is set, else `.symbol("iphone")`.
- Section `pair`:
  - Info row `pair.code` "Pairing Code", value = `pairingCode ?? "—"`.
  - Info row `pair.address`: title = `address ?? "No network connection"`, detail "Or open this address on the phone and enter the code".
  - If `lastPairedName`: info row `pair.done` "Paired \"\(name)\"", image `.symbol("checkmark.circle")`.
  - `pair.close` "Done", `.pop`.
  - Footer: "Scan the code with the phone's camera. Pairing ends when you leave this page."

**`.confirmForgetPhones`** (title "Forget All Phones?", image `.symbol("iphone.slash")`, hint "Select: choose · Back: cancel"):
- `confirm.cancel` "Cancel" `.pop`
- `confirm.forget` "Forget All Phones" `.forgetAllPhones`
- Footer: "Every phone will need to pair again."

`perform(.forgetAllPhones)` → `environment.forgetAllPhones()`, `refreshStatus()`, `pop()`.

Pairing lifecycle in `SettingsModel`:
- `@ObservationIgnored private var isPairing = false`.
- `private func syncPairing()`:
  ```swift
  let active = page == .pairPhone
  guard active != isPairing else { return }
  isPairing = active
  environment.setPhonePairing(active)
  refreshStatus()
  ```
- Call it at the end of `push`, `pop` and `reset`.
- `func screenDidClose()`: `if isPairing { isPairing = false; environment.setPhonePairing(false); refreshStatus() }`.
- `refreshStatus()` also reads `phoneRemote = environment.phoneRemoteStatus()`.

`AppRouter.goHome()`: before `screen = .home`, add `if screen == .settings { settings.screenDidClose() }`. The PIN screen can't be opened from `.pairPhone`, so no other path leaves it open.

`RowImageView` `.qrCode(let string)`: a white `RoundedRectangle(cornerRadius: 24)` of `Theme.settingsQRCodeSize`. Inside it, `Image(decorative: cgImage, scale: 1).interpolation(.none).resizable().scaledToFit().padding(Theme.settingsQRCodeSize * 0.08)`, from `QRCodeImage.make(string)`. Fall back to `symbol("qrcode")` if nil. It ignores the `size` parameter. Theme: `static let settingsQRCodeSize: CGFloat = 440` (fits the 600-pt side column; ~25 cm tall on a 65" TV).

### AppDelegate wiring

New properties: `remoteServer: RemoteServer?`, `phoneRemote: PhoneRemote?`, `volume: VolumeController?`, `livePlayer: MPVPlayerController?`, `appActivationObserver: NSObjectProtocol?`.

In `applicationDidFinishLaunching`, after `router` exists and before `windowController.show()`:

```swift
let livePlayer = MPVPlayerController()            // also passed to LiveTVModel (replace the inline construction)
self.livePlayer = livePlayer
let volume = VolumeController(
    mode: { [weak self] in self?.settings.volumeMode ?? .auto },
    isLauncherActive: { NSApp.isActive },
    applyAppVolume: { [weak self] volume in
        self?.livePlayer?.setVolume(volume.level, muted: volume.muted)
        self?.youtube?.setVolume(volume.level, muted: volume.muted)
    }
)
self.volume = volume
let server = RemoteServer()
let phoneRemote = PhoneRemote(transport: server, store: .keychain, environment: PhoneRemoteEnvironment(
    isLauncherActive: { NSApp.isActive },
    dispatch: { [weak inputRouter] command, isGlobal in inputRouter?.dispatch(command, isGlobal: isGlobal) },
    canPostEvents: { SyntheticInput.canPost },
    postExternal: { key in
        switch key {
        case .key(let code): SyntheticInput.postKey(code)
        case .media(let media): SyntheticInput.postMediaKey(media)
        }
    },
    typeEdit: { edit in
        SyntheticInput.deleteBackward(edit.deletions)
        SyntheticInput.type(edit.insertion)
    },
    postReturn: { SyntheticInput.postKey(CGKeyCode(kVK_Return)) },
    launcherAcceptsText: { [weak router] in router?.screen == .youtube },
    frontAppName: { NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac" },
    volume: { [weak volume] action in volume?.perform(action) ?? .unavailable("Volume can't be changed here") },
    now: { Date() },
    makeCode: { PairingCode.random() },
    makeToken: { PhoneToken.make() }
))
server.onMessage = { [weak phoneRemote] id, data in phoneRemote?.receive(data, from: id) }
server.onSessionClosed = { [weak phoneRemote] id in phoneRemote?.sessionClosed(id) }
server.onStateChange = { [weak router] in router?.settings.refreshStatus() }
phoneRemote.onStatusChange = { [weak router] in router?.settings.refreshStatus() }
remoteServer = server
self.phoneRemote = phoneRemote
if settings.phoneRemoteEnabled { startPhoneRemote() }
observeAppActivation()   // NSWorkspace.didActivateApplicationNotification → phoneRemote?.frontAppChanged()
```

- **Order:** `SettingsModel` is created before the phone remote, and `makeSettingsEnvironment` closures capture `self` weakly, so the first status read returns a default `PhoneRemoteSettingsStatus` until `refreshStatus()` runs again. `startPhoneRemote()` triggers `onStateChange`, which refreshes it.
- `startPhoneRemote()`: `let port = settings.validatedPhoneRemotePort`, then `remoteServer?.start(httpPort: NWEndpoint.Port(integerLiteral: UInt16(port)), socketPort: … UInt16(port + 1))`. Log `"Phone remote on port \(port)"`.
- `stopPhoneRemote()`: `remoteServer?.stop()`; `phoneRemote?.reset()`.
- `applySettings`: if `phoneRemoteEnabled` changed → start/stop.
- `systemDidWake()`: if enabled and `remoteServer.state` is `.failed`, call `startPhoneRemote()` (the 10 s retry covers it too).
- `phoneRemoteSettingsStatus()` builds `PhoneRemoteSettingsStatus` from:
  - `remoteServer.state`: `.running` → `isRunning`; `.starting` → problem "Starting…"; `.failed(m)` → problem m.
  - `LocalAddress.primaryIPv4()` → `address = "http://\(ip):\(port)"`.
  - `phoneRemote.pairing?.code`, the URL, `lastPairedName`, `pairedCount`, `connectedCount`.
  - `SyntheticInput.canPost`.
- `SettingsEnvironment` additions:
  ```swift
  phoneRemoteStatus: { [weak self] in self?.phoneRemoteSettingsStatus() ?? PhoneRemoteSettingsStatus() },
  setPhonePairing: { [weak self] in self?.phoneRemote?.setPairing($0) },
  forgetAllPhones: { [weak self] in self?.phoneRemote?.forgetAll() },
  ```
- The existing `requestAccessibility()` also calls `SyntheticInput.requestAccess()`. It's harmless when already granted; if PostEvent is ever separate from Accessibility, this prompts for it.

### Phone page (`MMTVL/RemoteServer/Web/`)

`remote.html`:
- `<!doctype html>`, `lang="en"`, `<meta charset="utf-8">`.
- `<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">`.
- `<meta name="apple-mobile-web-app-capable" content="yes">`, `<meta name="mobile-web-app-capable" content="yes">`, `<meta name="theme-color" content="#000000">`.
- `<title>MMTVL Remote</title>`, `<link rel="stylesheet" href="remote.css">`, `<script src="remote.js" defer></script>`.
- Three views, one visible at a time:
  - `#connecting`: "Connecting to MMTVL…".
  - `#pairing`: heading "Pair with MMTVL"; text "On the TV, open Settings → Phone Remote → Pair a Phone, then enter the code."; a `<form id="pair-form">` with `<input id="pair-code" inputmode="numeric" pattern="[0-9]*" maxlength="4" autocomplete="one-time-code">` and a Pair button; `<p id="pair-error">`.
  - `#remote`:
    - A top bar with `#front-app` (the app name).
    - The D-pad: a circle with `up/left/right/down` buttons (`data-command`, `data-repeat`) around a center `select` button labeled OK.
    - A row: Back (`back`), Home (`home`), Play/Pause (`playPause`).
    - A row: Rewind (`rewind`), Keyboard (`#keyboard-open`), Fast Forward (`fastForward`).
    - A row: `data-volume="down"`, `data-volume="mute"`, `data-volume="up"`.
    - The `#keyboard` panel (hidden): `<form id="text-form">` with `<input id="text" type="text" autocapitalize="off" autocomplete="off" autocorrect="off" spellcheck="false" enterkeyhint="search">` and a Done button `#keyboard-close`.
  - `#toast` (fixed, bottom).
- Use Unicode or inline SVG glyphs for icons (◀ ▶ ▲ ▼, ⏯, ⏪, ⏩, ⌂, ↩, 🔈, 🔇, 🔊, ⌨). No external resources.

`remote.css`:
- Black background, SF system font (`-apple-system, system-ui`), light-gray buttons `#2c2c2e` with white glyphs, a `.pressed` state (lighter, scaled 0.95).
- D-pad about 72 vw, max 340 px, as a CSS grid in a circle.
- `touch-action: manipulation; user-select: none; -webkit-user-select: none; -webkit-touch-callout: none;` on buttons.
- `padding: env(safe-area-inset-*)`. Everything fits on one phone screen without scrolling. The `[hidden]` attribute must win: `[hidden] { display: none !important; }`.

`remote.js` (complete logic; adjust markup names if needed, keep behavior):

```js
'use strict';
const TOKEN_KEY = 'mmtvl.token';
const $ = (id) => document.getElementById(id);
let ws = null;
let retryDelay = 1000;
let retryTimer = null;
let toastTimer = null;

function storedToken() { try { return localStorage.getItem(TOKEN_KEY); } catch { return null; } }
function storeToken(t) { try { t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY); } catch {} }
function socketURL() { return `ws://${location.hostname}:${Number(location.port || 80) + 1}/`; }
function send(obj) { if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj)); }
function hashCode() { const m = location.hash.match(/pair=(\d{4})/); return m ? m[1] : null; }
function clearHash() { history.replaceState(null, '', location.pathname); }
function phoneName() {
  const ua = navigator.userAgent;
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua)) return 'iPad';
  if (/Android/.test(ua)) return 'Android phone';
  return 'Browser';
}
function show(view) { for (const v of ['connecting', 'pairing', 'remote']) $(v).hidden = v !== view; }
function toast(text) {
  $('toast').textContent = text; $('toast').hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { $('toast').hidden = true; }, 2000);
}

function connect() {
  clearTimeout(retryTimer);
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;
  show('connecting');
  const socket = new WebSocket(socketURL());
  ws = socket;
  socket.onopen = () => {
    retryDelay = 1000;
    const token = storedToken();
    const code = hashCode();
    if (token) send({ type: 'hello', token });
    else if (code) send({ type: 'pair', code, name: phoneName() });
    else show('pairing');
  };
  socket.onmessage = (e) => { try { handle(JSON.parse(e.data)); } catch {} };
  socket.onclose = () => {
    if (ws !== socket) return;
    ws = null; show('connecting');
    retryTimer = setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, 10000);
  };
}

function handle(m) {
  switch (m.type) {
    case 'welcome': show('remote'); break;
    case 'paired': storeToken(m.token); clearHash(); show('remote'); break;
    case 'authFailed':
      storeToken(null);
      if (hashCode()) send({ type: 'pair', code: hashCode(), name: phoneName() }); else show('pairing');
      break;
    case 'pairFailed': clearHash(); $('pair-error').textContent = m.message; show('pairing'); break;
    case 'status': $('front-app').textContent = m.launcherActive ? 'MMTVL' : m.frontApp; break;
    case 'toast': toast(m.message); break;
    case 'volume':
      if (typeof m.level === 'number') toast(m.muted ? 'Muted' : `Volume ${Math.round(m.level * 100)}%`);
      break;
  }
}

function bindButtons() {
  for (const b of document.querySelectorAll('[data-command]')) {
    let delay = null, interval = null;
    const command = b.dataset.command;
    const stop = () => { clearTimeout(delay); clearInterval(interval); b.classList.remove('pressed'); };
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      b.classList.add('pressed');
      send({ type: 'command', command });
      if (navigator.vibrate) navigator.vibrate(10);
      if (b.hasAttribute('data-repeat')) {
        delay = setTimeout(() => { interval = setInterval(() => send({ type: 'command', command }), 120); }, 450);
      }
    });
    for (const t of ['pointerup', 'pointercancel', 'pointerleave']) b.addEventListener(t, stop);
  }
  for (const b of document.querySelectorAll('[data-volume]')) {
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); send({ type: 'volume', action: b.dataset.volume }); });
  }
}

function bindKeyboard() {
  const input = $('text');
  $('keyboard-open').addEventListener('click', () => {
    $('keyboard').hidden = false; input.value = ''; send({ type: 'textBegin' }); input.focus();
  });
  $('keyboard-close').addEventListener('click', () => { input.blur(); $('keyboard').hidden = true; });
  input.addEventListener('input', () => send({ type: 'text', value: input.value }));
  $('text-form').addEventListener('submit', (e) => {
    e.preventDefault(); send({ type: 'submit' }); input.value = ''; send({ type: 'textBegin' });
  });
}

function bindPairing() {
  $('pair-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const code = $('pair-code').value.trim();
    if (/^\d{4}$/.test(code)) { $('pair-error').textContent = ''; send({ type: 'pair', code, name: phoneName() }); }
  });
}

document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') connect(); });
bindButtons(); bindKeyboard(); bindPairing(); connect();
```
Keyboard `click` (not `pointerdown`) is deliberate. iOS only opens the soft keyboard when `focus()` runs inside a click-type user gesture.

### Theme additions

- `static let settingsQRCodeSize: CGFloat = 440`

## Implementation steps

The project must build after every step. Run the full test suite at the end of each step (`xcodebuild … test`).

- [x] **1. Synthetic input and event tagging**: files: `Input/SyntheticInput.swift`, `Input/ExternalKeyMap.swift`, `Input/InputRouter.swift`, `Input/GlobalEventTap.swift`, `MMTVLTests/SyntheticInputTests.swift`
  - Write `SyntheticInput` and `ExternalKeyMap` as in *Key types*. `import Carbon.HIToolbox` for `kVK_*`.
  - `InputRouter.start()`: first line inside the monitor closure is `if let cg = event.cgEvent, SyntheticInput.isOwn(cg) { return event }`.
  - `globalEventTapCallback`: before building `tapEvent`, `if SyntheticInput.isOwn(event) { return Unmanaged.passUnretained(event) }`. `SyntheticInput` is `nonisolated`, so this is fine in the C callback. Keep the check before `MainActor.assumeIsolated`.
  - `isOwn`: `event.getIntegerValueField(.eventSourceUserData) == marker || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())`.
  - Tests: `chunks` ("" → [], 45 ASCII chars → 20/20/5, a string of 15 "👍🏽" (4 UTF-16 each) → chunks of 5 emoji, never splitting one; "é" composed stays whole); `ExternalKeyMap` table (all ten commands); `isOwn` on a `CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!` with the marker set → true, without → false. Don't post events in tests.
  - Done when: tests pass. **Manual spike (the executor, dev Mac, Accessibility granted to MMTVL):** in a temporary `#if DEBUG` block in `applicationDidFinishLaunching`, schedule `SyntheticInput.type("hi")` 5 s after launch. Run windowed with TextEdit frontmost and confirm "hi" appears and `CGPreflightPostEventAccess()` was true (log it). **Remove the block before finishing the step.** If typing doesn't arrive, record it in *Deviations* and stop. If the executor can't run UI checks (M3/M4 note: synthesized keys reached Terminal), hand this check to the user's list and continue.

- [x] **2. Messages, text diff and LAN address**: files: `RemoteServer/RemoteMessage.swift`, `RemoteServer/TextEdit.swift`, `RemoteServer/LocalAddress.swift`, `MMTVLTests/RemoteMessageTests.swift`, `MMTVLTests/TextEditTests.swift`, `MMTVLTests/LocalAddressTests.swift`
  - As in *Key types*.
  - Done when tests pass:
    - **Decode:** every client type round-trips from the JSON in the wire table. Unknown type, unknown command ("jump"), missing field and invalid JSON → nil.
    - **Encode:** every server message encodes to exactly the JSON in the table (sorted keys, nil omitted); compare by re-parsing with `JSONSerialization`.
    - **TextEdit:** ""→"abc" = (0,"abc"); "abc"→"ab" = (1,""); "teh"→"the" = (2,"he"); "abc"→"abc" = empty; "a👍🏽"→"a" = (1,""); "abc"→"" = (3,"").
    - **LocalAddress.pick:** en0 preferred over en1 and others; skips loopback, down and 169.254; empty → nil.
    - **Real call:** `LocalAddress.interfaces()` returns without crashing.

- [x] **3. HTTP parsing and web assets (placeholder page)**: files: `RemoteServer/HTTPRequest.swift`, `RemoteServer/RemoteWebAssets.swift`, `RemoteServer/Web/remote.html`, `remote.css`, `remote.js`, `MMTVLTests/HTTPRequestTests.swift`
  - Placeholder web files: `remote.html` with the final `<head>` (meta, links) and `<body><p>MMTVL Remote</p></body>`; `remote.css` and `remote.js` with one comment line each. The real page comes in step 10.
  - Check the built app: `ls build/Build/Products/Debug/MMTVL.app/Contents/Resources/` lists `remote.html`, `remote.css`, `remote.js`. If they are missing or nested differently, note it in *Deviations* and fix `RemoteWebAssets.data` (e.g. `subdirectory:`).
  - Done when tests pass:
    - Parse a full GET head → `.complete(GET, "/")`; `"/remote.js?v=1"` → path `"/remote.js"`; a partial head → `.incomplete`; 17 KB without a terminator → `.tooLarge`; `"garbage\r\n\r\n"` → `.invalid`.
    - Assets: `/`, `/index.html`, `/remote.css`, `/remote.js` map correctly; `/../Info.plist`, `/remote.swift`, `/favicon.ico` → nil; `RemoteWebAssets.data` for each asset is non-nil (the host app bundle has them).
    - Response bytes: status line, `Content-Length` equals body count, HEAD omits the body but keeps the length.

- [x] **4. Pairing and the phone store**: files: `RemoteServer/Pairing.swift`, `MMTVLTests/PairingTests.swift`
  - Done when tests pass:
    - `PairingCode.check`: right code → accepted; expired → expired; four wrong → rejected each time with `failures` counting; the fifth wrong → `.rotated` with the new code from `makeCode` and failures 0.
    - `random()` is always 4 digits.
    - `PhoneToken.make()` is 43 chars of `[A-Za-z0-9_-]` and differs between calls. `hash` of "abc" equals the known SHA-256 hex `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
    - `PairedPhoneStore.inMemory` saves and loads.
    - A Keychain round-trip under a **test account** (`PairedPhoneStore` with a `keychain(account:)` factory). Follow `KeychainTests`' pattern: a unique account, removed at the end.

- [x] **5. The network server**: files: `RemoteServer/RemoteServer.swift`, `MMTVLTests/RemoteServerTests.swift`
  - As in *Key types* and *Server behavior*. Log state changes and session counts (category `PhoneRemote`); never message contents (L13).
  - Integration test (`@Suite(.serialized)`):
    1. Start on `.any`/`.any` and wait up to 5 s (poll every 50 ms) for `.running`.
    2. `URLSession.shared.data(from: http://localhost:<httpPort>/)` → 200, `text/html`, body contains "MMTVL Remote". `/nope` → 404.
    3. `URLSessionWebSocketTask` to `ws://localhost:<socketPort>/`, with `onMessage` echoing `.toast("echo")` via `server.send`. Send a text message and receive the toast JSON. This proves the metadata send path.
    4. `stop()` → state `.stopped`, `onSessionClosed` fired once.
  - **ATS fallback:** if the URLSession loads fail with NSURLErrorAppTransportSecureConnectionFailed (−1022), replace the HTTP check with an `NWConnection` client that sends `"GET / HTTP/1.1\r\nHost: x\r\n\r\n"` and reads the reply. Replace the WebSocket check with an `NWConnection` using a client `NWProtocolWebSocket.Options()`. Record it in *Deviations*.
  - Done when the integration test passes. The app isn't wired until step 9, so there's no manual check here.

- [x] **6. Volume**: files: `App/Volume.swift`, `IPTV/Player/LivePlayer.swift`, `YouTube/YouTubeKeyMap.swift`, `YouTube/YouTubeController.swift`, `MMTVLTests/VolumeTests.swift`, `MMTVLTests/YouTubeKeyMapTests.swift`
  - `MPVPlayerController.setVolume(_ level: Int, muted: Bool)`:
    - Store `appVolume` (level, muted). If `mpv` exists, `mpv.setString("volume", "\(level)")` and `mpv.setString("mute", muted ? "yes" : "no")`.
    - In `prepare()`, right after creating the core, apply the stored values if they differ from (100, false).
    - Not on the `LivePlayer` protocol (AppDelegate calls the concrete class), so `FakePlayer` doesn't change.
  - `YouTubeKeyMap.volumeScript` (document start, main frame), added to the user-script loop in `open()`:
    ```js
    (() => {
      let level = 1, muted = false;
      const apply = (v) => { v.volume = level; v.muted = muted; };
      window.__mmtvlSetVolume = (l, m) => { level = l; muted = m; document.querySelectorAll('video, audio').forEach(apply); };
      for (const t of ['play', 'loadedmetadata']) {
        document.addEventListener(t, (e) => { if (e.target instanceof HTMLMediaElement) apply(e.target); }, true);
      }
    })();
    ```
  - `YouTubeKeyMap.setVolumeScript(level: Int, muted: Bool) -> String` returns `"window.__mmtvlSetVolume && window.__mmtvlSetVolume(\(Double(level) / 100), \(muted)); 'ok'"`.
  - `YouTubeController.setVolume(_ level: Int, muted: Bool)`:
    - Store the values. If `webView` exists, evaluate the script and log errors.
    - Re-apply in `didFinishLoading()` when they're not the defaults (a reload resets the page's values).
    - Not on `YouTubeHosting`.
  - Done when:
    - Tests pass: `VolumeRoute.choose` covers all four modes × the relevant flags. `AppVolume.apply`: 100 + up stays 100; 3 × down = 85; mute toggles; up unmutes. `SystemVolume.step`: 0.5 + up = 0.5625; 0 + down = 0; 0.97 + up = 1; snapping 0.51 + up = 0.5625. `setVolumeScript` format.
    - Manual (dev Mac, built-in speakers or headphones): a temporary `#if DEBUG` call `VolumeController(...).perform(.up)` logs the route and new level. Remove it afterwards.
    - **SoundSource check (needs the user):** with SoundSource running and its output set to a device without macOS volume (or Super Volume Keys on), does `SyntheticInput.postMediaKey(NXKey.soundUp)` change SoundSource's volume? Record the answer in *Deviations*. If not, the plan's fallback is the user setting `"phoneRemoteVolume": "app"` on the mini, and the master plan's Q8 gets the answer.

- [x] **7. PhoneRemote coordinator**: files: `RemoteServer/PhoneRemote.swift`, `MMTVLTests/PhoneRemoteTests.swift`, `MMTVLTests/FakeTransport.swift`
  - `FakeTransport: RemoteTransport` records `sent: [(RemoteSessionID, ServerMessage)]` and `closed: [RemoteSessionID]`. A test helper builds `PhoneRemote` with an in-memory store and an environment backed by a recorder (active flag, dispatched commands, posted keys, edits, returns, volume results, fixed `now`, codes "1234", "5678", …, tokens "tok1", "tok2", …).
  - Done when tests pass:
    - **Unauthenticated:** `command`/`text`/`volume`/`submit` are ignored (nothing dispatched or posted, nothing sent).
    - **Bad `hello`:** `.authFailed`, session still open (not closed).
    - **`pair` without pairing** → `pairFailed`.
    - **Pairing:** `setPairing(true)` → `pairing.code == "1234"`. A wrong code → "Wrong code". The fifth wrong → rotated to "5678" and the rotated message. The right code → `.paired("tok1")` then `.status`; the store has one phone with `hash("tok1")`; `lastPairedName` is set; `onStatusChange` fired.
    - **Hello after pairing:** a new session with `hello("tok1")` → `.welcome`, `.status`.
    - **Expired:** `now` past expiry → `pairFailed`.
    - **11 pairings** → 10 stored, the oldest dropped.
    - **Commands (L5):** active → `dispatch(c, false)`. Inactive `.home` → `dispatch(.home, true)`. Inactive `.up` with post access → `postExternal(.key(126))`; without → Accessibility toast. Inactive `.playPause` → `.media(16)`.
    - **Text (L7):** "s" then "st" → edits (0,"s"), (0,"t"). `textBegin` then "x" → (0,"x"). Active and `launcherAcceptsText == false` → "Nothing to type into here" and no edit. Active and accepting → edit. Inactive without post access → Accessibility toast. Over 1000 chars → ignored.
    - **Submit** → `postReturn`, then "a" → (0,"a").
    - **Volume** feedback mapping, all three cases.
    - **`forgetAll`:** store empty; authenticated sessions get `.authFailed` and are closed; unauthenticated sessions untouched.
    - **`frontAppChanged`** sends `.status` only to authenticated sessions.
    - **`sessionClosed`** decrements `connectedCount`.
    - **`setPairing(false)`** clears the code and `lastPairedName`.

- [x] **8. Settings: Phone Remote pages and QR code**: files: `App/AppSettings.swift`, `Settings/SettingsTypes.swift`, `Settings/SettingsEnvironment.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsRowView.swift`, `DesignSystem/QRCodeImage.swift`, `DesignSystem/Theme.swift`, `Launcher/AppRouter.swift`, `App/AppDelegate.swift` (stub closures only), `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsPhoneRemoteTests.swift`, `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/AppRouterTests.swift`
  - As in *Settings additions*. In `AppDelegate.makeSettingsEnvironment`, wire the three new closures to stubs (`PhoneRemoteSettingsStatus()`, no-ops) for now; step 9 replaces them.
  - `SettingsRecorder` gains `phoneRemote = PhoneRemoteSettingsStatus()`, `pairingCalls: [Bool]`, `forgets = 0`.
  - Done when tests pass:
    - **AppSettings:** missing keys → defaults (true, 8765, "auto"); `"phoneRemoteVolume": "bogus"` decodes and `volumeMode == .auto`; port 80 → `validatedPhoneRemotePort == 8765`; an old file without the keys still decodes.
    - **Root:** has `phoneRemote` with value On/Off.
    - **`.phoneRemote` page:** rows vary with enabled/running/pairedCount (pair row only when running; forget row only when count > 0); toggle applies `phoneRemoteEnabled`.
    - **Pairing calls:** pushing `.pairPhone` → `pairingCalls == [true]`; Back → `[true, false]`. `reset()` while on it → false. `screenDidClose()` while on it → false; while elsewhere → no call.
    - **Page image:** `.qrCode(url)` when `pairingURL` is set.
    - **Forget all:** the confirm page → `forgets == 1` and pops.
    - **Router:** `goHome()` from Settings on the pair page → the recorder sees `false`.
    - **QR:** `QRCodeImage.make("http://192.168.1.20:8765/#pair=1234")` returns an image whose width is a multiple of 10.
  - Windowed run: Settings → Remote & Input → Phone Remote shows the page (status stubbed). The QR rendering is checked in step 9.

- [x] **9. Wire it up**: files: `App/AppDelegate.swift`
  - As in *AppDelegate wiring*.
  - Done when (windowed run, `open build/Build/Products/Debug/MMTVL.app --args -windowed YES`):
    - The log shows "Phone remote on port 8765".
    - `curl -i http://localhost:8765/` → 200 HTML. `curl -i http://localhost:8765/x` → 404. `curl -i -X POST http://localhost:8765/` → 405.
    - Settings → Phone Remote shows the LAN address. Pair a Phone shows a QR code and a code; Back ends pairing (log line).
    - In Safari on the Mac, open `http://localhost:8765/#pair=<code>` with the placeholder page. It's only a `<p>`, so test the socket from Safari's console instead: `ws = new WebSocket('ws://localhost:8766/'); ws.onmessage = e => console.log(e.data); ws.onopen = () => ws.send(JSON.stringify({type:'pair', code:'<code>', name:'Mac Safari'}))` → `paired` + `status`. Then `ws.send(JSON.stringify({type:'command', command:'down'}))` moves Settings focus. Settings shows Paired Phones 1, and `Paired "Mac Safari"` on the pair page.
    - Toggle Phone Remote off → curl fails to connect; on → works again.
    - Settings → Phone Remote → Forget All Phones → count 0.
    - If the executor can't drive the UI, hand these checks to the user's list (as in M4) and continue.

- [x] **10. The phone page**: files: `RemoteServer/Web/remote.html`, `remote.css`, `remote.js`
  - As in *Phone page*. Keep `<title>MMTVL Remote</title>` and the body text "MMTVL Remote" in the pairing view (the step 5 test checks "MMTVL Remote").
  - Done when:
    - The test suite still passes.
    - In Safari on the Mac (responsive design mode, iPhone size) at `http://localhost:8765/`: unpaired → the pairing form; entering the TV code → the remote. Buttons drive MMTVL (focus moves, Select opens tiles). Holding Down repeats. Home returns home.
    - Reloading the page goes straight to the remote (token saved).
    - After Forget All Phones, the page shows pairing again.
    - Keyboard: with YouTube open on its search screen, typing "cats" fills leanback's search, backspace deletes, Enter submits.

- [x] **11. Docs**: files: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan
  - CLAUDE.md:
    - `settings.json`: `phoneRemoteEnabled`, hand-edited `phoneRemotePort` (WebSocket = port + 1) and `phoneRemoteVolume` (`auto|keys|system|app`).
    - Keychain account `phone-remote-phones` and the Mac-side reset command.
    - The web files live in `MMTVL/RemoteServer/Web/` and ship as flat bundle resources.
    - The phone URL is `http://<Mac IP>:8765/`; give the Mac mini a DHCP reservation.
    - Debug: `curl -i http://localhost:8765/`; `log stream … AND category == "PhoneRemote"`.
    - Never log tokens, codes or typed text.
    - Synthetic events are tagged (L6). Input code must keep passing `SyntheticInput.isOwn` events through.
  - Master plan: M5 status `Done` once *Manual verification* passes (`In progress` until then); update Q8 with the SoundSource answer.
  - Done when the docs match the code.

## Tests

New test files (Swift Testing):
- `SyntheticInputTests`: chunking, `ExternalKeyMap`, `isOwn`.
- `RemoteMessageTests`: decode/encode of every message; invalid inputs.
- `TextEditTests`: diff cases, including grapheme clusters.
- `LocalAddressTests`: `pick` rules.
- `HTTPRequestTests`: head parsing, asset allow-list, response bytes.
- `PairingTests`: code checks and rotation, tokens and hash, in-memory and Keychain store.
- `RemoteServerTests` (serialized): HTTP 200/404 and a WebSocket round-trip on ephemeral ports.
- `VolumeTests`: route choice, `AppVolume`, `SystemVolume.step`.
- `PhoneRemoteTests` + `FakeTransport`: auth, pairing, routing, text, volume, forget-all, status.
- `SettingsPhoneRemoteTests`: pages, pairing lifecycle, forget confirm, QR image.

Changed: `SettingsTestSupport` (new environment closures), `AppSettingsTests` (new keys), `AppRouterTests` (goHome ends pairing), `YouTubeKeyMapTests` (volume script).

Commands:
```sh
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test -only-testing:'MMTVLTests/PhoneRemoteTests'
```

## Manual verification

On the Mac mini (kiosk mode) with a real iPhone and, if available, an Android phone, both on the same Wi-Fi:

- [x] Settings → Phone Remote → Pair a Phone shows a QR code readable from the couch. The iPhone camera opens the page, which pairs without typing a code. The TV shows `Paired "iPhone"`.
- [x] The Android phone pairs by opening the address and typing the 4-digit code.
- [x] Five wrong codes from a phone rotate the code on the TV.
- [x] Leaving the Pair page, then trying to pair → "Open Settings → Phone Remote → Pair a Phone on the TV".
- [x] D-pad, OK, Back, Home, Play/Pause, Rewind and Fast Forward work on the home screen, in Settings, in YouTube, in Live TV (channel up/down, seek) and on the PIN keypad. Holding an arrow repeats smoothly.
- [x] With **Plex HTPC** in front: arrows move, OK selects, Back goes back, Play/Pause toggles playback. Note what Rewind/FF do (seek or skip) and record it in *Deviations*. Home returns to MMTVL and Plex keeps running.
- [x] With **Brave** in front: typing from the phone fills the address bar or page search; Enter submits. With **Prime Video**: arrows and OK work; typing in its search works (record if not).
- [x] YouTube search: typing, backspace, autocorrected words and Enter all behave (no stray characters).
- [x] Typing on the home screen shows "Nothing to type into here" on the phone and no beep on the TV.
- [x] **Volume with SoundSource running:** up/down/mute change the HDMI volume (SoundSource HUD or level changes).
- [x] **Volume with SoundSource quit:** on HDMI, in Live TV and YouTube, up/down/mute change MMTVL's playback volume and the phone shows the level. With Plex in front → "Volume can't be changed here". On the dev Mac's speakers, the Mac's volume changes.
- [x] Phone locked for a minute, then unlocked → the page reconnects by itself (shows "Connecting…" briefly).
- [x] Settings → Relaunch MMTVL → phones reconnect within ~10 s (no "port in use").
- [x] Sleep and wake the Mac → phones reconnect.
- [x] Forget All Phones → every phone shows the pairing form.
- [x] Phone Remote off in Settings → the page can't connect. On again → it works.
- [x] If the macOS firewall is on: no lingering "accept incoming connections" alert (allow it once with the mouse if shown).
- [x] `log stream --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "PhoneRemote"' --level info` while pairing and typing: no codes, tokens or typed text appear.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| The local monitor doesn't see `eventSourceUserData` on our own posted events | Typing a backspace in YouTube acts as Back; "Unbound key 0" logs while typing | `isOwn` already also checks `eventSourceUnixProcessID`. If both fail, post to MMTVL's own window with `NSApp.postEvent` for the YouTube case, and skip tagging there. Record it. |
| SoundSource ignores synthetic volume keys | Step 6 SoundSource check; volume unchanged on the mini | Set `"phoneRemoteVolume": "app"` on the mini (in-app volume in MMTVL; none in Plex). Ask the user whether to look for SoundSource scripting later. |
| An app ignores `keyboardSetUnicodeString` text (types "a"s) | Manual check in Brave/Plex/Prime | For ASCII letters/digits in that case, post real key codes through a US-layout table (`kVK_ANSI_*` + shift). Ask before adding; scope it to the failing app. |
| `NSApp.activate()` is refused when Home comes from the phone (no user input event; macOS 14+ cooperative activation) | Phone Home while Plex is in front doesn't bring MMTVL forward | Before `windowController.show()`, call `NSRunningApplication.current.activate(from: NSWorkspace.shared.frontmostApplication!, options: [])`, or as a last resort post a tagged synthetic Home key event so the existing event-tap path runs. Record it. |
| Port 8765 is taken on the Mac mini | Settings shows "Port 8765 is in use" | Set `phoneRemotePort` in `settings.json` (WebSocket uses +1), relaunch. |
| The Mac's IP changes (DHCP) | The bookmarked page stops loading | DHCP reservation on the router (documented). Re-scan the QR code otherwise. |
| iOS forgets `localStorage` for the http origin, or the Home Screen app has separate storage | The phone asks to pair again | Accept (pairing takes seconds). Document "pair from the Home Screen icon". |
| Media keys don't reach Plex (Now Playing routing) | Play/Pause does nothing in Plex | Map `playPause` to Space (`kVK_Space`) in `ExternalKeyMap` for external apps. Record it. |
| ATS blocks the test's `http://localhost` | −1022 in `RemoteServerTests` | The `NWConnection` client fallback in step 5. |
| The firewall blocks incoming connections | Phone can't load the page; the firewall is on | System Settings → Network → Firewall → Options → allow MMTVL. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-10-06 (planner): user choices.**
  - Volume: SoundSource (installed on the mini), else system volume, else in-app volume.
  - The phone controls other apps with keys and text (no trackpad).
  - Pairing happens via a QR code in Settings.
- **2026-10-06 (executor), step 1: `isOwn` test.** A `CGEvent` created in-process already carries our PID in `eventSourceUnixProcessID`, so the planned "without the marker → false" check was true. The test now also sets that field to another PID (1) before expecting false. Code unchanged.
- **2026-10-06 (executor), step 1: typing spike passed.** `CGPreflightPostEventAccess()` was true for MMTVL (Accessibility granted) and `SyntheticInput.type("hi")` typed "hi" into a TextEdit document. The spike block was removed.
- **2026-10-06 (executor), step 4: `PairingCode.check` is `mutating`.** The planned non-mutating signature couldn't count `failures` across calls. It now increments `failures` itself and, on rotation, also replaces itself with the returned fresh code.
- **2026-10-06 (executor), step 6: system volume on the dev Mac.** A temporary `VolumeController` forced to `.system` on the Mac Studio speakers logged `settable true`, then up 0.5 → 0.5625 and down → 0.5, as planned. The speakers were already muted, and `setMuted(false)` after up/down did **not** unmute them: the mute property is settable and a no-op set returns `noErr`, but it still read muted afterwards. I didn't unmute the user's Mac to dig further. The system route isn't used on the mini (HDMI has no macOS volume), so this only matters on a Mac with speakers. **For the user:** check it on the dev Mac (unmuted, phone volume up/down/mute) during manual verification. Spike removed.
- **2026-10-06 (executor), step 6: SoundSource check handed to the user.** Whether SoundSource's Super Volume Keys reacts to synthetic volume keys can't be judged on the dev Mac: its speakers have a macOS volume, so the system acts on volume keys anyway. Check it on the mini (see *Manual verification*); Q8 stays open until then.
- **2026-10-06 (executor), step 8: `SettingsModelTests` updated.** The new root row `phoneRemote` (last in Remote & Input) shifted two focus-position tests (`upDownMovesAndClamps`, `accessibilityRowRequestsAccess`). Each now presses Down once more. That file wasn't in the step's list.
- **2026-10-06 (executor), step 9: checks run.** In a windowed run, the log showed "Phone remote on port 8765". curl returned `/` → 200 HTML, `/x` → 404, POST → 405, HEAD `/remote.js` → 200 with no body, and the LAN IP → 200. A launcher PIN is set on the dev Mac, so the executor couldn't open Settings. A temporary DEBUG spike started pairing at launch instead (code written to a scratchpad file, not logged; removed afterwards). A Swift WebSocket client then checked:
  - unauthenticated `command` → ignored; bad `hello` → `authFailed`; `pair` without pairing → the "Open Settings…" message; invalid JSON → ignored
  - wrong code → "Wrong code"; right code → `paired` + `status`
  - typing on the home screen → "Nothing to type into here"
  - **phone Home while Terminal was frontmost brought MMTVL forward**, so the `NSApp.activate()` risk didn't occur on the dev Mac
  - the PhoneRemote log had no codes, tokens or typed text
  - The test phones were then removed from the Keychain.
  - **Observation:** the `status` pushed from `didActivateApplicationNotification` when MMTVL comes forward says `frontApp: "MMTVL", launcherActive: false`, because `NSApp.isActive` isn't true yet when the notification fires. The page shows "MMTVL" either way (it falls back to `frontApp`), so I left it.
  - **Left for the user (needs the PIN):** Settings → Phone Remote shows the LAN address; Pair a Phone shows a QR code and the code; Back ends pairing (log "Pairing ended"); the Paired Phones count; Phone Remote off/on; Forget All Phones.
- **2026-10-06 (executor), step 9: Q8 answered on the dev Mac.** The default output was a FiiO USB DAC (no macOS volume). A phone volume button (auto route → keys, since SoundSource is running) made **SoundSource's volume HUD for the DAC appear**, so Super Volume Keys reacts to MMTVL's synthetic volume keys. One up and one down were sent, so the level is unchanged. Still confirm on the mini over HDMI.
- **2026-10-06 (executor), step 10: page details and checks.**
  - The volume buttons use small inline SVG speakers, because the 🔈/🔇/🔊 glyphs render as color emoji even with U+FE0E.
  - Added a `contextmenu` blocker so long presses (held arrows) don't open the browser menu, and a `pressed` state on the volume buttons. The pairing view has a "MMTVL Remote" label above its heading.
  - Rendered at 390×760 in WebKit: everything fits without scrolling.
  - End-to-end in a WKWebView against the live server (temporary pairing spike, since removed): `http://localhost:8765/#pair=<code>` paired, cleared the hash, saved the token and showed the remote. A reload reconnected straight to the remote with `hello`.
  - **Left for the user:** the Safari responsive-mode checks that need Settings (the PIN): buttons driving MMTVL, hold-to-repeat, Home, Forget All → pairing form, and YouTube search typing.
- **2026-10-06 (executor), step 11: status stays `In progress`.** Step 11 says M5 is `Done` only once *Manual verification* passes, which needs the Mac mini, phones and the PIN-guarded Settings checks. Every implementation step is done; this plan and the master plan's M5 row stay `In progress` until the user signs off.
- **2026-10-06 (user): manual checks accepted.** The user accepted all remaining manual checks (the executor's step 9/10 hand-offs, the dev-Mac system-volume mute check and the *Manual verification* list) without separate reports. M5 is `Done`.
