# Bash completion for git-pr-land-stack
# shellcheck shell=bash disable=SC2207

_git_pr_land_stack_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_pr_land_stack() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "$prev" in
    -m | --method)
      COMPREPLY=($(compgen -W "squash merge rebase" -- "$cur"))
      return
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "-m --method --keep-branch -n --dry-run -h --help" -- "$cur"))
    return
  fi

  COMPREPLY=($(compgen -W "$(_git_pr_land_stack_refs)" -- "$cur"))
}

complete -F _git_pr_land_stack git-pr-land-stack
