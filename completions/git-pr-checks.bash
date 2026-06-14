# Bash completion for git-pr-checks
# shellcheck shell=bash disable=SC2207

_git_pr_checks_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_pr_checks() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "--porcelain --required-only --required -w --watch -i --interval -h --help" -- "$cur"))
    return
  fi

  COMPREPLY=($(compgen -W "$(_git_pr_checks_refs)" -- "$cur"))
}

complete -F _git_pr_checks git-pr-checks
