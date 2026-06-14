# Bash completion for git-absorb-and-rebase
# shellcheck shell=bash disable=SC2207

_git_absorb_and_rebase_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_absorb_and_rebase() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "$prev" in
    -b | --base)
      COMPREPLY=($(compgen -W "$(_git_absorb_and_rebase_refs)" -- "$cur"))
      return
      ;;
  esac

  COMPREPLY=($(compgen -W "-b --base -h --help" -- "$cur"))
}

complete -F _git_absorb_and_rebase git-absorb-and-rebase
