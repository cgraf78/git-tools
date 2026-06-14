# Bash completion for git-pr-sync-stack
# shellcheck shell=bash disable=SC2207

_git_pr_sync_stack_refs() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

_git_pr_sync_stack() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "-b --base --no-push -n --dry-run -h --help" -- "$cur"))
    return
  fi

  COMPREPLY=($(compgen -W "$(_git_pr_sync_stack_refs)" -- "$cur"))
}

complete -F _git_pr_sync_stack git-pr-sync-stack
