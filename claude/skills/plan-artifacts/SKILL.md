---
name: plan-artifacts
description: Emit a plan as a PLAN.html architecture visualisation plus a TDD-sequenced TODO.md in the repo root, git-excluded and opened in the browser. Use whenever writing an implementation plan, usually in plan mode, before any production code is written.
---

# Plan Artifacts

You are the **Planner**. Design the architectural solution and emit the execution
state machine. **Write no production code** — not a stub, not a scaffold. The two
files below are the entire deliverable.

## Procedure

1. Read the baselines that ship with this skill:
   - `templates/UI_TEMPLATE.html`
   - `templates/TODO_TEMPLATE.md`

   If `~/.config/claude-templates/UI_TEMPLATE.html` or
   `~/.config/claude-templates/TODO_TEMPLATE.md` exist, those override the
   bundled copies — a machine-local override is intentional.

2. Generate **both** files in the repository root, in the same turn:
   - **`PLAN.html`** — adapt the template to visualise *this* change: the
     components touched, the data flow between them, and the boundaries
     crossed. Replace every placeholder. A diagram that restates the file list
     is not a diagram; show what calls what and where state lands.
   - **`TODO.md`** — divide the work into atomic increments on the TDD
     lifecycle. Each increment is one behaviour: a failing test, the minimal
     code to pass it, then the refactor. An increment that cannot be expressed
     as a single failing test is still too large — split it.

3. Exclude both locally — they are working artifacts, never committed:

   ```bash
   grep -q "^PLAN.html$" .git/info/exclude || printf 'PLAN.html\nTODO.md\n' >> .git/info/exclude
   ```

4. Open the plan:

   ```bash
   open PLAN.html
   ```

5. **Halt.** Ask the user for approval and do not proceed to implementation.
   If modifications are requested, iterate on `PLAN.html` and `TODO.md`
   **simultaneously** — the diagram and the increment list must never disagree.

## Constraints

- The plan name in `<title>` and the page heading names the *change*, not the
  repository. "Session colour retention sweep", not "conf".
- `PLAN.html` is a single self-contained file: inline CSS, no external fetches.
  It is opened from `file://`, where CDN loads and web fonts are unreliable.
- Every TODO increment states its **verification command** — the exact
  invocation that proves the increment landed.
