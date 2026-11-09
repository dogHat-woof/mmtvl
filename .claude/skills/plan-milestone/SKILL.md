---
name: plan-milestone
description: Research and write the detailed MMTVL sub plan for a milestone in the master plan, ready for /build-plan. Planning only, no app code.
argument-hint: <milestone id, e.g. M8>  [notes]
disable-model-invocation: true
---

# Plan an MMTVL milestone

Write the detailed sub plan for milestone **$ARGUMENTS**. This is planning only: don't write or
change app code. The generic procedure is `~/.claude/skills/plan-work/SKILL.md`. This file is the
MMTVL version and wins where they differ.

The plan's reader is `/build-plan`'s subagents (`implementer`, `designer`, `qa`) working from a
brief, without your context. Be explicit.

## 1. Read

1. `CLAUDE.md`, `docs/plans/MASTER_PLAN.md` (the milestone's §6 row, the §4 decisions it cites, §7
   open questions), `docs/plans/TEMPLATE.md`, and every sub plan this milestone depends on (archived
   ones in `docs/plans/archive/` too).
2. The current source under `MMTVL/` and `MMTVLTests/`, enough that the plan matches what actually
   exists: types, file layout, conventions (main-actor default, `nonisolated` models, Theme tokens, Glass).
   When the milestone touches several areas, fan out `Explore` agents by area in parallel and ask
   each for `file:line` facts, not file dumps.

## 2. Research

- Research anything uncertain before committing to it: Apple APIs and their limits on macOS 26
  (TCC, AX, GameController, WebKit, Network.framework), third-party libraries (current version, SPM
  URL, license: LGPL only as MPVKit's LGPL product, MIT-compatible otherwise), and provider or service
  behaviour (Plex, YouTube TV, IPTV providers, Reflector). Prefer primary sources: Apple docs, library
  READMEs and changelogs, source code.
- Record verified facts with links in *Research & findings*. Mark anything you couldn't verify as
  **unverified**, with how to verify it: on this Mac, on the MM, or on the TV. Make it a step if it gates the design.
- Findings about the current code carry `file:line`, the current behaviour, the likely cause,
  reusable code and open questions. The same goes when the user asks to **add items to an existing
  plan** (as in M7f): research each like the plan's existing findings. Add its checks to the TV-test
  step and give it a design step; the detailed design can wait.

## 3. Decide

- Ask the user about decisions that are genuinely theirs and change the design (what they'll see on
  the TV, trade-offs, anything outward-facing), with AskUserQuestion: standalone questions with a
  recommended option.
- Otherwise choose and record a local decision (L1, L2, …) with a one-line rationale.
  Architecture-level decisions go into the master plan's §4 as D-numbers.

## 4. Write `docs/plans/$ARGUMENTS-<short-slug>.md`

Follow `TEMPLATE.md`. Also:

- Every step lists its files, what to do, and a concrete **"Done when"**: a test name, an
  `xcodebuild` command and its result, a log line, or what shows on screen in `-windowed YES`. The
  project must build after every step.
- **Tag each step with its role** so `/build-plan` can route it: `[implementer]`, `[designer]`,
  `[human]` (the TV, the MM, the remote, phones; say exactly what to try and what to look for, and
  which `log show` line to run) or `[doc]`. Add `[security]` to steps that touch the areas
  `/build-plan` lists (phone remote, casting, relay, Keychain and secrets, synthetic input and the
  event tap, kiosk lock, entitlements, new packages).
- Group the `[human]` checks so they fit one or two test builds on the MM, not one build per step.
- Name the tests to add (Swift Testing, `MMTVLTests/<Suite>`) and what each asserts.
- Note new settings keys, files under `~/Library/Application Support/MMTVL/`, Keychain accounts and
  log categories, so the docs step can add them to `CLAUDE.md`. End with a `[doc]` step for that.
- Copy the master plan text a step needs into the sub plan, so a step never needs the whole master plan.

## 5. Update the master plan

Set the milestone's §6 status to `Planned` and link the sub plan. Add new decisions to §4, and
resolve or add open questions in §7. Commit the plan (`M<n>: plan`, staged by path) on the branch
the user is on, or ask which branch if it's unclear.

## 6. Report

A short summary for the user: the main design choices, anything **unverified**, the questions that
need their input, and roughly how many test builds the TV checks will take. Then: "Run
`/build-plan docs/plans/$ARGUMENTS-<slug>.md` to build it."
