# Bash completion for git-repo-state
# shellcheck shell=bash disable=SC2207

_git_repo_state() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  COMPREPLY=($(compgen -W "--porcelain --json -h --help" -- "$cur"))
}

complete -F _git_repo_state git-repo-state
