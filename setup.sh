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

backup_partial_omz() {
  local zsh_dir="$1"
  [[ -d "$zsh_dir" ]] || return 0

  local backup
  backup="${zsh_dir}.backup.$(date +%Y%m%d%H%M%S)"
  mv "$zsh_dir" "$backup" || {
    echo "error: could not back up $zsh_dir"
    return 1
  }
  echo "back: moved existing $zsh_dir -> $backup" >&2
  echo "$backup"
}

restore_omz_backup() {
  local backup="$1" zsh_dir="$2"
  [[ -n "$backup" && -d "$backup" ]] || return 0

  mv "$backup" "$zsh_dir" || {
    echo "error: could not move $backup back to $zsh_dir"
    return 1
  }
  echo "back: restored $zsh_dir from $backup"
}

# Copies only the files the destination lacks, so the fresh install's own files
# win any collision and no copy is ever skipped — BSD cp -n exits 1 on a skip,
# which is indistinguishable from a genuine failure.
copy_missing_files() {
  local src="$1" dest="$2"

  local entry rel
  while IFS= read -r entry; do
    rel="${entry#"$src"}"
    rel="${rel#/}"
    [[ -z "$rel" || -e "$dest/$rel" ]] && continue
    if [[ -d "$entry" && ! -L "$entry" ]]; then
      mkdir -p "$dest/$rel" || return 1
      continue
    fi
    mkdir -p "$(dirname "$dest/$rel")" || return 1
    cp -R "$entry" "$dest/$rel" || return 1
  done < <(find "$src")
}

restore_omz_content() {
  local backup="$1" zsh_dir="$2" zsh_custom="$3"
  [[ -n "$backup" && -d "$backup" ]] || return 0

  mkdir -p "$zsh_dir" || return 1
  copy_missing_files "$backup" "$zsh_dir" || {
    echo "error: could not restore content from $backup"
    return 1
  }

  # ZSH_CUSTOM may point outside $zsh_dir, which the copy above cannot reach.
  if [[ -d "$backup/custom" && "$zsh_custom" != "$zsh_dir/custom" ]]; then
    mkdir -p "$zsh_custom" || return 1
    copy_missing_files "$backup/custom" "$zsh_custom" || {
      echo "error: could not restore custom/ from $backup"
      return 1
    }
  fi

  echo "back: restored previous content from $backup"
}

setup_omz() {
  local zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"
  local zsh_custom="${ZSH_CUSTOM:-$zsh_dir/custom}"

  if ! command -v git >/dev/null 2>&1; then
    echo "skip: git not installed — see https://git-scm.com, then re-run"
    return 1
  fi

  # Not -d "$zsh_dir": setup_zsh's theme link makes link() mkdir -p the directory,
  # so a bare directory test reports "installed" forever and never installs.
  if [[ -f "$zsh_dir/oh-my-zsh.sh" ]]; then
    echo "ok:   oh-my-zsh already installed"
  else
    local installer
    installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || return 1
    if [[ -z "$installer" ]]; then
      echo "error: installer download was empty — check network/proxy and re-run"
      return 1
    fi

    # Upstream's installer aborts on an existing $ZSH; move the partial one aside.
    local backup
    backup="$(backup_partial_omz "$zsh_dir")" || return 1

    # ~/.zshrc is already, or is about to become, a symlink into this repo.
    # KEEP_ZSHRC stops the installer moving it aside and writing its own template.
    if ! KEEP_ZSHRC=yes sh -c "$installer" "" --unattended; then
      echo "error: oh-my-zsh install failed — previous $zsh_dir restored"
      restore_omz_backup "$backup" "$zsh_dir"
      return 1
    fi
    restore_omz_content "$backup" "$zsh_dir" "$zsh_custom" || return 1
  fi

  local plugins=("${OMZ_PLUGINS[@]:-zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git}")
  local entry plugin url dest status=0
  for entry in "${plugins[@]}"; do
    read -r plugin url <<<"$entry"
    dest="$zsh_custom/plugins/$plugin"
    if [[ -d "$dest" ]]; then
      continue
    fi
    git clone --depth 1 "$url" "$dest" || status=1
  done

  return "$status"
}

# A real file, not a symlink: apps like Docker Desktop append machine-specific
# lines to ~/.zshrc, which a symlink would write straight into this repo.
install_local_zshrc() {
  local dest="$HOME/.zshrc"
  local line="source \"$REPO_DIR/zsh/zshrc\""

  if [[ -L "$dest" ]]; then
    local backup
    backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup" || {
      echo "error: could not back up $dest"
      return 1
    }
    echo "back: moved existing $dest -> $backup"
  fi

  if [[ -f "$dest" ]] && grep -qxF "$line" "$dest"; then
    echo "ok:   $dest already sources the repo"
    return 0
  fi

  printf '%s\n' "$line" >>"$dest" || return 1
  echo "src:  $dest sources $REPO_DIR/zsh/zshrc"
}

