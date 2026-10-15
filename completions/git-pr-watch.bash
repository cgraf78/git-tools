# Bash completion for git-pr-watch
# shellcheck shell=bash disable=SC2207

_git_pr_watch_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
}

_git_pr_watch() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
    return
  fi

  COMPREPLY=($(compgen -W "$(_git_pr_watch_refs)" -- "$cur"))
}

complete -F _git_pr_watch git-pr-watch
