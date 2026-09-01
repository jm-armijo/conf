# conf

Personal configuration for **zsh** (with the **Starship** prompt), **git**, **ghostty**, and the **Magnet** and **OBS** macOS apps.

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

## Committing

A lefthook pre-commit hook runs `shellcheck` and `shfmt -d -i 2 -ci` on staged shell
scripts, and `bats test/` on every commit. Install it once per clone, along with the
three tools — without them commits fail:

```bash
brew install lefthook shellcheck shfmt bats-core
lefthook install
```
