#!/bin/bash

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

errors=()

# Returns 0 even on failure, deliberately: one broken step must not block the rest.
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
    # Split from the assignment: `local x=$(...)` masks the command's exit status.
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

# Separate from setup_starship so the config still lands when brew is skipped or fails.
setup_starship_config() {
  link "$REPO_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
}

setup_git() {
  link "$REPO_DIR/git/gitconfig" "$HOME/.gitconfig"
}

setup_ghostty() {
  link "$REPO_DIR/ghostty/config" "$HOME/.config/ghostty/config"
}

setup_magnet() {
  # `defaults import`, not a symlink: cfprefsd rewrites the plist atomically and
  # would clobber one.
  local plist="$REPO_DIR/magnet/com.crowdcafe.windowmagnet.plist"
  if [[ ! -f "$plist" ]]; then
    echo "skip: magnet plist missing $plist"
    return 1
  fi
  defaults import com.crowdcafe.windowmagnet "$plist" || return 1
  echo "magnet: imported settings (quit & reopen Magnet to apply)"
}

setup_obs() {
  # DIRECTORY symlink, never per-file: OBS's temp-then-rename replaces a file
  # symlink with a real file, but leaves a directory symlink intact.
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

# Per-file links, never a link of ~/.claude itself: Claude Code keeps its own
# runtime state there.
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

# Nothing outside this repo writes to ~/.claude/vendor, so one directory link is safe.
setup_claude_vendor() {
  link "$REPO_DIR/claude/vendor" "$HOME/.claude/vendor"
}

# One link per skill, never a link of ~/.claude/skills: Claude Code's plugins write
# their own state there. The list is explicit on purpose; do not glob it.
setup_claude_skills() {
  local skill status=0
  for skill in bug-fixing clean-code development plan-writing task-status ui-separation; do
    link "$REPO_DIR/claude/skills/$skill" "$HOME/.claude/skills/$skill" || status=1
  done
  return "$status"
}

# Keep new top-level side effects inside this guard: the bats suite sources this file.
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
