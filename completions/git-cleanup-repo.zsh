#compdef git-cleanup-repo
#description delete safely merged local branches

_git_cleanup_repo_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"})
  _describe -t refs 'branch' refs
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
    '--gone[Select branches whose own-name upstream is gone]' \
    '(-a --all)'{-a,--all}'[Delete all local branches except the base branch]' \
    '--remove-worktrees[Remove eligible linked worktrees for deleted branches]' \
    '*--worktree[Remove only this linked worktree]:worktree:_files -/' \
    '--no-update-base[Prove against the remote base without changing the local base]' \
    '--no-fetch[Prove against the remote-tracking base ref instead of fetching]' \
    '--porcelain[Print one tab-separated record per decision]' \
    '--min-age[Keep young ancestry-only branches]:days' \
    '*--retire-worktree[Remove this linked worktree but keep its branch]:worktree:_files -/' \
    '--include-closed[Retire selected worktrees of closed, unmerged PRs]' \
    '(-n --dry-run)'{-n,--dry-run}'[Print deletion actions without changing anything]' \
    '--interface-version[Print the porcelain interface version]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_cleanup_repo "$@"
