#!/bin/bash
# Claude Code discards the WHOLE statusline if this writes one byte to stderr.
# STATUSLINE_DEBUG=1 unmutes it for diagnosis.
[ -z "${STATUSLINE_DEBUG:-}" ] && exec 2>/dev/null

input=$(cat)

CYAN=$'\033[36m'
YELLOW=$'\033[33m'
# Clean-tree branch only. Every PALETTE background is filtered to clear a 3.0
# contrast ratio against this green and the dirty-tree yellow, which are fixed
# theme colours (#1cd915 / #d9bd26) rather than computed -- so a regenerated
# palette must be scored against those, not against xterm's defaults.
GREEN=$'\033[32m'
PURPLE=$'\033[35m'
BLUE=$'\033[34m'
RED=$'\033[31m'
RESET=$'\033[0m'

# In context-window.conf, not statusline.conf: these describe when Claude Code
# itself compacts, not how this script displays. Sourced directly rather than via
# session-colors.sh, which is sourced far later and skipped when unreadable.
CLAUDE_CONTEXT_CONF="${CLAUDE_CONTEXT_CONF:-$HOME/.claude/context-window.conf}"
# shellcheck source=/dev/null
[ -r "$CLAUDE_CONTEXT_CONF" ] && . "$CLAUDE_CONTEXT_CONF" 2>/dev/null

: "${CTX_MAX:=200000}"
# Empirical, not documented by Anthropic, and an ABSOLUTE budget rather than a
# fraction of the window. context-window.conf carries the jq to re-measure it.
: "${CTX_RESERVE:=33000}"

# A typo must not reach the arithmetic below: it would error to stderr, or read 0.
case "$CTX_MAX" in '' | *[!0-9]*) CTX_MAX=200000 ;; esac
case "$CTX_RESERVE" in '' | *[!0-9]*) CTX_RESERVE=33000 ;; esac

MODEL=$(echo "$input" | jq -r '.model.display_name // "Opus"' 2>/dev/null)
[ -z "$MODEL" ] && MODEL="Opus"

# Primary token source. total_input_tokens excludes output, the same basis the
# compaction check uses. The sibling used_percentage divides by the RAW window
# and reads ~83.5 when compaction fires -- it is the bug this scaling fixes.
# `// empty` because the object is present but null at session start.
CW_TOK=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)
CW_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
case "$CW_TOK" in '' | *[!0-9]*) CW_TOK="" ;; esac
case "$CW_SIZE" in '' | *[!0-9]*) CW_SIZE="" ;; esac

# A MINIMUM against CTX_MAX, never an override: autoCompactWindow can cap the
# effective window below the model's native size, and CTX_MAX records that cap.
[ -n "$CW_SIZE" ] && [ "$CW_SIZE" -lt "$CTX_MAX" ] && CTX_MAX=$CW_SIZE

# FALLBACK, for a CLI predating context_window and the null window at session
# start. Sidechain entries are subagent turns and do not consume main-thread
# context. This basis includes output_tokens where context_window's does not, so
# the two agree only within 0.2-2% -- hence fallback, not primary.
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
TOK_RAW=0
if [ -n "$CW_TOK" ]; then
  TOK_RAW=$CW_TOK
elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
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
case "$TOK_RAW" in '' | *[!0-9]*) TOK_RAW=0 ;; esac

TOK_K=$(awk -v t="$TOK_RAW" 'BEGIN {printf "%.1fk", t/1000}')

# The denominator is the USABLE window: Claude Code compacts at CTX_MAX -
# CTX_RESERVE, so that point is what "full" means. Clamped at 100 because a
# large turn can cross the threshold before compaction fires. A non-positive
# CTX_USABLE reads 0% rather than letting awk print "inf" into the statusline.
CTX_USABLE=$((CTX_MAX - CTX_RESERVE))
CTX_PCT=$(awk -v u="$TOK_RAW" -v m="$CTX_USABLE" 'BEGIN {
    p = (m > 0) ? (u / m * 100) : 0
    if (p > 100) p = 100
    printf "%.0f", p
  }')
CTX_COL=$YELLOW
[ "$CTX_PCT" -ge 80 ] && CTX_COL=$RED

