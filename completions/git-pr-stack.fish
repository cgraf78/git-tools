# Fish completion for git-pr-stack

function __git_pr_stack_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-stack -f
complete -c git-pr-stack -l porcelain -d "Print one stable tab-separated record per PR"
complete -c git-pr-stack -s h -l help -d "Show help"
complete -c git-pr-stack -a "(__git_pr_stack_refs)" -d "Pull request branch"
