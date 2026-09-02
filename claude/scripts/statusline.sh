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
# GREEN is used ONLY for a clean-tree branch. Every PALETTE background is
# filtered for contrast against both this and YELLOW -- see the PALETTE comment.
GREEN=$'\033[32m'
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
# Working-tree cleanliness, used to colour the branch segment. agnoster's rule:
# DIRTY means any uncommitted change at all -- unstaged edits, staged edits, OR
# untracked files. Unpushed commits do NOT count.
#
# `status --porcelain` prints one line per such change and nothing at all on a
# clean tree, so non-empty output is exactly the dirty predicate. Untracked files
# must be included, so the default --untracked-files=normal is what is wanted;
# do NOT "optimise" this to -uno, which would silently change the semantics.
#
# stderr is redirected here as well as by the blanket exec: outside a repo this
# prints "not a git repository", and a single stderr byte makes Claude Code
# discard the entire statusline.
#
# Cost note: this runs on every refresh and refreshInterval is 1s. On a very
# large working tree `status --porcelain` can take tens of ms; it is guarded by
# the BRANCH check so it is skipped entirely outside a repo.
DIRTY=""
if [ -n "$BRANCH" ]; then
  [ -n "$(git -C "$DIR_RAW" status --porcelain 2>/dev/null)" ] && DIRTY=1
fi

