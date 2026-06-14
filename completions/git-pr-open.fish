# Fish completion for git-pr-open

function __git_pr_open_refs
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

complete -c git-pr-open -f
complete -c git-pr-open -s t -l title -d "Pull request title" -r
complete -c git-pr-open -s b -l body -d "Pull request body" -r
complete -c git-pr-open -s F -l body-file -d "Read pull request body from file" -r
complete -c git-pr-open -s B -l base -d "Base branch" -a "(__git_pr_open_refs)"
complete -c git-pr-open -s H -l head -d "Head branch name for GitHub" -a "(__git_pr_open_refs)"
complete -c git-pr-open -s d -l draft -d "Create a draft pull request"
complete -c git-pr-open -l fill -d "Use commit info for title and body"
complete -c git-pr-open -l fill-first -d "Use first commit info for title and body"
complete -c git-pr-open -l fill-verbose -d "Use commit messages and bodies for description"
complete -c git-pr-open -l no-maintainer-edit -d "Disable maintainer edits"
complete -c git-pr-open -s n -l dry-run -d "Print actions without changing anything"
complete -c git-pr-open -s h -l help -d "Show help"
