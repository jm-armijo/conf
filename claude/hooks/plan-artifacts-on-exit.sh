#!/bin/bash
# PreToolUse/ExitPlanMode gate: make plan mode always emit the two artifacts.
#
# `plan-writing` is the instruction set for how a plan gets written here, and it
# only helps if it is consulted WHILE planning. Nothing makes that happen on its
# own: left alone the plan dies in the terminal as a wall of summary text, and
# neither PLAN.html nor TODO.md is written unless the skill is invoked by name,
# which is the thing that kept being forgotten. So the exit itself is the trigger
# -- block the first attempt, point the model at the skill, and let the retry
# through. Blocking at the exit is a late trigger for an early instruction, which
# is why the message tells the model to go back to the template rather than to
# reformat what it has.
#
# PreToolUse is the load-bearing part, not an implementation detail. It runs BEFORE
# the tool does, so the block lands before the approval prompt is ever drawn: by the
# time the user is asked to approve, PLAN.html exists and is open in their browser,
# and the plan is still editable. A PostToolUse hook would render the plan at the
# instant it stopped being reviewable, which is the whole point missed.
#
# Contract: exit 2 => blocked, stderr is fed back to the model; exit 0 => allow.
#
# The gate must fire ONCE per plan. It re-blocks only if the artifacts are missing,
# so a second ExitPlanMode after the skill has run passes straight through. Without
# that check this is an infinite loop: block, model re-exits, block again.
#
# Kept POSIX-ish on purpose - macOS /bin/bash is 3.2.

input=$(cat)

# cwd is where the model would write the artifacts, and it is the only reliable
# project root here: $PWD is the hook's own, not the session's.
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && exit 0

# Already emitted => the skill has run, this is the approval pass. Allow.
[ -f "$cwd/PLAN.html" ] && [ -f "$cwd/TODO.md" ] && exit 0

# Not a git repo => no branch, no PR, no tasks worth the name. A plan for a
# scratch directory should not be forced through a PR-shaped workflow.
[ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

cat >&2 <<'MSG'
BLOCKED: the plan has not been rendered for review yet.

Invoke the `plan-writing` skill now, before asking for approval. It is the
instructions for HOW A PLAN IS WRITTEN here, meant to be consulted while you
plan - not a formatter run over a finished one. Read it, and read the template
it points at: the template's sections are what a plan has to cover. Where your
plan does not already cover them, that is planning still to do.

A plan is delivered as:
  - PLAN.html - the plan, rendered and opened in the browser
  - TODO.md   - the work split into PR-sized tasks, with their branch names

The point is the review: the user reads PLAN.html in the browser, and the
approval you are about to ask for is an approval of what they read there. Do
not treat these as paperwork on the way out of plan mode.

Your chat output is ONE LINE plus the link - "I've generated the plan,
available at PLAN.html". No summary, no headings, no bullets. The terminal is
not where the plan gets read; duplicating it there is the thing these files
replace.

Open PLAN.html, then call ExitPlanMode again - this gate allows it once both
files exist.

If the user asks for changes, edit PLAN.html and TODO.md together and re-open
PLAN.html. Iterating on the plan happens here, not after approval.
MSG
exit 2
