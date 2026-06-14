# Bash completion for git-pr-open
# shellcheck shell=bash disable=SC2207

_git_pr_open_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_pr_open() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  case "${COMP_WORDS[$((COMP_CWORD - 1))]}" in
    --base | -B | --head | -H)
      COMPREPLY=($(compgen -W "$(_git_pr_open_refs)" -- "$cur"))
      return
      ;;
  esac

  COMPREPLY=($(compgen -W "-t --title -b --body -F --body-file -B --base -H --head -d --draft --fill --fill-first --fill-verbose --no-maintainer-edit -n --dry-run -h --help" -- "$cur"))
}

complete -F _git_pr_open git-pr-open
