# Fish completion for git-cleanup-repo

function __git_cleanup_repo_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

function __git_cleanup_repo_remotes
    git remote 2>/dev/null
end

complete -c git-cleanup-repo -f
complete -c git-cleanup-repo -s b -l base -r -a "(__git_cleanup_repo_refs)" -d "Base branch to keep and update"
complete -c git-cleanup-repo -s r -l remote -r -a "(__git_cleanup_repo_remotes)" -d "Remote to fetch the exact base from"
complete -c git-cleanup-repo -l gone -d "Also report branches whose upstream is gone"
complete -c git-cleanup-repo -s a -l all -d "Report all local branches except the base branch"
complete -c git-cleanup-repo -l remove-worktrees -d "Accepted for compatibility; removes nothing"
complete -c git-cleanup-repo -s n -l dry-run -d "Print candidate actions without changing anything"
complete -c git-cleanup-repo -s h -l help -d "Show help"
