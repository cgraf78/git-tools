# Bash completion for git-pr-ready
# shellcheck shell=bash disable=SC2207

_git_pr_ready_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_pr_ready() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "--porcelain -h --help" -- "$cur"))
    return
  fi

  COMPREPLY=($(compgen -W "$(_git_pr_ready_refs)" -- "$cur"))
}

complete -F _git_pr_ready git-pr-ready
