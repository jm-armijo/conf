#!/usr/bin/env bats

setup() {
  # setup.sh's own run() shadows bats' helper; tests must call bats_run, never run.
  eval "bats_run() $(declare -f run | tail -n +2)"

  source "${BATS_TEST_DIRNAME}/../setup.sh"

  SRC="${BATS_TEST_TMPDIR}/src"
  DEST="${BATS_TEST_TMPDIR}/dest"
  echo "source content" >"$SRC"
}

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
  [ "$(backup_count)" = "0" ]
  [ "$(readlink "$DEST")" = "$SRC" ]
}

@test "link backs up a pre-existing real file and replaces it with the symlink" {
  echo "pre-existing user config" >"$DEST"
  [ ! -L "$DEST" ]

  bats_run link "$SRC" "$DEST"
  [ "$status" -eq 0 ]

  [ -L "$DEST" ]
  [ "$(readlink "$DEST")" = "$SRC" ]

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

# PATH holds ONLY the stubs a test asks for, so "not stubbed" means absent to
# `command -v` rather than the developer's real binary.
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

stub_starship() {
  cat >"$STUB_BIN/starship" <<'STUB'
#!/bin/bash
[[ "$1" == "--version" ]] && echo "starship 1.2.3"
exit 0
STUB
  chmod +x "$STUB_BIN/starship"
}

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
  [ ! -e "$BREW_LOG" ]
  [[ "$output" == ok:* ]]
}

@test "setup_starship fails with skip: when brew is missing" {
  starship_env
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
  grep -qx 'install starship' "$BREW_LOG"
  [[ "$output" != *"starship: installed"* ]]
}

@test "setup_starship_config symlinks starship.toml into ~/.config" {
  starship_env

  bats_run setup_starship_config
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/starship.toml" ]
  [ "$(readlink "$HOME/.config/starship.toml")" = "$REPO_DIR/starship/starship.toml" ]
  [ "$(cat "$HOME/.config/starship.toml")" = "# starship config" ]
}

@test "setup_starship_config does not require starship to be installed" {
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
  echo "#!/bin/bash" >"$REPO_DIR/claude/hooks/plan-artifacts-on-exit.sh"

  # A stand-in for the 3.4MB bundle: the tests must never copy or read the real one.
  mkdir -p "$REPO_DIR/claude/vendor"
  echo "// not the real bundle" >"$REPO_DIR/claude/vendor/mermaid.min.BOTS-DO-NOT-READ.js"

  local skill
  for skill in bug-fixing clean-code development plan-writing ui-separation; do
    mkdir -p "$REPO_DIR/claude/skills/$skill"
    echo "# $skill" >"$REPO_DIR/claude/skills/$skill/SKILL.md"
  done
}

@test "setup_claude symlinks the tracked files into ~/.claude" {
  claude_env

  bats_run setup_claude
  [ "$status" -eq 0 ]

  local f
  for f in settings.json statusline.conf context-window.conf \
    scripts/statusline.sh lib/session-colors.sh \
    hooks/block-inefficient-bash.sh hooks/plan-artifacts-on-exit.sh; do
    [ -L "$HOME/.claude/$f" ]
    [ "$(readlink "$HOME/.claude/$f")" = "$REPO_DIR/claude/$f" ]
  done

  # The only renamed link: a claude/CLAUDE.md here would be read as this repo's
  # project instructions.
  [ -L "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$REPO_DIR/claude/global-instructions.md" ]
  [ "$(cat "$HOME/.claude/CLAUDE.md")" = "# global instructions" ]
}

@test "setup_claude is idempotent" {
  claude_env
  setup_claude

  bats_run setup_claude
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude/settings.json")" = "$REPO_DIR/claude/settings.json" ]
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
  local backup
  backup="$(echo "$HOME"/.claude/settings.json.backup.*)"
  [ "$(cat "$backup")" = '{"model":"sonnet"}' ]
}

@test "setup_claude_skills symlinks each tracked skill directory" {
  claude_env

  bats_run setup_claude_skills
  [ "$status" -eq 0 ]

  local skill
  for skill in bug-fixing clean-code development plan-writing ui-separation; do
    [ -L "$HOME/.claude/skills/$skill" ]
    [ "$(readlink "$HOME/.claude/skills/$skill")" = "$REPO_DIR/claude/skills/$skill" ]
    [ "$(cat "$HOME/.claude/skills/$skill/SKILL.md")" = "# $skill" ]
  done
}

@test "setup_claude_skills leaves plugin-written state in ~/.claude/skills alone" {
  claude_env
  # Reproduces the ruby-lsp plugin writing into ~/.claude/skills: a directory
  # symlink would land this state inside the repo as untracked junk.
  mkdir -p "$HOME/.claude/skills/.ruby-lsp"
  echo "gem 'ruby-lsp'" >"$HOME/.claude/skills/.ruby-lsp/Gemfile"

  bats_run setup_claude_skills
  [ "$status" -eq 0 ]

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
  # One bad skill must not abort the loop: record-and-continue, like run().
  [ -L "$HOME/.claude/skills/bug-fixing" ]
  [ -L "$HOME/.claude/skills/ui-separation" ]
}

@test "setup_claude_vendor symlinks the vendor directory itself" {
  claude_env

  bats_run setup_claude_vendor
  [ "$status" -eq 0 ]

  [ -L "$HOME/.claude/vendor" ]
  [ "$(readlink "$HOME/.claude/vendor")" = "$REPO_DIR/claude/vendor" ]
  [ -f "$HOME/.claude/vendor/mermaid.min.BOTS-DO-NOT-READ.js" ]
}

