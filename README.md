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
- Installs the **Starship** prompt with `brew install starship` (skipped, with a message, if it's already there or if Homebrew isn't).
- Symlinks `starship/starship.toml` → `~/.config/starship.toml`. This step is independent of the install above, so the config still lands where Homebrew is missing.
- Symlinks `git/gitconfig` → `~/.gitconfig`.
- Symlinks `ghostty/config` → `~/.config/ghostty/config`.
- Symlinks the **Claude Code** global config into `~/.claude` — the global instructions, `settings.json`, the statusline script and its config and colour library, and the two hooks — plus one symlink per tracked skill directory and one for `vendor/`. See [Claude Code](#claude-code) for what is and isn't managed.

The clone location isn't baked in anywhere, so any directory works.

Because these are symlinks, any later edit to your live config is saved straight back into the repo — including `git config --global` writes, which follow the symlink into `git/gitconfig`.

Existing files are backed up (renamed with a `.backup.<timestamp>` suffix) before being replaced. The script is idempotent — safe to re-run. **A failing step does not abort the rest**: the script lists what failed at the end and exits non-zero.

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

The Starship prompt needs a **Nerd Font**. A Powerline font alone renders the rounded
segment caps and the branch/AWS icons as boxes or blanks:

```bash
brew install --cask font-meslo-lg-nerd-font
```

Set the terminal font in `ghostty/config` rather than in a GUI; the symlink makes it live:

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

`starship/starship.toml` is agnoster's look rebuilt on Starship: the same section
order (`status → virtualenv → aws → context → dir → git`) and colours, drawn as
rounded segments.

Colours are the **basic-8 terminal names** (`blue`, `green`, `yellow`, `black`, `red`,
`cyan`), not hex, so the `theme` line in `ghostty/config` recolours the prompt too.

The git segment is two modules: `[git_branch]` is the green pill that is always there,
and `[git_status]` a yellow one that appears beside it only when the tree is dirty.

## Claude Code

`~/.claude` holds both files you write and state Claude Code writes for itself
(transcripts, caches, plugin installs). Only the first group is tracked, one symlink
per file, so the rest stays machine-local:

| Tracked | Linked to |
| --- | --- |
| `claude/global-instructions.md` | `~/.claude/CLAUDE.md` — global instructions applied to every project |
| `claude/settings.json` | `~/.claude/settings.json` — model, env flags, hooks, statusline, enabled plugins, UI prefs |
| `claude/statusline.conf` | `~/.claude/statusline.conf` — tunables for the session-colour assignments |
| `claude/context-window.conf` | `~/.claude/context-window.conf` — the context window and its auto-compact reserve |
| `claude/scripts/statusline.sh` | `~/.claude/scripts/statusline.sh` |
| `claude/lib/session-colors.sh` | `~/.claude/lib/session-colors.sh` — the colour database, also sourceable from your shell |
| `claude/hooks/block-inefficient-bash.sh` | `~/.claude/hooks/block-inefficient-bash.sh` |
| `claude/hooks/plan-artifacts-on-exit.sh` | `~/.claude/hooks/plan-artifacts-on-exit.sh` — renders a plan to `PLAN.html`/`TODO.md` in the browser before you are asked to approve it |
| `claude/skills/<skill>/` | `~/.claude/skills/<skill>/` — one link per skill |
| `claude/vendor/` | `~/.claude/vendor/` — the whole directory, one link; see [Vendored bundles](#vendored-bundles) |

**`claude/global-instructions.md` is renamed to `~/.claude/CLAUDE.md` across the
link**, because a `CLAUDE.md` in this repo would be read as this repo's own project
instructions instead.

**Renaming a script under `claude/` means editing `claude/settings.json` too** — it
names the statusline and the hooks by their `~/.claude/...` paths, and a stale path
is invoked silently with no warning.

`~/.claude/statusline-colors.db` is deliberately neither tracked nor linked: it is
machine-local runtime state the statusline creates on first use. Delete it to reset
every assignment.

### The statusline's one hard rule

**Claude Code discards the entire statusline if the command writes a single byte
to stderr** — no error, no partial render, the line just vanishes. `statusline.sh`
redirects fd 2 to `/dev/null` for the whole script, so editing it means you get no
feedback when something breaks. To diagnose, unmute stderr:

```bash
echo '{}' | STATUSLINE_DEBUG=1 ~/.claude/scripts/statusline.sh
```

Reproduce the hook's environment with `env -i`; an interactive PATH hides this whole
class of failure (`md5sum` lives in `/sbin`, which Claude Code does not pass on):

```bash
echo '{}' | env -i PATH=/usr/bin:/bin HOME="$HOME" ~/.claude/scripts/statusline.sh
```

Tests pin the contract: stderr stays empty across valid, empty and malformed
payloads, exit is zero with non-empty output, and the output is valid UTF-8.

### What the statusline renders

A context-usage bar on top, then a metrics line:

```
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
~/code/conf |  master | task     Opus | ctx:12% | 24.1k tok | 14:22:01 | cpu:3% mem:412M
```

The bar fills as context is used, green through to red. **Full means the
auto-compact point, not the raw window** — it reads 100% exactly when Claude Code
compacts, not when the window is literally full.

`dir | branch | task` share one background colour, so each checkout is visually
distinct — see [Session colours](#session-colours-are-recorded-not-hashed). The
branch is green on a clean tree and yellow when there is any uncommitted change,
untracked files included.

Two settings control the gauge, in `claude/context-window.conf`. It is symlinked
to `~/.claude/context-window.conf`, so a saved change is live immediately:

```bash
CTX_MAX=200000      # raise to 1000000 for an extended-context model
CTX_RESERVE=33000   # what Claude Code holds back for output
```

They describe *Claude Code's* compaction behaviour rather than this script's
display, which is why they are a separate file from `statusline.conf`; anything
else needing the threshold should read it from here. Both have inline defaults,
so an absent or half-written file still renders a statusline.

### Session colours are recorded, not hashed

The `dir | branch | task` block is painted so you can tell one session from
another **without reading the text**. A directory+branch is assigned a colour
once and keeps it permanently, in a SQLite database at
`~/.claude/statusline-colors.db`. Close the session, come back next month, check
the branch out again — same colour.

- **The key is directory + branch.** Switching branch changes the colour, which is
  intended: it is a different piece of work. Switching *back* returns the original.
- **Colours are not exclusive.** Past 12 keys they are reused, least-used first,
  so repeats stay evenly spread.
- **An existing row is never reassigned**, so a live session's colour cannot
  change underneath you.
- **Old assignments are forgotten** after 30 days by default, timed from when the
  colour was first assigned. Cleanup runs only when a new colour is assigned.

Both numbers live in `claude/statusline.conf`, symlinked to
`~/.claude/statusline.conf` and live the moment you save it:

```bash
STATUSLINE_COLOR_RETENTION_DAYS=30   # 0 disables cleanup entirely
STATUSLINE_COLOR_DB="$HOME/.claude/statusline-colors.db"
```

The logic lives in `claude/lib/session-colors.sh`, so you can use it from your
own shell:

```bash
. ~/.claude/lib/session-colors.sh
session_color ~/code/conf master      # prints the assigned code, or nothing
```

`session_color` is **read-only** — opening a terminal cannot claim a colour.
`session_color_assign` is the one that assigns, and only the statusline calls it.

Inspect or reset the database directly:

```bash
sqlite3 ~/.claude/statusline-colors.db 'SELECT * FROM colors;'
rm ~/.claude/statusline-colors.db*     # reset every assignment
```

Every failure degrades to the old behaviour rather than to a broken line: if
`sqlite3` is missing, the directory is unwritable or the database is corrupt, the
statusline falls back to hashing cwd+branch into the same palette.

### Skills

Skills are linked **one directory each**, from a hardcoded list in
`setup_claude_skills` — never `claude/skills` as a whole, because Claude Code's
plugins write into `~/.claude/skills` too. Anything not on the list stays a real
directory beside the symlinks.

To add one:

```bash
mv ~/.claude/skills/<name> claude/skills/<name>   # move the real dir into the repo
# add <name> to the loop in setup_claude_skills, then:
./setup.sh                                        # links it back
```

Until that name is added, the skill is not installed. A test fails if a listed name
has no `SKILL.md`.

Skill directories follow Claude Code's layout: `SKILL.md` at the root, `scripts/`
for executables, `references/` for docs loaded on demand, `assets/` for templates.
`plan-writing` keeps its two templates in `assets/`, so it works on a fresh machine;
`~/.config/claude-templates` is honoured as an override when it exists.

### Planning and doing

`plan-writing` writes a plan to `PLAN.html` and `TODO.md`, opens it in the browser
and halts for approval; **the chat gets one line**, since you read the plan in the
browser. To change the shape of every future plan, edit `assets/UI_TEMPLATE.html` —
it is the input the model plans against.

`development` does the work, in five steps: `writing tests`, `coding`, `bot review`,
`draft pr`, `author review`. Tests move first, `--no-verify` is never allowed, and
each task ends in a draft PR that is a hard stop until you review it. A task needing
an extra step gets one, shown in `PLAN.html` so you can veto it first.

`TODO.md`'s status is derived from the checkboxes, never declared: no steps checked
is not started, some checked is in progress, a checked task is done.

### Vendored bundles

`claude/vendor/` holds third-party JavaScript a generated `PLAN.html` loads from
`file://` — currently just Mermaid 11, the diagram renderer. It is linked as a whole
directory, so a second bundle needs no change to `setup.sh`.

> **Do not open `claude/vendor/mermaid.min.BOTS-DO-NOT-READ.js`.** It is 3.4MB of
> minified build output — roughly 750,000 tokens, several times an LLM context
> window. Reference it by path only; a version bump is a re-download, never a
> hand-edit.

To bump the version:

```bash
curl -sSL -o claude/vendor/mermaid.min.BOTS-DO-NOT-READ.js \
  https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js
```

Then re-prepend the agent guard comment to line 1 — a fresh download strips it —
and check a diagram still renders from `file://`.

**It must load as a classic `<script src>`, never `type="module"`.** From `file://`
an ESM import fails even for a local file, and every diagram then silently renders
as its own source text.

### One caveat on `settings.json`

Claude Code rewrites `settings.json` itself when you change a setting from inside a
session (`/config`, the theme picker). That write may replace the symlink with a
regular file, leaving your change out of the repo. It is harmless, and easy to spot:

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

Magnet's settings are managed by `cfprefsd`, which would clobber a symlink, so
`magnet/com.crowdcafe.windowmagnet.plist` is a **manual backup** — changes there are
not saved automatically.

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

`setup.sh` symlinks the whole `~/Library/Application Support/obs-studio` directory
to the chosen `obs/<resolution>/`, so edits made in OBS **autosave straight back into
the repo**. Never switch this to per-file symlinks — OBS's temp-then-rename saves
would replace them with real files.

OBS also writes logs, caches and binary plugins there. `.gitignore` tracks only
`global.ini`, `user.ini` and `basic/`, so that junk is never committed — a new
tracked OBS file needs a new `!` negation.

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

There is no CI, so the checks live on the commit itself, and nothing is softened
with `|| true`.

`lefthook.yml` runs `shellcheck` and `shfmt` on staged `*.sh`, and the suite when a
commit touches `setup.sh`, `claude/**`, `zsh/**`, `starship/**` or `test/**`. Commits
touching only `obs/`, `ghostty/`, `git/`, `magnet/` or the docs skip the ~15s run.

**The globs use a trailing `**`, which is not interchangeable with `**/*`** — the
latter needs an intermediate directory, so it matches `claude/lib/session-colors.sh`
but misses `claude/settings.json` and skips the suite.

**When you add tests, raise the floor in the `test-count` command.** A truncated
`.bats` file does not fail; it silently defines fewer tests and still exits 0, so the
floor on `bats test/ --count` is what catches a file that stopped parsing partway.

### The plan-mode gate

`claude/hooks/plan-artifacts-on-exit.sh` is a `PreToolUse` gate on `ExitPlanMode`: it
blocks the first exit and points the model at `plan-writing`, then lets the retry
through once `PLAN.html` and `TODO.md` exist. Running before the tool is what puts
the plan in the browser while it is still editable.

It exits 0 for a non-git `cwd` and fails open on bad input, so it cannot wedge plan
mode.

