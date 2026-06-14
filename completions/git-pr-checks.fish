# Fish completion for git-pr-checks

function __git_pr_checks_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-checks -f
complete -c git-pr-checks -l porcelain -d "Print stable key=value output and tab-separated records"
complete -c git-pr-checks -l required-only -d "Only include required checks"
complete -c git-pr-checks -l required -d "Only include required checks"
complete -c git-pr-checks -s w -l watch -d "Wait for checks to finish before summarizing"
complete -c git-pr-checks -s i -l interval -d "Refresh interval in seconds for --watch" -r
complete -c git-pr-checks -s h -l help -d "Show help"
complete -c git-pr-checks -a "(__git_pr_checks_refs)" -d "Pull request branch"
