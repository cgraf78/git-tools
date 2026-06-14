# Bash completion for git-pr-stack
# shellcheck shell=bash disable=SC2207

_git_pr_stack_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_pr_stack() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "--porcelain -h --help" -- "$cur"))
    return
  fi

  COMPREPLY=($(compgen -W "$(_git_pr_stack_refs)" -- "$cur"))
}

complete -F _git_pr_stack git-pr-stack
