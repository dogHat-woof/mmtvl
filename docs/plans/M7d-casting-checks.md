# M7d — Casting checks on the TV

| | |
|---|---|
| Status | Planned |
| Depends on | M7b (casting code complete), M7c (kiosk guard); both archived |
| Master plan decisions used | D12, D30 (YouTube DIAL), D31 (phone trackpad and icon), D32 (Reflector), D35 (foregrounding), D36 (kiosk lock) |
| Planned | 2026-10-14 |

## Goal

Every way of casting to the TV is confirmed on the Mac mini with real phones. A phone's YouTube app lists **MMTVL** and casts to it, cold and warm, from any screen. An Android phone mirrors through **Reflector** full screen and Home ends it. An iPhone mirrors through macOS's **AirPlay Receiver**. The phone's Plex app casts to **Plex HTPC**. The M7c kiosk guard doesn't fight any of these. The phone remote's trackpad and home-screen icon also work on a real phone. All the code is already built (M7b, M7c). This plan holds the checks that were left over when M7b and M7c were archived (2026-10-14), plus small fixes the checks turn up.

## Out of scope

- The Siri Remote driver spike (M7c step 19) and Q21: [M7e](M7e-siri-remote-spike.md).
- AirPlay to macOS's receiver playing over Live TV's sound (M7b *Risks*): macOS gives no session signal. This would need a later milestone.
- New casting features. If a check fails and the fix isn't small, record it under *Deviations & questions* and ask.

## Research & findings

The design is in the archived [M7b plan](archive/M7b-phone-and-casting.md): L1–L13 for YouTube DIAL, L14–L16 for Settings → Casting, L18–L23 for Reflector, and *Key types*. Its [research notes](archive/M7b-notes.md) cover DIAL, AirPlay and the phone icon. Facts the checks rely on:

- **YouTube DIAL:** SSDP is on UDP 1900 and DIAL on TCP 8770 (or a free port). The cold path opens `youtube.com/tv?<launch parameters>`. The warm path hands requests to leanback's own handlers through the `h5vcc.dial` shim. That only works if casting was on when the web view was created. The warm path was seen working on the dev Mac (M7b step 4): leanback registered about 1 s after load. It has never been tried with a real phone (Q13).
- **Reflector constants were set before any spike** (M7b *Deviations*): `ReflectorMonitor.bundleID = "com.squirrels.Reflector-4"`, a session is a window at least 25 % of the screen in each dimension, and a session ends after 2 missed polls. The kiosk guard always lets `ReflectorMonitor.bundleID` through (`KioskGuard.alwaysAllowed`). **If the bundle id is wrong, the guard takes the screen back from every mirroring session.**
- **Ending a session:** MMTVL first presses the window's AX close button. If it finds no close button, it posts ⌘W **to Reflector's pid** (`SyntheticInput.postKey(_:flags:toPid:)`), not to the front app.
- **Kiosk guard (M7c):** System Settings is allowed until the next Home, but only when MMTVL opened it (`KioskGuard.openedSystemSettings()`, called from Settings → Casting → AirPlay among others). A YouTube cast runs inside MMTVL, so the guard isn't involved. With Plex HTPC in front, a cast brings MMTVL forward through `Foregrounder` (D35).
- **Logs:** use the `Cast`, `Reflector`, `KioskGuard` and `Foreground` `log stream` lines in CLAUDE.md.

## Design

No new design. Small fixes allowed by the steps:

- Correct `ReflectorMonitor.bundleID` and the `MirroringDetector` constants (L19) if step 1 finds different values.
- Flip `PointerMath.scrollSign` if trackpad scrolling runs backwards (step 6).
- Change L2 (cold path) only after asking the user, as M7b step 5 says.

## Implementation steps

