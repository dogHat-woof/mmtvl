# M7e — Spike: an own Siri Remote driver

| | |
|---|---|
| Status | Done (2026-11-06: build it, M7h) |
| Depends on | M7c (archived; this is its step 19 and Q21) |
| Master plan decisions used | D2, D14 (input layer), D24 (synthetic input), D27 (learned buttons), D35 (foregrounding) |
| Planned | 2026-10-14 |

## Goal

A decision, not a feature. When this spike is done, it is known which Siri Remote buttons a normal macOS app can read without Remote Buddy, through GameController and through raw HID, in front and in the background. It is also known what macOS does with each button by itself. The user then decides between two options:

- Build MMTVL's own Siri Remote driver as a new milestone. Remote Buddy would no longer be needed, and so would Plex HTPC's HIDRemote "lending" (Q21).
- Stay on Remote Buddy plus the learned **controller A** Home that works today.

No app code changes.

## Out of scope

- Building the driver. That's a new milestone if the user chooses it.
- Casting checks: [M7d](../M7d-casting-checks.md).
- Remote Buddy's own configuration beyond recording the setting Q21 asks about.

## Research & findings

Carried from [M7c](M7c-punchlist.md) (*Follow-ups*, item 16; *Deviations*, step 15):

- **What exists:**
  - `Input/ControllerInput.swift` already reads controllers through GameController. In kiosk mode it sets `GCController.shouldMonitorBackgroundEvents` after a controller connects (M2 L4/L15). It logs `Controller connected: <vendor> (<profile>)`, where the profile is extendedGamepad, microGamepad or other.
  - `Input/SyntheticInput.swift` already posts keys and mouse events to other apps (M5 L6, M7b).
- **On the mini today (2026-10-10, build 15–17):**
  - Settings → Remote Buttons → Home → Add a Button learned the Siri Remote's **TV button as controller A** (GameController). With Work in Other Apps, it brings MMTVL back from every app, Plex HTPC included.
  - Remote Buddy's Home-key mapping never reached MMTVL: there was no "Unbound key" line.
  - The clickpad still selects through Remote Buddy's Return, so on this remote **A isn't the clickpad**.
  - Game Controllers must stay on, or the TV button stops working as Home.
  - **Open:** whether that controller A comes from the Siri Remote itself or from Remote Buddy presenting a virtual controller. This spike answers it by running with Remote Buddy quit.
- **Unknowns:**
  - Which buttons GameController exposes on macOS. On tvOS, the TV button is reserved for the system, Back is `buttonMenu`, and the clickpad is the `dpad` plus `buttonA`.
  - Whether the TV and Siri buttons reach a normal app at all. Raw HID goes through `IOHIDManager` and needs the Input Monitoring permission.
  - Whether macOS also acts on Play/Pause (Music) and volume by itself.
- **Q21:** Plex HTPC embeds HIDRemote, which asks remote drivers to lend it the remote exclusively while Plex is in front. Home from Plex works on the mini through controller A (M7c step 13), so this doesn't block anything today. The Remote Buddy setting that stops lending was never recorded. An own driver makes Q21 moot.
- **Rough size if the answer is "build it":** a milestone about M5's size. It would cover:
  - The HID reader.
  - Mapping into `RemoteCommand`s.
  - Touch-surface swipes.
  - Routing to other apps through `SyntheticInput`.
  - Bluetooth reconnect and sleep.

  If the TV button can't be read, it can't be Home without Remote Buddy, unless a compromise is used (a long press, or another button).

### Probe results (2026-11-06, on the mini, Remote Buddy's trial expired so it wasn't running)

Run over SSH from throwaway probes (not `scripts/siri-remote-probe.swift`; see *Deviations*). Each probe was a command-line process that was never frontmost, with MMTVL and then Safari in front, so **every result below is a background read**.

- **The remote:** Siri Remote, Apple vendor 0x4C, product 0x315 (789, already in `RemoteBattery.productIDs`, `Input/RemoteBattery.swift:11`), paired over Bluetooth LE in System Settings. macOS exposes 7 HID interfaces: Consumer (0x0C) usages 0x01, 0x04 and 0x109; Digitizer (0x0D) 0x01, driven by `AppleMultitouchDevice`; Sensor (0x20) 0xE0 and 0x42; vendor 0xFF00 0x0B.
- **`IOHIDManager`:** matched by vendor and product, opened with `kIOHIDOptionsTypeNone` (not seized), it returned `0x0`, with no prompt and no Input Monitoring grant. **Unverified:** whether the app (not an SSH process) gets an Input Monitoring prompt.
- **Buttons:** each press sends value 1, each release value 0.

  | Button | HID usage page / usage |
  |---|---|
  | TV | Consumer 0x60 |
  | Back | Generic Desktop 0x86 (System App Menu) |
  | Play/Pause | Consumer 0xCD |
  | Volume Up / Down | Consumer 0xE9 / 0xEA |
  | Mute | Consumer 0xE2 |
  | Power | Consumer 0x30 |
  | Clickpad up / down / left / right | Consumer 0x42 / 0x43 / 0x44 / 0x45 |
  | Clickpad centre | Consumer 0x80 |
  | Siri | Consumer 0x04 (1 while held) |