@test "setup_claude_vendor is idempotent" {
  claude_env
  setup_claude_vendor

  bats_run setup_claude_vendor
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude/vendor")" = "$REPO_DIR/claude/vendor" ]
  local backups=("$HOME"/.claude/vendor.backup.*)
  [ ! -e "${backups[0]}" ]
}

@test "setup_claude_vendor fails when the vendor directory is missing" {
  claude_env
  rm -r "$REPO_DIR/claude/vendor"

  bats_run setup_claude_vendor
  [ "$status" -ne 0 ]
  [[ "$output" == *skip:* ]]
  [ ! -e "$HOME/.claude/vendor" ]
}

@test "the vendored mermaid bundle is tracked and carries its do-not-read note" {
  local vendor="${BATS_TEST_DIRNAME}/../claude/vendor"
  # Existence only -- never read the bundle itself, it is ~750,000 tokens.
  [ -f "$vendor/mermaid.min.BOTS-DO-NOT-READ.js" ]
  [ -f "$vendor/!READ-ME-FIRST.md" ]
  grep -q "DO-NOT-READ" "$vendor/!READ-ME-FIRST.md"
}

@test "UI_TEMPLATE loads mermaid from the vendored bundle, not a CDN or ESM import" {
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/UI_TEMPLATE.html"
  # An ESM import fails from file:// and breaks every diagram SILENTLY.
  grep -q 'script src="{{VENDOR_DIR}}/mermaid.min.BOTS-DO-NOT-READ.js"' "$tpl"
  bats_run grep -q 'cdn.jsdelivr.net' "$tpl"
  [ "$status" -ne 0 ]
  bats_run grep -q 'type="module"' "$tpl"
  [ "$status" -ne 0 ]
}

@test "UI_TEMPLATE substitutes the vendor directory and hardcodes no username" {
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/UI_TEMPLATE.html"
  grep -q '{{VENDOR_DIR}}' "$tpl"
  bats_run grep -q '/Users/' "$tpl"
  [ "$status" -ne 0 ]
  grep -q 'mermaid.min.BOTS-DO-NOT-READ.js' "$tpl"
}

@test "plan-writing tells the model to substitute the vendor directory" {
  local skill="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/SKILL.md"
  # An unsubstituted {{VENDOR_DIR}} renders diagrams as raw text with no error.
  grep -q '{{VENDOR_DIR}}' "$skill"
  grep -q '\.claude/vendor' "$skill"
}

@test "plan-writing reads as plan-generation instructions, not a rendering step" {
  local skill="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/SKILL.md"
  bats_run grep -q 'what the plan is written to' "$skill"
  [ "$status" -ne 0 ]
  grep -qi 'not after' "$skill"
  grep -q 'chat output is one line' "$skill"
}

@test "plan-writing does not restate the template's section list" {
  local skill="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/SKILL.md"
  # The template is the single definition of a plan's shape; a second copy here
  # would silently disagree.
  bats_run grep -qi 'Risks & open questions' "$skill"
  [ "$status" -ne 0 ]
  bats_run grep -qi 'Data flow' "$skill"
  [ "$status" -ne 0 ]
}

@test "UI_TEMPLATE's do-not-read warning sits immediately above the script tag" {
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/UI_TEMPLATE.html"
  local script_line prev
  script_line="$(grep -n 'script src="{{VENDOR_DIR}}' "$tpl" | cut -d: -f1)"
  [ -n "$script_line" ]
  prev="$(sed -n "$((script_line - 1))p" "$tpl")"
  # Adjacency is the property that rots silently: assert the comment CLOSES on
  # the line directly above the tag, not merely that both strings exist.
  [[ "$prev" == *"-->"* ]]
  grep -q 'AGENT / LLM: do NOT read' "$tpl"
}

@test "UI_TEMPLATE shows the task split with a branch name for each task" {
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/UI_TEMPLATE.html"
  grep -q '<h2>Tasks</h2>' "$tpl"
  grep -q '<th>Branch</th>' "$tpl"
  grep -q 'feat/retry-policy' "$tpl"
}

@test "plan-writing requires the plan to state tasks and branch names" {
  local skill="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/SKILL.md"
  grep -qi 'branch name' "$skill"
  grep -q 'development' "$skill"
  bats_run grep -q 'plan-execution' "$skill"
  [ "$status" -ne 0 ]
}

@test "the development skill triggers on doing work, not on executing a plan" {
  local skill="${BATS_TEST_DIRNAME}/../claude/skills/development/SKILL.md"
  [ -f "$skill" ]
  [ ! -e "${BATS_TEST_DIRNAME}/../claude/skills/plan-execution" ]
  local desc
  desc="$(grep -m1 '^description:' "$skill")"
  # The description is the whole trigger surface: naming the phase is the bug
  # the rename fixed, so a plan-execution-only description must fail here.
  [[ "$desc" == *"bug"* ]]
  [[ "$desc" != *"Execute an approved"* ]]
  grep -qi 'whether or not a plan' "$skill"
}

@test "the development skill owns the contract the template no longer carries" {
  local skill="${BATS_TEST_DIRNAME}/../claude/skills/development/SKILL.md"
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/TODO_TEMPLATE.md"
  grep -q -- '--no-verify' "$skill"
  grep -qi 'never allowed' "$skill"
  bats_run grep -q -- '--no-verify' "$tpl"
  [ "$status" -ne 0 ]
  grep -qi 'baseline' "$skill"
  grep -q 'PLAN.html' "$skill"
}

@test "TODO_TEMPLATE names the five steps in order, numbered, one per line" {
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/TODO_TEMPLATE.md"
  local want=("1. writing tests" "2. coding" "3. bot review" "4. draft pr" "5. author review")
  local got
  got="$(grep -o '^- \[ \] [0-9]\. .*' "$tpl" | head -5 | sed 's/^- \[ \] //')"
  local i=0 line
  while IFS= read -r line; do
    [ "$line" = "${want[$i]}" ]
    i=$((i + 1))
  done <<<"$got"
  [ "$i" -eq 5 ]
}