- [ ] **1. Reflector spike (with the user)** (from M7b step 7): no app code unless a constant changes. Results go in *Research & findings* as a "Reflector spike results" list.
  - On the mini, the user installs and licenses Reflector 4 and sets it up per L23: Advanced: AirPlay off, Google Cast on; General: Always on Top off, Show Client Name off; Connection: Display Fullscreen on, no connection prompt; receiver name "MMTVL Screen Mirroring"; device frame off (⌘B); Reflector allowed under Local Network. macOS's AirPlay Receiver stays on.
  - Record the following, with an Android phone mirroring through Quick Settings → Cast:
    1. The bundle id: `mdls -name kMDItemCFBundleIdentifier "/Applications/Reflector 4.app"`. If it differs, update `ReflectorMonitor.bundleID`; the kiosk guard and CLAUDE.md follow from it.
    2. Reflector's windows when idle, while mirroring and after the phone stops. Use the `CGWindowListCopyWindowInfo` script in M7b step 7. The 25 % rule is right if idle windows are below it and the session window is above it.
    3. With MMTVL in front, does the mirroring window come forward by itself? Is it a native full-screen Space, or a plain window covering the screen?
    4. Escape in the session window. The close button: confirm it with Accessibility Inspector, press it, and check whether the phone's cast ends. Then do the same with ⌘W.
    5. When the phone stops: does the window close, does Reflector keep running, and which app is frontmost?
    6. Does the phone's sound play through the TV?
    7. Run `lsof -nP -iUDP:1900` with Reflector running, then start MMTVL with casting on. Settings → Casting → YouTube should say ready, and both Android's Cast tile and the YouTube app should still work. Run the M-SEARCH line from CLAUDE.md: does Reflector answer too?
    8. With Reflector running, does an iPhone's Screen Mirroring to the Mac still work?
    9. In the Android YouTube app's Cast list, which entries appear, and what does picking "MMTVL Screen Mirroring" do?
    10. Does Reflector have a launch-at-login or start-hidden option? Does it show a window or a Dock icon when idle?
  - Stop and ask the user if any of these happens:
    - Idle windows can't be told apart from a session window.
    - Neither the close button nor ⌘W ends the cast.
    - Reflector and MMTVL can't share port 1900.
  - Done when: all ten answers are recorded, any constant change is built and tested, and the user has confirmed it.

- [ ] **2. Mirroring workflow on the TV (with the user)** (from M7b step 8's done-when, plus M7c's guard check): no files unless a check fails.
  - On the mini with Reflector set up and kiosk lock on:
    - With Reflector quit, launch MMTVL. Reflector starts hidden and MMTVL stays in front. Quit Reflector: it comes back after about 5 s.
    - Mirror from the home screen, from Live TV and from YouTube. Live TV stops and the phone's screen fills the TV with sound. **The kiosk guard doesn't take the screen back** (`KioskGuard` log: no takeback for Reflector).
    - The phone stops mirroring: MMTVL's home screen shows within about 3 s.
    - Home on the remote, and on the phone remote, while mirroring: the phone's cast ends and the home screen shows.
    - A YouTube cast from another phone while mirroring: mirroring ends and YouTube shows.
    - Escape during mirroring: full screen comes back within about 3 s, or Escape does nothing.
    - Settings → Casting → Android shows Ready and Mirroring live.
    - After restarting the Mac, Reflector runs hidden, MMTVL is in front, and there's no watermark.
  - Done when: each check is ticked in *Manual verification*, or recorded with logs under *Deviations & questions*.

