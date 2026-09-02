#!/bin/bash
# Claude Code discards the WHOLE statusline if this command writes a single byte
# to stderr. Individual call sites are guarded too, but this is the structural
# backstop: any future command added below cannot silently kill the statusline.
# Set STATUSLINE_DEBUG=1 to unmute stderr when diagnosing.
[ -z "${STATUSLINE_DEBUG:-}" ] && exec 2>/dev/null

input=$(cat)

# ANSI Colour Codes
CYAN=$'\033[36m'
YELLOW=$'\033[33m'
PURPLE=$'\033[35m'
BLUE=$'\033[34m'
RED=$'\033[31m'
RESET=$'\033[0m'

# Context window ceiling (matches autoCompactWindow in settings.json)
CTX_MAX=200000

MODEL=$(echo "$input" | jq -r '.model.display_name // "Opus"' 2>/dev/null)
[ -z "$MODEL" ] && MODEL="Opus"

# Token usage is NOT in the statusline payload; it must be derived from the
# session transcript. Sum the last non-sidechain assistant usage block:
# input + cache_read + cache_creation + output == live context occupancy.
# Sidechain entries are subagent turns and do not consume main-thread context.
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
TOK_RAW=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  TOK_RAW=$(jq -s '
        [ .[] | select(.isSidechain != true and .message.usage != null) ]
        | last
        | if . == null then 0
          else [ .message.usage
                 | .input_tokens, .cache_read_input_tokens,
                   .cache_creation_input_tokens, .output_tokens ]
               | map(. // 0) | add
          end' "$TRANSCRIPT" 2>/dev/null)
fi
# Guard against jq failure / non-numeric output
case "$TOK_RAW" in '' | *[!0-9]*) TOK_RAW=0 ;; esac

TOK_K=$(awk -v t="$TOK_RAW" 'BEGIN {printf "%.1fk", t/1000}')

# ctx: % of context window consumed; turns RED past 80%
CTX_PCT=$(awk -v u="$TOK_RAW" -v m="$CTX_MAX" 'BEGIN {printf "%.0f", (m>0)?(u/m*100):0}')
CTX_COL=$YELLOW
[ "$CTX_PCT" -ge 80 ] && CTX_COL=$RED

# Working directory: the statusline payload carries it under workspace.current_dir.
# Fall back to .cwd, then to $PWD, so the segment never renders empty.
DIR_RAW=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$DIR_RAW" ] && DIR_RAW=$PWD
# Full path, with $HOME collapsed to ~ so a home-relative path stays readable.
DIR=${DIR_RAW/#$HOME/\~}

# Branch is resolved from DIR_RAW, not $PWD: the hook runs from wherever the
# `claude` process was started, which is not necessarily the session's cwd.
# --show-current is empty on a detached HEAD, so fall back to a short SHA.
BRANCH=$(git -C "$DIR_RAW" branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
  BRANCH=$(git -C "$DIR_RAW" rev-parse --short HEAD 2>/dev/null)
fi
# Session name ("customTitle"). Absent on an unnamed session, in which case the
# segment AND its separator are dropped rather than rendering a placeholder.
# Capped at TASK_MAX chars so a long title cannot shove the right-hand group
# past the render width; the cut is by CHARACTER (cut -c is multibyte-aware
# under a UTF-8 locale), never by byte, so a truncated title stays valid UTF-8.
TASK=$(echo "$input" | jq -r '.customTitle // empty' 2>/dev/null)
TASK_MAX=30
TASK_TEXT=""
if [ -n "$TASK" ]; then
  if [ "$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -gt "$TASK_MAX" ]; then
    TASK=$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 cut -c1-$((TASK_MAX - 1)))…
  fi
  TASK_TEXT=" | ${TASK}"
fi

# Empty when not in a repo at all -> the segment is omitted entirely below.
BRANCH_TEXT=""
[ -n "$BRANCH" ] && BRANCH_TEXT=" |  ${BRANCH}"

# ------------------------------------------------------------ header bar ----
# A full-width context-usage gauge: the filled run is CTX_PCT of the bar width,
# ramped green (empty) -> red (full). Deliberately NOT hashed -- the colour
# means "how full is the context", so it must read identically in every session
# at the same percentage.

# Terminal width. This hook runs with NO controlling TTY: stdin is the JSON
# payload, /dev/tty is unavailable, and bare `tput cols` therefore reports a
# hardcoded 80 rather than the real width. The parent `claude` process does own
# a TTY, so read the width from that first and keep the others as fallbacks.
# Terminal width. $PPID is NOT usable: when Claude Code runs this hook the
# immediate parent is a wrapper shell with no controlling terminal (tty "??"),
# and bare `tput cols` then reports a hardcoded 80. The real `claude` process is
# further up the tree and does own a TTY, so walk the ancestry and take the
# width from the first ancestor that has one.
COLS=${COLUMNS:-}
probe=$PPID
[ -n "$COLS" ] && probe=""
for _ in 1 2 3 4 5 6; do
  [ -z "$probe" ] && break
  [ "$probe" -le 1 ] 2>/dev/null && break
  ptty=$(ps -p "$probe" -o tty= 2>/dev/null | tr -d ' ')
  if [ -n "$ptty" ] && [ "$ptty" != "??" ] && [ -e "/dev/$ptty" ]; then
    COLS=$(stty size <"/dev/$ptty" 2>/dev/null | awk '{print $2}')
    [ -n "$COLS" ] && break
  fi
  probe=$(ps -p "$probe" -o ppid= 2>/dev/null | tr -d ' ')
done
[ -z "$COLS" ] && COLS=$(tput cols 2>/dev/null)
case "$COLS" in '' | *[!0-9]*) COLS=80 ;; esac
[ "$COLS" -lt 1 ] && COLS=80

# The renderer does not give the hook the whole terminal: it indents the block
# and reserves trailing columns (statusLine.padding = 1 is only part of it), and
# a bar drawn at the true width overflows and is truncated with an ellipsis.
# BAR_MARGIN is how many columns to hold back. Raise it if an ellipsis appears,
# lower it to make the bar reach further.
BAR_MARGIN=${STATUSLINE_BAR_MARGIN:-12}
COLS=$((COLS - BAR_MARGIN))
[ "$COLS" -lt 1 ] && COLS=1

# Palette of ANSI-256 background codes, used for the dir/branch/task block.
# Reds are deliberately excluded so the block is never confusable with an error
# state: no 1, 9, 52, 88, and nothing in the 124-196 red spectrum. What remains
# is blues, greens, cyans, purples, oranges and browns.
#
# The red ban applies ONLY here. The progress bar below is a usage gauge where
# red at 100% is the entire point, so it computes its colour arithmetically and
# never indexes this array. Do not add reds here to "match" the bar.
PALETTE=(
  17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33
  34 35 36 37 38 39 54 55 56 57 58 59 60 61 62 63 64
  65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81
  91 92 93 94 95 96 97 98 99 100 101 102 103 104 105
  106 107 108 109 110 111 112 113 114 115 116 117 118
  119 120 121 122 123 199 200 201 202 208 214 220 226
)

# Key the colour on the absolute path plus branch, so two worktrees of the same
# repo on different branches get different bars.
HASH_KEY="${DIR_RAW}${BRANCH}"
# Hash to hex, then take 8 chars (fits a 32-bit int with room to spare) and
# convert to base 10. 16#ABC is bash's base-N literal syntax.
#
# shasum is used rather than md5/md5sum because BOTH of those live only in
# /sbin on macOS, which is NOT on the PATH Claude Code gives this hook. The
# md5sum fallback therefore printed "command not found" to stderr, and the
# statusline is discarded when its command writes to stderr -- the whole line
# silently disappeared. shasum is in /usr/bin and always reachable.
HASH_HEX=$(printf '%s' "$HASH_KEY" | shasum 2>/dev/null | cut -d' ' -f1)
[ -z "$HASH_HEX" ] && HASH_HEX=0
HASH_HEX=${HASH_HEX:0:8}
HASH_INT=$((16#$HASH_HEX))
SEG_BG=${PALETTE[$((HASH_INT % ${#PALETTE[@]}))]}

# Pick a foreground that is legible on SEG_BG. The palette spans dark navies
# (17-21) through bright yellow (226); a fixed white would be unreadable on the
# bright end and a fixed black on the dark end, so this is computed, not eyeballed
# against the raw code number (which is a cube index, not a brightness).
#
# ANSI-256 layout: 16-231 is a 6x6x6 RGB cube, code = 16 + 36r + 6g + b with each
# channel 0-5 mapping to {0,95,135,175,215,255}; 232-255 is a greyscale ramp at
# 8 + 10*(code-232). Convert to RGB, take relative luminance (Rec.709 weights),
# then choose black 16 above the midpoint and white 231 below it.
SEG_FG=$(awk -v c="$SEG_BG" 'BEGIN {
    split("0 95 135 175 215 255", lv, " ")
    if (c >= 232) { r = g = b = 8 + (c - 232) * 10 }
    else {
      n = c - 16
      r = lv[int(n / 36) + 1]; g = lv[int((n % 36) / 6) + 1]; b = lv[(n % 6) + 1]
    }
    print ((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.5) ? 16 : 231
  }')

# Bar colour is a pure function of CTX_PCT -- identical in every session at the
# same fill, which is what makes it readable as a gauge rather than an ID.
# Interpolated across the same 6x6x6 cube: blue pinned at 0, red walked 0->5 and
# green 5->0, so the ramp passes green -> olive -> orange -> red continuously
# rather than snapping between hardcoded buckets.
BAR_COLOR=$(awk -v p="$CTX_PCT" 'BEGIN {
    if (p < 0) p = 0; if (p > 100) p = 100
    r = int(p * 5 / 100 + 0.5)
    g = int((100 - p) * 5 / 100 + 0.5)
    print 16 + 36 * r + 6 * g
  }')

# Fill length = CTX_PCT of the bar width. int() truncates, so the bar only shows
# a full row at a true 100% and an empty one below half a column of usage.
BAR_FILL=$(awk -v p="$CTX_PCT" -v n="$COLS" 'BEGIN {
    f = int(n * p / 100)
    if (f < 0) f = 0; if (f > n) f = n
    print f
  }')
BAR_REST=$((COLS - BAR_FILL))

# One-eighth-height bar. A cell cannot be split vertically, so a background-
# painted run of spaces is always a FULL row tall. Instead draw U+2594 UPPER ONE
# EIGHTH BLOCK (▔) as FOREGROUND, leaving the cell background untouched: the
# glyph inks only the top eighth of each cell, which is thinner than the U+2580
# UPPER HALF BLOCK (▀) this replaced. Both are East-Asian-Width "Ambiguous", i.e.
# single-column, and both are present in the installed Meslo faces. If U+2594
# ever renders as tofu, ▀ is the drop-in fallback.
#
# Built by REPEAT COUNT, not by measuring length: awk's length() counts BYTES in
# this locale and ▔ is 3 bytes, so a length-based loop truncated the final glyph
# mid-sequence and produced invalid UTF-8.
BAR_GLYPH="▔"
bar_run() {
  awk -v n="$1" -v ch="$BAR_GLYPH" 'BEGIN { for (i = 0; i < n; i++) printf "%s", ch }'
}
# The unfilled remainder stays visible as a dim track (grey 238) rather than
# going blank, so the bar's full extent -- and therefore the scale the fill is
# read against -- is always on screen.
HEADER="$(printf '\033[38;5;%sm%s\033[38;5;238m%s\033[0m' \
  "$BAR_COLOR" "$(bar_run "$BAR_FILL")" "$(bar_run "$BAR_REST")")"

TIME=$(date +%H:%M:%S)

# Claude Code process metrics via Parent PID ($PPID = the `claude` process)
read -r cpu_raw mem_kb <<<"$(ps -p "$PPID" -o %cpu=,rss= 2>/dev/null)"
CPU=$(awk -v cpu="${cpu_raw:-0}" 'BEGIN {printf "%.0f%%", cpu}')
MEM=$(awk -v mem="${mem_kb:-0}" 'BEGIN {
    if (mem > 1048576) printf "%.1fG", mem/1048576
    else printf "%.0fM", mem/1024
}')

# ----------------------------------------------------------- metrics line ----
# Two groups: LEFT pinned to column 1, RIGHT flush against column $COLS -- the
# same width the bar was drawn at, so both lines terminate on the same column.
#
# dir/branch/task share ONE background so they read as a single continuous block
# rather than three tinted chips. The RESET goes at the very END of the run, not
# after each segment: resetting between them would punch unpainted gaps through
# the block at every separator. BRANCH_TEXT/TASK_TEXT are plain text (empty when
# absent), so an omitted segment contributes no cells at all and cannot leave a
# stray coloured gap where it would have been.
#
# The trailing RESET is load-bearing for more than looks: without it the
# background bleeds through the pad, the whole RIGHT group, and on to the next
# terminal line.
SEG_SGR=$'\033'"[48;5;${SEG_BG}m"$'\033'"[38;5;${SEG_FG}m"
LEFT="${SEG_SGR}${DIR}${BRANCH_TEXT}${TASK_TEXT}${RESET}"
RIGHT="${CYAN}${MODEL}${RESET} | ${CTX_COL}ctx:${CTX_PCT}%${RESET} | ${CYAN}${TOK_K} tok${RESET} | ${PURPLE}${TIME}${RESET} | ${BLUE}cpu:${CPU} mem:${MEM}${RESET}"

# Visible width = the string with ANSI SGR sequences stripped, counted in
# CHARACTERS. Both halves matter:
#   - the sed strips \033[...m so colour codes are not billed as columns;
#   - `wc -m` under a UTF-8 locale counts characters, whereas awk's length()
#     counts BYTES in this locale and would over-count the 3-byte branch glyph
#     () and any non-ASCII path or title, shrinking the pad and pushing the
#     right group left of the bar's edge.
vis_width() {
  printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

RIGHT_W=$(vis_width "$RIGHT")
PAD=$((COLS - $(vis_width "$LEFT") - RIGHT_W))

# PAD going negative is the overflow signal: the two groups together are wider
# than the bar. Rather than let the metrics run past the bar's edge, wrap RIGHT
# onto its own line -- 2 total lines when it fits, 3 when it does not.
#
# The flip has no hysteresis and cannot have any: the script is stateless and
# re-run from scratch on every refresh, so there is nowhere to remember the
# previous layout. It will therefore toggle between 2 and 3 lines at the exact
# boundary column while the terminal is being resized. That is accepted.
if [ "$PAD" -lt 0 ]; then
  # Wrapped RIGHT is RIGHT-ALIGNED: padded out to $COLS so it stays flush
  # against the same edge the bar ends on. Clamped >= 0 because printf reads a
  # NEGATIVE "%*s" width as a left-justify flag and silently emits nothing --
  # which would leave the group unaligned instead of erroring. When RIGHT alone
  # is wider than the bar there is no alignment to be had, so it starts at
  # column 1 and is allowed to run over.
  WRAP_PAD=$((COLS - RIGHT_W))
  [ "$WRAP_PAD" -lt 0 ] && WRAP_PAD=0
  # Segments go through %s, never %b: the colour variables hold real ESC bytes
  # already, and %b would additionally re-interpret backslashes appearing inside
  # a branch name or path.
  printf "%s\n%s\n%*s%s\n" "$HEADER" "$LEFT" "$WRAP_PAD" "" "$RIGHT"
else
  # 0 is a legitimate exact fit and must NOT be rounded up to 1 -- that would
  # push the right group one column past the bar's edge.
  printf "%s\n%s%*s%s\n" "$HEADER" "$LEFT" "$PAD" "" "$RIGHT"
fi