@test "TODO_TEMPLATE derives status from checkboxes and declares none" {
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/TODO_TEMPLATE.md"
  # The patterns target a *declared* status only (a `**Status:**` line or a table
  # column) -- the bare word appears legitimately in the header comment.
  # Negations are bats_run-wrapped, never `! grep`, which never fails a test.
  bats_run grep -qi '^| # | ' "$tpl"
  [ "$status" -ne 0 ]
  bats_run grep -qiE '^[|*[:space:]]*\*?\*?Status\*?\*?[[:space:]]*[:|]' "$tpl"
  [ "$status" -ne 0 ]
  bats_run grep -q '^---$' "$tpl"
  [ "$status" -ne 0 ]
  grep -q '^## - \[ \] Task 1: ' "$tpl"
  local headings tasks
  headings="$(grep -c '^## - \[ \] Task ' "$tpl")"
  tasks="$(grep -c '^## - \[' "$tpl")"
  [ "$headings" -eq "$tasks" ]
  [ "$headings" -ge 2 ]
}

@test "TODO_TEMPLATE's uniform shape parses without edge cases" {
  local tpl="${BATS_TEST_DIRNAME}/../claude/skills/plan-writing/assets/TODO_TEMPLATE.md"
  local n
  n="$(grep -c '^## - \[[ x]\] Task ' "$tpl")"
  [ "$n" -ge 2 ]
  local steps
  steps="$(grep -c '^- \[[ x]\] [0-9]\+\. ' "$tpl")"
  [ "$steps" -eq $((n * 5)) ]
  local branches
  branches="$(grep -c '^\*\*Branch:\*\* ' "$tpl")"
  [ "$branches" -eq "$n" ]
}

@test "the tracked starship.toml exists and parses" {
  local toml="${BATS_TEST_DIRNAME}/../starship/starship.toml"
  [ -f "$toml" ]
  if ! command -v starship >/dev/null 2>&1; then
    skip "starship not installed"
  fi

  # DO NOT reduce this to asserting starship's exit status: it exits 0 on a
  # broken config and stderr is the only signal.
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
  # Renaming a script without editing settings.json leaves Claude Code silently
  # invoking nothing.
  grep -qE '(~|/Users/[^"]*)/\.claude/scripts/statusline\.sh' "$settings"
  grep -qE '(~|/Users/[^"]*)/\.claude/hooks/block-inefficient-bash\.sh' "$settings"
  grep -qE '(~|/Users/[^"]*)/\.claude/hooks/plan-artifacts-on-exit\.sh' "$settings"
  [ -x "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh" ]
  [ -x "${BATS_TEST_DIRNAME}/../claude/hooks/block-inefficient-bash.sh" ]
  [ -x "${BATS_TEST_DIRNAME}/../claude/hooks/plan-artifacts-on-exit.sh" ]
}

plan_hook() {
  printf '{"cwd":"%s","tool_name":"ExitPlanMode"}' "$1" |
    "${BATS_TEST_DIRNAME}/../claude/hooks/plan-artifacts-on-exit.sh"
}

@test "plan gate blocks ExitPlanMode when the artifacts are missing" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q .

  bats_run plan_hook "$repo"
  # exit 2 is the documented "block and feed stderr back to the model" code;
  # anything else silently lets the plan through unrendered.
  [ "$status" -eq 2 ]
  [[ "$output" == *"plan-writing"* ]]
}

@test "plan gate allows the retry once both artifacts exist" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q .
  touch "$repo/PLAN.html" "$repo/TODO.md"

  bats_run plan_hook "$repo"
  # Without this branch the hook re-blocks its own retry and plan mode is inescapable.
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "plan gate still blocks when only one of the two artifacts exists" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q .
  touch "$repo/PLAN.html"

  bats_run plan_hook "$repo"
  [ "$status" -eq 2 ]
}

@test "plan gate ignores directories that are not git repos" {
  local scratch="${BATS_TEST_TMPDIR}/scratch"
  mkdir -p "$scratch"

  bats_run plan_hook "$scratch"
  [ "$status" -eq 0 ]
}

@test "plan gate names the browser review in what it tells the model" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q .

  bats_run plan_hook "$repo"
  [ "$status" -eq 2 ]
  # A message that merely demands two files gets obeyed as paperwork on the way
  # out of plan mode. Pin the intent, not just the block.
  [[ "$output" == *"browser"* ]]
  [[ "$output" == *"before asking for approval"* ]]
}

@test "plan gate tells the model the chat output is one line, not a summary" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q .

  bats_run plan_hook "$repo"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ONE LINE"* ]]
  [[ "$output" == *"No summary"* ]]
}

@test "plan gate presents the skill as how a plan is written, not a formatter" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q .

  bats_run plan_hook "$repo"
  [ "$status" -eq 2 ]
  [[ "$output" == *"while you"* ]]
  [[ "$output" == *"template"* ]]
  [[ "$output" != *"formats and splits"* ]]
}

@test "plan gate fails open on malformed input" {
  bats_run bash -c "printf 'not json' | '${BATS_TEST_DIRNAME}/../claude/hooks/plan-artifacts-on-exit.sh'"
  # A hook that errors on an unexpected payload would wedge plan mode entirely.
  [ "$status" -eq 0 ]
}

@test "every skill setup_claude_skills links has a SKILL.md" {
  local skill
  for skill in bug-fixing clean-code development plan-writing ui-separation; do
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
  # Sourcing oh-my-zsh assigns $PROMPT, so an init above it is silently overwritten.
  [ "$init" -gt "$omz" ]
  grep -q 'command -v starship' "$zshrc"
}

