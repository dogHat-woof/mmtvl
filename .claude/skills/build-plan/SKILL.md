---
name: build-plan
description: Build an MMTVL milestone sub plan to completion, with this session as the orchestrator and subagents (implementer, designer, qa, security-reviewer, release) doing the steps.
argument-hint: <sub plan path, e.g. docs/plans/M<n>-<slug>.md>  [steps, e.g. "steps 9-12"]
disable-model-invocation: true
---

# Build an MMTVL sub plan

Implement the sub plan at `$ARGUMENTS`. **This session is the orchestrator**: it decides, delegates,
checks and commits. The subagents in `~/.claude/agents/` do the work. They can't start subagents
themselves, so this always runs in the main session.

The generic procedure is `~/.claude/skills/orchestrate-plan/SKILL.md` and the brief templates are
`~/.claude/skills/orchestrate-plan/briefs.md`. Read the briefs before your first delegation. This file
is the MMTVL version and wins where they differ.

| Agent | In MMTVL it does | Model |
|---|---|---|
| `implementer` | Swift steps and fixes, under `MMTVL/` and `MMTVLTests/`; builds and tests | Opus |
| `designer` | UI steps: SwiftUI on the 1920×1080 canvas with `DesignSystem/` tokens, Liquid Glass (D29); `.pen` designs through Pencil | Opus |
| `qa` | verifies each step: diff vs plan, build, full suite, launches `-windowed YES` and reads the log | Opus |
| `security-reviewer` | sensitive diffs (list below) and once before a build goes to the MM | Opus |
| `release` | `scripts/test-build.sh`, `scripts/deploy-mm.sh`, PRs and merges, **only after the user says yes** | Sonnet |

Never pass a `model` override. A `path-guard:` or `bash-guard:` refusal in a report means the work
belongs to someone else (the orchestrator owns git).

## 0. Set up

1. Read `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` (§4 decisions and §6 milestones; status only) and the
   sub plan in full, including its *Deviations & questions*. Leave source files to the subagents:
   you read plans, reports and diffs.
2. `git status -sb`. Uncommitted changes that aren't from this plan → ask the user before starting
   (say which files). If `master` is ahead of `origin/master`, push it first. Work happens on the
   milestone branch (`m<n>-<slug>`, e.g. `m7g-settings-redesign`); create it from `master` if it doesn't exist.
3. Set the sub plan's Status and the master plan's §6 row to `In progress`.
4. Make a task list: one item per unchecked step, then the pre-build review, the test build and the close-out.

## 1. Each step, in order

1. **Route it.**
   - Swift code → `implementer`.
   - Look and layout, motion, a new screen, a `.pen` design → `designer`. Use `implementer` after it if the step also wires up behaviour.
   - **On the TV or the MM** (remote, Siri Remote, casting from phones, Plex HTPC, display sleep, the
     real 4K picture): don't delegate. Add it to the human checks list with exactly what to try and what
     to look for, and go on to the next step that doesn't depend on it.
   - Docs only (the plan, `CLAUDE.md`, the master plan) → do it yourself.
2. **Brief it** from `briefs.md`. Always include: the sub plan path and step, what earlier steps
   changed that this one builds on, and the build and test commands:
   ```sh
   xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build build
   xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build test
   ```
   For a single test: `-only-testing:'MMTVLTests/<Suite>/<test>()'`.
   Only one subagent builds at a time: they share `build/`.
3. **Read the report**, deviations and questions first. A question, or a change to design, scope or
   behaviour → **stop**. Append to the sub plan's *Deviations & questions* (date, step, what
   happened, what's needed) and ask the user. Don't redesign. Small mechanical fixes (a type-name typo,
   an import) are noted there and work goes on.
4. **QA** with the step, its "done when" and the working-tree diff, not the implementer's
   conclusions. Tell QA how to exercise it:
   `open build/Build/Products/Debug/MMTVL.app --args -windowed YES` and the `log stream` line from
   `CLAUDE.md` for the area. Quit the app afterwards. Never launch it in kiosk mode on this Mac.
5. **On FAIL**, send the findings back to the same implementer (SendMessage), then QA again. After
   two failed rounds, stop and ask the user. On PASS, have majors fixed the same way and list the minors for the user.
6. **Security review now**, in parallel with QA, when the diff touches:
   - `RemoteServer/` (the phone remote: pairing, tokens, the WebSocket, `Web/`);
   - `Cast/` (SSDP on UDP 1900, the DIAL server on 8770) or `YouTube/YouTubeDIAL.swift` and other scripts injected into the web view;
   - `IPTV/Relay/` (the loopback relay) or `StreamResolver`;
   - `App/Keychain.swift`, or anything storing or logging IPTV URLs, Plex tokens, PINs or phone tokens;
   - `Input/SyntheticInput.swift`, `GlobalEventTap`, `KioskLock`, Accessibility (AX) calls, or the kiosk guard;
   - entitlements, signing, Info.plist privacy keys, or a new Swift package.
   Critical and high findings are fixed like QA blockers.
7. **Commit** it yourself: check `git status` and `git diff --stat`, stage by path, and commit with the
   project's subject style (`M7g step 9: centered root, no preview`; fixes as `M7g review fixes: …`)
   and the attribution trailer. Never `git add -A`.
8. **Update the sub plan**: tick the step and record QA and security findings and what was done about
   them. Keep the master plan's §6 row current. An architecture-level change goes into §4. Commit with
   the step or right after it.
9. One short line to the user per step (done, QA PASS, commit sha).

## 2. A test build for the MM (ask first)

When the steps that can be done here are finished (or the user wants a build for the TV checks):

1. One `qa` pass over the milestone's range (`git diff master...HEAD`) with the full suite, and one
   `security-reviewer` pass over it if anything sensitive changed. Give the reviewer a threshold and
   a stop condition.
2. **Ask the user** before making a build and before installing it on the MM. Then brief `release`:
   `scripts/test-build.sh` (bumps `CURRENT_PROJECT_VERSION` by 1, builds Release, zips to
   `~/Desktop/MMTVL-<version>-build<N>.zip`), and, if the user wants it installed,
   `scripts/deploy-mm.sh`. Its commit is `Build <N> for the Mac mini (M<n>)`. **A build number is never
   reused or reset**, even if the build fails.
3. Read the report's **surprises** line first, then check the zip yourself before telling the user.
4. Give the user the human checks list for that build: what to try on the TV and what to look for.
   When they report back, read the MM's log yourself over SSH (the `ssh … log show` line in
   `CLAUDE.md`; read-only, with the categories for that area) instead of asking them to copy it, and
   record the results in the sub plan. Rolling back (`scripts/deploy-mm.sh --rollback`) also needs the user's OK.

## 3. Close out

1. When every step is done (TV checks included, or moved to another milestone with the user's OK),
   set the sub plan's Status and the §6 row to `Done`. `git mv` the sub plan (and any notes file only
   it uses) into `docs/plans/archive/`, point the §6 row at `archive/<file>`, and fix relative links
   in it (`../TEMPLATE.md`) and to it from other plans.
2. Merging to `master` goes through a PR. **Ask first**, then brief `release` to open it. After it
   opens, watch CI if there is any, and merge only when the user says so.
3. Final report: steps and commit shas, tests run (with the result lines), QA and security findings
   and what was done, deviations, the checks only the user can do on the TV or MM, and anything not verified.
