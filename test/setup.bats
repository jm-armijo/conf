#!/usr/bin/env bats
#
# Tests for setup.sh's link() helper — the one piece of real logic in this repo
# (everything else is config data). link() is what touches $HOME, so a bug here
# clobbers real dotfiles; these tests pin its three contracts: it creates the
# symlink, it is idempotent, and it never destroys an existing real file.
#
# Also covers setup_spaceship(), the only step that installs from an upstream
# clone rather than a tracked file, and so the only one that can re-clone or
# litter backups on a re-run.
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

# --- setup_spaceship -------------------------------------------------------
#
# These never reach the network or the real $HOME: HOME is redirected into the
# per-test tmpdir, and a fake `git` earlier on PATH logs the subcommand it was
# called with (and fakes the clone's on-disk result) instead of running it.

# Redirect HOME and install the git stub. $GIT_LOG records each invocation;
# `touch $GIT_FAIL` first to make the stub exit non-zero.
spaceship_env() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export THEMES="$HOME/.oh-my-zsh/custom/themes"
  export DIR="$THEMES/spaceship-prompt"
  export GIT_LOG="${BATS_TEST_TMPDIR}/git.log"
  export GIT_FAIL="${BATS_TEST_TMPDIR}/git.fail"

  local bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin"
  cat >"$bin/git" <<'STUB'
#!/bin/bash
echo "$*" >>"$GIT_LOG"
# Fake what a real clone leaves behind, so the theme symlink has a source.
# Done even in the failure case deliberately: it means a failing clone is
# distinguishable ONLY by its exit status, so a test asserting the failure
# can't pass off the back of link() tripping over a missing source instead.
if [[ "$1" == "clone" ]]; then
  target="${*: -1}"
  mkdir -p "$target/.git"
  echo "theme" >"$target/spaceship.zsh-theme"
fi
[[ -e "$GIT_FAIL" ]] && exit 1
exit 0
STUB
  chmod +x "$bin/git"
  export PATH="$bin:$PATH"
}

# Pretend an earlier `sh install.sh` from oh-my-zsh already ran.
make_omz() {
  mkdir -p "$HOME/.oh-my-zsh"
}

# Simulate a clone already on disk from a previous setup.sh run.
make_clone() {
  mkdir -p "$DIR/.git"
  echo "theme" >"$DIR/spaceship.zsh-theme"
}

# Backups anywhere under the themes dir — the litter a wrong link() would leave.
theme_backup_count() {
  [[ -d "$THEMES" ]] || {
    echo 0
    return
  }
  find "$THEMES" -maxdepth 1 -name '*.backup.*' | wc -l | tr -d ' '
}

@test "setup_spaceship skips and clones nothing when oh-my-zsh is missing" {
  spaceship_env
  [ ! -d "$HOME/.oh-my-zsh" ]

  bats_run setup_spaceship
  [ "$status" -ne 0 ]
  [[ "$output" == skip:* ]]
  # The guard must fire before any git call, not just print alongside one.
  [ ! -e "$GIT_LOG" ]
  [ ! -e "$DIR" ]
}

@test "setup_spaceship clones on a fresh install and links the theme file" {
  spaceship_env
  make_omz

  bats_run setup_spaceship
  [ "$status" -eq 0 ]

  # Shallow clone of the upstream repo into the custom themes dir.
  grep -q '^clone --depth=1 .*spaceship-prompt' "$GIT_LOG"
  grep -q "$DIR\$" "$GIT_LOG"
  ! grep -q '^-C .* pull' "$GIT_LOG"

  # oh-my-zsh only discovers *.zsh-theme at the top of the themes dir, so the
  # nested theme file must be surfaced as a symlink one level up.
  [ -L "$THEMES/spaceship.zsh-theme" ]
  [ "$(readlink "$THEMES/spaceship.zsh-theme")" = "$DIR/spaceship.zsh-theme" ]
}

@test "setup_spaceship pulls an existing clone instead of re-cloning it" {
  spaceship_env
  make_omz
  make_clone
  echo "local marker" >"$DIR/marker"

  bats_run setup_spaceship
  [ "$status" -eq 0 ]

  grep -q "^-C $DIR pull --ff-only\$" "$GIT_LOG"
  ! grep -q '^clone' "$GIT_LOG"

  # The regression this design exists to prevent: link() must never be pointed
  # at the clone dir, or a re-run moves it aside as .backup.* and re-clones.
  [ "$(theme_backup_count)" = "0" ]
  [ -d "$DIR/.git" ]
  [ "$(cat "$DIR/marker")" = "local marker" ]
}

@test "setup_spaceship is idempotent across repeated runs" {
  spaceship_env
  make_omz

  bats_run setup_spaceship
  [ "$status" -eq 0 ]
  bats_run setup_spaceship
  [ "$status" -eq 0 ]

  # Second run pulls rather than cloning again, and leaves no backups behind.
  [ "$(grep -c '^clone' "$GIT_LOG")" = "1" ]
  [ "$(grep -c 'pull --ff-only' "$GIT_LOG")" = "1" ]
  [ "$(theme_backup_count)" = "0" ]
  [ "$(readlink "$THEMES/spaceship.zsh-theme")" = "$DIR/spaceship.zsh-theme" ]
}

@test "setup_spaceship fails when the clone fails" {
  spaceship_env
  make_omz
  touch "$GIT_FAIL"

  bats_run setup_spaceship
  [ "$status" -ne 0 ]
  grep -q '^clone' "$GIT_LOG"
  # The stub leaves a usable clone behind even when it fails, so link() would
  # succeed here. The only thing that can fail this step is the clone's exit
  # status being propagated — and the step must bail before linking a repo
  # that git said it could not fetch.
  [ ! -e "$THEMES/spaceship.zsh-theme" ]
  [ ! -L "$THEMES/spaceship.zsh-theme" ]
  [[ "$output" != *"spaceship: installed"* ]]
}

@test "setup_spaceship fails when the pull fails" {
  spaceship_env
  make_omz
  make_clone
  touch "$GIT_FAIL"

  bats_run setup_spaceship
  [ "$status" -ne 0 ]
  grep -q 'pull --ff-only' "$GIT_LOG"
  ! grep -q '^clone' "$GIT_LOG"
}
