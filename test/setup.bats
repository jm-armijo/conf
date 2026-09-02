#!/usr/bin/env bats
#
# Tests for setup.sh's link() helper — the one piece of real logic in this repo
# (everything else is config data). link() is what touches $HOME, so a bug here
# clobbers real dotfiles; these tests pin its three contracts: it creates the
# symlink, it is idempotent, and it never destroys an existing real file.
#
# Also covers setup_starship(), the only step that installs a binary via a
# package manager, setup_starship_config(), which links its config file, and
# setup_claude/setup_claude_skills, which link into a directory Claude Code and
# its plugins also write to.
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

# --- setup_claude / setup_claude_skills ------------------------------------
#
# Strategy 1 throughout, but split across two steps and — for skills — one link
# per skill directory rather than one for the whole dir. What the tests below
# actually pin is that boundary: ~/.claude and ~/.claude/skills are shared with
# Claude Code's own runtime state, so the untracked things living beside our
# links must survive setup and must not be pulled into the repo.

# Build a repo tree holding exactly what setup_claude* links, with HOME
# redirected into the tmpdir. Contents are unique per file so a test can prove
# which source a link resolved to, not merely that something is there.
claude_env() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"

  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_DIR/claude/scripts" "$REPO_DIR/claude/hooks" "$REPO_DIR/claude/lib"
  echo "# global instructions" >"$REPO_DIR/claude/global-instructions.md"
  echo '{"model":"opus"}' >"$REPO_DIR/claude/settings.json"
  echo "STATUSLINE_COLOR_RETENTION_DAYS=30" >"$REPO_DIR/claude/statusline.conf"
  echo "CTX_MAX=200000" >"$REPO_DIR/claude/context-window.conf"
  echo "#!/bin/bash" >"$REPO_DIR/claude/scripts/statusline.sh"
  echo "#!/bin/bash" >"$REPO_DIR/claude/lib/session-colors.sh"
  echo "#!/bin/bash" >"$REPO_DIR/claude/hooks/block-inefficient-bash.sh"

  local skill
  for skill in bug-fixing clean-code plan-execution plan-writing ui-separation; do
    mkdir -p "$REPO_DIR/claude/skills/$skill"
    echo "# $skill" >"$REPO_DIR/claude/skills/$skill/SKILL.md"
  done
}

@test "setup_claude symlinks the tracked files into ~/.claude" {
  claude_env

  bats_run setup_claude
  [ "$status" -eq 0 ]

  # These land at the same relative path on both sides.
  local f
  for f in settings.json statusline.conf context-window.conf \
    scripts/statusline.sh lib/session-colors.sh \
    hooks/block-inefficient-bash.sh; do
    [ -L "$HOME/.claude/$f" ]
    [ "$(readlink "$HOME/.claude/$f")" = "$REPO_DIR/claude/$f" ]
  done

  # This one is renamed across the link: Claude Code demands the name CLAUDE.md,
  # while the repo keeps it as global-instructions.md so it is not mistaken for
  # the repo's own project instructions.
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$REPO_DIR/claude/global-instructions.md" ]
  # link() has to create ~/.claude/scripts and ~/.claude/hooks itself: on a fresh
  # machine Claude Code has not made them yet.
  [ "$(cat "$HOME/.claude/CLAUDE.md")" = "# global instructions" ]
}

