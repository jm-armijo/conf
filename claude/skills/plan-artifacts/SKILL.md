---
name: plan-artifacts
description: Emit a plan as a PLAN.html architecture document plus a TDD-sequenced TODO.md in the repo root, git-excluded and opened in the browser, then execute it increment by increment behind draft PRs. Use whenever writing an implementation plan, usually in plan mode, before any production code is written.
---

# Plan Artifacts

Two roles, in order: **Planner** writes the artifacts and halts; **Developer**
executes them one increment at a time. Never start the Developer phase before
the user has approved the plan.

# Planner

Design the architectural solution and emit the execution state machine.
**Write no production code** — not a stub, not a scaffold. The two files below
are the entire deliverable.

## Procedure

1. Read the baselines that ship with this skill:
   - `assets/UI_TEMPLATE.html` — a fully worked example plan, not a blank form.
     Reproduce its structure and its styling; replace its content.
   - `assets/TODO_TEMPLATE.md` — the increment template, with placeholders to fill.

   If `~/.config/claude-templates/UI_TEMPLATE.html` or
   `~/.config/claude-templates/TODO_TEMPLATE.md` exist, those override the
   bundled copies — a machine-local override is intentional.

2. Generate **both** files in the repository root, in the same turn:
   - **`PLAN.html`** — the architecture: the components touched, the data flow
     between them, and the boundaries crossed. A diagram that restates the file
     list is not a diagram; show what calls what and where state lands.
     It must also **explain how the work splits into increments, and why** —
     that split is a judgement call the user reviews, so state the reasoning.
   - **`TODO.md`** — the increments, each carrying the full six-step checklist
     from the template.

3. Exclude both locally — they are working artifacts, never committed:

   ```bash
   grep -q "^PLAN.html$" .git/info/exclude || printf 'PLAN.html\nTODO.md\n' >> .git/info/exclude
   ```

4. Open the plan:

   ```bash
   open PLAN.html
   ```

5. **Halt.** Ask the user for approval and do not start implementing.
   If modifications are requested, iterate on `PLAN.html` and `TODO.md`
   **simultaneously** — the architecture and the increment list must never
   disagree.

## Sizing an increment

**An increment is a self-contained slice of work worth a pull request on its
own.** Not one function and its tests — that is too small to be worth opening a
PR for. A reviewer should be able to read it, judge it, and merge it by itself.

There is no formula; it depends on the work, so apply judgement and defend the
split in `PLAN.html`. When in doubt, err toward **too large rather than too
small** — a PR not worth reviewing is the wrong unit.

TDD operates *inside* an increment, not across increments: write a test, add
code, write a test, add code, until the increment's work is finished. Splitting
the general case and the edge case into separate commits is wrong — both belong
to the same increment.

# Developer

Execute the approved state machine **sequentially**. One increment at a time;
do not begin the next until the current one's gate clears.

1. Read `TODO.md` in the repository root and find the current increment.
2. Execute it under strict TDD, looping steps 1↔2 until the slice is complete:
   write a failing test, implement the minimum that passes it, repeat. Run only
   the **relevant** test files while looping — the full suite is the commit
   gate's job. Refactoring happens here, under green tests.
3. Run `/code-review high` (or the level the user set while planning) and **fix
   what it finds**. The step ends clean, not merely read.
4. Commit tests and code **together in one commit**, then push. The pre-commit
   hook runs the full suite and lint gates; if it fails, fixing it is part of
   this step. **`--no-verify` is never allowed.** Done only when push succeeds.
5. `gh pr create --draft --reviewer <the user>` on the branch's first push, then
   `gh pr view --web` to open it in the browser — **every increment, not just
   the first**. Watch for review comments and address them as they land.
6. **Halt at the `MANUAL GATE`.** The work is blocked on the author's review.
   Proceed only once the PR is approved, marked ready for review, or the user
   explicitly says to move on.

Tick each checkbox as it completes and keep the progress table at the top of
`TODO.md` current — that table is how the user knows where things stand.

## Constraints

- The plan name in `<title>` and the page heading names the *change*, not the
  repository. "Session colour retention sweep", not "conf".
- `PLAN.html` is a single self-contained file: inline CSS, no external fetches.
  It is opened from `file://`, where CDN loads and web fonts are unreliable.
- Every TODO increment states its **verification command** — the exact
  invocation that proves the increment landed.
