#!/bin/bash
#
# Set up a new machine from this repo. Symlinks zsh, git, ghostty and OBS
# config into place (so edits autosave back to the repo) and imports Magnet
# settings.
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
  local desc="$1"; shift
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
    local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup" || { echo "error: could not back up $dest"; return 1; }
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

echo "Setting up from $REPO_DIR"

run "zsh"     setup_zsh
run "git"     setup_git
run "ghostty" setup_ghostty
run "magnet"  setup_magnet
run "obs"     setup_obs

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
