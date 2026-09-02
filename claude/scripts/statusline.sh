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
GREEN=$'\033[32m'
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
TASK_SEG=""
if [ -n "$TASK" ]; then
  if [ "$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -gt "$TASK_MAX" ]; then
    TASK=$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 cut -c1-$((TASK_MAX - 1)))…
  fi
  TASK_SEG=" | ${PURPLE}${TASK}${RESET}"
fi

# Empty when not in a repo at all -> the segment is omitted entirely below.
BRANCH_SEG=""
[ -n "$BRANCH" ] && BRANCH_SEG=" | ${GREEN} ${BRANCH}${RESET}"

# ------------------------------------------------------------ header bar ----
# A full-width band whose colour is derived from cwd+branch, so each terminal
# panel is visually distinct and a given checkout always gets the same colour.

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

# Palette of ANSI-256 background codes. Reds are deliberately excluded so the
# bar is never confusable with an error state: no 1, 9, 52, 88, and nothing in
# the 124-196 red spectrum. What remains is blues, greens, cyans, purples,
# oranges and browns that all read clearly under white text.
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
BAR_COLOR=${PALETTE[$((HASH_INT % ${#PALETTE[@]}))]}

# Half-height bar. A cell cannot be split vertically, so a background-painted
# run of spaces is always a FULL row tall. Instead draw U+2580 UPPER HALF BLOCK
# (▀) in the bar colour as FOREGROUND, leaving the cell background untouched:
# the glyph inks only the top half of each cell. (Swap for ▄ to sit it on the
# baseline instead of hanging from the top.)
#
# Built by REPEAT COUNT, not by measuring length: awk's length() counts BYTES in
# this locale and ▀ is 3 bytes, so a length-based loop truncated the final glyph
# mid-sequence and produced invalid UTF-8.
BAR_BODY=$(awk -v n="$COLS" 'BEGIN { for (i = 0; i < n; i++) printf "▀" }')
HEADER="$(printf '\033[38;5;%sm%s\033[0m' "$BAR_COLOR" "$BAR_BODY")"

TIME=$(date +%H:%M:%S)

# Claude Code process metrics via Parent PID ($PPID = the `claude` process)
read -r cpu_raw mem_kb <<<"$(ps -p "$PPID" -o %cpu=,rss= 2>/dev/null)"
CPU=$(awk -v cpu="${cpu_raw:-0}" 'BEGIN {printf "%.0f%%", cpu}')
MEM=$(awk -v mem="${mem_kb:-0}" 'BEGIN {
    if (mem > 1048576) printf "%.1fG", mem/1048576
    else printf "%.0fM", mem/1024
}')

# ----------------------------------------------------------- metrics line ----
# Two groups: LEFT pinned to column 1, RIGHT flush against column $COLS — the
# same width the bar was drawn at, so both lines terminate on the same column.
LEFT="${YELLOW}${DIR}${RESET}${BRANCH_SEG}${TASK_SEG}"
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

PAD=$((COLS - $(vis_width "$LEFT") - $(vis_width "$RIGHT")))
# 0 is a legitimate exact fit and must NOT be rounded up to 1 — that would push
# the right group one column past the bar's edge. Only a genuine overflow
# (negative) is clamped, to a single separating space rather than a negative
# width (which printf reads as left-justify, silently emitting nothing) or a
# wrapped line.
[ "$PAD" -lt 0 ] && PAD=1

# Render Statusline. Segments go through %s, never %b: the colour variables hold
# real ESC bytes already, and %b would additionally re-interpret backslashes
# appearing inside a branch name or path.
printf "%s\n%s%*s%s\n" "$HEADER" "$LEFT" "$PAD" "" "$RIGHT"
