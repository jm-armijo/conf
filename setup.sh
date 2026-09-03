#!/bin/bash
#
# Set up a new machine from this repo. Symlinks zsh, git, ghostty, OBS and
# Claude Code config into place (so edits autosave back to the repo) and imports
# Magnet settings.
#
# Each step is independent and idempotent: a failing step is recorded and the
# rest still run, and re-running the script is safe.
#
# Usage: ./setup.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

errors=()

# Run a named step; record (don't abort) if it fails so later steps still run.
run() {
  local desc="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "ERROR: $desc"
  errors+=("$desc")
  return 0
}

# Symlink $1 -> $2, backing up an existing real file/dir/symlink at $2 first.
link() {
  local src="$1" dest="$2"

  if [[ ! -e "$src" ]]; then
    echo "skip: source missing $src"
    return 1
  fi

  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "ok:   $dest already links to repo"
    return 0
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    # Declared then assigned separately so `local` doesn't mask date's exit status.
    local backup
    backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup" || {
      echo "error: could not back up $dest"
      return 1
    }
    echo "back: moved existing $dest -> $backup"
  fi

  mkdir -p "$(dirname "$dest")" || return 1
  ln -s "$src" "$dest" || return 1
  echo "link: $dest -> $src"
}

setup_zsh() {
  link "$REPO_DIR/zsh/zshrc" "$HOME/.zshrc" || return 1
  link "$REPO_DIR/zsh/agnoster.zsh-theme" "$HOME/.oh-my-zsh/themes/agnoster.zsh-theme" || return 1
}

# Starship is a compiled Rust binary, not a zsh script, so none of the other
# strategies in this script fit: there is no tracked file to symlink into place
# (strategy 1) and cloning starship.rs would only get us source — building it
# would need a Rust toolchain and a per-machine `cargo build` that takes minutes
# and can fail on a toolchain mismatch. Homebrew already publishes a prebuilt,
# versioned bottle, so installing is a single fast download of a known-good
# binary that `brew upgrade` keeps current alongside everything else.
#
# The binary is the only thing brew owns here; its *config* is a plain file this
# repo tracks, so that goes through link() like every other dotfile (see
# setup_starship_config below).
setup_starship() {
  if command -v starship >/dev/null 2>&1; then
    echo "ok:   starship already installed ($(starship --version | head -n 1))"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "skip: brew not installed — see https://brew.sh, then re-run"
    return 1
  fi

  brew install starship || return 1
  echo "starship: installed (restart your shell to apply)"
}

# The prompt config is an ordinary tracked file, so this is strategy 1 — a plain
# link(), same as zshrc or ghostty/config, and edits to the live file write
# straight back into the repo. Kept as its own step rather than folded into
# setup_starship so the config still lands on a machine where the brew install
# was skipped or failed; it is inert until the binary shows up.
setup_starship_config() {
  link "$REPO_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
}

setup_git() {
  # Symlink the whole global config so `git config --global` edits (aliases and
  # everything else) are written straight back into the repo file.
  link "$REPO_DIR/git/gitconfig" "$HOME/.gitconfig"
}

setup_ghostty() {
  link "$REPO_DIR/ghostty/config" "$HOME/.config/ghostty/config"
}

setup_magnet() {
  # Magnet is a sandboxed app; macOS (cfprefsd) rewrites its plist atomically,
  # so a symlink would be clobbered. Import the saved settings instead.
  # Quit Magnet first so cfprefsd doesn't overwrite the imported values.
  local plist="$REPO_DIR/magnet/com.crowdcafe.windowmagnet.plist"
  if [[ ! -f "$plist" ]]; then
    echo "skip: magnet plist missing $plist"
    return 1
  fi
  defaults import com.crowdcafe.windowmagnet "$plist" || return 1
  echo "magnet: imported settings (quit & reopen Magnet to apply)"
}

