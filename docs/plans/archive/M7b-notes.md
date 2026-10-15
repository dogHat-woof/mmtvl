# M7b — research notes (not a plan yet)

Gathered while planning M7 (2026-10-06). `/plan-milestone M7b` starts from here and re-checks anything marked unverified. M7b scope (master plan §6): phone remote home-screen icon, phone trackpad mode, YouTube DIAL discovery, casting setup checklist, then the on-TV QA pass for M7 + M7b.

## YouTube DIAL (phones cast to MMTVL without a TV code)

- **How VacuumTube does it** (v1.8.0, 2026-06-30: "Casting from phone to VacuumTube now works without a TV code"; source at commit 3fa684e, `src/preload/modules/h5vcc/`):
  - Its own code answers only **SSDP** and the **device description**. Everything under `/apps/YouTube` is answered by **leanback's own JavaScript** through a fake Cobalt `DialServer` object injected as `window.h5vcc = { dial: { DialServer } }`.
  - `dial/discover.js`: UDP 1900 with `reuseAddr`, joins 239.255.255.250; for `M-SEARCH *` with ST `urn:dial-multiscreen-org:service:dial:1` it replies by unicast: `HTTP/1.1 200 OK`, `CACHE-CONTROL: max-age=1800`, `DATE`, `EXT:`, `LOCATION: http://<LAN-IP>:<port>/`, `SERVER: <os>/<ver> UPnP/1.0 …`, `ST: …dial:1`, `USN: uuid:<id>::urn:dial-multiscreen-org:service:dial:1`.
  - `dial/server.js`: `GET /` → UPnP device XML (deviceType `urn:dial-multiscreen-org:device:dial:1`, friendlyName, `UDN uuid:<id>`) with header `Application-URL: http://IP:port/apps`.
  - The id is the page's `localStorage['yt.leanback.default::mdx-device-id'].data`.
- **Cobalt shim API** ([Cobalt IDL](https://github.com/youtube/cobalt/tree/25.lts.1%2B/cobalt/h5vcc/dial)): `new DialServer("YouTube")` with `onGet/onPost/onDelete(path, cb)`; `cb(req{path,method,body,host}, res{responseCode,body,mimeType,addHeader()}) → bool`, synchronous.
- **What leanback registers** (module `CobaltInAppDialService` in the 2026-10-06 bundle):
  - GET "/": 200 `text/xml; charset="utf-8"`, `<service xmlns="urn:dial-multiscreen-org:schemas:dial"><name>YouTube</name><options allowStop="false"/><state>running</state><link rel="run" href="http://{host}{path}/run"/><additionalData …>…</additionalData></service>`. Pass `host = "IP:port"`, `path = "/apps/YouTube"`.
  - POST "/": body is a query string with `pairingCode` or `reversePairingCode` (else false → send 400). Success: 201 with `LOCATION: http://{host}{path}/run`.
  - DELETE "/run": 501.
- **When the page isn't loaded:** leanback reads `pairingCode`, `v`, `t`, `theme`, `dialLaunch`, `additionalDataUrl` from `youtube.com/tv?…` (Netflix's [reference server](https://github.com/Netflix/dial-reference) launches `https://www.youtube.com/tv?<POST body>&additionalDataUrl=http%3A%2F%2Flocalhost%3A<port>%2Fapps%2FYouTube%2Fdial_data%3F`). `additionalDataUrl` must match `^https?://(localhost|127.0.0.1)(:\d+)?/`. Native side must answer `stopped` and DELETE → 404 itself while the WKWebView isn't live.
- **Spec** (DIAL 2.2, [dial-multiscreen.org](http://www.dial-multiscreen.org/dial/protocol-specification)): LOCATION/Application-URL absolute http with an IPv4 host; unknown app 404; XML `text/xml` with UTF-8 charset; POST body `text/plain`; launch → 201 + LOCATION. CORS §6.6: allow no Origin and non-http(s) origins (phone apps send `package:com.google.android.youtube`, `package:com.google.ios.youtube`); **reject other http(s) Origins** so LAN web pages can't launch.
- **macOS** ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)): no multicast entitlement on macOS; receiving multicast and sending UDP need **Local Network permission** (M7 adds `NSLocalNetworkUsageDescription`). Port 1900 may be bound by others (Plex DLNA): use `SO_REUSEADDR` + `SO_REUSEPORT`. BSD sockets with `IP_ADD_MEMBERSHIP` + DispatchSource, or `NWConnectionGroup(NWMulticastGroup)`; multi-interface behavior of the latter unverified.
- Gotchas: re-detect the IP after wake/network change (Cobalt adds `CONFIGID.UPNP.ORG`); serve `/dd.xml` and `GET /apps/` → 302 like Cobalt; keep the PS4/Cobalt UA (D21); leanback config has `isPublicDialDevice` and an IP check that can switch DIAL off.
- **Unverified:** which phone app versions still use DIAL (gotubecast PR #1, June 2026, documents iOS POSTing a UUID `pairingCode`); Android reports; whether an offscreen WKWebView answers `callAsyncJavaScript` quickly.

## Casting checklist

- **AirPlay Receiver status (verified on macOS 27, 2026-10-06):** ControlCenter listens on TCP 7000/5000 when the receiver is on; `GET http://127.0.0.1:7000/info` answers with header `Server: AirTunes/…` (403 body with the "Current user" access setting). Loopback needs no Local Network permission. The `com.apple.controlcenter` key `AirplayRecieverEnabled` is **absent** when never toggled (default on), so don't rely on it.
- **Open the setting:** `x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension` (extension id verified in `/System/Library/ExtensionKit/Extensions/AirDropHandoffExtension.appex`). The user should set "Allow AirPlay for" to "Anyone on the same network" (or Current User with the same Apple Account).
- **Plex HTPC** (`tv.plex.htpc` 1.71.1, installed): the "advertise as player" setting's exact name/location is **unverified**; check in the app.
- **YouTube:** Link with TV code is in leanback Settings; with DIAL it isn't needed.

## Phone remote icon

- iOS: `<link rel="apple-touch-icon" href="…">` with a **180 × 180 PNG** (iOS scales down) and `<meta name="apple-mobile-web-app-title" content="MMTVL">` ([Apple: Configuring Web Applications](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html)). Works over http.
- Android Chrome on an http origin: a home-screen shortcut is created; whether it uses a manifest icon there is **unverified** (manifests need a secure context for install). Add `<link rel="icon" sizes="192x192">` too.
- The PNG can be rendered at runtime with `ImageRenderer` (no binary in the repo) and served through `RemoteWebAssets`' allow-list.

## Phone trackpad

- Post mouse events with the existing tagged `SyntheticInput` source: `CGEvent(mouseEventSource:mouseType:.mouseMoved, mouseCursorPosition:, mouseButton: .left)`, clicks as down/up at the current position (`CGEvent(source: nil)?.location`, top-left origin), scrolling with `CGEvent(scrollWheelEvent2Source:units: .pixel, wheelCount: 2, …)`. Clamp to the union of `CGDisplayBounds` of active displays. Same Accessibility grant as keys (D4/D24).
- Phone side: send summed deltas once per animation frame; tap = click, two-finger drag = scroll.
