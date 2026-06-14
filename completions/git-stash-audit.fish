# Fish completion for git-stash-audit

complete -c git-stash-audit -f
complete -c git-stash-audit -l porcelain -d "Print stable tab-separated list records"
complete -c git-stash-audit -l show -d "Show one stash by numeric index" -r
complete -c git-stash-audit -l patch -d "Show a patch with --show"
complete -c git-stash-audit -l drop -d "Drop one stash by numeric index" -r
complete -c git-stash-audit -l drop-obsolete -d "Drop stashes whose inferred local branch is gone"
complete -c git-stash-audit -l yes -d "Confirm --drop-obsolete"
complete -c git-stash-audit -s n -l dry-run -d "Print drop actions without changing anything"
complete -c git-stash-audit -s h -l help -d "Show help"
