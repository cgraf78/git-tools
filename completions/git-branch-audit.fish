# Fish completion for git-branch-audit

complete -c git-branch-audit -f
complete -c git-branch-audit -l porcelain -d "Print stable tab-separated branch records"
complete -c git-branch-audit -l drop-merged -d "Delete branches already merged into the default branch"
complete -c git-branch-audit -l yes -d "Confirm --drop-merged"
complete -c git-branch-audit -s b -l base -d "Use this branch as the default" -r
complete -c git-branch-audit -s n -l dry-run -d "Print drop actions without changing anything"
complete -c git-branch-audit -s h -l help -d "Show help"
