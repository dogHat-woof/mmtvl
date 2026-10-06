# M7b — Phone & casting

| | |
|---|---|
| Status | In progress |
| Depends on | M7 (and M3 YouTube, M5 phone remote) |
| Master plan decisions used | D1, D3, D4, D5, D9, D10, D11, D12, D15, D17, D18, D19, D20, D21, D24, D28; new **D30** (YouTube DIAL receiver), **D31** (phone trackpad and home-screen icon), **D32** (Android screen mirroring through Reflector) |
| Planned | 2026-10-06 |

## Goal

From the couch:

- **Cast from the YouTube app without a TV code.** On any phone on the home network, the YouTube app's Cast button lists **"MMTVL"**. Picking it switches the TV to YouTube (from the home screen, Live TV, Settings, or another app like Plex) and the phone controls playback, as with a smart TV. YouTube's *Link with TV Code* keeps working.
- **Android screen mirroring through Reflector 4** (Squirrels; Google Cast receiver). On an Android phone, Quick Settings → Cast → **"MMTVL Screen Mirroring"** puts the phone's screen on the TV:
  - *Before:* MMTVL keeps Reflector running hidden in the background (starts it at launch and after wake, restarts it if it quits). Reflector receives **Google Cast only**; iPhones keep using macOS's own AirPlay Receiver (user choice 2026-10-06).
  - *Starting:* when a phone connects, MMTVL leaves whatever it was showing (Live TV stops, YouTube pauses, like Home), brings Reflector's window to the front and makes it full screen.
  - *During:* the remote's **Home ends the mirroring** (MMTVL disconnects the phone in Reflector) and shows the home screen (user choice 2026-10-06). A YouTube cast (above) also ends it.
  - *After:* when the phone stops casting, MMTVL comes back to its home screen by itself, so the TV never sits on an empty Reflector or the desktop.
- **Settings → Casting** is a checklist for the ways to cast: YouTube (on/off and whether it's ready), **AirPlay** (is macOS's AirPlay Receiver on, with a button that opens the right System Settings page and what to set there), **Android** (is Reflector installed, running or mirroring; *Start Reflector with MMTVL*; the Reflector preferences to set), and **Plex** (is Plex HTPC running, and how to cast to it).
- **Phone remote home-screen icon.** "Add to Home Screen" on the phone gives an MMTVL remote icon and name instead of a screenshot or a letter.
- **Phone trackpad.** A *Trackpad* button on the phone remote turns the D-pad into a touch surface: drag to move the Mac's pointer, tap to click, two-finger tap to right-click, two-finger drag to scroll. Useful in the browser and other apps that need a pointer.
- **On-TV QA pass** of everything from M7 and M7b, run with the user.

## Out of scope

- A Chromecast (Google Cast) receiver built into MMTVL (master plan non-goal). YouTube casting here is DIAL plus YouTube's own lounge protocol, which is what smart TVs use; Android **screen mirroring** is Reflector's job (D32), MMTVL only manages it.
- Reflector's AirPlay (off, user choice), Miracast (not on macOS), several phones mirroring at once in a split layout (Reflector supports it; MMTVL treats any mirroring window as "a session" and Home ends all of them), Reflector's recording, and configuring Reflector's preferences from MMTVL (they're a one-time manual checklist).
- Pausing *other* apps' playback (e.g. Plex HTPC playing behind) when mirroring starts; only MMTVL's own playback stops.
- Casting other apps over DIAL (Netflix and others): only the `YouTube` DIAL app is answered; every other name gets 404.
- Starting Plex HTPC in the background so it can receive casts after a restart (it must have been opened once since login). Possible later.
- Drag-and-drop (press-and-hold then drag) on the trackpad, three-finger gestures, pinch zoom, pointer speed settings.
- Phone scrolling moving MMTVL's own home-screen focus (the phone's D-pad does that; synthetic scrolls pass through `InputRouter` untouched by design, M5 L6).
- A native phone app (D11).
- Fixing issues found in the QA pass beyond small, obvious ones the user asks for; the rest become follow-ups.

## Research & findings

Gathered in [M7b-notes.md](M7b-notes.md) during M7 planning and re-checked on 2026-10-06 (marked *re-checked*).

### YouTube DIAL: how a phone finds and launches YouTube on a TV

