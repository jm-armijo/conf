#!/bin/bash
# Persistent per-session background colours, keyed on directory + branch.
# Rationale and usage: README.md, "Session colours are recorded, not hashed".

_sc_conf="${STATUSLINE_CONF:-$HOME/.claude/statusline.conf}"
# shellcheck source=/dev/null
[ -r "$_sc_conf" ] && . "$_sc_conf" 2>/dev/null
unset _sc_conf

: "${STATUSLINE_COLOR_DB:=$HOME/.claude/statusline-colors.db}"
: "${STATUSLINE_COLOR_RETENTION_DAYS:=30}"

# A typo must not interpolate into a malformed DELETE.
case "$STATUSLINE_COLOR_RETENTION_DAYS" in
  '' | *[!0-9]*) STATUSLINE_COLOR_RETENTION_DAYS=30 ;;
esac

# Order is load-bearing: assignment walks the list, so adjacent entries go to
# sessions likely open together. Regenerate, never hand-edit -- see README.md.
SESSION_COLOR_PALETTE=(58 91 52 18 124 24 56 237 21 125 22 53)

# \x1f cannot occur in a path or branch: "/a/b"+"c" and "/a"+"bc" stay distinct.
_sc_key() {
  printf '%s\x1f%s' "$1" "${2:-}"
}

_sc_quote() {
  local s=$1
  printf "%s" "${s//\'/\'\'}"
}

# The pragmas below print a result row that $(...) would read as a colour code,
# and cannot be silenced inline -- so their output is dropped up to this marker.
_sc_mark='__sc__'

_sc_schema="CREATE TABLE IF NOT EXISTS colors(
  key        TEXT PRIMARY KEY,
  code       INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);"

# Silent on every failure: one byte on stderr discards the whole statusline.
_sc_sql() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  mkdir -p "$(dirname "$STATUSLINE_COLOR_DB")" 2>/dev/null || return 1
  # Without busy_timeout a locked write is abandoned silently, losing rows.
  sqlite3 "$STATUSLINE_COLOR_DB" \
    "PRAGMA busy_timeout=10000;
     PRAGMA journal_mode=WAL;
     SELECT '$_sc_mark';
     $_sc_schema
     $1" 2>/dev/null | sed "1,/^${_sc_mark}\$/d"
}

# Print this key's code, or nothing. READ-ONLY, so opening a shell claims nothing.
session_color() {
  local key
  key=$(_sc_quote "$(_sc_key "$1" "${2:-}")")
  _sc_sql "SELECT code FROM colors WHERE key='$key';"
}

# Print this key's code, assigning on first sight: least-used code, then earliest
# in the palette. A row holding a code no longer in the palette keeps its colour.
session_color_assign() {
  local key code
  key=$(_sc_quote "$(_sc_key "$1" "${2:-}")")

  # Fast path: every refresh of every session, so no write and no cleanup.
  code=$(_sc_sql "SELECT code FROM colors WHERE key='$key';")
  if [ -n "$code" ]; then
    printf '%s' "$code"
    return 0
  fi

  # Assign path only: too expensive for the read path, which observes nothing.
  local cleanup=""
  if [ "$STATUSLINE_COLOR_RETENTION_DAYS" -gt 0 ]; then
    cleanup="DELETE FROM colors
             WHERE created_at < strftime('%s','now') - $((STATUSLINE_COLOR_RETENTION_DAYS * 86400));"
  fi

  # Must be a CTE: SQLite rejects column aliases on a bare subquery, accepts them
  # on WITH. Passing the palette per-query means array edits need no migration.
  local values="" i=0
  for code in "${SESSION_COLOR_PALETTE[@]}"; do
    values="${values}${values:+,}($code,$i)"
    i=$((i + 1))
  done

  # OR IGNORE, never OR REPLACE: the loser of a race would repaint a live session.
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
