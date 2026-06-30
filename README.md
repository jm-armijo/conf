# conf

Personal configuration for **zsh**, **git**, **ghostty**, and the **Magnet** and **OBS** macOS apps.

## Setup a new machine

Clone the repo, then run the setup script:

```bash
git clone <this-repo-url> ~/code/personal/conf
cd ~/code/personal/conf
./setup.sh
```

The script:

- Symlinks `zsh/zshrc` → `~/.zshrc` and `zsh/agnoster.zsh-theme` → `~/.oh-my-zsh/themes/agnoster.zsh-theme`.
- Symlinks `git/gitconfig` → `~/.gitconfig`.
- Symlinks `ghostty/config` → `~/.config/ghostty/config`.

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

The agnoster theme needs a Powerline-patched font. Install one and enable it in your terminal:

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
- **git** — edit `~/.gitconfig` or run `git config --global ...` as usual; the symlink means changes (aliases and everything else) land in `git/gitconfig` automatically. Commit when ready.
- **ghostty** — edit `~/.config/ghostty/config` directly; the symlink means changes land in `ghostty/config` automatically. Commit when ready.
