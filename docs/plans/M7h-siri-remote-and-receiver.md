# M7h — Own Siri Remote driver, receiver & TV control, power button

| | |
|---|---|
| Status | Planned |
| Depends on | [M7e](archive/M7e-siri-remote-spike.md) (its probe results and the user's "build it" decision), M7g (the Settings layout these pages use), M7f (Q22; this plan takes over its step 5 Plex fix) |
| Master plan decisions used | D2 (focus), D3 (`RemoteCommand`), D4 (Accessibility), D16 (`key-bindings.json`), D20 (PIN), D24 (phone remote, synthetic input), D25 (volume routes; amended by D44), D27 (commands), D35 (foregrounding), D36 (kiosk lock), D42 (Settings layout); new D43, D44, D45 |
| Planned | 2026-11-06 |

## Goal

The Siri Remote works without Remote Buddy, everywhere: TV is Home from any app, the clickpad clicks and **swipes** move focus like on an Apple TV, and in Plex, the browser and Prime Video the remote drives the app through MMTVL's synthetic keys. A **double-press of Siri** switches the remote to **trackpad mode** and back (a 2-second "Trackpad On/Off" toast, like Remote Buddy): the touch surface moves the pointer, a centre click clicks, a **long press of the centre right-clicks**, Back stays Back, and sliding along the right edge scrolls. **Volume and Mute** reach the AV receiver over **RS-232** (Pioneer first; Onkyo/Integra, Denon/Marantz, Yamaha, Anthem and NAD too), the **network** (the same commands over TCP, for receivers with a LAN port; untested here) or **HDMI-CEC**, chosen in Settings, which can **test the connection with read-only queries** and **find the receiver** by trying each brand. The **Power** button turns the TV and receiver off or on like an Apple TV; a **long press** opens a power menu (Turn Off TV, Sleep Mac mini, Relaunch MMTVL, Restart Mac mini; the restart items ask for the PIN). After any HDMI hot-plug (the TV turned off and on, by the Power button or not), **Plex HTPC is restarted on its next open**, so it never shows a black screen (Q22). Typing "a" in a browser no longer jumps to Home.

## Out of scope

- Restarting `coreaudiod` after a hot-plug (needs root; the HDMI audio dropout of 2026-11-05 is tracked in memory and fixed by `sudo killall coreaudiod` or, long term, hardware). This plan only **logs** the default output device after MMTVL powers the TV on.
- The Pulse-Eight USB-CEC adapter (not chosen, 2026-11-06).
- Siri voice input. The Siri button is reserved for the trackpad toggle.
- Waking the Mac from sleep with the remote (macOS doesn't allow it since 11.3.1, per Remote Buddy's docs).
- Remote Buddy's uninstall itself (the user does it; *Manual verification* lists it).

## Research & findings

### The remote (from [M7e's probe](archive/M7e-siri-remote-spike.md), 2026-11-06)

- Siri Remote, Apple vendor 0x4C (76), product 0x315 (789), Bluetooth LE. `RemoteBattery.productIDs` (`MMTVL/Input/RemoteBattery.swift:11`) already lists the Siri Remote product ids `[614, 621, 788, 789]`.
- Its 7 HID interfaces (`ioreg`, on the mini): Consumer (0x0C) 0x01, 0x04, 0x109; Digitizer (0x0D) 0x01; Sensor (0x20) 0xE0, 0x42; vendor 0xFF00 0x0B. **None has `RequiresTCCAuthorization`**, so no Input Monitoring prompt: IOHIDFamily only adds that property to Keyboard (1/6), Mouse (1/2) and TouchPad (0x0D/5) interfaces ([IOHIDDevice.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDDevice.cpp) ~527–531; [IOHIDDeviceClass.m](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDLib/IOHIDDeviceClass.m) ~511–535).
- `IOHIDManager` matched by vendor/product, opened with `kIOHIDOptionsTypeNone`, from a background process: every button arrives, value 1 on press and 0 on release:

  | Button | Usage page / usage |
  |---|---|
  | TV | Consumer 0x60 |
  | Back | Generic Desktop 0x86 |
  | Play/Pause | Consumer 0xCD |
  | Volume Up / Down | Consumer 0xE9 / 0xEA |
  | Mute | Consumer 0xE2 |
  | Power | Consumer 0x30 |
  | Clickpad up / down / left / right | Consumer 0x42 / 0x43 / 0x44 / 0x45 |
  | Clickpad centre | Consumer 0x80 |
  | Siri | Consumer 0x04 (1 while held) |

- **Seizing** (`kIOHIDOptionsTypeSeizeDevice`) needs only the console user unless the interface is a Keyboard/Keypad ([IOHIDLibUserClient.cpp](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDLibUserClient.cpp) 709–714). While seized, input reports don't reach the system event driver (IOHIDDevice.cpp ~1218–1239), so macOS's own volume HUD and media-key handling stop. **Reported gaps** (third-party, [SiriRemoteForge HANDOFF](https://github.com/HOLODATA-COM/SiriRemoteForge/blob/main/HANDOFF.md)): Power (0x0C/0x30) still reaches `loginwindow` and may sleep or lock the Mac (their fix: `PowerButtonSleepsSystem = false` in `com.apple.loginwindow`); Bluetooth AVRCP play/pause bypasses the seize and goes to `com.apple.rcd`, which may open Music. **Unverified on the mini**: step 1 checks both.
- Bluetooth LE remotes disconnect when idle: the `IOHIDDevice`s go away and come back, a press can end without a release. Use device matching and removal callbacks, synthesize releases on removal (SiriRemoteForge `RemoteDetector.swift:118–119`).
- **Touch** gives no HID values. Apple's private **MultitouchSupport** (`/System/Library/PrivateFrameworks/MultitouchSupport.framework`, `dlopen`): `MTDeviceCreateList()` listed one device on the mini, family 0x91 (6 × 12, not built in); `MTRegisterContactFrameCallback` + `MTDeviceStart(dev, 0)` delivered one-finger frames. Callback `int cb(MTDeviceRef, MTTouch *, int count, double timestamp, int frame)`; `MTTouch` is 96 bytes: `state` Int32 at 20 (4 = touching), normalized position x, y Float at 32, 36, velocity x, y at 40, 44 ([OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport/blob/main/Framework/OpenMultitouchSupportXCF/OpenMTInternal.h)). Measured: slides across ≈ 0.20 → 0.75 in x, 0.74 → 0.29 in y (y grows upward). Devices come and go: watch `IOServiceAddMatchingNotification(IOServiceMatching("AppleMultitouchDevice"))` (matched and terminated) and rebuild the list; restart after wake ([Karabiner-Elements MultitouchDeviceManager.swift](https://github.com/pqrs-org/Karabiner-Elements/blob/main/src/apps/MultitouchExtension/src/MultitouchDeviceManager.swift)). Pick devices with `MTDeviceIsBuiltIn == false` (a MacBook's own trackpad must never be used). No TCC is known for it (**unverified**; step 1 runs it from the app).
- **GameController**: Apple documents `GCMicroGamepad` for the Siri Remote on macOS, but reports say macOS doesn't expose it ([forum 75911](https://developer.apple.com/forums/thread/75911)). **Unverified**: step 1 logs `GCController.controllers()` with Remote Buddy gone. If it does appear, `ControllerInput` must ignore it (double input).
- **Today's TV-button Home** was Remote Buddy typing "a": the mini's `key-bindings.json` has a global Home on `{"key":{"keyCode":0,"modifiers":[]}}` labeled "A" (M7e *Probe results*). Every "a" typed in Safari/Brave went Home. Remote Buddy's trial has expired.
- Plex HTPC's HIDRemote only matches the IR receiver (`AppleIRController`) ([HIDRemote](https://github.com/iospirit/HIDRemote)), so it can't take the Siri Remote: **Q21 is moot**.

### Existing code this plugs into (verified 2026-11-06)

- `RemoteCommand` (`MMTVL/Input/RemoteCommand.swift:3-6`): `up, down, left, right, select, back, home, playPause, fastForward, rewind, menu, channelUp, channelDown`; `allCases` order is the order of Settings → Remote Buttons; `title` at :9.
- `InputBinding.Trigger` (`MMTVL/Input/InputBinding.swift:39-43`): `.key(keyCode:modifiers:)`, `.media(key:)`, `.controller(button:)`; synthesized Codable, e.g. `{"controller":{"button":"a"}}`; `matches` :70, `normalized` :78. `ControllerButton` :31-35.
- `KeyBindings` (`MMTVL/Input/KeyBindings.swift:16-51` defaults; `currentRevision = 2` :54; `addingDefaults(for:)` :57-65; lookups `binding(keyCode:modifiers:)` :69, `binding(media:)` :76, `binding(controller:)` :80). Migration: `App/AppDelegate.swift:250-257` `migrateBindings` (revision < current → `addingDefaults(for: [.menu, .channelUp, .channelDown])`, saves both files). `AppSettings.keyBindingsRevision` (`App/AppSettings.swift:20`, decoded as 1 when missing at :58).
- `KeyBindings+Editing.swift`: `essentialCommands` :4 (up, down, left, right, select, back), `adding` :18-23 (sets `isGlobal = (command == .home)`), `removing` :26, `settingGlobal` :31, `canRemove` :41-46.
- `TriggerName.swift`: `describe` :7, `kind` :22, `keyName` :31 (Settings → Remote Buttons names).
- `InputRouter` (`MMTVL/Input/InputRouter.swift`): `capture(_:)` :66-70 (only while `captureHandler` set and MMTVL active), `dispatch(_:isGlobal:isRepeat:)` :75-85 (MMTVL active → handler; else `isGlobal` → `onGlobalCommand`; else false).
- Global Home: `AppDelegate.handleGlobal` (`App/AppDelegate.swift:602-612`) acts on `.home` only (ends mirroring, kiosk guard, launcher, `router.goHomeToStartTile()`, `windowController.show(reason: "home")`).
- `ControllerInput.swift`: repeat 450 ms then every 120 ms, directions only (:9-11, :147, task :174-187); `buttonChanged` :137-150 (capture → lookup → dispatch). Reuse these timings.
- Phone routing for other apps: `RemoteServer/PhoneRemote.swift:235-246` `route` (MMTVL in front → `dispatch(cmd, false)`; Home → `dispatch(.home, true)`; else `ExternalKeyMap.key(for:)` → `postExternal` when `canPostEvents`). `ExternalKeyMap` (`Input/ExternalKeyMap.swift:13-28`): arrows, Return, Escape, media play/next/previous, Page Up/Down; `home`/`menu` → nil. `postExternal` wired at `App/AppDelegate.swift:280-285`.
- Pointer: `PointerMath.accelerated` / `clamp` / `scrollWheels`, `ClickCounter` (`Input/PhonePointer.swift:16-66`); `SyntheticInput.pointerLocation` :97, `activeDisplayBounds()` :102, `movePointer(to:delta:)` :110, `click(_:at:clickCount:)` :120 (left/right), `scroll(wheel1:wheel2:)` :134, all tagged with `SyntheticInput.marker`.
- Volume (D25): `App/Volume.swift`: `VolumeMode` `auto|keys|system|app` :7 (from `settings.phoneRemoteVolume`), `VolumeRoute.choose` :14-27, `VolumeController.perform(_ VolumeAction) -> VolumeFeedback` :168-205 (created `AppDelegate.swift:266-272`, used only by the phone at :305). `VolumeAction` (`RemoteServer/RemoteMessage.swift:3`): `up, down, mute`.
- Settings (M7g): pages are `SettingsPage` cases (`Settings/SettingsTypes.swift:3-19`), sections from `sections(for:)` (`Settings/SettingsModel+Pages.swift:12-46`); Remote & Input rows at :142-173 (`globalInput`, `controllers`, `remoteButtons`, `channelUp`, `cursorAutoHide`, `phoneRemote`). Rows: `SettingsRow` (`SettingsTypes.swift:248-267`: `title, value, detail, showsDisclosure, action, description`); toggles are `SettingKey` cases with key paths (:138-170); choice lists are push pages whose rows carry a select action (pattern: `.setStartTile(id:)` at `SettingsModel+Pages.swift:343`, `.choosePlexServer(id:)` at :832). `perform` `SettingsModel.swift:262`; `.relaunch` :284-285 → `AppRelauncher.relaunch` (`App/AppRelauncher.swift:26-43`).
- `AppSettings` (`App/AppSettings.swift`): add a property with a default and a `decodeIfPresent ?? defaults.x` line in `init(from:)` (:47-72).
- Display sleep: `AppDelegate.observeScreensSleep` :680-697 → `router.screensDidSleep()` (`Launcher/AppRouter.swift:305-310`, stops the Live TV preview); wake `observeWake` :616-624, `systemDidWake` :647-661. **No helper puts the displays to sleep.** Screen changes: `KioskWindowController.swift:60-79` (refit only); no hot-plug detection exists.
- `AppLauncher` (`Launcher/AppLauncher.swift`): `launchedPIDs` :122, `launch(_:)` :217-283 (`wasRunning` :235), open log :299, `applicationDidTerminate` :395-425 (goes Home when a launched PID quits). **No code terminates or restarts other apps.** Plex's bundle id `tv.plex.htpc` (`Launcher/LaunchItem.swift:76`, `Launcher/TopShelf.swift:123`).
- Screens: `AppRouter.Screen` (`Launcher/AppRouter.swift:15-21`: `home, accessibilityOnboarding, settings, youtube, liveTV, pin(PINPurpose)`); `handle(_:isRepeat:)` :492-512 → `route` :513+; `LauncherRootView` :850 (YouTube and Live TV render outside the scaled canvas :856-861). **No global overlay layer and no on-TV toast exist.** A pure menu model to copy: `LiveMenu` (`IPTV/LiveMenu.swift:21`), view `IPTV/LiveMenuView.swift:5`. `PINPurpose` (`PIN/PINFlow.swift:4-10`): `openSettings, openTile(id:), exitToDesktop, quit, setNew, change, turnOff`.
- Tests to extend: `KeyBindingsTests`, `KeyBindingsEditingTests` (+ `InputRouterCaptureTests` :63), `TriggerNameTests`, `PointerMathTests`, `RemoteBatteryTests`, `VolumeTests`, `AppSettingsTests`, `SettingsRemoteButtonsTests`, `SettingsModelTests`, `AppLauncherTests`, `AppRouterTests`, `PINFlowTests`, `PhoneRemoteTests`. No tests exist for `ControllerInput` or `GlobalEventTap`.

### Receiver over RS-232 (verified on the mini, 2026-11-06)

- The mini has an **FTDI FT232R** USB-serial adapter wired to the receiver: `/dev/cu.usbserial-A9JL9ZSL` (Apple's built-in `AppleUSBFTDI` DriverKit driver; Prolific, CH340 and CP210x have built-in drivers too).
- Pioneer VSX-01TXH answered read-only queries at **9600 8N1, raw, CR-terminated**, after a bare CR to wake it (reply `R`): `?P` → `PWR0` (on), `?V` → `VOL61` (**2-digit volume**, 00–93, 81 = 0 dB, so 61 = −20 dB), `?M` → `MUT1` (not muted). Replies end with CR LF.
- Pioneer's protocol (the VSX-94TXH "RS232C Protocol", June 2007, same family; the 01TX PDF wasn't downloadable): DB9 male on the receiver, **null-modem** cable, 9600 8N1; in standby the main CPU is off and the first command only wakes it, so **send power-on twice, ≥ 100 ms apart**; allow 100 ms per command. Power `PO` / `PF` / `?P` → `PWR0` on, `PWR1` off. Volume `VU` / `VD` / `NNVL` / `?V` → `VOLNN`. Mute `MO` / `MF` / `?M` → `MUT0` muted, `MUT1` not. Front-panel changes are reported unsolicited (`VOLNN`, `PWRN`, `MUTN`, `FNNN`). No `MZ` toggle in that document. Newer Pioneers use 3-digit `NNNVL` (000–185): parse both.
- POSIX serial in Swift without dependencies: `open("/dev/cu…", O_RDWR | O_NOCTTY | O_NONBLOCK)`, `tcgetattr`, `cfmakeraw`, `cfsetspeed(B9600)`, `c_cflag |= CS8 | CLOCAL | CREAD`, clear `PARENB | CSTOPB | CRTSCTS`, `tcsetattr(TCSANOW)`, read with a `DispatchSourceRead`. Use `cu.*`, not `tty.*` (blocks on carrier). List ports with IOKit `IOServiceMatching(kIOSerialBSDServiceValue)`. The app isn't sandboxed, so no entitlement.
- **Other vendors**: see *Receiver protocols* below (from vendor documents; **unverified on hardware**: only Pioneer is in the house).

### Receiver protocols

Only Pioneer (legacy) is verified on hardware (the VSX-01TXH, 2026-11-06). The rest come from vendor documents where noted, else **unverified** (third-party libraries). Each brand's `probeQueries` (L12) are its query commands only. Lines that don't parse are ignored (some models send extra lines, e.g. Denon's `MVMAX nn`).

| Brand (`receiverBrand`) | Serial | Cable | Terminator / framing | Power on / off / query → reply | Volume up / down / query → reply | Mute on / off / query → reply | Timing | Network port | Source |
|---|---|---|---|---|---|---|---|---|---|
| Pioneer, before 2016 (`pioneer`) | 9600 8N1 | null-modem (receiver DB9 male) | CR; replies end CR LF | `PO` (send twice, 100 ms apart, from standby) / `PF` / `?P` → `PWR0` on, `PWR1` off | `VU` / `VD` / `?V` → `VOLnn` (00–93, 81 = 0 dB; newer 3-digit `VOLnnn` 000–185, 161 = 0 dB, half-dB steps) | `MO` / `MF` / `?M` → `MUT0` muted, `MUT1` not | 100 ms per command | 23, fallback 8102 (**unverified**) | Verified on hardware; Pioneer VSX-94TXH RS232C Protocol (2007) |
| Onkyo / Integra / Pioneer 2016+ (`onkyo`, ISCP) | 9600 8N1, no flow control | straight | send `!1` + command + CR; replies `!1…` ending in EOF 0x1A (some add CR/LF): split on 0x1A, CR or LF | `!1PWR01` / `!1PWR00` / `!1PWRQSTN` → `!1PWR01` on, `!1PWR00` standby | `!1MVLUP` / `!1MVLDOWN` / `!1MVLQSTN` → `!1MVLhh` (hex, 00–64 most models) | `!1AMT01` / `!1AMT00` / `!1AMTQSTN` → `!1AMT01` muted, `!1AMT00` not | > 50 ms between messages | 60128 (eISCP: 16-byte header `ISCP`, header size 0x00000010, data size, both big-endian, version 0x01, 3 reserved bytes; one client at a time) | [Onkyo ISCP v1.15 (2009)](https://community.symcon.de/uploads/short-url/7mxbIQ7qRIghfbEQrvcrEkU57ad.pdf); Pioneer 2016+ using ISCP **unverified** |
| Denon / Marantz 2010+ (`denon`) | 9600 8N1, no handshake | straight (receiver DB9 female, DCE) | CR | `PWON` / `PWSTANDBY` / `PW?` → `PWON` / `PWSTANDBY` | `MVUP` / `MVDOWN` / `MV?` → `MVnn` or `MVnnn` (80 = 0 dB; 3 digits = half dB, `MV805` = +0.5 dB; 00 = −∞) | `MUON` / `MUOFF` / `MU?` → `MUON` / `MUOFF` | wait 1 s after `PWON`; replies within 200 ms; 50 ms gap (**unverified**) | 23 (telnet, same commands) | [Denon AVR-X2000 protocol v10.1](https://assets.denon.com/documentmaster/uk/avrx2000_e400_protocol(1010)_v03.pdf), [AVR-1713 v8.6](https://assets.denon.com/documentmaster/uk/avr1713_avr1613_protocol_v860.pdf) |
| Yamaha 2010–2020 (`yamaha`, YNCA) | 9600 8N1 (**unverified**) | **unverified** | CR LF; `@SUBUNIT:FUNC=VALUE`, query `=?` | `@MAIN:PWR=On` / `@MAIN:PWR=Standby` / `@MAIN:PWR=?` → `@MAIN:PWR=On` / `=Standby` | `@MAIN:VOL=Up` / `@MAIN:VOL=Down` / `@MAIN:VOL=?` → `@MAIN:VOL=-35.5` (dB) | `@MAIN:MUTE=On` / `=Off` / `=?` → `@MAIN:MUTE=On` / `=Off` | 100 ms gap (**unverified**); `@UNDEFINED` / `@RESTRICTED` are errors | 50000 (one client at a time) | [ynca PROTOCOL.md](https://github.com/mvdwetering/ynca/blob/master/docs/PROTOCOL.md) (**unverified**, the spec is dealer-only) |
| Anthem MRX/AVM (`anthem`) | 115200 8N1 (**unverified**) | **unverified** | `;` | `Z1POW1;` / `Z1POW0;` / `Z1POW?;` → `Z1POW1` / `Z1POW0` | `Z1VUP;` / `Z1VDN;` / `Z1VOL?;` → `Z1VOL-35` (dB) | `Z1MUT1;` / `Z1MUT0;` / `Z1MUT?;` → `Z1MUT1` / `Z1MUT0` | errors `!R…` | 14999 | [RTI driver page](https://driverstore.rticontrol.com/driver/anthem-mrx-x10-series) (**unverified**) |
| NAD, protocol v2 (`nad`) | 115200 8N1, no flow control (**unverified**) | **unverified** | CR (send a leading CR); replies CR LF | `Main.Power=On` / `=Off` / `Main.Power?` → `Main.Power=On` / `=Off` | `Main.Volume+` / `Main.Volume-` / `Main.Volume?` → `Main.Volume=-30` (dB) | `Main.Mute=On` / `=Off` / `Main.Mute?` | — | 23 (**unverified**) | [nad-serial](https://pypi.org/project/nad-serial/) (**unverified**) |

Not supported (different, binary or handshake protocols): Marantz before about 2009 (`@1A1`, RTS/CTS, ACK/NAK; [SR6400 spec](https://marantz.com/on/demandware.static/-/Library-Sites-marantz_apac_shared/default/dw40620a18/archive-downloads/sr6400_sr5400_rs-232c_specification_v100b.pdf)), Yamaha's legacy "RS-232C Standard" and YRSC (RX-V3900 era), Sony ES (binary with checksums). Settings' brand list says which years each entry covers.

### HDMI-CEC from the Mac (verified on this Mac and the mini, 2026-11-06; sending **unverified**)

- No public API. `IOCECFamily.kext` is loaded; the registry has `DCPAVCECInterfaceProxy` → `IOAVCECService` (`IOUserClientClass = IOCECUserClient`). On the mini, **`/usr/libexec/corercd` (pid 205) already holds an `IOCECUserClient`** (its entitlements name `IOCECUserClient`).
- `/System/Library/PrivateFrameworks/IOCEC.framework` exports a C API (`IOCECInterfaceCreate`, `IOCECInterfaceCreateWithService`, `IOCECInterfaceSetLogicalAddressMask`, `IOCECInterfaceSendFrame`, `IOCECInterfaceRegisterReceiveCallback`, `IOCECInterfaceScheduleWithDispatchQueue`); no headers. On Apple TV 3, `IOCECInterfaceCreate` returns NULL for other processes while `cecd` holds the interface ([appletv3-cec](https://github.com/huguesdelamure/appletv3-cec)). **Unverified on macOS**: step 1's probe answers whether MMTVL can open a second client.
- Apple: the M4 Mac mini's HDMI supports CEC and "sleeps and wakes the display with the Mac" ([support 108928](https://support.apple.com/en-us/108928)). **Unverified**: whether **display** sleep (not system sleep) makes macOS send CEC standby. Step 1 tries `pmset displaysleepnow`.
- BetterDisplay 5 sends CEC on Apple silicon ("DisplayPort AUX DPCD CEC tunneling"; [wiki](https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI), [issue 3394](https://github.com/waydabber/BetterDisplay/issues/3394)), so it is possible from user space; how is undocumented. BetterDisplay was uninstalled from the mini on 2026-11-05 (it broke HDCP with a virtual screen; not needed for this).
- CEC frames (libcec `cectypes.h`): header `(initiator << 4) | destination`; Mac as playback device 4, TV 0, audio system 5, broadcast F. TV standby `40:36`; TV on `40:04` (Image View On) then Active Source `4F:82:PP:PP` (the Mac's physical address; 0x2300 in the mini's kernel log 2026-11-05: `physicalAddress = 0x2300`); power status `0x8F` → `0x90`; volume up/down/mute to the audio system: User Control Pressed `45:44:41` / `45:44:42` / `45:44:43`, then Released `45:45`.
- **Receiver caveat**: the VSX-01TXH manual calls its CEC "HDMI Control" (Pioneer KURO Link) and says it may not work with non-Pioneer components ([manual p. 67](https://www.manualslib.com/manual/130505/Pioneer-Elite-Vsx-01txh.html?page=67)). The user's TV turning off also turns the receiver off (2026-11-05), so some CEC link works.

### System calls (unverified ones are checked in step 1 or the TV steps)

- Display sleep now: `/usr/bin/pmset displaysleepnow` (no root). Wake displays: `IOPMAssertionDeclareUserActivity(..., kIOPMUserActiveLocal, ...)` (public IOKit).
- Sleep the Mac: `/usr/bin/pmset sleepnow` (**unverified without root** on macOS 26; fallback the `kAESleep` Apple event to `loginwindow`).
- Restart: Apple's documented way is sending `kAERestart` (`'rrst'`) to `loginwindow` (Technical Q&A QA1134). **Unverified** whether macOS 26 shows an Automation prompt for it.
- Hot-plug: `CGDisplayRegisterReconfigurationCallback` reports `kCGDisplayRemoveFlag` / `kCGDisplayAddFlag` per display (public CoreGraphics). On 2026-11-05 a TV power cycle removed and re-added the HDMI display about four times in 25 s, and Plex HTPC logged `[DisplayManager] Found 1 Display(s)` for each new display id before every black screen (M7f §1).

## Design

### New master plan decisions

- **D43 — Own Siri Remote driver** (replaces Remote Buddy, M7e): MMTVL reads the Siri Remote with `IOHIDManager` (Apple vendor, `RemoteBattery.productIDs`), **seized** so macOS doesn't act on its buttons too, and its touch surface with the private **MultitouchSupport** framework (`dlopen`; without it, buttons still work and swipes/trackpad mode are off). Buttons are a new trigger kind `{"siriRemote":{"button":"…"}}` in `key-bindings.json`. Normal mode: clickpad and swipes move focus, other apps get keys through `SyntheticInput` (D24's path). **Siri double-press toggles trackpad mode** (touch moves the pointer, centre click = click, long press = right click, Back = Back, right-edge slide = scroll); a 2-second toast says "Trackpad On/Off". Siri is reserved (not bindable). Rationale: Remote Buddy's trial expired; its TV-button Home typed "a" (2026-11-06).
- **D44 — Receiver & TV control** (amends D25): an `AVControl/` layer with per-vendor receiver protocols (Pioneer, Onkyo/Integra/Pioneer 2016+, Denon/Marantz, Yamaha, Anthem, NAD), over **RS-232** (POSIX serial), the **network** (the same commands over TCP with Network.framework; Onkyo's eISCP adds its header) or **HDMI-CEC** (the Mac's own, private `IOCEC.framework`), chosen in Settings → Remote & Input → Receiver & TV, which tests the link with **read-only queries** and can find the receiver (brand on a serial port; receivers on the LAN by SSDP). Volume buttons (Siri Remote and phone) go **receiver first** when one is set up and answering, then D25's order. TV power is CEC (or display sleep only). Rationale: HDMI has no macOS volume (D25); the user's Pioneer has RS-232 wired (2026-11-06).
- **D45 — Power button and HDMI hot-plugs** (resolves Q22, takes over M7f step 5): Power short press turns the TV and receiver off (displays sleep) or on; long press opens a **power menu** over any app (Turn Off TV, Sleep Mac mini, Relaunch MMTVL and Restart Mac mini, the last two behind the PIN, D20). After any HDMI hot-plug while Plex HTPC is in the background, MMTVL **restarts Plex on its next open**. Rationale: every black Plex screen followed a hot-plug (M7f §1); a virtual display that avoids it broke HDCP for Prime Video (2026-11-05).

### Local decisions

- **L1 — Seize, with a fallback.** Each remote interface is opened with `kIOHIDOptionsTypeSeizeDevice`; if that fails, with `kIOHIDOptionsTypeNone`, logged. Seizing stops macOS's own volume HUD and media handling (no double actions).
- **L2 — Trigger and commands.** `InputBinding.Trigger.siriRemote(button: SiriRemoteButton)`; `SiriRemoteButton`: `tv, back, playPause, volumeUp, volumeDown, mute, power, up, down, left, right, select` (no `siri`: reserved). New `RemoteCommand`s appended at the end (`allCases` order): `volumeUp, volumeDown, mute, power, powerMenu`. Defaults (revision 3): tv → home, back → back, clickpad → up/down/left/right/select, playPause → playPause, volume/mute → volumeUp/volumeDown/mute, power → power. Long press of power (≥ 0.8 s) sends `powerMenu` instead (not a separate trigger). Siri Remote bindings are always global (the remote is the TV's remote).
- **L3 — Routing.** A Siri Remote command goes (in order): learning capture → its binding → `volumeUp/Down/mute` to `VolumeController` and `power/powerMenu` to `PowerController` (from any app) → MMTVL in front: `dispatch(cmd, isGlobal: false)` → Home: `dispatch(.home, isGlobal: true)` → else `ExternalKeyMap.key(for:)` posted with `SyntheticInput` (the phone's `route`, `PhoneRemote.swift:235-246`, factored into one shared `ExternalRouter`).
- **L4 — Holds and long presses.** Held clickpad directions repeat (450 ms, then every 120 ms; `ControllerInput`'s values). Normal mode: a long press of centre (≥ 0.6 s) sends `menu` (Apple TV-like context menu: the channel menu in Live TV); a short one `select`. Trackpad mode: short = left click, long (≥ 0.6 s, fires once while held) = right click. Thresholds live in one `SiriRemoteTiming` enum.
- **L5 — Siri double-press.** Two presses within 0.4 s toggle trackpad mode; a single press does nothing. Home (TV) also leaves trackpad mode.
- **L6 — Swipes like Apple TV.** One finger, dominant axis: each 0.22 of travel (normalized) since the last step emits one direction command; on lift, a flick faster than 2.0 units/s adds up to 2 more steps. No swipe steps while a clickpad button is down or for 150 ms after one is released (clicking moves the finger a little). Taps do nothing. All values in `SwipeRecognizer` constants for TV tuning.
- **L7 — Trackpad motion.** Pointer delta = finger delta × 1200 points (x) and × −1200 (y, up is up), then `PointerMath.accelerated` and `clamp`. Scroll: a touch that starts with x ≥ 0.85 scrolls vertically for the whole touch (`dy` × 600 → `PointerMath.scrollWheels`); one that starts with y ≤ 0.12 scrolls horizontally. Clicks use `ClickCounter` (double-clicks). While trackpad mode is on, `cursorAutoHide` doesn't hide the pointer.
- **L8 — Toast.** One non-activating borderless `NSPanel` (`.statusBar` level, `ignoresMouseEvents`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`) shows a glass capsule for 2 s over any app: "Trackpad On", "Trackpad Off", volume ("Volume −20 dB", "Muted"), and receiver errors ("Receiver isn't answering"). The receiver volume toast replaces the HUD macOS no longer shows (L1).
- **L9 — Plain letters can't be global.** Bindings revision 3 removes global bindings whose trigger is a key without modifiers in the letters/digits set (`kVK_ANSI_A…Z`, `0…9`); `adding`/`settingGlobal` keep such a key non-global, and Settings says why ("Letter and number keys only work in MMTVL").
- **L10 — GameController.** If step 1 shows the Siri Remote as a `GCController`, `ControllerInput` skips controllers whose `productCategory` is the Siri Remote while the HID reader runs.
- **L11 — Receiver protocol layer.** A pure `ReceiverProtocol` per vendor turns `ReceiverCommand` (`powerOn, powerOff, queryPower, volumeUp, volumeDown, queryVolume, mute(Bool), queryMute`) into bytes and parses reply lines into `ReceiverStatus` events (`power(Bool)`, `volume(raw: Int, dB: Double?)`, `muted(Bool)`). Each protocol carries its serial settings, terminator, wake rule and minimum gap. `ReceiverController` owns one transport, a command queue that honors the gap, the power-on double send (Pioneer), and the last known status (also from unsolicited lines).
- **L12 — Test and find with read-only queries** (user request, 2026-11-06). Settings → Receiver & TV → **Test Connection** sends the chosen brand's `queryPower`, `queryVolume`, `queryMute` on the chosen port and shows each reply ("On · −20 dB · Not muted", or "No answer"). **Find Receiver** tries each brand's queries at that brand's serial settings on the chosen port (2 s per brand) and selects the first that answers. Neither ever sends a command that changes anything. The query sets are `ReceiverProtocol.probeQueries`.
- **L17 — Network transport** (user request, 2026-11-06; **untested**: no networked receiver in the house). `ReceiverTCPTransport` (`NWConnection`, TCP, to `receiverHost` on the brand's control port, overridable with `receiverNetworkPort`) carries the same `ReceiverProtocol` bytes; Onkyo/Integra wrap each command in the eISCP header (`ReceiverProtocol.networkFraming`). Reconnect with backoff (1, 2, 5, 10 s), keep-alive on, close after 5 minutes without commands (some receivers allow one client only). **Find on Network**: an SSDP M-SEARCH (`ssdp:all`, 3 s) for UPnP devices whose `manufacturer` is one of the supported brands; each found host is checked with that brand's read-only `probeQueries` on its control port, and the first that answers is selected. The host is entered with MMTVL's on-screen keyboard (D41) or chosen from Find's list. Outgoing LAN connections need the Local Network permission MMTVL already declares (`NSLocalNetworkUsageDescription`). Logs show host and port only.
- **L13 — CEC transport** (gated by step 1): `CECBus` wraps `IOCEC.framework` with `dlopen`. If MMTVL can't open it while `corercd` holds it, the CEC options in Settings show "Not available on this Mac" and TV power falls back to display sleep only.
- **L14 — Power short press.** Off: receiver `powerOff` (if set up), TV standby (CEC, if available), then `pmset displaysleepnow`. On (when MMTVL turned things off, or the receiver reports off): wake the displays, receiver `powerOn`, TV on (CEC `40:04`, then Active Source). A `poweredOffByMMTVL` flag (memory only) plus the receiver's status decide which. After power-on, log the default output device (`Power` category).
- **L15 — Power menu.** MMTVL comes forward (`Foregrounder`, reason `powerMenu`) and shows a `PowerMenu` (pure model like `LiveMenu`) over the current screen in `LauncherRootView` (a top-level overlay above every screen). Items: Turn Off TV & Receiver, Sleep Mac mini, Relaunch MMTVL (PIN), Restart Mac mini (PIN), Cancel. Back cancels. New `PINPurpose` cases `relaunch` and `restartMac`.
- **L16 — Plex restart after a hot-plug.** `DisplayHotplugMonitor` (CoreGraphics reconfiguration callback) marks every running app in `AppLauncher.restartOnNextOpen` that isn't frontmost at the time of a display remove or add; only bundle ids in `AppLauncher.restartAfterHotplug = ["tv.plex.htpc"]`. The next open of a marked app: remove its pid from `launchedPIDs`, `terminate()`, wait up to 5 s, `forceTerminate()` if needed, then launch as usual. Log `Restarting tv.plex.htpc after a display change` (category `AppLauncher`, notice).

### New and changed files

| File | Responsibility |
|---|---|
| `MMTVL/Input/SiriRemote/SiriRemoteButton.swift` (new) | `SiriRemoteButton` enum and the pure `(page, usage) → SiriRemoteButton?` / `isSiri` mapping. `nonisolated`. |
| `MMTVL/Input/SiriRemote/SiriRemoteHID.swift` (new) | `IOHIDManager` reader: matching/removal callbacks, seize-with-fallback (L1), value callback → `(button or siri, pressed)`, synthesized releases on removal. Main actor, runloop-scheduled. |
| `MMTVL/Input/SiriRemote/SiriRemoteGestures.swift` (new) | Pure state machine (clock injected): press/release → `.command(RemoteCommand, isRepeat)`, `.toggleTrackpad`, `.click(left|right)`; long presses (L4), repeats, Siri double-press (L5). `nonisolated struct`. |
| `MMTVL/Input/SiriRemote/MultitouchDevices.swift` (new) | `dlopen` of MultitouchSupport, device list (not built in), `AppleMultitouchDevice` matching notifications, restart after wake, frame callback → `TouchFrame` (count, x, y, state, timestamp) on the main actor. |
| `MMTVL/Input/SiriRemote/SwipeRecognizer.swift` (new) | Pure: `TouchFrame`s → direction steps (L6). |
| `MMTVL/Input/SiriRemote/TrackpadMapper.swift` (new) | Pure: `TouchFrame`s → `PointerAction`s (move / scroll, L7). |
| `MMTVL/Input/SiriRemote/SiriRemoteInput.swift` (new) | Owns the reader, gestures, touch, mode (normal/trackpad); routes per L3; posts pointer actions through `PhonePointer`; tells the toast. |
| `MMTVL/Input/ExternalRouter.swift` (new) | L3's shared "command for another app" routing, used by `PhoneRemote.route` and `SiriRemoteInput`. |
| `MMTVL/Input/InputBinding.swift`, `KeyBindings.swift`, `KeyBindings+Editing.swift`, `TriggerName.swift`, `RemoteCommand.swift`, `ExternalKeyMap.swift` | L2 trigger/commands/defaults, revision 3 + L9 guard, names ("Siri Remote TV", …). |
| `MMTVL/Input/ControllerInput.swift` | L10 skip (only if step 1 needs it). |
| `MMTVL/DesignSystem/OverlayToast.swift` (new) | L8 panel + SwiftUI capsule (designer). |
| `MMTVL/AVControl/SerialPort.swift` (new) | POSIX serial (open, settings, write, line reader, close), `SerialPort.available()` (IOKit list of `cu.*`). |
| `MMTVL/AVControl/ReceiverProtocol.swift` (new) + `ReceiverProtocols/Pioneer.swift`, `Onkyo.swift`, `Denon.swift`, `Yamaha.swift`, `Anthem.swift`, `NAD.swift` (new) | L11 pure codecs, serial settings, `probeQueries`. |
| `MMTVL/AVControl/ReceiverController.swift` (new) | L11 queue, status, test/find (L12). |
| `MMTVL/AVControl/ReceiverTCPTransport.swift`, `ReceiverDiscovery.swift` (new) | L17 TCP transport and SSDP discovery. |
| `MMTVL/AVControl/CECBus.swift` (new) | L13 (only if step 1's gate passes). |
| `MMTVL/AVControl/PowerController.swift` (new) | L14, display sleep/wake, Mac sleep/restart calls. |
| `MMTVL/Launcher/PowerMenu.swift`, `PowerMenuView.swift` (new) | L15 model and view. |
| `MMTVL/App/DisplayHotplugMonitor.swift` (new) | L16 callback → `AppLauncher`. |
| `MMTVL/App/Volume.swift` | D44: `.receiver` route. |
| `MMTVL/App/AppSettings.swift`, `AppDelegate.swift`, `Launcher/AppRouter.swift`, `Launcher/AppLauncher.swift`, `PIN/PINFlow.swift`, `RemoteServer/PhoneRemote.swift` | Wiring, migration, settings keys, PIN purposes, restart-on-next-open. |
| `MMTVL/Settings/SettingsTypes.swift`, `SettingsModel+Pages.swift`, `SettingsModel.swift`, `SettingsEnvironment.swift` | Remote & Input → Siri Remote and Receiver & TV pages. |
| `scripts/probes/` (new, deleted in step 14) | Step 1's throwaway probes, outside `MMTVL/`. |

### New settings keys (`settings.json`, all optional)

- `siriRemoteEnabled` (Bool, default `true`): read the Siri Remote directly (Settings → Remote & Input → Siri Remote).
- `receiverBrand` (String, default `"none"`): `none | pioneer | onkyo | denon | yamaha | anthem | nad`; unknown values read as `none`.
- `receiverConnection` (String, default `"serial"`): `serial | network | cec`.
- `receiverHost` (String?, default nil): the receiver's IP address or host name (network connection).
- `receiverNetworkPort` (Int?, default nil): overrides the brand's control port (L17).
- `receiverSerialPort` (String?, default nil): a `/dev/cu.*` path; nil = the first USB serial port found.
- `tvPowerControl` (String, default `"cec"`): `cec | displaySleep`; `cec` falls back to display sleep when CEC isn't available.
- `phoneRemoteVolume` gains `receiver` (D44); `auto` now means receiver → SoundSource keys → system → app.

### Settings pages (M7g layout, D42)

- **Remote & Input** gets two rows after Game Controllers: **Siri Remote** (push; value "Connected · 78 %" / "Not Connected" / "Off") and **Receiver & TV** (push; value the brand or "Not Set Up").
- **Siri Remote** page: Use Siri Remote (toggle `siriRemoteEnabled`; description: "Read the Siri Remote directly. Double-press Siri for trackpad mode."), Status (info: connected, battery, touch available or not), a "How it works" footer (TV = Home, swipes, double-press Siri = trackpad, long press centre = menu / right click, long press Power = power menu).
- **Receiver & TV** page: Brand (push → list: None, Pioneer (before 2016), Onkyo / Integra / Pioneer (2016 and later), Denon / Marantz (2010 and later), Yamaha (2010–2020), Anthem, NAD; the footer: "Tested with Pioneer. Serial cables: Pioneer needs a null-modem cable, Denon, Marantz and Onkyo a straight one."), Connection (push → Serial / Network / HDMI-CEC), Serial Port (push → list of `cu.*` ports plus "Automatic"; only with Serial), Address (only with Network: the host, edited with the on-screen keyboard, D41), **Test Connection** (action; detail shows the replies), **Find Receiver** (action; Serial: tries each brand on the port; Network: SSDP, then a push list of the receivers that answered), TV Power (HDMI-CEC / Display Sleep Only), Status (info: "On · −20 dB · Not muted" from the last status).

## Implementation steps

- [ ] **1. Probes on the mini** `[implementer]` then `[human]`: files: `scripts/probes/hid-seize.swift`, `scripts/probes/cec.swift`, `scripts/probes/gc.swift` (new)
  - `hid-seize.swift`: like M7e's probe but opens with `kIOHIDOptionsTypeSeizeDevice` (prints the open result per interface) and logs each value with a timestamp; arg `--seconds N`.
  - `gc.swift`: observes `GCControllerDidConnect`, prints `vendorName`, `productCategory`, profile for 30 s.
  - `cec.swift`: `dlopen` IOCEC.framework; resolve `IOCECInterfaceCreate` (and `…CreateWithService` with `IOServiceGetMatchingService(IOServiceMatching("IOAVCECService"))`); print whether it returns NULL. If it opens: register a receive callback and print frames for 10 s; with `--send standby|on|volup`, send `40:36`, `40:04` + `4F:82:23:00`, or `45:44:41` + `45:45`. Reverse-engineering the signatures is part of this step: try the shapes in the Research section; record what worked.
  - Run over SSH (`swiftc` on the mini, binaries in `/tmp/mmtvl-probes/`, deleted after), with the user at the TV, Remote Buddy not running:
    1. `gc`: press buttons; record whether the remote appears.
    2. `hid-seize --seconds 90`: press Vol+, Vol−, Mute, Play/Pause (does the volume HUD show? does Music open?), then **Power** (does the Mac sleep, lock or show anything?). If Power sleeps or locks the Mac, record it; then (with the user's OK) `defaults write com.apple.loginwindow PowerButtonSleepsSystem -bool false` and repeat.
    3. `pmset displaysleepnow`: does the TV turn off (macOS's own CEC)? Wake with a mouse move: does it turn on?
    4. `cec`: open result; with the user's OK, `--send standby`, `--send on`, `--send volup`.
    5. Pioneer write commands (a small Python termios script like the 2026-11-06 query script, run with `python3 -I`): `VD` then `VU` (volume back where it was), `MO` then `MF`, then `PF`, wait 5 s, `PO` twice 100 ms apart. Does the TV follow the receiver's power?
  - Done when: each result above is written under *Deviations & questions* as "Step 1 results" (raw lines saved in the session scratchpad), including the **CEC gate** (opens / doesn't) and the **Power gate** (needs the loginwindow setting / doesn't).

- [ ] **2. Apply the probe results** `[doc]`: files: this plan
  - CEC gate failed → mark step 9 "skipped (CEC not available)", and make steps 10–11 show CEC as unavailable. Power gate → add the loginwindow setting to the TV steps and CLAUDE.md. Siri Remote seen by GameController → keep L10, else drop it from step 4. Adjust timings (L4–L7) only if the probe showed reasons.
  - Done when: the plan has no open gate.

- [ ] **3. Triggers, commands and bindings revision 3** `[implementer]`: files: `Input/SiriRemote/SiriRemoteButton.swift` (new), `Input/InputBinding.swift`, `Input/RemoteCommand.swift`, `Input/KeyBindings.swift`, `Input/KeyBindings+Editing.swift`, `Input/TriggerName.swift`, `Input/ExternalKeyMap.swift`, `App/AppDelegate.swift` (`migrateBindings`), `MMTVLTests/KeyBindingsTests.swift`, `MMTVLTests/KeyBindingsEditingTests.swift`, `MMTVLTests/TriggerNameTests.swift`, `MMTVLTests/SiriRemoteButtonTests.swift` (new)
  - L2: `SiriRemoteButton` (String raw values as in L2) with `static func from(usagePage: UInt32, usage: UInt32) -> SiriRemoteButton?` per the probe table, and `static func isSiri(usagePage:usage:) -> Bool` (0x0C/0x04). `Trigger.siriRemote(button:)` (JSON `{"siriRemote":{"button":"tv"}}`), `KeyBindings.binding(siriRemote:)`. `RemoteCommand` appends `volumeUp, volumeDown, mute, power, powerMenu` with titles "Volume Up", "Volume Down", "Mute", "Power", "Power Menu". `ExternalKeyMap`: the new commands → nil (handled before it, L3).
  - Defaults: the L2 Siri Remote bindings (`isGlobal: true`, labels "Siri Remote TV", …); `currentRevision = 3`. Migration: revision < 3 → add the Siri Remote defaults (`addingDefaults` for their commands, Siri Remote triggers only) and remove L9's plain-letter/digit global bindings (log each removed one: `Removed global binding <name>`, category `Input`).
  - L9 guard in `adding` and `settingGlobal`; `canSetGlobal(_ trigger:) -> Bool`.
  - Names: `TriggerName.describe(.siriRemote(.tv))` = "Siri Remote TV" etc.; kind "Siri Remote".
  - Tests: Siri Remote trigger JSON round-trips; every probe usage maps to its button and unknown usages to nil; revision-2 bindings with `{"key":{"keyCode":0,"modifiers":[]}}` global Home migrate to revision 3 without it and with the Siri Remote defaults; `adding(.key(kVK_ANSI_A, []), to: .home)` stays non-global; `canSetGlobal` false for letters/digits, true for F-keys and Home; names.
  - Done when: `xcodebuild … test` passes with the new tests listed in the output.

- [ ] **4. Siri Remote buttons** `[implementer]` `[security]`: files: `Input/SiriRemote/SiriRemoteHID.swift`, `SiriRemoteGestures.swift`, `SiriRemoteInput.swift` (new), `Input/ExternalRouter.swift` (new), `RemoteServer/PhoneRemote.swift`, `Input/InputRouter.swift` (capture of `.siriRemote`), `Input/ControllerInput.swift` (L10, if kept), `App/AppSettings.swift` (`siriRemoteEnabled`), `App/AppDelegate.swift`, `MMTVLTests/SiriRemoteGesturesTests.swift` (new), `MMTVLTests/PhoneRemoteTests.swift`, `MMTVLTests/AppSettingsTests.swift`
  - `SiriRemoteHID`: `IOHIDManagerCreate`, matching `[{VendorID: 76, ProductID: p} for p in RemoteBattery.productIDs]`, device matching callback opens each device seized (L1) and logs `Siri Remote interface 0x0C/0x01 open: seized` (category `SiriRemote`, notice), removal callback synthesizes releases for held buttons, value callback → `onButton(SiriRemoteButton?, isSiri: Bool, pressed: Bool)`. Starts/stops with `siriRemoteEnabled`; restarts after wake.
  - `SiriRemoteGestures` per L4/L5 with injected `now` and a scheduled-tick API (no timers inside; `SiriRemoteInput` drives a 30 ms task while something is held).
  - `ExternalRouter.route(_ command:)` = L3's last three rungs; `PhoneRemote.route` uses it (behavior unchanged; existing `PhoneRemoteTests` stay green).
  - `SiriRemoteInput`: capture (`InputRouter.capture(.siriRemote(button))` while learning, Siri never captured), binding lookup, then L3; volume/power commands call closures (`onVolume`, `onPower`) that steps 10/12 fill (until then they log).
  - Tests (`SiriRemoteGesturesTests`): short centre → select; centre held 0.6 s → menu once, no select; held up → up, then repeats at 450 ms and every 120 ms with `isRepeat`; Siri, Siri within 0.4 s → toggleTrackpad; single Siri → nothing; power held 0.8 s → powerMenu, short → power; trackpad mode: short centre → click(left), long → click(right) once; removal mid-press → release, no long-press event.
  - Done when: tests pass; in `-windowed YES` on the dev Mac (no remote) the app logs `Siri Remote: no remote connected` and nothing else changes; `[security]` review of the HID seize and synthetic routing passes.

- [ ] **5. Touch: swipes and trackpad mapping** `[implementer]`: files: `Input/SiriRemote/MultitouchDevices.swift`, `SwipeRecognizer.swift`, `TrackpadMapper.swift` (new), `Input/SiriRemote/SiriRemoteInput.swift`, `MMTVLTests/SwipeRecognizerTests.swift`, `MMTVLTests/TrackpadMapperTests.swift` (new)
  - `MultitouchDevices`: `dlopen` + `dlsym` (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTUnregisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceIsBuiltIn`, `MTDeviceGetFamilyID`); missing symbols → `isAvailable = false`, log once. Only devices with `MTDeviceIsBuiltIn == false`. The C callback copies `count`, and for the first finger `state` (offset 20), x, y (32, 36) into a `TouchFrame` and hops to the main actor. Matching notifications on `AppleMultitouchDevice` rebuild the list; stop on `willSleep`, restart on `didWake`.
  - `SwipeRecognizer` (L6) and `TrackpadMapper` (L7), pure.
  - `SiriRemoteInput`: normal mode feeds `SwipeRecognizer` (steps → commands through L3, `isRepeat: false`), suppressed around clicks; trackpad mode feeds `TrackpadMapper` → `PhonePointer.perform`.
  - Tests: a 0.5 slide right → 2 rights; a slow 0.2 slide → none; a fast flick → extra steps capped at 2; a slide during a click → none; vertical dominant axis; trackpad: deltas scale and invert y; a touch starting at x 0.9 scrolls vertically only; at y 0.1 horizontally; lift resets.
  - Done when: tests pass and the build succeeds; on the dev Mac (a MacBook trackpad, if any) the built-in trackpad is ignored (log `Multitouch: 0 remote surfaces`).

- [ ] **6. Toast overlay** `[designer]`: files: `DesignSystem/OverlayToast.swift` (new), `App/AppDelegate.swift`
  - L8: a glass capsule (`.glassPanel(in: Capsule())`, Theme type tokens; an SF Symbol: `cursorarrow.motionlines` for trackpad, `speaker.wave.2.fill` / `speaker.slash.fill` for volume, `exclamationmark.triangle` for errors), top-centre of the main screen, 2 s, fades; a new message replaces the old one. Reduce Transparency → solid. API: `OverlayToast.shared.show(_ text: String, symbol: String)`.
  - Done when: in `-windowed YES`, a debug trigger (Settings → Siri Remote → Status row Select in Debug builds) shows "Trackpad On" over another app (e.g. Finder in front), clicks pass through it, and a screenshot is attached to the step's hand-back.

- [ ] **7. Trackpad mode** `[implementer]` `[security]`: files: `Input/SiriRemote/SiriRemoteInput.swift`, `App/AppDelegate.swift` (cursor auto-hide), `MMTVLTests/SiriRemoteGesturesTests.swift`
  - Mode toggle (L5) with the toast; clicks through `PhonePointer` (`ClickCounter`), right click per L4; Back stays L3's Back; Home leaves trackpad mode; cursor auto-hide off while on. Log `Trackpad mode on/off` (category `SiriRemote`).
  - Done when: tests for the mode switch pass, the build succeeds, `[security]` review passes.

- [ ] **8. Receiver protocols and serial** `[implementer]`: files: `AVControl/SerialPort.swift`, `ReceiverProtocol.swift`, `ReceiverProtocols/Pioneer.swift`, `Onkyo.swift`, `Denon.swift`, `Yamaha.swift`, `ReceiverController.swift` (new), `App/AppSettings.swift` (`receiverBrand`, `receiverConnection`, `receiverSerialPort`), `MMTVLTests/ReceiverProtocolTests.swift`, `MMTVLTests/ReceiverControllerTests.swift` (new)
  - L11 per *Receiver protocols*. `ReceiverProtocol` (protocol, `nonisolated`): `serial: SerialSettings` (baud, data bits, parity, stop bits), `terminator: [UInt8]`, `minimumGap: Duration`, `wakeRule` (Pioneer: send `powerOn` twice 100 ms apart; others per table), `encode(_ ReceiverCommand) -> [UInt8]`, `parse(line: String) -> ReceiverStatus?`, `probeQueries: [ReceiverCommand]` (the query commands only, L12).
  - `SerialPort`: termios setup per `SerialSettings` (Research), line splitting on the protocol's terminator, `close()` on deinit; `available() -> [SerialPortInfo]` (path, USB product name).
  - `ReceiverController`: transport protocol `ReceiverTransport` (send bytes, receive lines) so tests use a fake; queue with `minimumGap`; status from replies and unsolicited lines; `test() async -> ReceiverTestResult` and `find(on port:) async -> ReceiverBrand?` (L12, read-only queries only, 2 s per brand); reconnects when the port disappears (log `Receiver port gone`, category `Receiver`).
  - Tests: per vendor, every command encodes to the table's bytes; replies parse (Pioneer `PWR0`, `VOL61` → −20 dB, `VOL161` → 0 dB, `MUT1`; Onkyo `!1MVL28\u{1A}` → 40; Denon `MV805` → +0.5 dB and `MV80` → 0 dB, `MVMAX 98` ignored; Yamaha `@MAIN:VOL=-35.5`; Anthem `Z1VOL-35`; NAD `Main.Volume=-30`); `probeQueries` contain only queries; the Pioneer power-on sends twice ≥ 100 ms apart (fake clock); `find` stops at the first brand that answers and never encodes a non-query; the gap is honored.
  - Done when: tests pass, and at launch no serial port is opened while `receiverBrand` is `none` (log `Receiver: not set up`, category `Receiver`).

- [ ] **8b. Network transport and discovery** `[implementer]` `[security]`: files: `AVControl/ReceiverTCPTransport.swift`, `AVControl/ReceiverDiscovery.swift` (new), `AVControl/ReceiverProtocol.swift` (`networkPort`, `networkFraming`), `AVControl/ReceiverProtocols/Onkyo.swift` (eISCP header), `AVControl/ReceiverController.swift`, `App/AppSettings.swift` (`receiverHost`, `receiverNetworkPort`), `MMTVLTests/ReceiverProtocolTests.swift`, `MMTVLTests/ReceiverDiscoveryTests.swift` (new)
  - L17. The SSDP search can reuse the parsing in `Cast/` only if it fits as-is (`SSDPResponder` answers searches; this sends one): keep a small sender in `ReceiverDiscovery`, `SO_REUSEPORT` like `SSDPResponder`, and fetch each `LOCATION` description (http, LAN only, 2 s timeout, 64 KB cap) to read `manufacturer`/`modelName`.
  - Tests: eISCP framing of `!1PWR01` (header `ISCP`, header size 16, data size, version 1) and unframing of a reply; the brand's default port; an SSDP response and a device description parse to (brand, model, host); a description larger than the cap is rejected; non-LAN `LOCATION` hosts are ignored.
  - Done when: tests pass; `[security]` review passes (outgoing LAN connections only, no description fetch beyond the cap, hosts only in logs). **Not testable on hardware here** (record "untested on a real networked receiver" in *Deviations*).

- [ ] **9. HDMI-CEC transport** `[implementer]` (skip if step 1's CEC gate failed): files: `AVControl/CECBus.swift` (new), `AVControl/ReceiverController.swift`, `MMTVLTests/CECFrameTests.swift` (new)
  - L13 with the signatures step 1 found. Pure `CECFrame` builders for the frames in *Research* (TV standby, Image View On, then Active Source with the Mac's physical address read from the CEC interface at runtime; never hardcoded, and Active Source is skipped if it can't be read), audio-system volume up/down/mute (press + release), power status query. As a `ReceiverTransport` for `receiverConnection = cec` (volume/mute/power to address 5), and `tvPower(on:)` for step 12.
  - Done when: frame tests pass; on the mini (TV step 15) `cec` connection changes the receiver volume or the step records that the receiver ignores it.

- [ ] **10. Volume to the receiver** `[implementer]`: files: `App/Volume.swift`, `App/AppDelegate.swift`, `Input/SiriRemote/SiriRemoteInput.swift`, `MMTVLTests/VolumeTests.swift`
  - D44: `VolumeMode` gains `receiver`; `VolumeRoute` gains `.receiver`; `choose` takes `receiverReady: Bool` first in `auto`. `VolumeController.perform` sends `volumeUp/Down` or `mute(!muted)` through `ReceiverController` and returns `.level` from the reported dB when known. The Siri Remote's `onVolume` and the phone both use it. Toast (L8) on Siri Remote volume: "Volume −20 dB" / "Muted" / "Volume" (no level known).
  - Tests: `choose` order for each mode with and without a ready receiver; feedback mapping.
  - Done when: tests pass.

- [ ] **11. Settings pages** `[implementer]`: files: `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsEnvironment.swift`, `App/AppDelegate.swift`, `App/AppSettings.swift` (`tvPowerControl`), `MMTVLTests/SettingsSiriRemoteTests.swift`, `MMTVLTests/SettingsReceiverTests.swift` (new), `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/AppSettingsTests.swift`
  - Pages and rows per *Settings pages* (new `SettingsPage` cases `siriRemote`, `receiver`, `receiverBrand`, `receiverPort`; actions `setReceiverBrand(ReceiverBrand)`, `setReceiverPort(String?)`, `testReceiver`, `findReceiver`; toggles `siriRemoteEnabled`, receiver connection and TV power as two-value rows like Channel Up). Environment closures for status, ports, test and find (async, the row's detail shows "Testing…", then the result).
  - Tests: rows and values for each state (no remote, connected; brand none/pioneer; serial vs CEC hides Serial Port and Find); `setReceiverBrand` saves `receiverBrand`; test result text; decoding of the new keys (missing → defaults; unknown brand → none).
  - Done when: tests pass; in `-windowed YES` the pages open from Remote & Input and read right (screenshot in the hand-back).

- [ ] **12. Power button and power menu** `[implementer]` `[security]`: files: `AVControl/PowerController.swift`, `Launcher/PowerMenu.swift`, `Launcher/PowerMenuView.swift` (new), `Launcher/AppRouter.swift`, `PIN/PINFlow.swift`, `App/AppDelegate.swift`, `MMTVLTests/PowerMenuTests.swift`, `MMTVLTests/PowerControllerTests.swift` (new), `MMTVLTests/PINFlowTests.swift`, `MMTVLTests/AppRouterTests.swift`
  - `PowerController` (L14) with injected effects (`receiver`, `tv`, `sleepDisplays`, `wakeDisplays`, `sleepMac`, `restartMac`, `relaunch`) so tests fake them; real effects: `pmset displaysleepnow`, `IOPMAssertionDeclareUserActivity`, `pmset sleepnow` (fallback Apple event), `kAERestart` to `loginwindow`, `AppRelauncher.relaunch`. Log every action (category `Power`, notice) and, 10 s after power-on, the default output device name and transport.
  - `PowerMenu` (pure, `LiveMenu`-like) and `PowerMenuView` (glass panel, centered; designer polish optional) as a top-level overlay in `LauncherRootView` above every screen, YouTube and Live TV included; `AppRouter` routes commands to it while open. `powerMenu` brings MMTVL forward first (`Foregrounder`, reason `powerMenu`). Relaunch and Restart go through PIN entry when a PIN is set (`PINPurpose.relaunch`, `.restartMac`); cancel returns to the menu's screen.
  - Tests: short press off → receiver off, TV standby, displays sleep, in that order; next press → wake, receiver on, TV on; menu items, Back cancels; Restart with a PIN asks for it, without a PIN runs at once; wrong PIN doesn't restart.
  - Done when: tests pass; in `-windowed YES`, the keyboard (bind a key to Power Menu in Remote Buttons) opens the menu over Settings and Live TV, and Cancel/Back close it; `[security]` review passes (restart/relaunch behind the PIN, no shell strings built from input).

- [ ] **13. Plex restart after a hot-plug** `[implementer]`: files: `App/DisplayHotplugMonitor.swift` (new), `Launcher/AppLauncher.swift`, `App/AppDelegate.swift`, `MMTVLTests/AppLauncherTests.swift`, `MMTVLTests/DisplayHotplugTests.swift` (new)
  - L16. The monitor's callback is reduced to a pure `HotplugEvent` (display id, added/removed) handled on the main actor; `AppLauncher.noteDisplayChange(frontmostBundleID:)` marks running, non-frontmost apps in `restartAfterHotplug`; `launch(_:)` restarts a marked app per L16 before opening it. Also mark Plex when `PowerController` turns the TV on.
  - Tests: a remove/add while Plex runs in the background marks it; while Plex is frontmost it doesn't; opening a marked app terminates then launches it and its pid leaves `launchedPIDs` first (so `applicationDidTerminate` doesn't go Home); an unmarked app opens as before.
  - Done when: tests pass; record in M7f's *Deviations*: "Step 5's Plex fix is M7h step 13 (D45)".

- [ ] **14. TV check, build 1: the remote** `[human]` (after steps 3–7; one test build via `scripts/test-build.sh` and `scripts/deploy-mm.sh`, after the user says yes)
  - Remote Buddy quit (or uninstalled). In Settings → Remote & Input → Remote Buttons, the old "A" Home binding is gone; typing "a" in Safari types "a".
  - TV goes Home from Plex, Safari, Prime Video and Live TV; Back, Play/Pause and clickpad clicks work in MMTVL and in Plex/Safari (arrow keys, Return, Escape).
  - Swipes move focus on the home screen, in Settings and in the Live TV guide, one step per short swipe, several for a long one; clicking doesn't swipe. Long press centre opens the channel menu in Live TV.
  - Double-press Siri: "Trackpad On" toast; the pointer moves smoothly, centre click clicks, long press right-clicks (context menu in Safari), right-edge slide scrolls a web page, Back is Esc; double-press again: "Trackpad Off". Single Siri press does nothing.
  - Leave the remote alone 10 minutes, then press TV: it works (first press may be slow: note how slow).
  - Logs: `ssh mm "/usr/bin/log show --last 30m --predicate 'subsystem == \"dev.mmtvl.launcher\" AND (category == \"SiriRemote\" OR category == \"Input\")' --info"`.
  - Done when: each item is ticked in *Manual verification* or recorded under *Deviations*.

- [ ] **15. TV check, build 2: receiver, TV, power and Plex** `[human]` (after steps 8–13; one test build)
  - Plex: leave Plex in the background, turn the TV off and on with the TV's own remote, open Plex: it draws (it was restarted: `log show --last 15m --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "AppLauncher"' --info` shows `Restarting tv.plex.htpc after a display change`).
  - Settings → Remote & Input → Receiver & TV: Find Receiver (Serial) selects Pioneer; Network → Find Receiver finds nothing (no networked receiver) and says so, without errors; Test Connection shows "On · … dB · …" matching the receiver's display. Brand None hides control.
  - Volume Up/Down and Mute on the remote change the receiver, with the toast showing the dB value; the phone's volume buttons do the same.
  - Power short press: receiver and TV off, displays asleep; press again: all back on, MMTVL's home screen shows; Plex opens and draws. If CEC passed step 1: HDMI-CEC connection, Test Connection and volume work, or record what the receiver ignores.
  - Long press Power in Plex: MMTVL's power menu over the screen; Cancel/Back return; Relaunch asks for the PIN; Sleep Mac mini sleeps it (wake with the keyboard); Restart Mac mini asks for the PIN and restarts (MMTVL comes back at login).
  - Power while macOS's loginwindow setting is as step 2 decided: the Mac doesn't sleep or lock by itself.
  - Logs: `ssh mm "/usr/bin/log show --last 30m --predicate 'subsystem == \"dev.mmtvl.launcher\" AND (category == \"Receiver\" OR category == \"Power\")' --info"`.
  - Done when: each item is ticked or recorded.

- [ ] **16. Docs and cleanup** `[doc]`: files: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan, `scripts/probes/` (delete)
  - CLAUDE.md: replace the "Siri Remote through Remote Buddy (M7c L5)" paragraph with the own driver (D43: buttons, swipes, trackpad mode, Siri double-press, long presses, the toast); the new `settings.json` keys; the `siriRemote` trigger in `key-bindings.json`; new commands; Receiver & TV (D44: brands, serial path, CEC status, Test/Find are read-only, the AVR queries from Terminal); Power (D45, the loginwindow setting if step 2 needed it); the Plex restart after hot-plugs; log commands for categories `SiriRemote`, `Receiver`, `Power`. Remove "Game Controllers must stay on" for the TV button. D25's text in the master plan points to D44.
  - Master plan: M7h `Done`, Q21 and Q22 resolved, this plan moved to `archive/`.
  - Done when: `git grep -n "Remote Buddy" CLAUDE.md` shows only history notes, and the probes are deleted.

## Tests

- New suites: `SiriRemoteButtonTests`, `SiriRemoteGesturesTests`, `SwipeRecognizerTests`, `TrackpadMapperTests`, `ReceiverProtocolTests`, `ReceiverControllerTests`, `CECFrameTests` (if step 9 runs), `SettingsSiriRemoteTests`, `SettingsReceiverTests`, `PowerMenuTests`, `PowerControllerTests`, `DisplayHotplugTests`.
- Extended: `KeyBindingsTests`, `KeyBindingsEditingTests`, `TriggerNameTests`, `VolumeTests`, `AppSettingsTests`, `AppLauncherTests`, `AppRouterTests`, `PINFlowTests`, `PhoneRemoteTests`.
- Run after every step: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`.

## Manual verification

- [ ] Step 1's probe results recorded (GameController, seize and macOS's own handling, Power, display sleep CEC, IOCEC open, Pioneer writes).
- [ ] Remote Buddy is quit or uninstalled on the mini, and the old global "A" binding is gone; "a" types in browsers.
- [ ] TV = Home from every app; clickpad and swipes in MMTVL and in other apps; long-press centre = menu.
- [ ] Trackpad mode: Siri double-press toggles with the toast; move, click, right-click, scroll, Back.
- [ ] The remote works after 10 minutes idle and after the Mac's sleep and wake.
- [ ] Plex draws after a TV power cycle (restarted on open).
- [ ] Receiver: Find and Test (read-only), volume and mute with the toast, from the remote and the phone.
- [ ] Power short press off and on; power menu with PIN for Relaunch and Restart; the Mac doesn't sleep by itself on Power.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Power still sleeps or locks the Mac while seized | Step 1: the Mac sleeps on Power | `PowerButtonSleepsSystem = false` in `com.apple.loginwindow` (with the user's OK), documented in CLAUDE.md; else Power menu only on long press of TV. |
| Play/Pause opens Music through `com.apple.rcd` | Step 1: Music opens | The kiosk guard already takes the screen back; if not enough, record it and decide with the user (suspending `rcd` is out of scope). |
| MMTVL can't open CEC while `corercd` holds it | Step 1: `IOCECInterfaceCreate` NULL | L13: CEC shows as unavailable; TV power by display sleep only (macOS's own CEC, if step 1 shows it). |
| The receiver ignores CEC volume from the Mac | Step 15 | Serial stays the default for Pioneer; CEC recorded as TV-power only. |
| MultitouchSupport changes or is missing in a macOS update | `isAvailable == false` | Buttons keep working; swipes and trackpad mode off; Settings → Siri Remote → Status says "Touch not available". |
| The remote also appears as a game controller | Step 1 `gc` | L10. |
| Swipe or trackpad tuning feels wrong on the TV | Step 14 | All thresholds are constants in `SwipeRecognizer`/`TrackpadMapper`; record new values under *Deviations* and adjust in a follow-up. |
| A networked receiver allows one client only, or drops idle connections | Can't be tested here (L17) | Close after 5 idle minutes, reconnect on demand; Test Connection shows "Connection refused" plainly. |
| Other brands' protocols are wrong in detail | Can't be tested here | Marked unverified in Settings' footer ("Tested with Pioneer"); Test Connection shows raw replies to help. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
