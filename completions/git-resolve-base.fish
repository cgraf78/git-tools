# Fish completion for git-resolve-base

complete -c git-resolve-base -f
complete -c git-resolve-base -l ref -d "Print the resolved base ref instead of the merge-base commit"
complete -c git-resolve-base -l short -d "Abbreviate the merge-base commit id"
complete -c git-resolve-base -s h -l help -d "Show help"