@test "zshrc selects no oh-my-zsh theme and no longer sources spaceship" {
  local zshrc="${BATS_TEST_DIRNAME}/../zsh/zshrc"
  # ZSH_THEME must be empty: a non-empty theme would race starship for $PROMPT.
  grep -qx 'ZSH_THEME=""' "$zshrc"
  bats_run grep -qi 'spaceship' "$zshrc"
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TEST_DIRNAME}/../zsh/spaceship.zsh" ]
  [ -f "${BATS_TEST_DIRNAME}/../zsh/agnoster.zsh-theme" ]
}

@test "statusline writes nothing to stderr" {
  # THE contract: Claude Code discards the entire statusline on a single byte of
  # stderr, with no error shown anywhere. env -i is load-bearing -- an inherited
  # PATH contains /sbin and hides the failure.
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
  # A length-based bar loop once sliced the final 3-byte glyph mid-sequence,
  # because awk's length() counts bytes here.
  local script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"
  printf '%s' '{"workspace":{"current_dir":"/tmp"}}' |
    env -i PATH=/usr/bin:/bin HOME="$HOME" \
        STATUSLINE_CONF=/nonexistent \
        STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/direct.db" "$script" 2>/dev/null |
    iconv -f UTF-8 -t UTF-8 >/dev/null
}

# COLORTERM is UNSET under env -i unless $3 supplies it: that is the 256-colour
# fallback path, "truecolor" the 24-bit one. All three redirects are load-bearing.
statusline_run() { # <columns> <payload> [colorterm]
  printf '%s' "$2" |
    env -i PATH=/usr/bin:/bin HOME="$HOME" COLUMNS="$1" ${3:+COLORTERM="$3"} \
      STATUSLINE_CONF=/nonexistent \
      CLAUDE_CONTEXT_CONF="${CLAUDE_CONTEXT_CONF:-/nonexistent}" \
      STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/statusline-run.db" \
      "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh" 2>/dev/null
}