- **Touch surface:** no HID input values at all (the Digitizer interface stays silent). Apple's private `MultitouchSupport` framework (`dlopen`; `MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTDeviceStart`) lists one device, family 0x91 (6 × 12 sensor, not built in), and delivers one-finger frames: a normalized x and y from 0 to 1 (offsets 32 and 36 of the 96-byte finger struct, state at 20), with touch and lift. Slides across measured about 0.20 → 0.75 in x and 0.74 → 0.29 in y.
- **Today's "controller A" Home:** the mini's `key-bindings.json` has no controller A. Its global Home bindings are the Home key (115), controller home, controller menu, and the **keyboard A key** (`keyCode 0`, no modifiers). So the TV button reached MMTVL as Remote Buddy typing "a". That binding also took every typed "a" in Safari and Brave as Home (2026-11-05 log: Home at 23:45:32 and 23:46:10 with Brave in front). This corrects *What exists* above and CLAUDE.md's Siri Remote paragraph.
- **Not probed:** GameController (`--gc`), and what macOS does by itself for each button (volume HUD, Music, sleep). The build milestone checks both first.
- **Q21:** can't be recorded (Remote Buddy expired). It's moot if MMTVL reads the remote itself, except that Plex HTPC's HIDRemote may still seize the remote while Plex is in front. That's for the build milestone to test.

### Recommendation and the user's decision (2026-11-06)

**Build it** (user decision). Every button is readable in the background without Remote Buddy, and the touch surface works through `MultitouchSupport` (private, so it needs a master-plan decision and a graceful fallback to buttons only). The user's requirements for the build milestone:

- **Normal mode:**
  - Swipes move focus like Apple TV, and clickpad clicks are the arrows and Select.
  - TV is Home in every app.
  - Other apps get keys through `SyntheticInput`.
- **Siri double-press** only enters and exits **trackpad mode**:
  - The touch surface moves the pointer (the `PhonePointer` acceleration).
  - Clickpad centre clicks, and a **long press of centre right-clicks**.
  - Back stays Back.
  - Scroll is a one-finger slide along the edge to start, then tested.
- **Volume and Mute** go to one of three targets: macOS, the AVR over HDMI-CEC, or the AVR over RS-232.
- **Power:**
  - **Short press** turns the TV and AVR off or on, like Apple TV: the displays sleep plus CEC or RS-232 power.
  - **Long press** opens a power menu: Turn Off TV, Sleep Mac mini, Relaunch MMTVL, Restart Mac mini.
  - Because MMTVL then knows it caused the hot-plug, after power-on it restarts Plex HTPC on its next open (M7f Q22) and checks that HDMI audio came back.
