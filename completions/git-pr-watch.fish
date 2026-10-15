# Fish completion for git-pr-watch

function __git_pr_watch_refs
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
end

complete -c git-pr-watch -f
complete -c git-pr-watch -s h -l help -d "Show help"
complete -c git-pr-watch -a "(__git_pr_watch_refs)" -d "Pull request branch"
