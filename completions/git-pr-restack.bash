# Bash completion for git-pr-restack
# shellcheck shell=bash disable=SC2207

_git_pr_restack_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_pr_restack() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "$prev" in
    -b | --base | --fork)
      COMPREPLY=($(compgen -W "$(_git_pr_restack_refs)" -- "$cur"))
      return
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "-b --base --fork --no-push -n --dry-run -h --help" -- "$cur"))
    return
  fi

  COMPREPLY=($(compgen -W "$(_git_pr_restack_refs)" -- "$cur"))
}

complete -F _git_pr_restack git-pr-restack
