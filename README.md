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
- Symlinks the **Claude Code** global config into `~/.claude` — `CLAUDE.md`, `settings.json`, the statusline script and the bash hook — plus one symlink per tracked skill directory. See [Claude Code](#claude-code) for what is and isn't managed.

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
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` — global instructions applied to every project |
| `claude/settings.json` | `~/.claude/settings.json` — model, env flags, hooks, statusline, enabled plugins, UI prefs |
| `claude/scripts/statusline.sh` | `~/.claude/scripts/statusline.sh` |
| `claude/hooks/block-inefficient-bash.sh` | `~/.claude/hooks/block-inefficient-bash.sh` |
| `claude/skills/<skill>/` | `~/.claude/skills/<skill>/` — one link per skill |

`settings.json` refers to the hook and the statusline by their `~/.claude/...`
paths, so those two links are what make it work — renaming a script here without
editing `settings.json` leaves Claude Code silently invoking nothing. A test
pins that pairing.

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
- **Claude Code** — edit `~/.claude/CLAUDE.md`, the skills, or the scripts directly; the symlinks mean changes land in `claude/` automatically. A *new* skill needs a line in `setup_claude_skills` before it is tracked, and `settings.json` changed from inside a session is worth a quick `ls -l` (see [above](#one-caveat-on-settingsjson)). Commit when ready.

## Committing

A lefthook pre-commit hook runs `shellcheck` and `shfmt -d -i 2 -ci` on staged shell
scripts, and `bats test/` on every commit. Install it once per clone, along with the
three tools — without them commits fail:

```bash
brew install lefthook shellcheck shfmt bats-core
lefthook install
```
