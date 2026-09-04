#!/usr/bin/env bash
#
# Renders the Starship prompt for one named state and compares it against that
# state's committed expectation.
#
# It never runs agnoster. The files under expected-prompts/ ARE the spec: the
# prompt owns its own appearance, so changing how it looks is an edit to an
# expectation plus starship.toml, not a test that has to be argued with.
#
# Usage: check-prompt.sh <state>
# Exit:  0 match, 1 mismatch or unknown state.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly EXPECTED_DIR="${PROMPT_EXPECTED_DIR:-${REPO_DIR}/test/expected-prompts}"
WORK_DIR=""

readonly STARSHIP_TOML="${REPO_DIR}/starship/starship.toml"

die() {
  echo "check-prompt: $*" >&2
  exit 1
}

# Reduce a rendered prompt to what the eye actually sees: zsh's %{ %} wrappers
# dropped, SGR runs folded into the (fg, bg) pair in force, text kept verbatim.
# Byte-parity with any other renderer is unreachable and not the point.
normalise() {
  python3 -c '
import sys, re

raw = sys.stdin.buffer.read().decode("utf-8", "replace")
raw = re.sub(r"%[{}]", "", raw)

fg = bg = None
text = []
out = []

def quote(s):
    # repr() would escape the powerline glyphs; the expectations store them as
    # characters, so only the quotes and backslashes are escaped here.
    return "\x27" + s.replace("\\", "\\\\").replace("\x27", "\\\x27") + "\x27"

def flush():
    if text:
        out.append("fg=%s bg=%s %s" % (fg, bg, quote("".join(text))))
        del text[:]

i = 0
while i < len(raw):
    match = re.match(r"\x1b\[([0-9;]*)m", raw[i:])
    if not match:
        text.append(raw[i])
        i += 1
        continue
    flush()
    for code in (match.group(1) or "0").split(";"):
        code = int(code or 0)
        if code == 0:
            fg = bg = None
        elif code == 39:
            fg = None
        elif code == 49:
            bg = None
        elif 30 <= code <= 37:
            fg = code - 30
        elif 40 <= code <= 47:
            bg = code - 40
    i += match.end()
flush()

print("\n".join(line for line in out if line.split(None, 2)[2] != "\x27\x27"))
'
}

# Each state is a set of starship flags plus a fixture directory. Keeping the
# two together means a state is defined in exactly one place.
render_state() { # <state> <fixture-dir>
  local state="$1" fixture="$2"
  local -a flags=(--status=0 --jobs=0)
  local -a env=(STARSHIP_CONFIG="$STARSHIP_TOML")

  # starship exits 0 on a broken config and reports TOML errors on stderr, so
  # stderr is the only signal a config problem gives. Kept and inspected by the
  # caller rather than discarded, otherwise a malformed starship.toml would
  # surface here as a puzzling diff.
  (cd "$fixture" && env "${env[@]}" starship prompt "${flags[@]}")
}

# Where a state is rendered from. The prompt prints the path it is standing in,
# so a fixture has to be shaped like the path its expectation records -- a raw
# mktemp directory would bake this machine's private tmp name into every
# comparison. States added later live under WORK_DIR for that reason.
#
# non-git is the exception: it exists to show the prompt outside any repository,
# and /tmp is reliably not one. Nothing is written there, only stood in, so the
# cost is only that this state alone is not hermetic.
fixture_dir() { # <state>
  case "$1" in
    non-git) echo "/tmp" ;;
    *) echo "${WORK_DIR}/home/code/conf" ;;
  esac
}

# Builds whatever a state needs on disk. non-git needs nothing, so this is empty
# until a state that does arrives.
make_fixture() { # <state> <dir>
  return 0
}

main() {
  local state="${1:-}"
  [[ -n "$state" ]] || die "usage: check-prompt.sh <state>"
  command -v starship >/dev/null || die "starship is not installed"

  local expected_file="${EXPECTED_DIR}/${state}"
  [[ -f "$expected_file" ]] || die "unknown state: ${state}"

  # Not local: the EXIT trap runs after this function's scope is gone, and a
  # local would be unset by then. Armed before mktemp so an interrupt in
  # between cannot strand the directory.
  WORK_DIR=""
  trap 'rm -rf "${WORK_DIR}"' EXIT
  WORK_DIR="$(mktemp -d)" || die "cannot create a work directory"

  local fixture
  fixture="$(fixture_dir "$state")"
  make_fixture "$state" "$fixture"

  local raw errors
  errors="${WORK_DIR}/stderr"
  raw="$(HOME="${WORK_DIR}/home" render_state "$state" "$fixture" 2>"$errors")" ||
    die "starship failed to render ${state}: $(sed -n "p" "$errors")"

  # Empty stderr is the only evidence the config parsed; exit status is not.
  [[ -s "$errors" ]] && die "starship wrote to stderr rendering ${state}: $(sed -n "p" "$errors")"

  local actual expected
  actual="$(printf '%s' "$raw" | normalise)"
  expected="$(grep -v '^#' "$expected_file")"

  [[ "$actual" == "$expected" ]] && return 0

  echo "check-prompt: ${state} does not match its expectation" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") |
    sed 's/^</expected: /; s/^>/actual:   /' >&2
  return 1
}

main "$@"
