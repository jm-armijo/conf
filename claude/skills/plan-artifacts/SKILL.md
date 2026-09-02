---
name: plan-artifacts
description: Emit a plan as a PLAN.html architecture document plus a TDD-sequenced TODO.md in the repo root, git-excluded and opened in the browser. Use whenever writing an implementation plan, usually in plan mode, before any production code is written.
---

# Plan Artifacts

You are the **Planner**. Design the architectural solution and emit the execution
state machine. **Write no production code** — not a stub, not a scaffold. The two
files below are the entire deliverable.

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
   - **`TODO.md`** — the work as atomic TDD increments. Each increment is one
     behaviour, and carries the full five-step checklist from the template:
     write tests, implement code, atomic commit (tests + code together), update
     the draft PR, then **halt for user review**. An increment that cannot be
     expressed as a single failing test is still too large — split it.

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

## During execution

Once the plan is approved and you are working through `TODO.md`:

- Tick each checkbox as it completes, and keep the progress overview at the top
  of the file in step. The file is how the user knows where things stand.
- **`MANUAL GATE: User Review` is a hard stop**, not a formality. Do not begin
  the next increment until the user has reviewed and approved the current one.

## Constraints

- The plan name in `<title>` and the page heading names the *change*, not the
  repository. "Session colour retention sweep", not "conf".
- `PLAN.html` is a single self-contained file: inline CSS, no external fetches.
  It is opened from `file://`, where CDN loads and web fonts are unreliable.
- Every TODO increment states its **verification command** — the exact
  invocation that proves the increment landed.