@test "setup_claude is idempotent" {
  claude_env
  setup_claude

  bats_run setup_claude
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude/settings.json")" = "$REPO_DIR/claude/settings.json" ]
  # A re-run must not back up the symlinks it just made, or every setup.sh run
  # would litter ~/.claude with dated copies.
  local backups=("$HOME"/.claude/*.backup.*)
  [ ! -e "${backups[0]}" ]
}

@test "setup_claude fails when the renamed global instructions file is missing" {
  claude_env
  rm "$REPO_DIR/claude/global-instructions.md"

  bats_run setup_claude
  [ "$status" -ne 0 ]
  [[ "$output" == *skip:* ]]
  [ ! -e "$HOME/.claude/CLAUDE.md" ]
}

@test "setup_claude fails when a tracked file is missing" {
  claude_env
  rm "$REPO_DIR/claude/settings.json"

  bats_run setup_claude
  [ "$status" -ne 0 ]
  [[ "$output" == *skip:* ]]
  [ ! -e "$HOME/.claude/settings.json" ]
}

@test "setup_claude backs up a pre-existing real settings.json" {
  claude_env
  mkdir -p "$HOME/.claude"
  echo '{"model":"sonnet"}' >"$HOME/.claude/settings.json"

  bats_run setup_claude
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/settings.json" ]
  # The pre-move settings are not destroyed — this is the file the user had
  # before adopting the repo, and it is the only copy of it anywhere.
  local backup
  backup="$(echo "$HOME"/.claude/settings.json.backup.*)"
  [ "$(cat "$backup")" = '{"model":"sonnet"}' ]
}

@test "setup_claude_skills symlinks each tracked skill directory" {
  claude_env

  bats_run setup_claude_skills
  [ "$status" -eq 0 ]

  local skill
  for skill in bug-fixing clean-code plan-execution plan-writing ui-separation; do
    # Per-skill *directory* symlinks, so a skill's own references/ subtree comes
    # along without needing a line here for every file inside it.
    [ -L "$HOME/.claude/skills/$skill" ]
    [ "$(readlink "$HOME/.claude/skills/$skill")" = "$REPO_DIR/claude/skills/$skill" ]
    [ "$(cat "$HOME/.claude/skills/$skill/SKILL.md")" = "# $skill" ]
  done
}

@test "setup_claude_skills leaves plugin-written state in ~/.claude/skills alone" {
  claude_env
  # Reproduces what the ruby-lsp plugin actually does: it writes its own state
  # into ~/.claude/skills. This is the whole reason skills are linked per-skill
  # instead of as one directory symlink — a directory link would put ~/.claude/
  # skills *inside* the repo, so this state would land there as untracked junk.
  mkdir -p "$HOME/.claude/skills/.ruby-lsp"
  echo "gem 'ruby-lsp'" >"$HOME/.claude/skills/.ruby-lsp/Gemfile"

  bats_run setup_claude_skills
  [ "$status" -eq 0 ]

  # Untouched on disk, and — the actual assertion — still outside the repo.
  [ -f "$HOME/.claude/skills/.ruby-lsp/Gemfile" ]
  [ ! -L "$HOME/.claude/skills/.ruby-lsp" ]
  [ ! -e "$REPO_DIR/claude/skills/.ruby-lsp" ]
}

@test "setup_claude_skills is idempotent" {
  claude_env
  setup_claude_skills

  bats_run setup_claude_skills
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude/skills/clean-code")" = "$REPO_DIR/claude/skills/clean-code" ]
  local backups=("$HOME"/.claude/skills/*.backup.*)
  [ ! -e "${backups[0]}" ]
}

@test "setup_claude_skills links the remaining skills when one is missing" {
  claude_env
  rm -r "$REPO_DIR/claude/skills/clean-code"

  bats_run setup_claude_skills
  [ "$status" -ne 0 ]
  [[ "$output" == *skip:* ]]
  [ ! -e "$HOME/.claude/skills/clean-code" ]
  # One bad skill must not abort the loop: the others still have to be installed,
  # matching run()'s record-and-continue behaviour one level up.
  [ -L "$HOME/.claude/skills/bug-fixing" ]
  [ -L "$HOME/.claude/skills/ui-separation" ]
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

@test "the tracked claude settings.json is valid JSON" {
  local settings="${BATS_TEST_DIRNAME}/../claude/settings.json"
  [ -f "$settings" ]
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not installed"
  fi
  jq -e . "$settings" >/dev/null
}

@test "claude settings.json points at scripts this repo actually tracks" {
  local settings="${BATS_TEST_DIRNAME}/../claude/settings.json"
  # settings.json names the hook and statusline by their ~/.claude path (either
  # tilde-form or fully expanded). Those paths are symlinks into claude/scripts
  # and claude/hooks, so renaming a script here without editing settings.json
  # leaves Claude Code silently invoking nothing.
  grep -qE '(~|/Users/[^"]*)/\.claude/scripts/statusline\.sh' "$settings"
  grep -qE '(~|/Users/[^"]*)/\.claude/hooks/block-inefficient-bash\.sh' "$settings"
  [ -x "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh" ]
  [ -x "${BATS_TEST_DIRNAME}/../claude/hooks/block-inefficient-bash.sh" ]
}

@test "every skill setup_claude_skills links has a SKILL.md" {
  # The names are hardcoded in setup_claude_skills; a skill renamed or deleted in
  # claude/skills without that list being updated would only surface as a failing
  # step on the next machine setup.
  local skill
  for skill in bug-fixing clean-code plan-execution plan-writing ui-separation; do
    [ -f "${BATS_TEST_DIRNAME}/../claude/skills/$skill/SKILL.md" ]
  done
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

@test "statusline writes nothing to stderr" {
  # THE contract: Claude Code discards the entire statusline if the command
  # writes a single byte to stderr, with no error shown anywhere. Two separate
  # outages this session were exactly this -- md5sum resolving only in /sbin
  # (absent from the hook PATH), and `ps` on a PID that had gone away. Both
  # produced a perfectly good stdout and an invisible statusline.
  #
  # env -i is load-bearing: every earlier manual test inherited an interactive
  # PATH containing /sbin and so could not reproduce the md5sum failure.
  local script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"
  local payload err
  err="${BATS_TEST_TMPDIR}/stderr"

  for payload in \
    '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"}}' \
    '{}' \
    'not json at all'; do
    printf '%s' "$payload" |
      env -i PATH=/usr/bin:/bin HOME="$HOME" \
        STATUSLINE_CONF=/nonexistent \
        STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/direct.db" "$script" >/dev/null 2>"$err"
    [ "$(wc -c <"$err" | tr -d ' ')" -eq 0 ]
  done
}

@test "statusline exits zero and emits output on a degenerate payload" {
  local script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"
  local out
  out="${BATS_TEST_TMPDIR}/stdout"
  printf '%s' '{}' |
    env -i PATH=/usr/bin:/bin HOME="$HOME" \
        STATUSLINE_CONF=/nonexistent \
        STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/direct.db" "$script" >"$out" 2>/dev/null
  [ "$?" -eq 0 ]
  [ -s "$out" ]
}

@test "statusline output is valid UTF-8" {
  # The bar is built by repeat count, not by measuring length, because awk's
  # length() counts BYTES in this locale and the block glyph is 3 of them --
  # a length-based loop sliced the final glyph mid-sequence and emitted
  # invalid UTF-8. iconv is the check that would catch that regression.
  local script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"
  printf '%s' '{"workspace":{"current_dir":"/tmp"}}' |
    env -i PATH=/usr/bin:/bin HOME="$HOME" \
        STATUSLINE_CONF=/nonexistent \
        STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/direct.db" "$script" 2>/dev/null |
    iconv -f UTF-8 -t UTF-8 >/dev/null
}

# --- statusline rendering ------------------------------------------------
#
# Shared helpers. Every invocation goes through `env -i PATH=/usr/bin:/bin` for
# the same reason test 28 does: an inherited interactive PATH includes /sbin and
# hides the entire class of "binary not on the hook PATH" failure.
#
# COLUMNS is set explicitly so the width does not depend on whatever terminal
# bats happens to run under; the script prefers $COLUMNS over walking the
# process ancestry for a TTY, which makes the layout deterministic here.

# env -i, so COLORTERM is UNSET unless a third argument supplies it. That is the
# 256-colour fallback path; pass "truecolor" as $3 for the 24-bit path. Both are
# real: the fallback is what a plain xterm gets, truecolor is what ghostty gets.
statusline_run() { # <columns> <payload> [colorterm]
  # STATUSLINE_COLOR_DB is redirected into the test's own tmpdir. Without it
  # the script resolves the library from the real $HOME and every test run
  # writes assignments into the developer's LIVE ~/.claude/statusline-colors.db
  # -- one row per bats temp directory, none of which exist afterwards. That is
  # how 129 rows of dead /var/folders/... keys accumulated, including codes
  # from mutation runs that fail the contrast bar. Assignments are permanent by
  # design, so this pollution is not self-healing.
  # STATUSLINE_CONF must be pointed away too: the tracked conf assigns
  # STATUSLINE_COLOR_DB unconditionally, so sourcing it would overwrite the
  # redirect below and put the writes back into the live database.
  # CLAUDE_CONTEXT_CONF is redirected for the same isolation reason: unset, the
  # script would read the developer's live ~/.claude/context-window.conf and the
  # expected percentages would depend on whatever CTX_MAX that machine happens
  # to carry. Defaulting it to a nonexistent path also means every existing
  # statusline test exercises the INLINE fallbacks, which is the state a fresh
  # machine is in. A test that wants a real conf sets it before calling.
  printf '%s' "$2" |
    env -i PATH=/usr/bin:/bin HOME="$HOME" COLUMNS="$1" ${3:+COLORTERM="$3"} \
      STATUSLINE_CONF=/nonexistent \
      CLAUDE_CONTEXT_CONF="${CLAUDE_CONTEXT_CONF:-/nonexistent}" \
      STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/statusline-run.db" \
      "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh" 2>/dev/null
}

# Visible width of one line: SGR sequences stripped, then counted in CHARACTERS.
# `wc -m` and not awk's length(), which counts BYTES in this locale -- the block
# and branch glyphs are 3 bytes each and would be billed as 3 columns.
line_width() {
  printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

# A transcript yielding an exact token total, so CTX_PCT is a known value
# rather than whatever the live session happens to be using. This is the
# FALLBACK source -- see context_window_payload for the primary one.
make_transcript() { # <tokens> <path>
  printf '{"isSidechain":false,"message":{"usage":{"input_tokens":%d,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}\n' \
    "$1" >"$2"
}

# A payload carrying the context_window object Claude Code has emitted since
# v2.1.251 -- the PRIMARY source for both the token count and the window size.
# total_input_tokens is input + cache_creation + cache_read and EXCLUDES output,
# which is the same basis the compaction check itself uses.
#
# used_percentage is present in the real payload and is deliberately NOT read by
# the script: it divides by the RAW window, so it reads ~83.5 at the moment
# compaction fires. A wrong value is seeded here on purpose, so a regression
# that starts trusting the field is caught rather than merely unproven.
context_window_payload() { # <total_input_tokens> <context_window_size>
  printf '{"workspace":{"current_dir":"/tmp"},"context_window":{"total_input_tokens":%d,"context_window_size":%d,"used_percentage":99}}' \
    "$1" "$2"
}

@test "statusline renders two lines and aligns metrics to the bar when content fits" {
  # 160 columns less the default BAR_MARGIN of 12 leaves a 148-column bar. The
  # metrics line must terminate on exactly that column -- that alignment is the
  # whole point of the PAD computation.
  local out
  out=$(statusline_run 160 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"}}')
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(line_width "$(printf '%s\n' "$out" | sed -n 1p)")" -eq 148 ]
  [ "$(line_width "$(printf '%s\n' "$out" | sed -n 2p)")" -eq 148 ]
}

@test "statusline wraps to three lines when the metrics overflow the width" {
  # A long customTitle plus a narrow terminal drives PAD negative, which is the
  # overflow signal. LEFT and RIGHT then get a line each.
  local out
  out=$(statusline_run 90 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"customTitle":"a-fairly-long-session-title-x"}')
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "statusline right-aligns the wrapped right-hand group to the bar's edge" {
  # The wrapped RIGHT group is padded out to the bar width so it stays flush
  # against the same right edge, rather than starting at column 1.
  local out bar right
  out=$(statusline_run 90 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"customTitle":"a-fairly-long-session-title-x"}')
  bar=$(line_width "$(printf '%s\n' "$out" | sed -n 1p)")
  right=$(line_width "$(printf '%s\n' "$out" | sed -n 3p)")
  [ "$bar" -eq 78 ]
  [ "$right" -eq "$bar" ]
  # Padded on the LEFT, so the line must begin with spaces. A left-aligned
  # render would start straight into the model name and fail here.
  printf '%s\n' "$out" | sed -n 3p | sed $'s/\033\\[[0-9;]*m//g' | grep -q '^  *[^ ]'
}

@test "statusline never emits a negative pad when the right group alone overflows" {
  # printf reads a NEGATIVE "%*s" width as a left-justify flag and silently
  # emits nothing, so WRAP_PAD is clamped at 0. At 40 columns the bar is 28 and
  # RIGHT alone is wider than that: the group starts at column 1 and overruns,
  # which is correct, but the line must still be non-empty and unpadded.
  local out third
  out=$(statusline_run 40 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"customTitle":"a-fairly-long-session-title-x"}')
  third=$(printf '%s\n' "$out" | sed -n 3p)
  [ -n "$third" ]
  printf '%s' "$third" | sed $'s/\033\\[[0-9;]*m//g' | grep -qv '^ '
}

@test "statusline progress bar fill tracks context percentage" {
  # Fill length is CTX_PCT of the bar width. At 112 columns the bar is 100, so
  # the filled run is numerically equal to the percentage -- 0 at empty, 100 at
  # the AUTO-COMPACT POINT.
  #
  # 100% is 167000, not 200000: the scale's denominator is the USABLE window,
  # CTX_MAX minus the CTX_RESERVE that auto-compaction holds back for output
  # (200000 - 33000). A bar that divided by the raw 200000 read ~84% at the
  # instant compaction fired, showing ~14 cells of headroom that did not exist.
  # 83500 is exactly half the usable window and must therefore read 50.
  local t out fill
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  for pair in "0 0" "16700 10" "83500 50" "167000 100"; do
    set -- $pair
    make_transcript "$1" "$t"
    out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
    # Everything before the track colour (grey 238) is the filled run.
    fill=$(printf '%s' "$out" | sed $'s/\033\\[38;5;238m.*//' |
      sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    [ "$fill" -eq "$2" ]
  done
}

