# Fish completion for git-pr-ready

function __git_pr_ready_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-ready -f
complete -c git-pr-ready -l porcelain -d "Print stable key=value output"
complete -c git-pr-ready -s h -l help -d "Show help"
complete -c git-pr-ready -a "(__git_pr_ready_refs)" -d "Pull request branch"
