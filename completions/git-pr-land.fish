# Fish completion for git-pr-land

function __git_pr_land_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-land -f
complete -c git-pr-land -s m -l method -r -a "squash merge rebase" -d "Merge method"
complete -c git-pr-land -l keep-branch -d "Do not delete the remote or local branch"
complete -c git-pr-land -s n -l dry-run -d "Print actions without changing anything"
complete -c git-pr-land -s h -l help -d "Show help"
complete -c git-pr-land -a "(__git_pr_land_refs)" -d "Pull request branch"