# Counted in CHARACTERS with `wc -m` -- awk's length() bills each 3-byte glyph as 3.
line_width() {
  printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

make_transcript() { # <tokens> <path>
  printf '{"isSidechain":false,"message":{"usage":{"input_tokens":%d,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}\n' \
    "$1" >"$2"
}

# The PRIMARY source. used_percentage is seeded WRONG on purpose: it divides by the
# raw window, and the script must not read it.
context_window_payload() { # <total_input_tokens> <context_window_size>
  printf '{"workspace":{"current_dir":"/tmp"},"context_window":{"total_input_tokens":%d,"context_window_size":%d,"used_percentage":99}}' \
    "$1" "$2"
}

@test "statusline renders two lines and aligns metrics to the bar when content fits" {
  local out
  out=$(statusline_run 160 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"}}')
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(line_width "$(printf '%s\n' "$out" | sed -n 1p)")" -eq 148 ]
  [ "$(line_width "$(printf '%s\n' "$out" | sed -n 2p)")" -eq 148 ]
}

@test "statusline wraps to three lines when the metrics overflow the width" {
  local out
  out=$(statusline_run 90 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"customTitle":"a-fairly-long-session-title-x"}')
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "statusline right-aligns the wrapped right-hand group to the bar's edge" {
  local out bar right
  out=$(statusline_run 90 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"customTitle":"a-fairly-long-session-title-x"}')
  bar=$(line_width "$(printf '%s\n' "$out" | sed -n 1p)")
  right=$(line_width "$(printf '%s\n' "$out" | sed -n 3p)")
  [ "$bar" -eq 78 ]
  [ "$right" -eq "$bar" ]
  printf '%s\n' "$out" | sed -n 3p | sed $'s/\033\\[[0-9;]*m//g' | grep -q '^  *[^ ]'
}

@test "statusline never emits a negative pad when the right group alone overflows" {
  # printf reads a NEGATIVE "%*s" width as a left-justify flag and emits nothing,
  # so WRAP_PAD is clamped at 0.
  local out third
  out=$(statusline_run 40 '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"customTitle":"a-fairly-long-session-title-x"}')
  third=$(printf '%s\n' "$out" | sed -n 3p)
  [ -n "$third" ]
  printf '%s' "$third" | sed $'s/\033\\[[0-9;]*m//g' | grep -qv '^ '
}

@test "statusline progress bar fill tracks context percentage" {
  # At 112 columns the bar is 100 cells, so the filled run equals the percentage.
  # 100% is 167000 (the usable window), not 200000.
  local t out fill
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  for pair in "0 0" "16700 10" "83500 50" "167000 100"; do
    set -- $pair
    make_transcript "$1" "$t"
    out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
    fill=$(printf '%s' "$out" | sed $'s/\033\\[38;5;238m.*//' |
      sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    [ "$fill" -eq "$2" ]
  done
}

ctx_pct() { # <payload> [columns]
  statusline_run "${2:-200}" "$1" |
    sed $'s/\033\\[[0-9;]*m//g' |
    sed -n $'s/.*ctx:\\([0-9]*\\)%.*/\\1/p'
}

@test "statusline context percentage is scaled to the auto-compact point" {
  # Asserted on the printed number rather than the bar, so a fill-rounding change
  # cannot mask it.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  make_transcript 167000 "$t"
  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 100 ]

  make_transcript 83500 "$t"
  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 50 ]
}

@test "statusline reads the context_window payload in preference to the transcript" {
  # Seeded with DIFFERENT totals so the winner is identifiable: the payload's
  # 83500 is 50%, the transcript's 167000 would be 100%.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"

  local payload
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s","context_window":{"total_input_tokens":83500,"context_window_size":200000,"used_percentage":99}}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]
}

@test "statusline falls back to the transcript when context_window is absent" {
  # Older CLIs emit no context_window, and a current one emits null at the very
  # start of a session.
  local t payload
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 83500 "$t"

  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]

  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s","context_window":null}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]

  # Null MEMBERS: a `// empty` guarding only the object would render 0% here.
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s","context_window":{"total_input_tokens":null,"context_window_size":null}}' "$t")
  [ "$(ctx_pct "$payload")" -eq 50 ]
}

@test "statusline scales the context_window payload to the compact point" {
  [ "$(ctx_pct "$(context_window_payload 167000 200000)")" -eq 100 ]
  [ "$(ctx_pct "$(context_window_payload 83500 200000)")" -eq 50 ]

  [ "$(ctx_pct "$(context_window_payload 0 200000)")" -eq 0 ]
}

@test "statusline clamps a larger context_window_size down to CTX_MAX" {
  # CTX_MAX is a CEILING (autoCompactWindow can cap the effective window), so a
  # reported 1000000 must be clamped: believing it would render 17, not 100.
  [ "$(ctx_pct "$(context_window_payload 167000 1000000)")" -eq 100 ]

  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/extended.conf"
  cat >"$CLAUDE_CONTEXT_CONF" <<'EOF'
CTX_MAX=1000000
CTX_RESERVE=33000
EOF
  [ "$(ctx_pct "$(context_window_payload 967000 1000000)")" -eq 100 ]
  [ "$(ctx_pct "$(context_window_payload 167000 1000000)")" -eq 17 ]
}

@test "statusline clamps a smaller context_window_size to itself, not to CTX_MAX" {
  # The clamp is a MINIMUM of the two, not an override: 33500 of a 100000-token
  # window is half its 67000 usable span.
  [ "$(ctx_pct "$(context_window_payload 33500 100000)")" -eq 50 ]
}

@test "statusline context percentage clamps at 100 past the compact point" {
  # 200000 is a genuine overshoot of the 167000 point -- unclamped it computes to
  # 120, whereas the compact point itself would pass with no clamp.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  make_transcript 200000 "$t"
  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 100 ]

  # The bar line is isolated BEFORE the escapes are stripped: with a full bar
  # there is no track colour left to cut at, so the metrics line would fold in.
  local out fill
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
  fill=$(printf '%s' "$out" | sed $'s/\033\\[38;5;238m.*//' |
    sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
  [ "$fill" -eq 100 ]
}

# One code per RUN, not per cell.
bar_codes() { # <line>
  printf '%s' "$1" | sed $'s/\033\\[38;5;238m.*//' |
    grep -o $'\033\\[38;[25];[0-9;]*m' |
    sed $'s/\033\\[38;5;//;s/\033\\[38;2;//;s/m$//'
}

# One code per CELL: expands the run-length coalesced escapes. `wc -m`, never
# awk's length().
bar_cell_codes() { # <line>
  local filled seg code n
  filled=$(printf '%s' "$1" | sed $'s/\033\\[38;5;238m.*//')
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    code=${seg%%:*}
    n=$(printf '%s' "${seg#*:}" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
    while [ "$n" -gt 0 ]; do
      printf '%s\n' "$code"
      n=$((n - 1))
    done
  # printf '%s\n' and not '%s': `read` discards an unterminated last line, which
  # silently dropped the red end of the gradient.
  done < <(printf '%s\n' "$filled" |
    sed $'s/\033\\[38;5;\\([0-9]*\\)m/\\\n\\1:/g;s/\033\\[38;2;\\([0-9;]*\\)m/\\\n\\1:/g' |
    tail -n +2)
}

# Restated rather than imported, so changing the script's stops has to be done
# deliberately in two places.
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

expect_cell_cube() { # <i> <n>
  awk -v i="$1" -v n="$2" 'BEGIN {
    nc = split("40 76 112 148 184 220 214 208 202 196 160", cube, " ")
    f = (n > 1) ? i / (n - 1) : 0
    printf "%d", cube[int(f * (nc - 1) + 0.5) + 1]
  }'
}

@test "statusline progress bar gradient starts green and ends red" {
  local t out codes
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"

  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)
  codes=$(bar_codes "$out")
  [ "$(printf '%s\n' "$codes" | sed -n 1p)" = "60;200;70" ]
  [ "$(printf '%s\n' "$codes" | tail -n 1)" = "215;35;35" ]

  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)
  codes=$(bar_codes "$out")
  [ "$(printf '%s\n' "$codes" | sed -n 1p)" -eq 40 ]
  [ "$(printf '%s\n' "$codes" | tail -n 1)" -eq 160 ]
  [ "$(printf '%s\n' "$codes" | wc -l | tr -d ' ')" -gt 2 ]
}

@test "statusline progress bar gradient is monotonic green-to-red" {
  # HUE, not the raw channels: the ramp routes through yellow and orange, so
  # green rises before it falls and a per-channel assertion would reject it.
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
    [ "$h" -le "$prev" ]
    prev=$h
  done
  # Both ends actually reached, or a one-colour bar would pass vacuously.
  [ "$prev" -eq 0 ]
  [ "$(bar_codes "$out" | sed -n 1p)" = "60;200;70" ]
}

