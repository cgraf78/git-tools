# Fish completion for git-worktree-audit

complete -c git-worktree-audit -f
complete -c git-worktree-audit -l porcelain -d "Print stable tab-separated worktree records"
complete -c git-worktree-audit -l prune-orphan -d "Prune worktrees whose directory no longer exists"
complete -c git-worktree-audit -s n -l dry-run -d "With --prune-orphan, print what would be pruned"
complete -c git-worktree-audit -s h -l help -d "Show help"