# The `ctx:N%` reading off the metrics line, which is the number the bar fill is
# derived from. Read from the rendered output rather than by sourcing anything,
# so it pins what the user actually sees.
ctx_pct() { # <payload> [columns]
  statusline_run "${2:-200}" "$1" |
    sed $'s/\033\\[[0-9;]*m//g' |
    sed -n $'s/.*ctx:\\([0-9]*\\)%.*/\\1/p'
}

@test "statusline context percentage is scaled to the auto-compact point" {
  # The core of the rescale, asserted on the printed number rather than on the
  # bar so a fill-rounding change cannot mask it.
  #
  # Claude Code auto-compacts when the INPUT token count reaches
  # window - reserve, and the reserve is an ABSOLUTE output budget (~33000),
  # not a fraction of the window. So the gauge must hit 100 at 167000 on a
  # 200000 window, and read half at 83500.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  make_transcript 167000 "$t"
  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 100 ]

  make_transcript 83500 "$t"
  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 50 ]
}

@test "statusline reads the context_window payload in preference to the transcript" {
  # context_window is the authoritative source: it is what Claude Code itself
  # measures, whereas the transcript sum is this script reconstructing the same
  # number after the fact. When both are present the payload must win.
  #
  # The two are seeded with DIFFERENT totals precisely so the winner is
  # identifiable: 83500 from the payload is 50%, while the transcript's 167000
  # would be 100%. Reading the transcript here yields 100 and fails.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"

  local payload
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s","context_window":{"total_input_tokens":83500,"context_window_size":200000,"used_percentage":99}}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]
}

@test "statusline falls back to the transcript when context_window is absent" {
  # Older CLI versions emit no context_window at all, and even a current one
  # emits a null window at the very start of a session, before the first
  # request. The transcript sum has to keep working for both.
  local t payload
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 83500 "$t"

  # Field absent entirely.
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]

  # Present but null, which is the start-of-session shape.
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s","context_window":null}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]

  # Present, but with null members -- the same start-of-session state one level
  # down. A `// empty` that only guarded the object would let a null token count
  # through and render 0%.
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s","context_window":{"total_input_tokens":null,"context_window_size":null}}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]
}

@test "statusline scales the context_window payload to the compact point" {
  # Same rescale as the transcript path, asserted on the payload path because it
  # is separate code. 167000 of a declared 200000 window is the compact point.
  [ "$(ctx_pct "$(context_window_payload 167000 200000)")" -eq 100 ]
  [ "$(ctx_pct "$(context_window_payload 83500 200000)")" -eq 50 ]

  # And the payload's own used_percentage (seeded at 99) must not be what is
  # printed -- these readings prove the script computes its own.
  [ "$(ctx_pct "$(context_window_payload 0 200000)")" -eq 0 ]
}

@test "statusline clamps a larger context_window_size down to CTX_MAX" {
  # An extended-context session reports context_window_size 1000000. The
  # configured CTX_MAX is a CEILING -- autoCompactWindow caps the effective
  # window below the model's native one -- so a larger reported window must be
  # clamped rather than believed.
  #
  # 167000 tokens is the compact point under the clamped 200000 window and must
  # read 100. Believing the reported 1000000 would put it at (1000000-33000)
  # usable and render 17 instead.
  [ "$(ctx_pct "$(context_window_payload 167000 1000000)")" -eq 100 ]

  # The clamp follows CTX_MAX rather than a hardcoded 200000: raise the conf to
  # the full extended window and the same token count is a small fraction again.
  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/extended.conf"
  cat >"$CLAUDE_CONTEXT_CONF" <<'EOF'
CTX_MAX=1000000
CTX_RESERVE=33000
EOF
  [ "$(ctx_pct "$(context_window_payload 967000 1000000)")" -eq 100 ]
  [ "$(ctx_pct "$(context_window_payload 167000 1000000)")" -eq 17 ]
}

@test "statusline clamps a smaller context_window_size to itself, not to CTX_MAX" {
  # The clamp is a MINIMUM of the two, not an unconditional override. A session
  # genuinely running a smaller window than CTX_MAX must be scaled against the
  # smaller one, or the gauge under-reports exactly the way the raw-window bug
  # did. 33500 of a 100000-token window is half its 67000 usable span.
  [ "$(ctx_pct "$(context_window_payload 33500 100000)")" -eq 50 ]
}

@test "statusline context percentage clamps at 100 past the compact point" {
  # Compaction is not instantaneous and a single large turn can overshoot the
  # threshold before it fires, so tokens above the usable window are a REAL
  # state, not an impossible one. The gauge must saturate rather than print a
  # nonsensical "ctx:120%".
  #
  # 200000 is a genuine OVERSHOOT of the 167000 compact point, not a full
  # window: unclamped it computes to 120. Seeding the compact point itself here
  # would pass without any clamp at all.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  make_transcript 200000 "$t"
  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 100 ]

  # The bar fill saturates with it, rather than running past the bar's end.
  # The bar line is isolated into a variable BEFORE the escapes are stripped:
  # piping the whole render through the strip would fold the metrics line into
  # the count, since with a full bar there is no track colour left to cut at.
  local out fill
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
  fill=$(printf '%s' "$out" | sed $'s/\033\\[38;5;238m.*//' |
    sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
  [ "$fill" -eq 100 ]
}

# Every SGR foreground code appearing in the bar's FILLED run, in order. The
# track colour 238 and everything from it onward is cut first, so only gradient
# cells are returned. Codes repeat once per RUN, not once per cell, because
# consecutive cells resolving to the same code share one escape sequence.
#
# grep -o and not a sed s///gp: sed's global substitute has to walk the glyph
# bytes between matches, and the block glyph is 3 bytes, which trips multibyte
# handling on this platform's sed/awk. grep -o only ever touches the ASCII
# escape sequences.
# Handles BOTH output formats: "38;5;N" on the fallback path and "38;2;R;G;B" on
# the truecolor one. A truecolor cell is returned as "R;G;B" so callers can split
# it; a fallback cell as the bare cube code.
bar_codes() { # <line>
  printf '%s' "$1" | sed $'s/\033\\[38;5;238m.*//' |
    grep -o $'\033\\[38;[25];[0-9;]*m' |
    sed $'s/\033\\[38;5;//;s/\033\\[38;2;//;s/m$//'
}

