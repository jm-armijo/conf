# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal dotfiles for macOS. No build step and no runtime dependencies. Everything is config data consumed by external apps (zsh, git, ghostty, Claude Code, Magnet, OBS). The only executables are `setup.sh` and the two scripts under `claude/` — `scripts/statusline.sh` and `hooks/block-inefficient-bash.sh` — which are not run by this repo at all; Claude Code invokes them, and they are tracked here only so they can be symlinked into `~/.claude`. They are still covered by the pre-commit shellcheck/shfmt gate, which is globbed on `*.sh` rather than scoped to `setup.sh`.

## Commands

```bash
./setup.sh                # idempotent; safe to re-run. Prompts (via `select`) for an OBS resolution.
bats test/                # the test suite — pins link()'s contract, setup_starship's branches, and the tracked starship.toml/zshrc
shellcheck setup.sh       # lint
shfmt -d -i 2 -ci setup.sh # format check; -d fails on a diff instead of rewriting
lefthook install          # once per clone — installs the pre-commit hook that runs all three
```

`lefthook.yml` scopes shellcheck and shfmt to `*.sh`, but **not** `bats test/` — the suite runs on every commit, including config-only ones.

### Testing gotchas

- `setup.sh` defines its own `run()` step-wrapper, which **shadows bats' built-in `run` helper**. Sourcing `setup.sh` in a test file makes every subsequent `run` invocation fail with `Permission denied`. `test/setup.bats` works around it by aliasing bats' version *before* sourcing: `eval "bats_run() $(declare -f run | tail -n +2)"`. New tests must call `bats_run`, never `run`.
- `setup.sh`'s bottom execution block is guarded by `[[ "${BASH_SOURCE[0]}" == "$0" ]]` (`setup.sh:200`), so a test can source the file to get at `link()` and the `setup_*` functions without running the machine setup. Keep new top-level side effects inside that guard.

## Core architecture: three install strategies

The central design decision is **how each app's config gets onto the machine**, chosen per-app based on how that app writes to its own files. Read `setup.sh:31-58` (`link`) and the per-app comments before changing anything here.

1. **File symlink** (zsh, git, ghostty) — `repo file → ~/dotfile`. Bidirectional: editing the live config, or running `git config --global ...`, writes *through the symlink into the repo*. Changes then show up as uncommitted diffs here.
2. **Directory symlink** (OBS) — `obs/<resolution>/ → ~/Library/Application Support/obs-studio`. OBS saves via temp-then-rename, which **replaces a file symlink with a real file** but leaves a *directory* symlink intact. Never downgrade OBS to per-file symlinks.
3. **Copy/import** (Magnet) — sandboxed Mac App Store app whose plist is rewritten atomically by `cfprefsd`, which clobbers symlinks. Uses `defaults import` instead, and requires a manual `defaults export` to back changes up into the repo.
**Claude Code is strategy 1, but its destination directory is shared.** Every tracked file under `claude/` is a plain `link()`. What makes it different from zsh or ghostty is that `~/.claude` is not a config directory — it is mostly Claude Code's own runtime state (session transcripts, caches, plugin installs, shell snapshots, `history.jsonl`), which is machine-local and in places private. So the links are **per-file, never a link of `~/.claude` itself**.

The same problem recurs one level down, which is why there are two steps:

- `setup_claude` links the four flat files (`CLAUDE.md`, `settings.json`, `scripts/statusline.sh`, `hooks/block-inefficient-bash.sh`).
- `setup_claude_skills` links **one symlink per skill directory**, from a hardcoded list. It is not a link of `claude/skills → ~/.claude/skills`, because Claude Code's *plugins* write into that directory — `skills/.ruby-lsp/` (a Gemfile and lockfile) is the ruby-lsp plugin's doing. A directory symlink would aim that plugin state at the repo. Per-skill links keep untracked things — plugin state, an uncommitted local skill — as real directories beside the symlinks, invisible to git. Adding a tracked skill therefore means adding its name to the loop; that explicit opt-in is the point, not an oversight. `test/setup.bats` pins this by reproducing the `.ruby-lsp` write and asserting it stays out of the repo, so swapping in a directory symlink fails the suite.

Unlike the other apps, `setup_claude_skills` records failures across its loop (`status=1`) instead of returning early, so one renamed skill does not silently skip the rest — the same record-and-continue shape as `run()` one level up.

**Starship spans two of these, on purpose.** It is a compiled Rust binary plus a config file, and those are separate problems:

- The **binary** fits none of the strategies — there is nothing tracked here to symlink, and cloning `starship.rs` would only get source, needing a Rust toolchain and a slow, fallible per-machine `cargo build`. So `setup_starship` shells out to `brew install starship` (strategy: *package manager*), after an early `command -v starship` return so re-runs don't re-invoke brew, and a `command -v brew` guard that returns non-zero with `skip:` rather than failing obscurely.
- The **config** (`starship/starship.toml`) is an ordinary tracked file, so it is plain strategy 1 — `setup_starship_config` just `link()`s it to `~/.config/starship.toml`. It is a **separate `run()` step** so the config still lands on a machine where the brew install was skipped or failed; it is simply inert until the binary shows up.

