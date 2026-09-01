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

# --- zsh_custom_dir --------------------------------------------------------
#
# The break this guards against: a user uncomments zshrc's ZSH_CUSTOM line, so
# their shell scans a different themes dir than the one setup.sh installs into,
# and ZSH_THEME="spaceship" silently stops resolving. The helper has to read the
# answer out of zsh/zshrc, because $ZSH_CUSTOM is never set in this bash script.

# Write a zshrc into the scratch REPO_DIR. It always carries the shipped
# COMMENTED template line (the thing the parser must never match); $1, when
# given, is appended as a real uncommented assignment.
write_zshrc() {
  {
    echo 'ZSH="$HOME/.oh-my-zsh"'
    echo '# Would you like to use another custom folder than $ZSH/custom?'
    echo '# ZSH_CUSTOM=/path/to/new-custom-folder'
    if [[ $# -gt 0 ]]; then echo "ZSH_CUSTOM=$1"; fi
  } >"$REPO_DIR/zsh/zshrc"
}

# Point zsh_custom_dir() at a scratch zshrc holding $1 (or none) and echo it.
custom_dir_for() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_DIR/zsh"
  write_zshrc "$@"
  zsh_custom_dir
}

@test "zsh_custom_dir ignores the commented-out template and falls back" {
  # The default state of the repo's own zshrc. Anything but the fallback here
  # means the parser is matching a comment.
  bats_run custom_dir_for
  [ "$status" -eq 0 ]
  [ "$output" = "${BATS_TEST_TMPDIR}/home/.oh-my-zsh/custom" ]
}

@test "zsh_custom_dir falls back when zshrc is missing entirely" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  REPO_DIR="${BATS_TEST_TMPDIR}/no-such-repo"
  bats_run zsh_custom_dir
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.oh-my-zsh/custom" ]
}

@test "zsh_custom_dir reads an uncommented explicit path" {
  bats_run custom_dir_for "/explicit/path"
  [ "$output" = "/explicit/path" ]
}

@test "zsh_custom_dir expands \$HOME, \${HOME} and ~ in the value" {
  local home="${BATS_TEST_TMPDIR}/home"
  bats_run custom_dir_for '$HOME/omz-custom'
  [ "$output" = "$home/omz-custom" ]
  bats_run custom_dir_for '${HOME}/omz-custom'
  [ "$output" = "$home/omz-custom" ]
  bats_run custom_dir_for '~/omz-custom'
  [ "$output" = "$home/omz-custom" ]
}

@test "zsh_custom_dir expands \$ZSH to the oh-my-zsh install dir" {
  # `ZSH_CUSTOM=$ZSH/custom` is how oh-my-zsh users spell the default. Asserted
  # on a NON-default leaf on purpose: `$ZSH/custom` expands to the same string
  # as the fallback, so a broken expansion would still look right.
  bats_run custom_dir_for '$ZSH/mine'
  [ "$output" = "${BATS_TEST_TMPDIR}/home/.oh-my-zsh/mine" ]
  bats_run custom_dir_for '${ZSH}/braced'
  [ "$output" = "${BATS_TEST_TMPDIR}/home/.oh-my-zsh/braced" ]
}

@test "zsh_custom_dir handles leading whitespace and quoted values" {
  bats_run custom_dir_for '"/quoted/path"'
  [ "$output" = "/quoted/path" ]
  bats_run custom_dir_for "'/single/quoted'"
  [ "$output" = "/single/quoted" ]
  # Leading indentation before the assignment, trailing whitespace after it.
  bats_run custom_dir_for '"$HOME/spaced"   '
  [ "$output" = "${BATS_TEST_TMPDIR}/home/spaced" ]

  export HOME="${BATS_TEST_TMPDIR}/home"
  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_DIR/zsh"
  write_zshrc
  printf '\tZSH_CUSTOM="/indented/path"\n' >>"$REPO_DIR/zsh/zshrc"
  bats_run zsh_custom_dir
  [ "$output" = "/indented/path" ]
}

@test "zsh_custom_dir falls back on values it cannot expand safely" {
  local fallback="${BATS_TEST_TMPDIR}/home/.oh-my-zsh/custom"
  # Relative: would resolve against setup.sh's cwd, not $HOME.
  bats_run custom_dir_for "relative/path"
  [ "$output" = "$fallback" ]
  # An unknown variable — expanding it would need the file eval'd.
  bats_run custom_dir_for '$XDG_CONFIG_HOME/omz'
  [ "$output" = "$fallback" ]
  # Command substitution must never be executed, only refused — including when
  # it hides behind an otherwise-expandable $HOME prefix, where the leading-word
  # check alone would wave it through.
  bats_run custom_dir_for '$(touch '"${BATS_TEST_TMPDIR}"'/pwned)'
  [ "$output" = "$fallback" ]
  bats_run custom_dir_for '$HOME/$(touch '"${BATS_TEST_TMPDIR}"'/pwned)'
  [ "$output" = "$fallback" ]
  bats_run custom_dir_for '$HOME/`touch '"${BATS_TEST_TMPDIR}"'/pwned`'
  [ "$output" = "$fallback" ]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
  # Whitespace inside the value: unquoted, zsh would word-split it; we refuse.
  bats_run custom_dir_for '$HOME/two words'
  [ "$output" = "$fallback" ]
  # Empty assignment.
  bats_run custom_dir_for ""
  [ "$output" = "$fallback" ]
}