# One code per CELL rather than per run: expand the run-length coalesced
# escapes by counting the glyphs that follow each. Counted with `wc -m` under a
# UTF-8 locale, never awk's length(), which counts BYTES here and would report 3
# for every glyph.
bar_cell_codes() { # <line>
  local filled seg code n
  filled=$(printf '%s' "$1" | sed $'s/\033\\[38;5;238m.*//')
  # Split on the escape sequences, keeping the code with the run it introduces.
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    code=${seg%%:*}
    n=$(printf '%s' "${seg#*:}" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    while [ "$n" -gt 0 ]; do
      printf '%s\n' "$code"
      n=$((n - 1))
    done
  # printf '%s\n' and not '%s': the final run carries no trailing newline of its
  # own, and `read` discards an unterminated last line -- which silently dropped
  # the red end of the gradient from the expansion.
  done < <(printf '%s\n' "$filled" |
    sed $'s/\033\\[38;5;\\([0-9]*\\)m/\\\n\\1:/g;s/\033\\[38;2;\\([0-9;]*\\)m/\\\n\\1:/g' |
    tail -n +2)
}

# The gradient cell colour, recomputed independently of the script: the same
# piecewise-linear waypoint ramp, restated here rather than imported so a change
# to the script's stops has to be made deliberately in two places.
expect_cell_rgb() { # <i> <n>
  awk -v i="$1" -v n="$2" 'BEGIN {
    ns = split("0 0.20 0.35 0.55 0.70 0.85 1", sf, " ")
    split("60 150 225 245 250 240 215", sr, " ")
    split("200 205 210 175 130  75  35", sg, " ")
    split("70   40  30  25  20  30  35", sb, " ")
    f = (n > 1) ? i / (n - 1) : 0
    for (k = 1; k < ns && sf[k + 1] < f; k++) { }
    span = sf[k + 1] - sf[k]
    t = (span > 0) ? (f - sf[k]) / span : 0
    printf "%d;%d;%d", int(sr[k] + (sr[k+1] - sr[k]) * t + 0.5),
                       int(sg[k] + (sg[k+1] - sg[k]) * t + 0.5),
                       int(sb[k] + (sb[k+1] - sb[k]) * t + 0.5)
  }'
}

# The fallback ladder, restated for the same reason.
expect_cell_cube() { # <i> <n>
  awk -v i="$1" -v n="$2" 'BEGIN {
    nc = split("40 76 112 148 184 220 214 208 202 196 160", cube, " ")
    f = (n > 1) ? i / (n - 1) : 0
    printf "%d", cube[int(f * (nc - 1) + 0.5) + 1]
  }'
}

@test "statusline progress bar gradient starts green and ends red" {
  # THE defining property of the gradient: colour is a function of POSITION, so
  # the leftmost cell is green and the rightmost cell of a FULL bar is red. A
  # solid fill, which is what this replaced, would emit one code for the whole
  # run and fail the final assertion.
  local t out codes
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"

  # Truecolor: the exact endpoint RGBs of the waypoint ramp.
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)
  codes=$(bar_codes "$out")
  [ "$(printf '%s\n' "$codes" | sed -n 1p)" = "60;200;70" ]
  [ "$(printf '%s\n' "$codes" | tail -n 1)" = "215;35;35" ]

  # Fallback: the ends of the cube ladder -- 40 is pure green, 160 dark red.
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
  codes=$(bar_codes "$out")
  [ "$(printf '%s\n' "$codes" | sed -n 1p)" -eq 40 ]
  [ "$(printf '%s\n' "$codes" | tail -n 1)" -eq 160 ]
  [ "$(printf '%s\n' "$codes" | wc -l | tr -d ' ')" -gt 2 ]
}

@test "statusline progress bar gradient is monotonic green-to-red" {
  # Walking left to right, HUE must fall monotonically from green towards red.
  # Hue rather than the raw channels because the ramp deliberately routes through
  # yellow and orange: green rises before it falls, so a per-channel assertion
  # would reject the very shape that keeps the midpoint from going muddy.
  local t out prev=999 h
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)

  for rgb in $(bar_codes "$out"); do
    h=$(awk -F';' -v s="$rgb" 'BEGIN {
      split(s, c, ";"); r = c[1]; g = c[2]; b = c[3]
      mx = (r > g ? r : g); mx = (mx > b ? mx : b)
      mn = (r < g ? r : g); mn = (mn < b ? mn : b)
      if (mx == mn) { print 0; exit }
      d = mx - mn
      if (mx == r)      { hh = (g - b) / d; while (hh < 0) hh += 6 }
      else if (mx == g) { hh = (b - r) / d + 2 }
      else              { hh = (r - g) / d + 4 }
      printf "%d", hh * 60
    }')
    # Integer hue, so allow equality; strictly it never rises.
    [ "$h" -le "$prev" ]
    prev=$h
  done
  # Both ends actually reached, or a one-colour bar would pass vacuously.
  [ "$prev" -eq 0 ]
  [ "$(bar_codes "$out" | sed -n 1p)" = "60;200;70" ]
}

@test "statusline progress bar reaches yellow by the first third" {
  # The reason the ramp has waypoints at all. A straight green->red lerp sat at
  # pure green until ~30% and only reached yellow near 50%, which read as "fine"
  # far too long. Yellow is hue 50-70 and saturated; assert the bar is there by
  # 35% of its width, and no longer green-dominant.
  local t out cells cell h
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)

  # Cell 35 of 100 is the 35% mark.
  cell=$(bar_cell_codes "$out" | sed -n 36p)
  h=$(awk -v s="$cell" 'BEGIN {
    split(s, c, ";"); r = c[1]; g = c[2]; b = c[3]
    mx = (r > g ? r : g); mx = (mx > b ? mx : b)
    mn = (r < g ? r : g); mn = (mn < b ? mn : b)
    d = mx - mn
    if (mx == r)      { hh = (g - b) / d; while (hh < 0) hh += 6 }
    else if (mx == g) { hh = (b - r) / d + 2 }
    else              { hh = (r - g) / d + 4 }
    printf "%d", hh * 60
  }')
  [ "$h" -ge 45 ]
  [ "$h" -le 70 ]
}

@test "statusline progress bar gradient has no visible banding" {
  # The other half of the complaint the waypoints fixed: the old cube ramp gave
  # SIX distinct colours across the whole bar, one hard jump every ~17%. On the
  # truecolor path every cell must differ from its neighbour by a small step --
  # assert both that there are many distinct colours and that no single step is
  # large enough to read as a band.
  local t out n_distinct max_step
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)

  n_distinct=$(bar_cell_codes "$out" | sort -u | wc -l | tr -d ' ')
  # A 100-cell bar; the old implementation managed 6.
  [ "$n_distinct" -ge 60 ]

  max_step=$(bar_cell_codes "$out" | awk -F';' '
    NR > 1 {
      d = ($1 > pr ? $1 - pr : pr - $1)
      x = ($2 > pg ? $2 - pg : pg - $2); if (x > d) d = x
      x = ($3 > pb ? $3 - pb : pb - $3); if (x > d) d = x
      if (d > m) m = d
    }
    { pr = $1; pg = $2; pb = $3 }
    END { print m + 0 }')
  # 8/255 is roughly where a step starts being visible on a solid field.
  [ "$max_step" -le 8 ]
}

@test "statusline progress bar cell colour depends on position not on fill" {
  # The consequence of keying on position: a given cell keeps its colour as the
  # bar grows past it. Render at 50% and at 90% and compare the prefix -- the
  # shorter bar's colour sequence must be a prefix of the longer one's. A
  # percentage-keyed fill would recolour every cell and fail immediately.
  local t half deep
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  # Fractions of the USABLE window (167000), not of the raw one: 83500 is half
  # and 150300 is 90%. Both must sit below the compact point, or the two bars
  # would clamp to the same full width and the length comparison below could
  # not distinguish them.
  make_transcript 83500 "$t"
  half=$(bar_codes "$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)")
  make_transcript 150300 "$t"
  deep=$(bar_codes "$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)")

  [ -n "$half" ]
  [ "$(printf '%s\n' "$half" | wc -l | tr -d ' ')" -lt "$(printf '%s\n' "$deep" | wc -l | tr -d ' ')" ]
  # The 50% sequence is the leading run of the 90% one.
  [ "$(printf '%s\n' "$deep" | head -n "$(printf '%s\n' "$half" | wc -l | tr -d ' ')")" = "$half" ]
}

