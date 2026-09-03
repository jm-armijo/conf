---
name: plan-writing
description: How to write an implementation plan - the plan is produced as PLAN.html plus a TODO.md of PR-sized tasks with their branch names, git-excluded and opened in the browser, with one line in the chat, then halt for approval. Use whenever you are writing or revising an implementation plan, including throughout plan mode, before any production code is written. Doing the work is the development skill's job.
---

# Plan Writing

These are the instructions for **producing a plan**. Read them while planning,
not after. Research, read the code, weigh the options and decide exactly as you
normally would; what changes is where the plan lands — two files and the browser,
not the chat.

**Write no production code here** — not a stub, not a scaffold. Doing the work is
the `development` skill, which owns the steps each task runs through.

## Read the templates before you plan, not after

`assets/UI_TEMPLATE.html` is an input to the planning, not a formatter applied to
a finished plan. **Its sections are what the plan has to cover**, so read it early
enough that it shapes what you go and find out. This skill deliberately does not
restate that list — the template is the single place it is defined.

`assets/TODO_TEMPLATE.md` is the task list's shape. It is a to-do list and
nothing more: what its steps *mean* belongs to `development` and must not be
copied into the generated file.

`~/.config/claude-templates/{UI_TEMPLATE.html,TODO_TEMPLATE.md}` override the
bundled copies when present.

## The chat output is one line

**Do not write the plan into the chat** — not a summary, not the headings, not a
bullet list of findings. `ExitPlanMode`'s plan string is:

> I've generated the plan, available at `PLAN.html`.

That is the whole output.

## Procedure

1. Write **both** files to the repository root, in the same turn:

   - **`PLAN.html`** — the plan, rendered for the browser. Reproduce the
     template's structure and styling; replace its content. Drop sections the
     plan does not need rather than filling them with filler.

     A diagram that restates the file list is not a diagram; show what calls
     what and where state lands.

     It must **list the tasks with the branch name each will use**, and say why
     the work splits that way — that split is what the user is approving. The
     template's task table is where they go.

     If a task needs a step beyond the standard five, **name it there too**, so
     the user can veto it before work starts.

   - **`TODO.md`** — the same tasks as a plain checklist, in the template's
     shape, with the same numbering and branch names as `PLAN.html`.

2. **Substitute `{{VENDOR_DIR}}`** in `PLAN.html` with the expanded absolute path
   of the vendored bundle directory:

   ```bash
   printf '%s/.claude/vendor' "$HOME"
   ```

   Absolute and expanded — `PLAN.html` is written into whatever repo is being
   planned in, so a relative path cannot resolve, and HTML does not expand `~`.

   Left unsubstituted this fails **silently**: every diagram renders as raw text
   with no error of any kind. Check the written file contains no `{{`.

   Resolve the **directory** and stop. The filename after the placeholder is
   fixed template text — copy it through as-is, and never stat, list, glob,
   verify or open that file. The `AGENT / LLM` comment immediately above the
   `<script>` tag is copied into `PLAN.html` verbatim along with the tag.

3. Exclude both locally — they are working artifacts, never committed:

   ```bash
   grep -q "^PLAN.html$" .git/info/exclude || printf 'PLAN.html\nTODO.md\n' >> .git/info/exclude
   ```

4. Open the plan: `open PLAN.html`

5. **Halt** for approval, with the one-line chat output above. Do not start
   implementing.

   Approval comes *after* the browser view, never before: render first, then ask.

   Expect to iterate. When changes are requested, edit `PLAN.html` and `TODO.md`
   **together** — architecture and task list must never disagree — re-open
   `PLAN.html`, and halt again. Repeat until the user approves.

## Sizing a task

The one thing here that constrains the plan's *shape*, because it determines what
lands in each PR.

**A task is a self-contained slice of work worth a pull request on its own.** Not
one function and its tests — too small to be worth opening a PR for. A reviewer
should be able to read it, judge it, and merge it by itself.

There is no formula. Apply judgement, defend the split in `PLAN.html`, and when
in doubt err toward **too large rather than too small**. TDD operates *inside* a
task, all in one commit, so a general case and its edge case belong to the same
one. Tasks run strictly in order, one PR each — sequence them by dependency and
give each a branch name.

## Settle before halting

- The `/code-review` level, if the user wants something other than `high`.
- What is deliberately **out of scope**, recorded in `TODO.md` so it cannot drift
  back in mid-execution.

## Constraints

- The `<title>` and page heading name the *change*, not the repository —
  "Session colour retention sweep", not "conf".
- `PLAN.html` is one self-contained file apart from the vendored bundle above:
  inline CSS, no external fetches. It is opened from `file://`, where CDN loads
  and web fonts are unreliable.
- Every task states, in `PLAN.html`, the **verification command** that proves it
  landed. It goes there and not in `TODO.md`, which is a to-do list only.