- **Protocol (DIAL 2.1/2.2, [dial-multiscreen.org](http://www.dial-multiscreen.org/dial/protocol-specification)):**
  1. The phone multicasts an SSDP `M-SEARCH * HTTP/1.1` to `239.255.255.250:1900` with `ST: urn:dial-multiscreen-org:service:dial:1`.
  2. The TV answers by **unicast UDP** to the sender with `LOCATION: http://<TV IP>:<port>/<device description>`.
  3. The phone GETs the device description (UPnP XML). Its response header `Application-URL` names the DIAL REST service (e.g. `http://IP:port/apps`). The app resource is `Application-URL + "/" + appName` (spec: "concatenating the DIAL REST Service URL, a single slash and the application name"), so `Application-URL` has **no trailing slash**.
  4. `GET /apps/YouTube` returns the app's state as XML (`text/xml; charset="utf-8"`).
  5. `POST /apps/YouTube` (body `text/plain`, at most 4096 bytes, a query string) launches the app; success is **201** with `LOCATION` of the running instance. `DELETE <instance>` stops it.
  6. CORS (§6.6): requests with **no `Origin`** or a non-http(s) origin (phone apps send e.g. `package:com.google.android.youtube`, `package:com.google.ios.youtube`) are allowed; **an `http`/`https` `Origin` is rejected with 403**, so web pages on the LAN can't launch apps.
- **YouTube's TV app does the YouTube-specific part itself** (*re-checked* 2026-10-06 in the live leanback bundle `kabuki.base_cr.en_US…`, build `kabuki.web_20261005_16_RC00`, fetched with the D21 PS4/Cobalt user agent):
  - `_.Gy = () => !!(window.DialServer || window.h5vcc?.dial?.DialServer)` decides DIAL support; with it, the `DialCapabilities` service reports **"full"** (`if(_.Gy())return"full"`), unless the server config flags the device as a public DIAL device (`isPublicDialDevice`) or IP validation says "compromised" (`enforceDisablingCompromisedReceivers`). We can't control those flags; see *Risks*.
  - On Cobalt (YouTube's TV runtime) the native side provides `h5vcc.dial.DialServer`; leanback creates `new DialServer("YouTube")` and registers `onGet/onPost/onDelete(path, callback)`. A callback is `cb(request, response) → Bool`, synchronous; `request = {path, method, body, host}`, `response = {responseCode, body, mimeType, addHeader(name, value)}` ([Cobalt IDL](https://github.com/youtube/cobalt/tree/25.lts.1%2B/cobalt/h5vcc/dial)).
  - What leanback answers (from the notes, module `CobaltInAppDialService`, lazily loaded so not in the base bundle): GET "/" → 200 `<service xmlns="urn:dial-multiscreen-org:schemas:dial">…<state>running</state><link rel="run" href="…/run"/><additionalData>…</additionalData></service>`; POST "/" with a body containing `pairingCode` or `reversePairingCode` → 201 + `LOCATION`, else returns false; DELETE "/run" → 501.
  - Launch parameters: leanback reads `pairingCode`/`reversePairingCode` from its page URL at startup (*re-checked*: `_.xp=function(a){return a.get("pairingCode")||a.get("reversePairingCode")}`, and the deep-link handler only treats `v` as a video when no pairing code is present). So a TV that isn't running YouTube can open `https://www.youtube.com/tv?<POST body>`, which is what Netflix's [DIAL reference server](https://github.com/Netflix/dial-reference) does. `additionalDataUrl` must be `http://localhost…` or `127.0.0.1` (*re-checked*); we don't use it (with the shim, leanback stores additional data itself; an https page can't fetch http anyway).
  - Every `window.h5vcc` use in the bundle is guarded (`h5vcc?.x?.y`) (*re-checked*: 55 references), so a `window.h5vcc` that has **only** `dial` is safe. Without `h5vcc.system`, leanback keeps using `window.close()` to exit, which M3's exit hook catches.
- **VacuumTube** (Electron YouTube TV app) ships exactly this since v1.8.0 (2026-06-30: "Casting from phone to VacuumTube now works without a TV code", *re-checked* with `gh`, source `src/preload/modules/h5vcc/`):
  - `index.js`: `window.h5vcc = { dial: { DialServer }, runtime, system }` in the page; starts DIAL after `localStorage['yt.leanback.default::mdx-device-id']` exists (or 10 s).
  - `dial/discover.js`: UDP 1900, `reuseAddr`, joins `239.255.255.250`; replies to `M-SEARCH *` with `HTTP/1.1 200 OK`, `CACHE-CONTROL: max-age=1800`, `DATE`, `EXT:` (empty), `LOCATION: http://IP:port/`, `SERVER: <os>/<ver> UPnP/1.0 VacuumTube/<ver>`, `ST: urn:dial-multiscreen-org:service:dial:1`, `USN: uuid:<id>::urn:dial-multiscreen-org:service:dial:1`. It does not check `ST`.
  - `dial/server.js`: `GET /` → device XML (`deviceType urn:dial-multiscreen-org:device:dial:1`, `friendlyName`, `UDN uuid:<id>`) with `Content-Type: text/xml; charset="utf-8"` and `Application-URL: http://IP:port/apps`; a `DialServer` routes `basePath + path` (trailing slashes trimmed) with `request = {host: "IP:port", path: basePath, body}`; a callback returning false → **400**; else `responseCode`, `mimeType`, headers and body.
  - Its open PR #229 ("background receiver") keeps the page loaded while hidden and **restores the window on a successful POST** to the app root: the same "cast takes over the screen" behavior this plan uses. Issue #247 asks for the same.
- **macOS networking** ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)): no multicast entitlement on macOS; receiving multicast and sending unicast UDP on the LAN need **Local Network** permission, which MMTVL already declares (`NSLocalNetworkUsageDescription`, M7 L17). Incoming TCP (the DIAL HTTP server, like the phone remote) does not. Denied permission shows up as `sendto` failing (`EHOSTUNREACH`/`EPERM`) or no packets arriving.
- **Port 1900** is free on the dev Mac (*re-checked* with `lsof`). Plex Media Server binds it for DLNA if it runs on the same Mac; with `SO_REUSEADDR` + `SO_REUSEPORT` on our socket, multicast datagrams are delivered to every socket bound to the port. If the other process didn't set `SO_REUSEPORT`, our `bind` can fail with `EADDRINUSE` (see *Risks*).
- **Unverified (checked in step 5 with real phones):** that the current iOS and Android YouTube apps list a DIAL device and POST a `pairingCode` (gotubecast PR #1, June 2026, documents iOS POSTing a UUID `pairingCode`; VacuumTube's release shows it works with at least one platform); that `callAsyncJavaScript` answers quickly while the YouTube web view isn't in the window (MMTVL keeps it alive off screen, D21); when leanback creates its `DialServer` (at start or later); that a cold launch with `?pairingCode=` pairs end to end.

### AirPlay Receiver (verified on macOS 27, 2026-10-06; *re-checked*)

- When the receiver is on, ControlCenter listens on TCP **7000** and 5000. `GET http://127.0.0.1:7000/info` answers `HTTP/1.1 403 Forbidden` with header **`Server: AirTunes/980.77.5`**. Loopback needs no Local Network permission.
- The `com.apple.controlcenter` key `AirplayRecieverEnabled` is absent until toggled (default on), so don't read it. **Unverified:** that port 7000 is closed when the receiver is off (step 6's manual check).
- Settings page URL: `x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension` (System Settings → General → AirDrop & Handoff).
- Exact English labels (*re-checked* in `AirDropHandoffExtension.appex/…/Localizable.loctable`): **"AirPlay Receiver"**, **"Allow AirPlay for"** with **"Current User"** ("Only devices signed in to your Apple Account…"), **"Anyone on the Same Network"**, **"Everyone"**.

### Plex HTPC as a cast target

- Plex's [Supported Plex Companion Apps](https://support.plex.tv/articles/203082707-supported-plex-companion-apps/) (modified 2025-04-28) lists **Plex HTPC as "Receiver-Only"**: phones cast to it while it runs. The old **"Advertise as player"** setting was removed from Plex's desktop players ([forum, 2022](https://forums.plex.tv/t/advertise-as-player-removed/796708)); Plex HTPC 1.71.1's `plex.ini` on the dev Mac has no such key. So there is **nothing to switch on**; it must be running and signed in to the same account.
- The same article says it "does not apply to Plex for Mobile apps 2025.10 or higher". **Unverified:** whether the new Plex mobile app's Cast menu lists Plex HTPC. Checked in step 12; tracked as master plan Q14.
- Plex HTPC's bundle id is `tv.plex.htpc` (M7 notes).

### Reflector 4 (Android screen mirroring; research 2026-10-06 from Squirrels' help center, not installed on the dev Mac)

- **Version and identity:** latest Mac release **4.1.2 (2024-12-09)** ([release notes](https://www.airsquirrels.com/reflector/release-notes/mac)); "macOS 10.15 or newer" ([specs](https://www.airsquirrels.com/reflector/specs)), macOS 26/27 not stated. Bundle id **`com.squirrels.Reflector-4`** (from a third-party catalog, [appcatalog.cloud](https://appcatalog.cloud/apps/reflector-4); **unverified**, step 7 checks with `mdls -name kMDItemCFBundleIdentifier /Applications/Reflector\ 4.app`). One-time purchase, one computer per license; the 7-day trial shows a **watermark** ([try](https://www.airsquirrels.com/reflector/try)).
- **Android:** receives **Google Cast screen mirroring** from Quick Settings → Cast / Screen Cast; nothing to install on the phone ([requirements](https://help.airsquirrels.com/reflector/205-android-mirroring-requirements), [how to](https://help.airsquirrels.com/reflector/203-mirror-android-to-reflector)). Samsung/Android 11+ without the Cast tile need a workaround app ([article](https://help.airsquirrels.com/reflector/how-to-cast-and-screen-mirror-android-phones-and-tablets-on-android-11-and-later)). **Google Home's "Cast my screen" no longer lists Reflector** ([Squirrels blog](https://blog.airsquirrels.com/how-to-screen-mirror-android-phones-and-tablets-to-your-computer-with-google-home)). 4.1.2 fixed a Cast issue after an Android update. DRM apps (Netflix, Prime, Hulu) can't be mirrored ([article](https://help.airsquirrels.com/reflector/241-how-do-i-mirror-netflix-amazon-prime-hulu-etc)). **Unverified:** what the Android **YouTube app** does if Reflector is picked in its Cast list (Squirrels documents mirroring only).
- **Protocols are separate toggles:** Preferences → Advanced → AirPlay / Google Cast / Miracast (Miracast greyed out on a Mac) ([article](https://help.airsquirrels.com/reflector/why-is-the-miracast-setting-greyed-out-in-my-reflector-4-preferneces-menu)). Squirrels says Reflector's AirPlay **conflicts** with macOS's AirPlay Receiver and to turn the system one off ([Sonoma article](https://help.airsquirrels.com/reflector/connect-and-iphone-or-ipad-to-reflector-4-on-macos-sonoma)). With Reflector's AirPlay **off** (user choice), the conflict should be gone; **unverified**, step 7 checks.
- **Ports** ([networking](https://help.airsquirrels.com/reflector/221-reflector-4-networking-requirements)): mDNS UDP 5353; **SSDP UDP 1900 for Google Cast** (the same port as our DIAL responder, see *Risks*); Google Cast TCP 8008/8009 plus a random UDP port for the stream; AirPlay TCP 7000/7001/7100/47000 (unused with AirPlay off). Needs **Local Network** permission on macOS 15+ ([article](https://help.airsquirrels.com/reflector/issues-connecting-an-ios-device-to-reflector-4)).
- **Windows** ([features](https://www.airsquirrels.com/reflector/features/mac-and-windows), [smart layout](https://help.airsquirrels.com/reflector/235-disable-automatic-sizing-and-placement-of-the-reflector-window-after-connecting), [shortcuts](https://help.airsquirrels.com/reflector/228-user-keyboard-shortcuts-with-reflector)): one window per connected device; several devices at once ("smart layouts", can't be turned off). Preferences: General → **Always on Top**; Connection → **Display Fullscreen** (new connections full screen) and the full-screen background color; General → **Show Client Name** (Off/Always/On Hover); device frame **⌘B**; editable **receiver name**; connection prompts (allow/deny a new device, remembered or asked each time); on-screen codes apply to AirPlay only. Shortcuts: **⌘F** full screen, **⌘W disconnect**, ⌘Q quit.
- **Unverified (step 7):** whether Reflector activates itself when a phone connects; what "Display Fullscreen" is (a native full-screen Space or a borderless window); whether it has a window when idle (menu-bar app?) and a launch-at-login option; what happens to the window when the phone stops (closes?); whether closing a device window disconnects the phone (as ⌘W does); what Escape does in full screen; that mirrored audio plays on the Mac's default output; how Reflector binds UDP 1900 (`SO_REUSEPORT` or not) and whether it also answers **DIAL** searches (Chromecasts historically did, so YouTube might list it as a DIAL device too).
- **Window list without Screen Recording:** `CGWindowListCopyWindowInfo` returns `kCGWindowOwnerPID`, `kCGWindowLayer`, `kCGWindowBounds`, `kCGWindowAlpha` without Screen Recording permission (only `kCGWindowName` needs it). Window titles and close buttons are available through Accessibility (`kAXWindowsAttribute`, `kAXTitleAttribute`, `kAXCloseButtonAttribute` + `AXPress`), which MMTVL already has (D4/D15).

### Phone remote icon

- iOS: `<link rel="apple-touch-icon" href="…">` with a **180 × 180 PNG**, and `<meta name="apple-mobile-web-app-title" content="MMTVL">` ([Apple: Configuring Web Applications](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html)). Works over http. iOS also probes `/apple-touch-icon.png` and `/apple-touch-icon-precomposed.png` at the root.
- Android Chrome on an http origin: "Add to Home screen" makes a shortcut; manifests need a secure context to *install*, so whether the shortcut uses the manifest's icon or `<link rel="icon">` is **unverified**. Serve both (192 × 192 and 512 × 512) and check in step 12.

### Phone trackpad

- Mouse events with the tagged `SyntheticInput` source (M5 L6): `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` with `.mouseMoved` (also set `.mouseEventDeltaX/Y`), `.leftMouseDown/Up`, `.rightMouseDown/Up` with `.mouseEventClickState` (1, 2, 3 for double/triple clicks), and `CGEvent(scrollWheelEvent2Source:units: .pixel, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0)`. Positive `wheel1` scrolls up (content moves down). Posted at `.cghidEventTap` like the keys. The current pointer: `CGEvent(source: nil)?.location` (global, top-left origin). Displays: `CGGetActiveDisplayList` + `CGDisplayBounds` (same coordinate space).
- Same Accessibility grant as keys (`CGPreflightPostEventAccess`, D4/D24). `GlobalEventTap` only taps keys and system-defined events; `InputRouter`'s local monitor passes our own scroll events through (`SyntheticInput.isOwn`).
- **Unverified:** whether macOS applies the "natural scrolling" preference to posted scroll events (step 10 checks the direction; a constant flips it).

### This codebase (what M7b plugs into)

- `RemoteServer` (main actor): HTTP `NWListener` serving `RemoteWebAssets` (an allow-list), WebSocket listener for `PhoneRemote`. `HTTPRequestHead.parse` only reads the request line; `HTTPResponse.make(status:reason:contentType:body:includeBody:)` writes `Connection: close`, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`.
- `PhoneRemote` decodes `ClientMessage`s (`RemoteMessage.swift`, one `RemoteWireMessage` struct for both directions) and acts through `PhoneRemoteEnvironment` closures (tests: `PhoneRemoteRecorder` in `PhoneRemoteTests.swift`).
- `YouTubeController` owns the one `WKWebView` (D21), created on first `open()`; user scripts are added at creation (`YouTubeKeyMap.exitHookScript`, `alwaysVisibleScript`, `volumeScript`) with one message handler, `YouTubeKeyMap.messageHandlerName`. **Pitfall:** `YouTubeWebDelegate.userContentController(_:didReceive:)` currently treats *every* message as "leanback exited"; a second handler must branch on `message.name`.
- `YouTubeView` puts the web view in the window only while `router.screen == .youtube`; otherwise it lives off screen.
- `AppRouter.openYouTube()` / `goHome()` (leaves Live TV, ends Settings pairing/learning, closes the PIN screen). `AppDelegate.handleGlobal(.home)` shows the launcher over another app with `launcher.homePressed(); router.goHome(); windowController.show()`.
- Settings: pages are `SettingsPage` cases, rows are data (`SettingsRow`/`SettingsAction`), side effects through `SettingsEnvironment` closures, status structs filled by `AppDelegate` (`phoneRemoteSettingsStatus()`, `plexSettingsStatus()`), re-read by `SettingsModel.refreshStatus()`. Tests use `makeSettingsModel` + `SettingsRecorder` (`SettingsTestSupport.swift`).
- `AppSettings` decodes every key with `decodeIfPresent` and a default.
- `LocalAddress.primaryIPv4()` picks the LAN IPv4 (en0, en1, else any non-loopback, never 169.254).

## Design

### New and changed files

| File | Responsibility |
|---|---|
| `MMTVL/RemoteServer/HTTPRequest.swift` | + `HTTPHeader`; `HTTPResponse.make` gains `headers:` and an optional `contentType`; `HTTPResponse.reason(for:)`. |
| `MMTVL/RemoteServer/RemoteWebAssets.swift` | + generated assets: icons and the web manifest. |
| `MMTVL/RemoteServer/PhoneRemoteIcon.swift` (new) | Renders the remote's icon PNG at a size (cached). |
| `MMTVL/RemoteServer/RemoteServer.swift` | Serves generated assets. |
| `MMTVL/RemoteServer/Web/remote.html/.css/.js` | Icon/manifest tags; trackpad mode. |
| `MMTVL/RemoteServer/RemoteMessage.swift` | + `pointer`, `click`, `scroll` messages. |
| `MMTVL/RemoteServer/PhoneRemote.swift` | Routes pointer actions; throttled Accessibility toast. |
| `MMTVL/Input/SyntheticInput.swift` | + mouse move, click, scroll. |
| `MMTVL/Input/PhonePointer.swift` (new) | `PointerAction`, `PointerMath` (pure), `ClickCounter` (pure), `PhonePointer` (posts). |
| `MMTVL/Cast/DIALProtocol.swift` (new) | Pure: SSDP parse/reply, device description, app status XML, DIAL HTTP request parser, origin rule, launch-query sanitizer, routing decision. |
| `MMTVL/Cast/SSDPResponder.swift` (new) | BSD UDP socket on 1900, multicast membership, replies. |
| `MMTVL/Cast/DIALServer.swift` (new) | `NWListener` HTTP server executing `DIALRouting` decisions. |
| `MMTVL/Cast/CastReceiver.swift` (new) | Owns both, restarts on network change/wake, overall state. |
| `MMTVL/Cast/AirPlayReceiverProbe.swift` (new) | Loopback check of port 7000; pure response parser. |
| `MMTVL/Cast/MirroringDetector.swift` (new) | Pure: Reflector windows → session began/ended, needs full screen (L19). |
| `MMTVL/Cast/ReflectorMonitor.swift` (new) | Keeps Reflector running, polls its windows, starts/ends sessions (L18–L22). |
| `MMTVL/Launcher/WindowFullScreener.swift` | + `closeWindows(pid:matching:)` (AX close button) and `windows(pid:)` frames. |
| `MMTVL/YouTube/YouTubeDIAL.swift` (new) | The `h5vcc.dial` shim script, the call script, `DIALAppResponse` parsing. |
| `MMTVL/YouTube/YouTubeController.swift` | Shim injection, ready state, `handleDIAL`, `launch(query:)`. |
| `MMTVL/YouTube/YouTubeConfig.swift` | `launchURL(query:)`. |
| `MMTVL/Launcher/AppRouter.swift` | `castYouTube(query:)`. |
| `MMTVL/App/AppSettings.swift` | `youtubeCastEnabled`, `castDeviceID`. |
| `MMTVL/App/AppDelegate.swift` | Wiring: cast receiver, phone pointer, casting status. |
| `MMTVL/Settings/*` | Settings → Casting page; `.youtubeCastEnabled` toggle. |
| `MMTVL.xcodeproj/project.pbxproj` | Build setting only: the Local Network usage text (two configurations). |

### Local decisions

- **L1 — DIAL architecture: native discovery, leanback answers.** MMTVL answers SSDP and the device description natively and hands every `/apps/YouTube…` request to **leanback's own handlers** through a Cobalt-style `window.h5vcc.dial.DialServer` shim injected at document start (VacuumTube's proven approach). Native code never imitates leanback's pairing logic. *Why:* leanback stays the source of truth for YouTube's protocol; MMTVL only moves bytes.
- **L2 — Cold path when leanback isn't ready.** While the YouTube page isn't loaded (never opened, loading, crashed, or loaded before casting was turned on), native code answers `GET /apps/YouTube` with `stopped` (or `running` for 30 s after a launch, L9), and a `POST` launches YouTube with `https://www.youtube.com/tv?<sanitized body>` (Netflix reference behavior; leanback reads `pairingCode` from its URL). *Why:* MMTVL doesn't keep YouTube loaded from boot (memory, background CPU), and a cast must work anyway.
- **L3 — Ports and identity.** DIAL HTTP on TCP **8770**; if that is in use, any free port (the SSDP reply always names the real port). SSDP on UDP 1900 with `SO_REUSEADDR` + `SO_REUSEPORT`. `friendlyName` **"MMTVL"**. The UDN/USN uuid is MMTVL's own, generated once and saved as `settings.json` `castDeviceID` (not leanback's `mdx-device-id`, which doesn't exist before the page loads; VacuumTube itself falls back to a random UUID). `LOCATION: http://IP:port/dd.xml`; `/` serves the same document.
- **L4 — A cast takes over the TV, PIN ignored (user choices 2026-10-06).** A successful launch (cold: native 201; warm: leanback's 201 on `POST`) brings MMTVL to the front and shows YouTube from any screen: Live TV is left as Home leaves it; another app (Plex) keeps running behind (D18); Settings closes; a PIN screen is dismissed. The YouTube tile's *Require PIN* does not apply to casts.
- **L5 — Setting.** `settings.json` **`youtubeCastEnabled`** (default `true`), toggled in Settings → Casting, applied live: on starts the receiver, off stops it. The shim is injected only if casting is on **when the web view is created**; turning casting on later works through the cold path (L2) until YouTube is next created. *Why:* if the shim ever breaks YouTube, turning casting off (and relaunching) removes it.
- **L6 — Cold launch query allow-list.** Only `pairingCode`, `reversePairingCode`, `v`, `t`, `list`, `index`, `theme`, `dialLaunch` pass, each value 1…200 characters of `[A-Za-z0-9._~-]`. Anything else is dropped. A body that isn't a query string at all → 400. *Why:* the body comes from anyone on the LAN; the page URL must stay a plain YouTube launch.
- **L7 — DIAL safety and privacy.** `/apps/*` requests with an `http`/`https` `Origin` → 403 (spec §6.6). Bodies over 4096 bytes → 413. Request heads over 16 KB → 431. Only `GET`, `POST`, `DELETE` (others → 405). Logs (category **`Cast`**) show method, path without query, status and the client's IP; **never bodies, queries or pairing codes**.
- **L8 — Bridge readiness.** `YouTubeController.isDIALReady` becomes true when the shim posts `{type:"ready"}` (leanback constructed a `DialServer`), and false when a navigation starts, a load fails, the web content process dies, or `load()` runs. A forwarded request that doesn't answer within **3 s**, or finds no matching handler, falls back to the native answer (L2).
- **L9 — "Launching" window.** After a native launch, `GET /apps/YouTube` answers `running` (with `<link rel="run" href="run"/>`) for 30 s or until leanback is ready, so a phone polling the state doesn't relaunch.
- **L10 — Phone icon = the MMTVL logo.** The PNGs are the asset catalog image **`Logo`** (the user's "tv" logo, 2026-10-06: a full-bleed 1024 × 1024 square without rounded corners, because iOS and Android round icons themselves) scaled with `ImageRenderer`, cached per size, served at `/apple-touch-icon.png` (180; also `/apple-touch-icon-precomposed.png`), `/icon-192.png`, `/icon-512.png`. A web manifest at `/remote.webmanifest` is a Swift string. (The Mac app icon, `AppIcon`, is the same logo in the macOS icon shape; both were added during planning.)
- **L11 — Trackpad messages.** The phone sums movement per animation frame and sends `{type:"pointer",dx,dy}`, `{type:"scroll",dx,dy}` (CSS pixels) and `{type:"click",button:"left"|"right"}`. Each `dx`/`dy` must be finite with magnitude ≤ 1000, else the message is ignored. Gestures: one finger drag = move; one-finger tap (< 250 ms, < 10 px of movement) = left click; two-finger tap = right click; two-finger drag = scroll (content follows the fingers). The mode (D-pad / Trackpad) is remembered on the phone (`localStorage`).
- **L12 — Pointer math on the Mac.** Acceleration `factor = 1.5 + 1.5 × min(speed, 40) / 40` where `speed = hypot(dx, dy)` per message (so 1.5×…3×). The new position is clamped: if it isn't inside any active display, clamp it into the display that contains the current position. Scroll: `wheel1 = round(dy × 2) × scrollSign`, `wheel2 = round(dx × 2) × scrollSign`, `scrollSign = 1` (content follows the finger; flip if step 10 shows otherwise). Clicks within 0.5 s and 6 points of the last click of the same button count up (double, triple; max 3).
- **L13 — Pointer and Accessibility.** Pointer messages work whether MMTVL or another app is in front. Without post-event access, the phone gets the existing Accessibility toast at most once per 5 s per session (pointer messages arrive 60 times a second).
- **L14 — Settings → Casting.** A root row *Casting* opens a page with four sections: **YouTube** (toggle + state), **AirPlay** (receiver On/Off/Unknown from a loopback probe, Select opens System Settings → AirDrop & Handoff, footer with the exact labels), **Android** (Reflector Not Installed/Not Running/Ready/Mirroring, *Start Reflector with MMTVL* toggle, footer = L23's checklist), **Plex** (Plex HTPC Running/Not Running/Not Installed, info only, footer how to cast). Opening the page re-checks AirPlay, Reflector and Plex.
- **L15 — AirPlay probe.** A raw `NWConnection` to `127.0.0.1:7000` sends `GET /info HTTP/1.1` and reads the head (no URLSession, so no App Transport Security question): a response whose `Server` header starts with `AirTunes` → On; connection refused → Off; anything else or a 2 s timeout → Unknown.
- **L16 — Plex HTPC.** Status only: installed (`NSWorkspace.urlForApplication(withBundleIdentifier: "tv.plex.htpc")`), running (`NSRunningApplication.runningApplications(withBundleIdentifier:)`). No setting exists to change (*Research*).
- **L18 — Reflector stays running (D32).** When Reflector is installed and `settings.json` **`reflectorAutoStart`** is true (default), MMTVL opens it **hidden and in the background** (`NSWorkspace.OpenConfiguration`: `activates = false`, `hides = true`, `addsToRecentItems = false`) at launch, after wake (with the 2 s wake delay) and 5 s after it quits, at most 3 restarts per 10 minutes (then log and stop until the next launch or wake). Kiosk and `-windowed` alike; Settings → Casting → *Start Reflector with MMTVL* toggles it live (off does not quit Reflector). Logs use category **`Reflector`** (starts, restarts, session began/ended; never window titles).
- **L19 — Session detection.** While Reflector runs, MMTVL polls once per second: `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`, windows whose owner PID is Reflector's, alpha > 0, at least **25 % of the main screen's width and height**. One such window → session **began**; none for **2 polls in a row** → session **ended**. Thresholds are constants in `MirroringDetector` and are confirmed in step 7 (Reflector's idle/preferences windows must stay below them). No Screen Recording permission is needed (*Research*). Polling stops while Reflector isn't running (observe launch/terminate notifications).
- **L20 — Session began:** `castWillTakeOver()`: `launcher.homePressed()` and `router.goHome()` (Live TV leaves, YouTube pauses, Settings and the PIN screen close; same as L4, no PIN), then activate Reflector (`NSRunningApplication.activate()`). If, on any later poll, the session window isn't full screen (its bounds don't cover the main screen), call `WindowFullScreener.makeFullScreen(pid:)` (AXFullScreen, D15), at most once every 3 s. This covers Reflector not activating itself, "Display Fullscreen" off, and Escape leaving full screen.
- **L21 — Home during a session ends it (user choice 2026-10-06).** Global Home (event tap, phone, controller) while a session is active: close every session window through Accessibility (`kAXCloseButtonAttribute` → `AXPress`), else (no close button) activate Reflector and post **⌘W** once per session window with `SyntheticInput` (tagged). Then the usual Home (`launcher.homePressed(); router.goHome(); windowController.show()`). Step 7 confirms which of the two disconnects the phone; the code keeps both, close button first. A YouTube cast (L4) ends a session the same way before showing YouTube.
- **L22 — Session ended:** when the last session window is gone and the frontmost app is Reflector, MMTVL or nothing, MMTVL shows its window (`windowController.show()`) on the home screen. If the user had switched to another app on purpose, stay (like M1 L5).
- **L23 — Reflector setup is a manual checklist,** shown as the footer of Settings → Casting → Android and in CLAUDE.md: Preferences → Advanced: **AirPlay off, Google Cast on**; General: **Always on Top off** (MMTVL brings the window forward itself; an always-on-top window would stay over MMTVL after Home), **Show Client Name off**; Connection: **Display Fullscreen on**, no connection prompt (it needs a mouse); receiver name **"MMTVL Screen Mirroring"** (so Android's lists tell it apart from the YouTube DIAL device "MMTVL"); device frame off (⌘B); allow Reflector under Privacy & Security → Local Network. macOS's AirPlay Receiver stays **on** (user choice).
- **L17 — QA pass.** Step 12 walks M7's unticked *Manual verification* list and M7b's with the user on the TV; results are ticked in each plan, problems recorded under *Deviations & questions* as follow-ups.

### Key types (Swift sketches)

```swift
// RemoteServer/HTTPRequest.swift (additions)
nonisolated struct HTTPHeader: Equatable, Sendable {
    var name: String
    var value: String
}
extension HTTPResponse {
    /// `contentType` nil → no Content-Type header. Extra `headers` go after Content-Length.
    static func make(status: Int, reason: String, contentType: String?, headers: [HTTPHeader] = [],
                     body: Data, includeBody: Bool) -> Data
    /// 200 OK, 201 Created, 204 No Content, 302 Found, 400 Bad Request, 403 Forbidden, 404 Not Found,
    /// 405 Method Not Allowed, 413 Content Too Large, 431 Request Header Fields Too Large,
    /// 501 Not Implemented, 503 Service Unavailable; anything else "Status".
    static func reason(for status: Int) -> String
}
```
(Change the existing `make` in place: `contentType: String?` and a defaulted `headers:` keep every existing call compiling.)

```swift
// RemoteServer/RemoteWebAssets.swift
nonisolated struct RemoteWebAsset: Equatable, Sendable {
    enum Generated: Equatable, Sendable { case icon(size: Int), manifest }
    var resource: String
    var ext: String
    var contentType: String
    /// Non-nil: built in code (L10); `resource`/`ext` are empty.
    var generated: Generated? = nil
}
// asset(forPath:) adds:
// "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png" → .icon(size: 180), "image/png"
// "/icon-192.png" → .icon(size: 192); "/icon-512.png" → .icon(size: 512)
// "/remote.webmanifest" → .manifest, "application/manifest+json; charset=utf-8"
nonisolated enum RemoteWebManifest {
    /// {"name":"MMTVL Remote","short_name":"MMTVL","start_url":"/","display":"standalone",
    ///  "background_color":"#000000","theme_color":"#000000",
    ///  "icons":[{"src":"/icon-192.png","sizes":"192x192","type":"image/png"},
    ///           {"src":"/icon-512.png","sizes":"512x512","type":"image/png"}]}
    static let json: String
}

// RemoteServer/PhoneRemoteIcon.swift (main actor)
enum PhoneRemoteIcon {
    /// PNG data, rendered once per size with ImageRenderer (scale 1) and cached.
    static func png(size: Int) -> Data?
}
```

```swift
// Input/PhonePointer.swift
nonisolated enum PointerButton: String, Sendable { case left, right }
nonisolated enum PointerAction: Equatable, Sendable {
    case move(dx: Double, dy: Double)
    case click(PointerButton)
    case scroll(dx: Double, dy: Double)
}
nonisolated enum PointerMath {
    static let maxDelta: Double = 1000
    static let scrollScale: Double = 2
    static let scrollSign: Double = 1
    /// L12 acceleration.
    static func accelerated(dx: Double, dy: Double) -> CGVector
    /// L12 clamp: `point` if some display contains it, else clamped into the display containing `previous`
    /// (else the first display; no displays → `point`).
    static func clamp(_ point: CGPoint, displays: [CGRect], previous: CGPoint) -> CGPoint
    /// L12: (wheel1 vertical, wheel2 horizontal), pixels.
    static func scrollWheels(dx: Double, dy: Double) -> (Int32, Int32)
}
nonisolated struct ClickCounter {
    static let interval: TimeInterval = 0.5
    static let distance: CGFloat = 6
    /// 1, 2 or 3 (L12).
    mutating func register(_ button: PointerButton, at point: CGPoint, time: Date) -> Int64
}
/// Posts pointer actions with SyntheticInput (main actor).
final class PhonePointer {
    var now: () -> Date = Date.init
    func perform(_ action: PointerAction)
}
```

```swift
// Cast/DIALProtocol.swift (all nonisolated, pure)
nonisolated enum SSDP {
    static let multicastAddress = "239.255.255.250"
    static let port: UInt16 = 1900
    static let dialSearchTarget = "urn:dial-multiscreen-org:service:dial:1"
    /// True for "M-SEARCH * HTTP/1.1" with MAN "ssdp:discover" (quotes optional) and ST == dialSearchTarget
    /// (header names case-insensitive; ST compared case-sensitively after trimming).
    static func isDIALSearch(_ datagram: Data) -> Bool
    /// The unicast reply (CRLF lines, ends with an empty line).
    static func searchReply(location: String, deviceID: String, server: String, date: Date) -> Data
}
nonisolated struct DIALRequest: Equatable, Sendable {
    var method: String
    /// Without the query; repeated slashes collapsed.
    var path: String
    /// Lowercased names.
    var headers: [String: String]
    var body: String
    enum Parse: Equatable { case incomplete, tooLarge(Int), invalid, complete(DIALRequest) }   // tooLarge carries 413 or 431
    static let maxHeadSize = 16_384
    static let maxBodySize = 4_096
    static func parse(_ data: Data) -> Parse
}
nonisolated struct DIALReply: Equatable, Sendable {
    var status: Int
    var contentType: String?
    var headers: [HTTPHeader] = []
    var body: Data = Data()
    func encoded(includeBody: Bool = true) -> Data   // HTTPResponse.make + reason(for:)
}
nonisolated struct DIALAppRequest: Equatable, Sendable {
    var app: String        // "YouTube"
    var method: String
    var path: String       // relative to /apps/YouTube: "/" or "/run"
    var body: String
    var host: String       // "IP:port"
}
nonisolated struct DIALAppResponse: Equatable, Sendable {
    var handled: Bool
    var status: Int
    var body: String
    var mimeType: String?
    var headers: [HTTPHeader]
}
nonisolated struct DIALContext: Equatable, Sendable {
    var host: String       // "IP:port" as the phone reached us
    var deviceID: String
    var friendlyName: String
    var appReady: Bool
    var isLaunching: Bool  // L9
}
nonisolated enum DIALDecision: Equatable, Sendable {
    case reply(DIALReply)
    case forward(DIALAppRequest)
    /// Native cold launch (L2); nil = no parameters. The server replies 201 itself.
    case launch(query: String?)
}
nonisolated enum DIALRouting {
    static let appName = "YouTube"
    static func decide(_ request: DIALRequest, context: DIALContext) -> DIALDecision
    /// The native answer when leanback can't answer (also used after a forward times out).
    static func nativeAppDecision(_ request: DIALRequest, subpath: String, context: DIALContext) -> DIALDecision
    /// A leanback answer → reply. handled false → 400. status 0 → 200.
    static func reply(for response: DIALAppResponse) -> DIALReply
    static func deviceDescription(host: String, deviceID: String, friendlyName: String) -> String
    static func appStatus(running: Bool) -> String
    /// L7: true when the Origin header is http(s).
    static func isForbiddenOrigin(_ origin: String?) -> Bool
    /// L6. nil = not a query string; "" = nothing allowed.
    static func sanitizedLaunchQuery(_ body: String) -> String?
}
```

```swift
// Cast/CastReceiver.swift (main actor)
final class CastReceiver {
    enum State: Equatable { case off, starting, ready, failed(String) }
    private(set) var state: State
    var onStateChange: (() -> Void)?
    init(deviceID: String, friendlyName: String, bridge: CastBridge)
    func start()
    func stop()
    /// Wake or network change: re-join multicast with the current address.
    func restart()
}
/// What the receiver needs from YouTube and the app (AppDelegate wires it; tests can fake it).
struct CastBridge {
    var isAppReady: () -> Bool                                // YouTubeController.isDIALReady
    var forward: (DIALAppRequest) async -> DIALAppResponse?  // YouTubeController.handleDIAL
    var launch: (String?) -> Void                             // cold launch (L2) → AppDelegate.castToTV(query:)
    var didConnect: () -> Void                                // leanback answered a POST with 201 → castToTV(query: nil)
}
```

```swift
// YouTube/YouTubeDIAL.swift
nonisolated enum YouTubeDIAL {
    static let messageHandlerName = "mmtvlDial"
    /// Document-start user script for the page world (L1). Defines window.h5vcc.dial.DialServer and window.__mmtvlDial.
    static let shimScript: String
    /// For callAsyncJavaScript; arguments app, method, path, body, host.
    static let handleScript = "return window.__mmtvlDial ? window.__mmtvlDial.handle(app, method, path, body, host) : null;"
    /// nil for null/garbage or {found:false}.
    static func response(fromJavaScript value: Any?) -> DIALAppResponse?
}
// YouTubeHosting gains:
//   /// Opens YouTube on `https://www.youtube.com/tv?<query>` (a cold cast, L2), creating the web view if needed.
//   func launch(query: String)
```

```swift
// Cast/AirPlayReceiverProbe.swift
nonisolated enum AirPlayReceiverState: Equatable, Sendable { case unknown, on, off }
enum AirPlayReceiverProbe {
    /// L15.
    static func check() async -> AirPlayReceiverState
    /// Pure: a response head whose Server header starts with "AirTunes" (case-insensitive).
    nonisolated static func isAirPlayResponse(_ head: Data) -> Bool
}

// Settings/SettingsTypes.swift
nonisolated struct CastingSettingsStatus: Equatable, Sendable {
    enum YouTube: Equatable, Sendable { case off, starting, ready, failed(String) }
    enum PlexHTPC: Equatable, Sendable { case notInstalled, notRunning, running }
    enum Reflector: Equatable, Sendable { case notInstalled, notRunning, ready, mirroring }
    var youtube: YouTube = .off
    var airPlay: AirPlayReceiverState = .unknown
    var reflector: Reflector = .notInstalled
    var plexHTPC: PlexHTPC = .notInstalled
}
// SettingsPage + .casting; SettingsAction + .openAirPlaySettings;
// SettingKey + .youtubeCastEnabled, .reflectorAutoStart
// SettingsEnvironment + castingStatus: () -> CastingSettingsStatus,
//                       refreshCasting: () -> Void (AirPlay probe; when done, settings.refreshStatus()),
//                       openAirPlaySettings: () -> Void
```

```swift
// Cast/MirroringDetector.swift (pure)
nonisolated struct WindowSnapshot: Equatable, Sendable {
    var pid: pid_t
    var layer: Int
    var alpha: Double
    var bounds: CGRect     // CGWindowList coordinates (top-left origin)
}
nonisolated struct MirroringDetector {
    static let minimumFraction: CGFloat = 0.25   // L19, confirmed in step 7
    static let endAfterMissedPolls = 2
    enum Event: Equatable, Sendable { case none, began, ended }
    private(set) var isActive = false
    /// The session windows of the last poll.
    private(set) var sessionWindows: [WindowSnapshot] = []
    /// One poll: Reflector's windows (already filtered by pid) and the main screen's frame.
    mutating func update(windows: [WindowSnapshot], screen: CGRect) -> Event
    /// L20: true while active and no session window covers `screen` (within 2 points on each edge).
    func needsFullScreen(screen: CGRect) -> Bool
}
nonisolated struct RestartLimiter {
    static let maxRestarts = 3
    static let period: TimeInterval = 600
    /// L18: records and allows a restart, or refuses a 4th within 10 minutes.
    mutating func allowRestart(at date: Date) -> Bool
    mutating func reset()
}

// Cast/ReflectorMonitor.swift (main actor)
final class ReflectorMonitor {
    static let bundleID = "com.squirrels.Reflector-4"   // confirmed in step 7
    var autoStart: Bool                                  // settings.reflectorAutoStart
    private(set) var isMirroring: Bool
    var isInstalled: Bool { get }
    var isRunning: Bool { get }
    var onSessionBegan: (() -> Void)?                    // AppDelegate: L20 takeover
    var onSessionEnded: (() -> Void)?                    // AppDelegate: L22 return
    var onStatusChange: (() -> Void)?                    // Settings refresh
    func start()                                         // observe launch/terminate, launch if wanted, poll while running
    func systemDidWake()
    /// L21: closes every session window (AX close button, else ⌘W). Returns at once; the poll reports the end.
    func endMirroring()
}
```

### The shim (YouTubeDIAL.shimScript)

Use this exactly (comments may be dropped). It must define `window.h5vcc` **only if** it doesn't exist yet, and add nothing else to `h5vcc`.

```js
(() => {
  if (window.h5vcc && window.h5vcc.dial) return;
  const routes = {};
  const norm = (p) => {
    p = String(p == null ? '/' : p);
    if (!p.startsWith('/')) p = '/' + p;
    p = p.replace(/\/+$/, '');
    return p || '/';
  };
  class DialServer {
    constructor(name) {
      this.name = String(name);
      routes[this.name] = { GET: {}, POST: {}, DELETE: {} };
      try { window.webkit.messageHandlers.mmtvlDial.postMessage({ type: 'ready', app: this.name }); } catch (e) {}
    }
    onGet(path, cb) { routes[this.name].GET[norm(path)] = cb; return true; }
    onPost(path, cb) { routes[this.name].POST[norm(path)] = cb; return true; }
    onDelete(path, cb) { routes[this.name].DELETE[norm(path)] = cb; return true; }
  }
  window.h5vcc = Object.assign(window.h5vcc || {}, { dial: { DialServer } });
  Object.defineProperty(window, '__mmtvlDial', { value: {
    handle(app, method, path, body, host) {
      const table = routes[app] && routes[app][method];
      const cb = table && table[norm(path)];
      if (!cb) return { found: false };
      const headers = [];
      const res = { responseCode: 200, body: '', mimeType: '',
                    addHeader(k, v) { headers.push([String(k), String(v)]); } };
      let ok = false;
      try { ok = !!cb({ path: '/apps/' + app, method, body: body || '', host }, res); } catch (e) { ok = false; }
      return { found: true, handled: ok, status: Number(res.responseCode) || 0,
               body: res.body == null ? '' : String(res.body),
               mimeType: res.mimeType ? String(res.mimeType) : '', headers };
    }
  }});
})();
```

`YouTubeDIAL.response(fromJavaScript:)` reads a `[String: Any]`: `found` must be `true`; `handled` (Bool, default false), `status` (`NSNumber`/`Int`, default 0), `body` (String, default ""), `mimeType` (String; empty → nil), `headers` (array of 2-element string arrays; others skipped).

### Request flow (DIALServer)

1. Accept a TCP connection (main queue). Accumulate bytes until `DIALRequest.parse` is `.complete` (or reply `.tooLarge(n)` with status n, `.invalid` with 400). Cancel after 10 s.
2. Build `DIALContext`: `host` = the connection's local IPv4 and the listener port (helper below; fallback `LocalAddress.primaryIPv4()`), `appReady = bridge.isAppReady()`, `isLaunching = now < launchingUntil && !appReady`.
3. `DIALRouting.decide`:
   - `GET /` or `GET /dd.xml` → 200, `text/xml; charset="utf-8"`, header `Application-URL: http://<host>/apps`, body = device description.
   - `GET /apps` or `/apps/` → 302 `Location: http://<host>/apps/YouTube`.
   - `/apps/<name>[/…]`: name ≠ `YouTube` → 404. Forbidden origin → 403. Method not GET/POST/DELETE → 405. `subpath` = rest of the path (`""` → `/`). `appReady` → `.forward`. Else `nativeAppDecision`:
     - `GET /` → 200 `text/xml; charset="utf-8"`, `appStatus(running: isLaunching)`.
     - `POST /` → `sanitizedLaunchQuery(body)`: nil → 400; else `.launch(query: q.isEmpty ? nil : q)`.
     - `DELETE /run` → 404; anything else → 404.
   - Anything else → 404 (non-GET on `/`, `/dd.xml` → 405).
4. Execute: `.reply` → send and close. `.launch(q)` → `launchingUntil = now + 30 s`, reply **201** with `LOCATION: http://<host>/apps/YouTube/run` (no body), then `bridge.launch(q)`. `.forward(r)` → `Task { let response = await bridge.forward(r) }`; nil → execute `nativeAppDecision` with `appReady: false` (so a POST launches cold); else reply `DIALRouting.reply(for:)`, and if the method is POST and the status is 201 → `bridge.didConnect()`.
5. Log: `"\(method) \(path) → \(status) from \(clientIP)"` (L7).

Local IPv4 of a connection (no string formatting surprises):

```swift
private static func localIPv4(of connection: NWConnection) -> String? {
    guard case .hostPort(let host, _) = connection.currentPath?.localEndpoint,
          case .ipv4(let address) = host else { return nil }
    return address.rawValue.map(String.init).joined(separator: ".")
}
```

### SSDP socket (SSDPResponder)

BSD sockets on the main queue (as the notes recommend; `NWConnectionGroup` multi-interface behavior is unverified):

```swift
let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
var yes: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
address.sin_family = sa_family_t(AF_INET)
address.sin_port = SSDP.port.bigEndian
address.sin_addr.s_addr = INADDR_ANY
// bind via withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, …) } }
var request = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(SSDP.multicastAddress)),
                      imr_interface: in_addr(s_addr: inet_addr(interfaceIPv4)))
setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size))
_ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
// event handler: MainActor.assumeIsolated { loop recvfrom(fd, buffer[2048], …, &sender, &senderLength) until it returns -1 }
// cancel handler: close(fd)
```

- `start(interfaceIPv4:location:)`; any failing call → `close(fd)` and state `.failed` with `"Port 1900 is in use"` for `EADDRINUSE`, else `String(cString: strerror(errno))`.
- For each datagram where `SSDP.isDIALSearch` → `sendto(fd, reply, …, &sender, senderLength)`. If `sendto` fails with `EHOSTUNREACH` or `EPERM`, log once per start: "Can't answer phones: allow Local Network for MMTVL in System Settings → Privacy & Security" and set state `.failed("Allow Local Network for MMTVL in System Settings")`.
- `SERVER` header: `"macOS/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) UPnP/1.1 MMTVL/1.0"`.

`CastReceiver` starts the `DIALServer` first (it needs the port for `LOCATION`), then the responder with `LocalAddress.primaryIPv4()`. No address → state `.failed("No network connection")` and wait for the path monitor. An `NWPathMonitor` (main queue) calls `restart()` when the path's `status` or its interface list changes, and `AppDelegate.systemDidWake` calls `restart()`. `state` is `.ready` when both run.

### Casting workflow: before, during, after

Every way in which a phone puts something on the TV, and what MMTVL does around it. "Takeover" means `launcher.homePressed(); router.goHome()` plus bringing the target forward; it never asks for the PIN (user choice).

| Phase | YouTube cast (DIAL, D30) | Android mirroring (Reflector, D32) | AirPlay (macOS receiver, D12) | Plex (Plex HTPC) |
|---|---|---|---|---|
| **Before** (idle) | `CastReceiver` answers SSDP/DIAL while `youtubeCastEnabled`; phones list **"MMTVL"** in the YouTube app's Cast menu. | MMTVL keeps Reflector running hidden (L18); Android's Cast tile lists **"MMTVL Screen Mirroring"**. The Android YouTube app may list it too: use "MMTVL" there (L23 footer). | macOS's receiver is on (Settings → Casting checks it); iPhones list the Mac. | Plex HTPC must be running (opened once since login). |
| **Start** | Takeover → YouTube screen; an active Reflector session is ended first (L21). | Session window appears → takeover (Live TV stops, YouTube pauses) → Reflector activated and full screen (L20). | macOS shows its own full-screen AirPlay view over everything; MMTVL does nothing (its playback keeps playing underneath: see *Risks*). | Plex HTPC plays in its own window; MMTVL does nothing. |
| **During** | Remote works in YouTube as usual; Home leaves (YouTube pauses; the phone stays connected). | Home **ends the session** and shows home (L21). Other remote keys go to Reflector (harmless); if Escape leaves full screen, L20 restores it. | Home shows MMTVL; the AirPlay stream continues behind until the iPhone stops. | Home shows MMTVL; Plex keeps running (D18). |
| **After** (phone stops) | YouTube stays on screen (leanback shows its own "disconnected"); Back/Home as usual. | Session window closes → MMTVL comes back to the home screen (L22). | macOS closes its view; MMTVL is what was in front again. | Plex stays in front, as today. |

## Implementation steps

Branch first: `git switch -c m7b-phone-casting`. Build after every step (`xcodebuild … build`) and run the step's tests.

- [x] **1. Phone remote icon and manifest**: `RemoteServer/HTTPRequest.swift`, `RemoteServer/RemoteWebAssets.swift`, `RemoteServer/PhoneRemoteIcon.swift` (new), `RemoteServer/RemoteServer.swift`, `RemoteServer/Web/remote.html`, `MMTVLTests/HTTPRequestTests.swift`, `MMTVLTests/PhoneRemoteIconTests.swift` (new)
  - `HTTPHeader`, `HTTPResponse.make(contentType: String?, headers:)`, `HTTPResponse.reason(for:)` as sketched. Header order: status line, Content-Type (if any), Content-Length, the extra headers, Connection, Cache-Control, X-Content-Type-Options.
  - `RemoteWebAsset.generated`, the new paths and `RemoteWebManifest.json` (L10). Keep `data(for:bundle:)` for bundle files only (returns nil for generated ones).
  - `PhoneRemoteIcon.png(size:)`: `Image("Logo").resizable().interpolation(.high).frame(width: size, height: size)` rendered with `ImageRenderer` (`scale = 1`), `cgImage` → `NSBitmapImageRep(cgImage:).representation(using: .png, properties: [:])`. Cache in a `[Int: Data]` static dictionary. The `Logo` image set already exists in `Assets.xcassets` (don't change it).
  - `RemoteServer.response(for:)`: for `.icon(size)` serve `PhoneRemoteIcon.png(size:)`, for `.manifest` serve `RemoteWebManifest.json`; nil data → 404.
  - `remote.html` `<head>`: `<link rel="apple-touch-icon" href="apple-touch-icon.png">`, `<link rel="icon" type="image/png" sizes="192x192" href="icon-192.png">`, `<link rel="manifest" href="remote.webmanifest">`, `<meta name="apple-mobile-web-app-title" content="MMTVL">`.
  - Tests: the new paths map to the right `generated` values and content types; `/favicon.ico` still nil; `make` with extra headers and nil content type; `reason(for:)`; the manifest decodes as JSON with two icons; `PhoneRemoteIcon.png(size: 180)` starts with the PNG signature and `NSBitmapImageRep(data:)` reports 180 × 180 pixels.
  - Done when: tests pass; with the app running, `curl -sI http://localhost:8765/apple-touch-icon.png` shows `200` and `image/png`, and opening `http://localhost:8765/icon-512.png` shows the icon.

- [x] **2. DIAL protocol (pure)**: `Cast/DIALProtocol.swift` (new), `MMTVLTests/DIALProtocolTests.swift` (new)
  - Everything in the `DIALProtocol.swift` sketch, following *Request flow* step 3 exactly. XML-escape `friendlyName` and the uuid in the device description (`&`, `<`, `>`, `"`, `'`). Device description:
    `<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0"><specVersion><major>1</major><minor>0</minor></specVersion><URLBase>http://HOST</URLBase><device><deviceType>urn:dial-multiscreen-org:device:dial:1</deviceType><friendlyName>NAME</friendlyName><manufacturer>MMTVL</manufacturer><modelName>MMTVL</modelName><UDN>uuid:ID</UDN></device></root>`
  - App status: `<?xml version="1.0" encoding="UTF-8"?><service xmlns="urn:dial-multiscreen-org:schemas:dial" dialVer="2.1"><name>YouTube</name><options allowStop="false"/><state>stopped</state></service>`; with `running: true` the state is `running` followed by `<link rel="run" href="run"/>`.
  - SSDP reply lines in this order: `HTTP/1.1 200 OK`, `CACHE-CONTROL: max-age=1800`, `DATE: <RFC 1123, GMT>` (a `DateFormatter` with `en_US_POSIX`, GMT, `EEE, dd MMM yyyy HH:mm:ss 'GMT'`), `EXT:`, `LOCATION: …`, `SERVER: …`, `ST: urn:dial-multiscreen-org:service:dial:1`, `USN: uuid:<id>::urn:dial-multiscreen-org:service:dial:1`, then an empty line.
  - `DIALRequest.parse`: head up to `\r\n\r\n` (over 16 KB → `.tooLarge(431)`), request line as in `HTTPRequestHead`, header lines `Name: value` (trimmed; names lowercased; a line without `:` → `.invalid`); `content-length` (missing → 0; not a number → `.invalid`; > 4096 → `.tooLarge(413)`); `.incomplete` until the whole body arrived; body decoded as UTF-8. Path: strip the query, collapse repeated slashes.
  - `isForbiddenOrigin`: lowercase the value; true when it starts with `http://` or `https://`. `nil`, empty, `package:…`, `null` → false.
  - `sanitizedLaunchQuery` per L6, using `URLComponents` with `percentEncodedQuery = body` (a body with spaces or that `URLComponents` rejects → nil); output re-encoded in the original order (`URLComponents().queryItems = kept; .percentEncodedQuery ?? ""`).
  - Tests: M-SEARCH accepted (CRLF and LF, mixed-case header names, quoted and unquoted MAN); NOTIFY, wrong ST, `ssdp:all`, empty and binary data rejected; reply contains each line and ends with CRLF CRLF; parse cases (incomplete head, incomplete body, body exactly 4096 and 4097, 431, invalid header line, query stripped, `//apps//YouTube` normalized); every routing row of *Request flow* step 3 including 403 with `Origin: https://evil.example`, allowed with `Origin: package:com.google.ios.youtube`, 405, 404 for `/apps/Netflix`; native GET running/stopped; POST with `pairingCode=abc-123&theme=cl&foo=bar` → launch query `pairingCode=abc-123&theme=cl`; POST empty → `launch(query: nil)`; POST `a b` → 400; `reply(for:)` with handled false → 400 and status 0 → 200.
  - Done when: tests pass.

- [x] **3. DIAL server, SSDP and the cold path**: `Cast/DIALServer.swift`, `Cast/SSDPResponder.swift`, `Cast/CastReceiver.swift` (all new), `App/AppSettings.swift`, `App/AppDelegate.swift`, `YouTube/YouTubeController.swift`, `YouTube/YouTubeConfig.swift`, `Launcher/AppRouter.swift`, `MMTVL.xcodeproj/project.pbxproj` (build setting only), `MMTVLTests/FakeYouTube.swift`, `MMTVLTests/AppRouterTests.swift`, `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/YouTubeConfigTests.swift`, `MMTVLTests/DIALServerTests.swift` (new)
  - `AppSettings`: `youtubeCastEnabled = true`, `castDeviceID: String?` (both `decodeIfPresent`). In `applicationDidFinishLaunching`, if `castDeviceID` is nil, set `UUID().uuidString.lowercased()` and save `settings.json` once.
  - `YouTubeConfig.launchURL(query:)`: `startURL` with `percentEncodedQuery = query` (empty → `startURL`).
  - `YouTubeController`: split `open()` into `makeWebViewIfNeeded()` + `load()`; `launch(query:)` = `makeWebViewIfNeeded()`, then load `launchURL(query:)` (set `phase = .loading`). Add `launch(query:)` to `YouTubeHosting`; `FakeYouTube` records `launches: [String]`.
  - `AppRouter.castYouTube(query: String?)` (L4): `if screen != .youtube { goHome() }`, then `query.map(youtube.launch(query:)) ?? youtube.open()`, `screen = .youtube`. No PIN check (user choice).
  - `DIALServer`, `SSDPResponder`, `CastReceiver` per *Design*. In this step `CastBridge.isAppReady` returns false and `forward` returns nil (the bridge comes in step 4).
  - `AppDelegate`: create `CastReceiver(deviceID:friendlyName: "MMTVL", bridge:)`; start it when `settings.youtubeCastEnabled` (kiosk and `-windowed` alike, like the phone remote); `castToTV(query:)` = `launcher.homePressed(); router?.castYouTube(query: query); windowController?.show()`; `systemDidWake` calls `castReceiver?.restart()`; `applySettings` starts/stops it when `youtubeCastEnabled` changes; `castReceiver.onStateChange` → `router?.settings.refreshStatus()`.
  - `project.pbxproj`: both `INFOPLIST_KEY_NSLocalNetworkUsageDescription` lines → `"MMTVL connects to your Plex Media Server and lets phones on this network find it for casting."`
  - Tests: `castYouTube` from home, Live TV (FakeLiveTV left), Settings (pairing ended, like `goHomeFromSettingsEndsPhonePairing`), the PIN screen, and YouTube itself (no `goHome`, no pause); with a query → `launches == [query]`; a PIN-protected YouTube tile with a PIN set still casts without a PIN screen. Settings decoding defaults. `launchURL`. `DIALServerTests` (serialized, like `RemoteServerTests`): start `DIALServer` on `.any`, `GET http://localhost:<port>/dd.xml` → 200 with `Application-URL`; `POST /apps/YouTube` with body `pairingCode=x` → 201 with `Location` and the launch closure got `"pairingCode=x"`; `GET /apps/YouTube` right after → body contains `<state>running</state>`.
  - Done when: tests pass. On the Mac with MMTVL running: `curl -s http://localhost:8770/dd.xml` prints the XML; `curl -s -X POST -H 'Origin: https://x.example' http://localhost:8770/apps/YouTube -o /dev/null -w '%{http_code}'` prints 403; this M-SEARCH prints a reply naming port 8770 (answer the Local Network prompt with Allow if it appears):
    ```sh
    python3 - <<'EOF'
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
    s.sendto(b'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 1\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n', ('239.255.255.250', 1900))
    print(s.recvfrom(2048)[0].decode())
    EOF
    ```
    and `curl -s -X POST -d 'v=dQw4w9WgXcQ' http://localhost:8770/apps/YouTube` switches MMTVL to YouTube.

- [ ] **4. YouTube bridge (warm path)**: `YouTube/YouTubeDIAL.swift` (new), `YouTube/YouTubeController.swift`, `App/AppDelegate.swift`, `MMTVLTests/YouTubeDIALTests.swift` (new)
  - `YouTubeController.init(userAgent:castEnabled: Bool)`; when `castEnabled` at web view creation, add `YouTubeDIAL.shimScript` as a `WKUserScript` (`.atDocumentStart`, `forMainFrameOnly: true`; the default page content world) and `userContentController.add(delegate, name: YouTubeDIAL.messageHandlerName)`. AppDelegate passes `settings.youtubeCastEnabled` (read at creation, L5).
  - **Fix the delegate:** `userContentController(_:didReceive:)` calls `pageDidExit()` only for `YouTubeKeyMap.messageHandlerName`; for `YouTubeDIAL.messageHandlerName` with body `["type": "ready", "app": "YouTube"]` it calls `controller?.dialDidBecomeReady()`.
  - `private(set) var isDIALReady = false` (`@ObservationIgnored`), set true by `dialDidBecomeReady()` (log "Leanback registered its DIAL handlers"), false in `load()`, `didFail`, `contentProcessDidTerminate`, and a new `webView(_:didStartProvisionalNavigation:)` delegate method.
  - `func handleDIAL(_ request: DIALAppRequest) async -> DIALAppResponse?`: nil unless `isDIALReady` and a web view exist. Call `webView.callAsyncJavaScript(YouTubeDIAL.handleScript, arguments: ["app": …, "method": …, "path": …, "body": …, "host": …], in: nil, in: .page, completionHandler:)` inside `withCheckedContinuation`, racing a 3 s `DispatchQueue.main.asyncAfter`; resume exactly once (a small `final class` flag box if the compiler rejects a captured `var`). Map the result with `YouTubeDIAL.response(fromJavaScript:)`; errors → nil (log the error's description, never the body).
  - AppDelegate: the `CastBridge` now uses `youtube.isDIALReady` and `youtube.handleDIAL`; `didConnect` → `castToTV(query: nil)`.
  - Tests: `response(fromJavaScript:)` with a full dictionary, `found: false`, missing fields (defaults), `NSNumber` status, bad header entries skipped, `nil`/`NSNull`/a string → nil; `shimScript` contains `h5vcc`, `DialServer` and `mmtvlDial`, and doesn't contain `system` or `runtime`.
  - Done when: tests pass; with MMTVL running and YouTube opened once (Debug build), Safari → Develop → this Mac → the YouTube page console shows `typeof window.h5vcc.dial.DialServer === "function"`; the log (`… AND category == "YouTube"`) shows "Leanback registered its DIAL handlers" (if it never appears, record it under *Deviations*: leanback may create the server lazily, and step 5 tells whether the cold path is enough); `curl -s http://localhost:8770/apps/YouTube` then returns leanback's XML (with `<additionalData>`), also after going Home.

- [ ] **5. Cast from real phones (with the user)**: no files (results go in *Deviations & questions* and *Manual verification*)
  - Ask the user to run, on the dev Mac (or the mini), with an iPhone and, if available, an Android phone on the same Wi-Fi, each with the YouTube app signed in:
    1. MMTVL on the home screen, YouTube never opened since launch: Cast button → "MMTVL" listed? Pick it → MMTVL switches to YouTube and the phone says connected; play a video from the phone; pause/seek/volume from the phone.
    2. Same with YouTube already opened once and the user back on the home screen (warm path).
    3. From Live TV, and with Plex HTPC in front: the cast takes the TV (L4).
    4. Disconnect on the phone; cast again.
    5. After sleeping and waking the Mac: still listed.
  - Watch `log stream --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "Cast"' --level info` during each.
  - If the phone never lists MMTVL: check the M-SEARCH arrives (log), Local Network permission, the firewall (System Settings → Network → Firewall: allow MMTVL), and whether port 1900 bound (`lsof -nP -iUDP:1900`). If it lists but pairing fails only on the cold path: switch L2 to "load YouTube off screen at launch when casting is on" (record the change and ask the user first). Stop and ask if both paths fail.
  - Done when: the user confirms 1–4 on at least one phone, or the failure is recorded with logs and the user has decided what to do.

- [ ] **6. Settings → Casting**: `Cast/AirPlayReceiverProbe.swift` (new), `Settings/SettingsTypes.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsEnvironment.swift`, `App/AppDelegate.swift`, `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/SettingsCastingTests.swift` (new), `MMTVLTests/AirPlayReceiverProbeTests.swift` (new)
  - Types per *Key types*. `SettingKey.youtubeCastEnabled` (`\.youtubeCastEnabled`). `SettingsPage.casting` (title "Casting", image `.symbol("airplay.video")`, hint like `.phoneRemote`). `SettingsAction.openAirPlaySettings`.
  - Root page: a section `casting` titled "Casting" right after the YouTube section, with one row `casting` "Casting", `showsDisclosure`, action `.push(.casting)`.
  - Casting page sections:
    - `cast.youtube` titled "YouTube": row `cast.youtube.enabled` "Cast from the YouTube App", value On/Off, detail when on: `.ready` → "Phones on this network list \"MMTVL\"", `.starting` → "Starting…", `.failed(m)` → m, `.off` → nil; action `.toggle(.youtubeCastEnabled)`. Footer: "In the YouTube app on a phone, tap Cast and choose MMTVL. A cast switches the TV to YouTube. YouTube → Settings → Link with TV Code also works."
    - `cast.airplay` titled "AirPlay": row `cast.airplay.receiver` "AirPlay Receiver", value "On" / "Off" / "Unknown", detail "Opens AirDrop & Handoff in System Settings", action `.openAirPlaySettings`. Footer: "Turn on AirPlay Receiver and set Allow AirPlay for to \"Anyone on the Same Network\", or \"Current User\" if every phone uses your Apple Account. iPhones then list this Mac under Screen Mirroring and in AirPlay menus."
    - `cast.plex` titled "Plex": info row `cast.plex.htpc` "Plex HTPC", value "Running" / "Not Running" / "Not Installed". Footer: "Phones cast to Plex HTPC while it runs, signed in to your Plex account: in the Plex app, tap Cast and choose Plex HTPC. Home leaves it running; after a restart, open it once."
  - `SettingsModel`: `casting` status read in `init` and `refreshStatus()`; `push(.casting)` calls `environment.refreshCasting()`; `.openAirPlaySettings` calls `environment.openAirPlaySettings()`.
  - `AirPlayReceiverProbe.check()` per L15 (`NWConnection(host: "127.0.0.1", port: 7000, using: .tcp)`, main queue; `.failed`/`.waiting` with `ECONNREFUSED` → `.off`; read until `\r\n\r\n` or 4 KB; resume once; 2 s timeout → `.unknown`).
  - AppDelegate: `castingSettingsStatus()` from `castReceiver.state` (`.off` when the setting is off), the cached `airPlayState`, and Plex HTPC per L16; `refreshCasting` runs the probe then `router?.settings.refreshStatus()`; `openAirPlaySettings` opens the URL from *Research* with `NSWorkspace.shared.open`.
  - `SettingsRecorder`: `casting`, `castingRefreshes`, `airPlaySettingsOpened`.
  - Tests: root row pushes `.casting` and refreshes; each status renders the expected value/detail; toggling applies `youtubeCastEnabled` false; the AirPlay row opens settings; the Plex row has no action. `isAirPlayResponse` for the verified 403 head (`Server: AirTunes/980.77.5`), a lowercase `server:` header, another server, garbage.
  - Done when: tests pass; on the Mac, Settings → Casting shows AirPlay "On" (then "Off" after switching the receiver off in System Settings; if it still says On, record it: the off state is unverified), Plex HTPC Running/Not Running as it is, and toggling YouTube off makes the step 3 M-SEARCH script time out.

- [ ] **7. Reflector spike (with the user)**: no app code; results go into *Research & findings* (a "Reflector spike results" list) and, if a constant changes, into L19/L21/`MirroringDetector`
  - The user installs Reflector 4 on the Mac that will run MMTVL (license or trial) and sets it up per L23 (AirPlay off, Google Cast on, Always on Top off, Display Fullscreen on, Show Client Name off, no connection prompt, receiver name "MMTVL Screen Mirroring", Local Network allowed). macOS's AirPlay Receiver stays on.
  - Record, with an Android phone mirroring through Quick Settings → Cast:
    1. The bundle id: `mdls -name kMDItemCFBundleIdentifier "/Applications/Reflector 4.app"` (update `ReflectorMonitor.bundleID` if it differs).
    2. Reflector's windows when idle, while mirroring, and after the phone stops, with this script (save it in the scratchpad, run `swift windows.swift` each time):
       ```swift
       import CoreGraphics
       let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
       for w in list where (w[kCGWindowOwnerName as String] as? String ?? "").contains("Reflector") {
           print(w[kCGWindowOwnerPID as String] ?? "-", "layer", w[kCGWindowLayer as String] ?? "-",
                 "alpha", w[kCGWindowAlpha as String] ?? "-", w[kCGWindowBounds as String] ?? "-")
       }
       ```
       Done right if idle windows (preferences, menu-bar extras) are below 25 % of the screen and the session window is above it. If not, change L19's rule (e.g. also require `layer == 0`) and note it.
    3. With MMTVL in front (kiosk): does the mirroring window come in front by itself, and is it a native full-screen Space (a Space-switch animation) or a plain window covering the screen?
    4. What Escape does in the session window, and what closing the window does: in the spike, use Accessibility Inspector (Xcode → Open Developer Tool) to confirm the window has a close button; press it and see whether the phone's cast ends. Then reconnect and try ⌘W.
    5. When the phone stops casting: does the window close? Does Reflector stay running with no window? Which app is frontmost afterwards?
    6. Audio: does the phone's sound come out of the TV (the Mac's default output, through SoundSource)?
    7. `lsof -nP -iUDP:1900` with Reflector running; then start MMTVL with casting on: does Settings → Casting → YouTube say ready, and do both the Android Cast tile (Reflector) and the YouTube app (MMTVL) still work? Run step 3's M-SEARCH script: does Reflector answer too (a second reply)?
    8. iPhone AirPlay (Screen Mirroring) to the Mac still works with Reflector running (AirPlay off in Reflector).
    9. In the Android YouTube app's Cast list: which entries appear; what happens when "MMTVL Screen Mirroring" is picked.
    10. Does Reflector have a launch-at-login or start-hidden option, and a window or Dock icon when idle?
  - Stop and ask the user if: no Reflector window is distinguishable from idle windows (L19 can't work), both close button and ⌘W fail to disconnect (L21 can't work), or port 1900 can't be shared (one of YouTube casting / Android mirroring must go; the user decides).
  - Done when: all ten answers are recorded and the user has confirmed any change to L19–L22.

- [ ] **8. Reflector monitor and the mirroring workflow**: `Cast/MirroringDetector.swift`, `Cast/ReflectorMonitor.swift` (new), `Launcher/WindowFullScreener.swift`, `Input/SyntheticInput.swift`, `App/AppSettings.swift`, `App/AppDelegate.swift`, `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `MMTVLTests/MirroringDetectorTests.swift` (new), `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/SettingsCastingTests.swift`, `MMTVLTests/SettingsTestSupport.swift`
  - `AppSettings.reflectorAutoStart = true` (`decodeIfPresent`). `SettingKey.reflectorAutoStart`.
  - `MirroringDetector` and `RestartLimiter` per *Key types* and L19 (with step 7's constants).
  - `WindowFullScreener`: `closeWindows(pid:minimumSize:) -> Int` (every AX window of the pid at least that size: `kAXCloseButtonAttribute` → `AXUIElementPerformAction(button, kAXPressAction)`; returns how many it pressed).
  - `SyntheticInput.postKey(_:flags:)` (keyDown/keyUp with the given flags, e.g. `.maskCommand`; existing `postKey(_:)` calls it with `[]`).
  - `ReflectorMonitor` per L18–L21:
    - `start()`: observe `NSWorkspace.didLaunchApplicationNotification` / `didTerminateApplicationNotification` for `bundleID`; if running, start a 1 s `Timer` (main run loop) that reads `CGWindowListCopyWindowInfo`, maps Reflector's windows to `WindowSnapshot`, feeds `MirroringDetector.update(windows:screen:)` with `NSScreen.screens.first`'s frame **converted to CGWindowList coordinates** (top-left origin: for the main screen, origin (0, 0) and the same size); stop the timer when Reflector quits.
    - Auto-start (L18) at `start()`, from `systemDidWake()`, and 5 s after a terminate when `RestartLimiter.allowRestart`. Log "Started Reflector in the background" / "Reflector quit; restarting" / "Reflector keeps quitting; not restarting".
    - `.began` → `isMirroring = true`, `onSessionBegan`; `needsFullScreen` → `WindowFullScreener.makeFullScreen(pid:)` (at most every 3 s); `.ended` → `isMirroring = false`, `onSessionEnded`. Every change → `onStatusChange`.
    - `endMirroring()`: `closeWindows(pid:minimumSize:)` with the L19 size; if it pressed none, activate Reflector and post ⌘W (`kVK_ANSI_W`) once per `sessionWindows` entry, 150 ms apart.
  - `AppDelegate`:
    - Create and `start()` the monitor after the window is shown; `systemDidWake` calls `systemDidWake()`.
    - `onSessionBegan` → `launcher.homePressed(); router?.goHome()`, then `NSRunningApplication.runningApplications(withBundleIdentifier:)`'s first `.activate()` (L20).
    - `onSessionEnded` → if the frontmost app is Reflector, MMTVL or nil: `router?.goHome(); windowController?.show()` (L22).
    - `handleGlobal(.home)`: if `reflector.isMirroring`, `reflector.endMirroring()` first (L21). The local Home (MMTVL in front) needs nothing: a session only exists with Reflector in front, and if MMTVL was brought forward some other way, Home on MMTVL also calls `endMirroring()` when `isMirroring` (add it where `router.goHome` is reached from the Home command: wrap `inputRouter.handler` so `.home` first ends a session).
    - `castToTV(query:)` (step 3): if `reflector.isMirroring`, `reflector.endMirroring()` before the router call.
    - Settings: `castingSettingsStatus()` fills `reflector` (`.notInstalled` when `NSWorkspace.urlForApplication(withBundleIdentifier:)` is nil, `.mirroring`, `.ready` when running, else `.notRunning`); `refreshCasting` also refreshes it; `applySettings` passes `reflectorAutoStart` to the monitor (on: start Reflector now if installed and not running).
  - Settings → Casting gains section `cast.android` titled "Android", between AirPlay and Plex:
    - Row `cast.android.reflector` "Reflector", value "Not Installed" / "Not Running" / "Ready" / "Mirroring", detail when not installed "Install Reflector 4 from airsquirrels.com", info only.
    - Row `cast.android.autostart` "Start Reflector with MMTVL", On/Off, action `.toggle(.reflectorAutoStart)` (shown only when installed).
    - Footer (L23): "On an Android phone: Quick Settings → Cast → MMTVL Screen Mirroring. For YouTube, use Cast in the YouTube app and pick MMTVL instead. Home on the remote ends mirroring. In Reflector's Preferences: turn AirPlay off and Google Cast on, Always on Top off, Display Fullscreen on, Show Client Name off, no connection prompt, and name it MMTVL Screen Mirroring."
  - Tests: `MirroringDetector` (no windows; a small window only; a big window → began once; big window for several polls → no repeat; one missed poll → still active; two → ended; two devices then one → still active; `needsFullScreen` true for a centered half-size window, false for a screen-sized one); `RestartLimiter` (3 allowed, 4th refused, allowed again after 10 min, `reset`); settings decoding; the Android rows for each `Reflector` state, the toggle applying `reflectorAutoStart`, the autostart row hidden when not installed.
  - Done when: tests pass, and on the Mac with Reflector set up per L23 (the user's phone):
    - MMTVL launch with Reflector quit → Reflector starts hidden, MMTVL stays in front; quitting Reflector → it comes back after ~5 s.
    - Mirroring from the home screen and from Live TV → Live TV stops, the phone's screen is full screen on the TV.
    - Phone stops → MMTVL's home screen within ~3 s.
    - Home on the remote (and on the phone remote) while mirroring → the phone's cast ends, home screen shows.
    - A YouTube cast from another phone while mirroring → mirroring ends, YouTube shows.
    - Escape during mirroring → full screen comes back within ~3 s (or Escape does nothing).
    - Settings → Casting → Android shows Ready / Mirroring live.

- [ ] **9. Trackpad: Mac side**: `Input/PhonePointer.swift` (new), `Input/SyntheticInput.swift`, `RemoteServer/RemoteMessage.swift`, `RemoteServer/PhoneRemote.swift`, `App/AppDelegate.swift`, `MMTVLTests/PointerMathTests.swift` (new), `MMTVLTests/RemoteMessageTests.swift`, `MMTVLTests/PhoneRemoteTests.swift`
  - `RemoteWireMessage` gains `dx: Double?`, `dy: Double?`, `button: String?`. `ClientMessage.pointer(PointerAction)` decoded from types `pointer` (`.move`), `scroll` (`.scroll`) — both need finite `dx` and `dy` with `abs ≤ PointerMath.maxDelta` — and `click` (`PointerButton(rawValue:)`).
  - `PhoneRemoteEnvironment.pointer: (PointerAction) -> Void`. `receive`: authenticated only; `environment.canPostEvents()` false → the Accessibility toast at most every 5 s per session (store `lastAccessToast: Date?` in `Session`, use `environment.now()`), else `environment.pointer(action)`.
  - `SyntheticInput`: `pointerLocation`, `movePointer(to:delta:)`, `click(_:at:clickCount:)`, `scroll(wheel1:wheel2:)`, `activeDisplayBounds()` per *Research*, all through `makeSource()`/`post(_:)` so they carry the marker.
  - `PhonePointer.perform`: `.move` → `accelerated`, new point = current + delta, `clamp`, `movePointer`; `.click` → `ClickCounter.register` then `click`; `.scroll` → `scrollWheels` then `scroll`.
  - AppDelegate: one `PhonePointer`; `pointer: { [weak self] in self?.phonePointer.perform($0) }`.
  - Tests: decoding (valid move/scroll/click, NaN-free JSON can't carry NaN so test a missing `dy`, `dx: 5000`, `button: "middle"`); `PhoneRemote` routes pointer actions when authenticated and allowed, ignores them unauthenticated, toasts once within 5 s and again after; `accelerated` (zero stays zero, slow ×1.5, fast ×3, direction kept); `clamp` (inside, outside to the right of a single display, a gap between two displays of different heights, no displays); `scrollWheels` signs; `ClickCounter` (single, double within 0.5 s and 6 pt, reset after time, distance or button change, caps at 3).
  - Done when: tests pass (the phone UI comes next).

- [ ] **10. Trackpad: phone page**: `RemoteServer/Web/remote.html`, `remote.css`, `remote.js`
  - Header: after `#front-app`, a button `<button type="button" id="mode-toggle" class="mode-toggle" aria-label="Switch to trackpad">Trackpad</button>` (pushed to the right; label "D-pad" while in trackpad mode).
  - After the `.dpad` div: `<div id="trackpad" class="trackpad" hidden aria-label="Trackpad"><span class="trackpad-hint">Tap to click · two fingers to scroll · two-finger tap to right-click</span></div>`. CSS: same width as `.dpad`, `aspect-ratio: 1`, `border-radius: 32px`, `background: var(--button)`, `touch-action: none`, centered muted 14px hint, `user-select: none`.
  - JS (per L11): `setMode('dpad'|'trackpad')` toggles `.dpad`/`#trackpad` `hidden`, the button label and `aria-label`, and stores `mmtvl.mode` (try/catch like the token). Pointer events on `#trackpad` with `setPointerCapture`; a `Map` of active pointers; one active pointer adds to a move accumulator, two or more add `delta / count` to a scroll accumulator; `requestAnimationFrame` flushes non-zero accumulators as one `pointer` and one `scroll` message (rounded to 0.1). Tap detection on the last pointer up: total time < 250 ms and total movement < 10 px → `click` with `right` if two or more pointers were down during the gesture, else `left`; `navigator.vibrate(5)` if available. Reset on `pointercancel`.
  - Done when: on an iPhone (and Android if available) the toggle switches views and is remembered after a reload; moving, tapping, double-tapping (selects a word in a browser), two-finger tap (context menu) and two-finger scroll work in Brave; scrolling moves content the same way as the finger (if reversed, set `PointerMath.scrollSign = -1` and note it under *Deviations*); without Accessibility the toast appears but doesn't repeat continuously.

- [ ] **11. Docs**: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this file
  - `CLAUDE.md`: a log-stream line for `category == "Cast"`; `settings.json` keys `youtubeCastEnabled` and `castDeviceID`; a *Casting* bullet in Conventions (ports TCP 8770 and UDP 1900, `Cast/` folder, the shim and L7's never-log rule, the cold/warm paths, Settings → Casting, how to test with the M-SEARCH script and `curl`); phone remote: icon paths and trackpad messages; synthetic input: mouse events also carry the marker; the Local Network text now mentions casting; `settings.json` `reflectorAutoStart`; a *Reflector* bullet (bundle id, L23's preference checklist, that MMTVL starts it hidden, detects sessions by window size, and that Home ends mirroring; how to watch it: `category == "Reflector"`).
  - Master plan: tick nothing new in §4 (D30/D31 are added at planning time); fix anything the build changed; set M7b to `In progress` (it becomes `Done` after step 13).
  - Done when: docs match the code.

- [ ] **12. On-TV QA pass, M7 + M7b (with the user)**: no files except plan checkboxes and *Deviations*
  - On the Mac mini over HDMI, kiosk mode, Release-like Debug build: walk M7's *Manual verification* list (in `M7-launcher-polish.md`) and this plan's, ticking each item the user confirms in its own plan. Include Q9 (does "Add to Home Screen" open the remote without browser chrome on iOS 26 / Android) and Q14 (Plex mobile app → Plex HTPC).
  - Record every problem under *Deviations & questions* of the plan it belongs to, as a follow-up, with what was seen. Fix only small, obvious issues the user asks to fix now, each built and tested.
  - Done when: the user has gone through both lists and decided which follow-ups remain.

- [ ] **13. Full test run and status**: no files except docs
  - Run all tests; all pass. Set M7b to `Done` in the master plan and here; resolve Q13/Q14 and Q9 with what step 12 found.
  - Done when: tests pass and the master plan is current.

## Tests

- New test files: `PhoneRemoteIconTests.swift`, `DIALProtocolTests.swift`, `DIALServerTests.swift`, `YouTubeDIALTests.swift`, `SettingsCastingTests.swift`, `AirPlayReceiverProbeTests.swift`, `MirroringDetectorTests.swift`, `PointerMathTests.swift`.
- Extended: `HTTPRequestTests.swift` (headers, reasons, new asset paths), `AppRouterTests.swift` (`castYouTube`), `AppSettingsTests.swift` (new keys), `YouTubeConfigTests.swift` (`launchURL`), `RemoteMessageTests.swift` (pointer messages), `PhoneRemoteTests.swift` (pointer routing, throttled toast), `FakeYouTube.swift`, `SettingsTestSupport.swift`.
- Commands (CLAUDE.md): `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`; one suite, e.g. `-only-testing:'MMTVLTests/DIALProtocolTests'`.

## Manual verification

- [ ] The Mac app icon (the "tv" logo) shows in the Dock, Finder and the app switcher, not inside a gray tile.
- [ ] Phone icon: Add to Home Screen on iPhone shows the "tv" logo and the name "MMTVL"; on Android Chrome, the shortcut's icon (record which icon it used, or none).
- [ ] YouTube cast, cold: from the home screen with YouTube not opened since launch, the phone lists "MMTVL", the cast opens YouTube and plays.
- [ ] YouTube cast, warm: after YouTube was opened and left, the same works and the phone controls play/pause/seek/volume.
- [ ] A cast from Live TV leaves Live TV and shows YouTube; from Plex HTPC in front, MMTVL comes forward and Plex keeps running; from Settings, Settings closes.
- [ ] A YouTube tile with Require PIN still accepts casts without the PIN (user choice).
- [ ] Settings → Casting → Cast from the YouTube App off: the phone no longer lists MMTVL (may take a minute to drop from the phone's list); on again: listed.
- [ ] After sleep/wake and after switching Wi-Fi/Ethernet, the phone still finds MMTVL.
- [ ] YouTube's own Link with TV Code still pairs.
- [ ] Settings → Casting: AirPlay On/Off follows the System Settings switch; Select opens AirDrop & Handoff; an iPhone's Screen Mirroring lists the Mac after "Anyone on the Same Network".
- [ ] Android mirroring (Reflector): Quick Settings → Cast lists "MMTVL Screen Mirroring"; mirroring from the home screen, from Live TV and from YouTube takes over full screen with sound on the TV; stopping on the phone returns to the home screen; Home ends it; a YouTube cast ends it; after a restart of the Mac, Reflector is running hidden and MMTVL is in front; no watermark (licensed).
- [ ] Android YouTube app: picking "MMTVL" casts YouTube (D30); record what picking "MMTVL Screen Mirroring" does.
- [ ] iPhone AirPlay still goes to macOS's receiver with Reflector running.
- [ ] Plex: with Plex HTPC running, the phone's Plex app casts to it (record the Plex app version; Q14).
- [ ] Trackpad: move, click, double-click, right-click, scroll in Brave and in MMTVL (hovering tiles moves focus; clicking a tile opens it); pointer stays on screen at the edges; the D-pad still works after switching back.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Current phone YouTube apps don't use DIAL for this device, or YouTube's config disables it (`isPublicDialDevice`, IP validation "compromised") | Step 5: MMTVL never listed, or listed but nothing happens; leanback's `GET /apps/YouTube` answers but POST returns false | Link with TV Code keeps working (Settings footer says so). Record in Q13; leave casting on if harmless, else default it off. |
| The shim breaks leanback (startup error, black page) | YouTube fails to load only with casting on | Turn casting off in Settings and relaunch (L5); record and stop. |
| Leanback never constructs `DialServer` in WKWebView | No "registered" log in step 4 | The cold path (L2) still launches with the pairing code; a cast while YouTube is open reloads it. Acceptable; record. |
| `callAsyncJavaScript` is slow or blocked while the web view is off screen | Forwarded requests time out (3 s) on the home screen | The timeout falls back to the native answer, so a POST relaunches YouTube with the code. If that pairs, accept; else keep the web view in the window hierarchy (hidden) and ask the user. |
| Port 1900 already bound without `SO_REUSEPORT` (Plex Media Server on the mini) | Settings → Casting shows "Port 1900 is in use" | Quit or disable DLNA in Plex Media Server (Settings → DLNA) on the mini; record which. |
| Local Network permission denied, or the macOS firewall blocks incoming UDP/TCP | No M-SEARCH logged; `sendto` errors | Settings shows the fix text; allow MMTVL in Privacy & Security → Local Network and in the firewall. |
| The Mac's IP changes (no DHCP reservation) | Phones list MMTVL but connecting fails | `restart()` on path changes; the master plan already asks for a DHCP reservation (CLAUDE.md phone remote). |
| Port 7000 stays open with AirPlay Receiver off | Step 6 manual check | Record it under *Deviations*; ask the user whether the row should show only "AirPlay Settings" without a state. The row still opens the right page either way. |
| Plex's new mobile app can't cast to Plex HTPC | Step 12, Q14 | Footer says to use Plex HTPC's own UI or the phone remote; nothing to build. |
| Reflector and the DIAL responder can't share UDP 1900 | Step 7 item 7: Settings shows "Port 1900 is in use", or Android's Cast tile stops listing Reflector | Start Reflector before `CastReceiver` (MMTVL already does at launch) and retry; if they still can't share, the user picks one (Android mirroring or YouTube DIAL casting); record it. |
| Reflector doesn't come forward or its full screen fights MMTVL's kiosk window | Step 7 item 3; mirroring stays behind MMTVL | L20 activates it and sets AXFullScreen; if a native Space still loses, turn Display Fullscreen off and let L20 make it full screen. |
| Closing the window doesn't end the phone's cast | Step 7 item 4 | ⌘W fallback (L21). If neither works, Home only hides the session and the user stops it on the phone; ask the user. |
| Reflector idle windows look like a session | Step 7 item 2 | Tighten L19 (layer, size); record. |
| AirPlay to macOS's receiver plays over Live TV's sound | Seen in QA | Out of scope now (macOS gives no session signal); a later milestone could watch for the AirPlay full-screen window the same way as Reflector. |
| Reflector isn't updated for macOS 26/27 (last release 2024-12) | Crashes, no Cast discovery | L18's restart limit stops a crash loop; Settings shows Not Running; record and ask the user. |
| Synthetic scrolls are inverted by natural scrolling | Step 10 | Flip `PointerMath.scrollSign`. |
| Android Chrome ignores the icon over http | Step 12 | Cosmetic; record (Q9). |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