@test "statusline progress bar cell colours match the position formula exactly" {
  # Pins the interpolation itself, not just its endpoints: expand the run-length
  # coalesced escapes back to one code per cell and compare every one against an
  # independently recomputed ramp. At 112 columns the bar is 100 cells, and a
  # context at the auto-compact point (167000) fills all of them. Both paths,
  # because they are different code.
  local t out n cell expected
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"

  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)
  n=0
  while IFS= read -r cell; do
    expected=$(expect_cell_rgb "$n" 100)
    [ "$cell" = "$expected" ]
    n=$((n + 1))
  done < <(bar_cell_codes "$out")
  # Every cell accounted for; a truncated expansion would otherwise pass by
  # simply checking fewer cells than exist.
  [ "$n" -eq 100 ]

  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
  n=0
  while IFS= read -r cell; do
    expected=$(expect_cell_cube "$n" 100)
    [ "$cell" -eq "$expected" ]
    n=$((n + 1))
  done < <(bar_cell_codes "$out")
  [ "$n" -eq 100 ]
}

@test "statusline progress bar is byte-identical for different directories" {
  # This is what proves the bar is not hashed on cwd+branch. The gradient is a
  # pure function of (position, width), so at the same width and the same fill
  # two different directories must produce the SAME sequence of colours -- and
  # the segment background below it must still differ, or the comparison above
  # would be passing merely because both inputs were identical.
  local t a b
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 100000 "$t"

  bar_of() {
    statusline_run 112 "$(printf '{"workspace":{"current_dir":"%s"},"transcript_path":"%s"}' "$1" "$t")" |
      sed -n 1p
  }
  a=$(bar_codes "$(bar_of /tmp)")
  b=$(bar_codes "$(bar_of /usr)")
  [ -n "$a" ]
  [ "$a" = "$b" ]

  seg_bg() {
    statusline_run 112 "$(printf '{"workspace":{"current_dir":"%s"}}' "$1")" |
      sed -n 2p | sed -n $'s/^\033\\[48;5;\\([0-9]*\\)m.*/\\1/p'
  }
  [ "$(seg_bg /tmp)" != "$(seg_bg /usr)" ]
}

@test "statusline directory segment is yellow and the task segment is yellow and visible" {
  # The task was previously read from .customTitle, which is the SESSION
  # TRANSCRIPT's shape, not the statusline payload's -- the real key is
  # session_name, so the segment rendered as nothing at all. Assert both that a
  # title is present in the output and that it, and the directory before it, are
  # painted SGR 33.
  local out stripped
  out=$(statusline_run 200 '{"workspace":{"current_dir":"/usr"},"session_name":"Refine the statusline"}' | sed -n 2p)
  # Directory: the block opens with the hashed background then yellow.
  printf '%s' "$out" | grep -q $'^\033\[48;5;[0-9]*m\033\[33m/usr'
  # Task: the separator that introduces it re-asserts yellow, and the title text
  # is actually on the line.
  printf '%s' "$out" | grep -q $'\033\[33m | Refine the statusline'
  stripped=$(printf '%s' "$out" | sed $'s/\033\\[[0-9;]*m//g')
  case "$stripped" in *"Refine the statusline"*) ;; *) return 1 ;; esac
}

@test "statusline branch is green on a clean tree and yellow on every kind of dirt" {
  # agnoster's rule: dirty is ANY uncommitted change -- unstaged, staged, or
  # untracked. Unpushed commits do not count. Each case gets its own throwaway
  # repo so one cannot mask another.
  local repo out
  branch_fg() { # <dir>
    statusline_run 200 "$(printf '{"workspace":{"current_dir":"%s"}}' "$1")" |
      sed -n 2p | sed $'s/\033/E/g' | sed -n 's/.*E\[\(3[0-9]\)m |.*/\1/p'
  }
  new_repo() { # <name>
    repo="${BATS_TEST_TMPDIR}/$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    echo tracked >"$repo/tracked.txt"
    git -C "$repo" add tracked.txt
    git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init
  }

  # Clean: green.
  new_repo clean
  [ "$(branch_fg "$repo")" = "32" ]

  # Unstaged edit to a tracked file: yellow.
  new_repo unstaged
  echo changed >"$repo/tracked.txt"
  [ "$(branch_fg "$repo")" = "33" ]

  # Staged-only edit, working tree matching the index: yellow.
  new_repo staged
  echo changed >"$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  [ "$(branch_fg "$repo")" = "33" ]

  # Untracked file ONLY, nothing tracked touched: yellow. This is the case a
  # -uno "optimisation" of `status --porcelain` would silently report as clean.
  new_repo untracked
  echo new >"$repo/brand-new.txt"
  [ "$(branch_fg "$repo")" = "33" ]

  # An unpushed COMMIT is not dirt: still green. Without this the test would
  # pass for a check that merely compared against a remote.
  new_repo unpushed
  echo more >>"$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m second
  [ "$(branch_fg "$repo")" = "32" ]
}

