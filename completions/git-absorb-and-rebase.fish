# Fish completion for git-absorb-and-rebase

function __git_absorb_and_rebase_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-absorb-and-rebase -f
complete -c git-absorb-and-rebase -s b -l base -r -a "(__git_absorb_and_rebase_refs)" -d "Rebase from this base revision"
complete -c git-absorb-and-rebase -s h -l help -d "Show help"
