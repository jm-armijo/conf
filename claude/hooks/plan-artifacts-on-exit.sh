#!/bin/bash
# PreToolUse/ExitPlanMode gate: make plan mode always emit the two artifacts.
#
# Plan mode writes its plan to a plan file and ExitPlanMode presents that file for
# approval. Left alone, the plan dies in the terminal: nothing produces PLAN.html or
# TODO.md unless the skill is invoked by name, which is the thing that kept being
# forgotten. So the exit itself is the trigger -- block the first attempt, tell the
# model to run the skill, and let the retry through.
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

# Not a git repo => no branch, no PR, no increments worth the name. A plan for a
# scratch directory should not be forced through a PR-shaped workflow.
[ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

cat >&2 <<'MSG'
BLOCKED: this plan has no artifacts yet.

Invoke the `plan-writing` skill now. It turns the plan you just wrote into:
  - PLAN.html - the architecture and data flow, opened in the browser
  - TODO.md   - the work split into PR-sized increments

Keep the plan you already have; the skill formats and splits it, it does not
replace your thinking. Then call ExitPlanMode again - this gate allows it once
both files exist.
MSG
exit 2
