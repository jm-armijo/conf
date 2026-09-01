# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal dotfiles for macOS. No build step and no runtime dependencies. The only executable is `setup.sh`; everything else is config data consumed by external apps (zsh, git, ghostty, Magnet, OBS).

## Commands

```bash
./setup.sh                # idempotent; safe to re-run. Prompts (via `select`) for an OBS resolution.
bats test/                # the test suite — pins link()'s contract and setup_spaceship's clone/pull branches
shellcheck setup.sh       # lint
shfmt -d -i 2 -ci setup.sh # format check; -d fails on a diff instead of rewriting
lefthook install          # once per clone — installs the pre-commit hook that runs all three
```

`lefthook.yml` scopes shellcheck and shfmt to `*.sh`, but **not** `bats test/` — the suite runs on every commit, including config-only ones.

### Testing gotchas

- `setup.sh` defines its own `run()` step-wrapper, which **shadows bats' built-in `run` helper**. Sourcing `setup.sh` in a test file makes every subsequent `run` invocation fail with `Permission denied`. `test/setup.bats` works around it by aliasing bats' version *before* sourcing: `eval "bats_run() $(declare -f run | tail -n +2)"`. New tests must call `bats_run`, never `run`.
- `setup.sh`'s bottom execution block is guarded by `[[ "${BASH_SOURCE[0]}" == "$0" ]]` (`setup.sh:158`), so a test can source the file to get at `link()` and the `setup_*` functions without running the machine setup. Keep new top-level side effects inside that guard.

## Core architecture: four install strategies

The central design decision is **how each app's config gets onto the machine**, chosen per-app based on how that app writes to its own files. Read `setup.sh:29-52` (`link`) and the per-app comments before changing anything here.

1. **File symlink** (zsh, git, ghostty) — `repo file → ~/dotfile`. Bidirectional: editing the live config, or running `git config --global ...`, writes *through the symlink into the repo*. Changes then show up as uncommitted diffs here.
2. **Directory symlink** (OBS) — `obs/<resolution>/ → ~/Library/Application Support/obs-studio`. OBS saves via temp-then-rename, which **replaces a file symlink with a real file** but leaves a *directory* symlink intact. Never downgrade OBS to per-file symlinks.
3. **Copy/import** (Magnet) — sandboxed Mac App Store app whose plist is rewritten atomically by `cfprefsd`, which clobbers symlinks. Uses `defaults import` instead, and requires a manual `defaults export` to back changes up into the repo.
4. **Clone + pull, then symlink one file out of the clone** (Spaceship) — the theme is an upstream git repo that must be *updated in place*, not a single file this repo vendors, so strategy 1 has nothing to point at. `setup_spaceship` clones `--depth=1` (or `git pull --ff-only` if already there), then uses `link()` only on `spaceship.zsh-theme`, surfacing it one level up because oh-my-zsh discovers themes only directly in the themes dir. **Never call `link()` on the clone directory**: it backs up and replaces its destination, so every re-run would move the clone aside and re-clone, littering `$HOME` with `.backup.*` copies. The themes dir comes from `zsh_custom_dir()`, which **parses `ZSH_CUSTOM` out of `zsh/zshrc`** — `setup.sh` is bash and never sources oh-my-zsh, so `$ZSH_CUSTOM` is unset here and `${ZSH_CUSTOM:-…}` would silently always take the fallback. Don't "simplify" it to that; the two would then disagree and the theme would install where the shell doesn't look.

`setup.sh` runs each app's step through `run()`, which records failures instead of aborting (`set -uo pipefail`, deliberately **not** `-e`), so one broken step never blocks the rest.

## Consequences for editing

- Edits to `zsh/zshrc`, `zsh/spaceship.zsh`, `git/gitconfig`, `ghostty/config`, and `obs/<res>/*` on a machine where `setup.sh` has run are *already live* — no reinstall step. They still need committing.
- `zsh/agnoster.zsh-theme` is still tracked and still installed by `setup_zsh` on purpose: it makes reverting the prompt a one-word `ZSH_THEME` change in `zsh/zshrc`. Don't delete it as dead config.
- `git/gitconfig` is machine-tainted: it contains absolute `/Users/<username>/` paths (`core.excludesfile`, `commit.template`) and a work email. Expect those to drift per machine.
- `obs/` is inverse-gitignored (`.gitignore:6-9`): everything under `obs/*/` is ignored except `global.ini`, `user.ini`, and `basic/`. This is what keeps OBS's logs, caches, plugin binaries, and the **obs-websocket password** out of commits. Adding a new tracked OBS file requires a new `!` negation.
- `bash/`, `tmux/`, and `vim/` are tracked but **not wired into `setup.sh`** — legacy configs, installed by hand if at all.

## Adding a new app

1. Determine how the app writes its config (in-place edit / atomic rename / `cfprefsd`) — that picks the strategy above.
2. Add a `setup_<app>` function returning non-zero on failure; register it with `run "<app>" setup_<app>`.
3. If the app writes non-portable junk into a symlinked directory, extend the `.gitignore` allowlist pattern.
4. Document it in `README.md` — it is the user-facing doc and covers the per-app rationale and manual backup commands.