@test "every PALETTE background clears the contrast threshold against yellow and green" {
  # KNOWN FAILING PROPERTY, deliberately not enforced yet.
  #
  # The foregrounds are FIXED yellow and green, so legibility has to come from
  # the palette. Seven of the current entries do not clear 3.0 against them:
  #
  #   144 (1.18)  201 (1.64)  95 (2.87)  255 (1.61)
  #   228 (1.77)  208 (1.26)  130 (2.46)
  #
  # THE RATIOS ABOVE WERE ONCE WRONG, AND SO WAS THE PALETTE THEY JUSTIFIED.
  # Earlier revisions of this test scored against the XTERM DEFAULT yellow
  # rgb(205,205,0) and green rgb(0,205,0). The statusline emits SGR 33 and 32,
  # which resolve through the TERMINAL THEME, not through xterm's defaults --
  # ghostty's "deep" theme renders them #d9bd26 and #1cd915. Scoring the wrong
  # colours produced a wrong ranking, which is how a palette with seven
  # illegible entries passed a contrast filter at selection time. The constants
  # below are now the theme's real values.
  #
  # This makes the test THEME-SPECIFIC, which is the honest trade: the palette
  # protects legibility in the terminal the user actually runs, and a different
  # theme would need different constants. Anything reading SGR 33/32 as fixed
  # RGB is making the same mistake this comment exists to prevent.
  #
  # The palette is now settled, so this gates at the real bar: 3.0, WCAG AA for
  # large text, which is the right threshold for a single row of terminal
  # glyphs. It sat at a vacuous 1.0 while the palette was in flux -- 1.0 is the
  # floor for identical colours, so nothing could ever fail it.
  #
  # The current floor is 3.68 (code 124), so there is real headroom above the
  # bar; a code added without scoring it against these two foregrounds will
  # trip this rather than reach the terminal.
  local script codes
  script="${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"
  codes=$(sed -n 's/^SESSION_COLOR_PALETTE=(\(.*\))$/\1/p' "$script")
  [ -n "$codes" ]
  # A non-trivial palette, or "all entries pass" is close to vacuous. This is a
  # floor on the concept, not on the current size -- shrink the palette freely,
  # but a handful of colours cannot tell checkouts apart at all.
  [ "$(printf '%s' "$codes" | wc -w | tr -d ' ')" -ge 6 ]

  printf '%s' "$codes" | awk '
    function chan(v) { return (v <= 0.03928) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
    function lum(r, g, b) { return 0.2126 * chan(r/255) + 0.7152 * chan(g/255) + 0.0722 * chan(b/255) }
    function ratio(a, b) { return (a > b) ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
    BEGIN {
      split("0 95 135 175 215 255", lv, " ")
      # SGR 33 and 32 as the ghostty "deep" theme actually renders them --
      # NOT the xterm defaults. See the comment above this test.
      # (No apostrophes in here: this awk program is single-quoted, and one
      # would terminate the quote and silently truncate the rest of the file.
      # bats then reports FEWER TESTS rather than an error -- it went from 66
      # to 45 and still exited 0.)
      ly = lum(217, 189, 38)  # #d9bd26, SGR 33
      lg = lum(28, 217, 21)   # #1cd915, SGR 32
      bad = 0
    }
    {
      for (i = 1; i <= NF; i++) {
        c = $i + 0
        # 0-15 are the system colours: they resolve through the theme like the
        # foregrounds do, so they are NOT on the 6x6x6 cube and mapping them
        # with lv[] would score a colour the terminal never draws. Only 0 is in
        # the palette, and ghostty "deep" renders it #000000.
        if (c < 16) { r = g = b = 0 }
        else if (c >= 232) { r = g = b = 8 + (c - 232) * 10 }
        else {
          n = c - 16
          r = lv[int(n/36)+1]; g = lv[int((n%36)/6)+1]; b = lv[(n%6)+1]
        }
        l = lum(r, g, b)
        cy = ratio(ly, l); cgr = ratio(lg, l)
        m = (cy < cgr) ? cy : cgr
        if (m < 3.0) { printf "code %d fails: %.2f\n", c, m; bad = 1 }
      }
    }
    END { exit bad }'
}

@test "adjacent PALETTE entries are visually distinct" {
  # Assignment walks the palette in order, so neighbours are handed to sessions
  # opened close together and must be the LEAST alike pairs. The current
  # ordering holds a minimum of dE 82.6 between neighbours; sorting these same
  # codes numerically collapses that, putting the 21/24 blue-ramp pair adjacent.
  #
  # The list is cyclic -- the 12th assignment wraps to the first -- so the
  # last->first pair is checked too.
  local script codes
  script="${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"
  codes=$(sed -n 's/^SESSION_COLOR_PALETTE=(\(.*\))$/\1/p' "$script")
  [ -n "$codes" ]

  printf '%s\n' "$codes" | awk '
    function srgb(u) { u /= 255; return (u <= 0.04045) ? u/12.92 : ((u+0.055)/1.055)^2.4 }
    function f(t) { return (t > 216/24389) ? t^(1/3) : (841/108)*t + 4/29 }
    # sRGB -> CIE Lab (D65), then plain Euclidean distance (CIE76): enough to
    # answer "are these obviously different colours".
    function lab(c,   n, r, g, b, X, Y, Z, fx, fy, fz) {
      # 0-15 are system colours, not cube entries -- see the contrast test.
      if (c < 16) { r = g = b = 0 }
      else if (c >= 232) { r = g = b = 8 + (c - 232) * 10 }
      else {
        n = c - 16
        r = lv[int(n/36)+1]; g = lv[int((n%36)/6)+1]; b = lv[(n%6)+1]
      }
      r = srgb(r); g = srgb(g); b = srgb(b)
      X = r*0.4124564 + g*0.3575761 + b*0.1804375
      Y = r*0.2126729 + g*0.7151522 + b*0.0721750
      Z = r*0.0193339 + g*0.1191920 + b*0.9503041
      fx = f(X/0.95047); fy = f(Y); fz = f(Z/1.08883)
      L[c] = 116*fy - 16; A[c] = 500*(fx-fy); B[c] = 200*(fy-fz)
    }
    BEGIN { split("0 95 135 175 215 255", lv, " "); worst = 9999 }
    {
      for (i = 1; i <= NF; i++) { c[i] = $i + 0; lab(c[i]) }
      n = NF
      for (i = 1; i <= n; i++) {
        j = (i % n) + 1
        d = sqrt((L[c[i]]-L[c[j]])^2 + (A[c[i]]-A[c[j]])^2 + (B[c[i]]-B[c[j]])^2)
        if (d < worst) { worst = d; wi = c[i]; wj = c[j] }
      }
      if (worst < 80) { printf "%d beside %d is only dE %.1f\n", wi, wj, worst; exit 1 }
    }'
}

@test "statusline segment background is closed before the metrics that follow" {
  # An unreset 48;5;N bleeds the block colour through the pad and the whole
  # right-hand group. Asserting merely that no background is open at END of line
  # is vacuous -- the right-hand group ends with its own RESET, which closes the
  # bled background at the last possible moment. So assert on the CELLS: walk the
  # line tracking whether a background is active, and collect every printable
  # character painted with one. That set must be exactly the block's own text.
  local out painted
  out=$(statusline_run 160 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"customTitle":"demo"}')
  painted=$(printf '%s\n' "$out" | sed -n 2p | awk '
    {
      bg = 0; s = $0; acc = ""
      while (length(s) > 0) {
        if (match(s, /^\033\[[0-9;]*m/)) {
          code = substr(s, 3, RLENGTH - 3)
          if (code ~ /^48;5;/) bg = 1
          if (code == "0") bg = 0
          s = substr(s, RLENGTH + 1)
        } else {
          if (bg) acc = acc substr(s, 1, 1)
          s = substr(s, 2)
        }
      }
      print acc
    }')
  # Exactly the dir + task block. A bled background would additionally paint the
  # pad spaces and the entire model/ctx/tok/time/cpu group.
  [ "$painted" = "/tmp | demo" ]
}

@test "statusline omits absent branch and task without a stray coloured gap" {
  # /usr is not a git checkout and the payload carries no customTitle, so the
  # block must end immediately after the directory. A separator rendered for an
  # absent segment would leave painted cells past it.
  local out stripped
  out=$(statusline_run 160 '{"workspace":{"current_dir":"/usr"}}' | sed -n 2p)
  # Between the opening SGR pair and the FIRST reset there must be exactly
  # "/usr". Cut at the first reset rather than matching to end of line: sed is
  # greedy and would otherwise run to the LAST reset, swallowing the whole
  # right-hand group and turning this into a vacuous comparison.
  stripped=$(printf '%s' "$out" |
    sed $'s/\033\\[0m.*//' |
    sed $'s/^\033\\[48;5;[0-9]*m\033\\[3[0-9]m//')
  [ "$stripped" = "/usr" ]
}

# --- session colours -------------------------------------------------------
#
# The statusline's dir/branch/task background is RECORDED, not derived: a
# directory+branch is assigned a colour once and keeps it. These tests pin the
# assignment rule, the retention policy, and -- most importantly -- that nothing
# in the library can ever write to stderr, which would make Claude Code discard
# the entire statusline.

colors_env() {
  export STATUSLINE_CONF=/nonexistent
  export STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/colors.db"
  # shellcheck source=/dev/null
  . "${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"
}

# Age every row by N days, to exercise retention without waiting.
age_rows() { # <days>
  sqlite3 "$STATUSLINE_COLOR_DB" \
    "UPDATE colors SET created_at = strftime('%s','now') - $1 * 86400;"
}

@test "session_color_assign hands out the palette in order, then wraps" {
  colors_env

  # Derived from the palette, never restated: editing SESSION_COLOR_PALETTE --
  # its contents OR its length -- must not require touching this test. Assign
  # one more key than there are colours, so the wrap is exercised whatever the
  # size.
  local n want got="" i
  n=${#SESSION_COLOR_PALETTE[@]}
  [ "$n" -ge 2 ]

  for i in $(seq 1 $((n + 2))); do
    got="$got $(session_color_assign "/dir$i" main)"
  done

  # The first n are the palette in its declared order; the rest wrap to the
  # front. Ordering is load-bearing -- adjacent entries are the most visually
  # distinct pairs, so sessions opened close together look least alike.
  want=$(printf ' %s' "${SESSION_COLOR_PALETTE[@]}" \
    "${SESSION_COLOR_PALETTE[0]}" "${SESSION_COLOR_PALETTE[1]}")
  [ "$got" = "$want" ]
}

@test "an assigned colour never changes on re-read" {
  colors_env

  local first
  first=$(session_color_assign /stable main)

  # Assign 20 further keys, exhausting the palette and forcing duplicates.
  local i
  for i in $(seq 1 20); do session_color_assign "/other$i" main >/dev/null; done

  [ "$(session_color_assign /stable main)" = "$first" ]
}

@test "duplicates spread evenly instead of piling onto one colour" {
  colors_env

  # Assign strictly between one and two full passes of the palette, whatever
  # its size, so the expected shape is always "every colour used, none used
  # more than twice" -- no count in this test is tied to a particular palette.
  local n keys i
  n=${#SESSION_COLOR_PALETTE[@]}
  keys=$((n + n / 2))
  for i in $(seq 1 "$keys"); do session_color_assign "/dir$i" main >/dev/null; done

  # A rule that ignored use counts would stack the overflow onto whichever code
  # sorted first, leaving one code at $((keys - n + 1)) and others unused.
  local max
  max=$(sqlite3 "$STATUSLINE_COLOR_DB" \
    'SELECT MAX(n) FROM (SELECT COUNT(*) n FROM colors GROUP BY code);')
  [ "$max" -eq 2 ]
  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(DISTINCT code) FROM colors;')" -eq "$n" ]
}

@test "branch is part of the key, and switching back restores the colour" {
  colors_env

  local master feature back
  master=$(session_color_assign /repo master)
  feature=$(session_color_assign /repo feature)
  back=$(session_color_assign /repo master)

  [ "$master" != "$feature" ]
  [ "$master" = "$back" ]
}

@test "the key separator stops directory and branch running together" {
  colors_env

  # These two keys concatenate to the same string -- "/a/bc" -- so without a
  # separator between directory and branch they collapse into one row and two
  # different checkouts share a colour.
  #
  # Note the pair has to be chosen with care: "/a/b" + "c" versus "/a" + "bc"
  # does NOT collide, because the slash in the first path keeps them distinct.
  session_color_assign /a/b c >/dev/null
  session_color_assign /a/bc "" >/dev/null

  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 2 ]
}

@test "session_color reads without assigning" {
  colors_env

  # The read-only entry point exists so an interactive shell can ask for a
  # colour without claiming one just by opening a terminal.
  local out
  out=$(session_color /never/seen main)
  [ -z "$out" ]
  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;' 2>/dev/null || echo 0)" -eq 0 ]

  session_color_assign /seen main >/dev/null
  [ -n "$(session_color /seen main)" ]
}

@test "assigning prunes rows older than the retention period" {
  colors_env

  session_color_assign /old main >/dev/null
  age_rows 40

  session_color_assign /new main >/dev/null

  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" "SELECT COUNT(*) FROM colors WHERE key LIKE '/old%';")" -eq 0 ]
  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" "SELECT COUNT(*) FROM colors WHERE key LIKE '/new%';")" -eq 1 ]
}

@test "reading does not prune, however old the row is" {
  colors_env

  session_color_assign /old main >/dev/null
  age_rows 400

  # Cleanup is deliberately confined to the assign path: the read path runs on
  # every refresh of every session and must stay a single SELECT.
  session_color /old main >/dev/null

  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 1 ]
}

@test "retention of 0 disables pruning entirely" {
  colors_env
  STATUSLINE_COLOR_RETENTION_DAYS=0

  session_color_assign /old main >/dev/null
  age_rows 4000
  session_color_assign /new main >/dev/null

  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 2 ]
}

@test "a non-numeric retention setting falls back to the default" {
  export STATUSLINE_CONF="${BATS_TEST_TMPDIR}/bad.conf"
  echo 'STATUSLINE_COLOR_RETENTION_DAYS=thirty' >"$STATUSLINE_CONF"
  export STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/colors.db"
  # shellcheck source=/dev/null
  . "${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"

  # A typo in the config must not reach the DELETE as a malformed interval.
  [ "$STATUSLINE_COLOR_RETENTION_DAYS" -eq 30 ]

  session_color_assign /x main >/dev/null
  age_rows 40
  session_color_assign /y main >/dev/null
  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" "SELECT COUNT(*) FROM colors WHERE key LIKE '/x%';")" -eq 0 ]
}

