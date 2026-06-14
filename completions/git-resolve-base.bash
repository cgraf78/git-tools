# Bash completion for git-resolve-base
# shellcheck shell=bash disable=SC2207

_git_resolve_base() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  COMPREPLY=($(compgen -W "--ref --short -h --help" -- "$cur"))
}

complete -F _git_resolve_base git-resolve-base
