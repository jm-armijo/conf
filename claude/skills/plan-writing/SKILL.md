---
name: plan-writing
description: Write an implementation plan as PLAN.html (architecture and data flow) plus TODO.md (the work split into PR-sized increments), git-excluded and opened in the browser, then halt for approval. Use whenever planning a change, usually in plan mode, before any production code is written. Executing the resulting plan is the plan-execution skill's job, not this one's.
---

# Plan Writing

You are the **Planner**. Design the architectural solution and emit the
execution state machine. **Write no production code** — not a stub, not a
scaffold. The two files below are the entire deliverable.

Executing the plan is a separate skill (`plan-execution`). Do not start
implementing, and do not restate the execution steps here — `TODO.md` carries
them.

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
     from the template, copied verbatim.

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

This is the one real judgement call in planning, and the thing the user is
reviewing when they read `TODO.md`.

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

Increments are executed strictly in order, one PR each, so sequence them by
dependency.

## Ask before assuming

Settle these while planning, since they change what `TODO.md` says:

- The `/code-review` level, if the user wants something other than `high`.
- Anything ambiguous about scope. Record what is deliberately excluded under
  **Out of scope** so it cannot drift back in mid-execution.

## Constraints

- The plan name in `<title>` and the page heading names the *change*, not the
  repository. "Session colour retention sweep", not "conf".
- `PLAN.html` is a single self-contained file: inline CSS, no external fetches.
  It is opened from `file://`, where CDN loads and web fonts are unreliable.
- Every TODO increment states its **verification command** — the exact
  invocation that proves the increment landed.
