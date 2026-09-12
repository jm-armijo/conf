#!/usr/bin/env bash
set -uo pipefail

# git clean/smudge filter for OBS's config files. OBS cannot resolve a relative
# path, so the worktree must hold absolute ones while git stores placeholders —
# the absolute form bakes in a username. Two placeholders, because the scene's
# image_path sits inside the obs config dir while the ini files also point at
# ~/Movies and ~/Documents, which only a generic {{HOME}} covers.
# python3 does the rewrite because the replacement holds both spaces and
# slashes, which no single sed delimiter escapes cleanly.

# The two directions want opposite failure postures. A broken smudge only
# leaves a stale worktree path, so it replays its input; a broken clean would
# write the username straight into the index, so it must abort loudly enough
# for `required = true` to stop the commit.
mode=${1:-}

# Distinct from a plain failure so a rewrite that ran fine and found a name it
# could not mask is not also blamed on a missing python3.
UNMASKED_LEFTOVER_STATUS=3

give_up() {
  if [[ "$mode" == "clean" ]]; then
    echo "filter-mask-path: refusing to stage an unmasked path: $1" >&2
    exit 1
  fi
  return 0
}

input=$(mktemp) || {
  give_up "mktemp failed"
  exec cat
}
output=$(mktemp) || {
  give_up "mktemp failed"
  cat >"$input"
  cat "$input"
  rm -f "$input"
  exit 0
}
trap 'rm -f "$input" "$output"' EXIT
cat >"$input"

# An empty HOME would make the obs dir "/Library/..." and rewrite against a
# path this machine never uses.
rewrite=0
if [[ -n "${HOME:-}" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$mode" "$HOME" "$input" "$output" "$UNMASKED_LEFTOVER_STATUS" <<'PY'
import re, sys

mode, home, src, dst = sys.argv[1], sys.argv[2].encode("utf-8"), sys.argv[3], sys.argv[4]
UNMASKED_LEFTOVER = int(sys.argv[5])

# Substitution is keyed on *this* machine's $HOME, so a path carrying another
# user's name survives it untouched and would be staged verbatim. A trailing
# segment is required so a bare "/Users/" mention is not a home path.
LEFTOVER_HOME = re.compile(rb"/(?:Users|home)/[^/\s\"'<>:;,)\]}]+/")


# The obs config dir sits under $HOME, so cleaning $HOME first would leave a
# half-substituted "{{HOME}}/Library/Application Support/obs-studio" that no
# longer reads as the config dir. Most specific first when masking, and the
# exact mirror when expanding.
SUBSTITUTIONS = (
    (home + b"/Library/Application Support/obs-studio", b"{{OBS_CONFIG_DIR}}"),
    (home, b"{{HOME}}"),
)

with open(src, "rb") as f:
    data = f.read()
if mode == "clean":
    for absolute, placeholder in SUBSTITUTIONS:
        data = data.replace(absolute, placeholder)
    leftover = LEFTOVER_HOME.search(data)
    if leftover:
        sys.stderr.write(
            "filter-mask-path: refusing to stage a home path no substitution "
            "covers (a username other than this machine's): "
            + leftover.group(0).decode("utf-8", "replace")
            + "\n"
        )
        sys.exit(UNMASKED_LEFTOVER)
elif mode == "smudge":
    for absolute, placeholder in SUBSTITUTIONS:
        data = data.replace(placeholder, absolute)
with open(dst, "wb") as f:
    f.write(data)
PY
  rewrite=$?
else
  rewrite=1
fi

# Exit 3 is the leftover assertion, which has already explained itself on
# stderr and must not be recast as a missing interpreter.
if ((rewrite == UNMASKED_LEFTOVER_STATUS)); then
  exit 1
elif ((rewrite == 0)); then
  cat "$output"
else
  give_up "HOME unset, python3 missing, or the rewrite failed"
  cat "$input"
fi
exit 0
