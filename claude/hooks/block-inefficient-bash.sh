#!/bin/bash
# PreToolUse/Bash gate. Exit 2 blocks and feeds stderr back to the model; exit 0 allows.
# POSIX-ish on purpose: macOS /bin/bash is 3.2, so no ${var,,} and no associative arrays.

input=$(cat)

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# MUST precede every rule: grep is line-based and reads a heredoc body as commands.
printf '%s' "$cmd" | grep -qE '<<-?[[:space:]]*[A-Za-z_"'"'"']' && exit 0

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Each rule anchors to a command boundary and requires no downstream `|`: piped output is
# real shell work no Read/Grep/Glob replaces. The model acts on each message below, so
# every one names the replacement tool, not just the offence.
if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*cat[[:space:]]+[^|>]*$'; then
  block "BLOCKED: unpiped \`cat\`. Use the Read tool instead - it costs fewer tokens and returns line numbers. Piping (cat f | grep x) is still fine."
fi

if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*grep[[:space:]]+(-[A-Za-z]*[rR][A-Za-z]*[[:space:]])[^|]*$'; then
  block "BLOCKED: recursive \`grep\`. Use the Grep tool instead - it is faster and respects ignore files. Piping to head/wc is still fine."
fi

if printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*find[[:space:]]+[^|]*-(name|iname)[[:space:]][^|]*$'; then
  block "BLOCKED: \`find -name\`. Use the Glob tool instead for filename matching. Piping, or find with other predicates (-mtime, -delete), is still fine."
fi

exit 0
