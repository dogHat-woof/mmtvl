# M7h — Own Siri Remote driver, receiver & TV control, power button

| | |
|---|---|
| Status | Done (2026-11-08) |
| Depends on | [M7e](M7e-siri-remote-spike.md) (its probe results and the user's "build it" decision), M7g (the Settings layout these pages use), M7f (Q22; this plan takes over its step 5 Plex fix) |
| Master plan decisions used | D2 (focus), D3 (`RemoteCommand`), D4 (Accessibility), D16 (`key-bindings.json`), D20 (PIN), D24 (phone remote, synthetic input), D25 (volume routes; amended by D44), D27 (commands), D35 (foregrounding), D36 (kiosk lock), D42 (Settings layout); new D43, D44, D45 |
| Planned | 2026-11-06 |

## Next session starts here

*Updated 2026-11-08: **M7h is done.** Merged to `master` as PR #21 (after M7f #19 and M7g #20); version 1.2.0. Build 28 (1.1.0, `6a3687f` before the rebase) is on the MM; the next test build is 1.2.0 build 29. Follow-ups: M7i (inputs), M7j (antenna), M7k (software volume), M7l (TV polish). Not fixed: `SerialPort.write`'s main-thread `usleep` retry loop (up to 100 ms, `AVControl/SerialPort.swift`).*

## Goal

The Siri Remote works without Remote Buddy, everywhere: TV is Home from any app, the clickpad clicks and **swipes** move focus like on an Apple TV, and in Plex, the browser and Prime Video the remote drives the app through MMTVL's synthetic keys. A **double-press of Siri** switches the remote to **trackpad mode** and back (a 2-second "Trackpad On/Off" toast, like Remote Buddy): the touch surface moves the pointer, a centre click clicks, a **long press of the centre right-clicks**, Back stays Back, and sliding along the right edge scrolls. **Volume and Mute** reach the AV receiver over **RS-232** (Pioneer first; Onkyo/Integra, Denon/Marantz, Yamaha, Anthem and NAD too), or the **network** (the same commands over TCP, for receivers with a LAN port; untested here), chosen in Settings (HDMI-CEC isn't available to apps on macOS, step 1), which can **test the connection with read-only queries** and **find the receiver** by trying each brand. The remote's volume keys reach MMTVL through its event tap (step 1). The **Power** button turns the TV and receiver off or on like an Apple TV (the TV, a Panasonic VIERA, over the network and Wake-on-LAN; the receiver over RS-232); a **long press** opens a power menu (Turn Off TV, Sleep Mac mini, Relaunch MMTVL, Restart Mac mini; the restart items ask for the PIN). After any HDMI hot-plug (the TV turned off and on, by the Power button or not), **Plex HTPC is restarted on its next open**, so it never shows a black screen (Q22). Typing "a" in a browser no longer jumps to Home.

## Out of scope

- Restarting `coreaudiod` after a hot-plug (needs root; the HDMI audio dropout of 2026-11-05 is tracked in memory and fixed by `sudo killall coreaudiod` or, long term, hardware). This plan only **logs** the default output device after MMTVL powers the TV on.
- The Pulse-Eight USB-CEC adapter (not chosen, 2026-11-06). HDMI-CEC from the Mac itself (not possible for apps, step 1).
- Siri voice input. The Siri button is reserved for the trackpad toggle.
- Waking the Mac from sleep with the remote (macOS doesn't allow it since 11.3.1, per Remote Buddy's docs).
- Remote Buddy's uninstall itself (the user does it; *Manual verification* lists it).

## Research & findings

### The remote (from [M7e's probe](M7e-siri-remote-spike.md), 2026-11-06)

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

