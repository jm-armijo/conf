#!/usr/bin/env bats
#
# Tests for setup.sh's link() helper — the one piece of real logic in this repo
# (everything else is config data). link() is what touches $HOME, so a bug here
# clobbers real dotfiles; these tests pin its three contracts: it creates the
# symlink, it is idempotent, and it never destroys an existing real file.
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
