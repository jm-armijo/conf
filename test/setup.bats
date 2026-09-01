#!/usr/bin/env bats
#
# Tests for setup.sh's link() helper — the one piece of real logic in this repo
# (everything else is config data). link() is what touches $HOME, so a bug here
# clobbers real dotfiles; these tests pin its three contracts: it creates the
# symlink, it is idempotent, and it never destroys an existing real file.
#
# Also covers setup_starship(), the only step that installs a binary via a
# package manager, and setup_starship_config(), which links its config file.
#
# Run: bats test/

setup() {
  # setup.sh defines its own run() step-wrapper, which would shadow bats' run
  # helper. Alias bats' version to bats_run first, then source; the tests below
  # call bats_run so both functions can coexist.
  eval "bats_run() $(declare -f run | tail -n +2)"

  # Source rather than execute: setup.sh's bottom block is guarded by
  # BASH_SOURCE/$0, so this loads link() without running the machine setup.
  source "${BATS_TEST_DIRNAME}/../setup.sh"

  SRC="${BATS_TEST_TMPDIR}/src"
  DEST="${BATS_TEST_TMPDIR}/dest"
  echo "source content" >"$SRC"
}

# Count of backups next to $DEST, used to prove a backup was / was not made.
backup_count() {
  local n=0 f
  for f in "${DEST}".backup.*; do
    [[ -e "$f" ]] && n=$((n + 1))
  done
  echo "$n"
}

@test "link creates a symlink pointing at the source" {
  bats_run link "$SRC" "$DEST"
  [ "$status" -eq 0 ]
  [ -L "$DEST" ]
  [ "$(readlink "$DEST")" = "$SRC" ]
  [ "$(cat "$DEST")" = "source content" ]
  [ "$(backup_count)" = "0" ]
}

@test "link creates missing parent directories for the destination" {
  local nested="${BATS_TEST_TMPDIR}/a/b/c/config"
  bats_run link "$SRC" "$nested"
  [ "$status" -eq 0 ]
  [ -L "$nested" ]
  [ "$(readlink "$nested")" = "$SRC" ]
}

@test "link is idempotent: re-linking is a no-op with no backup" {
  link "$SRC" "$DEST"
  [ "$(backup_count)" = "0" ]

  bats_run link "$SRC" "$DEST"
  [ "$status" -eq 0 ]
  [[ "$output" == ok:* ]]
  # The critical assertion: an idempotent re-run must not back up the symlink
  # it just created, or repeated setup.sh runs would litter $HOME.
  [ "$(backup_count)" = "0" ]
  [ "$(readlink "$DEST")" = "$SRC" ]
}

@test "link backs up a pre-existing real file and replaces it with the symlink" {
  echo "pre-existing user config" >"$DEST"
  [ ! -L "$DEST" ]

  bats_run link "$SRC" "$DEST"
  [ "$status" -eq 0 ]

  # Destination is now the symlink to the repo...
  [ -L "$DEST" ]
  [ "$(readlink "$DEST")" = "$SRC" ]

  # ...and exactly one backup exists, holding the original contents intact.
  [ "$(backup_count)" = "1" ]
  local backup
  backup="$(echo "${DEST}".backup.*)"
  [ ! -L "$backup" ]
  [ "$(cat "$backup")" = "pre-existing user config" ]
}

@test "link backs up a symlink pointing somewhere else" {
  local other="${BATS_TEST_TMPDIR}/other"
  echo "other content" >"$other"
  ln -s "$other" "$DEST"

  bats_run link "$SRC" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(readlink "$DEST")" = "$SRC" ]
  [ "$(backup_count)" = "1" ]
  [ "$(readlink "$(echo "${DEST}".backup.*)")" = "$other" ]
}

@test "link fails and creates nothing when the source is missing" {
  bats_run link "${BATS_TEST_TMPDIR}/does-not-exist" "$DEST"
  [ "$status" -ne 0 ]
  [[ "$output" == skip:* ]]
  [ ! -e "$DEST" ]
  [ ! -L "$DEST" ]
}

# --- setup_starship --------------------------------------------------------
#
# These never install anything or touch the real $HOME: HOME is redirected into
# the per-test tmpdir, and stubs for `brew` and `starship` earlier on PATH log
# what they were called with instead of running.

# Redirect HOME and build a scratch PATH holding ONLY the stubs a test asks for,
# plus the system dirs setup.sh's own helpers need (mkdir, ln, mv, date). The
# real brew and starship live in /opt/homebrew/bin, which is deliberately NOT on
# this PATH — so "not stubbed" means genuinely absent to `command -v`, rather
# than silently resolving to the developer's real binary and passing vacuously.
#
# $BREW_LOG records each brew invocation; `touch $BREW_FAIL` makes brew fail.
starship_env() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"

  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_DIR/starship"
  echo "# starship config" >"$REPO_DIR/starship/starship.toml"

  export BREW_LOG="${BATS_TEST_TMPDIR}/brew.log"
  export BREW_FAIL="${BATS_TEST_TMPDIR}/brew.fail"

  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:/usr/bin:/bin"
}

# Put a fake `starship` on PATH — i.e. pretend it is already installed.
stub_starship() {
  cat >"$STUB_BIN/starship" <<'STUB'
#!/bin/bash
[[ "$1" == "--version" ]] && echo "starship 1.2.3"
exit 0
STUB
  chmod +x "$STUB_BIN/starship"
}

# Put a fake `brew` on PATH that logs its arguments instead of installing.
stub_brew() {
  cat >"$STUB_BIN/brew" <<'STUB'
#!/bin/bash
echo "$*" >>"$BREW_LOG"
[[ -e "$BREW_FAIL" ]] && exit 1
exit 0
STUB
  chmod +x "$STUB_BIN/brew"
}

