# Fish completion for git-pr-land-stack

function __git_pr_land_stack_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-land-stack -f
complete -c git-pr-land-stack -s m -l method -r -a "squash merge rebase" -d "Merge method"
complete -c git-pr-land-stack -l keep-branch -d "Pass --keep-branch to git pr-land"
complete -c git-pr-land-stack -s n -l dry-run -d "Print actions without changing anything"
complete -c git-pr-land-stack -s h -l help -d "Show help"
complete -c git-pr-land-stack -a "(__git_pr_land_stack_refs)" -d "Pull request branch"
