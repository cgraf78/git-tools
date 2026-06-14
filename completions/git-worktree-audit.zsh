#compdef git-worktree-audit
#description report state across all worktrees

_git_worktree_audit() {
  _arguments -s \
    '--porcelain[Print stable tab-separated worktree records]' \
    '--prune-orphan[Prune worktrees whose directory no longer exists]' \
    '(-n --dry-run)'{-n,--dry-run}'[With --prune-orphan, print what would be pruned]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_worktree_audit "$@"