- [ ] **3. YouTube casts from real phones (with the user)** (from M7b step 5, plus M7c's guard check): no files.
  - With an iPhone, and an Android phone if available, both on the same Wi-Fi and signed in to the YouTube app. Watch the `Cast` log during each check.
    1. Cold: MMTVL on the home screen, YouTube not opened since launch. Cast → "MMTVL" is listed. Pick it: MMTVL switches to YouTube and the phone says connected. Play a video, then pause, seek and change the volume from the phone.
    2. Warm: the same after YouTube was opened once and left.
    3. From Live TV: the cast leaves Live TV. With Plex HTPC in front: MMTVL comes forward and Plex keeps running (`Foreground` log). From Settings: Settings closes. With kiosk lock on, nothing snaps back.
    4. Disconnect on the phone, then cast again.
    5. After the Mac sleeps and wakes, and after switching between Wi-Fi and Ethernet, MMTVL is still listed.
    6. A YouTube tile with Require PIN still accepts casts without the PIN.
    7. Settings → Casting → Cast from the YouTube App off: the phone drops MMTVL (this can take a minute). Turned back on: MMTVL is listed again.
    8. YouTube's own Link with TV Code still pairs.
  - If the phone never lists MMTVL, check in this order:
    - Whether the M-SEARCH arrives (the log).
    - Local Network permission.
    - The firewall.
    - `lsof -nP -iUDP:1900`.
  - If MMTVL is listed but pairing fails only on the cold path, ask the user before changing L2.
  - Done when: the user confirms 1–4 on at least one phone, or the failure is recorded with logs and the user has decided what to do (Q13).

- [ ] **4. AirPlay and Settings → Casting (with the user)** (from M7b step 6's on-Mac check, plus M7c's System Settings check): no files.
  - Settings → Casting → AirPlay shows On. Turn the receiver off in System Settings and the row shows Off. If it still says On, record it: the Off state was never verified (M7b *Risks*).
  - Select on the AirPlay row opens AirDrop & Handoff in System Settings, and **the kiosk guard doesn't snap it back** until the next Home.
  - After "Allow AirPlay for: Anyone on the Same Network", an iPhone's Screen Mirroring lists the Mac and mirrors to the TV.
  - Plex HTPC's row shows Running or Not Running correctly.
  - Done when: ticked in *Manual verification*.

- [ ] **5. Plex casting (with the user)** (from M7b step 12, Q14): no files.
  - With Plex HTPC running, cast to it from the phone's Plex app. Record the Plex app version.
  - Done when: it works, or it doesn't and Q14 says so (nothing to build either way).

- [ ] **6. Phone remote page on real phones (with the user)** (from M7b steps 10 and 12): only `PointerMath.scrollSign` if scrolling runs backwards.
  - Trackpad, on an iPhone (and on Android if available):
    - The toggle switches views and is remembered after a reload.
    - In Brave: move, tap, double-tap (selects a word), two-finger tap (context menu) and two-finger scroll all work. Scrolling moves the content the same way as the finger.
    - In MMTVL: hovering a tile moves focus and clicking a tile opens it.
    - The pointer stays on screen at the edges.
    - The D-pad still works after switching back.
    - Without Accessibility, the toast shows but doesn't repeat continuously.
  - Icons:
    - Add to Home Screen on the iPhone shows the "tv" logo and the name MMTVL.
    - On Android Chrome, record which icon the shortcut used, or none.
    - Record whether the saved remote opens without browser chrome (Q9).
    - The Mac app icon shows in the Dock, Finder and the app switcher without a gray tile.
  - Done when: ticked in *Manual verification*, with Q9 recorded.

- [ ] **7. Docs and status**: files: `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, this plan.
  - CLAUDE.md:
    - Replace "to be confirmed in M7b step 7" in the Reflector bullet with the confirmed bundle id.
    - Add anything the checks changed, such as Reflector settings or the firewall.
  - Master plan:
    - Resolve Q9 and Q13–Q15 with what was found.
    - Set M7d to `Done`.
    - Move this plan to `archive/` and fix its links.
  - If any code changed, run the full test suite.
  - Done when: the docs match what was found and the tests pass.

## Tests

- No new tests unless a constant changes. In that case, update `MirroringDetectorTests` or `PointerMathTests` to match.
- Full suite: `xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test`.

## Manual verification

Carried from M7b's list and M7c step 13 on 2026-10-14.

- [ ] YouTube cast, cold: from the home screen with YouTube not opened since launch, the phone lists "MMTVL", and the cast opens YouTube and plays.
- [ ] YouTube cast, warm: after YouTube was opened and left, the same works, and the phone controls play/pause/seek/volume.
- [ ] A cast from Live TV leaves Live TV and shows YouTube. From Plex HTPC in front, MMTVL comes forward and Plex keeps running. From Settings, Settings closes. With the kiosk lock on, the guard doesn't fight the cast (M7c).
- [ ] A YouTube tile with Require PIN still accepts casts without the PIN (user choice).
- [ ] Settings → Casting → Cast from the YouTube App off: the phone no longer lists MMTVL (it may take a minute to drop from the phone's list). On again: listed.
- [ ] After sleep/wake and after switching between Wi-Fi and Ethernet, the phone still finds MMTVL.
- [ ] YouTube's own Link with TV Code still pairs.
- [ ] Settings → Casting: AirPlay On/Off follows the System Settings switch. Select opens AirDrop & Handoff, and the kiosk guard doesn't snap it back (M7c). An iPhone's Screen Mirroring lists the Mac after "Anyone on the Same Network".
- [ ] Android mirroring (Reflector):
  - Quick Settings → Cast lists "MMTVL Screen Mirroring".
  - Mirroring from the home screen, from Live TV and from YouTube takes over full screen with sound on the TV, and the kiosk guard doesn't fight it (M7c).
  - Stopping on the phone returns to the home screen.
  - Home ends it, and so does a YouTube cast.
  - After restarting the Mac, Reflector is running hidden and MMTVL is in front.
  - No watermark (licensed).
- [ ] Android YouTube app: picking "MMTVL" casts YouTube (D30). Record what picking "MMTVL Screen Mirroring" does.
- [ ] With Reflector running, iPhone AirPlay still goes to macOS's receiver.
- [ ] Plex: with Plex HTPC running, the phone's Plex app casts to it. Record the Plex app version (Q14).
- [ ] Trackpad: move, click, double-click, right-click and scroll work in Brave and in MMTVL (hovering a tile moves focus, clicking a tile opens it). The pointer stays on screen at the edges, and the D-pad still works after switching back.
- [ ] Phone icon: Add to Home Screen on iPhone shows the "tv" logo and the name "MMTVL". On Android Chrome, record which icon the shortcut used, or none (Q9).
- [ ] The Mac app icon (the "tv" logo) shows in the Dock, Finder and the app switcher, not inside a gray tile.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| Reflector's bundle id isn't `com.squirrels.Reflector-4` | Step 1 item 1; the kiosk guard takes the screen back from mirroring; Settings shows Not Installed | Update `ReflectorMonitor.bundleID` (the guard's allow-list uses it); rebuild. |
| Current phone YouTube apps don't use DIAL for this device, or YouTube's config turns it off | Step 3: MMTVL is never listed, or it's listed but nothing happens | Link with TV Code keeps working. Record in Q13; leave casting on if it's harmless, else default it off (ask). |
| Port 1900 is already bound without `SO_REUSEPORT` (Plex Media Server's DLNA, Reflector) | Settings → Casting shows "Port 1900 is in use" | Turn off DLNA in Plex Media Server. If Reflector can't share the port, the user picks Android mirroring or YouTube DIAL casting. |
| Local Network permission is denied, or the firewall blocks incoming traffic | No M-SEARCH in the log | Allow MMTVL under Privacy & Security → Local Network and in the firewall. |
| Reflector doesn't come forward, or its full screen fights MMTVL's window | Step 1 item 3; mirroring stays behind MMTVL | L20 activates it and sets AXFullScreen. If a native Space still loses, turn Display Fullscreen off. |
| Closing the window doesn't end the phone's cast | Step 1 item 4 | ⌘W fallback (L21). If neither works, Home only hides the session; ask the user. |
| Reflector isn't updated for macOS 26/27 | Crashes, no Cast discovery | L18's restart limit stops a crash loop. Record and ask (Q15). |
| Port 7000 stays open with AirPlay Receiver off | Step 4 | Record it; ask whether the row should show only "AirPlay Settings". |
| Synthetic scrolls are reversed | Step 6 | Flip `PointerMath.scrollSign`. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
