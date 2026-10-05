# M<n> — <Milestone name>

| | |
|---|---|
| Status | Planned / In progress / Done / Blocked |
| Depends on | M… |
| Master plan decisions used | D… |
| Planned | YYYY-MM-DD |

## Goal

One paragraph: what exists when this milestone is done, from the user's point of view on the TV.

## Out of scope

Bullets naming what is deliberately deferred and to which milestone.

## Research & findings

Facts the planner verified (APIs, library versions, provider behavior, gotchas) with links. Executors rely on these instead of re-researching.

## Design

- New/changed files (paths) and the responsibility of each.
- Key types and their signatures (Swift sketches are fine).
- How this plugs into existing pieces (InputRouter, LauncherStore, etc.).
- Local decisions made in this plan (L1, L2, …) with one-line rationale.

## Implementation steps

Ordered and small enough to verify individually. Each step lists the files touched and a concrete "done when" check. The project must build after every step.

- [ ] **1. <Title>**: files: `…`
  - What to do.
  - Done when: …

## Tests

- Unit tests to add (file, what they assert).
- Commands to run (see CLAUDE.md).

## Manual verification

Checklist to run on the Mac (and on the TV where relevant).

## Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|

## Deviations & questions

Executors append here when the plan is wrong or ambiguous: the date, the step, what happened, and what they need. Do not silently diverge.
