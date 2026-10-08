# Fish completion for git-branch-audit

complete -c git-branch-audit -f
complete -c git-branch-audit -l porcelain -d "Print stable tab-separated branch records"
complete -c git-branch-audit -s b -l base -d "Use this branch as the default" -r
complete -c git-branch-audit -s h -l help -d "Show help"
