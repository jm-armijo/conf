#!/bin/bash

git config --global alias.co 'checkout'
git config --global alias.br 'branch'
git config --global alias.ci 'commit'
git config --global alias.st 'status'
git config --global alias.sq 'rebase -i'
git config --global alias.sq2 'rebase -i HEAD~2'
git config --global alias.rename 'branch -m'
git config --global alias.po 'pull origin'
git config --global alias.ll 'log --oneline'
git config --global alias.shu 'stash push -k -u'
git config --global alias.fix 'commit --amend --no-edit'
git config --global alias.wm 'worktree move'
git config --global alias.pm '!git fetch origin main && git update-ref refs/heads/main origin/main'
git config --global alias.cont '!~/personal/scripts/contributors_table.sh'
git config --global alias.rbm '!f(){ git pm && git rebase main; }; f'
git config --global alias.aliases 'config --get-regexp '\''^alias\.'\'''
git config --global alias.vs '!f() {
  idx="${1:-0}";
  S="stash@{${idx}}";

  # Validate the stash entry exists
  git rev-parse --verify -q "$S^{commit}" >/dev/null || {
    echo "error: $S not found" >&2; exit 1;
  }

  # Stash description (subject line)
  desc=$(git log -1 --pretty=%s "$S")
  echo "stash@{${idx}}: $desc"
  echo

  {
    # Tracked changes (index + working tree) vs base
    git diff --name-status --no-renames "$S^1" "$S";

    # Untracked/ignored files (if present) as Added
    git ls-tree -r --name-only "$S^3" 2>/dev/null | sed "s/^/A\t/";
  } |
  # Prefer tracked status when a path appears in both; then sort by path
  awk -F"\t" '\''{ if (!seen[$2]++) map[$2]=$1 } END { for (f in map) print map[f] "\t" f }'\'' |
  sort -k2,2
}; f'
