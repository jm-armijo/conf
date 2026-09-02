---
name: plan-writing
description: Render a plan as PLAN.html plus a TODO.md of PR-sized increments, git-excluded and opened in the browser, then halt for approval. Use at the end of plan mode, or whenever writing an implementation plan, before any production code is written. Executing the result is the plan-execution skill's job.
---

# Plan Writing

Plan the work as you normally would. This skill is about **what the plan is
written to**, not about what makes a plan good — it adds two output files and
one halt, and changes nothing about how you research, design, or reason.

Plan mode's own plan file stays as it is. `PLAN.html` and `TODO.md` are
generated *from* the plan, alongside it.

**Write no production code here** — not a stub, not a scaffold. Executing the
plan is a separate skill (`plan-execution`).

## Procedure

1. Read the baselines that ship with this skill:
   - `assets/UI_TEMPLATE.html` — a worked example, not a blank form. Reproduce
     its structure and styling; replace its content.
   - `assets/TODO_TEMPLATE.md` — the increment template, with placeholders to fill.

   `~/.config/claude-templates/{UI_TEMPLATE.html,TODO_TEMPLATE.md}` override the
   bundled copies when present — a machine-local override is intentional.

2. Write **both** files to the repository root, in the same turn:

   - **`PLAN.html`** — the plan you already wrote, rendered for the browser: the
     components touched, the data flow between them, the boundaries crossed. A
     diagram that restates the file list is not a diagram; show what calls what
     and where state lands.

     It must also **say how the work splits into increments, and why**. That
     split is the one judgement call the user is reviewing.

   - **`TODO.md`** — the same work as increments, each carrying the six-step
     checklist from the template, copied verbatim.

   Sections the plan does not need are dropped rather than filled with filler.
   The template is a baseline, not a quota.

3. Exclude both locally — they are working artifacts, never committed:

   ```bash
   grep -q "^PLAN.html$" .git/info/exclude || printf 'PLAN.html\nTODO.md\n' >> .git/info/exclude
   ```

4. Open the plan: `open PLAN.html`

   This is the review copy. The user reads the plan in the browser, not in the
   terminal — that is what these files are for.

5. **Halt** for approval. Do not start implementing.

   Approval comes *after* the browser view, never before it: render first, then
   ask. Asking for approval and rendering afterwards defeats the skill entirely.

   Expect to iterate. When changes are requested, edit `PLAN.html` and `TODO.md`
   **together** — the architecture and the increment list must never disagree —
   re-open `PLAN.html`, and halt again. Repeat until the user approves.

## Sizing an increment

The one thing here that constrains the plan's *shape*, because it determines
what lands in each PR.

**An increment is a self-contained slice of work worth a pull request on its
own.** Not one function and its tests — too small to be worth opening a PR for.
A reviewer should be able to read it, judge it, and merge it by itself.

There is no formula; it depends on the work. Apply judgement, and defend the
split in `PLAN.html`. When in doubt, err toward **too large rather than too
small** — a PR not worth reviewing is the wrong unit.

TDD operates *inside* an increment, not across increments: test, code, test,
code, until the increment's work is done, all in one commit. Splitting the
general case from its edge case across increments is wrong — both belong to the
same one.

Increments run strictly in order, one PR each, so sequence them by dependency.

## Settle before halting

- The `/code-review` level, if the user wants something other than `high`.
- What is deliberately **out of scope**, recorded in `TODO.md` so it cannot
  drift back in mid-execution.

## Constraints

- The `<title>` and page heading name the *change*, not the repository —
  "Session colour retention sweep", not "conf".
- `PLAN.html` is one self-contained file: inline CSS, no external fetches. It is
  opened from `file://`, where CDN loads and web fonts are unreliable.
- Every increment states the **verification command** that proves it landed.
