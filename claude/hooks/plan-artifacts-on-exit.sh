#!/bin/bash
# PreToolUse/ExitPlanMode gate: make plan mode always emit PLAN.html + TODO.md.
# Why PreToolUse, and why it must fire once: see README "The plan-mode gate".
# Contract: exit 2 => blocked, stderr fed back to the model; exit 0 => allow.
# Kept POSIX-ish on purpose - macOS /bin/bash is 3.2.

input=$(cat)

# cwd from the payload, not $PWD -- $PWD is the hook's own, not the session's.
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && exit 0

# Both artifacts present => the skill has run; allowing here is what stops the
# gate re-blocking its own retry and making plan mode inescapable.
[ -f "$cwd/PLAN.html" ] && [ -f "$cwd/TODO.md" ] && exit 0

# Not a git repo => no branch, no PR, nothing to hang tasks off.
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
