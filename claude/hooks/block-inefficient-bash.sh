#!/bin/bash
# PreToolUse/Bash gate: hard-block token-wasteful commands that a dedicated tool does better.
# Contract: exit 2 => command is blocked and stderr is fed back to the model; exit 0 => allow.
# Kept POSIX-ish on purpose - macOS /bin/bash is 3.2, so no ${var,,} and no associative arrays.

input=$(cat)

# jq is the documented way to reach the command; `// empty` keeps a missing field from
# yielding the literal string "null" and tripping a rule.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Heredoc guard MUST run before every rule below. grep matches line by line and cannot tell
# a heredoc body from a command, so `cat > s.sh <<EOF` whose body mentions cat was being
# blocked while writing a perfectly ordinary script. Anything carrying a heredoc is skipped.
printf '%s' "$cmd" | grep -qE '<<-?[[:space:]]*[A-Za-z_"'"'"']' && exit 0

# Name the replacement tool, not just the offence - this text is what the model reads and
# acts on, so it has to say what to do next.
block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Every rule anchors to a command boundary (start, ; & | && ||) so the verb only matches in
# command position - that is what keeps `concatenate`, `grep -r "cat" .` and
# `git commit -m "find and fix bug"` from being caught.
# Each also requires no `|` downstream: once output feeds another program the command is
# doing real shell work that no Read/Grep/Glob call replaces.

# Rule 1: bare `cat` - no pipe, no redirect. Read is cheaper and returns line numbers.
# Excluding `>` also spares `cat f > out` and, with the $() form, `input=$(cat)`.
if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*cat[[:space:]]+[^|>]*$'; then
  block "BLOCKED: unpiped \`cat\`. Use the Read tool instead - it costs fewer tokens and returns line numbers. Piping (cat f | grep x) is still fine."
fi

# Rule 2: recursive grep. The -[A-Za-z]*[rR] class catches bundled flags such as -rn.
if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*grep[[:space:]]+(-[A-Za-z]*[rR][A-Za-z]*[[:space:]])[^|]*$'; then
  block "BLOCKED: recursive \`grep\`. Use the Grep tool instead - it is faster and respects ignore files. Piping to head/wc is still fine."
fi

# Rule 3: find by filename only. Other predicates (-mtime, -delete, -type) are real work.
if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*find[[:space:]]+[^|]*-(name|iname)[[:space:]][^|]*$'; then
  block "BLOCKED: \`find -name\`. Use the Glob tool instead for filename matching. Piping, or find with other predicates (-mtime, -delete), is still fine."
fi

exit 0
