# Fish completion for git-pr-sync-stack

function __git_pr_sync_stack_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-sync-stack -f
complete -c git-pr-sync-stack -s b -l base -d "Rebase the root PR onto this base branch" -r
complete -c git-pr-sync-stack -l no-push -d "Rebase locally without pushing or editing PR bases"
complete -c git-pr-sync-stack -s n -l dry-run -d "Print actions without changing anything"
complete -c git-pr-sync-stack -s h -l help -d "Show help"
complete -c git-pr-sync-stack -a "(__git_pr_sync_stack_refs)" -d "Pull request branch"
