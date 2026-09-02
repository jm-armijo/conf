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
  mkdir -p "$REPO_DIR/claude/scripts" "$REPO_DIR/claude/hooks"
  echo "# global instructions" >"$REPO_DIR/claude/CLAUDE.md"
  echo '{"model":"opus"}' >"$REPO_DIR/claude/settings.json"
  echo "#!/bin/bash" >"$REPO_DIR/claude/scripts/statusline.sh"
  echo "#!/bin/bash" >"$REPO_DIR/claude/hooks/block-inefficient-bash.sh"

  local skill
  for skill in bug-fixing clean-code ui-separation; do
    mkdir -p "$REPO_DIR/claude/skills/$skill"
    echo "# $skill" >"$REPO_DIR/claude/skills/$skill/SKILL.md"
  done
}

@test "setup_claude symlinks the four tracked files into ~/.claude" {
  claude_env

  bats_run setup_claude
  [ "$status" -eq 0 ]

  local f
  for f in CLAUDE.md settings.json scripts/statusline.sh hooks/block-inefficient-bash.sh; do
    [ -L "$HOME/.claude/$f" ]
    [ "$(readlink "$HOME/.claude/$f")" = "$REPO_DIR/claude/$f" ]
  done
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
  for skill in bug-fixing clean-code ui-separation; do
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
  for skill in bug-fixing clean-code ui-separation; do
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
      env -i PATH=/usr/bin:/bin HOME="$HOME" "$script" >/dev/null 2>"$err"
    [ "$(wc -c <"$err" | tr -d ' ')" -eq 0 ]
  done
}

