#!/bin/bash
# Persistent per-session background colours, keyed on directory + branch.
#
# WHY THIS EXISTS
#
# The statusline paints the dir/branch/task block with a background colour so a
# session is identifiable WITHOUT reading the text. That only works if the
# colour is stable and if two sessions on screen together look different.
#
# Hashing the key into a palette gave neither guarantee: two live sessions could
# hash to the same code with nothing to detect it. So the colour is not derived
# any more, it is RECORDED. A key is assigned a colour once, and that assignment
# is permanent -- reopening a branch next month returns the same colour.
#
# Colours are NOT exclusive. Past PALETTE-many keys they are reused, least-used
# first. An existing row is never reassigned, so a live session's colour cannot
# change underneath it.
#
# SQLite is what makes the concurrent case safe: several sessions may render at
# the same instant, and INSERT OR IGNORE settles a race between two of them
# claiming the same new key -- one wins, the other reads the winner's value.
#
# Sourceable on its own, so you can ask for a colour from an interactive shell:
#
#   . ~/.claude/lib/session-colors.sh
#   session_color ~/code/conf master

# Config is optional in every sense: absent file, unreadable file, or a file
# missing either setting all fall through to the defaults below.
_sc_conf="${STATUSLINE_CONF:-$HOME/.claude/statusline.conf}"
# shellcheck source=/dev/null
[ -r "$_sc_conf" ] && . "$_sc_conf" 2>/dev/null
unset _sc_conf

: "${STATUSLINE_COLOR_DB:=$HOME/.claude/statusline-colors.db}"
: "${STATUSLINE_COLOR_RETENTION_DAYS:=30}"

# Clamp retention to a non-negative integer. A typo in the config must not turn
# into a malformed DELETE; fall back to the default rather than guess.
case "$STATUSLINE_COLOR_RETENTION_DAYS" in
  '' | *[!0-9]*) STATUSLINE_COLOR_RETENTION_DAYS=30 ;;
esac

# The palette, ordered so that CONSECUTIVE entries are as unlike each other as
# possible. This ordering is load-bearing, not cosmetic: assignment walks the
# list in order, so entries that sit next to each other here are handed to
# sessions that are likely to be open at the same time.
#
# Minimum CIELab distance between adjacent entries is dE 90 (mean 116). Sorting
# these same 16 codes numerically would drop that to 47.9, putting 58 next to
# 95. The list is CYCLIC -- after the 16th assignment it wraps to the first --
# so the 130 -> 18 pair is part of the guarantee too (dE 131).
#
# Two rules govern membership; both must hold for anything added here.
#
# 1. CONTRAST >= 3.0 AGAINST BOTH YELLOW AND GREEN. The segments painted on this
#    background use fixed foregrounds -- yellow rgb(205,205,0) for directory and
#    task, green rgb(0,205,0) for a clean branch -- so a background must be
#    legible under both. Scored with the WCAG relative-luminance contrast ratio;
#    a code survives only if the WORSE of its two ratios clears 3.0 (WCAG AA for
#    large text, the right bar for a single row of terminal glyphs). 4.5 leaves
#    only 6 codes in the entire 256-colour space, too few to tell checkouts
#    apart -- and NOTHING reaches 4.5 against both, the maximum being 5.0/4.1 on
#    pure black.
#
# 2. VISUALLY DISTINCT FROM EVERY OTHER ENTRY, not merely from its neighbours.
#
# Note there is no ban on reds here. An earlier version of this palette excluded
# them to avoid looking like an error state, but the block is always a solid
# painted field behind text, never a lone glyph, and distinctness matters more
# than that resemblance. 52, 126, 130, 201 and 208 are in the list on purpose.
#
# Regenerate rather than hand-edit if the foregrounds ever change: adding a code
# without re-running the ordering breaks rule 2 silently.
SESSION_COLOR_PALETTE=(18 144 126 22 201 95 21 58 53 255 52 228 235 208 24 130)

# Build the key. \x1f (unit separator) cannot occur in a path or a branch name,
# so it cannot collide the way a plain concatenation could: without it,
# directory "/a/b" + branch "c" and directory "/a" + branch "bc" are one key.
_sc_key() {
  printf '%s\x1f%s' "$1" "${2:-}"
}

# SQL-quote: double any single quote. Paths and branch names may contain one.
_sc_quote() {
  local s=$1
  printf "%s" "${s//\'/\'\'}"
}