@test "statusline progress bar reaches yellow by the first third" {
  # Why the ramp has waypoints: a straight green->red lerp only reached yellow
  # near 50%, reading as "fine" far too long.
  local t out cells cell h
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)

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
  local t out n_distinct max_step
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 167000 "$t"
  out=$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" truecolor | sed -n 1p)

  n_distinct=$(bar_cell_codes "$out" | sort -u | wc -l | tr -d ' ')
  # The old cube ramp managed 6 across the whole 100-cell bar.
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
  local t half deep
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"

  # Both must sit below the compact point (167000), or the two bars clamp to the
  # same width and cannot be distinguished.
  make_transcript 83500 "$t"
  half=$(bar_codes "$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)")
  make_transcript 150300 "$t"
  deep=$(bar_codes "$(statusline_run 112 "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")" | sed -n 1p)")

  [ -n "$half" ]
  [ "$(printf '%s\n' "$half" | wc -l | tr -d ' ')" -lt "$(printf '%s\n' "$deep" | wc -l | tr -d ' ')" ]
  [ "$(printf '%s\n' "$deep" | head -n "$(printf '%s\n' "$half" | wc -l | tr -d ' ')")" = "$half" ]
}

@test "statusline progress bar cell colours match the position formula exactly" {
  # Both paths, because they are different code.
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
  # Every cell accounted for; a truncated expansion would check fewer than exist.
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
  # The segment background below must still DIFFER, or the comparison would pass
  # on identical inputs.
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
  # The task was once read from .customTitle -- the session transcript's shape,
  # not the payload's -- so the segment rendered as nothing at all.
  local out stripped
  out=$(statusline_run 200 '{"workspace":{"current_dir":"/usr"},"session_name":"Refine the statusline"}' | sed -n 2p)
  printf '%s' "$out" | grep -q $'^\033\[48;5;[0-9]*m\033\[33m/usr'
  printf '%s' "$out" | grep -q $'\033\[33m | Refine the statusline'
  stripped=$(printf '%s' "$out" | sed $'s/\033\\[[0-9;]*m//g')
  case "$stripped" in *"Refine the statusline"*) ;; *) return 1 ;; esac
}

@test "statusline branch is green on a clean tree and yellow on every kind of dirt" {
  # agnoster's rule: dirty is ANY uncommitted change, but an unpushed commit is
  # not dirt.
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

  new_repo clean
  [ "$(branch_fg "$repo")" = "32" ]

  new_repo unstaged
  echo changed >"$repo/tracked.txt"
  [ "$(branch_fg "$repo")" = "33" ]

  new_repo staged
  echo changed >"$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  [ "$(branch_fg "$repo")" = "33" ]

  # Untracked ONLY: the case a `-uno` optimisation would report as clean.
  new_repo untracked
  echo new >"$repo/brand-new.txt"
  [ "$(branch_fg "$repo")" = "33" ]

  # Without this the test would pass for a check that merely compared against a
  # remote.
  new_repo unpushed
  echo more >>"$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m second
  [ "$(branch_fg "$repo")" = "32" ]
}

