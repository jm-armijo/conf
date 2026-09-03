# Notes on `test/setup.bats`

Rationale that would otherwise live as long comment blocks inside the suite. The
tests carry one-line pointers back to the headings here.

## Writing tests in this suite

### `bats_run`, never `run`

`setup.sh` defines its own `run()` step-wrapper. Sourcing `setup.sh` in a test
file therefore **shadows bats' built-in `run` helper**, and every later `run`
invocation fails with `Permission denied`.

`setup()` works around it by copying bats' helper onto a second name *before*
sourcing:

```bash
eval "bats_run() $(declare -f run | tail -n +2)"
source "${BATS_TEST_DIRNAME}/../setup.sh"
```

New tests must call `bats_run`. The same copy-the-body idiom is used again in
"a losing racer's assign never overwrites the winner's colour" to stub
`_sc_sql`.

Sourcing rather than executing is safe because `setup.sh`'s bottom execution
block is guarded by `[[ "${BASH_SOURCE[0]}" == "$0" ]]`, so the helpers load
without running the machine setup.

### Negations must be `bats_run` plus an explicit status check

A bare `! grep ...` in the middle of a bats test body **does not fail the
test**: bats consults only the last command's status. Negations written that way
are silently unevaluated, and this masked a real violation before it was found —
re-adding `PALETTE=(1 2 3)` to `statusline.sh` slipped straight through a
`! grep -q` form.

Every negation is therefore written as:

```bash
bats_run grep -q 'forbidden' "$file"
[ "$status" -ne 0 ]
```

or, where a helper is more convenient, as an assertion on a `grep -c` count.

### Assert on effects, not on stderr alone

Two places where a stderr-only assertion passes vacuously:

- **`starship --version` exits 0 on a broken config.** A TOML syntax error is
  logged to *stderr* and starship carries on with its built-in defaults; the
  same is true of `starship module` / `starship prompt`. Verified against
  1.26.0. A check that a config parses must assert **stderr is empty**, never on
  exit status.
- **The concurrency test asserts on ROWS WRITTEN, not stderr.** Without
  `PRAGMA busy_timeout`, sqlite3 abandons a locked write *silently* — measured
  at 13 of 24 rows surviving with zero bytes of stderr. See below.

### Isolation from the developer's machine

`statusline_run` and `colors_env` redirect `STATUSLINE_COLOR_DB`,
`STATUSLINE_CONF` and `CLAUDE_CONTEXT_CONF` into `$BATS_TEST_TMPDIR`.

All three are load-bearing:

- Without the DB redirect every rendering test writes an assignment into the
  developer's **live** `~/.claude/statusline-colors.db`, one row per bats temp
  directory. 129 rows of dead `/var/folders/...` keys accumulated this way,
  including codes from mutation runs that fail the contrast bar. Assignments are
  permanent by design, so the pollution is not self-healing.
- `STATUSLINE_CONF` must be pointed away too: the tracked conf assigns
  `STATUSLINE_COLOR_DB` unconditionally, so sourcing it would undo the redirect.
- `CLAUDE_CONTEXT_CONF` defaults to a nonexistent path, which both isolates the
  expected percentages from whatever `CTX_MAX` the machine carries and means
  every statusline test exercises the **inline fallbacks** — the state a fresh
  machine is in. A test wanting a real conf sets it before calling.

Every statusline invocation goes through `env -i PATH=/usr/bin:/bin`. An
inherited interactive PATH contains `/sbin` and hides the whole class of "binary
not on the hook PATH" failure — that is exactly how the `md5sum` outage escaped
manual testing. `COLUMNS` is set explicitly so layout is deterministic.

The starship and claude fixtures build a scratch PATH holding only the stubs a
test asks for. The real `brew`/`starship` in `/opt/homebrew/bin` are deliberately
**off** that PATH, so "not stubbed" means genuinely absent to `command -v` rather
than silently resolving to the developer's binary and passing vacuously.

### Multibyte glyphs

The block and branch glyphs are 3 bytes each, and awk's `length()` counts
**bytes** in this locale. Anything measuring visible width uses
`LC_ALL=en_US.UTF-8 wc -m`. A length-based bar loop once sliced the final glyph
mid-sequence and emitted invalid UTF-8, which is what the `iconv` test guards.

