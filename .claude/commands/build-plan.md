---
description: Implement a milestone sub plan step by step
argument-hint: <path to sub plan, e.g. docs/plans/M1-launcher-shell.md>
---

Implement the sub plan at `$ARGUMENTS`.

1. Read `CLAUDE.md`, `docs/plans/MASTER_PLAN.md`, and the sub plan in full. Set the sub plan status (and the milestone row in the master plan) to `In progress`.
2. Work through the unchecked steps **in order**. For each step:
   - Make only the changes the step describes, in the files it names.
   - Build (and run the tests the step mentions). Fix failures before moving on. The project must build after every step.
   - Check the step's "done when" condition, then tick its checkbox in the sub plan.
3. Follow the plan; do not redesign. If a step is impossible, wrong, or ambiguous, or the code no longer matches the plan's assumptions, stop. Append an entry to the sub plan's *Deviations & questions* section (date, step, what happened, what you need), and ask the user. Small mechanical fixes (a typo in a type name, a missing import) may be made and noted there without stopping.
4. Steps that need the real hardware (TV, remote, Mac mini) or a human check: list them for the user at the end instead of claiming them done.
5. When all steps are done, set the statuses to `Done`, then archive the sub plan: `git mv` it into `docs/plans/archive/`, point the master plan's milestone row at `archive/<file>`, and fix relative links in and to it. Report which tests ran, which manual checks remain for the user, and any deviations.