@test "every PALETTE background clears the contrast threshold against yellow and green" {
  # The foregrounds are the TERMINAL THEME's yellow and green, NOT xterm's
  # defaults -- scoring xterm's is how seven illegible entries once passed a
  # contrast filter. Bar is 3.0 (WCAG AA, large text).
  local script codes
  script="${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"
  codes=$(sed -n 's/^SESSION_COLOR_PALETTE=(\(.*\))$/\1/p' "$script")
  [ -n "$codes" ]
  # A non-trivial palette, or "all entries pass" is close to vacuous. A floor on
  # the concept, not on the current size.
  [ "$(printf '%s' "$codes" | wc -w | tr -d ' ')" -ge 6 ]

  printf '%s' "$codes" | awk '
    function chan(v) { return (v <= 0.03928) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
    function lum(r, g, b) { return 0.2126 * chan(r/255) + 0.7152 * chan(g/255) + 0.0722 * chan(b/255) }
    function ratio(a, b) { return (a > b) ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
    BEGIN {
      split("0 95 135 175 215 255", lv, " ")
      # No apostrophes in this single-quoted awk program -- one truncates the
      # file and bats then reports FEWER TESTS rather than an error.
      ly = lum(217, 189, 38)  # #d9bd26, SGR 33
      lg = lum(28, 217, 21)   # #1cd915, SGR 32
      bad = 0
    }
    {
      for (i = 1; i <= NF; i++) {
        c = $i + 0
        # 0-15 resolve through the theme, so they are NOT on the 6x6x6 cube;
        # mapping them with lv[] would score a colour the terminal never draws.
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
  # Assignment walks the palette in order, so neighbours go to sessions opened
  # close together and must be the LEAST alike pairs. The list is cyclic, so the
  # last->first pair is checked too.
  local script codes
  script="${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"
  codes=$(sed -n 's/^SESSION_COLOR_PALETTE=(\(.*\))$/\1/p' "$script")
  [ -n "$codes" ]

  printf '%s\n' "$codes" | awk '
    function srgb(u) { u /= 255; return (u <= 0.04045) ? u/12.92 : ((u+0.055)/1.055)^2.4 }
    function f(t) { return (t > 216/24389) ? t^(1/3) : (841/108)*t + 4/29 }
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
  # Asserting that no background is open at END of line is vacuous -- the right
  # group ends with its own reset. So walk the line and collect every PAINTED
  # character instead.
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
  # A bled background would also paint the pad spaces and the right-hand group.
  [ "$painted" = "/tmp | demo" ]
}

@test "statusline omits absent branch and task without a stray coloured gap" {
  local out stripped
  out=$(statusline_run 160 '{"workspace":{"current_dir":"/usr"}}' | sed -n 2p)
  # Cut at the FIRST reset: sed is greedy and would otherwise run to the last
  # one, swallowing the right-hand group and making this vacuous.
  stripped=$(printf '%s' "$out" |
    sed $'s/\033\\[0m.*//' |
    sed $'s/^\033\\[48;5;[0-9]*m\033\\[3[0-9]m//')
  [ "$stripped" = "/usr" ]
}

colors_env() {
  export STATUSLINE_CONF=/nonexistent
  export STATUSLINE_COLOR_DB="${BATS_TEST_TMPDIR}/colors.db"
  # shellcheck source=/dev/null
  . "${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"
}

age_rows() { # <days>
  sqlite3 "$STATUSLINE_COLOR_DB" \
    "UPDATE colors SET created_at = strftime('%s','now') - $1 * 86400;"
}

@test "session_color_assign hands out the palette in order, then wraps" {
  colors_env

  # Derived from the palette, never restated: editing SESSION_COLOR_PALETTE --
  # contents OR length -- must not require touching this test.
  local n want got="" i
  n=${#SESSION_COLOR_PALETTE[@]}
  [ "$n" -ge 2 ]

  for i in $(seq 1 $((n + 2))); do
    got="$got $(session_color_assign "/dir$i" main)"
  done

  want=$(printf ' %s' "${SESSION_COLOR_PALETTE[@]}" \
    "${SESSION_COLOR_PALETTE[0]}" "${SESSION_COLOR_PALETTE[1]}")
  [ "$got" = "$want" ]
}

@test "an assigned colour never changes on re-read" {
  colors_env

  local first
  first=$(session_color_assign /stable main)

  local i
  for i in $(seq 1 20); do session_color_assign "/other$i" main >/dev/null; done

  [ "$(session_color_assign /stable main)" = "$first" ]
}

@test "duplicates spread evenly instead of piling onto one colour" {
  colors_env

  # Between one and two full passes, whatever the palette's size, so the shape
  # is always "every colour used, none more than twice".
  local n keys i
  n=${#SESSION_COLOR_PALETTE[@]}
  keys=$((n + n / 2))
  for i in $(seq 1 "$keys"); do session_color_assign "/dir$i" main >/dev/null; done

  # A rule ignoring use counts would stack the overflow onto one code.
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

  # These two keys concatenate to the same string, so without a separator they
  # collapse into one row.
  session_color_assign /a/b c >/dev/null
  session_color_assign /a/bc "" >/dev/null

  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 2 ]
}

@test "session_color reads without assigning" {
  colors_env

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

  # Cleanup is confined to the assign path: the read path runs on every refresh
  # of every session and must stay a single SELECT.
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

  # A typo must not reach the DELETE as a malformed interval.
  [ "$STATUSLINE_COLOR_RETENTION_DAYS" -eq 30 ]

  session_color_assign /x main >/dev/null
  age_rows 40
  session_color_assign /y main >/dev/null
  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" "SELECT COUNT(*) FROM colors WHERE key LIKE '/x%';")" -eq 0 ]
}

@test "concurrent assigns of one key produce one row and no stderr" {
  colors_env

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

  # THE regression test for INSERT OR IGNORE: OR REPLACE lets the loser repaint
  # a live session mid-work. Reproduced by stubbing the fast-path lookup to
  # return nothing, which is what the loser observes.
  session_color_assign /a main >/dev/null
  local first
  first=$(session_color /a main)
  [ -n "$first" ]

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

  # THE regression test for PRAGMA busy_timeout. It asserts on ROWS, not on
  # stderr: without the pragma sqlite3 abandons a locked write SILENTLY (13 of
  # 24 rows, zero stderr), so a stderr-only assertion passes vacuously.
  local err="${BATS_TEST_TMPDIR}/err"
  : >"$err"

  local i pids=()
  for i in $(seq 1 24); do
    (session_color_assign "/dir$i" main >/dev/null 2>>"$err") &
    pids+=("$!")
  done

  local pid failed=0
  for pid in "${pids[@]}"; do
    wait "$pid" || failed=$((failed + 1))
  done
  [ "$failed" -eq 0 ]

  [ "$(sqlite3 "$STATUSLINE_COLOR_DB" 'SELECT COUNT(*) FROM colors;')" -eq 24 ]
  [ "$(wc -c <"$err" | tr -d ' ')" -eq 0 ]
}

@test "the library is silent when sqlite3 is unavailable" {
  colors_env

  # A non-zero return is expected -- the caller falls back to hashing -- hence
  # the || true.
  local err="${BATS_TEST_TMPDIR}/err" out
  out=$(PATH=/nonexistent session_color_assign /x main 2>"$err") || true

  [ -z "$out" ]
  [ "$(wc -c <"$err" | tr -d ' ')" -eq 0 ]
}

@test "the statusline falls back to hashing when the library is missing" {
  local out
  out=$(printf '%s' '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"}}' |
    env -i PATH=/usr/bin:/bin HOME="$HOME" COLUMNS=160 \
      SESSION_COLORS_LIB=/nonexistent \
      "${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh" 2>/dev/null)

  [ -n "$out" ]
  [[ "$out" == *$'\033[48;5;'* ]]
}

@test "the palette is defined in exactly one place" {
  local script
  script="${BATS_TEST_DIRNAME}/../claude/scripts/statusline.sh"

  # No bare PALETTE=(...) -- only the guarded default, which is allowed to
  # differ. Assert on a COUNT, not `! grep`: mutation-checked, re-adding
  # PALETTE=(1 2 3) slipped straight through the negated form.
  local dupes
  dupes=$(grep -cE '^PALETTE=\(' "$script" || true)
  [ "$dupes" -eq 0 ]

  # Require the SUBSCRIPTED read: a bare "SESSION_COLOR_PALETTE[" is satisfied
  # by the ${#...[@]} emptiness guard and survived renaming the only real use.
  local uses
  uses=$(grep -cE 'SEG_BG=\$\{SESSION_COLOR_PALETTE\[' "$script" || true)
  [ "$uses" -ge 1 ]
}

@test "the statusline falls back to a usable palette when the library is unreadable" {
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
  # Assert on the FIXTURE, not the live file: diffing the real database would
  # pass vacuously on a machine that has none.
  local fixture
  fixture=$(sed -n '/^statusline_run() {/,/^}/p' "${BATS_TEST_DIRNAME}/setup.bats")

  # Both redirects are needed: the tracked conf assigns STATUSLINE_COLOR_DB
  # unconditionally, so a sourced conf undoes the DB redirect.
  local db conf
  db=$(printf '%s' "$fixture" | grep -c 'STATUSLINE_COLOR_DB=' || true)
  conf=$(printf '%s' "$fixture" | grep -c 'STATUSLINE_CONF=' || true)
  [ "$db" -ge 1 ]
  [ "$conf" -ge 1 ]

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
  # 25000 of a 100000/50000 conf is exactly half, and is NOT 50% under the
  # built-in defaults (~15%), so this cannot pass unless the conf was read.
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
  local t out
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 83500 "$t"
  local payload
  payload=$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")

  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/does-not-exist.conf"
  [ "$(ctx_pct "$payload")" -eq 50 ]

  # chmod 000 is not honoured for root, so verify it actually denies a read
  # first -- otherwise this passes vacuously.
  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/unreadable.conf"
  echo 'CTX_MAX=1' >"$CLAUDE_CONTEXT_CONF"
  chmod 000 "$CLAUDE_CONTEXT_CONF"
  if [ ! -r "$CLAUDE_CONTEXT_CONF" ]; then
    [ "$(ctx_pct "$payload")" -eq 50 ]
  fi

  # The line must be whole, not merely non-empty.
  out=$(statusline_run 160 "$payload")
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "a non-numeric context-window setting falls back to the default" {
  # CTX_MAX=lots would make $((CTX_MAX - CTX_RESERVE)) either error to stderr,
  # discarding the whole statusline, or silently evaluate the word as 0.
  local t
  t="${BATS_TEST_TMPDIR}/transcript.jsonl"
  make_transcript 83500 "$t"

  export CLAUDE_CONTEXT_CONF="${BATS_TEST_TMPDIR}/bad-context.conf"
  cat >"$CLAUDE_CONTEXT_CONF" <<'EOF'
CTX_MAX=lots
CTX_RESERVE=-5
EOF

  [ "$(ctx_pct "$(printf '{"workspace":{"current_dir":"/tmp"},"transcript_path":"%s"}' "$t")")" -eq 50 ]
}

@test "a reserve at or above the window reads 0 rather than dividing by zero" {
  # awk would otherwise print "inf" into the ctx: segment, and a non-numeric
  # CTX_PCT then fails the `-ge 80` colour test with a stderr byte -- which
  # discards the entire statusline.
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

@test "README documents the terminal-theme foregrounds the palette is scored against" {
  # Trimming session-colors.sh removes the comment that named these. Scoring
  # xterm's rgb(205,205,0)/rgb(0,205,0) instead is what shipped seven illegible
  # codes, so the real values have to survive somewhere a human will look.
  local readme="${BATS_TEST_DIRNAME}/../README.md"
  grep -qi '#d9bd26' "$readme"
  grep -qi '#1cd915' "$readme"
  # The bar itself, not a bare "3.0" that any unrelated figure would satisfy.
  grep -qE '(ratios|worse of).{0,80}3\.0' "$readme"
  # Rule 2, the pairwise floor. It is the one palette guarantee no test computes,
  # so if the prose stops stating it, a regeneration can break it unnoticed.
  grep -qE '24\.36' "$readme"
}

@test "no document claims the palette holds sixteen colours" {
  # The palette is twelve. A stale "16" in the README outliving the comments it
  # replaced would make this trim a net loss.
  local n root
  root="${BATS_TEST_DIRNAME}/.."
  # shellcheck source=/dev/null
  . "${root}/claude/lib/session-colors.sh"
  n=${#SESSION_COLOR_PALETTE[@]}

  bats_run grep -nE "(Past|all) ${n}|${n} keys" "${root}/README.md"
  [ "$status" -eq 0 ]

  # Phrasing-independent, but present-tense only. Both files legitimately discuss
  # the OLD sixteen-code palette in the past tense ("7 of 16 codes below the
  # bar"), so match claims that 16 is the size NOW: a quantifier or copula
  # binding 16 to the palette, rather than any co-occurrence of the two.
  bats_run grep -nEi \
    "(past|all|only|the) 16 (colours?|codes?|keys|entries|assignments)|16 (colours?|codes?|keys|entries) (in|are|remain)|(palette|list) (of|has|holds|contains) 16|after 16 assignments" \
    "${root}/README.md" "${root}/claude/lib/session-colors.sh"
  [ "$status" -ne 0 ]
}

@test "session-colors.sh carries a one-line why for each load-bearing line" {
  # CLAUDE.md names three invariants as load-bearing. Their tests catch a
  # behaviour change but not a comment deletion, so the reason each line exists
  # must stay AT the line -- briefly, not as an essay.
  local script total
  script="${BATS_TEST_DIRNAME}/../claude/lib/session-colors.sh"

  grep -qE '^\s*#.*busy_timeout' "$script"
  grep -qE '^\s*#.*OR REPLACE' "$script"
  # The REASON the order matters, not the bare word: "# TODO: reorder this" would
  # satisfy a `[Oo]rder` match while the invariant it guards had been deleted.
  grep -qE '^\s*#.*[Oo]rder is load-bearing' "$script"
  grep -qE '^\s*#.*(adjacent|likely open together)' "$script"

  # Essential only: the file must not go back to explaining itself at length.
  # Prose only -- the shebang and shellcheck directives are not explanations, and
  # counting them would make a future directive look like a budget failure.
  total=$(grep -E '^\s*#([^!]|$)' "$script" | grep -cvE '^\s*#\s*shellcheck')
  [ "$total" -le 25 ]
}
