---
name: plan-writing
description: How to write an implementation plan - the plan is produced as PLAN.html plus a TODO.md of PR-sized tasks with their branch names, git-excluded and opened in the browser, with one line in the chat, then halt for approval. Use whenever you are writing or revising an implementation plan, including throughout plan mode, before any production code is written. Doing the work is the development skill's job.
---

# Plan Writing

These are the instructions for **producing a plan**. Read them while planning,
not after.

Plan the work exactly as you normally would — research, read the code, weigh the
options, decide. Nothing here changes how you investigate or reason. What
changes is where the plan lands: in two files and the browser, rather than in
the chat.

**Write no production code here** — not a stub, not a scaffold. Doing the work
is a separate skill (`development`), which owns the steps each task runs
through; this skill only decides how the work splits.

## Read the templates before you plan, not after

`assets/UI_TEMPLATE.html` is an input to the planning, not a formatter applied
to a finished plan. **Its sections are what the plan has to cover**, so read it
early enough that it shapes what you go and find out. This skill deliberately
does not restate that list: the template is the single place it is defined, so
changing the shape of every future plan is an edit to that one file.

`assets/TODO_TEMPLATE.md` is the task list's shape, with placeholders to fill.
It is a to-do list and nothing more: what its steps *mean* is the `development`
skill's, and must not be copied back into the generated file.

`~/.config/claude-templates/{UI_TEMPLATE.html,TODO_TEMPLATE.md}` override the
bundled copies when present — a machine-local override is intentional.

## The chat output is one line

**Do not write the plan into the chat.** Not a summary, not the headings, not a
bullet list of what you found, not "here is a brief overview". The plan is in
`PLAN.html`; the terminal is not where it gets read.

`ExitPlanMode`'s plan string is essentially one line:

> I've generated the plan, available at `PLAN.html`.

That is the whole output. Anything more duplicates the artifact and is exactly
what these files exist to replace.

## Procedure

1. Write **both** files to the repository root, in the same turn:

   - **`PLAN.html`** — the plan, rendered for the browser. Reproduce the
     template's structure and styling; replace its content. Sections the plan
     does not need are dropped rather than filled with filler — the template is
     a baseline, not a quota.

     A diagram that restates the file list is not a diagram; show what calls
     what and where state lands.

     It must **list the tasks with the branch name each will use**, and say why
     the work splits that way. The split and the branch naming are what the
     user is approving, so they have to be visible in the browser — the
     template's task table is where they go.

     If a task needs a step beyond the standard five, **name it there too**, so
     the user can veto it before the work starts.

   - **`TODO.md`** — the same tasks as a plain checklist, in the template's
     shape, with the same numbering and branch names as `PLAN.html`.

2. **Substitute `{{VENDOR_DIR}}`** in `PLAN.html` with the expanded absolute
   path of the vendored bundle directory:

   ```bash
   printf '%s/.claude/vendor' "$HOME"
   ```

   Absolute and expanded — `PLAN.html` is written into whatever repo is being
   planned in, so a relative path cannot resolve, and HTML does not expand `~`.

   Left unsubstituted this fails **silently**: every diagram renders as raw text
   with no console error and no failure of any kind. Check the written file
   contains no `{{` before moving on.

   Resolve the **directory** and stop. The filename after the placeholder is
   fixed template text — copy it through as-is. Never stat, list, glob, verify
   the existence of, or open that file; a directory path is all that is ever
   needed. The `AGENT / LLM` comment immediately above the `<script>` tag is
   copied into `PLAN.html` verbatim along with the tag — it is not boilerplate
   to strip, because `PLAN.html` is itself a file agents will open later.

3. Exclude both locally — they are working artifacts, never committed:

   ```bash
   grep -q "^PLAN.html$" .git/info/exclude || printf 'PLAN.html\nTODO.md\n' >> .git/info/exclude
   ```

4. Open the plan: `open PLAN.html`

   This is the review copy. The user reads the plan in the browser, not in the
   terminal — that is what these files are for.

5. **Halt** for approval, with the one-line chat output above. Do not start
   implementing.

   Approval comes *after* the browser view, never before it: render first, then
   ask. Asking for approval and rendering afterwards defeats the skill entirely.

   Expect to iterate. When changes are requested, edit `PLAN.html` and `TODO.md`
   **together** — the architecture and the task list must never disagree —
   re-open `PLAN.html`, and halt again. Repeat until the user approves.

## Sizing a task

The one thing here that constrains the plan's *shape*, because it determines
what lands in each PR.

**A task is a self-contained slice of work worth a pull request on its own.**
Not one function and its tests — too small to be worth opening a PR for. A
reviewer should be able to read it, judge it, and merge it by itself.

There is no formula; it depends on the work. Apply judgement, and defend the
split in `PLAN.html`. When in doubt, err toward **too large rather than too
small** — a PR not worth reviewing is the wrong unit.

TDD operates *inside* a task, not across tasks: test, code, test, code, until
the task's work is done, all in one commit. Splitting the general case from its
edge case across tasks is wrong — both belong to the same one.

Tasks run strictly in order, one PR each, so sequence them by dependency, and
give each one a branch name.

## Settle before halting

- The `/code-review` level, if the user wants something other than `high`.
- What is deliberately **out of scope**, recorded in `TODO.md` so it cannot
  drift back in mid-execution.

## Constraints

- The `<title>` and page heading name the *change*, not the repository —
  "Session colour retention sweep", not "conf".
- `PLAN.html` is one self-contained file apart from the vendored bundle above:
  inline CSS, no external fetches. It is opened from `file://`, where CDN loads
  and web fonts are unreliable.
- Every task states, in `PLAN.html`, the **verification command** that proves it
  landed. It goes there and not in `TODO.md`, which is a to-do list only.