- **Remove the stray global "A" Home binding**, and refuse or warn when a plain letter or number key is learned as a binding that works in other apps.
- **Open (for that milestone's research):**
  - CEC from the mini: the kernel has `IOCECFamily`, a private API, and the 2026-11-05 log shows its HPD messages on this port. **Unverified** whether an app can send commands.
  - Pioneer VSX-01TXH RS-232: a USB-serial adapter, with the usual Pioneer `PO`/`PF`/`VU`/`VD`/`MO` commands **unverified** for this model.
  - Double actions from macOS's own handling.
  - Plex HTPC's HIDRemote seizing the remote.

## Design

One throwaway command-line probe, not part of the app target. It lives outside `MMTVL/` so the synchronized groups don't pick it up.

- `scripts/siri-remote-probe.swift`, run with `swift scripts/siri-remote-probe.swift [--gc | --hid]`:
  - `--gc`:
    - Observe `GCControllerDidConnect` and set `GCController.shouldMonitorBackgroundEvents = true` after the first connect.
    - For each controller, print `vendorName`, `productCategory` and the profile (`extendedGamepad` / `microGamepad` / `physicalInputProfile`).
    - Install `valueChangedHandler` on `physicalInputProfile` and print every element whose value changes: its `localizedName`, its `aliases`, and pressed or value.
    - Run the main run loop.
  - `--hid`:
    - `IOHIDManagerCreate`, matching the remote by vendor/product from the GC run. Fall back to every device with usage page Consumer (0x0C) or Generic Desktop (0x01).
    - `IOHIDManagerRegisterInputValueCallback` prints the device product name, usage page, usage and integer value of each input value.
    - Schedule with the run loop and open with `kIOHIDOptionsTypeNone`. The probe doesn't seize the device, so macOS's own handling stays visible.
  - Print only button and element identities and values. Nothing personal is read.

## Implementation steps

- [ ] **1. Write the probe** (not done as written: ad hoc probes instead, see *Deviations*): files: `scripts/siri-remote-probe.swift` (new)
  - Per *Design*. Keep it under about 150 lines with no dependencies beyond GameController, IOKit and Foundation.
  - Done when: `swift scripts/siri-remote-probe.swift --gc` runs on the dev Mac and prints connects for any controller (or nothing, without crashing), and `--hid` prints keyboard/mouse usages when Terminal has Input Monitoring.

- [x] **2. Run it on the mini (with the user)** (HID and touch only, see *Deviations*): no files.
  - Quit Remote Buddy, then quit MMTVL (or open it with `-windowed YES`, so its own controller handling doesn't take over). Grant Terminal Input Monitoring for `--hid`.
  - Run both modes. In each, press every button, each one a few times: TV, Back, Play/Pause, Siri, Volume Up, Volume Down, Power, clickpad centre, clickpad ring up/down/left/right, and touch-surface swipes and taps.
  - Repeat both modes with another app in front (Plex HTPC, then a Brave web app) to see what's readable in the background.
  - Also note what macOS does by itself for each button: volume HUD, Music opening, TV app, Siri, sleep.
  - Last, start Remote Buddy again and repeat `--gc` for the TV button only. Does controller A still appear? That tells whether today's controller A comes from the remote or from Remote Buddy.
  - With Remote Buddy running and Plex HTPC in front, look in Remote Buddy's preferences for the setting that lends the remote to other applications (HIDRemote). Record its exact name (Q21).
  - Done when: the raw output is saved (scratchpad or pasted in the conversation) for every button in both modes.

- [x] **3. Findings and recommendation**: files: this plan
  - In *Research & findings*, add a "Probe results" table: button, GameController element, HID usage page/usage, readable in the background (yes/no for each API), and what macOS does by itself.
  - Add a recommendation, with the reason:
    - **Build it** (outline the milestone in a few lines: scope, the permission prompts it adds, what replaces Remote Buddy).
    - **Stay on Remote Buddy** plus the learned controller A.
    - **Hybrid** (e.g. GameController for everything but one button).
  - Record Q21's answer.
  - Done when: the table and the recommendation are in this plan.

- [x] **4. Decision and status (with the user)**: files: `docs/plans/MASTER_PLAN.md`, `CLAUDE.md` (only if the Remote Buddy setup changes), this plan
  - The user decides. If it's "build it", add a milestone row (status `Not planned`) and a decision row in §4 if the input architecture changes. Either way, resolve Q21.
  - Delete `scripts/siri-remote-probe.swift`, unless the user wants to keep it for the build milestone.
  - Set M7e to `Done` and move this plan to `archive/`.
  - Done when: the master plan records the decision.

## Tests

None: the probe isn't part of the app, and no app code changes.

## Manual verification

- [ ] The probe's GameController and HID output were captured on the mini for every Siri Remote button, with Remote Buddy quit, in front and in the background.
- [ ] Whether today's controller A comes from the remote or from Remote Buddy is known.
- [ ] Q21's Remote Buddy setting is recorded.

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| The Siri Remote only connects to macOS while Remote Buddy runs | No GC connect and no HID device with Remote Buddy quit | Pair the remote in System Settings → Bluetooth first. If it still isn't seen, record it: an own driver isn't possible, so stay on Remote Buddy. |
| The TV button never reaches an app (system-reserved) | No GC element or HID usage for it | Record it. Today's controller A path (if it comes from Remote Buddy) stays, or Home moves to a long press or another button in the build milestone. |
| Input Monitoring for Terminal can't be granted on the mini | `IOHIDManagerOpen` fails (`kIOReturnNotPermitted`) | Run `--gc` only and record the HID side as unknown. |
| Background GameController events need the app to be a regular app | `--gc` stops printing with another app in front | Record it. The app (a regular app with `shouldMonitorBackgroundEvents`) already gets background events for controller A, so test the background case through MMTVL's `Unbound`/controller log instead. |

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.

- **2026-11-06, steps 1–3:** done ad hoc during a debugging session on the mini, not as written. Remote Buddy's trial had expired, and typing "a" in the browser jumped to Home (the learned A binding, see *Probe results*). Two throwaway probes (`IOHIDManager`, and `MultitouchSupport` for touch) ran over SSH from the session's scratchpad and were deleted from the mini. `scripts/siri-remote-probe.swift` was never written. GameController and macOS's own handling of each button weren't probed; the build milestone covers them. The findings, the recommendation and the user's decision ("build it") are in *Research & findings*. **Needed:** step 4, the master plan row for the build milestone, a decision for the private `MultitouchSupport` (and maybe `IOCECFamily`), and the CLAUDE.md Siri Remote paragraph corrected. Then plan the build with `/plan-milestone`.
- **2026-11-06, step 4:** done while planning M7h: the master plan has M7h (D43–D45), Q21 is resolved (moot: Plex's HIDRemote only matches the IR receiver), and this plan is archived. CLAUDE.md's Siri Remote paragraph is corrected in M7h's docs step, when the driver replaces Remote Buddy.