# Every sqlite3 invocation opens with these.
#
# busy_timeout is not optional. SQLite allows one writer at a time and by
# DEFAULT gives up instantly on a locked database, printing "database is locked"
# to stderr -- and Claude Code discards the ENTIRE statusline when its command
# writes a single byte to stderr. Measured: 24 parallel writers produced 8 such
# errors without this pragma and zero bytes of stderr with it.
#
# The ceiling is deliberately far larger than any real wait. A write holds the
# lock for microseconds, so 24 contending writers should clear in single-digit
# milliseconds; the value only matters when the machine stalls hard enough to
# suspend a process mid-transaction, and there the difference between waiting
# and failing is the whole statusline. Raised from 2000 after one test run in
# a loaded suite lost rows at 2s -- unreproducible in 40 subsequent runs, 8 of
# them under full CPU saturation, which is exactly the profile of a stall
# rather than of contention. Nothing waits this long in practice; the number
# is a backstop, not a budget.
#
# WAL lets readers proceed while a writer holds the lock, which is the common
# case here: many sessions reading, one occasionally assigning. Unlike
# busy_timeout it is a property of the FILE, not the connection, so setting it
# once when the schema is created is enough -- every later connection inherits
# it.
#
# "PRAGMA busy_timeout=N" prints its new value, which would be captured by the
# caller's $(...) and read as a colour code. It cannot be silenced inline (the
# table-valued pragma_busy_timeout() form takes no argument when setting), so
# _sc_sql pairs it with a marker row and drops everything up to that marker.
_sc_mark='__sc__'

_sc_schema="CREATE TABLE IF NOT EXISTS colors(
  key        TEXT PRIMARY KEY,
  code       INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);"

# Run SQL against the DB, printing only the caller's own output. Silent on every
# failure -- a missing sqlite3, an unwritable directory, or a corrupt file must
# degrade to "no colour", never to a broken statusline.
_sc_sql() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  mkdir -p "$(dirname "$STATUSLINE_COLOR_DB")" 2>/dev/null || return 1
  # WAL is set only on the schema statement, which is a no-op after first run.
  sqlite3 "$STATUSLINE_COLOR_DB" \
    "PRAGMA busy_timeout=10000;
     PRAGMA journal_mode=WAL;
     SELECT '$_sc_mark';
     $_sc_schema
     $1" 2>/dev/null | sed "1,/^${_sc_mark}\$/d"
}

# session_color <directory> [branch]
#
# Print the code already assigned to this key, or nothing if there is none.
# READ-ONLY: never assigns, never cleans up. This is the one to call from an
# interactive shell -- opening a terminal should not claim a colour.
session_color() {
  local key
  key=$(_sc_quote "$(_sc_key "$1" "${2:-}")")
  _sc_sql "SELECT code FROM colors WHERE key='$key';"
}

# session_color_assign <directory> [branch]
#
# Print the code for this key, assigning one on first sight. This is what the
# statusline calls.
#
# Selection, when the key is new:
#   1. lowest use count across the palette, then
#   2. earliest position in SESSION_COLOR_PALETTE.
#
# Rule 2 is what makes assignment walk the ordered list: with every count at 0
# it takes the first entry, then the second, and once all 16 are used the counts
# are level again and it starts over at the top. Codes held by rows but no
# longer in the palette are simply not counted -- those rows keep their colour.
session_color_assign() {
  local key code
  key=$(_sc_quote "$(_sc_key "$1" "${2:-}")")

  # Fast path. A key that already has a colour needs no write and no cleanup,
  # and this is overwhelmingly the common case (every refresh of every session).
  code=$(_sc_sql "SELECT code FROM colors WHERE key='$key';")
  if [ -n "$code" ]; then
    printf '%s' "$code"
    return 0
  fi

  # Assign path only, as designed: cleanup is far too expensive to run on every
  # refresh, and retention is about forgetting stale assignments, not about
  # anything the read path observes.
  local cleanup=""
  if [ "$STATUSLINE_COLOR_RETENTION_DAYS" -gt 0 ]; then
    cleanup="DELETE FROM colors
             WHERE created_at < strftime('%s','now') - $((STATUSLINE_COLOR_RETENTION_DAYS * 86400));"
  fi

  # The palette as a CTE carrying each code's position, so ORDER BY can use it.
  # Passing the palette per-query rather than storing it in a table means
  # editing the array above takes effect immediately, with no migration.
  #
  # It must be a CTE: SQLite rejects column aliases on a bare subquery
  # ("(VALUES ...) AS p(code,pos)" is a syntax error), but accepts them on a
  # WITH clause.
  local values="" i=0
  for code in "${SESSION_COLOR_PALETTE[@]}"; do
    values="${values}${values:+,}($code,$i)"
    i=$((i + 1))
  done

  _sc_sql "$cleanup
    INSERT OR IGNORE INTO colors(key, code, created_at)
    SELECT '$key',
           (WITH p(code, pos) AS (VALUES $values)
            SELECT p.code
              FROM p
              LEFT JOIN colors c ON c.code = p.code
             GROUP BY p.code, p.pos
             ORDER BY COUNT(c.key) ASC, p.pos ASC
             LIMIT 1),
           strftime('%s','now');
    SELECT code FROM colors WHERE key='$key';"
}
