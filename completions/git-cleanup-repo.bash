# Bash completion for git-cleanup-repo
# shellcheck shell=bash disable=SC2207

_git_cleanup_repo_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_cleanup_repo_remotes() {
  git remote 2>/dev/null
}

_git_cleanup_repo() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "$prev" in
    -b | --base)
      COMPREPLY=($(compgen -W "$(_git_cleanup_repo_refs)" -- "$cur"))
      return
      ;;
    -r | --remote)
      COMPREPLY=($(compgen -W "$(_git_cleanup_repo_remotes)" -- "$cur"))
      return
      ;;
  esac

  COMPREPLY=($(compgen -W "-b --base -r --remote --gone -a --all --remove-worktrees -n --dry-run -h --help" -- "$cur"))
}

complete -F _git_cleanup_repo git-cleanup-repo