DIR_RAW=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$DIR_RAW" ] && DIR_RAW=$PWD
DIR=${DIR_RAW/#$HOME/\~}

# From DIR_RAW, not $PWD: the hook runs from wherever `claude` was started.
BRANCH=$(git -C "$DIR_RAW" branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
  BRANCH=$(git -C "$DIR_RAW" rev-parse --short HEAD 2>/dev/null)
fi
# Dirty means any uncommitted change, untracked files included -- so the default
# --untracked-files is required; -uno would silently narrow the predicate.
DIRTY=""
if [ -n "$BRANCH" ]; then
  [ -n "$(git -C "$DIR_RAW" status --porcelain 2>/dev/null)" ] && DIRTY=1
fi

# The payload key is session_name; customTitle is the TRANSCRIPT's shape and
# always reads empty here. Cut by character, never byte, to stay valid UTF-8.
TASK=$(echo "$input" | jq -r '.session_name // .customTitle // empty' 2>/dev/null)
TASK_MAX=30
TASK_TEXT=""
if [ -n "$TASK" ]; then
  if [ "$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -gt "$TASK_MAX" ]; then
    TASK=$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 cut -c1-$((TASK_MAX - 1)))…
  fi
  # Bare 3x with NO reset -- a reset would drop the shared background too.
  TASK_TEXT="${YELLOW} | ${TASK}"
fi

# Baked in here, not applied in LEFT, so an absent branch contributes no SGR at
# all and cannot leak onto the task segment.
BRANCH_TEXT=""
if [ -n "$BRANCH" ]; then
  BRANCH_FG=$GREEN
  [ -n "$DIRTY" ] && BRANCH_FG=$YELLOW
  BRANCH_TEXT="${BRANCH_FG} |  ${BRANCH}"
fi

# ------------------------------------------------------------ header bar ----
# Context-usage gauge. Colour is keyed on POSITION, not on CTX_PCT, and is
# deliberately NOT hashed: the bar must read identically in every session.

# This hook has no controlling TTY, so bare `tput cols` reports a hardcoded 80.
# $PPID is a wrapper shell with no TTY either -- walk the ancestry and take the
# width from the first ancestor that owns one.
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

# The renderer reserves columns, so a bar at the true width is truncated with an
# ellipsis. Raise BAR_MARGIN if one appears, lower it to make the bar reach further.
BAR_MARGIN=${STATUSLINE_BAR_MARGIN:-12}
COLS=$((COLS - BAR_MARGIN))
[ "$COLS" -lt 1 ] && COLS=1

# The palette is defined only in session-colors.sh, sourced below. The
# last-resort literal after it is deliberately NOT a copy: a stale duplicate that
# silently disagreed would be worse than an obviously reduced one.

# RECORDED, not derived: hashing could not guarantee two live sessions differed.
SESSION_COLORS_LIB="${SESSION_COLORS_LIB:-$HOME/.claude/lib/session-colors.sh}"
SEG_BG=""
if [ -r "$SESSION_COLORS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$SESSION_COLORS_LIB" 2>/dev/null
  SEG_BG=$(session_color_assign "$DIR_RAW" "$BRANCH" 2>/dev/null)
fi

if [ "${#SESSION_COLOR_PALETTE[@]}" -eq 0 ]; then
  SESSION_COLOR_PALETTE=(58 18 52 22)
fi

# A hash collision is a far better outcome than an unpainted segment.
case "$SEG_BG" in
  '' | *[!0-9]*)
    HASH_KEY="${DIR_RAW}${BRANCH}"
    # shasum, never md5/md5sum: those live only in /sbin, which is not on the
    # PATH Claude Code gives this hook, and the resulting stderr byte would
    # discard the statusline.
    HASH_HEX=$(printf '%s' "$HASH_KEY" | shasum 2>/dev/null | cut -d' ' -f1)
    [ -z "$HASH_HEX" ] && HASH_HEX=0
    HASH_HEX=${HASH_HEX:0:8}
    HASH_INT=$((16#$HASH_HEX))
    SEG_BG=${SESSION_COLOR_PALETTE[$((HASH_INT % ${#SESSION_COLOR_PALETTE[@]}))]}
    ;;
esac

BAR_FILL=$(awk -v p="$CTX_PCT" -v n="$COLS" 'BEGIN {
    f = int(n * p / 100)
    if (f < 0) f = 0; if (f > n) f = n
    print f
  }')
BAR_REST=$((COLS - BAR_FILL))

# U+2594 drawn as FOREGROUND: a background-painted cell is always a full row
# tall. If it ever renders as tofu, ▀ (U+2580) is the drop-in fallback.
BAR_GLYPH="▔"

# The waypoints exist because a single green->red lerp desaturates to olive at
# the midpoint. The 256-colour fallback is a hand-checked ladder, not a computed
# nearest-cube match: the cube is not monotonic in hue, so a computed ramp
# visibly backtracks.
#
# Built by repeat count, never by measuring: awk's length() counts BYTES here and
# the glyph is 3, so a length-based loop emits invalid UTF-8.
case "${COLORTERM:-}" in
  truecolor | 24bit) BAR_TRUECOLOR=1 ;;
  *) BAR_TRUECOLOR=0 ;;
esac

bar_gradient() { # <fill> <total>
  awk -v fill="$1" -v n="$2" -v ch="$BAR_GLYPH" -v tc="$BAR_TRUECOLOR" 'BEGIN {
    ns = split("0 0.20 0.35 0.55 0.70 0.85 1", sf, " ")
    split("60 150 225 245 250 240 215", sr, " ")
    split("200 205 210 175 130  75  35", sg, " ")
    split("70   40  30  25  20  30  35", sb, " ")

    nc = split("40 76 112 148 184 220 214 208 202 196 160", cube, " ")

    prev = ""
    for (i = 0; i < fill; i++) {
      # A one-cell bar has no span to interpolate over.
      f = (n > 1) ? i / (n - 1) : 0

      if (tc == 1) {
        for (k = 1; k < ns && sf[k + 1] < f; k++) { }
        span = sf[k + 1] - sf[k]
        t = (span > 0) ? (f - sf[k]) / span : 0
        r = int(sr[k] + (sr[k + 1] - sr[k]) * t + 0.5)
        g = int(sg[k] + (sg[k + 1] - sg[k]) * t + 0.5)
        b = int(sb[k] + (sb[k + 1] - sb[k]) * t + 0.5)
        seq = sprintf("\033[38;2;%d;%d;%dm", r, g, b)
      } else {
        j = int(f * (nc - 1) + 0.5) + 1
        seq = sprintf("\033[38;5;%dm", cube[j])
      }

      if (seq != prev) { printf "%s", seq; prev = seq }
      printf "%s", ch
    }
  }'
}

# A dim track, not blank, so the scale the fill is read against stays on screen.
bar_track() { # <count>
  awk -v n="$1" -v ch="$BAR_GLYPH" 'BEGIN { for (i = 0; i < n; i++) printf "%s", ch }'
}
HEADER="$(printf '%s\033[38;5;238m%s\033[0m' \
  "$(bar_gradient "$BAR_FILL" "$COLS")" "$(bar_track "$BAR_REST")")"

TIME=$(date +%H:%M:%S)

# Claude Code process metrics via Parent PID ($PPID = the `claude` process)
read -r cpu_raw mem_kb <<<"$(ps -p "$PPID" -o %cpu=,rss= 2>/dev/null)"
CPU=$(awk -v cpu="${cpu_raw:-0}" 'BEGIN {printf "%.0f%%", cpu}')
MEM=$(awk -v mem="${mem_kb:-0}" 'BEGIN {
    if (mem > 1048576) printf "%.1fG", mem/1048576
    else printf "%.0fM", mem/1024
}')

# ----------------------------------------------------------- metrics line ----
# dir/branch/task share ONE background: separators switch only the foreground,
# because a RESET between them would punch gaps through the block. The single
# RESET at the END is load-bearing -- without it the background bleeds on to the
# next terminal line.
SEG_BG_SGR=$'\033'"[48;5;${SEG_BG}m"
LEFT="${SEG_BG_SGR}${YELLOW}${DIR}${BRANCH_TEXT}${TASK_TEXT}${RESET}"
RIGHT="${CYAN}${MODEL}${RESET} | ${CTX_COL}ctx:${CTX_PCT}%${RESET} | ${CYAN}${TOK_K} tok${RESET} | ${PURPLE}${TIME}${RESET} | ${BLUE}cpu:${CPU} mem:${MEM}${RESET}"

# SGR stripped, then counted in CHARACTERS: `wc -m`, never awk's length(), which
# counts BYTES here and would over-count the branch glyph and any non-ASCII path.
vis_width() {
  printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

RIGHT_W=$(vis_width "$RIGHT")
PAD=$((COLS - $(vis_width "$LEFT") - RIGHT_W))

# A negative PAD is the overflow signal: wrap RIGHT onto its own line. The flip
# cannot have hysteresis -- the script is stateless -- so it toggles between 2
# and 3 lines at the boundary column during a resize. Accepted.
if [ "$PAD" -lt 0 ]; then
  # Clamped >= 0: printf reads a NEGATIVE "%*s" width as a left-justify flag and
  # silently emits nothing, leaving the group unaligned instead of erroring.
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
