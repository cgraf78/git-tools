#compdef git-stash-audit
#description inspect and clean git stashes

_git_stash_audit() {
  _arguments -s \
    '--porcelain[Print stable tab-separated list records]' \
    '--show[Show one stash by numeric index]:index' \
    '--patch[Show a patch with --show]' \
    '--drop[Drop one stash by numeric index]:index' \
    '--drop-obsolete[Drop stashes whose inferred local branch is gone]' \
    '--yes[Confirm --drop-obsolete]' \
    '(-n --dry-run)'{-n,--dry-run}'[Print drop actions without changing anything]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_stash_audit "$@"
