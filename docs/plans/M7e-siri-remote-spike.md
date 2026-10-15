# M7e — Spike: an own Siri Remote driver

| | |
|---|---|
| Status | Planned |
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
- Casting checks: [M7d](M7d-casting-checks.md).
- Remote Buddy's own configuration beyond recording the setting Q21 asks about.

## Research & findings

Carried from [M7c](archive/M7c-punchlist.md) (*Follow-ups*, item 16; *Deviations*, step 15):

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

- [ ] **1. Write the probe**: files: `scripts/siri-remote-probe.swift` (new)
  - Per *Design*. Keep it under about 150 lines with no dependencies beyond GameController, IOKit and Foundation.
  - Done when: `swift scripts/siri-remote-probe.swift --gc` runs on the dev Mac and prints connects for any controller (or nothing, without crashing), and `--hid` prints keyboard/mouse usages when Terminal has Input Monitoring.

- [ ] **2. Run it on the mini (with the user)**: no files.
  - Quit Remote Buddy, then quit MMTVL (or open it with `-windowed YES`, so its own controller handling doesn't take over). Grant Terminal Input Monitoring for `--hid`.
  - Run both modes. In each, press every button, each one a few times: TV, Back, Play/Pause, Siri, Volume Up, Volume Down, Power, clickpad centre, clickpad ring up/down/left/right, and touch-surface swipes and taps.
  - Repeat both modes with another app in front (Plex HTPC, then a Brave web app) to see what's readable in the background.
  - Also note what macOS does by itself for each button: volume HUD, Music opening, TV app, Siri, sleep.
  - Last, start Remote Buddy again and repeat `--gc` for the TV button only. Does controller A still appear? That tells whether today's controller A comes from the remote or from Remote Buddy.
  - With Remote Buddy running and Plex HTPC in front, look in Remote Buddy's preferences for the setting that lends the remote to other applications (HIDRemote). Record its exact name (Q21).
  - Done when: the raw output is saved (scratchpad or pasted in the conversation) for every button in both modes.

- [ ] **3. Findings and recommendation**: files: this plan
  - In *Research & findings*, add a "Probe results" table: button, GameController element, HID usage page/usage, readable in the background (yes/no for each API), and what macOS does by itself.
  - Add a recommendation, with the reason:
    - **Build it** (outline the milestone in a few lines: scope, the permission prompts it adds, what replaces Remote Buddy).
    - **Stay on Remote Buddy** plus the learned controller A.
    - **Hybrid** (e.g. GameController for everything but one button).
  - Record Q21's answer.
  - Done when: the table and the recommendation are in this plan.

- [ ] **4. Decision and status (with the user)**: files: `docs/plans/MASTER_PLAN.md`, `CLAUDE.md` (only if the Remote Buddy setup changes), this plan
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
