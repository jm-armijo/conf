# Notes on `test/setup.bats`

Rationale that would otherwise live as long comment blocks inside the suite. The
tests carry one-line pointers back to the headings here.

## Writing tests in this suite

### `bats_run`, never `run`

`setup.sh` defines its own `run()` step-wrapper, so sourcing it **shadows bats'
built-in `run` helper** and every later `run` fails with `Permission denied`.
`setup()` copies bats' helper onto a second name *before* sourcing:

```bash
eval "bats_run() $(declare -f run | tail -n +2)"
source "${BATS_TEST_DIRNAME}/../setup.sh"
```

New tests must call `bats_run`. The same copy-the-body idiom stubs `_sc_sql` in
"a losing racer's assign never overwrites the winner's colour".

Sourcing is safe because `setup.sh`'s execution block is guarded by
`[[ "${BASH_SOURCE[0]}" == "$0" ]]`.

### Negations must be `bats_run` plus an explicit status check

A bare `! grep ...` mid-body **does not fail a bats test** — bats consults only
the last command's status. This masked a real violation: re-adding
`PALETTE=(1 2 3)` to `statusline.sh` slipped straight through a `! grep -q`.

```bash
bats_run grep -q 'forbidden' "$file"
[ "$status" -ne 0 ]
```

Or, where a helper is more convenient, an assertion on a `grep -c` count.

### Assert on effects, not on stderr alone

Two places where a stderr-only assertion passes vacuously:

- **`starship --version` exits 0 on a broken config.** A TOML syntax error goes
  to *stderr* and starship carries on with its defaults; same for `starship
  module` / `prompt`. Verified against 1.26.0. Assert **stderr is empty**, never
  exit status.
- **The concurrency test asserts on ROWS WRITTEN, not stderr.** Without
  `PRAGMA busy_timeout`, sqlite3 abandons a locked write *silently* — 13 of 24
  rows surviving with zero bytes of stderr.

### Isolation from the developer's machine

`statusline_run` and `colors_env` redirect `STATUSLINE_COLOR_DB`,
`STATUSLINE_CONF` and `CLAUDE_CONTEXT_CONF` into `$BATS_TEST_TMPDIR`. All three
are load-bearing:

- Without the DB redirect every rendering test writes into the developer's
  **live** `~/.claude/statusline-colors.db` — 129 dead `/var/folders/...` rows
  accumulated this way. Assignments are permanent by design, so it is not
  self-healing.
- `STATUSLINE_CONF` must be redirected too: the tracked conf assigns
  `STATUSLINE_COLOR_DB` unconditionally and would undo the redirect.
- `CLAUDE_CONTEXT_CONF` defaults to a nonexistent path, so tests exercise the
  **inline fallbacks** and ignore whatever `CTX_MAX` the machine carries.

Every statusline invocation goes through `env -i PATH=/usr/bin:/bin`. An
inherited interactive PATH contains `/sbin` and hides the whole class of "binary
not on the hook PATH" failure — exactly how the `md5sum` outage escaped manual
testing. `COLUMNS` is set explicitly so layout is deterministic.

The starship and claude fixtures build a scratch PATH holding only the stubs a
test asks for; the real `brew`/`starship` in `/opt/homebrew/bin` are deliberately
**off** it, so "not stubbed" means genuinely absent to `command -v` rather than
passing vacuously against the developer's binary.

### Multibyte glyphs

The block and branch glyphs are 3 bytes each and awk's `length()` counts
**bytes** in this locale. Anything measuring visible width uses
`LC_ALL=en_US.UTF-8 wc -m`. A length-based bar loop once sliced the final glyph
mid-sequence and emitted invalid UTF-8, which is what the `iconv` test guards.

`bar_codes` uses `grep -o` rather than `sed s///gp`: sed's global substitute has
to walk the multibyte bytes between matches, which trips this platform's
sed/awk. `bar_cell_codes` ends its loop with `printf '%s\n'` because `read`
discards an unterminated last line, which silently dropped the red end of the
gradient.

**No apostrophes inside the single-quoted awk programs.** One terminates the
quote and silently truncates the rest of the file — bats then reports **fewer
tests** rather than an error (66 to 45, still exiting 0).

## The statusline

**Claude Code discards the entire statusline if the command writes a single byte
to stderr**, with no error shown anywhere. Two outages were exactly this:
`md5sum` resolving only in `/sbin`, and `ps` on a PID that had gone away — both
produced good stdout and an invisible statusline.