@test "statusline exits zero and emits output on a degenerate payload" {
  local script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"
  local out
  out="${BATS_TEST_TMPDIR}/stdout"
  printf '%s' '{}' |
    env -i PATH=/usr/bin:/bin HOME="$HOME" "$script" >"$out" 2>/dev/null
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
    env -i PATH=/usr/bin:/bin HOME="$HOME" "$script" 2>/dev/null |
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

statusline_run() { # <columns> <payload>
  printf '%s' "$2" |
    env -i PATH=/usr/bin:/bin HOME="$HOME" COLUMNS="$1" \
      "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh" 2>/dev/null
}

# Visible width of one line: SGR sequences stripped, then counted in CHARACTERS.
# `wc -m` and not awk's length(), which counts BYTES in this locale -- the block
# and branch glyphs are 3 bytes each and would be billed as 3 columns.
line_width() {
  printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

# A transcript yielding an exact token total, so CTX_PCT is a known value
# rather than whatever the live session happens to be using.
make_transcript() { # <tokens> <path>
  printf '{"isSidechain":false,"message":{"usage":{"input_tokens":%d,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}\n' \
    "$1" >"$2"
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
  # a full context window.
  local t out fill
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  for pair in "0 0" "20000 10" "100000 50" "200000 100"; do
    set -- $pair
    make_transcript "$1" "$t"
    out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
    # Everything before the track colour (grey 238) is the filled run.
    fill=$(printf '%s' "$out" | sed $'s/\033\\[38;5;238m.*//' |
      sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    [ "$fill" -eq "$2" ]
  done
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
bar_codes() { # <line>
  printf '%s' "$1" | sed $'s/\033\\[38;5;238m.*//' |
    grep -o $'\033\\[38;5;[0-9]*m' | sed $'s/\033\\[38;5;//;s/m$//'
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
    sed $'s/\033\\[38;5;\\([0-9]*\\)m/\\\n\\1:/g' | tail -n +2)
}

# The gradient cell colour, recomputed independently of the script: fraction
# i/(n-1) over the 6x6x6 cube, blue pinned at 0, red up and green down.
expect_cell() { # <i> <n>
  awk -v i="$1" -v n="$2" 'BEGIN {
    f = (n > 1) ? i / (n - 1) : 0
    printf "%d", 16 + 36 * int(f * 5 + 0.5) + 6 * int((1 - f) * 5 + 0.5)
  }'
}

@test "statusline progress bar gradient starts green and ends red" {
  # THE defining property of the gradient: colour is a function of POSITION, so
  # the leftmost cell is green and the rightmost cell of a FULL bar is red --
  # 46 is pure green (r=0,g=5) and 196 pure red (r=5,g=0) on the 6x6x6 cube.
  # A solid fill, which is what this replaced, would emit one code for the whole
  # run and fail the second assertion.
  local t out codes
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 200000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
  codes=$(bar_codes "$out")
  [ "$(printf '%s\n' "$codes" | sed -n 1p)" -eq 46 ]
  [ "$(printf '%s\n' "$codes" | tail -n 1)" -eq 196 ]
  # More than one colour, or it is still a solid fill wearing a gradient's name.
  [ "$(printf '%s\n' "$codes" | wc -l | tr -d ' ')" -gt 2 ]
}

@test "statusline progress bar gradient is monotonic green-to-red" {
  # Walking left to right the red channel must never decrease and the green
  # channel must never increase. This is what makes it read as one continuous
  # ramp rather than an arbitrary sequence of colours.
  local t out code prev_r=-1 prev_g=6 r g
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 200000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
  for code in $(bar_codes "$out"); do
    # Invert code = 16 + 36r + 6g + b back to its cube channels.
    r=$(( (code - 16) / 36 ))
    g=$(( ((code - 16) % 36) / 6 ))
    [ "$r" -ge "$prev_r" ]
    [ "$g" -le "$prev_g" ]
    prev_r=$r
    prev_g=$g
  done
  # Both ends actually reached, or a one-colour bar would pass vacuously.
  [ "$prev_r" -eq 5 ]
  [ "$prev_g" -eq 0 ]
}

@test "statusline progress bar cell colour depends on position not on fill" {
  # The consequence of keying on position: a given cell keeps its colour as the
  # bar grows past it. Render at 50% and at 90% and compare the prefix -- the
  # shorter bar's colour sequence must be a prefix of the longer one's. A
  # percentage-keyed fill would recolour every cell and fail immediately.
  local t half deep
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  make_transcript 100000 "$t"
  half=$(bar_codes "$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)")
  make_transcript 180000 "$t"
  deep=$(bar_codes "$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)")

  [ -n "$half" ]
  [ "$(printf '%s\n' "$half" | wc -l | tr -d ' ')" -lt "$(printf '%s\n' "$deep" | wc -l | tr -d ' ')" ]
  # The 50% sequence is the leading run of the 90% one.
  [ "$(printf '%s\n' "$deep" | head -n "$(printf '%s\n' "$half" | wc -l | tr -d ' ')")" = "$half" ]
}

@test "statusline progress bar cell colours match the position formula exactly" {
  # Pins the interpolation itself, not just its endpoints: expand the run-length
  # coalesced escapes back to one code per cell and compare every one against an
  # independently computed i/(n-1) ramp. At 112 columns the bar is 100 cells and
  # a full context fills all of them.
  local t out n=0 cell expected
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 200000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)

  while IFS= read -r cell; do
    expected=$(expect_cell "$n" 100)
    [ "$cell" -eq "$expected" ]
    n=$((n + 1))
  done < <(bar_cell_codes "$out")
  # Every cell accounted for; a truncated expansion would otherwise pass by
  # simply checking fewer cells than exist.
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
  # The dir/branch/task foregrounds are now FIXED yellow and green rather than a
  # foreground computed per background, so legibility has to come from the
  # palette instead. Recompute the WCAG contrast ratio here, independently of the
  # script, and require the WORSE of the two to clear 3.0 for every entry.
  local script codes
  script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"
  codes=$(sed -n '/^PALETTE=(/,/^)/p' "$script" | sed '1d;$d' | tr -s ' \n' ' ')
  [ -n "$codes" ]
  # A non-trivial palette, or "all entries pass" is close to vacuous.
  [ "$(printf '%s' "$codes" | wc -w | tr -d ' ')" -ge 12 ]

  printf '%s' "$codes" | awk '
    function chan(v) { return (v <= 0.03928) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
    function lum(r, g, b) { return 0.2126 * chan(r/255) + 0.7152 * chan(g/255) + 0.0722 * chan(b/255) }
    function ratio(a, b) { return (a > b) ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
    BEGIN {
      split("0 95 135 175 215 255", lv, " ")
      ly = lum(205, 205, 0)   # xterm yellow, SGR 33
      lg = lum(0, 205, 0)     # xterm green,  SGR 32
      bad = 0
    }
    {
      for (i = 1; i <= NF; i++) {
        c = $i + 0
        if (c >= 232) { r = g = b = 8 + (c - 232) * 10 }
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

@test "PALETTE contains no reds" {
  # Preserved from before the contrast filter: the block must never be
  # confusable with an error state. No 1, 9, 52, 88, or anything in 124-196.
  local script code
  script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"
  for code in $(sed -n '/^PALETTE=(/,/^)/p' "$script" | sed '1d;$d'); do
    [ "$code" -ne 1 ]
    [ "$code" -ne 9 ]
    [ "$code" -ne 52 ]
    [ "$code" -ne 88 ]
    [ "$code" -lt 124 ] || [ "$code" -gt 196 ]
  done
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
