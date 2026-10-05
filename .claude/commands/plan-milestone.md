---
description: Write a detailed sub plan for a milestone from the master plan
argument-hint: <milestone id, e.g. M2>
---

Create the detailed sub plan for milestone **$ARGUMENTS**. This is planning only: do not write or change app code.

1. Read `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, `docs/plans/TEMPLATE.md`, and every existing sub plan this milestone depends on. Skim the current source under `MMTVL/` so the plan matches what actually exists (types, file layout, conventions).
2. Research anything uncertain before committing to it: Apple APIs and their platform limits, third-party libraries (current versions, SPM URLs, licenses), provider/service behavior. Prefer primary sources (Apple docs, library READMEs). Record verified facts with links in *Research & findings*, and mark anything you could not verify as **unverified** with how to verify it.
3. Ask the user about any decision that is genuinely theirs to make and that changes the design. Otherwise choose and record it as a local decision (L1, L2, …).
4. Write `docs/plans/$ARGUMENTS-<short-slug>.md` following the template. The plan's reader is a smaller model executing it without your context. Be explicit about file paths, type signatures, ordering, edge cases, known pitfalls, and a concrete "done when" for each step. The project must build after every step.
5. Update `docs/plans/MASTER_PLAN.md`: set the milestone status to `Planned` and link the sub plan. Add any new architecture-level decisions to §4 and resolve or add open questions in §7.
6. Finish with a short summary for the user: the main design choices, anything unverified, and questions that need their input.