`bar_codes` uses `grep -o` rather than a `sed s///gp` for the same reason: sed's
global substitute has to walk the multibyte glyph bytes between matches, which
trips this platform's sed/awk. `bar_cell_codes` ends its loop with
`printf '%s\n'` because `read` discards an unterminated last line, which
silently dropped the red end of the gradient.

**No apostrophes inside the single-quoted awk programs.** One terminates the
quote and silently truncates the rest of the file — bats then reports **fewer
tests** rather than an error (it went from 66 to 45 and still exited 0).

## Install strategies (`link`, `setup_*`)

`link()` is the only real logic in the repo and the one thing that touches
`$HOME`, so a bug clobbers real dotfiles. Its three contracts: it creates the
symlink, it is idempotent (a re-run must not back up the symlink it just made,
or every `setup.sh` run litters `$HOME` with dated copies), and it never destroys
an existing real file.

`setup_starship` and `setup_starship_config` are two steps on purpose: the config
must land on a machine where the brew install was skipped or failed, ready for
the binary's arrival. The early `command -v starship` return means brew must not
be invoked *at all* on a re-run — not merely invoked and shrugged off.

`~/.claude` and `~/.claude/skills` are shared with Claude Code's own runtime
state, so those are linked **per file / per skill**. The ruby-lsp plugin writes
`~/.claude/skills/.ruby-lsp/`; a directory symlink would put that state inside
the repo as untracked junk, which is what the plugin-state test reproduces.
`setup_claude_skills` records failures across its loop instead of returning
early, so one bad skill still leaves the others installed — the same
record-and-continue shape as `run()` one level up.

`~/.claude/vendor` is the one directory symlink, because nothing outside this
repo has ever written there. Its test asserts existence only — the mermaid bundle
is ~750,000 tokens and must never be read.

`claude/global-instructions.md` → `~/.claude/CLAUDE.md` is the only renamed link:
Claude Code demands that filename, while a `claude/CLAUDE.md` here would be read
as this repo's own project instructions.

## The plan-writing templates

- **Mermaid must be a classic `<script src>` off the vendored bundle.**
  `PLAN.html` is opened from `file://`, where an ESM `import` fails even for a
  local file ("Failed to fetch dynamically imported module") — module fetches are
  subject to CORS and `file://` origins are opaque. A CDN URL is additionally
  unreachable offline. Verified in headless Chrome in both directions. The test
  exists because "modernising" it back breaks every diagram with **no error at
  all** — the diagram source just sits there as text.
- **Only `{{VENDOR_DIR}}` is substituted, and the filename stays literal.** A
  template with `/Users/<someone>` baked in works on exactly one machine. A
  whole-file placeholder would invite the generating model to stat or open the
  bundle; a directory placeholder is resolved and dropped. The `AGENT / LLM: do
  NOT read` comment must close on the line *directly above* the `<script>` tag —
  adjacency is the property that matters and the one that rots silently.
- **`SKILL.md` must not restate the template's section list.** The template is
  the single definition of a plan's shape, so plans are retuned by editing one
  file. A second copy would silently disagree.
