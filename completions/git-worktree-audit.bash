# Bash completion for git-worktree-audit
# shellcheck shell=bash disable=SC2207

_git_worktree_audit() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  COMPREPLY=($(compgen -W "--porcelain --prune-orphan -n --dry-run -h --help" -- "$cur"))
}

complete -F _git_worktree_audit git-worktree-audit
