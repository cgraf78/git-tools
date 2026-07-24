#compdef git-cleanup-repo
#description report stale local branch cleanup candidates

_git_cleanup_repo_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_cleanup_repo_remotes() {
  local -a remotes
  remotes=(${(f)"$(git remote 2>/dev/null)"})
  _describe -t remotes 'git remote' remotes
}

_git_cleanup_repo() {
  _arguments -s \
    '(-b --base)'{-b,--base}'[Base branch to keep and update]:base branch:_git_cleanup_repo_refs' \
    '(-r --remote)'{-r,--remote}'[Remote to fetch the exact base from]:remote:_git_cleanup_repo_remotes' \
    '--gone[Also report branches whose upstream is gone]' \
    '(-a --all)'{-a,--all}'[Report all local branches except the base branch]' \
    '--remove-worktrees[Accepted for compatibility; removes nothing]' \
    '(-n --dry-run)'{-n,--dry-run}'[Print candidate actions without changing anything]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_cleanup_repo "$@"