setup_obs() {
  # OBS rewrites files via temp-then-rename, which replaces a *file* symlink with
  # a regular file (verified). A *directory* symlink survives, because renames hit
  # files inside it, never the dir itself. So we symlink the whole obs-studio dir
  # to the chosen per-resolution config and edits autosave back into the repo.
  # Heavy/secret bits OBS writes there (logs, caches, plugins, obs-websocket
  # password) are gitignored, so they live on disk but never get committed.
  local dest="$HOME/Library/Application Support/obs-studio"
  local configs=() d choice
  if [[ -d "$REPO_DIR/obs" ]]; then
    for d in "$REPO_DIR/obs"/*/; do
      [[ -d "$d" ]] && configs+=("$(basename "$d")")
    done
  fi

  if [[ ${#configs[@]} -eq 0 ]]; then
    echo "skip: no obs config found in $REPO_DIR/obs"
    return 1
  fi

  echo
  echo "OBS configurations available:"
  select choice in "${configs[@]}" "skip"; do
    [[ -n "$choice" ]] && break
    echo "Please choose a number from the list."
  done

  if [[ "$choice" == "skip" || -z "$choice" ]]; then
    echo "obs: skipped"
    return 0
  fi

  link "$REPO_DIR/obs/$choice" "$dest" || return 1
  echo "obs: linked '$choice' (quit & reopen OBS to apply)"
}

# Claude Code reads these files and rewrites them in place rather than through
# the temp-then-rename dance OBS uses or the atomic plist swap cfprefsd does, so
# strategy 1 (file symlink) holds: edits made in-app — including the settings
# Claude Code itself writes when you change one from inside a session — land back
# in the repo through the link.
#
# Deliberately per-file, NOT a symlink of ~/.claude itself: that directory is
# mostly Claude Code's own runtime state — session transcripts, caches, plugin
# installs, shell snapshots, history.jsonl — which is machine-local, large, and
# in places private. Linking the directory would drag all of it into the repo.
#
# One file is renamed across the link: the repo calls it global-instructions.md,
# Claude Code requires the name CLAUDE.md. Keeping the repo copy under a
# different name stops it being read as THIS repo's project instructions — the
# root CLAUDE.md is a different file with a different job.
#
# Not linked, and not tracked: ~/.claude/statusline-colors.db, the session
# colour assignments. It is runtime state created on first use, machine-local by
# design (a colour belongs to this laptop's checkouts, not to any project).
setup_claude() {
  link "$REPO_DIR/claude/global-instructions.md" "$HOME/.claude/CLAUDE.md" || return 1
  link "$REPO_DIR/claude/settings.json" "$HOME/.claude/settings.json" || return 1
  link "$REPO_DIR/claude/statusline.conf" "$HOME/.claude/statusline.conf" || return 1
  link "$REPO_DIR/claude/context-window.conf" "$HOME/.claude/context-window.conf" || return 1
  link "$REPO_DIR/claude/scripts/statusline.sh" "$HOME/.claude/scripts/statusline.sh" || return 1
  link "$REPO_DIR/claude/lib/session-colors.sh" "$HOME/.claude/lib/session-colors.sh" || return 1
  link "$REPO_DIR/claude/hooks/block-inefficient-bash.sh" "$HOME/.claude/hooks/block-inefficient-bash.sh" || return 1
  link "$REPO_DIR/claude/hooks/plan-artifacts-on-exit.sh" "$HOME/.claude/hooks/plan-artifacts-on-exit.sh" || return 1
}

# Third-party bundles PLAN.html loads from file://, currently just Mermaid.
#
# This one IS a directory symlink, unlike everything else under ~/.claude, and
# the difference is ownership rather than taste. ~/.claude and ~/.claude/skills
# are *shared*: Claude Code and its plugins write their own state into them, so
# linking either would drag that state into the repo — hence the per-file and
# per-skill lists above. Nothing but this repo writes to ~/.claude/vendor; the
# whole directory is ours, which is the OBS case, so one link covers it and
# adding a second vendored bundle needs no line here.
#
# Its own step, not a line in setup_claude, so a machine without it still gets
# settings.json and the hooks; a plan simply renders without its diagram.
setup_claude_vendor() {
  link "$REPO_DIR/claude/vendor" "$HOME/.claude/vendor"
}

# Skills get one symlink per skill directory rather than a single symlink of
# ~/.claude/skills, because that directory is *shared* — Claude Code's plugins
# write their own state into it (the ruby-lsp plugin drops a Gemfile and lockfile
# in skills/.ruby-lsp/). A directory symlink would point that plugin-written junk
# straight at the repo and it would show up as untracked noise on every machine.
#
# Per-skill links keep the boundary exact in both directions: only the skills
# tracked here are repo-backed, and anything else — a plugin's state, a skill
# written on one machine and not yet committed — stays a real directory beside
# them, invisible to git. The cost is that a newly tracked skill needs a line
# here, which is the same explicit opt-in every other app in this script gets.
#
# Its own step, separate from setup_claude, so a missing or renamed skill fails
# loudly on its own line without also taking settings.json and the hooks with it.
setup_claude_skills() {
  local skill status=0
  for skill in bug-fixing clean-code development plan-writing ui-separation; do
    link "$REPO_DIR/claude/skills/$skill" "$HOME/.claude/skills/$skill" || status=1
  done
  return "$status"
}

# Only run the setup when executed directly. Sourcing the script (the bats suite
# does this) just loads the helpers above without touching the machine.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Setting up from $REPO_DIR"

  run "zsh" setup_zsh
  run "starship" setup_starship
  run "starship-config" setup_starship_config
  run "git" setup_git
  run "ghostty" setup_ghostty
  run "magnet" setup_magnet
  run "obs" setup_obs
  run "claude" setup_claude
  run "claude-skills" setup_claude_skills
  run "claude-vendor" setup_claude_vendor

  echo
  if [[ ${#errors[@]} -eq 0 ]]; then
    echo "Done — all steps succeeded. Restart your shell (or run: exec zsh)."
  else
    echo "Done with ${#errors[@]} error(s):"
    for e in "${errors[@]}"; do
      echo "  - $e"
    done
    echo "Fix the above and re-run ./setup.sh (it's safe to re-run)."
    exit 1
  fi
fi