There is no clone-and-pull strategy any more. It existed only for Spaceship (removed), and with it went `zsh_custom_dir()`, the helper that parsed `ZSH_CUSTOM` out of `zsh/zshrc` to find oh-my-zsh's custom themes dir. Starship isn't an oh-my-zsh theme and never goes near that directory, so nothing reads `ZSH_CUSTOM` in this repo now.

`setup.sh` runs each app's step through `run()`, which records failures instead of aborting (`set -uo pipefail`, deliberately **not** `-e`), so one broken step never blocks the rest.

## Consequences for editing

- Edits to `zsh/zshrc`, `starship/starship.toml`, `git/gitconfig`, `ghostty/config`, `claude/**`, and `obs/<res>/*` on a machine where `setup.sh` has run are *already live* — no reinstall step. They still need committing.
- **A new skill under `claude/skills/` is not installed until its name is added to the loop in `setup_claude_skills`.** Nothing globs that directory, deliberately (see above). A test asserts every name in that list has a `SKILL.md`, so a rename caught there is a failing test rather than a silently missing skill.
- **`claude/settings.json` names `scripts/statusline.sh` and `hooks/block-inefficient-bash.sh` by their `~/.claude/...` paths.** Renaming or moving either script without editing `settings.json` leaves Claude Code invoking a dead path silently — it does not warn. `test/setup.bats` pins the pairing.
- **Whether Claude Code's own writes to `settings.json` survive the symlink is unverified.** It rewrites the file when a setting is changed from inside a session; an in-place write follows the link into the repo, a temp-then-rename would replace the link with a real file (exactly the OBS failure mode). The CLI's `config` subcommand is gone, so there is no non-interactive way to trigger that write path and settle it. `README.md` documents the `ls -l ~/.claude/settings.json` check and the copy-back recovery. Claude Code also drops a timestamped `settings.json.<date>.bak` beside the file before rewriting, so nothing is lost either way.
- `claude/skills/format-technical-response` does not exist on purpose: the directory in `~/.claude/skills` was empty (no `SKILL.md`), so there was nothing to track.
- `zsh/agnoster.zsh-theme` is still tracked and still installed by `setup_zsh` on purpose: it makes reverting the prompt a one-word `ZSH_THEME` change in `zsh/zshrc`. Don't delete it as dead config.
- **`zsh/zshrc` has `ZSH_THEME=""` deliberately.** Starship owns `$PROMPT` now; a non-empty oh-my-zsh theme would race it. The `eval "$(starship init zsh)"` line must stay **below** `source $ZSH/oh-my-zsh.sh` — that line assigns `$PROMPT`, so an init above it is silently overwritten — and must keep its `command -v starship` guard so a machine without the binary still gets a working shell.
- **`starship --version` exits 0 on a broken config.** A TOML syntax error is logged to *stderr* and starship carries on with its built-in defaults; the same is true of `starship module`/`prompt`. So any check that a config parses must assert on **stderr being empty**, never on exit status — `test/setup.bats` does this, and a status-only check there passes vacuously (verified against 1.26.0).
- `git/gitconfig` is machine-tainted: it contains absolute `/Users/<username>/` paths (`core.excludesfile`, `commit.template`) and a work email. Expect those to drift per machine.
- `obs/` is inverse-gitignored (`.gitignore:6-9`): everything under `obs/*/` is ignored except `global.ini`, `user.ini`, and `basic/`. This is what keeps OBS's logs, caches, plugin binaries, and the **obs-websocket password** out of commits. Adding a new tracked OBS file requires a new `!` negation.
- `bash/`, `tmux/`, and `vim/` are tracked but **not wired into `setup.sh`** — legacy configs, installed by hand if at all.

## Adding a new app

1. Determine how the app writes its config (in-place edit / atomic rename / `cfprefsd`) — that picks the strategy above.
2. Add a `setup_<app>` function returning non-zero on failure; register it with `run "<app>" setup_<app>`.
3. If the app writes non-portable junk into a directory you want to link, pick one of the two ways this repo already handles that: **link the directory and gitignore the junk** (OBS — right when the app owns the whole directory and you want its edits to autosave), or **link the individual files/subdirectories** (Claude Code — right when the directory is *shared* with state that should never be in the repo at all). The first keeps junk on disk inside the repo but out of commits; the second keeps it out of the repo entirely, at the cost of an explicit list to maintain.
4. Document it in `README.md` — it is the user-facing doc and covers the per-app rationale and manual backup commands.
