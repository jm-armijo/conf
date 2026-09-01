# Spaceship prompt configuration.
#
# Sourced from zsh/zshrc after `source $ZSH/oh-my-zsh.sh`, which is where
# oh-my-zsh loads the theme and where upstream documents user config to go.
#
# The default section icons (git branch, node, ruby, ...) are glyphs from a
# Nerd Font. Without one the prompt renders boxes or blanks; see the README.

# Sections to render, in order. Doubles as the list of what's active — a
# section left out of here is off, regardless of its other SPACESHIP_* vars.
SPACESHIP_PROMPT_ORDER=(
  time          # timestamp at the start of the line
  dir           # current directory
  git           # branch + working tree status
  package       # package.json / gemspec version
  node          # node version, only in node projects
  ruby          # ruby version, only in ruby projects
  exec_time     # duration of the previous command, when slow
  line_sep      # newline: everything above, input below
  jobs          # background job count
  exit_code     # non-zero exit status of the previous command
  char          # the prompt character itself
)

SPACESHIP_PROMPT_ADD_NEWLINE="true"  # blank line between each prompt
SPACESHIP_CHAR_SYMBOL="➜ "           # prompt character
SPACESHIP_DIR_TRUNC_REPO="true"      # inside a repo, show the repo-relative path (agnoster's behaviour)
