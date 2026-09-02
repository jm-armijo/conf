# conf

Personal configuration for **zsh** (with the **Starship** prompt), **git**, **ghostty**, **Claude Code**, and the **Magnet** and **OBS** macOS apps.

## Setup a new machine

Clone the repo anywhere you like, then run the setup script:

```bash
git clone <this-repo-url> ~/code/conf
cd ~/code/conf
./setup.sh
```

The script:

- Symlinks `zsh/zshrc` → `~/.zshrc` and `zsh/agnoster.zsh-theme` → `~/.oh-my-zsh/themes/agnoster.zsh-theme`.
- Installs the **Starship** prompt with `brew install starship` (skipped, with a message, if it's already there or if Homebrew isn't). Starship is a compiled binary, not a zsh script, so it comes from a package manager rather than being vendored here.
- Symlinks `starship/starship.toml` → `~/.config/starship.toml` — the prompt's own config, which *is* tracked in this repo. This step runs independently of the install above, so the config still lands on a machine where Homebrew is missing.
- Symlinks `git/gitconfig` → `~/.gitconfig`.
- Symlinks `ghostty/config` → `~/.config/ghostty/config`.
- Symlinks the **Claude Code** global config into `~/.claude` — the global instructions, `settings.json`, the statusline script and its config and colour library, and the bash hook — plus one symlink per tracked skill directory. See [Claude Code](#claude-code) for what is and isn't managed.

The clone location isn't baked in anywhere — `zsh/zshrc` finds its sibling files by
resolving its own `~/.zshrc` symlink — so any directory works.

Because these are symlinks, any later edit to your live config is saved straight back into the repo — including `git config --global` writes, which follow the symlink into `git/gitconfig`.

Existing files are backed up (renamed with a `.backup.<timestamp>` suffix) before being replaced. The script is idempotent — safe to re-run.

After running, restart your shell (`exec zsh`).

### Prerequisites

The zsh config expects oh-my-zsh and the `zsh-syntax-highlighting` plugin:

```bash
# oh-my-zsh — see https://ohmyz.sh/#install
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# zsh-syntax-highlighting plugin
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

The Starship prompt needs a **Nerd Font** — a stricter requirement than agnoster's
Powerline-patched font. The rounded segment caps (``, ``) and the branch/AWS icons in
`starship/starship.toml` are glyphs that only exist in the Nerd Font range; a Powerline
font alone renders them as boxes or blanks:

```bash
brew install --cask font-meslo-lg-nerd-font
```

The terminal font is part of this repo (`ghostty/config`), so set it there — the symlink
makes it live — rather than in a GUI:

```
font-family = MesloLGS Nerd Font
```

If you'd rather not install a Nerd Font, edit `starship/starship.toml`: replace the ``/``
caps with the plain-ASCII Powerline arrow `` (or nothing), and clear the `symbol` values on
`[git_branch]` and `[aws]`. The colours and the section order work without any of them.

The agnoster fallback theme needs only a Powerline-patched font:

```bash
git clone https://github.com/powerline/fonts.git --depth=1
cd fonts && ./install.sh && cd .. && rm -rf fonts
```

In iTerm2: Settings → Profiles → Text → enable *Use built-in Powerline glyphs*.

## Prompt

`starship/starship.toml` is agnoster's look rebuilt on Starship: agnoster's section
order (`status → virtualenv → aws → context → dir → git`) and its colours, drawn as
rounded segments rather than agnoster's square ones.

The colours are the **basic-8 terminal names** (`blue`, `green`, `yellow`, `black`,
`red`, `cyan`), not hex, deliberately — they resolve against the terminal's own palette,
so the `theme` line in `ghostty/config` still recolours the prompt exactly as it did
under agnoster.

The one bit of logic worth knowing: agnoster coloured the git segment green when the
working tree was clean and yellow when it was dirty. Starship has no such switch, so
that's two modules — `[git_branch]` is the always-present green pill with the branch
name, and `[git_status]` is a yellow pill that appears beside it only when the tree is
dirty.

## Claude Code

`~/.claude` mixes two very different things: a handful of files you write, and a
lot of state Claude Code writes for itself — session transcripts, caches, plugin
installs, shell snapshots, `history.jsonl`. Only the first group is tracked here,
one symlink per file, so the rest stays machine-local and out of git:

| Tracked | Linked to |
| --- | --- |
| `claude/global-instructions.md` | `~/.claude/CLAUDE.md` — global instructions applied to every project |
| `claude/settings.json` | `~/.claude/settings.json` — model, env flags, hooks, statusline, enabled plugins, UI prefs |
| `claude/statusline.conf` | `~/.claude/statusline.conf` — tunables for the session-colour assignments |
| `claude/context-window.conf` | `~/.claude/context-window.conf` — the context window and its auto-compact reserve |
| `claude/scripts/statusline.sh` | `~/.claude/scripts/statusline.sh` |
| `claude/lib/session-colors.sh` | `~/.claude/lib/session-colors.sh` — the colour database, also sourceable from your shell |
| `claude/hooks/block-inefficient-bash.sh` | `~/.claude/hooks/block-inefficient-bash.sh` |
| `claude/skills/<skill>/` | `~/.claude/skills/<skill>/` — one link per skill |

**One file is renamed across the link.** Claude Code requires the name
`CLAUDE.md`, but a file by that name in *this* repo would be read as this repo's
own project instructions — which is a different file with a different job. So the
tracked copy is `claude/global-instructions.md` and `link()` puts it at
`~/.claude/CLAUDE.md`. A test pins the rename.

`settings.json` refers to the hook and the statusline by their `~/.claude/...`
paths, so those two links are what make it work — renaming a script here without
editing `settings.json` leaves Claude Code silently invoking nothing. A test
pins that pairing.

**One file is deliberately neither tracked nor linked:**
`~/.claude/statusline-colors.db`, the session colour assignments. It is runtime
state the statusline creates on first use, and it is machine-local by design — a
colour belongs to *this* laptop's set of checkouts, not to any project. Delete it
to reset every assignment. See [Session colours](#session-colours-are-recorded-not-hashed).

### The statusline's one hard rule

**Claude Code discards the entire statusline if the command writes a single byte
to stderr** — no error, no partial render, the line just vanishes. Two separate
outages traced to exactly this, and neither was visible from a normal shell:

- `md5sum` resolves only in `/sbin`, which is **not** on the PATH Claude Code
  gives the hook, so it printed `command not found` to stderr. Every manual test
  passed because an interactive PATH includes `/sbin`.
- `ps -p "$PPID"` writes to stderr once that PID has gone away.

`statusline.sh` therefore redirects fd 2 to `/dev/null` for the whole script as a
structural backstop, so a command added later cannot silently kill the line. To
diagnose it, unmute stderr:

```bash
echo '{}' | STATUSLINE_DEBUG=1 ~/.claude/scripts/statusline.sh
```

Reproduce the real hook environment with `env -i` — an inherited PATH hides this
whole class of failure:

```bash
echo '{}' | env -i PATH=/usr/bin:/bin HOME="$HOME" ~/.claude/scripts/statusline.sh
```

Three tests pin the contract: stderr stays empty across valid, empty and
malformed payloads; exit is zero with non-empty output; and the output is valid
UTF-8 (the bar glyph is 3 bytes, and a byte-based width calculation once sliced
it mid-sequence).

### What the statusline renders

A context-usage bar on top, then a metrics line:

```
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
~/code/conf |  master | task     Opus | ctx:12% | 24.1k tok | 14:22:01 | cpu:3% mem:412M
```

- **Full means the auto-compact point, not the raw window.** Claude Code compacts
  once the input token count reaches `CTX_MAX - CTX_RESERVE` — 167,000 on a
  200,000 window — because the reserve it holds back for output is an *absolute*
  token budget, not a fraction of the window. So the gauge is scaled against that
  threshold and reads 100% exactly when compaction fires. Scaling against the raw
  200,000 read only ~84% at that moment, showing about a seventh of the bar as
  headroom that did not exist. Past the threshold it clamps at 100% rather than
  overshooting, since one large turn can cross the line before compaction runs.

  The token count and window size come from the payload's `context_window` object
  when the CLI provides one, falling back to summing the session transcript on
  older versions and at the very start of a session. Both numbers live in
  `claude/context-window.conf`, symlinked to `~/.claude/context-window.conf` and
  live the moment you save it:

  ```bash
  CTX_MAX=200000      # raise to 1000000 for an extended-context model
  CTX_RESERVE=33000   # empirical; NOT documented by Anthropic
  ```

  These are facts about *Claude Code's* behaviour rather than statusline
  settings, which is why they are a separate file from `statusline.conf` — any
  other script needing to reason about the compaction threshold should read them
  from here. `CTX_RESERVE` was measured across 93 `compact_boundary` records
  (`200000 - preTokens` fell in a 32,852–33,273 band) and is confirmed absolute by
  the 1M-window case compacting at ~967K. Both settings have inline defaults in
  the script, so an absent, unreadable or half-written config falls back rather
  than breaking the statusline; a non-numeric value falls back too, and a reserve
  at or above the window reads 0% instead of dividing by zero.
- **The bar is a context gauge with a positional gradient.** The filled run is
  the percentage of the usable context window in use. Its colour is a function of each
  cell's **position along the bar**, not of the percentage: cell `i` of `n` is
  coloured at fraction `i/(n-1)`, so the leftmost cell is always green and the
  rightmost cell of a full bar is always red, whatever the fill. Growing context
  therefore extends the bar rightward and *reveals* progressively warmer colours,
  instead of recolouring the whole bar at once. The remainder stays visible as a
  dim grey track so the scale is always on screen. The colour is a pure function
  of (position, width), so two sessions at the same width produce a byte-identical
  bar — it is deliberately **not** hashed, and it is the one part of the line that
  has nothing to do with the per-session colour below. Red at the right-hand end
  is the point here.
- **The ramp is piecewise-linear through waypoints, not a straight green→red
  lerp.** Two reasons, and both are the shape's job. A single lerp passes through
  desaturated olive at the midpoint, because the endpoints' channels cross over
  and cancel; routing through real yellow and orange holds saturation ≥ 0.75 the
  whole way. And *where* the warning lands matters more than linearity — the stops
  put yellow at **35%** and red-orange at **85%**, so the bar stops reading as
  "fine" about a third of the way across. The linear version sat at pure green
  until ~30% and only reached yellow near 50%, which read as safe far too long.
  Hue falls monotonically 139° → 0° across the bar. The stops are:

  | fraction | rgb | |
  | --- | --- | --- |
  | 0.00 | `60,200,70` | green |
  | 0.20 | `150,205,40` | yellow-green |
  | 0.35 | `225,210,30` | yellow |
  | 0.55 | `245,175,25` | amber |
  | 0.70 | `250,130,20` | orange |
  | 0.85 | `240,75,30` | red-orange |
  | 1.00 | `215,35,35` | red |

- **Two output paths, chosen by `COLORTERM`.** With `truecolor` or `24bit` the bar
  emits `38;2;r;g;b` and every cell gets its own exact colour — the largest
  per-cell channel step on a 100-cell bar is **6/255**, below the visible-banding
  floor. That is the path that actually delivers smoothness, and it is what
  ghostty gets. Everything else falls back to the ANSI-256 cube, which *cannot*:
  6 levels per channel means a computed green→red diagonal yields **six** distinct
  codes across the whole bar, one hard jump every ~17%. Worse, nearest-cube
  matching is not even monotonic in hue there (`166` sits at 27°, between `202` at
  22° and `160` at 0°), so the ramp visibly backtracks. The fallback therefore
  walks a hand-checked ladder of 11 fully-saturated codes whose hue is strictly
  monotonic 120° → 0°. It is coarser by construction — that is the cube's limit,
  not a defect in the code.
- The glyph is `▔` U+2594 UPPER ONE EIGHTH BLOCK, drawn as **foreground**. A cell
  cannot be split vertically, so a background-painted run of spaces is always a
  full row tall; inking the glyph instead gives a one-eighth-height rule.
  Consecutive cells resolving to the same cube code share one escape sequence, so
  a 100-cell bar emits a handful of SGR sequences rather than a hundred. Anything
  measuring the bar's width must strip SGR and count **characters** — never bytes,
  and never the raw string length.
- **`dir | branch | task` share one background colour**, looked up from a small
  database keyed on cwd+branch, so each checkout is visually distinct and a given
  checkout is always the same colour — see
  [Session colours](#session-colours-are-recorded-not-hashed). All three share the
  one colour so they read as a single block; only the *foreground* changes between
  them, with a bare `38;5;`/`3x` and never a reset, which would drop the
  background too and punch a gap at every separator.
- **Foregrounds are fixed, not computed.** Directory and task are **yellow**.
  The branch is **green when the working tree is clean and yellow when it is
  dirty**, where dirty is agnoster's rule — any uncommitted change at all:
  unstaged edits, staged edits, *or* untracked files. Unpushed commits do not
  count. That is exactly `git status --porcelain` being non-empty; do not
  "optimise" it to `-uno`, which would stop counting untracked files. It runs once
  per refresh (~12 ms on this repo, against a ~65 ms whole-script budget) and is
  skipped entirely outside a repo.
- **The palette is filtered by contrast, and the filter is its contract.**
  Because the foregrounds above are fixed rather than computed per background, the
  background has to be legible under **both** yellow and green. Every candidate was
  mapped to RGB via the 6×6×6 cube and scored with the WCAG relative-luminance
  contrast ratio; a code survives only if the **worse** of the two ratios is
  ≥ 3.0 (WCAG AA for large text — the right bar for a single row of terminal
  glyphs).

  **Score against the foregrounds the terminal actually renders.** `SGR 33` and
  `SGR 32` resolve through the *terminal theme*, not through xterm's defaults:
  under ghostty's `deep` they are `#d9bd26` and `#1cd915`, not `rgb(205,205,0)`
  and `rgb(0,205,0)`. An earlier version of this palette was scored against the
  xterm values and shipped **7 of its 16 codes below the bar** — `144` at 1.18,
  `208` at 1.26, `255` at 1.61, `201` at 1.64, `228` at 1.77, `130` at 2.46,
  `95` at 2.87. The swatch page they were picked from looked fine; the terminal
  did not. A test pins the real constants.

  Both real foregrounds are bright — relative luminance 0.513 and 0.499 — so a
  3.0 ratio caps a qualifying background at 0.133 luminance, and **only 42 of the
  256 codes** clear it. That is why the list is short, dark, and contains **no
  orange at all**: every orange in the cube is too light against these two.

  **Twelve, not sixteen.** The qualifying pool is small and clustered — `21`–`26`
  is a straight blue ramp — so the best possible 16 could only reach a minimum
  pairwise ΔE of 24.36, by including codes barely separable from ones already
  present. Cutting to 12 raised the contrast floor from 3.04 to **3.52** and the
  pairwise minimum to **24.36**. Running out of colours is not a failure mode:
  duplicates are correct behaviour, and the assignment rule spreads them evenly.

  **There is no ban on reds.** An earlier version excluded them so the block would
  not read as an error state; that is superseded, because the block is always a
  solid painted field behind text rather than a lone glyph, and distinctness earns
  more than the resemblance costs. `52`, `124` and `125` are in the list on
  purpose.

  **The array's order is load-bearing.** Assignment walks the list in order, so
  entries sitting next to each other are handed to sessions likely to be open at
  the same time. The order is chosen to maximise the CIELab distance between
  *adjacent* entries: minimum ΔE **91.3**, mean 109.8, versus 53.2 if the same 12
  codes were simply sorted ascending (which would put `124` beside `125`). It is
  **cyclic** — the 13th assignment wraps to the first entry, so the `53 → 58` pair
  counts too (ΔE 96.9). Regenerate the array rather than hand-editing it; adding a
  code without re-running the ordering breaks the guarantee silently. Tests pin
  the ordering's minimum ΔE and record the per-code contrast ratios.
- **The metrics wrap when they do not fit.** Normally the left and right groups
  share one line, padded so the line ends on the bar's exact column. When they
  would overflow, the right group moves to its own line, right-aligned to the
  same edge. The script is stateless and re-run per refresh, so there is no
  hysteresis: it flips between 2 and 3 lines at the boundary column while the
  terminal is resized. That is expected.

**The session title comes from `session_name`, not `customTitle`.** `customTitle`
is the shape used in the session *transcript* (a record of type `custom-title`);
the statusline payload carries the same value under `session_name`, resolving the
user-set title first and the AI-generated one as a fallback. Reading
`.customTitle` from the payload always yielded empty, so the task segment
rendered as nothing at all.

`statusLine.refreshInterval` in `settings.json` is in **seconds**, not
milliseconds (Claude Code multiplies it by 1000 internally, minimum 1), so
`"refreshInterval": 1` is a one-second refresh.

Sixteen further tests pin this rendering: the fit and overflow layouts, the
right-alignment of the wrapped group, the pad clamp (`printf` reads a negative
`%*s` width as a left-justify flag and silently emits nothing), the fill
proportion, the gradient's green and red endpoints, its monotonicity, its
independence from the fill percentage, its exact per-cell formula, the bar being
byte-identical across directories, the yellow directory and the task segment
being present at all, the branch's green/yellow across a clean tree and all three
kinds of dirt, the palette's contrast ratios, the palette's adjacent-ΔE
ordering, the background closing before the metrics, and absent segments leaving
no coloured gap. A further fifteen cover the colour database itself — see
[Session colours](#session-colours-are-recorded-not-hashed).

**Changes to this script need a Claude Code restart.** `settings.json` is read
once at startup, so an edited statusline does not take effect in a running
session — which has already produced one phantom "it's broken" report.

### Session colours are recorded, not hashed

The `dir | branch | task` block is painted so you can tell one session from
another **without reading the text**. That only works if the colour is stable and
if two sessions on screen together look different — and hashing cwd+branch into
the palette gave neither. Two live sessions could hash to the same code with
nothing to detect it, and nothing could ever be done about it if they did.

So the colour is not derived any more, it is **recorded**. A directory+branch is
assigned a colour once and keeps it permanently, in a SQLite database at
`~/.claude/statusline-colors.db`. Close the session, come back next month, check
the branch out again — same colour.

- **The key is directory + branch.** Switching branch changes the colour, which
  is the intended behaviour: it is a different piece of work. Switching *back*
  returns the original colour.
- **Colours are not exclusive.** Past 16 keys they are reused. A new key takes the
  **least-used** code, and among codes tied at the lowest count, the one earliest
  in the palette. With every count at zero that walks the ordered list from the
  top; after 16 assignments the counts are level again and it starts over. So all
  16 are handed out before any repeats, and repeats stay evenly spread.
- **An existing row is never reassigned.** Whatever else happens, a live session's
  colour cannot change underneath it — that is the entire point of the feature,
  and it is why the insert is `INSERT OR IGNORE`. Two sessions racing to claim the
  same new key produce one row, and the loser reads the winner's value rather than
  overwriting it with a freshly computed one.
- **Old assignments are forgotten**, by default after 30 days from when the colour
  was *first assigned* — there is no "last used" tracking, so a session left open
  longer than the retention period loses its row and picks up a new colour on the
  next render. Cleanup runs only when a new colour is being assigned, never on the
  far more frequent read path.

Both of those numbers live in `claude/statusline.conf`, which is symlinked to
`~/.claude/statusline.conf` and so is live the moment you save it — no reinstall,
no restart:

```bash
STATUSLINE_COLOR_RETENTION_DAYS=30   # 0 disables cleanup entirely
STATUSLINE_COLOR_DB="$HOME/.claude/statusline-colors.db"
```

The file is sourced defensively and every setting has an inline default in the
library, so an absent, unreadable or half-written config falls back rather than
breaking the statusline. A non-numeric retention value falls back to 30 rather
than being interpolated into a malformed `DELETE`.

The logic lives in `claude/lib/session-colors.sh` rather than inside the
statusline, so it can be tested on its own **and** used from your own shell:

```bash
. ~/.claude/lib/session-colors.sh
session_color ~/code/conf master      # prints the assigned code, or nothing
```

`session_color` is **read-only** — it never assigns, so merely opening a terminal
cannot claim a colour. `session_color_assign` is the one that creates an
assignment, and only the statusline calls it.

Inspect or reset the database directly:

```bash
sqlite3 ~/.claude/statusline-colors.db 'SELECT * FROM colors;'
rm ~/.claude/statusline-colors.db*     # reset every assignment
```

Every failure degrades to the old behaviour rather than to a broken line: if
`sqlite3` is missing, the directory is unwritable, or the database is corrupt,
the statusline falls back to hashing cwd+branch into the same palette.

**`PRAGMA busy_timeout=10000` is not optional.** SQLite allows one writer at a
time and by default abandons a locked write *instantly*. That fails in two ways,
and the quiet one is worse: measured across 24 parallel writers, dropping the
pragma silently lost 11 of 24 rows with **zero** bytes of stderr — and it can
instead print `database is locked`, which under the rule above discards the whole
statusline. With the pragma, 24 of 24 rows and no stderr. Writes hold the lock
for microseconds, so the ceiling is never approached in practice — it is a
backstop against the machine stalling mid-transaction, not a contention budget. The
regression test asserts on **rows written**, not on stderr, precisely because a
stderr-only assertion passes vacuously here. (`journal_mode=WAL` is set
alongside it, but that one is a property of the file rather than the connection,
so it only has to be set once.)

Both pragmas print a result row, which would be captured by the caller's `$(...)`
and read as a colour code — an early version painted every session in colour
"2000". They cannot be silenced inline, so the library emits a marker row after
them and `sed` drops everything up to it.

### Why skills are linked one-by-one

Claude Code's **plugins write into `~/.claude/skills` too** — the ruby-lsp plugin
keeps a `Gemfile` and lockfile in `skills/.ruby-lsp/`. Symlinking the whole
`skills` directory would therefore point that plugin state straight at the repo,
where it would show up as untracked noise on every machine. Linking each skill
directory individually keeps the boundary exact: tracked skills are repo-backed,
and anything else — plugin state, or a skill written on one machine and not yet
committed — stays a real directory beside them.

The trade-off is that adding a skill to the repo means adding its name to the
list in `setup_claude_skills`. That is deliberate: it is the same explicit
opt-in every other app in `setup.sh` gets.

`claude/skills/plan-artifacts` carries its own `templates/` directory
(`UI_TEMPLATE.html`, `TODO_TEMPLATE.md`) rather than reading them from
`~/.config/claude-templates`, so the skill works on a fresh machine with nothing
else installed. That path is still honoured when it exists — it is the
machine-local override.

### Adding a skill

```bash
mv ~/.claude/skills/<name> claude/skills/<name>   # move the real dir into the repo
# add <name> to the loop in setup_claude_skills, then:
./setup.sh                                        # links it back
```

### One caveat on `settings.json`

Claude Code rewrites `settings.json` itself when you change a setting from
inside a session (`/config`, the theme picker). Whether that write **preserves
the symlink depends on how it writes**: an in-place write follows the link into
the repo, but a temp-then-rename replaces the link with a regular file — the
same behaviour that rules out file symlinks for OBS. This has **not** been
verified against a real in-app settings change; the CLI's `config` subcommand
was removed, so there is no non-interactive way to trigger the write path.

It is harmless either way, and easy to spot:

```bash
ls -l ~/.claude/settings.json      # should say "-> .../conf/claude/settings.json"
```

If it has become a regular file, your in-app change is sitting there rather than
in the repo. Copy it back and re-link:

```bash
cp ~/.claude/settings.json claude/settings.json
./setup.sh
```

Claude Code also writes a timestamped `settings.json.<date>.bak` next to the
file before rewriting it, so the previous version is recoverable regardless.

## Magnet

Magnet is a sandboxed Mac App Store app. Its settings live in a preferences
plist managed by macOS (`cfprefsd`), which rewrites the file atomically at
unpredictable times — so a symlink would get clobbered and is not safe here.
Instead `magnet/com.crowdcafe.windowmagnet.plist` is a manual backup (stored
as XML so changes are reviewable in git).

Back up current settings into the repo:

```bash
defaults export com.crowdcafe.windowmagnet - \
  > magnet/com.crowdcafe.windowmagnet.plist
```

Restore the saved settings onto a machine (quit Magnet first):

```bash
defaults import com.crowdcafe.windowmagnet \
  magnet/com.crowdcafe.windowmagnet.plist
```

## OBS

OBS config depends on the monitor, so it's stored per resolution under
`obs/<resolution>/` (e.g. `obs/7680x2160/`). `setup.sh` lists the available
configurations and asks which one to install.

OBS rewrites individual files via temp-then-rename, which would clobber a
*file* symlink — but a *directory* symlink survives (the renames happen on
files inside it, never the directory itself). So `setup.sh` symlinks the whole
`~/Library/Application Support/obs-studio` directory to the chosen
`obs/<resolution>/`, and edits you make in OBS **autosave straight back into
the repo**.

OBS also writes logs, profiler data, browser caches, and binary plugins into
that directory. Because it's symlinked, those land under `obs/<resolution>/`
too — but `.gitignore` tracks only the portable config (`global.ini`,
`user.ini`, `basic/`) and ignores everything else, so the junk never gets
committed.

**Note:** the obs-websocket server password lives in
`plugin_config/obs-websocket/config.json`, which is gitignored — it's a secret
and is never committed. Re-set it in OBS settings if you use WebSocket.

To add a new monitor's config, copy the current live config into a new folder
(quit OBS first), then commit the portable files:

```bash
OBS="$HOME/Library/Application Support/obs-studio"
RES=3840x2160                      # name the folder after the monitor
mkdir -p "obs/$RES"
cp -R "$OBS"/. "obs/$RES"/         # .gitignore keeps only the portable subset
```

## Editing config later

- **zsh** — edit `~/.zshrc` or the theme directly; the symlink means changes land in the repo automatically. Commit when ready.
- **prompt** — edit `starship/starship.toml` (sections, colours, prompt character, truncation). It's symlink-live like the rest, so edits apply on the next prompt; no reinstall. To revert to the old prompt, set `ZSH_THEME="agnoster"` in `zsh/zshrc` — `zsh/agnoster.zsh-theme` is still tracked and still installed, and the Starship init is guarded so it simply does nothing if the binary is absent.
- **git** — edit `~/.gitconfig` or run `git config --global ...` as usual; the symlink means changes (aliases and everything else) land in `git/gitconfig` automatically. Commit when ready.
- **ghostty** — edit `~/.config/ghostty/config` directly; the symlink means changes land in `ghostty/config` automatically. Commit when ready.
- **Claude Code** — edit `~/.claude/CLAUDE.md` (tracked as `claude/global-instructions.md`), `~/.claude/statusline.conf`, `~/.claude/context-window.conf`, the skills, or the scripts directly; the symlinks mean changes land in `claude/` automatically. A *new* skill needs a line in `setup_claude_skills` before it is tracked, and `settings.json` changed from inside a session is worth a quick `ls -l` (see [above](#one-caveat-on-settingsjson)). Commit when ready.

## Committing

A lefthook pre-commit hook runs `shellcheck` and `shfmt -d -i 2 -ci` on staged shell
scripts, and `bats test/` on every commit. Install it once per clone, along with the
three tools — without them commits fail:

```bash
brew install lefthook shellcheck shfmt bats-core
lefthook install
```