Things a test author gets wrong here:

- `printf` reads a negative `%*s` width as a left-justify flag and silently emits
  nothing, so `WRAP_PAD` is clamped at 0.
- The gauge's denominator is the *usable* window (`CTX_MAX - CTX_RESERVE`), not
  the raw one. `context_window.used_percentage` is deliberately **not** read, and
  the fixtures seed it with a wrong value on purpose so a regression that starts
  trusting it fails rather than merely going unproven. The overshoot fixture uses
  a genuine overshoot rather than the compact point, which would pass with no
  clamp at all.
- Gradient monotonicity is asserted on **hue**, not raw channels: the ramp routes
  through yellow and orange, so green rises before it falls.
  `expect_cell_rgb` / `expect_cell_cube` restate the ramp rather than importing
  it, so changing the script's stops is a deliberate two-place edit.
- The bar's colour is a function of position, not fill, so two directories give
  an identical bar; the segment background is checked to still *differ*, or the
  comparison would pass merely because both inputs were identical.
- The task comes from `session_name`, not `.customTitle` — that is the session
  transcript's shape, and the segment rendered as nothing at all.
- Dirty means **any** uncommitted change, untracked included; a `-uno`
  "optimisation" of `status --porcelain` reports that as clean. An unpushed
  commit is *not* dirt.
- Asserting merely that no background is open at end-of-line is vacuous — the
  right-hand group's own reset closes a bled `48;5;N` at the last moment. The
  test instead walks the line collecting every painted printable character. The
  "no stray gap" test cuts at the *first* reset, because sed is greedy.

## Session colours

A directory+branch is assigned a colour once and keeps it. Permanence is the
feature, so anything that could repaint a live session mid-work is a bug.

### Palette expectations are derived, never restated

The palette lives in exactly one place — `SESSION_COLOR_PALETTE` in
`claude/lib/session-colors.sh`. Tests read the array and derive expectations from
it (assign `n + 2` keys to exercise the wrap; assign between one and two full
passes for "every colour used, none more than twice"), so changing its contents
**or its length** needs no test edit.

`statusline.sh` sources the library rather than keeping a copy; its small guarded
default is deliberately *not* a duplicate, and every code in it must clear the
contrast bar. The "defined in exactly one place" test requires the *subscripted*
read `SEG_BG=${SESSION_COLOR_PALETTE[` — a bare `SESSION_COLOR_PALETTE[` is
satisfied by the emptiness guard `${#SESSION_COLOR_PALETTE[@]}` and survived
renaming the only real use.

### Contrast is scored against the terminal theme's real foregrounds

The statusline emits SGR 33 and 32, which resolve through the **terminal theme** —
ghostty's "deep" renders them `#d9bd26` and `#1cd915`, not xterm's rgb(205,205,0)
and rgb(0,205,0). Scoring the wrong colours is how a palette with seven
illegible entries passed a contrast filter at selection time. Codes `0`–`15` are
theme-resolved too, so they are **not** on the 6×6×6 cube and must not be mapped
through it.

The bar is 3.0 (WCAG AA, large text). It sat at a vacuous 1.0 while the palette
was in flux — 1.0 is the floor for identical colours, so nothing could fail it.

### Concurrency

**`INSERT OR IGNORE`, not `OR REPLACE`.** Two sessions can both miss the
fast-path `SELECT` and both `INSERT`; `OR REPLACE` lets the loser overwrite the
winner and repaint a live session (measured: 18 becomes 144). The test stubs the
fast-path lookup to return nothing for one call — what the loser observes —
rather than restating the SQL, which would keep saying `OR IGNORE` no matter what
the library says.

**`PRAGMA busy_timeout=10000`, asserted on rows written.** Without it sqlite3
abandons a locked write *silently* (13 of 24 rows, zero stderr), so a
stderr-only assertion passes vacuously. The other half is a `database is locked`
on stderr, which discards the whole statusline.

Each writer is waited on **individually**: `wait` with no argument reaps every
child but reports nothing, so a writer that died was indistinguishable from a
lost row. This cost two flakes under load.

Ruled out by measurement, so nobody re-litigates: busy_timeout exhaustion is not
the mechanism at this scale (24 writers finish in ~0.22s against a 10s budget);
the harness does not leak state; and a FIFO barrier reliably releases only 23 of
24 readers on this platform, hanging the suite, while buying nothing measurable.
