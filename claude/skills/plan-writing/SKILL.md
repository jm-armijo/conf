---
name: plan-writing
description: How to write an implementation plan - the plan is produced as PLAN.html plus a TODO.md of PR-sized tasks with their branch names, git-excluded and opened in the browser, with one line in the chat, then halt for approval. Use whenever you are writing or revising an implementation plan, including throughout plan mode, before any production code is written. Doing the work is the development skill's job.
---

# Plan Writing

Produces the implementation plan. **Write absolutely no production code.** The `development` skill handles execution.

## Read the templates before you plan, not after
* **UI Template:** Read `~/.config/claude-templates/UI_TEMPLATE.html` (or bundled `assets/UI_TEMPLATE.html`) *before* researching. Its sections dictate the required plan content.
* **TODO Template:** Read `~/.config/claude-templates/TODO_TEMPLATE.md` (or bundled fallback) for the checklist structure. Do not copy workflow definitions into it.

## Procedure
1. **Generate Files:** Write both to the repository root simultaneously.
   * **`PLAN.html`:** Adapt the template structure/styling. Drop unused sections. Diagrams must show how information moves and how state changes, not just file lists. **List all tasks with their branch names and justify the split.** Explicitly name any non-standard steps requiring user veto.
   * **`TODO.md`:** A plain checklist matching the template's shape. Task numbering and branch names must perfectly match `PLAN.html`. Record explicitly out-of-scope items here.
2. **Resolve Vendor Path:** In `PLAN.html`, replace `{{VENDOR_DIR}}` with the expanded absolute path: `"$HOME/.claude/vendor"`. Copy the subsequent template filename as-is. Do not stat, glob, or verify the file. *Failure to expand this path results in silently broken diagrams.*
3. **Git Exclude:** Exclude both files locally (never commit):
   `grep -q "^PLAN.html$" .git/info/exclude || echo -e "PLAN.html\nTODO.md" >> .git/info/exclude`
4. **Launch:** Execute `open PLAN.html`.
5. **Halt & Output:** The chat output is one line, exactly: `I've generated the plan, available at PLAN.html.` Do not output summaries, bullet points, or headers to the chat. Wait for user approval. If changes are requested, edit both files synchronously, re-open, and halt again.

## Task Sizing
* **Size:** A task is a self-contained, mergeable PR. Err toward too large rather than too small (e.g., general case + edge cases = one task). Do not split at the function level.
* **Sequence:** Sequence strictly by dependency. 

## Strict Constraints
* **Titles:** The `<title>` and `<h1>` must name the *change* (e.g., "Session colour sweep"), not the repository.
* **Self-Contained:** `PLAN.html` must run locally via `file://`. Use inline CSS. No external network fetches.
* **Verification:** Every task must state its verification command in `PLAN.html` only (not in `TODO.md`).
* **Settle details:** Confirm the `/code-review` level before halting.