# Session name. The payload key is "session_name", NOT "customTitle".
# customTitle is the shape used in the session TRANSCRIPT (a record of
# type "custom-title"); the statusline payload builder emits it as
# `...sessionName && {session_name: sessionName}`, resolving the user-set title
# first and the AI-generated one as a fallback. Reading .customTitle here always
# yielded empty, which is why the segment was invisible -- it was never rendered
# at all rather than rendered in an unreadable colour.
#
# Absent on a session with neither title, in which case the segment AND its
# separator are dropped rather than rendering a placeholder.
# Capped at TASK_MAX chars so a long title cannot shove the right-hand group
# past the render width; the cut is by CHARACTER (cut -c is multibyte-aware
# under a UTF-8 locale), never by byte, so a truncated title stays valid UTF-8.
TASK=$(echo "$input" | jq -r '.session_name // .customTitle // empty' 2>/dev/null)
TASK_MAX=30
TASK_TEXT=""
if [ -n "$TASK" ]; then
  if [ "$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -gt "$TASK_MAX" ]; then
    TASK=$(printf '%s' "$TASK" | LC_ALL=en_US.UTF-8 cut -c1-$((TASK_MAX - 1)))…
  fi
  # Carries its own foreground so the segment is yellow regardless of what the
  # branch segment before it set. A bare 3x with NO reset: a reset would drop
  # the shared background too and punch a gap through the block.
  TASK_TEXT="${YELLOW} | ${TASK}"
fi

# Empty when not in a repo at all -> the segment is omitted entirely below,
# separator included. GREEN on a clean tree, YELLOW when dirty. The colour is
# baked in here rather than applied in LEFT so that an absent branch contributes
# no SGR at all, and so it cannot leak onto the task segment that follows.
BRANCH_TEXT=""
if [ -n "$BRANCH" ]; then
  BRANCH_FG=$GREEN
  [ -n "$DIRTY" ] && BRANCH_FG=$YELLOW
  BRANCH_TEXT="${BRANCH_FG} |  ${BRANCH}"
fi

# ------------------------------------------------------------ header bar ----
# A full-width context-usage gauge. The filled run is CTX_PCT of the bar width;
# its colour is a per-cell gradient keyed on POSITION, green at the left edge
# through to red at the right, so growing context reveals warmer colours instead
# of recolouring the whole bar. Deliberately NOT hashed -- the bar means "how
# full is the context", so it must read identically in every session.

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

# The palette lives in claude/lib/session-colors.sh as SESSION_COLOR_PALETTE
# and is NOT duplicated here -- the library is sourced below, before anything
# needs a colour, so both the database path and the hash fallback read the same
# array. Changing the palette means editing that one list; see the comment
# there for the contrast rule and the ordering constraint that govern it.
#
# A last-resort literal is declared AFTER the source below, for the case where
# the library cannot be read at all. It is deliberately a few obviously-safe
# darks rather than a copy of the real list: a stale duplicate that silently
# disagreed would be worse than an obviously reduced one, and reaching it means
# the install is already broken.

# The colour is RECORDED, not derived.
#
# Hashing the key into the palette could not guarantee two live sessions looked
# different -- nothing detected a collision. So a directory+branch is assigned a
# colour once, permanently, in a machine-local SQLite database, and reopening
# that branch months later returns the same colour. See the library for the full
# rationale and the assignment rule.
SESSION_COLORS_LIB="${SESSION_COLORS_LIB:-$HOME/.claude/lib/session-colors.sh}"
SEG_BG=""
if [ -r "$SESSION_COLORS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$SESSION_COLORS_LIB" 2>/dev/null
  SEG_BG=$(session_color_assign "$DIR_RAW" "$BRANCH" 2>/dev/null)
fi

# Only fires when the source above did not happen or did not define the array.
# In the normal case this is a no-op and the hash fallback below uses the very
# same list the database assigns from.
if [ "${#SESSION_COLOR_PALETTE[@]}" -eq 0 ]; then
  SESSION_COLOR_PALETTE=(58 18 52 22)
fi

# Fall back to hashing whenever the database could not answer -- library absent,
# sqlite3 missing, file corrupt, lock held past the timeout. A collision is a
# far better outcome than an unpainted segment.
case "$SEG_BG" in
  '' | *[!0-9]*)
    HASH_KEY="${DIR_RAW}${BRANCH}"
    # Hash to hex, then take 8 chars (fits a 32-bit int with room to spare) and
    # convert to base 10. 16#ABC is bash's base-N literal syntax.
    #
    # shasum is used rather than md5/md5sum because BOTH of those live only in
    # /sbin on macOS, which is NOT on the PATH Claude Code gives this hook. The
    # md5sum fallback therefore printed "command not found" to stderr, and the
    # statusline is discarded when its command writes to stderr -- the whole
    # line silently disappeared. shasum is in /usr/bin and always reachable.
    HASH_HEX=$(printf '%s' "$HASH_KEY" | shasum 2>/dev/null | cut -d' ' -f1)
    [ -z "$HASH_HEX" ] && HASH_HEX=0
    HASH_HEX=${HASH_HEX:0:8}
    HASH_INT=$((16#$HASH_HEX))
    SEG_BG=${SESSION_COLOR_PALETTE[$((HASH_INT % ${#SESSION_COLOR_PALETTE[@]}))]}
    ;;
esac

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

# The filled run is a GRADIENT, not a solid fill: each cell's colour is a
# function of its POSITION along the bar, never of CTX_PCT. Cell i of n is
# coloured at fraction i/(n-1), so the leftmost cell is always green and the
# rightmost cell of a full bar is always red regardless of how full the bar
# actually is. Growing context therefore extends the fill rightward and REVEALS
# progressively warmer colours, instead of recolouring the whole bar at once.
#
# THE RAMP IS PIECEWISE-LINEAR THROUGH EXPLICIT WAYPOINTS, not a straight line
# from green to red. Two reasons, and both are the point of the shape:
#
#  1. A single lerp green -> red passes through desaturated olive at the midpoint
#     -- the two endpoints' channels cross over and cancel. The waypoints hold
#     saturation >= 0.75 the whole way by routing through real yellow and orange.
#  2. Position of the warning matters more than linearity. The stops put yellow
#     at 35% and red-orange at 85%, so the bar stops reading as "green/fine"
#     roughly a third of the way across. A linear ramp instead sat at pure green
#     until ~30% and only reached yellow near 50%, which read as safe far too
#     long.
#
# Stops (fraction -> rgb), interpolated linearly between neighbours:
#   0.00  ( 60,200, 70)  green
#   0.20  (150,205, 40)  yellow-green
#   0.35  (225,210, 30)  yellow
#   0.55  (245,175, 25)  amber
#   0.70  (250,130, 20)  orange
#   0.85  (240, 75, 30)  red-orange
#   1.00  (215, 35, 35)  red
# Hue falls monotonically 139deg -> 0deg across the bar; the largest per-cell
# channel step on a 100-cell bar is 6/255, i.e. below the visible-banding floor.
#
# TWO OUTPUT PATHS, chosen by COLORTERM:
#
# * Truecolor (38;2;r;g;b) when COLORTERM is "truecolor" or "24bit". Every cell
#   gets its own exact colour, so there is no banding at any width. This is the
#   path that actually delivers smoothness -- the 6x6x6 cube physically cannot,
#   see below.
# * The ANSI-256 cube otherwise. The cube offers only 6 levels per channel, so a
#   computed green->red diagonal yields SIX distinct codes across the whole bar
#   -- ~17% of the width each, one hard jump per step. Worse, picking the nearest
#   cube code per cell is not even monotonic in hue (166 sits at 27deg, between
#   202 at 22deg and 160 at 0deg), so the ramp visibly backtracks. The fallback
#   therefore uses a HAND-CHECKED ladder of 11 fully-saturated codes whose hue is
#   strictly monotonic 120deg -> 0deg, indexed by position. It is coarser than
#   truecolor by construction; that is the cube's limit, not a bug here.
#
# The colour is a pure function of (position, width): two different sessions or
# directories at the same width produce a byte-identical bar. It encodes usage,
# not identity, so it must NOT be hashed the way the segment block below is.
#
# Built by REPEAT COUNT inside awk, never by measuring length: awk's length()
# counts BYTES in this locale and the glyph is 3 of them, so a length-based loop
# sliced the final glyph mid-sequence and emitted invalid UTF-8. Consecutive
# cells resolving to the same code still share one SGR sequence -- that collapses
# the fallback path to a handful of escapes, and is a no-op on the truecolor path
# where practically every cell differs.
#
# NOTE for anything downstream: the bar carries many more escape sequences than a
# solid fill did. Its width must be measured with SGR stripped and counted in
# CHARACTERS (vis_width below), never by the raw string's byte or char length.
case "${COLORTERM:-}" in
  truecolor | 24bit) BAR_TRUECOLOR=1 ;;
  *) BAR_TRUECOLOR=0 ;;
esac

bar_gradient() { # <fill> <total>
  awk -v fill="$1" -v n="$2" -v ch="$BAR_GLYPH" -v tc="$BAR_TRUECOLOR" 'BEGIN {
    # Waypoints, parallel arrays: sf[] fraction, sr/sg/sb[] channels.
    ns = split("0 0.20 0.35 0.55 0.70 0.85 1", sf, " ")
    split("60 150 225 245 250 240 215", sr, " ")
    split("200 205 210 175 130  75  35", sg, " ")
    split("70   40  30  25  20  30  35", sb, " ")

    # Hand-checked monotonic cube ladder for the non-truecolor path.
    nc = split("40 76 112 148 184 220 214 208 202 196 160", cube, " ")

    prev = ""
    for (i = 0; i < fill; i++) {
      # Guard n==1: a one-cell bar has no span to interpolate over, so it takes
      # the green end rather than dividing by zero.
      f = (n > 1) ? i / (n - 1) : 0

      if (tc == 1) {
        # Locate the segment holding f, then lerp within it.
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

# The unfilled remainder stays visible as a dim track (grey 238) rather than
# going blank, so the bar's full extent -- and therefore the scale the fill is
# read against -- is always on screen.
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
# Two groups: LEFT pinned to column 1, RIGHT flush against column $COLS -- the
# same width the bar was drawn at, so both lines terminate on the same column.
#
# dir/branch/task share ONE background so they read as a single continuous block
# rather than three tinted chips. Only the FOREGROUND is switched between them,
# with a bare 38;5;N -- never a RESET, which would drop the background too and
# punch unpainted gaps through the block at every separator. The single RESET
# goes at the very END of the run. It is load-bearing for more than looks:
# without it the background bleeds through the pad, the whole RIGHT group, and on
# to the next terminal line.
#
# The foregrounds are FIXED, not computed from the background: every PALETTE
# entry is filtered to clear a 3.0 contrast ratio against both of them (see the
# PALETTE comment), which is what makes a fixed choice safe here.
#   dir    -> yellow
#   branch -> GREEN when the working tree is clean, YELLOW when it is dirty
#   task   -> yellow
# BRANCH_TEXT/TASK_TEXT carry their own leading SGR and are empty when the
# segment is absent, so an omitted segment contributes no cells at all -- not
# even a stray colour change -- and cannot leave a coloured gap behind.
SEG_BG_SGR=$'\033'"[48;5;${SEG_BG}m"
LEFT="${SEG_BG_SGR}${YELLOW}${DIR}${BRANCH_TEXT}${TASK_TEXT}${RESET}"
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
