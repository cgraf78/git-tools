# Bash completion for git-cleanup-repo
# shellcheck shell=bash disable=SC2207

# --base names a branch on the remote; local branch names are the useful
# candidates (a remote-tracking name such as origin/main is not one).
_git_cleanup_repo_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
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
    --worktree | --retire-worktree)
      COMPREPLY=($(compgen -d -- "$cur"))
      return
      ;;
    --min-age)
      return
      ;;
  esac

  COMPREPLY=($(compgen -W "-b --base -r --remote --gone -a --all --remove-worktrees --worktree --no-update-base --no-fetch --porcelain --min-age --retire-worktree --include-closed -n --dry-run --interface-version -h --help" -- "$cur"))
}

complete -F _git_cleanup_repo git-cleanup-repo
