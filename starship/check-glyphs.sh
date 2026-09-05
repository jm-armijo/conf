#!/usr/bin/env bash
set -uo pipefail

# Escape-sequence comparison proves the prompt emits the right codepoints; it
# cannot prove the font draws them. Tofu boxes are byte-identical to real
# arrows, so this renders the prompt in a genuine Ghostty window and hands the
# operator a picture to judge.

readonly SHOT_DIR="${GLYPH_SHOT_DIR:-${TMPDIR:-/tmp}}"
readonly WINDOW_SETTLE_SECONDS=3
readonly CAPTURE_HOLD_SECONDS=30
readonly STATES_TO_RENDER=(git-clean git-dirty exit-nonzero-jobs venv-active)

die() {
  echo "check-glyphs: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not on PATH"
}

repository_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Ghostty is usually already running, and `ghostty -e` then opens a TAB in the
# existing window rather than a new window. The banner is the operator's proof
# that the frame caught this tab and not whatever else was in front.
rendering_script() {
  local root=$1 marker=$2
  cat <<SCRIPT
export STARSHIP_CONFIG="${root}/starship/starship.toml"
clear
printf '\n  ${marker}\n\n'
printf '  Every arrow and glyph below must have a shape.\n'
printf '  A hollow box, a "?" or a blank gap means the font cannot draw it.\n\n'
for state in ${STATES_TO_RENDER[*]}; do
  printf '  %-22s' "\$state"
  starship prompt --status=1 --jobs=1
  printf '\n'
done
printf '\n'
sleep ${CAPTURE_HOLD_SECONDS}
SCRIPT
}

launch_terminal() {
  ghostty -e bash --noprofile --norc -c "$1" >/dev/null 2>&1 &
}

window_geometry() {
  osascript -e \
    'tell application "System Events" to tell process "Ghostty" to get {position, size} of front window' \
    2>/dev/null
}

# screencapture cannot target a window without a CGWindowID, and nothing here
# can list one. Capturing the whole display and cropping to the window's
# Accessibility rectangle is the route that works.
crop_to_window() {
  local image=$1 geometry=$2
  local left top width height
  IFS=', ' read -r left top width height <<<"$geometry"

  [ -n "${height:-}" ] || die "could not read Ghostty's window geometry"

  sips --cropToHeightWidth "$height" "$width" \
    --cropOffset "$top" "$left" "$image" >/dev/null 2>&1 ||
    die "could not crop the capture to the window"
}

capture_display() {
  local image=$1
  screencapture -x "$image" 2>/dev/null

  # screencapture exits 0 having written nothing when Screen Recording
  # permission is denied, so only the file proves the frame exists.
  [ -s "$image" ] ||
    die "no image was written -- grant Screen Recording permission to your terminal in System Settings > Privacy & Security"
}

main() {
  require_command ghostty
  require_command screencapture
  require_command osascript

  local root image marker
  root="$(repository_root)"
  marker="GLYPH CHECK $(date +%H:%M:%S)"
  image="${SHOT_DIR}/prompt-glyphs-$(date +%Y%m%d-%H%M%S).png"

  mkdir -p "$SHOT_DIR" || die "cannot write to $SHOT_DIR"

  launch_terminal "$(rendering_script "$root" "$marker")"
  sleep "$WINDOW_SETTLE_SECONDS"

  capture_display "$image"
  crop_to_window "$image" "$(window_geometry)"

  echo "check-glyphs: wrote $image"
  echo "check-glyphs: confirm the image shows the banner \"${marker}\";"
  echo "check-glyphs: without it the capture caught another tab and proves nothing"
  echo "check-glyphs: then confirm every arrow and glyph has shape, not boxes"
}

main "$@"