@test "concurrent assigns of one key produce one row and no stderr" {
  colors_env

  # SQLite allows one writer at a time. Two sessions racing to claim the same
  # new key must settle to a single row, via INSERT OR IGNORE.
  local err="${BATS_TEST_TMPDIR}/err"
  : >"$err"

  local i
  for i in $(seq 1 24); do
    (session_color_assign /shared main >/dev/null 2>>"$err") &
  done
  wait

  [ "$(wc -c <"$err" | tr -d ' ')" -eq 0 ]
  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 1 ]
}

@test "a losing racer's assign never overwrites the winner's colour" {
  colors_env

  # THE regression test for INSERT OR IGNORE. Two sessions can both miss the
  # fast-path SELECT and both go on to INSERT; the second to commit must be
  # discarded, not applied. INSERT OR REPLACE applies it -- and because the
  # winner's row makes its own code the most-used, the loser recomputes a
  # DIFFERENT code and repaints a live session mid-work, the exact failure this
  # feature exists to prevent (measured: 18 becomes 144).
  #
  # Reproduced by stubbing the fast-path lookup to return nothing for one call,
  # which is what the loser observes: it read before the winner committed. The
  # assign then runs its real INSERT against a database that already holds the
  # row. Driving the library rather than restating its SQL is deliberate -- a
  # hand-written INSERT in the test would keep saying OR IGNORE no matter what
  # the library says.
  session_color_assign /a main >/dev/null
  local first
  first=$(session_color /a main)
  [ -n "$first" ]

  # Same idiom the suite uses to get at setup.sh's shadowed run() (see the top
  # of this file): copy the function body onto a second name.
  eval "_sc_real_sql() $(declare -f _sc_sql | tail -n +2)"
  _sc_sql() {
    case "$1" in
      # The loser's fast-path SELECT: it read before the winner committed, so
      # it sees no row and falls through to the INSERT.
      "SELECT code FROM colors WHERE key="*) return 0 ;;
      *) _sc_real_sql "$@" ;;
    esac
  }
  session_color_assign /a main >/dev/null
  eval "_sc_sql() $(declare -f _sc_real_sql | tail -n +2)"

  [ "$(session_color /a main)" = "$first" ]
  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 1 ]
}

@test "concurrent assigns of distinct keys all get written" {
  colors_env

  # THE regression test for PRAGMA busy_timeout, and the reason it asserts on
  # rows rather than on stderr: without the pragma sqlite3 abandons a locked
  # write, and here it does so SILENTLY -- measured at 13 of 24 rows surviving
  # with zero bytes of stderr. A stderr-only assertion passes vacuously.
  #
  # (Silent loss is the milder half. The same abandoned write can instead print
  # "database is locked", and Claude Code discards the WHOLE statusline on a
  # single stderr byte.)
  local err="${BATS_TEST_TMPDIR}/err"
  : >"$err"

  local i
  for i in $(seq 1 24); do
    (session_color_assign "/dir$i" main >/dev/null 2>>"$err") &
  done
  wait

  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 24 ]
  [ "$(wc -c <"$err" | tr -d ' ')" -eq 0 ]
}

@test "the library is silent when sqlite3 is unavailable" {
  colors_env

  # Degrade to "no colour", never to a broken statusline: the caller falls back
  # to hashing when it gets an empty answer.
  # A non-zero return is expected and fine -- the caller treats an empty answer
  # as "fall back to hashing" -- so || true keeps bats from aborting on it.
  local err="${BATS_TEST_TMPDIR}/err" out
  out=$(PATH=/nonexistent session_color_assign /x main 2>"$err") || true

  [ -z "$out" ]
  [ "$(wc -c <"$err" | tr -d ' ')" -eq 0 ]
}

@test "the statusline falls back to hashing when the library is missing" {
  # SESSION_COLORS_LIB points nowhere, so the DB path is skipped entirely and
  # the segment must still be painted.
  local out
  out=$(printf '%s' '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"}}' |
    env -i PATH=/usr/bin:/bin HOME="$HOME" COLUMNS=160 \
      SESSION_COLORS_LIB=/nonexistent \
      "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh" 2>/dev/null)

  [ -n "$out" ]
  [[ "$out" == *$'\033[48;5;'* ]]
}