- **`plan-writing` is instructions consulted *while* planning, not a post-hoc
  renderer.** The old wording ("this skill is about what the plan is written
  to") made it a formatter and must not come back.

## `development` and `TODO.md`

`development` was `plan-execution`, and the rename is the substance: a skill
described as "execute an approved plan" never triggers, because nobody labels the
phase — after approval you just start working. It is described by the *activity*,
and its steps apply to every piece of work, plan or not. The description is the
whole trigger surface, so a description advertising only plan execution must
fail.

`draft pr` swallowed the old separate commit step, and that merge is exactly how
the `--no-verify` prohibition gets dropped — so it is pinned to the skill. The
contract prose must **not** be copied back into `TODO_TEMPLATE.md`: a to-do list
is exactly a to-do list. Five steps are a baseline, not a ceiling.

**Status is derived from the checkboxes, never declared.** A declared status can
disagree with the boxes; a derived one cannot. So no Progress table, no status
column, no front-matter. The rigid shape is a *parseability* requirement — a
script must answer "which task, which step" with a grep — so every task heading
and step line is identical in form, and the tests assert the whole ordered
sequence rather than that the words appear somewhere.

## `plan-artifacts-on-exit`

A `PreToolUse` gate on `ExitPlanMode`. Its one real hazard is looping: it blocks,
the model runs the skill and exits again, and if the second call blocked too the
session would never leave plan mode. So the **"allow once both artifacts exist"**
branch is the test that matters, not the block. Exit 2 is the documented "block
and feed stderr back to the model" code; anything else silently lets the plan
through unrendered. A non-git `cwd` is allowed through — a scratch directory has
no branch or PR worth the name. Malformed input fails open, or an unexpected
payload would wedge plan mode entirely.

The message's *content* is pinned, not just the block:

- It names the **browser review**, because the point is that the plan is
  reviewable *before* approval. A message that merely demands two files gets
  obeyed as paperwork on the way out of plan mode, which renders the plan at the
  moment it stops being worth reading.
- It says the chat output is **ONE LINE**, no summary. Having written
  `PLAN.html`, the reflex is to also paste the plan into the terminal — the exact
  duplication these files exist to remove.
- It sends the model back to the **template as an input**. The earlier wording
  ("formats and splits", "does not replace your thinking") hard-coded the
  post-hoc-renderer framing into the wiring.

## The statusline

**The contract: Claude Code discards the entire statusline if the command writes
a single byte to stderr**, with no error shown anywhere. Two separate outages were
exactly this — `md5sum` resolving only in `/sbin` (absent from the hook PATH),
and `ps` on a PID that had gone away. Both produced a perfectly good stdout and
an invisible statusline.

### Layout

At 160 columns, less the default `BAR_MARGIN` of 12, the bar is 148 and both
lines must terminate on exactly that column — that alignment is the whole point
of the `PAD` computation. A long title in a narrow terminal drives `PAD` negative
(the overflow signal) and `LEFT`/`RIGHT` get a line each; the wrapped right group
is padded on the **left** so it stays flush to the same edge. `printf` reads a
negative `%*s` width as a left-justify flag and silently emits nothing, so
`WRAP_PAD` is clamped at 0.

### The context gauge

Claude Code auto-compacts when **input** tokens reach `CTX_MAX - CTX_RESERVE`,
and the reserve is an **absolute** output budget (~33000), not a fraction of the
window. So the gauge's denominator is the *usable* window: 100% is 167000 on a
200000 window, and 83500 reads 50. A bar dividing by the raw 200000 read ~84% at
the instant compaction fired, showing ~14 cells of headroom that did not exist.

- The payload's `context_window` object is the **primary** source — it is what
  Claude Code itself measures. Its `used_percentage` field is deliberately *not*
  read (it divides by the raw window), and the fixtures seed it with a wrong
  value on purpose so a regression that starts trusting it is caught rather than
  merely unproven.
- The transcript sum is the **fallback**, for older CLIs and for the null window
  at the start of a session — including the case where `context_window` is
  present but its *members* are null.
- `context_window_size` is clamped **down** to `CTX_MAX` (`autoCompactWindow` can
  cap the effective window below the model's native one) but a genuinely
  *smaller* reported window is scaled against itself — the clamp is a minimum of
  the two, not an override.
- The reading clamps at 100. Compaction is not instantaneous and one large turn
  can overshoot, so tokens above the usable window are a real state; the fixtures
  use a genuine overshoot (200000 against a 167000 point, which computes to 120
  unclamped) rather than the compact point itself, which would pass with no clamp
  at all.
- A reserve at or above the window must read 0. awk would otherwise print `inf`
  or `nan` into the `ctx:` segment, and a non-numeric percentage then fails the
  colour comparison with a stderr byte — which discards the whole statusline.

### The gradient

Colour is a function of **position**, not of fill, so a cell keeps its colour as
the bar grows past it and two different directories produce an identical bar at
the same width. That is what proves the bar is not hashed on cwd+branch; the
segment background is checked to still *differ*, or the comparison would pass
merely because both inputs were identical.

Monotonicity is asserted on **hue**, not on raw channels: the ramp deliberately
routes through yellow and orange, so green rises before it falls and a
per-channel assertion would reject the very shape that keeps the midpoint from
going muddy.

The waypoints exist for two reasons, both regressions of the old cube ramp:

- A straight green→red lerp sat at pure green until ~30% and only reached yellow
  near 50%, reading as "fine" far too long. The bar must be yellow (hue 45–70) by
  35% of its width.
- The old ramp gave **six** distinct colours across the whole bar, one hard jump
  every ~17%. A 100-cell bar must now show ≥60 distinct colours with no
  neighbouring step above 8/255, which is roughly where a step becomes visible on
  a solid field.

`expect_cell_rgb` / `expect_cell_cube` restate the ramp rather than importing it,
so a change to the script's stops has to be made deliberately in two places.

### Segments

The task was previously read from `.customTitle`, which is the *session
transcript's* shape rather than the statusline payload's — the real key is
`session_name`, so the segment rendered as nothing at all.

Branch colour follows agnoster's rule: dirty is **any** uncommitted change —
unstaged, staged, or untracked. An untracked file alone is the case a `-uno`
"optimisation" of `status --porcelain` would silently report as clean. An
unpushed commit is *not* dirt, and that case is asserted so the test cannot pass
for a check that merely compared against a remote.

An unreset `48;5;N` bleeds the block colour through the pad and the whole
right-hand group. Asserting merely that no background is open at end-of-line is
vacuous — the right-hand group ends with its own reset, closing the bled
background at the last possible moment. So the test walks the line tracking
whether a background is active and collects every painted printable character;
that set must be exactly the block's own text. Similarly, the "no stray gap" test
cuts at the *first* reset, because sed is greedy and would otherwise run to the
last one and swallow the whole right-hand group.

## Session colours

The dir/branch/task background is **recorded, not derived**: a directory+branch
is assigned a colour once and keeps it. Permanence is the feature, so anything
that could repaint a live session mid-work is a bug.

### Palette expectations are derived, never restated

The palette lives in exactly one place — `SESSION_COLOR_PALETTE` in
`claude/lib/session-colors.sh`. The tests read the array and derive their
expectations from it (assign `n + 2` keys to exercise the wrap whatever the size;
assign between one and two full passes to get "every colour used, none more than
twice"). Changing the palette's **contents or its length** therefore needs no
test edit.

`statusline.sh` sources the library rather than keeping its own copy — the two
lists could otherwise drift into handing out colours the contrast audit never
covered. It keeps a small guarded default for the case where the library cannot
be read at all, which is deliberately *not* a copy (a stale duplicate that
silently disagreed would be worse than an obviously reduced one); every code in
it must still clear the contrast bar. The "defined in exactly one place" test
requires the *subscripted* read `SEG_BG=${SESSION_COLOR_PALETTE[`, because a bare
`SESSION_COLOR_PALETTE[` is satisfied by the emptiness guard
`${#SESSION_COLOR_PALETTE[@]}` and survived renaming the only real use.

### Contrast is scored against the terminal theme's real foregrounds

The foregrounds are fixed yellow and green, so legibility has to come from the
palette. **Earlier revisions scored against the xterm defaults** rgb(205,205,0)
and rgb(0,205,0). The statusline emits SGR 33 and 32, which resolve through the
**terminal theme** — ghostty's "deep" renders them `#d9bd26` and `#1cd915`.
Scoring the wrong colours produced a wrong ranking, which is how a palette with
seven illegible entries passed a contrast filter at selection time.

This makes the test theme-specific, which is the honest trade. Codes `0`–`15` are
system colours resolved through the theme too, so they are **not** on the 6×6×6
cube and must not be mapped through it.

The bar is 3.0 (WCAG AA for large text, right for a single row of glyphs). It sat
at a vacuous 1.0 while the palette was in flux — 1.0 is the floor for identical
colours, so nothing could fail it. The current floor is 3.68 (code 124).

### Ordering is load-bearing

Assignment walks the palette in order, so neighbours go to sessions opened close
together and must be the *least* alike pairs. The current ordering holds a
minimum of ΔE 82.6 between neighbours; sorting the same codes numerically
collapses that, putting the 21/24 blue-ramp pair adjacent. The list is cyclic, so
the last→first pair is checked too. Distance is CIE76 (sRGB → CIE Lab D65, plain
Euclidean) — enough to answer "are these obviously different colours".

### Concurrency

**`INSERT OR IGNORE`, not `OR REPLACE`.** Two sessions can both miss the
fast-path `SELECT` and both go on to `INSERT`; the second to commit must be
discarded. `OR REPLACE` applies it — and because the winner's row makes its own
code the most-used, the loser recomputes a *different* code and repaints a live
session mid-work (measured: 18 becomes 144). The test reproduces this by stubbing
the fast-path lookup to return nothing for one call, which is exactly what the
loser observes. Driving the library rather than restating its SQL is deliberate:
a hand-written `INSERT` in the test would keep saying `OR IGNORE` no matter what
the library says.

**`PRAGMA busy_timeout`, asserted on rows.** Without it sqlite3 abandons a locked
write, and does so *silently* — measured at 13 of 24 rows surviving with zero
bytes of stderr. A stderr-only assertion passes vacuously. (Silent loss is the
milder half; the same abandoned write can instead print `database is locked`, and
Claude Code discards the whole statusline on a single stderr byte.)

Each writer is waited on **individually**. This test failed twice under load on a
busy machine and passed everywhere else: `wait` with no argument reaps every
child but reports nothing about any of them, so a writer that died — killed,
fork-failed, or exiting non-zero — was indistinguishable from a lost row. Waiting
per-PID separates "the library lost a write" from "the harness never ran 24
writers".

Ruled out by measurement, so nobody re-litigates:

- **busy_timeout exhaustion is not the mechanism at this scale.** The 24 writers
  complete in ~0.22s against the library's 10s budget — a 45× margin — unchanged
  with 24 CPU-bound spinners on 8 cores. Forcing the timeout to genuinely expire
  takes a >10s exclusive lock hold; that loses all 24 rows with zero stderr, and
  is a machine stall rather than contention. The 10s ceiling is what keeps this
  green, not what breaks it.
- **The harness does not leak state.** `STATUSLINE_COLOR_DB` is per-test under
  `BATS_TEST_TMPDIR`, and a bare `wait` was verified never to return before all
  24 rows were durable (counts taken immediately after `wait` and again 1s later
  agreed across 40 runs under load).
- **A FIFO barrier was tried and rejected.** A single `: >gate` reliably releases
  only 23 of 24 readers on this platform, leaving one blocked forever and hanging
  the suite. It also bought nothing measurable — staggered and barrier
  start-spreads were indistinguishable, both dominated by process startup. Do not
  reintroduce one without measuring both.

### Retention and degradation

Cleanup is confined to the assign path: the read path runs on every refresh of
every session and must stay a single `SELECT`. A non-numeric retention setting
must not reach the `DELETE` as a malformed interval. With sqlite3 unavailable the
library degrades to "no colour" and stays silent — the caller falls back to
hashing on an empty answer, so a non-zero return is expected and fine.

The key separator stops directory and branch running together: `/a/b` + `c` and
`/a/bc` + `""` concatenate to the same string. (The pair has to be chosen with
care — `/a/b` + `c` versus `/a` + `bc` does *not* collide, because the slash keeps
them distinct.)

## Tracked-file checks

`setup.sh` and `zshrc` refer to these by path, so a rename, a deletion or a TOML
typo would otherwise only surface as a promptless shell on a machine that pulled.

- `settings.json` names the statusline and hooks by their `~/.claude/...` paths.
  Renaming a script without editing it leaves Claude Code silently invoking
  nothing.
- The skill list in `setup_claude_skills` is hardcoded; a skill renamed in
  `claude/skills` without updating it would only surface as a failing step on the
  next machine setup.
- `zshrc`: `eval "$(starship init zsh)"` must sit **below** `source
  $ZSH/oh-my-zsh.sh`, which assigns `$PROMPT` — an init above it is silently
  overwritten. The `command -v starship` guard stops a machine without the binary
  printing an error on every shell start. `ZSH_THEME` must be empty or a
  non-empty theme races starship for `$PROMPT`. `agnoster` stays as the
  documented fallback.