@test "setup_starship is a no-op when starship is already installed" {
  starship_env
  stub_starship
  stub_brew

  bats_run setup_starship
  [ "$status" -eq 0 ]
  # The point of the early return: brew must not be invoked at all, not merely
  # invoked and shrugged off — otherwise every setup.sh re-run shells out to a
  # network-touching `brew install` for a binary that is already there.
  [ ! -e "$BREW_LOG" ]
  [[ "$output" == ok:* ]]
}

@test "setup_starship fails with skip: when brew is missing" {
  starship_env
  # Neither stub installed: nothing to short-circuit on, and no brew to use.
  [ ! -x "$STUB_BIN/starship" ]
  [ ! -x "$STUB_BIN/brew" ]

  bats_run setup_starship
  [ "$status" -ne 0 ]
  [[ "$output" == skip:* ]]
  [[ "$output" == *brew* ]]
}

@test "setup_starship brew-installs starship when it is missing" {
  starship_env
  stub_brew
  [ ! -x "$STUB_BIN/starship" ]

  bats_run setup_starship
  [ "$status" -eq 0 ]
  [ -e "$BREW_LOG" ]
  grep -qx 'install starship' "$BREW_LOG"
}

@test "setup_starship fails when brew install fails" {
  starship_env
  stub_brew
  touch "$BREW_FAIL"

  bats_run setup_starship
  [ "$status" -ne 0 ]
  # brew was actually reached and its non-zero exit propagated, rather than the
  # step bailing earlier for an unrelated reason and looking like the same thing.
  grep -qx 'install starship' "$BREW_LOG"
  [[ "$output" != *"starship: installed"* ]]
}

# --- setup_starship_config -------------------------------------------------
#
# Strategy 1: an ordinary link() of the tracked toml. Kept as its own step,
# separate from the brew install, so the config lands even where the binary
# did not.

@test "setup_starship_config symlinks starship.toml into ~/.config" {
  starship_env

  bats_run setup_starship_config
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/starship.toml" ]
  [ "$(readlink "$HOME/.config/starship.toml")" = "$REPO_DIR/starship/starship.toml" ]
  # link() has to create ~/.config itself on a fresh machine, where it is absent.
  [ "$(cat "$HOME/.config/starship.toml")" = "# starship config" ]
}

@test "setup_starship_config does not require starship to be installed" {
  # The reason it is a separate step: a machine where the brew install was
  # skipped or failed must still get the config, ready for the binary's arrival.
  starship_env
  [ ! -x "$STUB_BIN/starship" ]
  [ ! -x "$STUB_BIN/brew" ]

  bats_run setup_starship_config
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/starship.toml" ]
}

@test "setup_starship_config fails when the tracked toml is missing" {
  starship_env
  rm "$REPO_DIR/starship/starship.toml"

  bats_run setup_starship_config
  [ "$status" -ne 0 ]
  [[ "$output" == skip:* ]]
  [ ! -e "$HOME/.config/starship.toml" ]
}

# --- the repo's own tracked files ------------------------------------------
#
# setup.sh and zshrc refer to these by path; a rename, a deletion or a TOML typo
# would otherwise only surface as a promptless shell on a machine that pulled.

@test "the tracked starship.toml exists and parses" {
  local toml="${BATS_TEST_DIRNAME}/../starship/starship.toml"
  [ -f "$toml" ]
  if ! command -v starship >/dev/null 2>&1; then
    skip "starship not installed"
  fi

  # DO NOT reduce this to asserting starship's exit status. On a TOML syntax
  # error starship logs to STDERR and **still exits 0**, silently rendering its
  # built-in default prompt instead — verified against 1.26.0. A status-only
  # check therefore passes on a config the user's shell is quietly ignoring,
  # which is the exact failure this test exists to catch. Diagnostics on stderr
  # are the only signal, so capture and assert on those.
  local err="${BATS_TEST_TMPDIR}/starship.err"
  STARSHIP_CONFIG="$toml" starship module character >/dev/null 2>"$err"
  [ ! -s "$err" ] || {
    cat "$err" >&2
    return 1
  }
}

@test "zshrc initialises starship after sourcing oh-my-zsh" {
  local zshrc="${BATS_TEST_DIRNAME}/../zsh/zshrc"
  local omz init
  omz="$(grep -n '^source \$ZSH/oh-my-zsh\.sh' "$zshrc" | cut -d: -f1)"
  init="$(grep -n 'starship init zsh' "$zshrc" | cut -d: -f1)"
  [ -n "$omz" ]
  [ -n "$init" ]
  # Order is load-bearing: sourcing oh-my-zsh assigns $PROMPT, so a starship
  # init placed above that line is silently overwritten and the prompt reverts.
  [ "$init" -gt "$omz" ]
  # And the init must be guarded, or a machine without the binary prints an
  # error on every single shell start.
  grep -q 'command -v starship' "$zshrc"
}

@test "zshrc selects no oh-my-zsh theme and no longer sources spaceship" {
  local zshrc="${BATS_TEST_DIRNAME}/../zsh/zshrc"
  # ZSH_THEME must be empty: a non-empty theme would race starship for $PROMPT.
  grep -qx 'ZSH_THEME=""' "$zshrc"
  ! grep -qi 'spaceship' "$zshrc"
  [ ! -e "${BATS_TEST_DIRNAME}/../zsh/spaceship.zsh" ]
  # agnoster stays: it is the documented fallback and setup_zsh still links it.
  [ -f "${BATS_TEST_DIRNAME}/../zsh/agnoster.zsh-theme" ]
}