setup_zsh() {
  install_local_zshrc || return 1
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

# The prompt's joiners are private-use glyphs; without a patched font they
# render as tofu boxes.
setup_nerd_font() {
  local cask="font-meslo-lg-nerd-font"

  if ! command -v brew >/dev/null 2>&1; then
    echo "skip: brew not installed — see https://brew.sh, then re-run"
    return 1
  fi

  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "ok:   $cask already installed"
    return 0
  fi

  brew install --cask "$cask" || return 1
  echo "nerd-font: installed (set your terminal font to MesloLGS Nerd Font)"
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

# Separate from setup_ghostty so a refused permission never costs the symlink.
# Ghostty has no +reload-config action and its +new-window is unsupported on
# macOS, so the only way in is the app's own reload_config keybind (cmd+shift+,)
# driven through System Events — which is what raises the permission prompt.
setup_ghostty_reload() {
  if ! command -v ghostty >/dev/null 2>&1; then
    echo "ok:   ghostty not installed — nothing to reload"
    return 0
  fi

  if ! pgrep -xq ghostty; then
    echo "ok:   ghostty not running — config loads on next launch"
    return 0
  fi

  # osascript exits 0 even when System Events cannot see the process or the
  # permission is refused, so the reload is confirmed by asking for state back
  # on stdout — never by exit status.
  if [[ "$(osascript -e 'tell application "System Events" to exists process "ghostty"' 2>/dev/null)" != "true" ]]; then
    echo "error: System Events cannot see ghostty — approve the macOS prompt"
    echo "       (System Settings > Privacy & Security > Accessibility, and"
    echo "       Automation), then re-run, or press cmd+shift+, in Ghostty."
    return 1
  fi

  # keystroke goes to the frontmost app, not to the process named in the tell
  # block, so Ghostty must be raised first or the reload lands in another app.
  osascript -e 'tell application "Ghostty" to activate' >/dev/null 2>&1
  if [[ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)" != "ghostty" ]]; then
    echo "error: could not bring ghostty to the front; skipping the reload"
    echo "       rather than sending cmd+shift+, to another app."
    echo "       Press cmd+shift+, in Ghostty to apply the config."
    return 1
  fi

  osascript -e 'tell application "System Events" to tell process "ghostty" to keystroke "," using {command down, shift down}' >/dev/null 2>&1

  echo "ghostty: reloaded config"
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

# OBS's config files must hold absolute paths for OBS to resolve them, but must
# never commit one — a username baked into a tracked file breaks the next
# machine.
# A clean/smudge filter keeps that invariant by construction; `required` makes
# a missing filter a loud error instead of silently committing the real path.
setup_obs_filter() {
  local filter="$REPO_DIR/obs/filter-mask-path.sh"

  [[ -x "$filter" ]] || {
    echo "skip: no mask-path filter at $filter"
    return 1
  }
  # git splits a filter command on whitespace, so a repo path with a space in
  # it needs the script quoted inside the config value.
  git -C "$REPO_DIR" config filter.obsmaskpath.clean "'$filter' clean" || return 1
  git -C "$REPO_DIR" config filter.obsmaskpath.smudge "'$filter' smudge" || return 1
  git -C "$REPO_DIR" config filter.obsmaskpath.required true || return 1
  echo "obs: registered the mask-path clean/smudge filter"

  resmudge_obs_configs || {
    echo "obs: filter registered, but the re-smudge failed"
    return 1
  }
}

# A clone runs its checkout before this filter is registered, so the worktree
# holds the literal placeholder and git sees nothing to do — the cleaned
# worktree already equals the index. Only an explicit re-checkout expands it.
resmudge_obs_configs() {
  local filter="$REPO_DIR/obs/filter-mask-path.sh" path stash failed=0

  while IFS= read -r -d '' path; do
    [[ -n "$path" && -f "$REPO_DIR/$path" ]] || continue
    grep -qE '\{\{(OBS_CONFIG_DIR|HOME)\}\}' "$REPO_DIR/$path" || continue

    # Restoring from the index is lossless only where the worktree differs by
    # nothing but the path form, which is exactly what cleaning it proves.
    if ! cmp -s \
      <("$filter" clean <"$REPO_DIR/$path") \
      <(git -C "$REPO_DIR" show ":$path"); then
      echo "obs: skipped re-smudge of $path (uncommitted local edits)"
      continue
    fi

    # git skips a checkout whose content already matches the index, so the file
    # must be out of the way for the smudge to run at all. Moved, never
    # unlinked: `required = true` aborts the checkout on a failing smudge, and
    # an unlinked file would be gone with nothing left to restore it from.
    stash="$REPO_DIR/$path.resmudge.$$"
    mv "$REPO_DIR/$path" "$stash" || {
      failed=1
      continue
    }
    if git -C "$REPO_DIR" checkout -- "$path"; then
      rm -f "$stash"
    else
      mv "$stash" "$REPO_DIR/$path"
      failed=1
    fi
  done < <(git -C "$REPO_DIR" ls-files -z ':(attr:filter=obsmaskpath)')
  return "$failed"
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

  run "oh-my-zsh" setup_omz
  run "zsh" setup_zsh
  run "starship" setup_starship
  run "starship-config" setup_starship_config
  run "nerd-font" setup_nerd_font
  run "git" setup_git
  run "ghostty" setup_ghostty
  run "ghostty-reload" setup_ghostty_reload
  run "magnet" setup_magnet
  run "obs" setup_obs
  run "obs-filter" setup_obs_filter
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