@test "the palette is defined in exactly one place" {
  # The statusline used to keep its own copy for the hash fallback, and the two
  # lists could drift into handing out colours the contrast audit never covered.
  # It now sources the library and reads SESSION_COLOR_PALETTE, so changing the
  # palette is a one-line edit in one file. This test pins that: a
  # re-introduced second list is the regression.
  local script
  script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"

  # No bare PALETTE=(...) assignment -- only the guarded default, which is
  # SESSION_COLOR_PALETTE and is allowed to differ (it is a broken-install
  # backstop, not a copy).
  #
  # Assert on a COUNT, not with `! grep`: a bare negated pipeline does not fail
  # a bats test the way a plain command does, so `! grep -q ...` here passes
  # whatever the file contains. Mutation-checked -- re-adding PALETTE=(1 2 3)
  # slipped straight through the negated form.
  local dupes
  dupes=$(grep -cE '^PALETTE=\(' "$script" || true)
  [ "$dupes" -eq 0 ]

  # And the statusline must actually INDEX the library's array to pick a
  # colour. Matching a bare "SESSION_COLOR_PALETTE[" is too loose -- the
  # emptiness guard ${#SESSION_COLOR_PALETTE[@]} satisfies it, so the check
  # survived renaming the only real use. Require the subscripted read.
  local uses
  uses=$(grep -cE 'SEG_BG=\$\{SESSION_COLOR_PALETTE\[' "$script" || true)
  [ "$uses" -ge 1 ]
}

@test "the statusline falls back to a usable palette when the library is unreadable" {
  # The guarded default only fires when sourcing failed. Every code in it must
  # still clear the contrast bar -- a broken install should degrade to fewer
  # colours, never to illegible ones.
  local codes
  codes=$(sed -n 's/^  SESSION_COLOR_PALETTE=(\(.*\))$/\1/p' \
    "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh")
  [ -n "$codes" ]

  printf '%s' "$codes" | awk '
    function chan(v) { return (v <= 0.03928) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
    function lum(r, g, b) { return 0.2126 * chan(r/255) + 0.7152 * chan(g/255) + 0.0722 * chan(b/255) }
    function ratio(a, b) { return (a > b) ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
    BEGIN {
      split("0 95 135 175 215 255", lv, " ")
      ly = lum(217, 189, 38)
      lg = lum(28, 217, 21)
      bad = 0
    }
    {
      for (i = 1; i <= NF; i++) {
        c = $i + 0
        if (c < 16) { r = g = b = 0 }
        else if (c >= 232) { r = g = b = 8 + (c - 232) * 10 }
        else {
          n = c - 16
          r = lv[int(n/36)+1]; g = lv[int((n%36)/6)+1]; b = lv[(n%6)+1]
        }
        l = lum(r, g, b)
        cy = ratio(ly, l); cgr = ratio(lg, l)
        m = (cy < cgr) ? cy : cgr
        if (m < 3.0) { printf "fallback code %d fails: %.2f\n", c, m; bad = 1 }
      }
    }
    END { exit bad }'
}

@test "the test suite never writes to the real colour database" {
  # statusline_run used to pass the developer HOME straight through, so every
  # rendering test assigned a colour in the LIVE database -- 129 rows of dead
  # bats temp paths had accumulated, including codes from mutation runs that
  # fail the contrast bar. Assignments are permanent by design, so nothing
  # cleaned them up.
  #
  # Assert on the fixture rather than on the live file: a test that diffed the
  # real database would itself depend on the developer machine, and would pass
  # vacuously on a machine that has none.
  local fixture
  fixture=$(sed -n '/^statusline_run() {/,/^}/p' "${BATS_TEST_DIRNAME}/setup.bats")

  # Both redirects are needed. STATUSLINE_COLOR_DB alone is not enough: the
  # tracked conf assigns that variable unconditionally, so a sourced conf puts
  # the writes straight back into the live database.
  local db conf
  db=$(printf '%s' "$fixture" | grep -c 'STATUSLINE_COLOR_DB=' || true)
  conf=$(printf '%s' "$fixture" | grep -c 'STATUSLINE_CONF=' || true)
  [ "$db" -ge 1 ]
  [ "$conf" -ge 1 ]

  # And the redirect must point inside the test tmpdir, not at a fixed path.
  printf '%s' "$fixture" | grep -q 'STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}'
}

@test "the tracked statusline.conf parses and defines both settings" {
  local conf="${BATS_TEST_DIRNAME}/../claude/statusline.conf"

  bash -n "$conf"
  grep -q '^STATUSLINE_COLOR_RETENTION_DAYS=' "$conf"
  grep -q '^STATUSLINE_COLOR_DB=' "$conf"
}

@test "the tracked context-window.conf parses and defines both constants" {
  local conf="${BATS_TEST_DIRNAME}/../claude/context-window.conf"

  bash -n "$conf"
  grep -q '^CTX_MAX=' "$conf"
  grep -q '^CTX_RESERVE=' "$conf"
}

@test "context-window.conf values override the statusline's inline defaults" {
  # The whole point of de-hardcoding: retuning the window must not require
  # touching the script. A 100000 window with a 50000 reserve leaves 50000
  # usable, so 25000 tokens is exactly half the gauge -- a number that is NOT
  # 50% under the built-in 200000/33000 defaults (it would be ~15%), so this
  # cannot pass unless the conf was actually read.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 25000 "$t"

  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/context-window.conf"
  cat >"$CLAUDE_CONTEXT_CONF" <<'EOF'
CTX_MAX=100000
CTX_RESERVE=50000
EOF

  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 50 ]
}

@test "a missing or unreadable context-window.conf still renders a statusline" {
  # The "absence must be a working state" rule. Neither an absent file nor one
  # that cannot be read may break the gauge: both fall through to the inline
  # defaults, where 83500 tokens is half of the 167000 usable window.
  local t out
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 83500 "$t"
  local payload
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")

  # Absent.
  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/does-not-exist.conf"
  [ "$(ctx_pct "$payload")" -eq 50 ]

  # Present but unreadable. chmod 000 is not honoured for root, which would make
  # this pass vacuously, so the mode is verified to actually deny a read first.
  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/unreadable.conf"
  echo 'CTX_MAX=1' >"$CLAUDE_CONTEXT_CONF"
  chmod 000 "$CLAUDE_CONTEXT_CONF"
  if [ ! -r "$CLAUDE_CONTEXT_CONF" ]; then
    [ "$(ctx_pct "$payload")" -eq 50 ]
  fi

  # And the line must be whole, not merely non-empty: two rendered lines.
  out=$(statusline_run 160 "$payload")
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "a non-numeric context-window setting falls back to the default" {
  # Mirrors the retention-days guard in session-colors.sh: a typo must not reach
  # the arithmetic. CTX_MAX=lots would make $((CTX_MAX - CTX_RESERVE)) either
  # error to stderr -- which discards the whole statusline -- or silently
  # evaluate the bare word as 0.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 83500 "$t"

  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/bad-context.conf"
  cat >"$CLAUDE_CONTEXT_CONF" <<'EOF'
CTX_MAX=lots
CTX_RESERVE=-5
EOF

  # Both fall back, so this is the default 167000-usable scale again.
  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 50 ]
}

@test "a reserve at or above the window reads 0 rather than dividing by zero" {
  # A misconfiguration, but it must degrade to a harmless reading. awk would
  # otherwise print "inf" or "nan" straight into the ctx: segment, and a
  # non-numeric CTX_PCT then fails the `-ge 80` colour test with a stderr byte,
  # which makes Claude Code discard the entire statusline.
  local t out
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 50000 "$t"

  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/inverted.conf"
  cat >"$CLAUDE_CONTEXT_CONF" <<'EOF'
CTX_MAX=100000
CTX_RESERVE=100000
EOF

  local payload
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")
  [ "$(ctx_pct "$payload")" -eq 0 ]
  out=$(statusline_run 160 "$payload")
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 2 ]
}
