#!/usr/bin/env bash
set -uo pipefail

# git clean/smudge filter for OBS scene files. OBS cannot resolve a relative
# image_path, so the worktree must hold an absolute path while git stores a
# {{OBS_CONFIG_DIR}} placeholder — the absolute one bakes in a username.
# python3 does the rewrite because the replacement holds both spaces and
# slashes, which no single sed delimiter escapes cleanly.

# The two directions want opposite failure postures. A broken smudge only
# leaves a stale worktree path, so it replays its input; a broken clean would
# write the username straight into the index, so it must abort loudly enough
# for `required = true` to stop the commit.
mode=${1:-}

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
if [[ -n "${HOME:-}" ]] && command -v python3 >/dev/null 2>&1 &&
  python3 - "$mode" "$HOME/Library/Application Support/obs-studio" \
    "$input" "$output" <<'PY'; then
import sys

PLACEHOLDER = b"{{OBS_CONFIG_DIR}}"

mode, obs_dir, src, dst = sys.argv[1], sys.argv[2].encode("utf-8"), sys.argv[3], sys.argv[4]
with open(src, "rb") as f:
    data = f.read()
if mode == "clean":
    data = data.replace(obs_dir, PLACEHOLDER)
elif mode == "smudge":
    data = data.replace(PLACEHOLDER, obs_dir)
with open(dst, "wb") as f:
    f.write(data)
PY
  cat "$output"
else
  give_up "HOME unset, python3 missing, or the rewrite failed"
  cat "$input"
fi
exit 0