@test "zsh_custom_dir takes the last uncommented assignment" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_DIR/zsh"
  write_zshrc "/first/path"
  echo 'ZSH_CUSTOM=/second/path' >>"$REPO_DIR/zsh/zshrc"
  bats_run zsh_custom_dir
  [ "$output" = "/second/path" ]
}

# --- setup_spaceship -------------------------------------------------------
#
# These never reach the network or the real $HOME: HOME is redirected into the
# per-test tmpdir, and a fake `git` earlier on PATH logs the subcommand it was
# called with (and fakes the clone's on-disk result) instead of running it.

# Redirect HOME and install the git stub. $GIT_LOG records each invocation;
# `touch $GIT_FAIL` first to make the stub exit non-zero.
#
# Also points REPO_DIR at a scratch copy of the repo layout holding just
# zsh/zshrc, since zsh_custom_dir() reads the themes location out of that file.
# $1, if given, is the ZSH_CUSTOM value written there uncommented; with no
# argument the zshrc carries only the shipped commented-out template, which is
# the default state every pre-existing test below assumes.
spaceship_env() {
  export HOME="${BATS_TEST_TMPDIR}/home"

  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_DIR/zsh"
  write_zshrc "$@"

  export THEMES
  THEMES="$(zsh_custom_dir)/themes"
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

@test "setup_spaceship installs under \$HOME/.oh-my-zsh/custom by default" {
  # No-regression case: with only the commented template in zshrc, the install
  # lands exactly where it did before zsh_custom_dir() existed.
  spaceship_env
  make_omz

  bats_run setup_spaceship
  [ "$status" -eq 0 ]
  grep -q "$HOME/.oh-my-zsh/custom/themes/spaceship-prompt\$" "$GIT_LOG"
  [ -L "$HOME/.oh-my-zsh/custom/themes/spaceship.zsh-theme" ]
}

@test "setup_spaceship follows an uncommented ZSH_CUSTOM to an explicit path" {
  # The whole point: zshrc moved the custom dir, so the clone and the theme
  # symlink must move with it or the shell never finds the theme.
  spaceship_env "${BATS_TEST_TMPDIR}/elsewhere"
  make_omz
  [ "$THEMES" = "${BATS_TEST_TMPDIR}/elsewhere/themes" ]

  bats_run setup_spaceship
  [ "$status" -eq 0 ]

  grep -q "${BATS_TEST_TMPDIR}/elsewhere/themes/spaceship-prompt\$" "$GIT_LOG"
  [ -d "$DIR/.git" ]
  [ -L "$THEMES/spaceship.zsh-theme" ]
  [ "$(readlink "$THEMES/spaceship.zsh-theme")" = "$DIR/spaceship.zsh-theme" ]

  # ...and nothing was written to the old hardcoded location.
  [ ! -e "$HOME/.oh-my-zsh/custom/themes" ]
}

@test "setup_spaceship follows a \$HOME-relative ZSH_CUSTOM" {
  spaceship_env '$HOME/omz-custom'
  make_omz
  [ "$THEMES" = "$HOME/omz-custom/themes" ]

  bats_run setup_spaceship
  [ "$status" -eq 0 ]
  [ -d "$HOME/omz-custom/themes/spaceship-prompt/.git" ]
  [ -L "$HOME/omz-custom/themes/spaceship.zsh-theme" ]
  [ ! -e "$HOME/.oh-my-zsh/custom/themes" ]
}

@test "setup_spaceship still requires oh-my-zsh when ZSH_CUSTOM is relocated" {
  # The -d ~/.oh-my-zsh guard checks $ZSH, a different variable — relocating
  # ZSH_CUSTOM must not accidentally satisfy or bypass it.
  spaceship_env "${BATS_TEST_TMPDIR}/elsewhere"
  mkdir -p "${BATS_TEST_TMPDIR}/elsewhere"

  bats_run setup_spaceship
  [ "$status" -ne 0 ]
  [[ "$output" == skip:* ]]
  [ ! -e "$GIT_LOG" ]
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
