# Fish completion for git-pr-restack

function __git_pr_restack_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-restack -f
complete -c git-pr-restack -s b -l base -r -a "(__git_pr_restack_refs)" -d "Rebase onto this branch and update the PR base"
complete -c git-pr-restack -l no-push -d "Rebase locally without pushing or editing the PR base"
complete -c git-pr-restack -s n -l dry-run -d "Print actions without changing anything"
complete -c git-pr-restack -s h -l help -d "Show help"
complete -c git-pr-restack -a "(__git_pr_restack_refs)" -d "Pull request branch"