- The mini has an **FTDI FT232R** USB-serial adapter wired to the receiver: `/dev/cu.usbserial-XXXXXXXX` (Apple's built-in `AppleUSBFTDI` DriverKit driver; Prolific, CH340 and CP210x have built-in drivers too).
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

### HDMI-CEC from the Mac (verified on this Mac and the mini, 2026-11-06; **closed to apps**, see step 1 results)

- No public API. `IOCECFamily.kext` is loaded; the registry has `DCPAVCECInterfaceProxy` → `IOAVCECService` (`IOUserClientClass = IOCECUserClient`). On the mini, **`/usr/libexec/corercd` (pid 205) already holds an `IOCECUserClient`** (its entitlements name `IOCECUserClient`).
- `/System/Library/PrivateFrameworks/IOCEC.framework` exports a C API (`IOCECInterfaceCreate`, `IOCECInterfaceCreateWithService`, `IOCECInterfaceSetLogicalAddressMask`, `IOCECInterfaceSendFrame`, `IOCECInterfaceRegisterReceiveCallback`, `IOCECInterfaceScheduleWithDispatchQueue`); no headers. On Apple TV 3, `IOCECInterfaceCreate` returns NULL for other processes while `cecd` holds the interface ([appletv3-cec](https://github.com/huguesdelamure/appletv3-cec)). **Unverified on macOS**: step 1's probe answers whether MMTVL can open a second client.
- Apple: the M4 Mac mini's HDMI supports CEC and "sleeps and wakes the display with the Mac" ([support 108928](https://support.apple.com/en-us/108928)). **Unverified**: whether **display** sleep (not system sleep) makes macOS send CEC standby. Step 1 tries `pmset displaysleepnow`.
- BetterDisplay 5 sends CEC on Apple silicon ("DisplayPort AUX DPCD CEC tunneling"; [wiki](https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI), [issue 3394](https://github.com/waydabber/BetterDisplay/issues/3394)), so it is possible from user space; how is undocumented. BetterDisplay was uninstalled from the mini on 2026-11-05 (it broke HDCP with a virtual screen; not needed for this).
- CEC frames (libcec `cectypes.h`): header `(initiator << 4) | destination`; Mac as playback device 4, TV 0, audio system 5, broadcast F. TV standby `40:36`; TV on `40:04` (Image View On) then Active Source `4F:82:PP:PP` (the Mac's physical address; 0x2300 in the mini's kernel log 2026-11-05: `physicalAddress = 0x2300`); power status `0x8F` → `0x90`; volume up/down/mute to the audio system: User Control Pressed `45:44:41` / `45:44:42` / `45:44:43`, then Released `45:45`.
- **Receiver caveat**: the VSX-01TXH manual calls its CEC "HDMI Control" (Pioneer KURO Link) and says it may not work with non-Pioneer components ([manual p. 67](https://www.manualslib.com/manual/130505/Pioneer-Elite-Vsx-01txh.html?page=67)). The user's TV turning off also turns the receiver off (2026-11-05), so some CEC link works.

### System calls (unverified ones are checked in step 1 or the TV steps)

- Display sleep now: `/usr/bin/pmset displaysleepnow` (no root). Wake displays: `IOPMAssertionDeclareUserActivity(..., kIOPMUserActiveLocal, ...)` (public IOKit).
- Sleep the Mac: `/usr/bin/pmset sleepnow` (**unverified without root** on macOS 26; fallback the `kAESleep` Apple event to `loginwindow`).
- Restart: Apple's documented way is sending `kAERestart` (`'rest'`; `'rrst'` is `kAEShowRestartDialog`, corrected in step 12) to `loginwindow` (Technical Q&A QA1134). **Unverified** whether macOS 26 shows an Automation prompt for it.
- Hot-plug: `CGDisplayRegisterReconfigurationCallback` reports `kCGDisplayRemoveFlag` / `kCGDisplayAddFlag` per display (public CoreGraphics). On 2026-11-05 a TV power cycle removed and re-added the HDMI display about four times in 25 s, and Plex HTPC logged `[DisplayManager] Found 1 Display(s)` for each new display id before every black screen (M7f §1).


### Software volume (M7h, user decision 2026-11-06)

**Decision:** MMTVL stops relying on SoundSource. With a receiver (serial, network, or CEC if step 14b opens it) SoundSource isn't needed. Setups with neither get MMTVL's **own system-wide software volume** for outputs without hardware volume (HDMI). Built last in M7h (steps 17–19).

**Core Audio process taps (primary: SDK headers and Apple's sample):**
- `AudioHardwareCreateProcessTap(CATapDescription*, AudioObjectID*)` / `AudioHardwareDestroyProcessTap`: **macOS 14.2** (`AudioHardwareTapping.h:42-54`; Objective-C only, `#ifdef __OBJC__`, so Swift reaches it through the CoreAudio module). The deployment target is 26.0, so availability is not an issue.
- `CATapDescription` (`CATapDescription.h`):
  - `initExcludingProcesses:andDeviceUID:withStream:` (:111) taps "all process audio streams destined for the selected device stream except the given processes", and "the format of the tap will match the format of this stream". That keeps HDMI's channel count (5.1/7.1 LPCM to a TV or receiver). `initStereoGlobalTapButExcludeProcesses:` (:66) mixes everything down to stereo.
  - `exclusive` (:148) means "tap all processes except" those listed. `bundleIDs` (:135, **macOS 26**) can name processes by bundle id instead of process object.
  - `privateTap` (:160) makes the tap visible only to its creator.
- Mute behaviour (`CATapDescription.h:20-34`):
  - `CATapMuted`: no audio from the tapped process reaches the hardware.
  - `CATapMutedWhenTapped`: muted "for the duration of the read activity on the tap" only. If MMTVL stops reading (quits, crashes, stops the IOProc), the original audio comes back **at full level**. That is a loud jump, but never a stuck silence. Use `.mutedWhenTapped`.
- The aggregate device (`AudioHardware.h`):
  - `kAudioAggregateDeviceTapListKey` "taps" (:1627).
  - `kAudioAggregateDeviceTapAutoStartKey` (:1640): start waits for the first tapped audio, and it requires `kAudioAggregateDeviceIsPrivateKey` (:1609; a private aggregate isn't published and isn't persistent, so it never becomes the default output).
  - Sub-tap keys `kAudioSubTapUIDKey`, `kAudioSubTapDriftCompensationKey` (:1861, :1887).
  - Shape: one private aggregate whose main/clock sub-device is the HDMI device, with the tap in its tap list. An IOProc (`AudioDeviceCreateIOProcIDWithBlock`) reads the tap's input buffers and writes them, times the gain, to the HDMI output buffers.
- Apple's sample, "Capturing system audio with Core Audio taps" (doc JSON fetched 2026-11-06):
  - It needs **`NSAudioCaptureUsageDescription`** in Info.plist.
  - "The first time you start recording from an aggregate device that contains a tap, the system prompts you to grant the app system audio recording permission."
  - It names macOS 14.2.
- Process objects: `kAudioHardwarePropertyTranslatePIDToProcessObject` / `kAudioHardwarePropertyProcessObjectList` (`AudioHardware.h:633-634`), and `kAudioProcessPropertyBundleID` / `IsRunningOutput` (:1974, :1978). MMTVL excludes **itself**, or its own IOProc output would be tapped again (a feedback loop).
- **Hog mode and passthrough** (`AudioHardware.h:932-944`): "If the AudioDevice is in a non-mixable mode, the HAL will automatically take hog mode on behalf of the first process to start an IOProc." Bitstream (AC-3/DTS passthrough) is a non-mixable format (`kAudioFormatFlagIsNonMixable`, `CoreAudioBaseTypes.h:530`). So passthrough can't be tapped or scaled, and a hogged device belongs to one other pid. The engine must watch `kAudioDevicePropertyHogMode` (pid ≠ −1 and ≠ MMTVL → stop). Whether Plex HTPC's passthrough hogs the device, and what a running tap does to it: **unverified** (step 17).
- Listeners for rebuilds:
  - `kAudioHardwarePropertyDefaultOutputDevice`
  - `kAudioHardwarePropertyDevices`
  - `kAudioDevicePropertyDeviceIsAlive` (`AudioHardwareBase.h:746`)
  - `kAudioDevicePropertyNominalSampleRate` (:754)
  - `kAudioDevicePropertyStreamFormat`
  - `kAudioDevicePropertyHogMode`
  - Latency figures: `kAudioDevicePropertyLatency` / `SafetyOffset` / `BufferFrameSize` (:750, :753).

**Permission (TCC):**
- The service is `kTCCServiceAudioCapture`. There is **no public API to check or request it** (insidegui/AudioCap README).
- AudioCap uses the private `TCC.framework` (`dlopen` `/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC`, `TCCAccessPreflight(CFString, CFDictionary?) -> Int`: 0 granted, 1 denied, else unknown; `TCCAccessRequest(…, (Bool) -> Void)`; `AudioRecordingPermission.swift:55-124`). That is the same kind of private-framework use as D43's MultitouchSupport.
- **Denied or unknown permission is dangerous:** "a tap is still created but delivers silence, and a muting tap still mutes" (docs.rs `coreaudio` 0.3.3). Started without the grant, MMTVL would silence every app. **Unverified** on macOS 26 (step 17 checks it). So the engine starts only when preflight says granted, and a **silence watchdog** stops it if the tap gives only zeros while some process is running output to that device.
- AudioCap is sandboxed with `com.apple.security.device.audio-input`. MMTVL isn't sandboxed (no entitlement needed).
- **Unverified:**
  - that an Apple Development-signed app without hardened runtime gets the prompt and a lasting grant (likely, like Accessibility; step 17);
  - the System Settings section name (FineTune says "Screen & System Audio Recording"; macOS 15+ has a "System Audio Recording Only" list);
  - `tccutil reset AudioCapture dev.mmtvl.launcher`;
  - whether macOS 15+'s periodic "continue to allow?" re-prompt (seen for screen recording) also applies to audio-only taps. A recurring prompt on the TV would be a blocker.
- **Unverified:** whether Xcode's generated Info.plist emits `INFOPLIST_KEY_NSAudioCaptureUsageDescription`. AudioCap's README says the key isn't in Xcode's list, so it's entered by hand. Check: build, then `plutil -p build/Build/Products/Debug/MMTVL.app/Contents/Info.plist | grep NSAudioCapture`. TurnThatDown's author reports that on macOS 26 taps return non-zero buffers only with the key present.

**Open-source references (read 2026-11-06):**
- **FineTune** (ronitsingh10/FineTune, `FineTune/Audio/Engine/ProcessTapController.swift`):
  - :535-557: per-app taps with `.mutedWhenTapped` and `isPrivate`. It prefers a device-stream tap and falls back to a stereo mixdown.
  - :376-410: aggregate keys `MainSubDevice` = `ClockDevice` = the output, `IsPrivate`, `TapAutoStart`, `IsStacked` false for a single device. Tap drift compensation is **on for wired outputs**, off for Bluetooth and virtual ones (crackle).
  - :711-790: device switches crossfade a second tap and aggregate, then destroy the old one.
  - Its issues show the risks:
    - #81: about 0.5 s of added delay on YouTube for some users;
    - #424: Bluetooth A/V desync beyond the documented ~10–13 ms;
    - #455: a few seconds at full volume when playback starts (per-app taps attach late; a global exclusive tap avoids this);
    - #228/#279: HDMI through USB-C hubs dropping when FineTune starts (from its display/DDC probing, probably; MMTVL does no DDC).
- **SonicFlow** (altuzar/sonicflow): the same shape (per-app `CATapMutedWhenTapped` taps, a private aggregate, a gain IOProc, "~10 ms"). Device hot-swap is listed as not done.
- No source covers FairPlay-protected audio (Prime Video). Whether it's tapped, tapped as zeros while muted, or left unmuted at full level: **unverified** (step 17 gate C).

**The alternative: an AudioServerPlugIn virtual device** (BackgroundMusic-style; ExistentialAudio/BlackHole is the passive loopback version):
- The bundle goes in `/Library/Audio/Plug-Ins/HAL` (`AudioServerPlugIn.h:22`), so installing needs admin. The host is coreaudiod, and the plug-in runs **sandboxed inside coreaudiod** (:38).
- Install and update need `sudo killall -9 coreaudiod` (BlackHole README; BackgroundMusic's installer restarts coreaudiod). That interrupts all audio, and on the mini Plex HTPC then has to be reopened before it plays (memory, 2026-11-05).
- It must become the **default output** (BackgroundMusic sets itself as default). Apps that pick HDMI by name bypass it, and MMTVL has to play its output through to HDMI.
- BackgroundMusic: alpha, "only 2-channel (stereo) audio devices are currently supported for output", clipping above 50 % app volume.
- It needs a separate driver target and signing, plus an installer step on the mini.
- SoundSource's own ARK is this kind of in-coreaudiod component, and it is the suspect for the mini's HDMI dropout after a TV power cycle (memory).
- **Recommendation: process taps.** No install, no admin, no coreaudiod restart. Nothing runs inside coreaudiod: when MMTVL quits or crashes, the tap and aggregate go with it and `.mutedWhenTapped` returns the original audio (step 17 confirms). The device-stream tap keeps multichannel. It's the public API Apple documents. The costs are a TCC grant, added latency (step 17 measures it) and a rebuild on every HDMI hot-plug.

**Existing MMTVL code to change or reuse:**
- `App/Volume.swift`:
  - `VolumeMode` `auto|keys|system|app` :7; `VolumeRoute` :10; `choose(mode:soundSourceRunning:systemSettable:launcherActive:)` :14-27.
  - `VolumeFeedback` (`.level`, `.sentKeys`, `.unavailable`) :30-35; `AppVolume` (±5, mute toggle) :38-58.
  - `SystemVolume` :61-149: `isSettable` :65 reads `VirtualMainVolume` on the default output every call; `step` 1/16 :97-106 (reuse it for software steps).
  - `VolumeController` :152-205: `soundSourceBundleID` :153; SoundSource detection by `NSWorkspace.runningApplications` :169-171; the keys route posting `SyntheticInput.NXKey.soundUp/soundDown/mute` :177-185 (`Input/SyntheticInput.swift:12`, used nowhere else). Log category `PhoneRemote` :154.
- Callers:
  - The phone: `AppDelegate.setUpPhoneRemote` creates the controller at `AppDelegate.swift:385-393`, with `applyAppVolume` → `liveTV.setAppVolume` (`IPTV/LiveTVModel.swift:368`) and `youtube.setVolume` (`YouTube/YouTubeController.swift:115`). It is wired into the environment at :418.
  - The phone's feedback: `RemoteServer/PhoneRemote.swift:113-118` (`.sentKeys` → `volume(level: nil)`); wire `RemoteMessage.swift:3`, :56-57; page toast `Web/remote.js:66-67` ("Volume N%").
  - The Siri Remote: `SiriRemoteInput.onVolume` `Input/SiriRemote/SiriRemoteInput.swift:13-16` (logs only), routed at :219-221.
  - Volume keys: `GlobalEventTap.decide` :119, `.media` path :154-176, mask :79; `MediaKeyEvent.parse` returns nil for volume (`Input/MediaKeyEvent.swift:12-28`).
- `AppSettings.phoneRemoteVolume` :18 (a String), `volumeMode` :52 (`VolumeMode(rawValue:) ?? .auto`), decode :67. Because unknown values already read as `auto`, **deleting the `keys` case makes an old `"keys"` read as `auto`** with no migration code.
- The toast: `OverlayToast.shared.show(_:symbol:)` (`DesignSystem/OverlayToast.swift:22`), L8.
- The Settings footer that names SoundSource: `Settings/SettingsModel+Pages.swift:656`.
- Docs that name SoundSource: `MASTER_PLAN.md:35` (§3 Volume), :69 (D25), Q8 :152; `CLAUDE.md:95` (`phoneRemoteVolume` values).
- Tests: `MMTVLTests/VolumeTests.swift` (`choose` matrix :5-22, `AppVolume` :24, `SystemVolume.step` :44, parsing :52); `AppSettingsTests.swift:43-54`.
- **What step 10 adds** (not built yet; build on it):
  - `VolumeMode.receiver` and `VolumeRoute.receiver`;
  - `choose` takes `receiverReady` first in `auto`;
  - `perform` routes to `ReceiverController`;
  - the Siri Remote's `onVolume` uses `VolumeController`, with the L8 toast;
  - L3a's tap path consumes Vol±/Mute "while the receiver route is ready".

  Step 18 widens that predicate to "the route is receiver or software", removes `soundSourceRunning`, and adds `softwareReady`.

**HDMI audio after a TV power cycle (memory, 2026-11-05):** HDMI audio went silent after the TV and receiver power-cycled; `killall coreaudiod` fixed it, and SoundSource's ARK (which rebuilt its taps many times as HDMI dropped about 4 times) is suspected. This plan doesn't fix it (still out of scope). Two checks follow from it:
- After SoundSource is uninstalled, step 19 re-runs the TV power-cycle test without ARK. If the dropout is gone, record that as evidence for the memory note.
- MMTVL's own engine rebuilds on the same hot-plugs, so it must debounce, or it could cause the same thing (step 17 gate E).

## Design

### New master plan decisions

- **D43 — Own Siri Remote driver** (replaces Remote Buddy, M7e): MMTVL reads the Siri Remote with `IOHIDManager` (Apple vendor, `RemoteBattery.productIDs`), **seized** so macOS doesn't act on its buttons too, and its touch surface with the private **MultitouchSupport** framework (`dlopen`; without it, buttons still work and swipes/trackpad mode are off). Buttons are a new trigger kind `{"siriRemote":{"button":"…"}}` in `key-bindings.json`. Normal mode: clickpad and swipes move focus, other apps get keys through `SyntheticInput` (D24's path). **Siri double-press toggles trackpad mode** (touch moves the pointer, centre click = click, long press = right click, Back = Back, right-edge slide = scroll); a 2-second toast says "Trackpad On/Off". Siri is reserved (not bindable). Rationale: Remote Buddy's trial expired; its TV-button Home typed "a" (2026-11-06).
- **D44 — Receiver & TV control** (amends D25): an `AVControl/` layer with per-vendor receiver protocols (Pioneer, Onkyo/Integra/Pioneer 2016+, Denon/Marantz, Yamaha, Anthem, NAD), over **RS-232** (POSIX serial), the **network** (the same commands over TCP with Network.framework; Onkyo's eISCP adds its header) chosen in Settings → Remote & Input → Receiver & TV, which tests the link with **read-only queries** and can find the receiver (brand on a serial port; receivers on the LAN by SSDP). **No HDMI-CEC** (step 1: IOCEC is exclusive to corercd, whose API needs private entitlements). The **TV over the network** (L18: Panasonic VIERA SOAP on port 55000, Wake-on-LAN to turn it on, wired). Volume buttons (Siri Remote through the event tap, L3a, and phone) go **receiver** (set up and answering) → **MMTVL's software volume** (L19: a Core Audio process tap on an output without hardware volume, e.g. HDMI, when no receiver is answering; gated on step 17) → **system** (CoreAudio, when settable) → **in-app** (MMTVL in front). MMTVL no longer uses SoundSource (user decision 2026-11-06). Rationale: HDMI has no macOS volume (D25); the user's Pioneer has RS-232 wired (2026-11-06).
- **D45 — Power button and HDMI hot-plugs** (resolves Q22, takes over M7f step 5): Power short press turns the TV (network, L18) and receiver (RS-232) off and sleeps the displays, or wakes them and turns both on (Wake-on-LAN for the TV); long press opens a **power menu** over any app (Turn Off TV, Sleep Mac mini, Relaunch MMTVL and Restart Mac mini, the last two behind the PIN, D20). After any HDMI hot-plug while Plex HTPC is in the background, MMTVL **restarts Plex on its next open**. Rationale: every black Plex screen followed a hot-plug (M7f §1); a virtual display that avoids it broke HDCP for Prime Video (2026-11-05).

### Local decisions

- **L1 — Seize, with a fallback.** Each remote interface except the digitizer (0x0D, left unopened since the build 24 TV checks, see *Deviations*) is opened with `kIOHIDOptionsTypeSeizeDevice`; if that fails, with `kIOHIDOptionsTypeNone`, logged. Seizing stops macOS's own media handling (no double actions). **Step 1:** Vol+/Vol−/Mute (0xE9/0xEA/0xE2) never reach a seizing client while macOS still handles them (its HUD shows); they reach MMTVL through the event tap instead (L3a). Every other button arrives seized.
- **L2 — Trigger and commands.** `InputBinding.Trigger.siriRemote(button: SiriRemoteButton)`; `SiriRemoteButton`: `tv, back, playPause, volumeUp, volumeDown, mute, power, up, down, left, right, select` (no `siri`: reserved). New `RemoteCommand`s appended at the end (`allCases` order): `volumeUp, volumeDown, mute, power, powerMenu`. Defaults (revision 3): tv → home, back → back, clickpad → up/down/left/right/select, playPause → playPause, volume/mute → volumeUp/volumeDown/mute, power → power. Long press of power (≥ 0.8 s) sends `powerMenu` instead (not a separate trigger). Siri Remote bindings are always global (the remote is the TV's remote).
- **L3 — Routing.** A Siri Remote command goes (in order): learning capture → its binding → `volumeUp/Down/mute` to `VolumeController` and `power/powerMenu` to `PowerController` (from any app) → MMTVL in front: `dispatch(cmd, isGlobal: false)` → Home: `dispatch(.home, isGlobal: true)` → else `ExternalKeyMap.key(for:)` posted with `SyntheticInput` (the phone's `route`, `PhoneRemote.swift:235-246`, factored into one shared `ExternalRouter`).
- **L3a — Volume keys through the event tap** (step 1 result, user decision 2026-11-06). `GlobalEventTap` already taps NX_SYSDEFINED (`Input/GlobalEventTap.swift:79` mask, `.media` case :154-176, acting only while MMTVL is active), and `MediaKeyEvent.parse` (`Input/MediaKeyEvent.swift`) returns nil for volume and mute, so they pass through today. Add a volume path ahead of the media-key one: subtype 8 (`auxControlButtonsSubtype`) with key code 0 (NX_KEYTYPE_SOUND_UP), 1 (SOUND_DOWN) or 7 (MUTE); while a receiver is set up and answering (`VolumeController` would choose `.receiver`), the tap **consumes** them from any app (so macOS's HUD doesn't show) and calls `onVolume` on the main actor: key-down and repeats for up/down, key-down only for mute. Otherwise they pass through untouched (macOS handles them). It doesn't matter where they come from: the Mac keyboard's volume keys do the same. Needs the tap (Accessibility; off in `-windowed`). Log `Volume key up|down|mute → receiver` (info, category `Input`). **Unverified** until TV build 1: that the seized remote's volume reaches the tap as NX_SYSDEFINED (the HUD suggests it goes through the HID event system to WindowServer).
- **L4 — Holds and long presses.** Held clickpad directions repeat (450 ms, then every 120 ms; `ControllerInput`'s values). Normal mode: a long press of centre (≥ 0.6 s) sends `menu` (Apple TV-like context menu: the channel menu in Live TV); a short one `select`. Trackpad mode: short = left click, long (≥ 0.6 s, fires once while held) = right click. Thresholds live in one `SiriRemoteTiming` enum.
- **L5 — Siri double-press.** Two presses within 0.4 s toggle trackpad mode; a single press does nothing. Home (TV) also leaves trackpad mode.
- **L6 — Swipes like Apple TV.** One finger, dominant axis: each 0.22 of travel (normalized) since the last step emits one direction command; on lift, a flick faster than 2.0 units/s adds up to 2 more steps. No swipe steps while a clickpad button is down or for 150 ms after one is released (clicking moves the finger a little). Taps do nothing. All values in `SwipeRecognizer` constants for TV tuning.
- **L7 — Trackpad motion.** Pointer delta = finger delta × 1200 points (x) and × −1200 (y, up is up), then `PointerMath.accelerated` and `clamp`. Scroll: a touch that starts with x ≥ 0.85 scrolls vertically for the whole touch (`dy` × 600 → `PointerMath.scrollWheels`); one that starts with y ≤ 0.12 scrolls horizontally. Clicks use `ClickCounter` (double-clicks). While trackpad mode is on, `cursorAutoHide` doesn't hide the pointer.
- **L8 — Toast.** One non-activating borderless `NSPanel` (`.statusBar` level, `ignoresMouseEvents`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`) shows a glass capsule for 2 s over any app: "Trackpad On", "Trackpad Off", volume ("Volume −20 dB", "Muted"), and receiver errors ("Receiver isn't answering"). The receiver volume toast replaces the HUD macOS no longer shows (L1).
- **L9 — Plain letters can't be global.** Bindings revision 3 removes global bindings whose trigger is a key without modifiers in the letters/digits set (`kVK_ANSI_A…Z`, `0…9`); `adding`/`settingGlobal` keep such a key non-global, and Settings says why ("Letter and number keys only work in MMTVL").
- **L10 — GameController.** ~~If step 1 shows the Siri Remote as a `GCController`, `ControllerInput` skips it.~~ **Dropped** (step 1: GameController doesn't list the Siri Remote).
- **L11 — Receiver protocol layer.** A pure `ReceiverProtocol` per vendor turns `ReceiverCommand` (`powerOn, powerOff, queryPower, volumeUp, volumeDown, queryVolume, mute(Bool), queryMute`) into bytes and parses reply lines into `ReceiverStatus` events (`power(Bool)`, `volume(raw: Int, dB: Double?)`, `muted(Bool)`). Each protocol carries its serial settings, terminator, wake rule and minimum gap. `ReceiverController` owns one transport, a command queue that honors the gap, the power-on double send (Pioneer), and the last known status (also from unsolicited lines).
- **L12 — Test and find with read-only queries** (user request, 2026-11-06). Settings → Receiver & TV → **Test Connection** sends the chosen brand's `queryPower`, `queryVolume`, `queryMute` on the chosen port and shows each reply ("On · −20 dB · Not muted", or "No answer"). **Find Receiver** tries each brand's queries at that brand's serial settings on the chosen port (2 s per brand) and selects the first that answers. Neither ever sends a command that changes anything. The query sets are `ReceiverProtocol.probeQueries`.
- **L17 — Network transport** (user request, 2026-11-06; **untested**: no networked receiver in the house). `ReceiverTCPTransport` (`NWConnection`, TCP, to `receiverHost` on the brand's control port, overridable with `receiverNetworkPort`) carries the same `ReceiverProtocol` bytes; Onkyo/Integra wrap each command in the eISCP header (`ReceiverProtocol.networkFraming`). Reconnect with backoff (1, 2, 5, 10 s), keep-alive on, close after 5 minutes without commands (some receivers allow one client only). **Find on Network**: an SSDP M-SEARCH (`ssdp:all`, 3 s) for UPnP devices whose `manufacturer` is one of the supported brands; each found host is checked with that brand's read-only `probeQueries` on its control port, and the first that answers is selected. The host is entered with MMTVL's on-screen keyboard (D41) or chosen from Find's list. Outgoing LAN connections need the Local Network permission MMTVL already declares (`NSLocalNetworkUsageDescription`). Logs show host and port only.
- **L18 — TV over the network: Panasonic VIERA** (user request, 2026-11-06; verified on the user's TC-P55VT50, step 1). `AVControl/TVController.swift` with a pure `PanasonicViera` codec. **Control:** SOAP over HTTP to port 55000, no pairing on this generation: `POST /nrc/control_0`, `SOAPACTION: "urn:panasonic-com:service:p00NetworkControl:1#X_SendKey"`, body `<u:X_SendKey xmlns:u="urn:panasonic-com:service:p00NetworkControl:1"><X_KeyEvent>NRC_POWER-ONOFF</X_KeyEvent></u:X_SendKey>` in a SOAP envelope (→ 200, TV off). **Read-only status:** `POST /dmr/control_0` RenderingControl `GetVolume` / `GetMute` (`<InstanceID>0</InstanceID><Channel>Master</Channel>`) → `CurrentVolume` 12, `CurrentMute` 0, in ~20 ms. **On/off state:** the TV is on when port 55000 accepts a connection within 1 s (its network is down in standby). **Turning on:** Wake-on-LAN, a UDP magic packet (6 × 0xFF, then the MAC 16 times) to port 9 at the subnet broadcast and the TV's address, every 2 s until 55000 answers (at most 30 s). Needs the TV **wired** (over Wi-Fi WoL never woke it) and the TV's Wake on LAN on; the receiver came on with the TV. **Find TV:** SSDP M-SEARCH, ST `urn:panasonic-com:device:p00RemoteController:1`, 3 s; the `LOCATION` host (`http://<tv>:55000/nrc/ddd.xml`) is the address, `friendlyName` the name ("VIERA VT50"); the MAC is the UDN's last 12 hex digits (`uuid:4D454930-0200-1000-8001-<MAC>`; **unverified** beyond the VT50: if it doesn't look like a MAC, Settings says the TV can't be turned on). The TV answers only with Network Link Settings → TV Remote App on. Shares the SSDP sender with `ReceiverDiscovery` (L17). Settings keys `tvBrand`, `tvHost`, `tvMAC`. Logs show the host only. Newer VIERAs (2019+) need an encrypted pairing; not supported (the brand row says which years, **unverified** boundary).
- **L13 — CEC transport.** ~~`CECBus` wraps `IOCEC.framework`.~~ **Dropped** (step 1: IOCEC is exclusive to corercd, and corercd's API needs private Apple entitlements; display and Mac sleep send no CEC). No CEC code and no HDMI-CEC choice in Settings; the Receiver & TV footer says macOS doesn't let apps use the Mac's HDMI-CEC. The TV is controlled over the network instead (L18). **Reopened as a question (2026-11-06):** step 14b probes CEC through DisplayPort AUX tunneling (DPCD `0x3000`…), below corercd; this decision changes only if its gates pass. **Reopened (2026-11-08, step 14b passed for standby and the broadcast cycle):** step 9 builds a CEC TV control over DPCD, next to corercd: TX only, never the tunnel's control or address mask, only a fixed set of frames.
- **L14 — Power short press** (rewritten in step 2, from step 1's results). **Off:** the TV `NRC_POWER-ONOFF` (L18; only if a TV is set up and answering, since the key toggles), the receiver `powerOff` (if set up; the TV's own CEC usually turns it off too, so a missing reply is not an error), then `pmset displaysleepnow`. **On:** wake the displays, Wake-on-LAN to the TV until it answers (L18, at most 30 s; 18 s on the VT50), the receiver `powerOn` (Pioneer: twice, 100 ms apart). Which one: on when `poweredOffByMMTVL` (memory only) is set or a set-up TV doesn't answer; otherwise off. Never from the receiver's `?P` alone (after a CEC standby from the TV, Pioneer answered `PWR0` while off, step 1). Without a TV set up: receiver and displays only (the TV shows "no signal"). After power-on, log the default output device (`Power` category).
- **L15 — Power menu.** MMTVL comes forward (`Foregrounder`, reason `powerMenu`) and shows a `PowerMenu` (pure model like `LiveMenu`) over the current screen in `LauncherRootView` (a top-level overlay above every screen). Items: Turn Off TV & Receiver, Sleep Mac mini, Relaunch MMTVL (PIN), Restart Mac mini (PIN), Cancel. Back cancels. New `PINPurpose` cases `relaunch` and `restartMac`.
- **L16 — Plex restart after a hot-plug.** `DisplayHotplugMonitor` (CoreGraphics reconfiguration callback) marks every running app in `AppLauncher.restartOnNextOpen` that isn't frontmost at the time of a display remove or add; only bundle ids in `AppLauncher.restartAfterHotplug = ["tv.plex.htpc"]`. The next open of a marked app: remove its pid from `launchedPIDs`, `terminate()`, wait up to 5 s, `forceTerminate()` if needed, then launch as usual. Log `Restarting tv.plex.htpc after a display change` (category `AppLauncher`, notice).

- **L19 — Software volume** (user decision 2026-11-06; gated on step 17).
  - **Engine.** `AVControl/SoftwareVolume*.swift`. One private, `.mutedWhenTapped` Core Audio tap of everything going to the default output's stream 0 except MMTVL (`initExcludingProcesses:andDeviceUID:withStream:`, or `exclusive` + `bundleIDs = ["dev.mmtvl.launcher"]`, whichever step 17 shows works). The tap feeds a private aggregate whose clock and main sub-device is that output (tap drift compensation on, `TapAutoStart`). An IOProc multiplies the tap's buffers by the gain and writes them to the output, same channel count; a stereo tap goes into channels 1–2. The gain is an atomic read by the IOProc and ramped across one buffer when it changes. No allocation, locks or logging in the IOProc.
  - **Level.** Level 0…1 in 16 steps (`SystemVolume.step`). Amplitude = level³ (level 0.5 ≈ −18 dB), so never above 1 (no boost). Mute = gain 0. The level is kept in `softwareVolumeLevel` (default 1.0), saved 2 s after the last press.
  - **When it runs.** All of these: `softwareVolumeEnabled`; the route is software (L19 order, or `phoneRemoteVolume = "software"`); the output's `VirtualMainVolume` isn't settable (forced `software` skips this check); permission preflight says granted; no other pid holds hog mode on the output and its stream isn't non-mixable; and **level < 1 or muted**. At unity the engine is torn down, so there is no added latency and no tap when it isn't needed.
  - **Receiver.** Never while the receiver is ready. It stops within 1 s when the receiver answers, and may start only after the receiver has been unready for 10 s (no rebuild storm while the TV and receiver power up together).
  - **MMTVL's own audio.** MMTVL is excluded from the tap, so mpv gets the same amplitude through `applyAppVolume`. YouTube's page gets it too only if step 17 shows WebKit's audio isn't in the tap (it may come from a separate WebKit process, which would be tapped; **unverified**).
  - **Rebuilds.** On a default-output, device-list, alive, sample-rate, format or hog-mode change: tear down at once (the original audio plays unscaled meanwhile), then rebuild after 2 s with no device change.
  - **Silence watchdog.** If the tap delivers only zeros for 3 s while a process is running output to the output device (`kAudioProcessPropertyIsRunningOutput`), tear down and stay off until the next volume press. Log it, with the toast "Volume control paused". This covers a denied permission and protected audio that taps as zeros.
  - **Quitting.** Destroy the IOProc, the aggregate, then the tap, in `applicationWillTerminate`.
  - **Logs.** Category `Volume`: "Software volume on (<device name>, <channels> ch, <rate> Hz)", "… off: unity | receiver | settable output | no permission | passthrough | device change | silence", the rebuild count. Never audio data.
  - **Toast (L8).** "Volume 50 %" / "Muted" (percent of level). The phone gets `.level(level, muted:)`.
  - **Volume keys (L3a).** The event tap consumes Vol±/Mute when the route is receiver **or software**. Otherwise they pass through to macOS as before.
  - **`keys` is removed** (an old `"keys"` reads as `auto`, `AppSettings.swift:52`), together with all SoundSource code.

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
| `MMTVL/DesignSystem/OverlayToast.swift` (new) | L8 panel + SwiftUI capsule (designer). |
| `MMTVL/AVControl/SerialPort.swift` (new) | POSIX serial (open, settings, write, line reader, close), `SerialPort.available()` (IOKit list of `cu.*`). |
| `MMTVL/AVControl/ReceiverProtocol.swift` (new) + `ReceiverProtocols/Pioneer.swift`, `Onkyo.swift`, `Denon.swift`, `Yamaha.swift`, `Anthem.swift`, `NAD.swift` (new) | L11 pure codecs, serial settings, `probeQueries`. |
| `MMTVL/AVControl/ReceiverController.swift` (new) | L11 queue, status, test/find (L12). |
| `MMTVL/AVControl/ReceiverTCPTransport.swift`, `ReceiverDiscovery.swift` (new) | L17 TCP transport and SSDP discovery. |
| ~~`MMTVL/AVControl/CECBus.swift`~~ | Dropped (L13). |
| `MMTVL/AVControl/TVController.swift`, `TVProtocols/PanasonicViera.swift`, `WakeOnLAN.swift` (new) | L18. |
| `MMTVL/AVControl/PowerController.swift` (new) | L14, display sleep/wake, Mac sleep/restart calls. |
| `MMTVL/Launcher/PowerMenu.swift`, `PowerMenuView.swift` (new) | L15 model and view. |
| `MMTVL/App/DisplayHotplugMonitor.swift` (new) | L16 callback → `AppLauncher`. |
| `MMTVL/App/Volume.swift` | D44: `.receiver` route. |
| `MMTVL/App/AppSettings.swift`, `AppDelegate.swift`, `Launcher/AppRouter.swift`, `Launcher/AppLauncher.swift`, `PIN/PINFlow.swift`, `RemoteServer/PhoneRemote.swift` | Wiring, migration, settings keys, PIN purposes, restart-on-next-open. |
| `MMTVL/Settings/SettingsTypes.swift`, `SettingsModel+Pages.swift`, `SettingsModel.swift`, `SettingsEnvironment.swift` | Remote & Input → Siri Remote and Receiver & TV pages. |
| `scripts/probes/` (new, deleted in step 14) | Step 1's throwaway probes, outside `MMTVL/`. |
| `MMTVL/AVControl/SoftwareVolume.swift` (new) | L19 pure parts (`nonisolated`): gain curve and ramp, the render function (buffers in → gain → buffers out, channel mapping), `SoftwareVolumeRules` (inputs → run/stop + reason, with the debounce clock injected). The main-actor `SoftwareVolume` owns the engine, state, status for Settings, level saving and logs. |
| `MMTVL/AVControl/SoftwareVolumeEngine.swift` (new) | `SoftwareVolumeEngine` protocol. `CoreAudioTapEngine`: tap + private aggregate + IOProc, property listeners → events, hog/format/zero-buffer reporting. Never created in hosted tests (`AppEnvironment.isRunningTests`). |
| `MMTVL/AVControl/AudioCapturePermission.swift` (new) | `dlopen` TCC `TCCAccessPreflight` / `TCCAccessRequest` for `kTCCServiceAudioCapture`; a missing symbol means unknown (engine off; Settings says to allow it). |
| `scripts/probes/audiotap/` (new, deleted in step 16) | Step 17's probe app. |

### New settings keys (`settings.json`, all optional)

- `siriRemoteEnabled` (Bool, default `true`): read the Siri Remote directly (Settings → Remote & Input → Siri Remote).
- `receiverBrand` (String, default `"none"`): `none | pioneer | onkyo | denon | yamaha | anthem | nad`; unknown values read as `none`.
- `receiverConnection` (String, default `"serial"`): `serial | network` (no `cec`, L13; an unknown value reads as `serial`).
- `receiverHost` (String?, default nil): the receiver's address (network connection): a LAN IP, a `.local` name, or a DNS name; a name that resolves outside the LAN is refused when the connection opens (step 8b).
- `receiverNetworkPort` (Int?, default nil): overrides the brand's control port (L17).
- `receiverMaxDB` (Double, default `0`): the loudest MMTVL's volume buttons set the receiver (step 10, user decision 2026-11-06; Settings → Audio & TV → Receiver → Maximum Volume, steps 11 and 13c).
- `receiverSerialPort` (String?, default nil): a `/dev/cu.*` path; nil = the first USB serial port found.
- ~~`tvPowerControl`~~ (dropped with CEC, L13). `tvBrand` (String, default `"none"`): `none | panasonic | cec` (L18; `cec` from step 9, 2026-11-08; unknown → `none`). `tvHost` (String?, default nil): the TV's address. `tvMAC` (String?, default nil): its wired MAC for Wake-on-LAN (from Find TV). Never committed or logged.
- `softwareVolumeEnabled` (Bool, default `true`): allow L19's software volume (Settings → Audio & TV → Software Volume, in its Volume section; step 13c).
- `softwareVolumeLevel` (Double, default `1.0`, clamped 0…1): the software level, saved by MMTVL. Hand edits only with MMTVL quit.
- `phoneRemoteVolume`: `auto | receiver | software | system | app`. `keys` is gone and reads as `auto`. `auto` = receiver → software → system → app.
- `tvVolumeEnabled` (Bool, default `false`; step 9c): with no receiver ready, the volume buttons change the TV's own volume (HDMI-CEC or VIERA network). `receiverConnection` gains `cec` (step 9c).
- `volumeToast` (Bool, default `true`; step 13b, user request 2026-11-08): show the volume toast for the Siri Remote's and the keyboard's volume presses (Settings → Audio & TV → Show Volume, step 13c; first built on the Receiver & TV page in 13b). Off hides the level and Muted toasts; the "can't change" and "isn't answering" error toasts still show.

### Settings pages (M7g layout, D42)

- *(Step 13c, 2026-11-08: Receiver & TV moved to a root category **Audio & TV**, with Receiver and TV pages and Show Volume. The two bullets below describe step 11 as built.)*
- **Remote & Input** gets two rows after Game Controllers: **Siri Remote** (push; value "Connected · 78 %" / "Not Connected" / "Off") and **Receiver & TV** (push; value the brand or "Not Set Up").
- **Siri Remote** page: Use Siri Remote (toggle `siriRemoteEnabled`; description: "Read the Siri Remote directly. Double-press Siri for trackpad mode."), Status (info: connected, battery, touch available or not), a "How it works" footer (TV = Home, swipes, double-press Siri = trackpad, long press centre = menu / right click, long press Power = power menu).
- **Receiver & TV** page: Brand (push → list: None, Pioneer (before 2016), Onkyo / Integra / Pioneer (2016 and later), Denon / Marantz (2010 and later), Yamaha (2010–2020), Anthem, NAD; the footer: "Tested with Pioneer. Serial cables: Pioneer needs a null-modem cable, Denon, Marantz and Onkyo a straight one."), Connection (push → Serial / Network), Serial Port (push → list of `cu.*` ports plus "Automatic"; only with Serial), Address (only with Network: the host, edited with the on-screen keyboard, D41), **Test Connection** (action; detail shows the replies), **Find Receiver** (action; Serial: tries each brand on the port; Network: SSDP, then a push list of the receivers that answered), Status (info: "On · −20 dB · Not muted" from the last status). A **TV** section: TV (push → None, Panasonic VIERA (2012–2018, network); L18), Address (the host, on-screen keyboard, or from Find TV), **Find TV** (SSDP, L18; fills Address and the MAC), **Test TV** (read-only: on or off, volume, mute), and a footer: "Turn on TV Remote App and Wake on LAN in the TV's Network settings. The TV must be on Ethernet to turn on from MMTVL. macOS doesn't let apps use the Mac's HDMI-CEC."

## Implementation steps

- [x] **1. Probes on the mini** `[implementer]` then `[human]`: files: `scripts/probes/hid-seize.swift`, `scripts/probes/cec.swift`, `scripts/probes/gc.swift` (new)
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

- [x] **2. Apply the probe results** `[doc]`: files: this plan
  - CEC gate failed → mark step 9 "skipped (CEC not available)", and make steps 10–11 show CEC as unavailable. Power gate → add the loginwindow setting to the TV steps and CLAUDE.md. Siri Remote seen by GameController → keep L10, else drop it from step 4. Adjust timings (L4–L7) only if the probe showed reasons.
  - Done when: the plan has no open gate.

- [x] **3. Triggers, commands and bindings revision 3** `[implementer]`: files: `Input/SiriRemote/SiriRemoteButton.swift` (new), `Input/InputBinding.swift`, `Input/RemoteCommand.swift`, `Input/KeyBindings.swift`, `Input/KeyBindings+Editing.swift`, `Input/TriggerName.swift`, `Input/ExternalKeyMap.swift`, `App/AppDelegate.swift` (`migrateBindings`), `MMTVLTests/KeyBindingsTests.swift`, `MMTVLTests/KeyBindingsEditingTests.swift`, `MMTVLTests/TriggerNameTests.swift`, `MMTVLTests/SiriRemoteButtonTests.swift` (new)
  - L2: `SiriRemoteButton` (String raw values as in L2) with `static func from(usagePage: UInt32, usage: UInt32) -> SiriRemoteButton?` per the probe table, and `static func isSiri(usagePage:usage:) -> Bool` (0x0C/0x04). `Trigger.siriRemote(button:)` (JSON `{"siriRemote":{"button":"tv"}}`), `KeyBindings.binding(siriRemote:)`. `RemoteCommand` appends `volumeUp, volumeDown, mute, power, powerMenu` with titles "Volume Up", "Volume Down", "Mute", "Power", "Power Menu". `ExternalKeyMap`: the new commands → nil (handled before it, L3).
  - Defaults: the L2 Siri Remote bindings (`isGlobal: true`, labels "Siri Remote TV", …); `currentRevision = 3`. Migration: revision < 3 → add the Siri Remote defaults (`addingDefaults` for their commands, Siri Remote triggers only) and remove L9's plain-letter/digit global bindings (log each removed one: `Removed global binding <name>`, category `Input`).
  - L9 guard in `adding` and `settingGlobal`; `canSetGlobal(_ trigger:) -> Bool`.
  - Names: `TriggerName.describe(.siriRemote(.tv))` = "Siri Remote TV" etc.; kind "Siri Remote".
  - Tests: Siri Remote trigger JSON round-trips; every probe usage maps to its button and unknown usages to nil; revision-2 bindings with `{"key":{"keyCode":0,"modifiers":[]}}` global Home migrate to revision 3 without it and with the Siri Remote defaults; `adding(.key(kVK_ANSI_A, []), to: .home)` stays non-global; `canSetGlobal` false for letters/digits, true for F-keys and Home; names.
  - Done when: `xcodebuild … test` passes with the new tests listed in the output.

- [x] **4. Siri Remote buttons** `[implementer]` `[security]`: files: `Input/SiriRemote/SiriRemoteHID.swift`, `SiriRemoteGestures.swift`, `SiriRemoteInput.swift` (new), `Input/ExternalRouter.swift` (new), `RemoteServer/PhoneRemote.swift`, `Input/InputRouter.swift` (capture of `.siriRemote`), `App/AppSettings.swift` (`siriRemoteEnabled`), `App/AppDelegate.swift`, `MMTVLTests/SiriRemoteGesturesTests.swift` (new), `MMTVLTests/PhoneRemoteTests.swift`, `MMTVLTests/AppSettingsTests.swift`
  - `SiriRemoteHID`: `IOHIDManagerCreate`, matching `[{VendorID: 76, ProductID: p} for p in RemoteBattery.productIDs]`, device matching callback opens each device seized (L1) and logs `Siri Remote interface 0x0C/0x01 open: seized` (category `SiriRemote`, notice), removal callback synthesizes releases for held buttons, value callback → `onButton(SiriRemoteButton?, isSiri: Bool, pressed: Bool)`. Starts/stops with `siriRemoteEnabled`; restarts after wake.
  - Volume buttons don't arrive seized (step 1); keep their mapping (an unseized fallback still gets them) and leave volume to L3a (step 10).
  - `SiriRemoteGestures` per L4/L5 with injected `now` and a scheduled-tick API (no timers inside; `SiriRemoteInput` drives a 30 ms task while something is held).
  - `ExternalRouter.route(_ command:)` = L3's last three rungs; `PhoneRemote.route` uses it (behavior unchanged; existing `PhoneRemoteTests` stay green).
  - `SiriRemoteInput`: capture (`InputRouter.capture(.siriRemote(button))` while learning, Siri never captured), binding lookup, then L3; volume/power commands call closures (`onVolume`, `onPower`) that steps 10/12 fill (until then they log).
  - Tests (`SiriRemoteGesturesTests`): short centre → select; centre held 0.6 s → menu once, no select; held up → up, then repeats at 450 ms and every 120 ms with `isRepeat`; Siri, Siri within 0.4 s → toggleTrackpad; single Siri → nothing; power held 0.8 s → powerMenu, short → power; trackpad mode: short centre → click(left), long → click(right) once; removal mid-press → release, no long-press event.
  - Done when: tests pass; in `-windowed YES` on the dev Mac (no remote) the app logs `Siri Remote: no remote connected` and nothing else changes; `[security]` review of the HID seize and synthetic routing passes.

- [x] **5. Touch: swipes and trackpad mapping** `[implementer]`: files: `Input/SiriRemote/MultitouchDevices.swift`, `SwipeRecognizer.swift`, `TrackpadMapper.swift` (new), `Input/SiriRemote/SiriRemoteInput.swift`, `MMTVLTests/SwipeRecognizerTests.swift`, `MMTVLTests/TrackpadMapperTests.swift` (new)
  - `MultitouchDevices`: `dlopen` + `dlsym` (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTUnregisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceIsBuiltIn`, `MTDeviceGetFamilyID`); missing symbols → `isAvailable = false`, log once. Only devices with `MTDeviceIsBuiltIn == false`. The C callback copies `count`, and for the first finger `state` (offset 20), x, y (32, 36) into a `TouchFrame` and hops to the main actor. Matching notifications on `AppleMultitouchDevice` rebuild the list; stop on `willSleep`, restart on `didWake`.
  - `SwipeRecognizer` (L6) and `TrackpadMapper` (L7), pure.
  - `SiriRemoteInput`: normal mode feeds `SwipeRecognizer` (steps → commands through L3, `isRepeat: false`), suppressed around clicks; trackpad mode feeds `TrackpadMapper` → `PhonePointer.perform`.
  - Tests: a 0.5 slide right → 2 rights; a slow 0.2 slide → none; a fast flick → extra steps capped at 2; a slide during a click → none; vertical dominant axis; trackpad: deltas scale and invert y; a touch starting at x 0.9 scrolls vertically only; at y 0.1 horizontally; lift resets.
  - Done when: tests pass and the build succeeds; on the dev Mac (a MacBook trackpad, if any) the built-in trackpad is ignored (log `Multitouch: 0 remote surfaces`).

- [x] **6. Toast overlay** `[designer]`: files: `DesignSystem/OverlayToast.swift` (new), `App/AppDelegate.swift`
  - L8: a glass capsule (`.glassPanel(in: Capsule())`, Theme type tokens; an SF Symbol: `cursorarrow.motionlines` for trackpad, `speaker.wave.2.fill` / `speaker.slash.fill` for volume, `exclamationmark.triangle` for errors), top-centre of the main screen, 2 s, fades; a new message replaces the old one. Reduce Transparency → solid. API: `OverlayToast.shared.show(_ text: String, symbol: String)`.
  - Done when: in `-windowed YES`, a debug trigger (Settings → Siri Remote → Status row Select in Debug builds) shows "Trackpad On" over another app (e.g. Finder in front), clicks pass through it, and a screenshot is attached to the step's hand-back.

- [x] **7. Trackpad mode** `[implementer]` `[security]`: files: `Input/SiriRemote/SiriRemoteInput.swift`, `App/AppDelegate.swift` (cursor auto-hide), `MMTVLTests/SiriRemoteGesturesTests.swift`
  - Mode toggle (L5) with the toast; clicks through `PhonePointer` (`ClickCounter`), right click per L4; Back stays L3's Back; Home leaves trackpad mode; cursor auto-hide off while on. Log `Trackpad mode on/off` (category `SiriRemote`).
  - Done when: tests for the mode switch pass, the build succeeds, `[security]` review passes.

- [x] **8. Receiver protocols and serial** `[implementer]`: files: `AVControl/SerialPort.swift`, `ReceiverProtocol.swift`, `ReceiverProtocols/Pioneer.swift`, `Onkyo.swift`, `Denon.swift`, `Yamaha.swift`, `ReceiverController.swift` (new), `App/AppSettings.swift` (`receiverBrand`, `receiverConnection`, `receiverSerialPort`), `MMTVLTests/ReceiverProtocolTests.swift`, `MMTVLTests/ReceiverControllerTests.swift` (new)
  - L11 per *Receiver protocols*. `ReceiverProtocol` (protocol, `nonisolated`): `serial: SerialSettings` (baud, data bits, parity, stop bits), `terminator: [UInt8]`, `minimumGap: Duration`, `wakeRule` (Pioneer: send `powerOn` twice 100 ms apart; others per table), `encode(_ ReceiverCommand) -> [UInt8]`, `parse(line: String) -> ReceiverStatus?`, `probeQueries: [ReceiverCommand]` (the query commands only, L12).
  - `SerialPort`: termios setup per `SerialSettings` (Research), line splitting on the protocol's terminator, `close()` on deinit; `available() -> [SerialPortInfo]` (path, USB product name).
  - `ReceiverController`: transport protocol `ReceiverTransport` (send bytes, receive lines) so tests use a fake; queue with `minimumGap`; status from replies and unsolicited lines; `test() async -> ReceiverTestResult` and `find(on port:) async -> ReceiverBrand?` (L12, read-only queries only, 2 s per brand); reconnects when the port disappears (log `Receiver port gone`, category `Receiver`).
  - Tests: per vendor, every command encodes to the table's bytes; replies parse (Pioneer `PWR0`, `VOL61` → −20 dB, `VOL161` → 0 dB, `MUT1`; Onkyo `!1MVL28\u{1A}` → 40; Denon `MV805` → +0.5 dB and `MV80` → 0 dB, `MVMAX 98` ignored; Yamaha `@MAIN:VOL=-35.5`; Anthem `Z1VOL-35`; NAD `Main.Volume=-30`); `probeQueries` contain only queries; the Pioneer power-on sends twice ≥ 100 ms apart (fake clock); `find` stops at the first brand that answers and never encodes a non-query; the gap is honored.
  - Done when: tests pass, and at launch no serial port is opened while `receiverBrand` is `none` (log `Receiver: not set up`, category `Receiver`).

- [x] **8b. Network transport and discovery** `[implementer]` `[security]`: files: `AVControl/ReceiverTCPTransport.swift`, `AVControl/ReceiverDiscovery.swift` (new), `AVControl/ReceiverProtocol.swift` (`networkPort`, `networkFraming`), `AVControl/ReceiverProtocols/Onkyo.swift` (eISCP header), `AVControl/ReceiverController.swift`, `App/AppSettings.swift` (`receiverHost`, `receiverNetworkPort`), `MMTVLTests/ReceiverProtocolTests.swift`, `MMTVLTests/ReceiverDiscoveryTests.swift` (new)
  - L17. The SSDP search can reuse the parsing in `Cast/` only if it fits as-is (`SSDPResponder` answers searches; this sends one): keep a small sender in `ReceiverDiscovery`, `SO_REUSEPORT` like `SSDPResponder`, and fetch each `LOCATION` description (http, LAN only, 2 s timeout, 64 KB cap) to read `manufacturer`/`modelName`.
  - Tests: eISCP framing of `!1PWR01` (header `ISCP`, header size 16, data size, version 1) and unframing of a reply; the brand's default port; an SSDP response and a device description parse to (brand, model, host); a description larger than the cap is rejected; non-LAN `LOCATION` hosts are ignored.
  - Done when: tests pass; `[security]` review passes (outgoing LAN connections only, no description fetch beyond the cap, hosts only in logs). **Not testable on hardware here** (record "untested on a real networked receiver" in *Deviations*).

- [x] ~~**9. HDMI-CEC transport**~~ **Skipped (CEC not available, step 1; L13).** Step 14b probes a lower route (DP-AUX CEC tunneling, as BetterDisplay does); if it works, this step comes back as a DP-AUX transport.
- [x] **9 (reopened). DP-AUX CEC TV control** `[implementer]` `[security]` (user decision 2026-11-08, after step 14b's probe 2): files: `AVControl/CEC/CECFrame.swift`, `AVControl/CEC/CECTunnel.swift`, `AVControl/CEC/EDIDPhysicalAddress.swift`, `AVControl/TVProtocols/HDMICEC.swift` (new), `AVControl/TVController.swift` (`TVBrand.cec`), `AVControl/PowerController.swift`, `App/AppSettings.swift` (`tvBrand`), `App/AppDelegate.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `MMTVLTests/CECFrameTests.swift`, `MMTVLTests/CECTunnelTests.swift`, `MMTVLTests/EDIDPhysicalAddressTests.swift` (new), `MMTVLTests/PowerControllerTests.swift`, `MMTVLTests/SettingsReceiverTests.swift`, `MMTVLTests/AppSettingsTests.swift`
  - **What step 14b established** (Deviations, "step 14b results", probes 1 and 2; `scripts/probes/dpcd-cec.swift` has working code for every call):
    - The mini's HDMI is Apple's DP-to-HDMI converter (`pHDMIg`), and it tunnels CEC (DPCD `0x3000` = 0x07). DCP and corercd already have tunneling on, with logical address 4 and broadcast (`0x3001` = 0x01, mask 0x8010).
    - A normal process can open `DCPDPDeviceProxy` and read and write DPCD, with no entitlement or prompt:
      - `IODPDeviceCreateWithService(alloc, service)` (needs `IODPDeviceUserInterfaceSupported`, location 0 = External);
      - `IODPDeviceReadDPCD(dev, addr, buf, len)`, selector 0;
      - `IODPDeviceWriteDPCD(dev, addr, buf, len)`, selector 1;
      - all through `dlsym` from IOKit.
    - Sending: wait while `0x3003` bit 7 is set (corercd's send); write the frame to `0x3020…`; write `0x3003` = (len − 1) | (3 << 4) | 0x80; sent when bit 7 clears (~65 ms).
    - Replies: poll `0x3002`/`0x3010…` every 10 ms. The TV's `04:90:00` was read this way. Never write `0x3004`; DCP clears the flags.
    - corercd treats our traffic as ordinary bus traffic; nothing broke over ~12 sends, and HDCP and the TV-off-turns-receiver-off link stayed intact.
    - The physical address comes from the EDID (`IOPortTransportStateDisplayPort` → `"EDID"`, HDMI VSDB): 2.3.0.0 on the mini.
  - **Frames (the only ones the transport can send; initiator 4, which must be in the mask):**
    - **Off:** `4F:36` (Standby to all). It turns off the TV and a CEC receiver; a TV-only `40:36` left the receiver on, and a receiver left on re-routes away from the Mac when CEC wakes the TV.
    - **On:** `40:04` (Image View On), then about 300 ms later `4F:82:<PA>` (Active Source).
    - **Status:** `40:8F` → `04:90:<s>`: 0 on, 1 standby, 2 standby → on (counts as on), 3 on → standby (counts as off). No reply in 1 s means unknown.
  - **`CECTunnel`** (`nonisolated`, its own serial queue):
    - Finds the External `DCPDPDeviceProxy`, and is "available" only when `0x3000` bit 0 and `0x3001` bit 0 are set and the mask holds address 4.
    - Its write path has a **hard allow-list in code**: `0x3020…0x302F` and `0x3003` with bit 7, nothing else (no `0x3001`, `0x300E`/`F` or `0x3004`, ever). Any other address is a programming error: refused and logged at fault level.
    - Busy wait at most 500 ms. Recreates the device after an HDMI hot-plug (the proxies vanish while HPD is low; `DisplayHotplugMonitor` events).
    - Never sends from another logical address, never enables tunneling, never changes the mask.
    - The symbols are looked up with `dlsym`; a missing one means "not available".
  - **`EDIDPhysicalAddress`:** a pure parser (CEA-861 extension, data block tag 3, OUI 00-0C-03, bytes 4–5) plus a lookup of the `"EDID"` property. With no EDID or no VSDB there is no Active Source: "on" sends Image View On only, and that is logged.
  - **`HDMICEC` (a `PowerTV`, `AVControl/PowerController.swift:15-25`):**
    - `isConfigured` = brand `cec`.
    - `isOn` = the status query (unknown → as today's "doesn't answer").
    - `powerOff` = `4F:36`; `powerOn` = wake displays already done by `PowerController`, then wait up to 5 s for the tunnel, then On.
    - `canTurnOn` = tunnel available.
  - **`PowerController`:** with a CEC TV, "off" sends `4F:36` before the receiver's own `powerOff` (keep that too; a missing reply isn't an error) and before `pmset displaysleepnow`. "On" wakes the displays first, as today.
    - **Unverified:** that the tunnel survives `pmset displaysleepnow`. The probe never slept the displays. If it doesn't, "on" waits for it after the wake.
    - After a CEC "on", if the Mac's HDMI display hasn't returned within 20 s, log it and toast "Switch the receiver to the Mac's input". This is the re-route case from probe 2; if a serial receiver is set up, don't switch its input automatically yet (not planned; the user decides later).
  - **Settings → Audio & TV → TV:**
    - The Brand list gains **HDMI-CEC** ("Any TV, through the Mac's HDMI. Also turns a CEC receiver off and on.").
    - With CEC there are no Address, Find TV or MAC rows.
    - **Test TV** sends the status query and shows "On", "Standby" or "No answer".
    - A **Status** row: "Ready", "HDMI-CEC not available on this display", or "No HDMI display".
    - Footer: "MMTVL shares the Mac's HDMI-CEC with macOS. Turning off also turns off receivers that follow HDMI-CEC."
  - **Logs** (category `CEC`, notice): every frame sent and its result, replies to our status query, tunnel availability changes. CEC frames carry no secrets, so log them in hex. The EDID isn't logged, only the physical address.
  - **Tests:**
    - frame building and the allow-list (every other address refused);
    - busy wait, sent and timeout, with a fake DPCD;
    - status parsing for 0–3, other values and no reply;
    - EDID parsing: a synthetic EDID with the VSDB gives 2.3.0.0; no extension, no VSDB, or a truncated block give nil;
    - `PowerController` with a fake CEC TV: off sends `4F:36` before display sleep, on waits for the tunnel, and the 20 s no-display toast;
    - Settings rows for `cec`, and Test TV's three answers;
    - `tvBrand: "cec"` decodes, and unknown values read as `none`.
  - **Security review:** a hardware write path through private IOKit; the allow-list; no new listener; nothing from the phone (its `power` is already dropped); frames logged without secrets; behaviour when another process (BetterDisplay) also writes the tunnel.
  - Done when: tests pass (quote the full suite's result line). QA on the dev Mac (macOS 27.2, the same `pHDMIg` converter, the Odyssey G70NC with no address claimed in the mask):
    - the tunnel reports "HDMI-CEC not available" (mask without address 4) and sends nothing;
    - a fake-DPCD test covers sending.
  - **TV check (build 25, user at the TV):** TV Brand HDMI-CEC; Test TV shows On; Power off turns the TV and receiver off; Power on brings both back with MMTVL and sound; `CEC` lines in the log; Prime Video plays afterwards with VNC closed.

- [x] **9b. TV over the network (Panasonic VIERA)** `[implementer]` `[security]` (added in step 2): files: `AVControl/TVController.swift`, `AVControl/TVProtocols/PanasonicViera.swift`, `AVControl/WakeOnLAN.swift` (new), `AVControl/ReceiverDiscovery.swift` (the SSDP sender, shared), `App/AppSettings.swift` (`tvBrand`, `tvHost`, `tvMAC`), `MMTVLTests/PanasonicVieraTests.swift`, `MMTVLTests/WakeOnLANTests.swift`, `MMTVLTests/TVControllerTests.swift` (new), `MMTVLTests/AppSettingsTests.swift`
  - L18. `PanasonicViera` (pure): the SOAP request (path, headers, body) for `X_SendKey` with a key from a fixed `VieraKey` enum (`NRC_POWER-ONOFF` only for now; never a string from input) and for `GetVolume`/`GetMute`; parsing of their responses (and SOAP faults). `WakeOnLAN` (pure packet builder + a sender): `packet(mac:) -> [UInt8]` (102 bytes), MAC parsing (`02:00:5e:…`, `02-00-5E-…`, `02005e…`). `TVController`: `isOn() async -> Bool` (TCP connect to 55000, 1 s), `powerOff()` (only when on), `powerOn() async -> Bool` (WoL every 2 s until `isOn`, at most 30 s), `test() async -> TVTestResult` (on/off, volume, mute; read-only), `find() async -> [FoundTV]` (SSDP per L18, description fetch LAN-only, 2 s timeout, 64 KB cap, name and UDN → MAC). URLSession with an ephemeral configuration, LAN hosts only (private ranges or `.local`).
  - Tests: the X_SendKey and GetVolume requests match step 1's working bytes; responses parse (`CurrentVolume` 12, `CurrentMute` 0; a fault → error); the WoL packet for a made-up MAC (`02005e0010ab`, never the TV's real one in the repo) is 6 × FF + 16 × the MAC; MAC parsing and rejection; UDN `uuid:4D454930-0200-1000-8001-02005E0010AB` → that MAC, a UDN without one → nil; `powerOn` with a fake clock and transport stops when `isOn` and gives up at 30 s; `powerOff` doesn't send when the TV is off; an SSDP response + description parse to (host, name, MAC); a non-LAN `LOCATION` is ignored.
  - Done when: tests pass; `[security]` review passes (outgoing LAN only, fixed SOAP bodies, capped description fetch, host only in logs). Hardware check in step 15.

- [x] **9c. Volume and the receiver over HDMI-CEC; TV volume** `[implementer]` `[security]` (user request 2026-11-08: "we need to account for these scenarios not just this particular one with my avr/tv combo"; after step 9): files: `AVControl/CEC/CECFrame.swift`, `AVControl/CEC/CECTunnel.swift` (allow-list), `AVControl/CEC/CECAudioSystem.swift` (new), `AVControl/TVProtocols/HDMICEC.swift`, `AVControl/TVProtocols/PanasonicViera.swift` (`SetVolume`, `SetMute`), `AVControl/TVController.swift`, `AVControl/ReceiverProtocol.swift` (`ReceiverConnection.cec`), `AVControl/PowerController.swift`, `App/Volume.swift`, `App/AppSettings.swift` (`receiverConnection`, `tvVolumeEnabled`), `App/AppDelegate.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `MMTVLTests/VolumeTests.swift`, `MMTVLTests/CECFrameTests.swift`, `MMTVLTests/CECAudioSystemTests.swift` (new), `MMTVLTests/PanasonicVieraTests.swift`, `MMTVLTests/PowerControllerTests.swift`, `MMTVLTests/SettingsReceiverTests.swift`, `MMTVLTests/AppSettingsTests.swift`
  - **User decisions (2026-11-08):**
    - A CEC receiver is **Connection: HDMI-CEC** on Audio & TV → Receiver, next to Serial and Network.
    - The toast **asks for the level, then falls back**.
    - **TV volume is an opt-in toggle** that covers a CEC TV **and** a network VIERA.
  - **What the probes showed** (Deviations, step 14b results, "Volume over CEC"):
    - To the audio system (address 5): `45:44:41` / `42` / `43` (Volume Up / Volume Down / Mute), each followed by `45:45`, step the Pioneer one notch or toggle mute.
    - `45:71` (Give Audio Status) gets no answer from the Pioneer. Other brands send `5F:7A` / `54:7A` (bit 7 mute, bits 0–6 volume 0–100, 0x7F unknown).
    - `45:8F` → `54:90:<s>` (power status) and `45:46` → `54:47:<name>` (OSD name, "VSX-01TXH") work, so they're the detection and naming queries.
    - The TV (address 0) answers `40:71` and `40:46` with Feature Abort. Its reaction to volume couldn't be seen (its speakers are off).
  - **Today (read 2026-11-08):**
    - `VolumeRoute.choose(mode:receiverReady:soundSourceRunning:systemSettable:launcherActive:)` (`App/Volume.swift:15`); `VolumeController.perform` (`:334`), `performOnReceiver` (`:428`).
    - Step 10's queue: at most one waiting Vol± (latest wins) and one waiting Mute; readiness probes at most every 10 s.
    - `GlobalEventTap`'s `VolumeKeyTracker` (`Input/GlobalEventTap.swift:66`): a held key's repeats follow its key-down.
    - The Siri Remote's volume buttons call `onVolume(.up/.down/.mute)` (`Input/SiriRemote/SiriRemoteInput.swift:229-231`).
    - `ReceiverConnection` is `serial | network` (`AVControl/ReceiverProtocol.swift:25`).
    - `PanasonicViera` has `GetVolume` and `GetMute` on RenderingControl (`AVControl/TVProtocols/PanasonicViera.swift:55-65`) but no setters.
  - **CEC transport (step 9's `CECTunnel`):**
    - One serial queue for every frame (power, volume, queries).
    - Replies are matched by initiator and opcode, with a 1 s timeout.
    - The allow-list becomes a table of (destination, opcode, operands):
      - step 9's `4F:36`, `40:04`, `4F:82:<PA>`, `40:8F`;
      - plus `45:44:41/42/43/6D`, `45:45`, `45:36`, `45:71`, `45:8F`, `45:46`;
      - plus `40:44:41/42/43`, `40:45`.
    - Nothing else can be sent.
  - **`CECAudioSystem`** (the receiver with Connection HDMI-CEC):
    - `isAnswering` = power status "on" (0 or 2) answered since configure. It's probed at launch, when the tunnel comes up and after a fallback press, at most every 10 s, as in step 10. Standby (1 or 3) or no answer means not ready.
    - Each Vol± is Pressed + Released, run through step 10's queue rules (at most one waiting step, latest wins; Mute never dropped). Then `45:71`, with a 300 ms wait for `7A`.
    - After 3 presses without a `7A`, it stops asking until the next configure (the Pioneer case).
    - `powerOff` = `45:36`. `powerOn` = `45:44:6D` + `45:45` (Power On Function; **unverified on the Pioneer**, which followed the TV on in probe 2).
    - Test = `45:8F` + `45:46` → "On · VSX-01TXH", "Standby · …", "No answer".
    - Find Receiver tries the serial brands first, then HDMI-CEC (a `45:8F` answer). A serial match wins, because it gives dB and the volume cap.
  - **TV volume (`tvVolumeEnabled`, Bool, default `false`):**
    - With it on and **no receiver set up** (amended 2026-11-08 in review, was "no receiver ready"; the receiver's Maximum Volume can't be bypassed through the TV), Vol± and Mute go to the TV.
    - **CEC TV:** `40:44:4x` + `40:45`. The level is unknown (TVs Feature Abort `71`), so the toast falls back.
    - **VIERA (network):** read `GetVolume`/`GetMute`, then `SetVolume` (±1, clamped 0…100) / `SetMute` (toggle) on RenderingControl, with the real level in the toast ("Volume 13 %").
    - Ready = the TV answered (VIERA's 1 s check; CEC power status on).
    - **Unverified:** `SetVolume`/`SetMute` on the VT50, and any TV acting on CEC volume. The user's TV plays through the receiver only; testing needs its speakers on.
  - **Routing (amends D25/D44; step 18 inserts software volume after `tv`):**
    - `auto` = receiver (serial/network ready) → **receiver over HDMI-CEC** (ready) → **tv** (`tvVolumeEnabled`, ready) → SoundSource keys (until step 18) → system → app.
    - `phoneRemoteVolume` gains `tv`; `receiver` covers every connection.
    - The event tap consumes the volume keys for every route except system/keys, as today.
  - **Toasts and feedback:**
    - With a level: "Volume 45 %", "Muted".
    - Without one: "Volume Up", "Volume Down", "Mute".
    - The phone gets the level when known, else unknown.
    - Maximum Volume doesn't apply over HDMI-CEC; the row says "HDMI-CEC receivers can't be limited", like Onkyo.
  - **Power (L14):**
    - With a CEC receiver and a non-CEC TV: "off" also sends `45:36`; "on" sends `45:44:6D` + `45:45` after the TV is on.
    - With a CEC TV, step 9's `4F:36` already covers the receiver.
  - **Settings:**
    - **Receiver:**
      - Connection becomes Serial / Network / HDMI-CEC (a push list if three values don't fit the toggle row).
      - With HDMI-CEC: Brand, Serial Port, Address and Maximum Volume are hidden (Maximum Volume becomes an info line); Test and Status show the name.
      - Audio & TV's Receiver value shows "HDMI-CEC" or the OSD name.
    - **TV:**
      - **Volume Buttons Change TV Volume** (toggle), for brands Panasonic and HDMI-CEC.
      - Description: "When no receiver is set up, the volume buttons change the TV's own volume. For TVs that play through their own speakers. Some TVs ignore HDMI-CEC volume."
  - **Tests:**
    - every new frame and the allow-list refusing anything else;
    - `7A` parsing (mute bit, 0x7F unknown);
    - `CECAudioSystem` with a fake tunnel: ready/standby/no answer, press = Pressed + Released, the queue, level asked then given up after 3, Test text, power;
    - `choose` with the new routes in every mode;
    - VIERA `SetVolume`/`SetMute` envelopes and clamping;
    - TV-volume toggle off, on, and on with a ready receiver (the receiver wins);
    - Settings rows for HDMI-CEC and the toggle;
    - `receiverConnection: "cec"` and `tvVolumeEnabled` decoding (unknown → defaults, no `.bak`).
  - **Security review:** the grown allow-list; the phone's volume now reaching CEC devices (paired phones only, as with the receiver); no frames from a phone other than volume.
  - Done when: tests pass (quote the full suite's result line). QA on the dev Mac: the tunnel isn't available there, so routing falls through with `CEC` log lines saying why, and nothing is sent.
  - **TV checks (build 25):**
    - Receiver Connection HDMI-CEC: Test "On · VSX-01TXH"; Vol±/Mute with the "Volume Up/Down"/"Mute" toasts.
    - Back to Serial: dB toasts again.
    - Optional, with the TV's speakers turned on for a minute: TV volume (VIERA network, then HDMI-CEC).

- [x] **10. Volume to the receiver** `[implementer]`: files: `App/Volume.swift`, `App/AppDelegate.swift`, `Input/SiriRemote/SiriRemoteInput.swift`, `MMTVLTests/VolumeTests.swift`
  - L3a (step 2): the event tap's volume path (`MediaKeyEvent` learns key codes 0, 1, 7 for this path only; `GlobalEventTap.decide` consumes them from any app while the receiver route is ready, else passes them through), with tests for the parsing and for the decision (ready → consumed and `onVolume` called; not ready or `-windowed` → passed through). Files also: `Input/GlobalEventTap.swift`, `Input/MediaKeyEvent.swift`, `MMTVLTests/MediaKeyEventTests.swift`.
  - D44: `VolumeMode` gains `receiver`; `VolumeRoute` gains `.receiver`; `choose` takes `receiverReady: Bool` first in `auto`. `VolumeController.perform` sends `volumeUp/Down` or `mute(!muted)` through `ReceiverController` and returns `.level` from the reported dB when known. The Siri Remote's `onVolume` and the phone both use it. Toast (L8) on Siri Remote volume: "Volume −20 dB" / "Muted" / "Volume" (no level known).
  - Tests: `choose` order for each mode with and without a ready receiver; feedback mapping.
  - Done when: tests pass.

- [x] **11. Settings pages** `[implementer]`: files: `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsEnvironment.swift`, `App/AppDelegate.swift`, `App/AppSettings.swift` (`tvPowerControl`), `MMTVLTests/SettingsSiriRemoteTests.swift`, `MMTVLTests/SettingsReceiverTests.swift` (new), `MMTVLTests/SettingsTestSupport.swift`, `MMTVLTests/AppSettingsTests.swift`
  - Also from step 3 (see *Deviations*, 2026-11-06 step 3): L9's text on a plain letter/digit binding, Work in Other Apps hidden for Siri Remote bindings, and the Remote Buttons rows for Volume Up/Down, Mute, Power and Power Menu (Power Menu: no row, it's a long press).
  - The TV section (L18): `SettingsPage` `tvBrand`; actions `setTVBrand`, `findTV`, `testTV`; Address via the on-screen keyboard.
  - Pages and rows per *Settings pages* (new `SettingsPage` cases `siriRemote`, `receiver`, `receiverBrand`, `receiverPort`; actions `setReceiverBrand(ReceiverBrand)`, `setReceiverPort(String?)`, `testReceiver`, `findReceiver`; toggles `siriRemoteEnabled`, receiver connection as a two-value row like Channel Up). Environment closures for status, ports, test and find (async, the row's detail shows "Testing…", then the result).
  - Tests: rows and values for each state (no remote, connected; brand none/pioneer; serial vs network shows Serial Port or Address; TV none/panasonic); `setReceiverBrand` saves `receiverBrand`; test result text; decoding of the new keys (missing → defaults; unknown brand → none).
  - Done when: tests pass; in `-windowed YES` the pages open from Remote & Input and read right (screenshot in the hand-back).

- [x] **12. Power button and power menu** `[implementer]` `[security]`: files: `AVControl/PowerController.swift` (L14 as rewritten in step 2: TV through `TVController`, no CEC), `Launcher/PowerMenu.swift`, `Launcher/PowerMenuView.swift` (new), `Launcher/AppRouter.swift`, `PIN/PINFlow.swift`, `App/AppDelegate.swift`, `MMTVLTests/PowerMenuTests.swift`, `MMTVLTests/PowerControllerTests.swift` (new), `MMTVLTests/PINFlowTests.swift`, `MMTVLTests/AppRouterTests.swift`
  - `PowerController` (L14) with injected effects (`receiver`, `tv`, `sleepDisplays`, `wakeDisplays`, `sleepMac`, `restartMac`, `relaunch`) so tests fake them; real effects: `pmset displaysleepnow`, `IOPMAssertionDeclareUserActivity`, `pmset sleepnow` (fallback Apple event), `kAERestart` to `loginwindow`, `AppRelauncher.relaunch`. Log every action (category `Power`, notice) and, 10 s after power-on, the default output device name and transport.
  - `PowerMenu` (pure, `LiveMenu`-like) and `PowerMenuView` (glass panel, centered; designer polish optional) as a top-level overlay in `LauncherRootView` above every screen, YouTube and Live TV included; `AppRouter` routes commands to it while open. `powerMenu` brings MMTVL forward first (`Foregrounder`, reason `powerMenu`). Relaunch and Restart go through PIN entry when a PIN is set (`PINPurpose.relaunch`, `.restartMac`); cancel returns to the menu's screen.
  - Tests: short press off → TV power key (only when on), receiver off, displays sleep, in that order; next press → wake, Wake-on-LAN until the TV answers, receiver on; no TV set up → receiver and displays only; a TV that doesn't answer when on was expected → treated as off (next press turns on); menu items, Back cancels; Restart with a PIN asks for it, without a PIN runs at once; wrong PIN doesn't restart.
  - Done when: tests pass; in `-windowed YES`, the keyboard (bind a key to Power Menu in Remote Buttons) opens the menu over Settings and Live TV, and Cancel/Back close it; `[security]` review passes (restart/relaunch behind the PIN, no shell strings built from input).

- [x] **13. Plex restart after a hot-plug** `[implementer]`: files: `App/DisplayHotplugMonitor.swift` (new), `Launcher/AppLauncher.swift`, `App/AppDelegate.swift`, `MMTVLTests/AppLauncherTests.swift`, `MMTVLTests/DisplayHotplugTests.swift` (new)
  - L16. The monitor's callback is reduced to a pure `HotplugEvent` (display id, added/removed) handled on the main actor; `AppLauncher.noteDisplayChange(frontmostBundleID:)` marks running, non-frontmost apps in `restartAfterHotplug`; `launch(_:)` restarts a marked app per L16 before opening it. Also mark Plex when `PowerController` turns the TV on (L14).
  - Tests: a remove/add while Plex runs in the background marks it; while Plex is frontmost it doesn't; opening a marked app terminates then launches it and its pid leaves `launchedPIDs` first (so `applicationDidTerminate` doesn't go Home); an unmarked app opens as before.
  - Done when: tests pass; record in M7f's *Deviations*: "Step 5's Plex fix is M7h step 13 (D45)".

- [x] **13b. Optional volume toast** `[implementer]` (added 2026-11-08 at the user's request, after build 24): files: `App/AppSettings.swift` (`volumeToast`), `App/AppDelegate.swift` (`performVolume`), `App/Volume.swift` (`VolumeToast`), `Settings/SettingsTypes.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift` (if the toggle needs a case), `MMTVLTests/VolumeTests.swift`, `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/SettingsReceiverTests.swift`
  - **Why:** the user wants the volume toast to be optional. It may also be the cause of the Live TV skip on volume presses (2026-11-08 entry under *Deviations*). This step doesn't fix the skip; with the toast off, it does show whether the toast causes it.
  - **Today:**
    - Every Siri Remote and volume-key press that `VolumeController` performs ends in `AppDelegate.performVolume` (`App/AppDelegate.swift:607-613`). It turns the outcome into `VolumeToast.message(for:)` (`App/Volume.swift:80`) and calls `OverlayToast.shared.show`. The phone shows no toast (step 10).
    - The messages are:
      - levels: "Volume −20 dB", "Volume Min", "Volume … (max)", "Volume 50 %", "Volume";
      - "Muted";
      - `.unavailable` errors: "Volume can't be changed here", "Receiver isn't answering".
    - Bool settings decode with `decodeIfPresent … ?? defaults` (`App/AppSettings.swift:102`, `homeLivePreview`), and toggle rows use `action: .toggle(.<key>)` with `Self.onOff` (`Settings/SettingsModel+Pages.swift:194`, `cursorAutoHide`).
  - **Change:**
    - Add `volumeToast` (Bool, default `true`; a missing or wrong-typed key reads as `true` without sending `settings.json` to `.bak`, like step 9b's keys).
    - A pure `VolumeToast.shouldShow(_ message:, outcome:, enabled:)` decides; or give `message(for:enabled:)` an `enabled` argument, whichever fits. Off hides level and Muted messages; `.unavailable` messages always show, because they tell the user why a press did nothing. `performVolume` reads the live setting at each press.
    - Settings → Remote & Input → Receiver & TV, in the Receiver section, adds the row **Show Volume** (On/Off toggle, every brand including None, since the toast also shows for the Mac's own volume). It goes after Maximum Volume, or after the Brand row when Maximum Volume is hidden. Description: "Shows the volume at the top of the screen when you press a volume button. Messages about volume not working always show." It saves at once, like the other toggles.
  - **Tests:**
    - `volumeToast` decoding: missing → true, false, wrong type → true without `.bak`;
    - the show rule for each feedback kind, with the toast on and off;
    - the row appears for brand None and Pioneer, and toggling it saves.
  - Done when: tests pass (quote the full suite's result line). QA, in `-windowed YES` on the dev Mac: with Show Volume Off, a keyboard volume key logs no `Toast Volume …` line; with it On, it does. Category `Toast` in `log stream`. The keyboard volume keys need the event tap, which `-windowed` doesn't run, and the phone shows no toast. If no live path reaches `performVolume` on the dev Mac, QA checks the row live (it toggles and saves to `settings.json`) and the show rule through the tests, and says so. **TV check (build 25):** Show Volume Off, Live TV playing, Siri Remote Vol±: no toast, and say whether the skip is gone.

- [x] **13c. Settings → Audio & TV** `[implementer]` (added 2026-11-08 at the user's request: "I was instinctively looking for audio in the settings menu when I went to set up the AVR"; after 13b): files: `Settings/SettingsTypes.swift` (`SettingsPage`), `Settings/SettingsModel+Pages.swift`, `Settings/SettingsModel.swift`, `MMTVLTests/SettingsReceiverTests.swift`, `MMTVLTests/SettingsSiriRemoteTests.swift`, `MMTVLTests/SettingsModelTests.swift`, `MMTVLTests/SettingsRemoteButtonsTests.swift`, `MMTVLTests/SettingsTestSupport.swift` (as needed)
  - **User decisions (2026-11-08):**
    - A new root category, **Audio & TV**, right **after Casting**. The root order becomes Home Screen, Live TV, Plex, YouTube, Casting, Audio & TV, Remote & Input, Restrictions, System, About.
    - It holds **Receiver** and **TV** as their own pages.
  - **Today (read 2026-11-08):**
    - The root rows are at `Settings/SettingsModel+Pages.swift:133-161`.
    - Remote & Input's `receiver` row ("Receiver & TV", value `receiverAndTVValue`, `:183-185`; value at `:997`) pushes `.receiver`.
    - `.receiver`'s title is "Receiver & TV" (`:94`). It returns two sections, the Receiver section and `tvSection` (`:1061-1064`, `:1083`).
    - The subpages are `.receiverBrand`, `.receiverPort`, `.receiverMaxVolume`, `.receiverFound`, `.tvBrand` and `.addressEntry(AddressField)` (`SettingsTypes.swift:21-23`).
    - `SettingsModel.swift` decides some things by which page is on top. Around `:66-73`, the receiver status refreshes when the page opens. At `:617`, Find on Network's chooser shows "if Receiver & TV is still the page". The TV's Find and Test results may check the same.
    - The parent column (M7g D42) shows the page below the top of the stack, with `parentSelectionRowID` (`SettingsModel.swift:150`).
    - Root's Remote & Input description names "the receiver and TV" (`:151-153`).
  - **Change:**
    - New page `.audioTV`, title "Audio & TV", pushed from a root row `audioTV`. Description: "The AV receiver for volume and power, the TV's power, and the volume display." Its rows, in order:
      - **Receiver**: value = the receiver's brand or "Not Set Up", disclosure, pushes `.receiver`. Description: "Volume, mute and power through the AV receiver, over a serial cable or the network."
      - **TV**: value = the TV brand or "Not Set Up", disclosure, pushes a new page `.tv`. Description: "Turning the TV on and off with the remote's Power button."
      - A **Volume** section with step 13b's **Show Volume** row. It moves here from the Receiver page, because it applies to every volume route, not only the receiver.
    - `.receiver` is renamed **"Receiver"** and keeps only the Receiver section.
    - `.tv` (new), titled "TV", holds today's `tvSection` rows. Its subpages (`.tvBrand`, the TV `addressEntry`) push from it.
    - Every page-on-top check that meant "Receiver & TV" now checks `.receiver` or `.tv`, whichever the result belongs to. Keep Find on Network's chooser reachable (step 8b QA minor 1).
    - Remote & Input loses its `receiver` row. The root description becomes "The Siri Remote, remote buttons, game controllers, the pointer and the phone remote."
    - Comments and `AppSettings.swift`'s doc text that say "Remote & Input → Receiver & TV" now say "Audio & TV → Receiver" or "→ TV". Step 18's **Without a Receiver** section goes on the **Audio & TV** page's Volume section, not on the Receiver page.
    - The Debug `-settingsDemo` paths follow, e.g. `audioTV/receiver`.
  - **Tests:**
    - root order, and the row's push;
    - Audio & TV's rows and values: brand None, Pioneer serial, and a TV set up;
    - Receiver keeps its rows without the TV section; TV has the TV rows;
    - Remote & Input no longer lists Receiver & TV, and the focus-order tests are updated;
    - Find on Network's chooser and the TV Find/Test results still land when their page is on top;
    - Show Volume toggles and saves from Audio & TV;
    - Back from Receiver or TV returns to Audio & TV with that row focused, and Back again returns to root on Audio & TV.
  - Done when: tests pass (quote the full suite's result line). QA in `-windowed YES` walks root → Audio & TV → Receiver → Brand and back, and Audio & TV → TV, with screenshots of each page and its parent column. The layout matches the other categories.

- [x] **13e. Build 25 findings** `[implementer]` (added 2026-11-08 from build 25's TV checks; see that Deviations entry): files: `App/AppDelegate.swift`, `Settings/SettingsModel.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsTypes.swift`, `App/AppSettings.swift` (`siriRemoteSwipes`), `Input/SiriRemote/SiriRemoteInput.swift`, `Input/CursorAutoHide*` / wherever the pointer is hidden, tests as needed
  - **(a) The Live TV skip.**
    - Status changes from the receiver, the CEC receiver and the other devices must not run the whole `SettingsModel.refreshStatus()` while Settings isn't on screen.
    - When it is on screen, they refresh only the fields that changed: the receiver's status for receiver changes, CEC for CEC.
    - Nothing on a volume press or a receiver line may touch the Keychain, `SMAppService` or any IPC on the main actor.
    - Measure `refreshStatus()` on the dev Mac (signposts or timing) before and after, and report the numbers.
  - **(b) Swipes are optional, off by default.** New `settings.json` key `siriRemoteSwipes` (Bool, default `false`), and a Settings → Remote & Input → Siri Remote row **Swipes** (On/Off; description "Swipe on the remote's touch surface to move around, like an Apple TV. Off: only the clickpad's clicks move."). With it off:
    - touches outside trackpad mode do nothing in MMTVL (no swipe events);
    - trackpad mode is unchanged.
    - "How it works" mentions it.
  - **(c) The pointer is invisible in trackpad mode**, on the desktop too, though the mouse moves.
    - Find how the pointer is hidden: `CursorAutoHide`, `NSCursor.setHiddenUntilMouseMoves`, `CGDisplayHideCursor`, kiosk presentation options, or synthetic moves not counting as mouse movement. Whether the phone trackpad has the same issue is unknown.
    - Make the pointer visible while trackpad mode is on, in every app, and hide it again when trackpad mode ends (if auto-hide is on).
    - Record the cause in the report.
  - Done when: tests pass (quote the full suite's result line); (a)'s timing numbers; (c)'s cause, and a fix exercised in `-windowed YES` with synthetic pointer moves through the same `SyntheticInput` path.
  - **TV check (build 26):** no skip on Vol± (remote, phone, dial); swipes off by default with clicks clean, and on when chosen; trackpad mode shows the pointer.

- [x] **13f. Home screen freeze: the parallax hover loop** `[implementer]` (added 2026-11-08 from a build 26 freeze; see Deviations, "2026-11-08, build 26: home screen frozen after YouTube"): files: `DesignSystem/ParallaxFocus.swift`, `MMTVLTests/ParallaxTests.swift`
  - **Current behaviour (`DesignSystem/ParallaxFocus.swift:59-68`):** `.onContinuousHover` is on `content`, inside the `keyframeAnimator` whose `ParallaxRender` applies two `rotation3DEffect`s and `scaleEffect(Theme.focusScale)` (`:121-125`). So the hover location is in the tilted, scaled tile's own space. Each `.active(location)` sets `hoverTilt` with `.interactiveSpring`; the tilt turns the tile under a pointer that hasn't moved; SwiftUI re-hit-tests after the transaction (`EventBindingManager.enqueueHoverUpdateIfNeeded`) and reports a new location; that sets a new tilt, without end. The MM's sample: 100 % CPU on the main thread, half in `NSHostingView.didRequestHoverUpdate` hit-testing, half in the transaction animating the specular `RadialGradient` (`:135-141`), with `closure #3 in ParallaxFocus.body` (the hover handler) on the stack. Nothing else runs, so input is ignored.
  - **Why now (inferred, not seen):** the hidden pointer rests over the focused tile on return to Home (build 26's Siri trackpad mode, or a pointer move in YouTube). Unlike the router's hover handlers (`AppRouter.swift:885-898`, `pointerMovedSinceLastCommand`), the parallax follows a pointer that never moved. Both users of the modifier are affected: home tiles (`Launcher/AppTileView.swift:18`) and top shelf cards (`Launcher/TopShelfView.swift:169`).
  - **(a) Hover outside the transforms.** In `ParallaxFocus.body`, move `.onContinuousHover` (and the `onGeometryChange` it reads `size` from) after the `keyframeAnimator`, behind `.contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))`. The location and the hover area are then the untilted layout frame, so a tilt can't change what the pointer is over or where. Keep `.shadow` last. The tile's tap area (`HomeView.swift:185-188`, `TopShelfView.swift:141-145`, outside the modifier) becomes the untilted shape too, which is intended.
  - **(b) Only a moving pointer tilts.** Remember `NSEvent.mouseLocation` when the tile becomes focused and at each hover update it follows; ignore `.active` when the pointer hasn't moved since then (the view moved, not the pointer). So a resting, hidden pointer never tilts a newly focused tile, and nothing can loop even if (a) misses a case. `.ended` still settles the tilt to zero. Put the decision in a pure, tested helper (e.g. `ParallaxMath.followsPointer(at:last:)`).
  - **Tests:** the helper (unchanged pointer = no; moved = yes; none recorded = no). The existing `ParallaxTests` stay green.
  - Done when: tests pass (quote the full suite's result line). In `-windowed YES` on the dev Mac: (1) with the pre-fix build, try to reproduce: park the pointer (a synthetic move, e.g. `CGWarpMouseCursorPosition` from a script) at several points of the focused tile, near the edges too, and focus that tile with the arrow keys; report MMTVL's CPU (`ps -o %cpu`) and a `sample` if it spins, or that it didn't reproduce; (2) with the fix, the same: CPU settles to idle; (3) a real pointer move over the focused tile still tilts it and the shine follows. If the dev Mac's session is locked (no hover events), say so: then it's a TV check only.
  - **TV check (build 27):** the user's sequence: Home → YouTube (use the Siri trackpad mode there) → Home, several times, with the pointer left on different tiles; the home screen stays responsive. Trackpad mode on the home screen: moving over the focused tile still tilts it.

- [x] **13g. Live TV black after Select from the home preview** `[implementer]` (added 2026-11-08 from a build 27 report; see Deviations, "2026-11-08, build 27: Live TV black after Select"): files: `IPTV/Player/MPVVideoView.swift`, `IPTV/Player/LivePlayer.swift`, a test file
  - **Fix:** `MPVVideoLayer` tells its ready callback whether the render context it just made replaced one. On a replaced context, with no pending URL, a current URL and phase `.loading`/`.playing`, `MPVPlayerController` reloads the current stream through `load(_:)` (resolver cache, relay). It logs `Video GL context replaced while playing; reloading the stream (player N)`. Paused is left alone. The decision is a pure, tested helper.
  - Done when: tests pass (quote the full suite's result line). **Done 2026-11-08:** `✔ Test run with 1538 tests in 154 suites passed`.
  - **TV check (build 28), superseded by 13h:** with 13h the Select no longer swaps the context, so the reload only fires on real context changes (a display change). Original check: Select on Live TV from the home preview shows video within about half a second, every time (5×); Back to Home keeps the preview's video; the same through Multiview. The log has the reload line after each `Video GL context created`.

- [x] **13h. Seamless Select: one video layer for the home preview and Live TV** `[implementer]` (added 2026-11-08 at the user's request: "is it not possible to not make it reload and just remove the home screen elements and have them fade out?"): files: `Launcher/AppRouter.swift` (`LauncherRootView.screenBody`), `Launcher/ScreenVideoLayout.swift` (new), `IPTV/LiveTVView.swift`, `MMTVLTests/ScreenVideoLayoutTests.swift` (new)
  - **Change:** every player's video is in one `ForEach` keyed by player identity, the first child of `screenBody`'s ZStack for every screen but YouTube. It sits under the home canvas or `LiveTVRootView`, so a player's view stays in the window from home to Live TV and back. No GL context swap and no reload: the home UI fades over video that keeps playing. `ScreenVideoLayout.placements` (pure, tested) gives the placements per screen: the home preview full window at `homeFade` (animated, kept at 0 while it preloads), and Live TV's `videoPlacements` (not animated). Frames never animate. The background is black for Live TV and the gradient otherwise, set through `.background`, not a branch. `LiveTVRootView` keeps only its overlays. 13g's reload stays as the safety net.
  - Done when: tests pass. **Done 2026-11-08:** `✔ Test run with 1546 tests in 155 suites passed`; QA PASS by code reading. The dev Mac was at the login window, so it couldn't be run.
  - **TV check (build 28):** Select on Live TV from the playing home preview, 5×: the home UI fades over the moving picture, with no black and no restart. Back and Home from Live TV keep the preview's picture. Multiview entered from the preview, and the guide's preview rect, look right. Log (`category == "MPV"`): no `Video GL context released`/`created` and no `reloading the stream` at those moments.

- [x] **14. TV check, build 1: the remote** `[human]` (after steps 3–7; one test build via `scripts/test-build.sh` and `scripts/deploy-mm.sh`, after the user says yes)
  - Remote Buddy quit (or uninstalled). In Settings → Remote & Input → Remote Buttons, the old "A" Home binding is gone; typing "a" in Safari types "a".
  - TV goes Home from Plex, Safari, Prime Video and Live TV; Back, Play/Pause and clickpad clicks work in MMTVL and in Plex/Safari (arrow keys, Return, Escape).
  - Swipes move focus on the home screen, in Settings and in the Live TV guide, one step per short swipe, several for a long one; clicking doesn't swipe. Long press centre opens the channel menu in Live TV.
  - Double-press Siri: "Trackpad On" toast; the pointer moves smoothly, centre click clicks, long press right-clicks (context menu in Safari), right-edge slide scrolls a web page, Back is Esc; double-press again: "Trackpad Off". Single Siri press does nothing.
  - Leave the remote alone 10 minutes, then press TV: it works (first press may be slow: note how slow).
  - Logs: `ssh mm "/usr/bin/log show --last 30m --predicate 'subsystem == \"dev.mmtvl.launcher\" AND (category == \"SiriRemote\" OR category == \"Input\")' --info"`.
  - Done when: each item is ticked in *Manual verification* or recorded under *Deviations*.

- [x] **14b. Probe: HDMI-CEC through DisplayPort AUX tunneling** `[implementer]` then `[human]` (added 2026-11-06 at the user's request, after TV build 1; doesn't block steps 15–16): files: `scripts/probes/dpcd-cec.swift` (new; deleted in step 16 with the other probes)
  - **Why:** step 1 closed only the two high-level routes (IOCEC: exclusive to corercd; CoreRC: private entitlements). BetterDisplay sends CEC on Apple silicon by "DisplayPort AUX DPCD CEC tunneling" (Research, *HDMI-CEC from the Mac*), a route below corercd that step 1 never tried. The user wants CEC kept as an option so MMTVL works with other TVs and receivers (no network control, no RS-232).
  - **What exists (verified on the dev Mac, macOS 27, 2026-11-06):** `IOKit.framework` exports, with no CEC framework involved: `IODPDeviceCreateWithService`, `IODPDeviceReadDPCD`, `IODPDeviceWriteDPCD`, `IODPServiceCreateWithService`, `IODPServiceGetDevice`, `IODPServiceGetAVService`, `IODPDeviceGetRevisionMajor/Minor`, and `IOAVServiceCreateWithService`, `IOAVServiceReadI2C`/`WriteI2C`, `IOAVServiceCopyPhysicalAddress` (`dyld_info -exports …/IOKit`). The registry has `DCPDPDeviceProxy`, `DCPDPServiceProxy`, `DCPAVServiceProxy` and the CEC pair `DCPAVCECInterfaceProxy` → `IOAVCECService` (`ioreg -l`). **Unverified:** these functions' signatures (no headers; `IOAVServiceReadI2C(service, chip, offset, buf, len)` is the shape m1ddc uses; DPCD is probably `(device, address, buf, len)`), whether the user client needs an entitlement or root, and whether the mini's HDMI port is a DP-to-HDMI protocol converter at all (it may be native HDMI inside DCP, with CEC handled there).
  - **Registers** (VESA DP 1.3 §5.3.3.3.1, DPCD 1.4+; from Linux `include/drm/display/drm_dp.h`, the driver is `drm_dp_cec.c`): `0x3000` TUNNELING_CAPABILITY (bit 0 tunneling, 1 snooping, 2 multiple logical addresses); `0x3001` TUNNELING_CONTROL (bit 0 enable, 1 snooping); `0x3002` RX_MESSAGE_INFO (len − 1 in bits 0–3, bit 7 ended); `0x3003` TX_MESSAGE_INFO (len − 1 in bits 0–3, retries bits 4–6, bit 7 send); `0x3004` IRQ_FLAGS (bit 0 RX valid, 1 RX overflow, 4 TX sent, 5 line error, 6 address NACK, 7 data NACK; write a bit back to clear); `0x300E`/`0x300F` logical address mask; `0x3010` RX buffer, `0x3020` TX buffer (16 bytes each). Also read `0x0000` (DPCD revision; ≥ 0x14 for these registers) and `0x0005`/`0x0080` (downstream port present and type; HDMI = a protocol converter). The len − 1 encoding and the clear-by-write are from `drm_dp_cec.c` (**unverified** on Apple's converter).
  - **Probe 1, read-only, over SSH, no one at the TV:** `dlopen` IOKit symbols with `dlsym`; find the HDMI display's `DCPDPServiceProxy`/`DCPDPDeviceProxy` (`IOServiceGetMatchingServices`, print class, location and `IOAVServiceCopyPhysicalAddress`); create the DP device; **read only** `0x0000`, `0x0005`, `0x0080`, `0x3000`–`0x3004`, `0x300E`–`0x300F`, printing each result code and byte. Try the signature shapes above until a read of `0x0000` returns a plausible revision; record what worked. Writes are not compiled into probe 1.
  - **Gate A:** `0x3000` bit 0 is set (the converter tunnels CEC). Also record `0x3001`: if tunneling is **already enabled**, DCP/corercd is using the tunnel, and MMTVL writing to it would race corercd for the same RX buffer and IRQ flags (risk: breaking the CEC macOS does itself, e.g. the TV turning the receiver off). Fails → record "no DP CEC tunnel on the mini", keep step 9 skipped, done.
  - **Probe 2, with the user at the TV and their OK, only if gate A passes:** `--send standby`: if tunneling isn't enabled, enable it (`0x3001` = 0x01) and set the logical address mask to playback 4 (`0x300E` = 0x10); write `40 36` to `0x3020`, `0x3003` = (2 − 1) | (3 << 4) | 0x80; poll `0x3004` for TX sent/NACK (1 s), write the flags back to clear; restore `0x3001`/`0x300E` to what they were. Then `--send on` (`40 04`, then `4F 82 <physical address>`), and `--listen 10` (print RX frames, read-only). Watch: does the TV turn off/on; does the receiver still follow the TV (corercd's CEC unharmed); any HDCP or picture glitch (Prime Video test, as on 2026-11-05).
  - **Gate B:** standby and on work, and macOS's own CEC behaviour is unchanged afterwards. Passes → reopen step 9 as **"9. DP-AUX CEC transport"** (a `CECBus` over DPCD, offered in Settings → Receiver & TV as a TV control alongside Panasonic VIERA, and for TV/receiver power on setups without network or RS-232; L13 and D44 amended, the user decides scope). Fails → record why, keep it skipped.
  - Done when: both gates' results are under *Deviations & questions* ("Step 14b results"), with the working signatures, and the user has decided whether step 9 comes back.

- [x] **15. TV check, build 2: receiver, TV, power and Plex** `[human]` (after steps 8–13; one test build)
  - Plex: leave Plex in the background, turn the TV off and on with the TV's own remote, open Plex: it draws (it was restarted: `log show --last 15m --predicate 'subsystem == "dev.mmtvl.launcher" AND category == "AppLauncher"' --info` shows `Restarting tv.plex.htpc after a display change`).
  - Settings → Remote & Input → Receiver & TV: Find Receiver (Serial) selects Pioneer; Network → Find Receiver finds nothing (no networked receiver) and says so, without errors; Test Connection shows "On · … dB · …" matching the receiver's display. Brand None hides control.
  - Volume Up/Down and Mute on the remote change the receiver, with the toast showing the dB value; the phone's volume buttons do the same.
  - Power short press: receiver and TV off, displays asleep; press again: all back on, MMTVL's home screen shows; Plex opens and draws. The TV (wired, TV Remote App and Wake on LAN on): Settings → Receiver & TV → Find TV finds "VIERA VT50" and fills Address; Test TV shows On and its volume; Power off turns the TV off (and the receiver), Power on wakes it within about 20 s.
  - Long press Power in Plex: MMTVL's power menu over the screen; Cancel/Back return; Relaunch asks for the PIN; Sleep Mac mini sleeps it (wake with the keyboard); Restart Mac mini asks for the PIN and restarts (MMTVL comes back at login).
  - Power never sleeps or locks the Mac by itself (step 1: no loginwindow setting needed). Volume keys: with the receiver set up, Vol± and Mute on the remote change the receiver and no macOS HUD shows; with Brand None, macOS's HUD shows as before.
  - Logs: `ssh mm "/usr/bin/log show --last 30m --predicate 'subsystem == \"dev.mmtvl.launcher\" AND (category == \"Receiver\" OR category == \"Power\")' --info"`.
  - Done when: each item is ticked or recorded.

- [x] **16. Docs and cleanup** `[doc]` (runs last, after the build 25 TV checks; the software volume parts below move to M7k with steps 17–19): files: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan, `scripts/probes/` (delete)
  - CLAUDE.md: replace the "Siri Remote through Remote Buddy (M7c L5)" paragraph with the own driver (D43: buttons, swipes, trackpad mode, Siri double-press, long presses, the toast); the new `settings.json` keys; the `siriRemote` trigger in `key-bindings.json`; new commands; Receiver & TV (D44: brands, serial path, no CEC on macOS, the TV over the network (L18: the TV's settings, wired for Wake-on-LAN), Test/Find are read-only, the AVR queries from Terminal); volume keys through the event tap (L3a); Power (D45); the Plex restart after hot-plugs; log commands for categories `SiriRemote`, `Receiver`, `Power`. Remove "Game Controllers must stay on" for the TV button. D25's text in the master plan points to D44.
  - Master plan: M7h `Done`, Q21 and Q22 resolved, this plan moved to `archive/`.
  - Software volume (steps 17–19):
    - CLAUDE.md:
      - `settings.json` gains `softwareVolumeEnabled` and `softwareVolumeLevel`; `phoneRemoteVolume` values become `auto | receiver | software | system | app` (`CLAUDE.md:95`);
      - a **Software volume** paragraph: L19, `NSAudioCaptureUsageDescription`, the System Audio Recording grant and its reset command (from step 17), off at 100 % and with a receiver, not for passthrough, sound returns at full level if MMTVL quits;
      - the `Volume` log command;
      - remove SoundSource everywhere.
    - Master plan:
      - D25 and D44 as in this plan's Design;
      - §3 Volume row;
      - Q8 marked moot.
    - Delete `scripts/probes/audiotap/`, and the probe's TCC entry on the mini (`tccutil reset AudioCapture dev.mmtvl.probe.audiotap`).
    - Done-when addition: `git grep -n -i soundsource -- ':!docs/plans/archive'` shows only history notes.
  - Done when: `git grep -n "Remote Buddy" CLAUDE.md` shows only history notes, and the probes are deleted.
  - **Done 2026-11-08** (QA PASS; full suite 1546 tests passed). See Deviations, "step 16". M7h `Done` and the archive move wait for the 1.2.0 bump and the PR.


- [x] ~~**17. Probe: software volume with a process tap on the mini**~~ **Moved to M7k** (user, 2026-11-08; opt-in in Settings, telling the user it taps every app's audio). The text below is M7k's starting point. `[implementer]` then `[human]` (after step 15, with SoundSource uninstalled on the mini first: the user, see *Manual verification*; its ARK would confuse the hot-plug results): files: `scripts/probes/audiotap/main.swift`, `scripts/probes/audiotap/Info.plist`, `scripts/probes/audiotap/build.sh` (new; deleted in step 16)
  - **A tiny app, not a CLI.** `build.sh` runs `swiftc` and builds `AudioTapProbe.app` (bundle id `dev.mmtvl.probe.audiotap`, `NSAudioCaptureUsageDescription` in its Info.plist), signed `Apple Development` with team H846CY8RB4. It is started on the mini with `open … --args`, so the TCC prompt shows on the TV and the grant belongs to the probe (a binary run from SSH may not get a prompt, **unverified**). Output goes to a log file in `/tmp/mmtvl-probes/`, read over SSH.
  - **Arguments:** `--gain 0.25`, `--seconds N`, `--tap stream|stereo`, `--exclude pid|bundle`, `--mute whenTapped|muted`, `--rebuild-debounce 2`.
  - **At start it prints:**
    - the default output (name, UID, `VirtualMainVolume` settable, nominal rate, stream format with channels and the non-mixable flag, hog pid, latency + safety offset + buffer size);
    - the TCC preflight result;
    - its own process object id;
    - every 2 s, the processes with `IsRunningOutput` (bundle ids only).
  - **What it does:** builds L19's tap + private aggregate + IOProc (gain applied) and prints:
    - the tap format;
    - each second, the peak of the tap input and the **added latency** (IOProc `inOutputTime` − `inInputTime` host time, in ms, plus the aggregate's reported latency minus the output's);
    - device events with timestamps (default output, device list, alive, rate, hog). On an event it tears down and rebuilds after the debounce, counting rebuilds.
  - **Read-only toward settings:** it changes no system setting and leaves the output's format alone.
  - **Run with the user at the TV.** MMTVL running, the receiver at a fixed level:
    1. First run: does the prompt show on the TV? Grant it. Record the System Settings section it lands in. Record whether `tccutil reset AudioCapture dev.mmtvl.probe.audiotap` resets it.
    2. `--gain 0.25`. Is each source clearly quieter (not silent, not doubled)? Sources: YouTube in MMTVL, Live TV in MMTVL (excluded from MMTVL's own engine later, but tapped here), Plex HTPC (normal PCM), Prime Video in Safari, Prime Video in Brave, the Prime Video app (`com.amazon.aiv.AIVApp`), and optionally AirPlay from an iPhone and Reflector. Record which process plays YouTube's audio (MMTVL's pid or a WebKit process).
    3. Latency: the probe's added ms, and lip sync on a YouTube A/V sync test video with the probe off and on.
    4. Plex HTPC with audio passthrough on (AC-3/DTS; the receiver shows Dolby/DTS): the probe's hog and format lines; does the receiver still get the bitstream; does the probe stop cleanly or break the audio?
    5. TV power cycle (TV remote off and on) with the probe running: count device events and rebuilds; does audio come back scaled; any stuck silence? Then quit the probe: does HDMI audio work without `killall coreaudiod`?
    6. `kill -9` the probe while audio plays: does the original audio come back, how fast, at what level?
    7. With the user's OK, deny the permission (System Settings), then run again: confirm the docs.rs claim (silent and still muted), and that preflight reports denied. Grant it again.
    8. Settings → Sound / `pmset` sanity: the default output stays HDMI the whole time (the private aggregate never shows).
  - **Gates:**
    - **A:** scaled audio from YouTube, Plex (PCM) and Safari, with the originals muted.
    - **B:** added latency ≤ 40 ms (lip sync not noticeably off; ITU-R BT.1359 puts the detectability threshold at about 125 ms of audio lag).
    - **C:** Prime Video (browser and app) is scaled, or is at least never silent. Silent-and-muted is the case the watchdog handles; full volume unscaled is acceptable but goes on record.
    - **D:** passthrough isn't broken while the probe runs. Software volume never runs with a receiver ready anyway, so D failing means "engine off while hogged or non-mixable", not a stop.
    - **E:** after a TV power cycle the probe recovers within about 5 s of the last device event, and a killed probe gives the audio back.
  - **If a gate fails:** A fails → L19 is dropped, `auto` = receiver → system → app, and the user decides. B fails → record the number and decide with the user (e.g. software volume off by default). C, D and E failures adjust L19 (watchdog, hog rule, debounce) and are recorded.
  - Done when: each result and gate is under *Deviations & questions* as "Step 17 results" (raw logs in the session scratchpad), with the tap shape that worked (stream or stereo, exclude by pid or bundle id), and the user has said go or no-go for step 18.

- [x] ~~**18. Software volume**~~ **Moved to M7k** (user, 2026-11-08). `[implementer]` `[security]` (after steps 10, 11 and 17's go): files: `AVControl/SoftwareVolume.swift`, `AVControl/SoftwareVolumeEngine.swift`, `AVControl/AudioCapturePermission.swift` (new), `App/Volume.swift`, `App/AppSettings.swift` (`softwareVolumeEnabled`, `softwareVolumeLevel`), `App/AppDelegate.swift`, `Input/GlobalEventTap.swift`, `Input/SyntheticInput.swift` (drop `NXKey.soundUp/soundDown/mute` if unused), `RemoteServer/PhoneRemote.swift`, `Settings/SettingsModel+Pages.swift`, `Settings/SettingsTypes.swift`, `MMTVL.xcodeproj/project.pbxproj` (`INFOPLIST_KEY_NSAudioCaptureUsageDescription`, both configurations), `MMTVLTests/VolumeTests.swift`, `MMTVLTests/SoftwareVolumeTests.swift` (new), `MMTVLTests/AppSettingsTests.swift`, `MMTVLTests/SettingsReceiverTests.swift`, `MMTVLTests/PhoneRemoteTests.swift`
  - **The engine:** L19 as step 17 settled it. The render function and rules are pure; `CoreAudioTapEngine` follows step 17's working shape. The IOProc block is `nonisolated` with an `Atomic<UInt32>` gain (`Synchronization`), and its queue is dedicated.
  - **`Volume.swift`:**
    - remove `soundSourceBundleID`, the `NSWorkspace` check, `VolumeMode.keys`, `VolumeRoute.keys` and `.sentKeys` (or keep it as "sent, level unknown" if step 10 reused it for the receiver);
    - add `VolumeMode.software` and `VolumeRoute.software`;
    - change the signature to `choose(mode:receiverReady:softwareReady:systemSettable:launcherActive:)`;
    - `perform(.software)` steps the level, unmutes on up/down, toggles mute, applies the amplitude to mpv (and YouTube, per step 17), and returns `.level(level, muted:)`;
    - the log category becomes `Volume`.
  - **The event tap (step 10's L3a):** it consumes when the route is receiver or software (`VolumeController.consumesVolumeKeys`).
  - **The Info.plist text:** "MMTVL changes the sound level of other apps on outputs without their own volume control, like HDMI. Nothing is recorded or saved." Check that the built `Info.plist` has the key. If Xcode drops it, record that under *Deviations* (fallback: a partial `INFOPLIST_FILE` with only this key).
  - **Settings** (step 13c's **Audio & TV** page, in or after its Volume section), a section **Without a Receiver**:
    - Software Volume (toggle `softwareVolumeEnabled`; description "Controls the volume of the Mac's HDMI sound when there's no receiver. Not for Dolby or DTS passthrough.");
    - System Audio Access (value Allowed / Not Allowed / Unknown; Select → `TCCAccessRequest`; once denied, Select opens System Settings → Privacy & Security. The pane URL is **unverified**: try `x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`, else open the Privacy & Security root);
    - Status (info: "Off at full volume", "On · 50 %", "Paused: passthrough", "Paused: no sound", "Receiver in use").
  - The phone page footer (`SettingsModel+Pages.swift:656`): "Volume buttons control the receiver when one is set up, else MMTVL's software volume (HDMI), else the Mac's volume, else MMTVL's own."
  - **Wiring:** `AppDelegate` creates `SoftwareVolume` (not in hosted tests), gives `VolumeController` `softwareReady`, tears down in `applicationWillTerminate`, and feeds `receiverReady` changes from `ReceiverController`.
  - **Tests:**
    - `choose` for every mode with and without a ready receiver, software ready and settable output (receiver > software > system > app; forced modes);
    - `"keys"` and `"bogus"` read as `auto`;
    - gain curve (0 → 0, 1 → 1, monotonic, ≤ 1), ramp endpoints, render on arrays (gain, mute, 2 → 8 channels, NaN-free);
    - rules: off at unity, off when the receiver is ready, starts 10 s after it isn't, off on a settable output unless forced, off without permission, off when hogged or non-mixable, the 2 s rebuild debounce, the watchdog after 3 s of zeros while output is running (fake clock);
    - a fake engine counts start/stop;
    - feedback and toast text;
    - `softwareVolumeLevel` clamped and saved after 2 s.
  - **Security review:** the app now holds system-audio capture. Buffers are never stored, logged or sent (no file, no network). Both tap and aggregate are private. The TCC SPI is reached through `dlopen` with a missing symbol leading to "unknown" and the engine off. Teardown on quit; after a crash `.mutedWhenTapped` gives the audio back (step 17 gate E). Logs carry no device UIDs beyond names. Settings' Allow path can't be triggered by a paired phone without the Settings PIN (D20).
  - Done when: tests pass (quote the result line). QA, in `-windowed` with `"phoneRemoteVolume": "software"` on the dev Mac: phone Vol− logs `Software volume on (…)` and returns a level, and Vol+ back to 100 % logs `… off: unity`. Security review has no open medium or worse.

- [x] ~~**19. TV check, build 3: software volume**~~ **Moved to M7k** (user, 2026-11-08). `[human]` (after step 18; one test build after the user says yes; SoundSource uninstalled)
  - Settings → Audio & TV → Receiver → Brand **None**:
    - Vol−/Vol+/Mute on the remote and the phone scale YouTube, Live TV, Plex (PCM) and Prime Video (browser and app), with the "Volume N %" toast and no macOS HUD;
    - back at 100 % the engine is off (`Software volume off: unity`);
    - lip sync looks right.
  - First Vol− with no grant: the system prompt shows on the TV and can be answered (phone trackpad or keyboard; record whether the Siri Remote's pointer can click it, QA minor 3). Settings → System Audio Access shows Allowed after.
  - With Brand Pioneer and the receiver on, the remote's volume goes to the receiver and the software engine stays off. Turn the receiver off with its own remote: within about 10 s the next Vol− uses software volume. Turn it on: back to the receiver, and the engine stops.
  - TV power cycle with software volume at 50 %: sound comes back scaled within about 5 s, and no `killall coreaudiod` is needed. Record whether the HDMI dropout of 2026-11-05 recurs without SoundSource (memory note).
  - Plex passthrough on: the receiver shows Dolby/DTS, and Settings shows "Paused: passthrough" (or what step 17 decided).
  - Relaunch MMTVL from Settings: the level comes back. Quit MMTVL while scaled: sound returns at full level (expected).
  - Logs: `ssh mm "/usr/bin/log show --last 30m --predicate 'subsystem == \"dev.mmtvl.launcher\" AND category == \"Volume\"' --info"`.
  - Done when: each item is ticked or recorded.

## Tests

- New suites: `SiriRemoteButtonTests`, `SiriRemoteGesturesTests`, `SwipeRecognizerTests`, `TrackpadMapperTests`, `ReceiverProtocolTests`, `ReceiverControllerTests`, `CECFrameTests` (if step 9 runs), `SettingsSiriRemoteTests`, `SettingsReceiverTests`, `PowerMenuTests`, `PowerControllerTests`, `DisplayHotplugTests`.
- Extended: `KeyBindingsTests`, `KeyBindingsEditingTests`, `TriggerNameTests`, `VolumeTests`, `AppSettingsTests`, `AppLauncherTests`, `AppRouterTests`, `PINFlowTests`, `PhoneRemoteTests`.
- Run after every step: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`.

## Manual verification

- [x] Step 1's probe results recorded (GameController, seize and macOS's own handling, Power, display sleep CEC, IOCEC open, Pioneer writes).
- [x] Remote Buddy is quit or uninstalled on the mini, and the old global "A" binding is gone; "a" types in browsers.
- [x] TV = Home from every app; clickpad and swipes in MMTVL and in other apps; long-press centre = menu.
- [x] Trackpad mode: Siri double-press toggles with the toast; move, click, right-click, scroll, Back.
- [x] The remote works after 10 minutes idle and after the Mac's sleep and wake.
- [x] Plex draws after a TV power cycle (restarted on open). (2026-11-08, build 24)
- [x] Receiver: Find and Test (read-only), volume and mute with the toast, from the remote and the phone. (2026-11-08, build 24)
- [x] Power short press off and on; power menu with PIN for Relaunch and Restart; the Mac doesn't sleep by itself on Power. (2026-11-08, build 24)

- [x] SoundSource (app and its ARK capture engine) uninstalled on the mini before step 17 (2026-11-07, then a reboot). Its `keyboardVolume` Super Volume Keys are gone, so the remote's Vol± reach MMTVL's tap.
- [ ] *(moved to M7k)* Step 17's probe results and gates recorded; go or no-go for step 18.
- [ ] *(moved to M7k)* Without a receiver: software volume scales every app (YouTube, Live TV, Plex, Prime Video) with the toast, lip sync OK, off at 100 %.
- [ ] *(moved to M7k)* System Audio Access prompt answered on the TV; the grant survives a new build.
- [ ] *(moved to M7k)* TV power cycle with software volume on: sound returns scaled; the HDMI dropout checked without SoundSource.
- [ ] *(moved to M7k)* Receiver set up: software volume stays off; passthrough plays.
## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Power still sleeps or locks the Mac while seized | Step 1: the Mac sleeps on Power | `PowerButtonSleepsSystem = false` in `com.apple.loginwindow` (with the user's OK), documented in CLAUDE.md; else Power menu only on long press of TV. |
| Play/Pause opens Music through `com.apple.rcd` | Step 1: Music opens | The kiosk guard already takes the screen back; if not enough, record it and decide with the user (suspending `rcd` is out of scope). |
| ~~MMTVL can't open CEC~~ | Happened (step 1) | L13 dropped; the TV over the network (L18). |
| DP-AUX CEC writes race corercd or disturb the link (HDCP, picture) | Step 14b probe 2: macOS's own CEC stops, a glitch, or Prime Video fails | Restore `0x3001`/`0x300E`; keep step 9 skipped; never enable tunneling from MMTVL when corercd already has it on. |
| The seized remote's volume doesn't reach the event tap | Step 14: no `Volume key … → receiver` log | Read the remote unseized for volume only (the 0x0C/0x01 interface carries every button, so this would need filtering), or leave remote volume to macOS; decide with the user. |
| Wake-on-LAN doesn't wake the TV after a long standby | Step 15 | Power on still wakes the displays and the receiver; the TV's own remote turns it on. |
| MultitouchSupport changes or is missing in a macOS update | `isAvailable == false` | Buttons keep working; swipes and trackpad mode off; Settings → Siri Remote → Status says "Touch not available". |
| The remote also appears as a game controller | Step 1 `gc` | L10. |
| Swipe or trackpad tuning feels wrong on the TV | Step 14 | All thresholds are constants in `SwipeRecognizer`/`TrackpadMapper`; record new values under *Deviations* and adjust in a follow-up. |
| A networked receiver allows one client only, or drops idle connections | Can't be tested here (L17) | Close after 5 idle minutes, reconnect on demand; Test Connection shows "Connection refused" plainly. |
| Other brands' protocols are wrong in detail | Can't be tested here | Marked unverified in Settings' footer ("Tested with Pioneer"); Test Connection shows raw replies to help. |
| The tap can't capture or scale some audio (FairPlay in Prime Video, other apps) | Step 17 gate C: silent, or unscaled | Watchdog (L19) tears down on all-zero buffers, so the sound plays unscaled; record which apps; the receiver route is the full answer. |
| Denied or unknown permission silences everything (a muting tap still mutes) | Step 17 run 7 | Engine starts only when preflight says granted; watchdog after 3 s of zeros; Settings shows Not Allowed. |
| Added latency puts lip sync off | Step 17 gate B > 40 ms, step 19 | Engine off at 100 % (no cost unless used); if too high, `softwareVolumeEnabled` default `false` (user decides). |
| HDMI hot-plugs cause rebuild storms or a stuck output | Step 17 gate E, step 19 | Tear down at once, rebuild 2 s after the last event; 10 s receiver hysteresis; if stuck, record it and keep the engine off until the next volume press. |
| Passthrough (hog mode, non-mixable) conflicts with the engine | Step 17 run 4 | Engine off while another pid hogs the output or the stream is non-mixable; never runs with a receiver ready. |
| macOS re-asks for System Audio Recording periodically, or the TCC SPI changes | A prompt on the TV after weeks; preflight symbol missing | Missing symbol → "unknown", engine off, Settings explains. A recurring prompt → record it; user decides (off by default). |
| `INFOPLIST_KEY_NSAudioCaptureUsageDescription` isn't emitted | Built Info.plist lacks the key | Partial `INFOPLIST_FILE` with that key only (pbxproj build setting). |
| A crash leaves sound at full level suddenly | MMTVL quits while scaled | Accepted (`.mutedWhenTapped`: never stuck silent); documented in CLAUDE.md. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

### 2026-11-06, step 1 results (probes on the mini, user at the TV, Remote Buddy not running)

Probes: `scripts/probes/` (`gc.swift`, `hid-seize.swift`, `cec.swift`, `pioneer-write.py`), compiled and run over SSH in `/tmp/mmtvl-probes/` on the mini (macOS 26.6.2). Raw output was kept in the session scratchpad (not in the repo).

- **GameController:** `GCController.controllers()` stayed at 0 for 30 s while the remote (product 789) was connected and buttons were pressed. **L10 is not needed** (a command-line probe; MMTVL's own `ControllerInput` logged no connect either).
- **Seize:** all 7 interfaces open with `kIOHIDOptionsTypeSeizeDevice` → `0x0` (no prompt). Seized, these arrive on 0x0C/0x01 with press 1 / release 0, as M7e's table: Play/Pause 0xCD, right 0x45, left 0x44, up 0x42, down 0x43, centre 0x80, TV 0x60, Back (page 0x01) 0x86, Siri 0x04, Power 0x30.
- **Seized, Vol+ / Vol− / Mute never reach the seizing client, and macOS still shows its own volume HUD** (two seized runs). Not seized, they arrive (0xE9, 0xEA, 0xE2 on 0x0C/0x01) and macOS shows the HUD too. So L1's "seizing stops macOS's own volume HUD" is wrong for volume. The remote's HID services include `AppleEmbeddedBluetoothButtons` (an event driver on an `IOHIDInterface` of the remote, `hidutil list`), which is the likely path; **unverified**. → *Question 1* below.
- **Play/Pause seized:** Music didn't open; nothing on screen. **Power seized:** the Mac didn't sleep, lock or show anything (`PowerButtonSleepsSystem` isn't set on the mini). **Power gate: passes without the loginwindow setting.**
- **Display sleep:** `pmset displaysleepnow` → the TV showed "no signal" and stayed on, the receiver stayed on; `caffeinate -u` brought the picture back. macOS sends **no CEC standby** on display sleep.
- **CEC gate: closed.** `IOCECInterfaceCreate` and `…CreateWithService(IOAVCECService)` return NULL: `IOServiceOpen` succeeds, the user client's open (selector 0) returns `0xE00002C5 kIOReturnExclusiveAccess`; corercd (pid 205) holds the only `IOCECUserClient`. corercd's own client API (`CoreRCManagerClient`, mach service `com.apple.corercd`) names private entitlements (`com.apple.private.cecd.*`), which a Developer-signed app can't have (whether corercd checks them per call is **unverified**). No frames were sent. Same result on the dev Mac.
- **Pioneer writes (VSX-01TXH, `/dev/cu.usbserial-XXXXXXXX`):** `VD` → `VOL60`, `VU` → `VOL61` (one step = 1 dB in the 2-digit scale), `MO` → `MUT0`, `MF` → `MUT1`, `PF` → `PWR1`; from standby the first `PO` gets no reply and the second `PO` → `PWR0`, as documented. After power-on it sends unsolicited lines not in the table (`SR0219`, `LM219`, `SR0000`, `LM128`, `SR0009`), and once a reply came with garbage bytes before it (`P\xff\xff\xff\xffPWR0`): the parser must find the known prefix inside a line and ignore the rest. In a second cycle (15 s off) `PF` got no reply although the receiver turned off: the controller must not treat a missing reply as failure for power commands.
- **The TV doesn't follow the receiver's power** (15 s cycle: receiver off and on, TV stayed on). Only the TV turning off turns the receiver off (2026-11-05). With CEC closed, MMTVL can't turn the TV off or on: Power can turn the receiver off and sleep the displays ("no signal"), nothing more.
- **Mac sleep** (`pmset sleepnow`, no root needed; the pmset log shows "Entering DarkWake state due to 'Software Sleep'"): the TV showed "no signal" and stayed on, so did the receiver. macOS sends no CEC standby on system sleep either (with this TV and receiver). Woken with the keyboard.
- **Volume decision (user, 2026-11-06):** keep the seize; MMTVL's `GlobalEventTap` catches the system volume/mute key events (from the remote, and the Mac keyboard's volume keys too) and consumes them when a receiver is set up, sending them to the receiver with the toast. **Unverified** until TV build 1 that the tap sees the remote's volume events while it is seized. → step 2 updates L1, L3, step 4 and step 10.
- **TV power:** the user asked whether CEC can still work in combination. **corercd's client API is closed too** (`scripts/probes/corerc.m`, ObjC, run read-only on the dev Mac and the mini): `[[CoreRCManager alloc] init]` (a `CoreRCManagerClient`, NSXPC to `com.apple.corercd`) connects, but `queryBusesAsync:` replies `NSOSStatusErrorDomain -6773` with no buses, on both Macs. corercd accepts every connection and checks entitlements per call (82 of its 84 client methods call `corerc_checkEntitlement:` with `com.apple.private.cecd.control`, `.private`, `.observer` or `.logging`; standby and active source need `.private` and `.control`). A Developer-signed app can't have `com.apple.private.*` entitlements. No frames were sent. **CEC from MMTVL is not possible on this Mac** (IOCEC: exclusive access; CoreRC: private entitlements): step 9 is skipped, L13 takes its fallback.
- **TV network control (user request, 2026-11-06; Panasonic TC-P55VT50, on Wi-Fi, a DHCP address on the LAN; address kept out of the repo).** With the TV's Network Link Settings → TV Remote App on, it serves `http://<tv>:55000/nrc/ddd.xml` ("VIERA VT50", `urn:panasonic-com:service:p00NetworkControl:1`, actions incl. `X_SendKey`, `X_SendString`, `X_LaunchApp`) and `/dmr/ddd.xml` (UPnP RenderingControl, ConnectionManager, AVTransport). It didn't answer an `ssdp:all` M-SEARCH from the mini (only one device on the LAN answered), so discovery needs a different ST or a typed-in address (**unverified** which ST it answers). No pairing or encryption (a 2012 model): read-only `GetVolume` → 12 and `GetMute` → 0 on `/dmr/control_0` in ~20 ms; `X_SendKey` `NRC_POWER-ONOFF` on `/nrc/control_0` → 200 and the **TV turned off**, and the receiver followed it off (the TV's own CEC). In standby the TV's network is down (port 55000 times out), so the same key can't turn it on. **Wake-on-LAN** (the TV's setting is on): magic packets to its Wi-Fi MAC, unicast and broadcast, from both of the mini's interfaces, ports 9 and 7, every 2 s for 30 s → no wake. The user is wiring the TV to Ethernet to retest WoL.
- **Receiver after the TV turned it off:** `?P` answered `PWR0` (on) while the receiver looked off; it came on at the next `PO` pair (no replies to either `PO`). So after a CEC standby from the TV, Pioneer's `?P` can't be trusted to mean "on". L14's "on or off" choice must not depend on `?P` alone.

### 2026-11-06, step 3 (QA PASS after two fix rounds; full suite 932 tests passed)

- Small additions beyond the plan, in scope: the migration is a pure `KeyBindings.migrated(fromRevision:)` (tested) that `migrateBindings` calls; `KeyBindings.canSetGlobal(_:)` is static; `adding` makes any Siri Remote trigger global (L2). Exhaustive switches over `RemoteCommand` gained ignore cases in OnScreenKeyboard, GuideModel, YouTubeKeyMap, LauncherFocusModel, LiveSearchModel, AppRouter, PINPad, LiveMenu, SettingsModel, LiveTVModel (player and Multiview return `.handled`, like other unused commands).
- **QA major (fixed):** a rollback to a pre-M7h build (`deploy-mm.sh --rollback`) moves the whole revision-3 `key-bindings.json` to `.bak` (the old build can't decode `siriRemote`) while `settings.json` keeps revision 3, so the next forward install has no Siri Remote bindings. Fix: entries are decoded one by one (an unreadable entry is skipped and logged, not the whole file), and a file without any Siri Remote trigger gets the Siri Remote defaults at launch (`No Siri Remote buttons; added the defaults`, category `Input`). Custom bindings the old build discarded stay in `key-bindings.json.bak` (the old build can't be changed). Second QA round: an array whose entries are all unreadable counts as corrupt again (`.bak` + defaults), and a file with skipped entries is copied to `.bak` before the first save. **Accepted** (user's off switch is step 4's `siriRemoteEnabled`): someone who deletes every Siri Remote binding gets all 12 back at the next launch.
- **QA minor (fixed):** `settingGlobal(false, …)` could make a Siri Remote binding non-global (L2 says always global); it now keeps them global.
- **For step 11 (Settings pages):** (a) L9's text "Letter and number keys only work in MMTVL" on a plain letter/digit binding's Work in Other Apps row (today the toggle shows Off and does nothing); (b) hide Work in Other Apps for Siri Remote bindings (always global; its "Needs Accessibility" text is wrong for the remote); (c) Remote Buttons now lists Volume Up/Down, Mute, Power and Power Menu as rows (Power Menu shows "None": it's a long press, not a trigger) — hide Power Menu or explain it; (d) `canRemove` counts Siri Remote bindings, so the last keyboard Select/Back/arrow can be removed (same as controller bindings today; left as is unless the user wants otherwise).
- For later steps and the security review: a paired phone can already send `power`, `powerMenu`, `volumeUp` … as commands (`RemoteMessage.swift:27` decodes any raw value); they do nothing until L3's routing.

### 2026-11-06, step 4 (QA PASS; security review: one medium, fixed)

- Small changes in scope: `InputRouter.swift` is unchanged (`capture(_:)` already takes any trigger). `SiriRemoteHID.onButton` gets a `ButtonEvent` with a `synthesized` flag; a release made up because the remote went away or reading stopped **sends nothing** (no select, long press or repeat): accepted. `AppDelegate`'s phone `postExternal` is one static function shared with the Siri Remote. `SiriRemoteHID` takes an injectable `System` (manager open/close, next run-loop turn) so its lifecycle is tested.
- **Long presses belong to the physical button** (user decision 2026-11-06): centre held 0.6 s sends `menu` (trackpad: right click) and Power held 0.8 s sends `powerMenu` even when those buttons are unbound or rebound. Step 11's Siri Remote page says so.
- Left for later steps as planned: Home leaving trackpad mode (step 7), the toast and pointer posting (steps 6–7), `onVolume`/`onPower` only log (steps 10, 12).
- **Security medium (fixed):** `SiriRemoteHID.stop()` could tear down the manager from inside the HID value callback (a remote Select turning Siri Remote off in Settings), freeing what IOKit was still using. Now a stop during delivery is deferred to the next run-loop turn (`SiriRemoteHIDTests`). Also fixed: teardown in `isolated deinit`; a removed interface is unregistered and closed; the "needs Accessibility" notice resets per start; `RemoteBattery.productIDs` gains **790** (listed by Apple's `AppleBluetoothRemote.kext`; the list drives both battery and seize).
- **Pre-existing since M5, fixed in M7h (user decision 2026-11-06):** with MMTVL's window showing but not active (Finder in front after Plex quits), the first phone or remote press only brought MMTVL forward and was dropped. The command is now delivered once MMTVL is active: `InputRouter.dispatchFromRemote` (phone and Siri Remote only; the event tap and local monitor keep `dispatch`) keeps the latest non-repeat press during `repairForeground` and delivers it once when the repair succeeds, or first, before a newer press, if MMTVL became active before the repair's check ended (QA major on the fix round, fixed; `ForegroundRepairTests`). A failed or superseded repair drops it. **TV check:** with Finder in front after Plex quits, Down then Select on the phone or remote: MMTVL comes forward and Down lands before Select.
- Security lows for later: (step 12) a paired phone's `power`/`powerMenu` reach MMTVL's screens while it's in front: the power menu must not open from the phone (add a test); (step 16) CLAUDE.md's "`-windowed`: no global input" — the Siri Remote is read and seized in `-windowed` too. **Unverified until TV build 1:** that the value callback's `sender` is the `IOHIDDevice` (as in step 1's probe), and whether opening seized from the app (not SSH) prompts for Input Monitoring.

### 2026-11-06, step 5 (question: which touch surfaces count)

- **Plan is too wide:** "only devices with `MTDeviceIsBuiltIn == false`" also takes a Bluetooth **Magic Trackpad** (the dev Mac has one: not built in, family 129, product 804); its touches would become swipes in MMTVL and other apps. The implementer narrowed it: a surface counts only if it isn't built in **and** its IOKit service (or a parent) has vendor 76 and a product in `RemoteBattery.productIDs` (one more symbol, `MTDeviceGetService`). Dev Mac logs `Multitouch: skipped a surface (family 129, product 804): not a Siri Remote`, `Multitouch: 0 remote surfaces`. **Unverified on the mini:** that the remote's `AppleMultitouchDevice` or a parent carries product 789; if not, swipes would be off in TV build 1. Step 1 measured the remote's surface as family 0x91 (145). → asked the user. **User decision 2026-11-06: product match, with a family fallback:** a surface counts when it isn't built in and either its service (or a parent) is vendor 76 with a product in `RemoteBattery.productIDs`, or no ProductID is found and its family is 0x91; any other ProductID stays out. The accept log line names the rule (`accepted by product` / `accepted by family 0x91`), so TV build 1 shows which one the mini uses.
- QA PASS (993 tests). Minor fixed: the recognizers followed "the first touch", not the same finger, so a second finger taking over made a jump; frames now carry the touch identifier (MTTouch offset 16) and a new identifier starts a new touch (in trackpad mode it also re-decides pointer vs. scroll). **TV check:** the remote must report a steady identifier while one finger stays down, or swipes and the pointer do nothing. **For step 7:** hold pointer moves while a clickpad button is down and briefly after (a click moves the finger; at ×1200 that's 18–70 points, enough to miss the target or `ClickCounter`'s double-click window).
- Choices within L6/L7 (constants in `SwipeRecognizer`/`TrackpadMapper`): flick speed over the last 50 ms of touching frames, +1 step per 2.0 units/s (max 2), a flick needs ≥ 0.1 travel and no click in the touch; the cross axis re-anchors after each step. Scroll: finger up moves content up (like the phone), `dy × −600`. `TouchFrame.timestamp` is `systemUptime` read in the callback (the buttons' clock). Frames with state 3/5 count as not touching.

### 2026-11-06, step 6 (small mechanical change)

- The step's debug trigger (Settings → Siri Remote → Status row) only exists after step 11. Step 6 uses a Debug-only launch argument instead (`-toastDemo "<text>"`, compiled out of Release); step 11 may add the Status-row trigger.
- QA PASS (999 tests). Additions: toast tokens in `Theme.swift` (`Theme.toast*`), a 30 % black scrim inside the glass (white text over a white page was ~2.3:1), a VoiceOver announcement per toast, and the "Trackpad On/Off" toast already wired in `SiriRemoteInput` (L5). Seen live: over Finder/Calculator in front, no focus taken, click-through, gone after ~2.5 s; the demo isn't in Release. **TV checks:** the toast over Plex HTPC full screen (its own Space), legibility from the couch, Reduce Transparency solid.

### 2026-11-06, step 7 (QA PASS; security review: two mediums)

- Additions beyond the plan, in scope: the click hold lives in `TrackpadMapper` (`clickpadPressed/Released`, quiet time = `SwipeRecognizer.clickQuiet`, 150 ms; scroll touches aren't held); `stop()` leaves trackpad mode (with the toast) so auto-hide can't stay off; turning the mode on shows the pointer; moves and scrolls are gated on Accessibility like clicks; "Home leaves trackpad mode" means any Siri Remote press whose binding is `home` (the TV button by default), not phone or keyboard Home. `CursorAutoHide.hides(setting:isTrackpadMode:)` decides auto-hide.
- **Security medium 1 (fixing):** NaN, ±inf or huge touch values from MultitouchSupport (an unverified private struct) would trap in `PointerMath.scrollWheels` / `SyntheticInput.movePointer` and crash MMTVL in trackpad mode. Fix: the recognizers drop non-finite or out-of-range frames, and the shared pointer sinks reject non-finite input for every caller.
- **Security medium 2 (user decision 2026-11-06: keep the pointer off the edges):** a Siri double-press gives the remote holder a mouse in other apps without the PIN; in a full-screen app the top edge reveals the menu bar (Force Quit MMTVL), and the Dock reveals at its edge. While the kiosk lock is in force and another app is in front, the **remote's** pointer is clamped inside the display by `PointerMath.kioskEdgeInset` (6 points to start, tune on the TV) on all four edges. The phone's trackpad is unchanged (pairing is PIN-gated). **TV check:** over Plex full screen, push the pointer into each edge and corner: no menu bar, Dock or hot corner.
- QA minor (fixing): a release past the long-press threshold but before the next 30 ms tick gave the short result (left click / select / power). Security low (fixing): reset the recognizers when the touch surfaces stop or rebuild (sleep, wake), so no stale jump.
- Accepted lows: trackpad mode survives a remote disconnect and sleep (the remote idles off; the mode is kept); the phone and remote share one `ClickCounter`; `stop()`'s "Trackpad Off" toast also shows at quit; hosted tests write real "Trackpad mode on/off" lines to the log store (after a test run, `log show` can look like the remote was used).
- **Fix rounds:** all four fixed. NaN/inf: `TouchFrame.hasValidPosition` (−0.5…1.5) and `maxJump` (**0.4** per frame starts a new touch; 0.3 was tripped by float rounding in a test; the remote's frame rate is unverified, so fast swipes might split: TV check); `PointerMath.accelerated` caps at `maxDelta`, `clamp`/`scrollWheels`/`eventDelta` and `SyntheticInput.movePointer` reject non-finite values for every caller. Long press: `release` returns the long-press event once past its threshold. Reset: `MultitouchDevices.onReset` → `SiriRemoteInput.touchSurfacesReset()`. Edges: `PointerMath.remoteEdgeInset(isLockEffective:)` applies **whenever the kiosk lock is in force, MMTVL in front too** (security re-review: presentation options come back only 1 s after MMTVL activates, so the menu bar could reveal in that second); clicks move inside the inset first; the shared edge of two displays is inset too. Security re-review: findings closed, phone path unchanged. Full suite 1018 tests passed.
- Security lows accepted: 6 pt only stops a hidden menu bar or Dock from revealing; if the mini's menu bar isn't on *Always* auto-hide or the Dock isn't auto-hidden, a windowed app shows them and the pointer can reach them (CLAUDE.md in step 16, TV checklist). Scrolls don't move the pointer inside the inset (harmless).

### 2026-11-06, pre-build pass for TV build 1 (QA PASS; security: one medium, waiting on the user)

- **QA PASS** over `6ea0bd6..HEAD`: Debug and Release build, full suite **1018 tests in 118 suites passed**; `-windowed YES` logs `Siri Remote: no remote connected` and `Multitouch: 0 remote surfaces` (Magic Trackpad skipped); the toast shows over another app without taking focus; `-toastDemo` isn't in Release. Migration run through the real launch path on a copy of the settings folder (restored after): a mini-like revision-2 file loses the global "A" Home and keeps a learned global "Controller a"; rollback-then-forward re-adds the Siri Remote defaults; unreadable entries are skipped with a `.bak`.
- QA minors: (1) `SiriRemoteHID` drops values from an unknown `sender` without a log, so a wrong `sender` assumption would look like "connected, buttons dead"; (2) the scroll edges (x ≥ 0.85, y ≤ 0.12) may be out of reach (M7e measured only 0.20–0.75 in x); a debug log of each trackpad touch's start would settle it; (3) in trackpad mode the clickpad's up/down/left/right still send arrows (L4: only the centre clicks) → user.
- **Security medium M1 (plausible, not run):** with the remote alone (no PIN), trackpad clicks on a link in an allowed tile's app (e.g. `mailto:` → Mail) plus reopening the tile can reach the kiosk guard's 3-takebacks-in-10-s limit, which suspends the guard until Home; the remote's pointer then works in any app. The remote's pointer path checks only `canPost` and the edge inset. → user.
- Security lows: the L9 guard doesn't cover Space, punctuation, keypad digits, Return, Tab, Delete; a global letter added in a rolled-back build isn't removed again (already revision 3); `isRepairingForeground` stays true if `bringForward` never returns (unchecked whether it has a time limit); `OverlayToast` logs its text as public (later receiver/TV error toasts must not carry addresses or serial paths); probes build in a fixed `/tmp/mmtvl-probes/` (deleted in step 16). **Fixed here:** the plan named the mini's FTDI adapter by its serial number; now `cu.usbserial-XXXXXXXX`.
- TV checklist additions (QA): routing lines are **debug** level, so stream with `--level debug` during the check; every interface logs `open: seized` (the 0x0D digitizer too until build 24; from build 25 it logs `left to macOS (touch)`; "not seized" means another client such as Remote Buddy holds it); `Removed global binding A` and `Key bindings updated from revision 2 to 3` after the first launch; with Game Controllers on, TV gives exactly one Home (the learned "Controller a" stays); Power from the app logs `(not wired yet)` and doesn't sleep or lock the Mac, Vol±/Mute still show macOS's HUD (until step 10), Play/Pause doesn't open Music; trackpad bottom-edge horizontal scroll and off-centre presses; buttons logging nothing while connected → the `sender` issue; quitting in trackpad mode shows "Trackpad Off".
- **User decisions 2026-11-06:** M1 → **gate the pointer**: with the kiosk lock in force, the remote's pointer moves, clicks and scrolls act only when MMTVL, an app the guard allows (the tile's app / its browser, `sessionApps`) or Reflector is in front; otherwise nothing is posted (trackpad mode stays on). Off-centre clickpad presses in trackpad mode **keep sending arrows** (L4 as planned; revisit on the TV). QA's two diagnostics are added (unknown-sender log once per run; debug log of each trackpad touch's start). Then TV build 1: build and install on the MM.
- **Fixes done** (QA PASS, full suite **1026 tests in 118 suites passed**; security re-review: M1 closed, nothing medium or above). `KioskGuard.allows(bundleID:isSelf:)` is the guard's one allow rule (`appDidActivate` uses it too); `KioskGuard.pointerGate(isLockInForce:frontBundleID:isSelf:)` ignores suspension; `SiriRemoteInput.post` checks `canPost`, then the gate, and logs `Trackpad: ignored, <bundle id> isn't allowed` (info, once per front-app change). A nil or non-regular front app is blocked (stricter than the guard, which ignores non-regular apps). `SiriRemoteHID` logs `Siri Remote: value from an unknown device, ignored` once per start; trackpad mode logs `Trackpad touch at x, y: pointer|scroll vertical|scroll horizontal` at debug.
- QA minors (open, for the user): (1) with MMTVL's window showing but nothing or Finder in front (after a tile's app quits), the gate blocks the pointer (`? isn't allowed`) until a button press brings MMTVL forward; possible fix: a blocked action in that state calls `repairForeground()` once. (2) The "ignored" notice re-logs only after an allowed action, not on every front-app change or remote restart (diagnostic only). (3) **Unverified:** a system prompt from a non-regular process (e.g. the Downloads access prompt in Tile Art) can't be clicked with the remote's pointer; keys and Home still work.
- Security lows: the gate checks the front app, not the window under the pointer (one click or scrolls can reach a blocked app's window behind a windowed allowed app); `frontmostApplication` can lag a switch by a run-loop turn (about one action); while the guard is suspended the remote's **keys** still reach a blocked app in front (the decision covered the pointer only); the gate's AppDelegate wiring has no test.
- TV checklist additions: with the kiosk lock on, open Mail from a link in a tile's app: the remote's pointer does nothing there and `Trackpad: ignored, com.apple.mail isn't allowed` logs once; the tile's app and Reflector still get pointer, clicks and scrolls; after a tile's app quits, touch the surface before pressing anything (QA minor 1); stream `--level debug` and start touches at the right and bottom edges to read `Trackpad touch at …`; `value from an unknown device` should never appear.

### 2026-11-06, SoundSource (for step 10 and build 2)

- SoundSource runs on the mini with `keyboardVolume = 1` in `com.rogueamoeba.soundsource` (probably Super Volume Keys; read over SSH). It and L3a's event tap both want the volume key events: whichever tap sees them first can consume them, so with the receiver set up the remote's Vol± may never reach MMTVL (or SoundSource stops reacting). **Unverified**; step 15 checks it. The "macOS volume HUD" in step 1 may have been SoundSource's. Its software volume also stacks with the receiver's (keep it at 100 %).
- **User direction (2026-11-06):** MMTVL shouldn't rely on SoundSource. With a receiver over serial (or CEC, if step 14b opens it) SoundSource isn't needed; for setups with neither, MMTVL should get its own system-wide software volume instead of SoundSource's. Not in M7h's scope as planned; where it goes is the user's call (see the chat of 2026-11-06).

### 2026-11-06, step 8 (QA PASS after one fix round; full suite 1077 tests passed)

- Small additions in scope: all six codecs (Anthem and NAD too); `ReceiverProtocol.lineDelimiters` (replies end differently from commands: Pioneer CR LF, Onkyo 0x1A, Anthem `;`); `ReceiverWakeRule` = `onOpen` bytes (Pioneer's bare CR, sent once per opened port and before every Test and Find pass), `powerOnCount`/`powerOnRepeatGap`, `pauseAfterPowerOn` (Denon 1 s); `probeQueries` default = power, volume, mute queries; gaps Onkyo 60 ms, Anthem and NAD 50 ms (**unverified**, no source gives one). `ReceiverStatus.volume(raw:)` is the brand's own number (not comparable, not a level): **step 10 uses `dB` only**. Ports are logged by USB product name, never the device path. `SerialPort` takes `TIOCEXCL`. `AppDelegate.setUpReceiver()` runs in kiosk and `-windowed`; brand `none` logs `Receiver: not set up` and opens nothing; `network` logs "not supported yet" (step 8b). **For step 11:** `applySettings` doesn't re-apply receiver settings live yet.
- QA minors (fixed): Find reopened the old port after a `stop()`/`configure()` during the search (and could loop reconnecting forever): a config generation token now guards the restore and the reconnect loop, and a successful connect cancels the loop; a command queued before a reconfigure is dropped (no old-codec bytes on the new port); a hand-edited `receiverSerialPort` must be `/dev/cu.<name>`, else Automatic. Re-check minor (open): the test `reconnectLoopStopsAfterAnyConnect` passes without the new cancel in `connect()` (that cancel guards future code only).
- **Unverified (step 15, the mini):** termios on the FT232R, unplug behaviour (EOF vs ENXIO), the exclusive-lock handover between Find's brands, Pioneer's wake from standby during Test; a bare CR or other brands' queries being harmless to non-Pioneer receivers (Pioneer is tried first, so the user's receiver only ever gets Pioneer bytes).

### 2026-11-06, software volume (steps 17–19 planned; open questions)

- User decision: software volume at the end of M7h (steps 17–19); research in *Software volume* above, L19. Recommendation: Core Audio process taps, not an AudioServerPlugIn.
- Open questions for the user:
  1. **Off at 100 %** (no tap, no latency until the first Vol−) and the **10 s receiver hysteresis**: OK?
  2. `keys` simply removed (reads as `auto`, no migration): OK?
  3. Using the private TCC preflight/request (like MultitouchSupport), with the watchdog as a backstop: OK, or public-API only (the engine's first start triggers the prompt, the watchdog catches a denial)?
  4. Where Settings shows it: a **Without a Receiver** section on Receiver & TV (proposed), or its own Volume page?
  5. Uninstall SoundSource on the mini right after step 15 (before the probe)? Until step 18 ships, the mini has no HDMI volume except the receiver.
- **User answers (2026-11-06):** (1) off at 100 % and the 10 s receiver hysteresis: yes. (2) `keys` removed, an old value reads as `auto`: accepted with question 5. (3) the private TCC preflight/request, with the silence watchdog as backup: yes. (4) Settings: a **Without a Receiver** section on Receiver & TV. (5) SoundSource is uninstalled on the mini **after step 15's TV checks** (receiver volume working), before step 17's probe.

### 2026-11-06, step 8b (QA PASS and security re-review after one fix round; full suite 1129 tests passed)

- **Untested on a real networked receiver** (none in the house); SSDP search got no replies on the dev Mac (no UI to run Find on Network until step 11).
- In scope: `ReceiverLink` (`.serial(path:)` / `.network(host:port:)`) with per-link reconnect delays (serial 5 s; network 1, 2, 5, 10 s); `networkPort` + `networkFallbackPorts` (Pioneer 23, then 8102) + `networkFraming` (`EISCP.frame`/`Deframer` for Onkyo); `ReceiverTCPTransport` (keep-alive, 2 s per port, `.waiting` = refused); `ReceiverController.probe` shared by serial Find and `ReceiverDiscovery.find` (Find on Network, returns every receiver that answered; step 11 chooses); the 5-minute idle close and on-demand reopen in the controller's existing generation logic (commands during the backoff fail at once). The SSDP sender, description parser (UDN, friendlyName), fetcher and `LANAddress` are reusable by step 9b. A Pioneer manufacturer is tried as `pioneer`, then `onkyo` (2016+ ISCP). Swift 6.4 crashed on the async URLSession redirect delegate, so the completion-handler form is used.
- **Security medium (fixed):** "LAN only" admitted the Mac's own loopback (`fe80::1%lo0` from an attacker's `LOCATION`, confirmed; `.local` names via mDNS, plausible). Now: discovery fetches only LAN IP literals (no names, no zones) that equal the reply's source address; loopback zones are refused; the TCP transport prohibits loopback and checks the resolved remote endpoint on `.ready` before anything is written (seen live: a LAN IP connects, a public name and `localhost` are refused). Security low (fixed): the backoff resets only after a reply or 10 s up. QA minors (fixed): backoff reset on idle reopen; "no connection to host:port" for links that never came up; `[v6]:port` in logs; a wrong-typed `receiverNetworkPort` no longer sends `settings.json` to `.bak`. **`receiverHost`:** see *New settings keys* (DNS names allowed, checked when connected).
- Open lows (follow-up fix, below): a name resolving outside the LAN is retried on the backoff for 5 minutes (a TCP handshake every ~10 s, nothing written); a spoofed reply with the Mac's own LAN address as source could aim the description fetch at the Mac's wildcard listeners; `AppDelegate` logs a refused `receiverHost` in full. Accepted: a hostile configured receiver that replies once and closes is reconnected every 1 s until the idle close. **For step 10:** coalesce held volume repeats while a connection comes up (`waitUntilReady` queues them). **For step 11:** keep the last connect error for Test Connection ("Connection refused"). **Possible follow-up:** Onkyo/Integra's own UDP discovery (`!xECNQSTN` on 60128) if they don't answer SSDP (not planned).
- **Follow-up fixes** (QA PASS, full suite 1132 tests passed): a transport refused at `.ready` (resolved off the LAN, or a loopback path) sets `closedForConfiguration`; the controller then stops reconnecting, doesn't reopen after the idle close, and only `configure` clears it (seen live with a public-resolving name). Discovery refuses LOCATIONs naming the Mac's own interface addresses (`LANAddress.ownAddresses()`; MMTVL's own DIAL reply drops out). The `receiverHost` refusal log gives only its length. Noted: the Mac's own LAN IP or `localhost` as `receiverHost` never reaches `.ready` (loopback prohibited → `.waiting`), so it takes the ordinary backoff with "no connection"; harmless, nothing connects.

### 2026-11-06, step 9b (QA PASS and security re-review after one fix round; full suite 1179 tests passed)

- **Untested on the TV** (step 15). Nothing was sent to a real device. A read-only M-SEARCH from the mini for `p00RemoteController` got no reply (the TV was probably in standby, its network down); whether the VT50's UDN node is its **wired** MAC (step 1 ran on Wi-Fi) stays a step 15 check: if not, Find fills a MAC that can't wake it.
- In scope: `PanasonicViera` (fixed bodies from `VieraKey`, one case; the **compact** SOAP 1.1 envelope as in the `panasonic_viera` library, since step 1's exact bytes weren't recorded; any 200 without a fault counts as sent); `WakeOnLAN` (`MACAddress`, unicast only; UDN → MAC only for version-1 UUIDs, which the VT50's `…-1000-…` is; targets = the subnet broadcast of usable interfaces on the TV's subnet + the TV's address); `TVController` (clock, connect, SOAP, wake, search, fetch injected; SOAP only to the IPv4 literal the 1 s check reached; `powerOn` every 2 s from the start, gives up at 30 s, stopped by `configure`/`powerOff`). IPv4 only: an IPv6 `tvHost` is refused ("TV: an IPv4 address or name is needed"). `TV: not set up` at launch with brand none; nothing is sent at launch. The MAC is never logged.
- Security lows (fixed): WoL only on broadcast-capable, non-point-to-point interfaces, never `utun`/`ipsec`/`ppp`/`bridge`/`vmnet`/`gif`/`stf`/`awdl`/`llw`; no system proxies for the TV, the description fetcher (8b) or `ReceiverTCPTransport`; SOAP faults logged by numeric code only; an off-LAN refusal latched until `configure`; `localhost` and the Mac's own addresses refused. QA minors (fixed): compact envelope, IPv6 refused, empty 200 = success, wrong-typed TV and receiver keys no longer send `settings.json` to `.bak`.
- Accepted: a LAN host answering mDNS for a `.local` `tvHost` with an off-LAN address switches TV control off until the settings change or a relaunch (availability only). `powerOn` sends one round of LAN broadcasts before its first check. **Unverified:** that `connectionProxyDictionary = [:]` also bypasses a PAC proxy. Follow-up low (fixed, full suite 1180 tests passed): ZeroTier `feth*`/`zt*` and OpenVPN `tap*` adapters are excluded from WoL by name too.

### 2026-11-06, step 10 (QA PASS; security: one medium; fixes in progress)

- **User decision (2026-11-06): a volume cap.** MMTVL's volume buttons (Siri Remote, volume keys, phone) never step the receiver above `receiverMaxDB` (Double, default **0 dB**; new key in *New settings keys*); step 11's Receiver & TV page gets a **Maximum Volume** row. Vol+ at the cap sends nothing; the toast says "Volume 0 dB (max)". The receiver's own remote and knob are unaffected. A brand that reports no dB (Onkyo) can't be capped (noted in Settings).
- **Done** (QA PASS and security re-review after two fix rounds; full suite **1223 tests passed**). "Receiver ready" = `ReceiverController.isAnswering`: set up, link open/coming up or closed only for idle, a line parsed since `configure`, and the last request answered. The tap decides from that cached state (never waits). The first press after a receiver goes silent is consumed and shows "Receiver isn't answering"; the next falls back to D25's order; a read-only `queryVolume` probe (at launch, on each link-up, and after a fallback press, at most every 10 s from any source) brings it back. Presses wait one at a time for their reply: at most one waiting Vol± (latest wins; a replaced press is answered at once with the last known state) and one waiting Mute (parity kept, never replaced), run in the order they were filled. Mute toggles from the known state (`?M` first when unknown). Phone feedback: −80…0 dB → level 0…1 (clamped); −∞ (`VOL00`, `MV00`) → level 0 and the toast "Volume Min"; no dB (Onkyo) → level unknown. Toasts on Siri Remote and volume-key presses only. `VolumeKeyTracker`: a key-up and repeats follow their key-down; repeats of a taken key are dropped once the receiver isn't ready. `PhoneRemoteEnvironment.volume` takes a completion. `VolumeController` logs in category `Volume` (debug per press). SoundSource and the `keys` route stay until step 18.
- Fixed in review: **security medium** — an implausible dB reply (e.g. NAD `Main.Volume=1e18`) trapped the `Int` conversion and, with the launch probe, crashed MMTVL at every launch; dB outside −100…+30 is now ignored. **Security medium** — the link-up probe counted as activity and its reply reset the backoff, so a host that answers and closes was reconnected every second forever; probes no longer count as activity, share the 10 s interval, and link-up probes never reopen an idle-closed link. Lows and QA minors: bounded waiting presses; Mute never lost or collapsed; a probe when the link comes up; a 1.5 s ready wait for volume; −∞; quieter logs; press order; "(max)" with the real level.
- Open (minor, rare): a passive probe that can't be written because the idle close fired meanwhile marks the receiver "not answering"; the next press falls back and its probe recovers it within 10 s. Unverified (step 15): the seized remote's volume reaching the tap; Pioneer's answers in standby and after the TV's CEC standby; whether Pioneer unmutes on a volume step; the cap landing on 0 dB; SoundSource's tap vs MMTVL's; non-Pioneer brands answering set commands; the Pioneer `VOL<digits>` match against zone replies. **For step 16:** CLAUDE.md's `phoneRemoteVolume` values gain `receiver`; document `receiverMaxDB` and the `Volume` log category.

### 2026-11-06, step 11 (QA PASS after one fix round; full suite 1275 tests passed)

- Pages: Remote & Input → **Siri Remote** (toggle, Status with battery and touch, "How it works" incl. step 4's long-press note; Debug: Select on Status shows the toast) and **Receiver & TV** (Brand list with years and the "Tested with Pioneer" footer; Connection as a two-value row, as the step says (*Settings pages* said push); Serial Port list incl. a configured port that isn't plugged in; Address on an on-screen keyboard page (D41) that starts on digits for numeric addresses; Test Connection; Find Receiver / Find on Network with a **Receivers Found** chooser; **Maximum Volume** as a push list, −30…+10 dB in 5 dB steps plus any hand-edited value, with an Onkyo "no limit" note; Status; a TV section: TV list, Address, Find TV, Test TV, MAC Address info row, footer). Find appears even with brand None (so it can set the brand); Test, Maximum Volume and Status need a brand. Remote Buttons: L9's text on plain letter/digit Home bindings, no Work in Other Apps for Siri Remote bindings, no Power Menu row (the footer explains long presses); `canRemove` unchanged. Game Controllers' description no longer mentions the Siri Remote.
- Wiring: `applySettings` re-applies receiver and TV settings live (only on changes to their own keys; brand None closes the port); `ReceiverController.lastConnectError` with plain reasons ("Connection refused", "No answer", …) for Test Connection and Status; `ReceiverController.onLinkChange` and `SiriRemoteHID.onConnectionChange` refresh Settings, coalesced to one refresh per main-actor turn (seen live: Status moves from "Waiting for an answer" to "No answer"). Debug-only `-settingsDemo "<page path>"` / `-settingsDemoFocus <row id>` launch arguments (for screenshots with a locked screen; compiled out of Release, checked with `strings`).
- Accepted: phone text and the Mac keyboard's letters don't type into the address page (only the on-screen keys, D41). **User decision pending (not now):** with several VIERAs, Find TV takes the first with a MAC (no chooser).
- **TV checks (build 2):** legibility of the new pages and the keyboard page; Test/Find on the real serial port and the VT50; live re-apply reconnecting after a brand or port change; Status following a failing or dropping link and the remote waking and idling off with the page open.

### 2026-11-06, step 12 (QA PASS and security re-review after four fix rounds; full suite 1331 tests passed)

- **User decisions (2026-11-06):** (1) Cancel/Back on a power menu opened over another app (Plex) hands the screen back to that app. (2) Power and Power Menu are learnable again in Settings → Remote Buttons (step 11 had hidden Power Menu; without a Siri Remote, Sleep and Restart were unreachable). (3) A paired phone may drive a power menu someone else opened (Turn Off and Sleep; Relaunch and Restart still need the PIN): accepted.
- Accepted (security low, behind the PIN): Restart quits MMTVL before the restart is certain (`willPowerOff` → `allowsTermination`); if another app cancels the restart, the Mac stays up without MMTVL. Same for a relaunch whose old process outlives the helper's 10 s.
- Built: `AVControl/PowerController.swift` (L14 with injected effects; `pmset` through `Process` with fixed arguments, `kAESleep`/`kAERestart` (`'rest'`) to loginwindow sent off the main actor with failure toasts, `IOPMAssertionDeclareUserActivity`; a press during a running sequence is ignored with a toast; the output device logged 10 s after power-on), `Launcher/PowerMenu.swift` + `PowerMenuView.swift` (a top-level overlay in `LauncherRootView` above every screen, Theme tokens; `Theme.menuDim` now shared with LiveMenu), `Launcher/PowerMenuPresenter.swift` (Power/Power Menu routing for the Siri Remote and global keys; remembers the app the menu opened over). `PINPurpose.relaunch`/`.restartMac`. `NSAppleEventsUsageDescription` added. A paired phone's `power`/`powerMenu` are dropped. Power and Power Menu are learnable again in Remote Buttons and can Work in Other Apps (L9 unchanged); repeats of either do nothing. The menu stays open during Reflector mirroring. Debug-only `-powerMenuDemo`/`-powerMenuDemoCommands` (actions only log).
- Review fixes: Cancel/Back returns only to an app the kiosk guard allows while the lock is in force (security medium: a refused app could be re-activated to trip the guard's suspension), with a matching non-nil bundle id. Opening the menu doesn't end Exit to Desktop; while exited, Cancel returns then re-hides MMTVL, an item/Power/goHome re-hides it, a Relaunch/Restart PIN screen or Home ends the exit (security medium: MMTVL could be left in front with the lock off). Home while MMTVL is active now always ends Exit to Desktop (also closes the older ⌘Tab-then-Home variant).
- Accepted lows: the phone can drive an open menu (user decision); the restart/relaunch gap behind the PIN; after ⌘Tab into MMTVL while exited, a cancelled menu hides MMTVL again. **Unverified (build 2):** whether macOS 26 asks for Automation consent to send to loginwindow; Cancel over Plex full screen returning to Plex; the menu during mirroring; the real Sleep/Restart; `pmset` from the app; the output-device log line.

### 2026-11-06, step 13 (QA PASS after one fix round; security: nothing medium+; full suite 1358 tests passed)

- Built: `App/DisplayHotplugMonitor.swift` (CoreGraphics reconfiguration callback → pure `HotplugEvent` → main actor; logs `Display <id> added|removed`, category `Display`); `AppLauncher.noteDisplayChange(frontmostBundleID:)` marks running, non-frontmost apps in `restartAfterHotplug = ["tv.plex.htpc"]`, remembering their pids; the next open of a marked app takes its pids out of `launchedPIDs`, `terminate()`s them, polls up to 5 s, `forceTerminate()`s, waits up to 1 s more, then opens as usual (`Restarting tv.plex.htpc after a display change`). `PowerController.onPowerOn` marks Plex the same way. The kiosk guard is told about the open before the restart, so the new Plex is a session app. Workspace effects are injected (`LauncherWorkspace`).
- Review fixes: a second open while Plex is restarting opens nothing (QA major: it reattached to the dying instance, whose exit sent MMTVL Home over the new Plex); a mark restarts only a still-running marked pid (security low); a pid that outlives the force quit is opened but not tracked; the home/carousel exit waits for the restart before its fallback timer (no bounce); the monitor sets itself active only after registering and stops in `deinit`.
- Accepted lows: a reused pid force-quit within milliseconds; log lines per hot-plug; an impostor app claiming Plex's bundle id (needs code running as the user). Plex in front during a hot-plug or power-on isn't marked (L16; every black screen followed a hot-plug with Plex in the background). `aPlexRestartHoldsTheHomeExit` uses real-time margins (~100 ms); passed 15 runs incl. under load.
- **TV checks (build 2):** TV off/on with Plex in the background → `Display` added/removed and `will restart on its next open`; opening Plex → `Restarting tv.plex.htpc…`, Plex draws, MMTVL doesn't jump Home; double Select during the restart; the carousel art holding until Plex appears; Power off/on marks Plex too; how long Plex takes to quit.

### 2026-11-06, pre-build pass for TV build 2 (QA PASS; security: nothing medium+)

- QA over `0fb66af..HEAD`: Debug and Release build; full suite **1358 tests passed**; a mini-like launch (no receiver/TV keys) and a clean-state launch open no serial port, send nothing to a TV, make no outgoing connection, leave `key-bindings.json`/`settings.json` byte-identical; the Debug demo arguments are absent from Release (`strings`). The power menu draws over the new Settings pages.
- **User decisions (2026-11-06), amending L14:** (1) every short Power press **checks the TV first** (≤ 1 s): if a set-up TV answers, the press turns everything off, even after an MMTVL power-off (`poweredOffByMMTVL` only decides when no TV is set up); (2) after a power-on, **MMTVL's home screen comes to the front** (like an Apple TV waking), and a running Plex is marked for restart (it was put in the background by this, after the hot-plug). User OK for build 2 (build 24) and installing it.
- Fixing before the build: a TV set up without a MAC no longer toasts "TV Didn't Turn On" at every power-on; Settings' learning capture comes before the volume-key path (volume keys can be learned while the receiver answers); SSDP discovery skips the same VPN/bridge interfaces Wake-on-LAN does.
- Accepted / noted: live re-apply during a power sequence aborts that sequence (the next press recovers); Find Receiver on a serial port holds the receiver queue ~12 s (volume keys go to macOS meanwhile); Find TV takes the first VIERA with a MAC; anything answering at `receiverHost` gets the volume keys (capped). **For step 16:** CLAUDE.md log commands and never-log rules for `Receiver`, `TV`, `Power`, `Volume`, `Display`; the `Power: default output <name>` line.
- **Build 2 checklist** = step 15 + the per-step TV notes (steps 8–13) + QA's list: first launch (`Receiver: not set up`, `TV: not set up`, no migration line, remote still seized); Power with nothing set up (displays only); a second press during a sequence (toast, ignored); a slow-answering TV; Power off → TV on by its own remote → Power (now turns off); Vol± during a power sequence; Vol± during Find Receiver; live re-apply (brand/port changes with the page open); Test Connection right after power-off (Pioneer in standby); Mute from the receiver's own remote (state follows `MUT`); `pmset displaysleepnow` alone — does it report a display add/remove (would mark Plex after every display sleep?); power-off over Plex then on (MMTVL home, Plex restarts on open); the power menu over YouTube, Live TV, Multiview and the Address keyboard page; first Sleep and first Restart (Automation prompt?); Relaunch with the PIN; SoundSource vs MMTVL's tap for Vol± (record before uninstalling); no MAC, `/dev/cu.*` or full URL in the logs.
- **Fixes done** (QA PASS, full suite **1368 tests passed**; security: nothing medium+): every Power press checks a set-up TV first; power-on marks a running Plex (even in front, `AppLauncher.notePowerOn`) and goes home from anywhere right after the displays wake (`goHomeFromAnywhere(reason: "powerOn")`, like a global Home: ends Exit to Desktop and mirroring, clears the guard's session apps); a TV without a MAC is skipped quietly; the event tap's learning check comes before the volume path (a volume press while learning goes to macOS; volume keys stay unlearnable, not needed); SSDP replies only from a source on a usable (non-VPN/bridge) interface's subnet (link-local refused). Lows accepted: a set-up TV that never answers makes every press "on" (30 s of WoL; the menu's Turn Off still works); a VPN overlapping the home subnet; a stale comment on learning (step 16).
- Build 2 checklist additions: power-on from Plex, Live TV and after Exit to Desktop — MMTVL's home fills the TV once it's up; pull `Foreground`/`KioskWindowController` (power-on runs before the TV's display exists: watch for a Dock restart or a misplaced window; fallback: go home after `tv.powerOn()` returns or on the display-add) and `KioskGuard` (takebacks of a Plex that comes forward by itself); opening Plex logs `Restarting … (power on)`. Power-off during Live TV full screen: does mpv keep streaming until power-on? Find TV with the new subnet rule.

### 2026-11-07, build 24 TV checks: volume and trackpad (from the user and the MM's log)

- **Volume ("Volume can't be changed here", SoundSource quit by the user):** not a code fault. The MM's `settings.json` has `receiverBrand: "none"` and `tvBrand: "none"` (last written 2026-11-06 16:00), so no receiver is set up; with SoundSource gone, `VolumeRoute.choose` (`App/Volume.swift:15`) falls to `system`, which HDMI can't set, then `unavailable` while Finder was in front (the toast logged 9 times at 23:15:49–53; no `Receiver` or `Volume` lines since launch). The receiver's port is there (`/dev/cu.usbserial-…`). Needed: the user sets up Settings → Remote & Input → Receiver & TV (Brand Pioneer, Connection Serial, Serial Port automatic), Test Connection, then Vol± again. Software volume for the no-receiver case is still steps 17–19.
- **Trackpad (toast shows, nothing moves):** the remote has **no touch surface**. The log: `Multitouch: 1 remote surfaces` at 08:04:47 (a wake restart, the remote stayed connected), then the remote really disconnected at 10:54:37 (Mac in Deep Idle), reconnected at 11:09:57 during a DarkWake, and every rebuild since logged `Multitouch: 0 remote surfaces`. `ioreg` on the MM now: every remote interface has its `AppleBluetoothRemote.kext` driver (Buttons, DeviceManagement, Proximity, Audio, Infrared, Radio) **except the digitizer (0x0D/0x01), which has no `AppleEmbeddedBluetoothTouch`**, so no `AppleMultitouchDevice` exists for MultitouchSupport to list. MMTVL seized 0x0D/0x01 at 11:09:57.53, the first interface to appear, before the touch driver started. Most likely cause: **the seize of the digitizer interface keeps the kernel's touch driver from starting** on a fresh connection (at build 24's first launch the remote was already connected, so the driver was already running). **Unverified** (the mechanism is from the evidence only, not from IOHIDFamily's source or a controlled test). MMTVL reads nothing from 0x0D (touch comes through MultitouchSupport; `buttonPages` is 0x0C and 0x01 only), so seizing it buys nothing. Fix: `SiriRemoteHID.deviceMatched` leaves the digitizer interface unopened. Kernel matching isn't retried, so the fixed build's check needs a real reconnect of the remote (the Mac sleeping until the remote drops, as at 10:54) and then `Multitouch: 1 remote surfaces`. Swipes are affected the same way.
- Fixed (2026-11-07): `SiriRemoteHID.deviceMatched` leaves the 0x0D interface unopened (`shouldOpen(primaryUsagePage:)`, notice line `Siri Remote interface 0x0D/0x01 left to macOS (touch)`); QA PASS, full suite **1371 tests passed**. **TV check (QA):** with 0x0D no longer seized, touching the surface outside trackpad mode must not move the cursor or scroll in MMTVL, Plex or the browser.
- **Receiver set up (2026-11-07):** Vol± works through the receiver (1 dB a press, the toast matches the receiver's display), but the user finds −28 dB far too quiet. The Mac's side is at full level: the default output is the VSX-01TXH (HDMI, 8 channels, stereo on channels 1–2, no volume or mute controls; probe over SSH), and nothing was playing at the time. **SoundSource's saved Output volume is 0.1875** (`~/Library/Application Support/SoundSource/Models.v2.plist`, about −14.5 dB), and its ARK driver is still loaded with SoundSource quit (`/Library/Audio/Plug-Ins/HAL/ARK.driver`, `arkaudiod --agent`, both running since 2026-11-05). Likely cause: ARK still applying that level. **Unverified.** User asked whether to uninstall SoundSource and ARK now: yes. That was already the plan after step 15, and the SoundSource-vs-tap check it was waiting for is moot (Vol± now goes to the receiver). Turn the receiver down before uninstalling, since the level may jump by about 15 dB. Afterwards, compare −28 dB with before; this also starts step 19's hot-plug comparison without ARK.
- **SoundSource uninstalled (2026-11-07):** still quiet after the uninstall; **normal after rebooting the MM** (ARK lives inside coreaudiod until it restarts). After the reboot `/Library/Audio/Plug-Ins/HAL/` holds only `ParrotAudioPlugin.driver` and no `arkaudiod` runs. So the level was ARK's (likely; nothing else changed). Manual verification's "SoundSource uninstalled" item is done; step 19's TV power cycle without ARK is still to run.
- **Trackpad, second sighting (build 24, after the reboot):** MMTVL started at 23:54:28 before the remote connected (`no remote connected`); the remote connected at 23:54:43 and MMTVL seized 0x0D/0x01; `ioreg` shows no `AppleEmbeddedBluetoothTouch`, log `Multitouch: 0 remote surfaces`. Consistent with the cause above. Build 24 will have no touch until build 25 is installed and the remote reconnects.
- **TV power cycle without ARK (2026-11-07, build 24, after the reboot):** the user turned the TV and receiver off and on with the remote's Power button; audio came back without `killall coreaudiod`. Log: `Power: turning off` → `TV power key sent`, `receiver power off sent`, displays to sleep (23:57:22); `turning on` (23:57:43) → displays woken, `Display 4 added` / `Display 2 removed` then back (two hot-plugs), `TV is on` after ~16 s, `receiver power on sent`, `default output VSX-01TXH (HDMI)`. One clean run supports ARK as the 2026-11-05 dropout's cause (memory note); step 19 repeats it with software volume. Also first evidence for step 15: Power drives the TV (network) and the receiver (serial) both ways.
- **Version (user decision 2026-11-07):** when M7h is complete, bump the version to **1.2.0** (recorded in *Next session starts here*).

### 2026-11-08, build 24 TV checks: step 15 (from the user and the MM's log)

- **Done (user, 2026-11-08):**
  - Find Receiver (Serial) selects Pioneer. Log: `Find Receiver: pioneer answered on USB serial port (FT232R USB UART)`.
  - Find Receiver over Network finds nothing and says so.
  - Test Connection matches the receiver's display.
  - Find TV finds the VT50. Log: `Find TV: 1 SSDP replies, 1 TVs`.
  - Test TV shows On.
  - Long press Power over Plex opens the power menu. Log: `Power menu opened` and `Power menu closed (cancelled)` at 00:02.
  - Cancel/Back returns to Plex.
  - Relaunch asks for the PIN.
  - Sleep Mac mini sleeps the mini.
  - Restart Mac mini asks for the PIN, and MMTVL comes back at login.
  - Plex draws after a TV off/on with Plex in the background. Log: `Restarting tv.plex.htpc after a display change`, 2026-11-07 16:28.
  - With the entry of 2026-11-07, this also covers Power off/on and the remote's Vol± through the receiver.
- **Only the user's word for:** Relaunch, Sleep and Restart. They left no log line under those words; the log reads were `log show --last 36h`.
- **Then done too (user, 2026-11-08):** Mute from the remote, the phone's volume buttons, and Brand None (receiver control hidden, macOS's HUD back). **Step 15 is done.**
- **Trackpad and swipes:** waiting on build 25.

### 2026-11-08, step 14b results: probe 1 (read-only; gate A passes, but the tunnel is in use)

- **Probe:** `scripts/probes/dpcd-cec.swift`. It was run on the mini (macOS 26.6.2, 25G83) over SSH as the normal user at 00:06 on 2026-11-08, after a first run on the dev Mac (macOS 27.2, same converter). Raw output and IOKit disassembly are in the session scratchpad. Nothing was written: there is no write code.
- **Read path:** every register was read twice, through `IODPDeviceReadDPCD` and through a raw `IOConnectCallMethod` selector 0. Both gave the same byte, all with return code 0. No root, entitlement or prompt was needed.
- **The HDMI port is Apple's own DP-to-HDMI converter.** Registry: `BranchIEEEOUI` 0xFA1000, `BranchDeviceID` "pHDMIg". DPCD `0x0005` = 0x1D: a downstream port, DVI/HDMI/DP++, with format conversion. DPCD `0x0080` = 0x0B: HDMI, HPD-aware.
- **DPCD revision 0x11.** The CEC registers answer anyway; the plan expected them only from 0x14.
- **Gate A: passes.** `0x3000` = 0x07: tunneling, snooping and multiple logical addresses.
- **But tunneling is already enabled and owned:**
  - `0x3001` = 0x01: enabled.
  - The mask (`0x300E`/`0x300F` = 0x10/0x80) holds logical address 4 (playback 1, the Mac) and broadcast.
  - `0x3002` = 0xD2: a 3-byte RX ended and acked.
  - `0x3003` = 0x23: the last TX was 4 bytes with 2 retries, maybe Active Source `4F:82:23:00` (unverified).
  - `0x3004` = 0x00: no flags pending, so the owner clears them.
  - So macOS's own CEC (corercd → IOAVCECService → DCP) runs over this tunnel. MMTVL writing to it would race corercd for the RX buffer and IRQ flags, which is the risk the step names.
  - On the dev Mac, tunneling is enabled but no address is claimed (mask 0x00/0x00).
- **Physical address:** `IOAVServiceCopyPhysicalAddress` (selector 0x1F) succeeds but returns an empty CFData on both Macs. The 0x2300 can't be read this way.
- **Working signatures** (disassembly, the same on 25G83 and 27.2):
  - `IOReturn IODPDeviceReadDPCD(IODPDeviceRef, uint32_t address, void *buf, uint32_t len)`, which is selector 0, at most 0x1000 bytes.
  - `IODPDeviceRef IODPDeviceCreateWithService(CFAllocatorRef, io_service_t)`. It needs `IODPDeviceUserInterfaceSupported = true` and opens type 'DPVD'. `IODPDeviceCreate(alloc)` and `…CreateWithLocation(alloc, 0)` (0 = External) find the same device.
  - `IOReturn IOAVServiceCopyPhysicalAddress(IOAVServiceRef, CFDataRef *)`.
  - `IODPServiceGetDevice` and `…GetAVService` return NULL, so the device is created from `DCPDPDeviceProxy` directly.
  - `IODPDeviceGetRevisionMajor/Minor` return 0.0, so the revision is read from DPCD 0x0000.
- **Open (user):** probe 2 as planned enables tunneling and sets the mask only if they're off. Here both are already on, owned by corercd. So probe 2 would mean writing the TX buffer (`0x3020`/`0x3003`) next to corercd: TX only, address 4 kept, no IRQ clears, user at the TV. Run it, or record "tunnel owned by corercd" and keep step 9 skipped? Whether writes need an entitlement is unknown.

### 2026-11-08, step 14b results: probe 2 (user approved; run with the user at the TV)

- **The plan's probe 2 is amended, since tunneling is already on and owned by corercd.** The probe never writes `0x3001`, `0x300E` or `0x300F`. Writes go through one fence (`guardedWrite`/`writeAllowed`): only the TX buffer `0x3020…0x302F` and `0x3003` with the send bit, and `0x3004` only with `--clear`. Before writing `0x3003` it waits up to 500 ms for a send in progress to finish. It sends only from an address already in the mask (4). It doesn't clear the IRQ flags. In dry and listen runs it doesn't even resolve the write symbol.
- **Write signature:** `IOReturn IODPDeviceWriteDPCD(IODPDeviceRef, uint32_t address, const void *buffer, uint32_t length)`, selector 1, the mirror of the read. Source: the disassembly of 25G83 and 27.2.
- **Before any send, read-only:** corercd's last TX was `4F:82:23:00` (Active Source), which confirms the physical address 2.3.0.0. The last RX was `5F:72:01` (Set System Audio Mode, from the receiver).
- **First real send (00:18, 2026-11-08, `--send status`):**
  - Writing `40:8F` returned success with no entitlement, as the normal user. `0x3003` went from B1 to 31 within 64 ms (sent).
  - The TV answered `04:90:00` (Report Power Status: On). It was in the RX buffer afterwards.
  - corercd logged it as an ordinary RX: `RX: TV -> Playback Device 1: <Report Power Status> On`. Nothing else showed in its log.
  - The owner's registers were unchanged.
  - **So CEC works from a normal process through DPCD, next to corercd.**
- **`--send standby` (00:23, user at the TV):**
  - `40:36` was acked, and **the TV turned off. The receiver stayed on**: a standby sent to the TV alone isn't passed on. The TV's own remote broadcasts standby, which takes both down.
  - corercd saw the bus change (the Audio System device dropped, addresses reallocated) and re-announced itself as usual.
- **`--send on` (00:24):**
  - `40:04`, then `4F:82:23:00` about 300 ms later, both written OK. **The TV came on, but showed "no signal".**
  - About 4 s later the receiver broadcast `5F:72:01` (Set System Audio Mode), then `5F:80:23:00:20:00`, a **Routing Change from 2.3.0.0 (the Mac) to 2.0.0.0 (the receiver itself, likely the TV's ARC audio)**.
  - At that moment the Mac's HDMI display went away (MMTVL `Display 2 removed`, `Display 6 added`, Screen Sharing's virtual display; the `DCP*Proxy` objects were gone). So probe 2 couldn't send another Active Source (no DP device).
  - The user switched the receiver back to the Mac's input: display 2 returned at 00:27:42, and corercd sent its own Image View On, Active Source 2.3.0.0 and Report Power Status.
  - Likely cause (inference): when CEC wakes the TV, it starts System Audio Mode, and the Pioneer moves to its own/ARC route, which drops the Mac's input. Our Active Source came before that and was overridden. When MMTVL wakes the TV with network Wake-on-LAN (2026-11-07), this doesn't happen.
- **After the probe (user):** the TV's own remote off still turns the receiver off, so macOS's CEC and the bus are unharmed. Prime Video didn't play while a VNC session was open; **with VNC closed it plays** (user, 2026-11-08). So HDCP is intact. Screen sharing blocks protected video, which matters for remote debugging.
- **Gate B so far:**
  - Standby works (TV only).
  - "On" turns the TV on, but this receiver then drops the Mac's input. On this setup CEC "on" is worse than Wake-on-LAN, unless MMTVL also switches the receiver back over RS-232 after it, or re-sends Active Source once the HDMI display returns.
  - macOS's CEC is unchanged.
  - HDCP is intact.
  - **Result: gate B passes for standby, and fails for "on" with this receiver.** Whether step 9 returns as a DP-AUX CEC transport is the user's decision.
- **System Audio Mode Request first (00:35):** standby `40:36` (TV off), 12 s later `45:70:23:00`, then `40:04` and `4F:82:23:00`. The receiver answered `5F:72:01` at once, but 3 s after Active Source it sent the same Routing Change to 2.0.0.0. The Mac's HDMI dropped again (00:35:41), and the user switched the input back. **So a receiver left on re-routes when CEC wakes the TV, whatever the Mac sends.**
- **Broadcast standby, then on (00:39, the Power button's case):**
  - `4F:36` was acked. The receiver sent `5F:72:00` and `5F:85` and went to standby with the TV.
  - During standby the Mac's HDMI display stayed (display 2, after a few hot-plugs), so the tunnel stayed usable.
  - 20 s later `40:04` + `4F:82:23:00`: the TV came on and the receiver woke. It reported 2.0.0.0, sent Request Active Source, and corercd answered Active Source 2.3.0.0 itself. HDMI dropped at 00:39:37 and came back at 00:39:41 (the receiver powering up). **No Routing Change. MMTVL showed, with sound** (user).
- **Physical address source:** the EDID is the property `"EDID"` on `IOPortTransportStateDisplayPort` (`ioreg`, read-only). Its HDMI vendor-specific block (CEA extension, OUI 00-0C-03) gives **2.3.0.0**, matching what corercd sends.
- **Volume over CEC (00:42–00:50, user at the TV; the user asked that every setup be covered, not only theirs):**
  - **To the receiver (address 5):**
    - User Control Pressed `45:44:41` / `45:44:42` / `45:44:43`, each followed about 1 s later by Released `45:45`, all acked. Three Ups then three Downs moved the Pioneer up three steps and back, and Mute toggled mute (user).
    - Give Audio Status `45:71` got **no reply**: no Report Audio Status, so no level or mute state from this receiver. Other brands may answer; this is how an Apple TV shows a level.
  - **Queries the receiver answers:**
    - Give Device Power Status `45:8F` → `54:90:00` (on);
    - Give Physical Address `45:83` → `5F:84:20:00:05` (2.0.0.0, Audio System);
    - Give System Audio Mode Status `45:7D` → `54:7E:01`;
    - Give OSD Name `45:46` → "VSX-01TXH";
    - Give Device Vendor ID `45:8C` → `5F:87:00:E0:36` (Pioneer).
    - So a CEC receiver can be detected (power status) and named (OSD name).
  - **To the TV (address 0):**
    - `40:71` → Feature Abort (unrecognized opcode); `40:46` → Feature Abort.
    - Volume and Mute (`40:44:4x` + `40:45`) were acked, but changed nothing visible. **The user's TV is set to external audio only (its speakers off), so the TV-volume case can't be judged on this setup.** Untested here.
- **User decision (2026-11-08): step 9 comes back as a DP-AUX CEC transport with full on and off** (Settings → Audio & TV → TV → Brand → HDMI-CEC). See step 9.

### 2026-11-08, step 13b (QA PASS; full suite 1375 tests passed)

- Built as planned. `VolumeToast.message(for:enabled:)` is an overload, so existing function references still compile. `performVolume` reads the live `settings.volumeToast` at each press. No `SettingsModel.swift` case was needed: the generic `.toggle(key)` covers it.
- Decoding: a missing, null, numeric, string, array or object `volumeToast` reads as true, and `settings.json` keeps its other keys (no `.bak`).
- QA checked the row live (brand None, after Brand): Return toggles it, and `settings.json` changes within 1 s with no relaunch. A real press with Off/On couldn't be tried on the dev Mac: only the event tap (kiosk) and a paired Siri Remote reach `performVolume`. That's a TV check on build 25.
- QA minor: no test for the row's place with Connection set to Network. Moot, since step 13c moves the row to Audio & TV.

### 2026-11-08, step 13c (QA PASS; full suite 1380 tests passed)

- Built as planned:
  - root row `audioTV` after Casting;
  - the `.audioTV` page: Receiver and TV, each showing its brand or "Not Set Up", then a **Volume** section with Show Volume (id `receiver.showVolume` kept);
  - `.receiver` titled "Receiver", and the new `.tv` page;
  - each page drops only its own old Test/Find results when it opens;
  - Find on Network's chooser opens only over `.receiver`;
  - the Debug `-settingsDemo` accepts `audioTV` and `tv`.
- **Orchestrator decisions:**
  - A page takes the title of the row that opened it. The Receiver and TV pages' brand rows are both **"Brand"**, and so are the pages they open (QA minor, fixed).
  - Single-section Receiver and TV pages have no section header.
  - Find's answers are dropped when Receiver reopens (as before with Receiver & TV).
- QA walked it with real key presses in `-windowed YES`: Back restores focus at each level, Receiver's value follows a brand change live, and Show Volume saves from the new page and survives a relaunch.
- Not verified live: the network chooser and TV Find/Test (no receiver or TV on the dev Mac; covered by tests), and the kiosk layout on the TV.
- Docs: the master plan's D44 and this plan's forward references now say Audio & TV. Step 18's **Without a Receiver** section goes on the Audio & TV page.
- **TV check (build 25):** Settings → Audio & TV on the TV, legible, with the receiver set up (Pioneer) and the TV (VIERA).

### 2026-11-08, step 9 reopened (QA PASS; security: nothing medium+; full suite 1431 tests passed)

- **Built:**
  - `AVControl/CEC/CECFrame.swift`: a private init, so only `4F:36`, `40:04`, `40:8F` and `4F:82:<PA>` exist, plus the allowed-frame table.
  - `CECTunnel.swift`: one serial queue. The DPCD write allow-list is checked twice: in `writeAllowed`, and again before the `dlsym`'d call.
  - `EDIDPhysicalAddress.swift`: the VSDB parser, and the `"EDID"` lookup on `IOPortTransportStateDisplayPort`.
  - `TVProtocols/HDMICEC.swift`: a `PowerTV`.
  - `PowerTVSelector`, which picks the CEC or the network TV by `tvBrand`.
  - The TV page's CEC rows: Brand, Test TV, Status, footer.
- **Accepted deviations:**
  - Standby to all is sent on every "off", even without an answer (it doesn't toggle).
  - New `PowerTV` requirements with defaults (`powerOffToggles`, `checksHDMIAfterPowerOn`, `hdmiDisplayReturned()`).
  - `TVController.isConfigured` needs brand panasonic, so a leftover `tvHost` sends no SOAP under `cec`.
  - The "macOS doesn't let apps use HDMI-CEC" footer is gone.
- **Fixes in review:**
  - Status replies identical to the last RX frame are caught by the RX-valid edge, by polling `0x3004` (read only) every 5 ms, and an unanswered query is retried once. Otherwise a missed reply while the TV is on would turn Power "off" into "on".
  - **QA major:** "can turn on" is decided after the wake. HDMI-CEC always runs `powerOn()` with its 5 s wait, and says "TV Didn't Turn On" when the tunnel never becomes ready or Image View On isn't sent.
  - A test pins that "off" or a second "on" cancels the pending 20 s display check.
- **Security (one pass, no medium+; fences fuzzed):** no DPCD write outside `0x3020…0x302F`/`0x3003` over every address and length; only the 4 frames pass the table; the EDID parser was fuzzed with 300k random inputs and 123k edge cases, with no traps. Lows fixed:
  - `0x3003` is re-read after the TX-buffer write, returning `.busy` if corercd started a send.
  - DPCD `0x0000` must read 0x10…0x14 before the first write per opened device, a guard against changed private signatures after a macOS update.
  - The poll rate went from 2 ms to 5 ms.
- **Lows accepted:**
  - The EDID comes from the first display that has one (the mini has one display).
  - A paired phone can drive an already-open power menu's Turn Off (step 12's accepted exposure, now sending `4F:36`).
- **Unverified (TV check, build 25):**
  - whether the IODPDevice user client leaks per hot-plug reopen (compare `ioreg` user-client counts before and after a few hot-plugs);
  - the tunnel across `pmset displaysleepnow`;
  - AUX polling load next to HDCP: Prime Video plays while Test TV is pressed;
  - "another send started while the frame was written" lines (rare collisions).

### 2026-11-08, step 9c (QA PASS; security: one medium, fixed; full suite 1494 tests passed)

- **Built:**
  - `CECAudioSystem` (the receiver over HDMI-CEC);
  - the frame table grown by 8 rows (`45:44:{41,42,43,6D}`, `45:45`, `45:36`, `45:71`, `45:8F`, `45:46`, `40:44:{41,42,43}`, `40:45`), with the DPCD fence unchanged;
  - `7A`, OSD-name and receiver-power parsing;
  - VIERA `SetVolume`/`SetMute`, and `TVController.stepVolume`;
  - routes `.cecReceiver` and `.tv`, and `VolumeMode.tv`;
  - `PowerReceiverSelector`;
  - the Receiver → Connection list (Serial / Network / HDMI-CEC), and the TV page's "Volume Buttons Change TV Volume".
- **Accepted deviations:**
  - Connection is a list page.
  - A forced `phoneRemoteVolume: "tv"` still needs the toggle.
  - One step-10 queue for every device.
  - Consecutive count for giving up on `45:71`.
  - A hot-plug runs a read-only check, then a probe.
  - No CEC receiver frames when the TV is HDMI-CEC.
  - Power-on check after 5 s.
- **Decided in review:**
  - MMTVL's "off" marks the CEC receiver not answering (10 s hold), and "on" probes it 5 s later.
  - **The TV gets the volume buttons only when no receiver is set up at all** (security L2 and a QA text mismatch; the plan's step text is amended).
- **Fixes:**
  - **Security M1 (medium):** Released always follows a Pressed that may have gone out (sent, timed out, not acknowledged), and a Released that isn't sent is retried once after 0.1 s. Otherwise a held key could ramp the volume, with no cap over CEC.
  - **QA major:** a set-up receiver is re-asked after fallback presses (throttled).
  - A ready CEC receiver or TV is re-checked after a press when its last answer is over 60 s old.
  - `noteTurnedOff` ignores in-flight probe answers.
  - The TV's power status is cleared on MMTVL's CEC off.
  - VIERA `stepVolume` stops when the settings change mid-press.
  - An unreachable log line was fixed.
- **Accepted low:** a hand-edited `receiverConnection: "cec"` sends read-only queries at launch.
- **Not verified (build 25):**
  - live presses (no event tap in `-windowed`, no Siri Remote or phone on the dev Mac);
  - Report Audio Status from a non-Pioneer receiver;
  - Power On Function on the Pioneer;
  - VIERA `SetVolume`/`SetMute` on the VT50;
  - any TV acting on CEC volume;
  - no ramping after a held Vol± over HDMI-CEC;
  - the standby re-check after the receiver's own remote turns it off.

### 2026-11-08, pre-build pass for build 25 (QA PASS; security: nothing medium+)

- **QA** over `7d62615..f42f0e5`:
  - Debug and Release builds; full suite **1494 tests passed**; no demo arguments in the Release binary.
  - Mini-like launch (serial Pioneer, VIERA without `tvHost`) and clean-state launch: no `.bak`, defaults added at the first save, no CEC traffic. Audio & TV shows Pioneer / VIERA / Show Volume On.
  - All Audio & TV pages per connection and brand.
  - The selectors agree (`tvUsesCEC` = `cec.isConfigured`).
  - **During the walk, one batch of synthetic keys (Escape, Up, Return, Down, Return) went to Plex HTPC, which was playing on the dev Mac and took the front.** The user was told.
- **Security** over the same range: nothing medium or above. Fixing before the build:
  - **L1:** a post-write collision with corercd returned `.busy`, which skipped Released. It now gets its own result, which counts as "may have gone out".
  - **L2:** a network receiver with a brand but no usable address counted as not set up, so TV volume could bypass its cap. "Set up" now follows the settings.
- QA minor: the VIERA footer showed for TV Brand None.
- **All three are fixed** (full suite **1495 tests passed**):
  - L1: a new `CECSendResult.collided`, which counts as `mayHaveGoneOut`, so Released follows. A failed re-read after the TX write is also `.collided`. The receiver stays ready on `.collided`.
  - L2: `AppSettings.receiverIsSetUp` (brand not none, or connection cec) feeds `VolumeController.receiverSetUp`.
  - The VIERA footer shows only for Panasonic.
- Docs (done): D44's text no longer says CEC is closed, and says TV volume needs "no receiver set up".
- Accepted for the TV check: touch outside trackpad mode (L3); IODPDevice reopen per hot-plug (L4, compare `ioreg` user-client counts). The Power log now says "TV off sent" (was "TV power key sent").
- **Build 25 TV checklist additions (QA):**
  1. Regression on the mini's own setup (serial Pioneer + network VIERA): Power off/on drives both; dB toasts; first launch shows Audio & TV correctly, with no `.bak`.
  2. HDMI-CEC TV with the serial Pioneer kept: off = `4F:36` then serial off; on = CEC on then serial on, with no Routing Change to 2.0.0.0; does "Switch the receiver to the Mac's input" ever appear.
  3. The 20 s no-display toast on purpose (receiver left on, TV off with `40:36`, then Power on).
  4. Find Receiver with the USB adapter unplugged falls through to HDMI-CEC and switches Connection; plugging back in and choosing Serial restores dB volume.
  5. Show Volume Off with the receiver off by its own remote: "Receiver isn't answering" still shows.
  6. Restoring Panasonic VIERA + Serial after the CEC tests works without a relaunch.
  7. Digitizer: 6 interfaces `open: seized`, 1 `left to macOS (touch)`; no native scroll or pointer from the surface outside trackpad mode.
  8. The Live TV skip checks (a)–(c), together with step 13b's Show Volume Off check.


### 2026-11-08, build 25 TV checks (user, and the MM's log)

- **Remote:**
  - TV = Home everywhere, long press centre = menu, "a" types: good. Idle and wake: called good.
  - **The touch fix works after a real reconnect:** the remote dropped at 02:13:03 and reconnected at 02:13:20. The log shows 0x0D/0x01 `left to macOS (touch)`, `Multitouch: Siri Remote surface (family 145, product 789) accepted by product`, `1 remote surfaces`. The trackpad tries before that (02:01–02:03) had no surface.
- **Swipes (user):** they work but are **too sensitive**: a click on up/down/left/right sometimes registers as a swipe. **User: "I don't have to have swipe in remote mode … I just want the trackpad function in trackpad mode."** → swipes become a Settings → Siri Remote option, **off by default** (decision recorded here; step 13e).
- **Trackpad mode (user):** it acts as a mouse (on the desktop after Exit to Desktop, the bottom edge revealed the Dock and left/right moved through apps), but **no pointer is visible.** Needs investigation (step 13e).
- **Settings, power, volume, CEC (checks 6, 7, 9, 10, 11):** called good by the user.
- **Live TV skip (check 8):**
  - It skips with the phone's volume (no toast) and with the **receiver's own dial**.
  - The user notes it never happened on any input before with this receiver, so the receiver alone is unlikely.
  - mpv logged nothing at those moments.
  - **Hypothesis (code reading, unverified):** every receiver status line (a `VOL…` reply or an unsolicited line when the dial turns) calls `receiver.onStatusChange` → `scheduleSettingsRefresh` → `SettingsModel.refreshStatus()` (`App/AppDelegate.swift:446-467`, `Settings/SettingsModel.swift:194-206`), **even when Settings isn't showing**. That re-reads the PIN (Keychain), the login item, IPTV, the phone remote, Plex, casting, the Siri Remote, the receiver and CEC on the main actor. mpv's frames are drawn through the main thread (`IPTV/Player/MPVVideoView.swift:136-139`), so each stall drops frames.
  - Before 2026-11-07 the receiver wasn't connected over serial, which fits.
  - **Confirmed by the user (2026-11-08):** with Connection HDMI-CEC (serial port closed), neither the receiver's dial nor the Siri Remote's volume makes Live TV skip. So MMTVL's handling of the serial lines is the cause, not the receiver.
  - The toast is not the cause.

### 2026-11-08, step 13e (a) and (b) (QA PASS; full suite 1502 tests passed); (c) below

- **(a) The skip:**
  - Measured on the dev Mac: a full `refreshStatus()` has a median of ~2.5 ms (SMAppService ~1.9 ms; a Keychain read of an existing item ~0.7 ms; first call ~10–13 ms). A receiver line cost **~2.2–2.6 ms** of main-actor time in build 25, and costs **~15–19 µs** now.
  - `SettingsModel` gains `StatusParts` (receiver, cec, siriRemote, phoneRemote, iptv, plex, casting), `refreshStatus(_:)` and `refreshStatusIfShowing()`. Both do nothing unless `isShowing()` (set by `AppRouter`: `screen == .settings`). Every status source refreshes only its own part. Opening or returning to Settings still re-reads everything.
  - `VolumeController.perform` picks the receiver, CEC receiver or TV route without CoreAudio or the running-apps list.
  - Debug-only harnesses (`-measureSettingsRefresh`, `-pointerDemo`) stay until (c) is settled; step 16 removes them.
- **(b) Swipes:** `siriRemoteSwipes` (default `false`), and the Siri Remote page's **Swipes** row. With it off, touches outside trackpad mode do nothing. Trackpad mode is unchanged.
- **(c) The invisible pointer (findings before the fix; the fix is the next entry):**
  - The MM has no pointing device (`IOHIDPointing` empty).
  - **The phone's trackpad shows the pointer on the MM now (user, build 25), through the same `PhonePointer.perform` path.** So a missing mouse isn't the cause.
  - Hypothesis (unverified): with the digitizer left to macOS, touches on the Siri Remote reach the HID event system and hide the cursor (like hide-while-typing).
  - **User (2026-11-08):** after the pointer was moved with the phone's trackpad, the Siri Remote's trackpad mode **shows the pointer** too, even while the surface is touched. So the touch-hides-cursor hypothesis is unlikely. More likely the cursor was left in a hidden state that the phone's moves cleared and the Siri path's didn't (same posting function; the difference is unknown). **Watch for it on build 26:** after a relaunch, wake or Home, does Siri trackpad mode show the pointer without the phone first?
- **Follow-up (not fixed):** `SerialPort.write` can `usleep(2000)` up to 50 times on EAGAIN on the main thread (`AVControl/SerialPort.swift:110-120`), up to 100 ms. It doesn't explain the skip (the dial writes nothing); move it off the main thread later.

### 2026-11-08, step 13e (c) (QA PASS; security: nothing medium+; full suite 1529 tests passed)

- **Cause (best known, unverified on the MM's 26.6.2):** WindowServer doesn't reveal a cursor obscured by `setHiddenUntilMouseMoves(true)` (or hidden with no mouse attached) for moves made while a touch is active. macOS 27's SkyLight has "Skip reveal: cursor obscured for active touch"; the string isn't in the MM's 26.6.2 cache. Every Siri trackpad move has a finger down, and the phone's don't. That fits the user's report: once a phone move had revealed the pointer, Siri touches didn't hide it.
- **Item 1 (no obscuring in trackpad mode) was already in place from L7:** `CursorAutoHide.hides(setting:isTrackpadMode:)` and `onTrackpadModeChange` (`setHiddenUntilMouseMoves(false)` on mode on). Build 25 still showed no pointer, so un-hiding alone isn't enough.
- **Built:**
  - `Input/SiriRemote/PointerReveal.swift`, a pure `nonisolated` type: a reveal is due when trackpad mode turns on (after the lift if a finger is down) and 0.15 s after each lift (`liftDelay`; touching again sooner skips it). A touch-surface reset counts as a lift; mode off cancels; a refused reveal is dropped and the next lift retries.
  - `PhonePointer.reveal(edgeInset:)` / pure `revealPath`: 1 point right and back (left at the right edge), through `SyntheticInput.movePointer`; a pointer outside the kiosk edge inset is moved inside first and stays; nothing for no displays or a non-finite location.
  - `SiriRemoteInput`: the reveal state follows every frame, `stop()`, `touchSurfacesReset()` and the mode; a wait task. `post`'s checks are now `isPointerAllowed()` (Accessibility, then `KioskGuard.pointerGate`, each noted once), shared with the reveal (security M1 unchanged).
  - `AppDelegate`: `revealPointer` = `setHiddenUntilMouseMoves(false)` + `phonePointer.reveal`; the Debug `-pointerDemo reveal` scenario (removed in step 16).
- **Exercised (`-windowed YES -pointerDemo reveal`, QA):** no move while the finger is down; "Trackpad: pointer revealed" 154 ms after the lift and 158 ms after a mid-touch reset; nothing after mode off. A listen-only event tap saw exactly two 1-point pairs, tagged with `SyntheticInput.marker`, ending at the start position. The dev Mac's session was locked, so whether the pointer becomes **visible** couldn't be seen: a TV check.
- **Fixes in review:**
  - QA minor: trackpad mode off with Cursor Auto-Hide on left the pointer showing until the next remote command. Now `CursorAutoHide.hiddenUntilMouseMoves(trackpadModeOn:setting:isAppActive:)` hides it at once (MMTVL active only); tested.
  - Security low 2: the wait loop now always sleeps (at least 1 ms, `PointerReveal.minimumWait`), and a seeded random-sequence test pins the invariant (pending ⇒ trackpad mode on, no finger down).
  - Two reveal tests waited a fixed 400 ms and failed under full-suite load; they now wait for the notice (up to 2 s).
- **Lows accepted:** with edge inset 0 (`-windowed`, Exit to Desktop, lock off) a pointer parked in a screen corner is nudged 1 point out and back on each lift, which might re-fire a hot corner (unverified; with the lock in force the 6-point inset keeps it off corners). A reveal can follow sleep if a finger was down as the surfaces stopped.
- **TV checks (build 26):** after a relaunch, wake or Home, without using the phone first, double-press Siri: the pointer shows, and shows again after each lift, in MMTVL, on the desktop (Exit to Desktop) and in Plex/Safari. With Cursor Auto-Hide on, Trackpad Off hides the pointer at once. If the pointer still doesn't show, the touch theory is wrong.

### 2026-11-08, pre-build pass for build 26 (QA PASS; security: nothing medium+)

- **QA** over `ad7929b..HEAD` (step 13e (a)–(c)): Debug and Release builds; full suite **1529 tests passed**; no Debug harness strings (`pointerDemo`, `measureSettingsRefresh`, `settingsDemo`, …) in the Release binary; a clean-home launch (defaults seeded, `"siriRemoteSwipes": false`, no `.bak`) and a launch with the real settings (no errors, every `.json` unchanged). The timing harness again: a receiver line ~2.26 ms in build 25's wiring, ~18 µs now. The dev Mac's session was locked, so nothing visual was checked; no keys were posted.
- **Security** over the same range: nothing medium or above. The Debug harnesses (including `-pointerDemo desktop`, which skips the PIN) are only reachable under `#if DEBUG`; no secrets in the new log lines; the volume route short-cut is equivalent to build 25 in every mode.
- **Both found (low, a 13e (a) regression):** coming back from the PIN screen to Settings (cancel, or a verified Quit/Relaunch/Restart/Set/Change/Turn Off PIN) didn't re-read status, and part refreshes during PIN entry were dropped, so Settings could show a stale receiver, Siri Remote or phone status. **Fixed:** `AppRouter.returnFromPIN()` goes through `returnToSettings()` (full `refreshStatus()`, page kept) when the PIN screen covered Settings; 3 tests (two fail without the fix). Full suite **1532 tests passed**.
- **Lows accepted:** a reveal's synthetic move reaches the window under the pointer, like every trackpad move.
- **TV check (build 26):** open a PIN prompt from Settings, change the receiver (dial) or reconnect the remote, cancel: the status is current.

### 2026-11-08, build 26: home screen frozen after YouTube (user; step 13f added)

- **What happened:** using YouTube on the MM, then going back Home, the home screen froze and ignored input.
- **Found over SSH (12:51):** MMTVL (pid 3168, up 9.5 h) at 100 % CPU, state R; its last log line 12:49:12 (Plex connected, i.e. the home screen coming back; YouTube had opened at 12:45). `sample 3168 3`: all 1417 main-thread samples under SwiftUI's run-loop observer, 710 in a hover update (`NSHostingView.didRequestHoverUpdate` → `HoverEventDispatcher` → hit tests) and 704 in the next transaction (`GraphHost.flushTransactions`, a `FluidSpringAnimation` of a `ResolvedGradientVector`, the parallax shine). MMTVL's frames on the stack: `closure #3 in ParallaxFocus.body` (the `.onContinuousHover` handler, 21 samples), `ParallaxRender.body`. No screenshot (`screencapture` over SSH: "could not create image from display"), so the pointer's position wasn't seen.
- **Recovered:** with the user's OK, `kill 3168` (it stopped on SIGTERM) and `open -a /Applications/MMTVL.app`; the new process idled at 9.5 % CPU.
- **Again at 12:55 (user: "stuck when I clicked"):** pid 8039, 81 s after the restart, at 99 % CPU. Its log: `Trackpad mode on` 12:55:53.896, `Trackpad mode off` 12:55:55.529, then nothing. A 1 s sample: the same loop, `closure #1 in closure #3 in ParallaxFocus.body` on the stack. Restarted again (pid 8062). So trackpad mode on the home screen triggers it (the pointer, revealed or moved by trackpad mode, rests on the focused tile). Until 13f is installed: no trackpad mode on the home screen.
- **Cause and fix:** step 13f. The user chose to fix it in M7h (2026-11-08).

### 2026-11-08, step 13f (QA PASS after one fix round; security: nothing medium+; full suite 1533 tests passed)

- **Reproduced on the dev Mac** (`-windowed YES`, the window resized to 1920 × 1080 content, the MM's 1:1 geometry): with the pre-fix build, a pointer resting at a focused tile's right edge, bottom-right corner or top band spun MMTVL at ~100 % CPU, with the MM's sample signature. At the default 2/3-scale window it didn't reproduce. A move onto the focused tile and then resting also spun.
- **Fixed** as written: (a) hover after the `keyframeAnimator` on a `.contentShape`; (b) `ParallaxMath.followsPointer(at:last:)`, with `onChange(of: isFocused, initial: true)` recording the pointer. Same positions after the fix: 4–18 % CPU (idle).
- **QA minor, fixed:** the untilted shape left a dead band at the focused tile's drawn edge (it draws at `focusScale` 1.1), where a click no longer opened it. The shape is now `.scale(isFocused ? Theme.focusScale : 1)`: it grows with focus, never with the tilt. A click in the band opens the tile; the band positions stay idle; Home from YouTube with the pointer resting, then Right onto it: no spin.
- **Not checked on the dev Mac:** top shelf cards (no Plex data), moves through the phone's `SyntheticInput` path, the Siri trackpad mode. TV checks for build 27.

### 2026-11-08, build 27: Live TV black after Select (user; step 13g added)

- **User:** "home screen previews the live tv properly, but when selecting it now, the audio works but there is no video once it enters live tv... just a black screen."
- **MM log (`log show --last 3h`, categories MPV/IPTV), e.g. 19:47:18:** `Live TV opened on the home preview's stream (no reconnect)`, then `Video GL context released` and `Video GL context created`, and no `Loading a stream` until the user zapped. The same pair at 19:17:13, 19:17:20 and on each `Left Live TV; the channel keeps playing as the home preview` (19:17:18, 19:42:59). The log store only reaches back to 18:35, so earlier builds can't be compared.
- **Cause (mpv source, `master`):**
  - The one `MPVVideoView` moves between `LauncherRootView`'s home branch (`Launcher/AppRouter.swift:1030-1040`) and `LiveTVRootView` (`IPTV/LiveTVView.swift:28-37`). Core Animation releases the layer's GL context and makes a new one. `MPVVideoLayer.releaseCGLContext` frees the mpv render context (`IPTV/Player/MPVVideoView.swift:66-76`).
  - `render.h` says of `mpv_render_context_free`: "If video is still active (e.g. a file playing), video will be disabled forcefully."
  - `vo_libmpv.c` `mpv_render_context_free` → `kill_video_async` → `client.c` `do_kill`: `uninit_video_out`, then `error_on_track` (`misc.c`), which deselects the video track for the rest of the file. Audio goes on.
  - `LiveTVModel.adopt` (`IPTV/LiveTVModel.swift:273-282`) deliberately doesn't reload, so nothing brings the video back. A zap does reload, which is why the home preview's own zaps showed video.
- **Not explained (unverified):** why the user saw video on Select before build 27. Nothing in Live TV or the home's video hosting changed since build 25 (`git diff ad7929b HEAD -- MMTVL`: only Settings, input, Siri trackpad and `ParallaxFocus`). The M7c step 35 note says a new context used to mean only a flicker. Maybe the old view's removal and the new host's insertion used to land in one Core Animation transaction, so the layer never left the window. How to check: build 26 on the dev Mac with Live TV set up, Select from the home preview, and watch for the release/create pair.
- **Fix chosen:** step 13g. A reload on a replaced context is the reliable recovery: it also covers a display change or a window move. A seamless Select (no reload) would mean hosting every video view in one place above the screens. That was done next, as step 13h, at the user's request.

### 2026-11-08, step 13g (QA PASS; full suite 1538 tests passed)

- **Built as written,** plus one addition QA confirmed: the reload cancels a waiting stream-error retry. Otherwise the retry would load the same URL again 2 s later.
- **QA minors, not fixed (known gaps):**
  - A zap that lands within one main-queue hop of a new context can load the same URL twice. It's rare, and costs one extra loadfile from the resolver cache; there's no loop.
  - A context replaced while **paused** (e.g. a TV or HDMI power cycle with Live TV paused) still leaves audio only after unpause, until the next zap. This was so before 13g too. A possible fix: remember the replaced context and reload on unpause.
  - The reload keeps `retries`. A stream that used both retries earlier then reloads straight from the CDN, without the relay. The retry path already behaves this way.

### 2026-11-08, step 13h (QA PASS; full suite 1546 tests passed)

- **Checked by code reading (QA):**
  - The `ForEach` keeps its structural place on every non-YouTube screen.
  - Every `LiveTVModel.open` path sets `mode` in the same main-actor turn as `screen = .liveTV`, and `videoPlacements` keeps `player` placed in loading, setup and unavailable.
  - `leave(keepingPreview:)` sets `previewChannelID` before `screen = .home`.
  - So no frame drops the preview's placement on Select, Back or Home.
- **Not run:** the dev Mac was at the login window (`launch: every rung failed; front app now com.apple.loginwindow`). The no-swap claim rests on the build 28 log.
- **QA minors, not fixed:** Back onto a start tile other than Live TV now fades the preview out (0.35 s) instead of inserting it at 0. It's behind the tile's opaque backdrop, so it's likely invisible. Unverified on screen: whether SwiftUI ever reorders the video's host view as the sibling content swaps.

### 2026-11-08, build 27 checks closed (user)

- **User:** "all of build 27 checks can be closed". That covers step 13f's sequence (no home screen freeze after YouTube or trackpad mode), build 26's list (no Live TV skip on Vol± over serial, Swipes off by default, the Siri trackpad pointer, Settings status live, Trackpad Off hiding the pointer, PIN-cancel status) and the build 25 carry-overs. Steps 13e, 13f and 14 are ticked.

### 2026-11-08, build 28 TV check: step 13h (user, and the MM's log)

- **User:** "live tv select works now".
- **Log (`log show --start '2026-11-08 20:19:00'`, MPV and IPTV):**
  - One `Video GL context created` at launch (20:19:14), for the preview's first load.
  - Then `Live TV opened on the home preview's stream (no reconnect)` at 20:19:25, :39 and :47, and `Left Live TV; the channel keeps playing as the home preview` at 20:19:33 and :42.
  - No `Video GL context released`/`created`, no `reloading the stream` and no `Loading a stream` at any of them. The view stayed in the window, and mpv's video was never turned off.
- **Then closed (user, 2026-11-08):** Multiview opened from the preview, and the guide's preview rect. Step 13h's TV check is done.

### 2026-11-08, volume presses make Live TV skip (user, build 24; closed: fixed by step 13e (a), confirmed on build 27)

- **What happens:** with the receiver set up, every remote volume press makes Live TV's video skip. The user expects other video apps (Plex, Prime Video) to do the same; that isn't checked yet. The MM's log has nothing at those moments: `Volume` lines are debug and aren't kept, and mpv doesn't log dropped frames. Only `Toast Volume −54 dB` and `Toast Muted` show (00:04 on 2026-11-08).
- **Code paths (read 2026-11-08):**
  - mpv's frames go through the main thread. Its update callback queues `setNeedsDisplay` on the main queue (`IPTV/Player/MPVVideoView.swift:136-139`), and `CAOpenGLLayer.draw` renders them.
  - Each Siri Remote or volume-key press calls `OverlayToast.show` (`DesignSystem/OverlayToast.swift:22`). That runs `place(panel)` → `setFrame(…, display: true)` (`:97`, a synchronous redraw on every press), `orderFrontRegardless` (`:41`) and a fade animation. The glass capsule (`.glassPanel(in: Capsule())`, `:168`) sits over the video and samples it.
- **Possible causes (unverified):**
  1. Main-thread work for the toast, or the volume path, delays mpv's frame draws, and mpv drops the late frames.
  2. A window over the full-screen video makes the compositor stop sending the video straight to the display, which hitches it. This would affect every video app.
  3. The receiver: the Pioneer's own volume handling glitches the HDMI picture. Then the receiver's own remote would cause it too, with MMTVL not involved.
- **Telling them apart (user at the TV, Live TV playing):**
  - (a) the receiver's own remote's volume: a skip means cause 3;
  - (b) the phone's volume buttons: same receiver path, but no toast. No skip points to the toast (cause 1 or 2);
  - (c) the Siri Remote's volume in Plex: a skip there too supports cause 2, or 1 if Plex is affected some other way.
- **Needed:** the results of (a)–(c), then a fix step. Possible fixes, depending on the cause:
  - keep the panel placed and only move it when the screen changes (no `display: true` per press), and update the text without re-ordering the panel;
  - a plain, non-glass toast over video;
  - draw mpv's frames off the main thread (a bigger change to D22's layer).

### 2026-11-08, step 16 (QA PASS; full suite 1546 tests passed)

- **Code:** removed the Debug harnesses `-pointerDemo` and `-measureSettingsRefresh` (`App/AppDelegate.swift`, with `measureReceiverLines`, its `FakeSerial` and the `SettingsTiming` logger; `SiriRemoteInput.demoSetTrackpadMode`). All were `#if DEBUG`. The `-toastDemo`, `-settingsDemo` and `-powerMenuDemo` harnesses stay. `scripts/probes/` is deleted, and `/tmp/mmtvl-probes/` on the mini too (user's OK). Debug and Release build.
- **CLAUDE.md:**
  - the Siri Remote paragraph (D43) replaces Remote Buddy's, with one history note left;
  - new Receiver & TV (D44, with CEC through the DPCD tunnel) and Power (D45) paragraphs;
  - the 13 new `settings.json` keys and the `phoneRemoteVolume` values;
  - `key-bindings.json`: the `siriRemote` trigger, new commands, revision 3;
  - log commands for `SiriRemote`, `Receiver`/`TV`/`CEC`, `Volume`, and `Power`/`Display`;
  - the kiosk note (the mini's menu bar auto-hide "Always", the Dock auto-hidden).
- **Master plan:**
  - Q21 and Q22 resolved;
  - the §3 Volume row and D44's volume order now match `VolumeRoute.choose` (receiver serial/network → receiver CEC → TV opt-in → SoundSource keys until M7k → system → app);
  - D43 notes swipes are opt-in.
- **Step 16 text that was out of date:**
  - "no CEC on macOS" (CEC works since step 9 reopened);
  - the log category list (TV, CEC, Volume and Display added);
  - the software volume parts (M7k).
- **Dropped:** "the AVR queries from Terminal". The only tested recipe was the deleted `pioneer-write.py`, and an untested `screen`/`stty` line wasn't added. CLAUDE.md says to quit MMTVL or set the brand to None before talking to the receiver by hand, since MMTVL opens the port exclusively.
- **For the user (unverified):** an old "controller A → Home" binding from M7c may still be in the mini's `key-bindings.json`. It's harmless, and can be removed in Remote Buttons.
