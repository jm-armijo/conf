# conf

Personal configuration for **zsh** (with the **Spaceship** prompt), **git**, **ghostty**, and the **Magnet** and **OBS** macOS apps.

## Setup a new machine

Clone the repo anywhere you like, then run the setup script:

```bash
git clone <this-repo-url> ~/code/conf
cd ~/code/conf
./setup.sh
```

The script:

- Symlinks `zsh/zshrc` → `~/.zshrc` and `zsh/agnoster.zsh-theme` → `~/.oh-my-zsh/themes/agnoster.zsh-theme`.
- Clones (or pulls) the **Spaceship** prompt into `~/.oh-my-zsh/custom/themes/spaceship-prompt`, then symlinks its `spaceship.zsh-theme` one level up into `~/.oh-my-zsh/custom/themes/` — oh-my-zsh only discovers themes directly in that directory, never nested. If you uncomment `ZSH_CUSTOM` in `zsh/zshrc`, the script reads that path out of the file and installs there instead, so the shell and the installer never disagree.
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

The Spaceship prompt needs a **Nerd Font** — a stricter requirement than agnoster's
Powerline-patched font, because Spaceship's section icons (git branch, node, ruby, …)
are glyphs that only exist in the Nerd Font range. A Powerline font alone renders them
as boxes or blanks:

```bash
brew install --cask font-meslo-lg-nerd-font
```

The terminal font is part of this repo (`ghostty/config`), so set it there — the symlink
makes it live — rather than in a GUI:

```
font-family = MesloLGS Nerd Font
```

If you'd rather not install a Nerd Font, drop the icon-bearing sections (`git`, `package`,
`node`, `ruby`) from `SPACESHIP_PROMPT_ORDER` in `zsh/spaceship.zsh`; the remaining
sections are plain text.

The agnoster fallback theme needs only a Powerline-patched font:

```bash
git clone https://github.com/powerline/fonts.git --depth=1
cd fonts && ./install.sh && cd .. && rm -rf fonts
```

In iTerm2: Settings → Profiles → Text → enable *Use built-in Powerline glyphs*.

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
- **prompt** — edit `zsh/spaceship.zsh` (sections, prompt character, truncation). It's symlink-live like the rest, so edits apply on the next shell; no reinstall. To revert to the old prompt, set `ZSH_THEME="agnoster"` in `zsh/zshrc` — `zsh/agnoster.zsh-theme` is still tracked and still installed.
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
