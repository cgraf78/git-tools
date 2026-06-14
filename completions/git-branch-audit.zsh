#compdef git-branch-audit
#description audit local branches against the default branch

_git_branch_audit() {
  _arguments -s \
    '--porcelain[Print stable tab-separated branch records]' \
    '--drop-merged[Delete branches already merged into the default branch]' \
    '--yes[Confirm --drop-merged]' \
    '(-b --base)'{-b,--base}'[Use this branch as the default]:branch:__git_branch_names' \
    '(-n --dry-run)'{-n,--dry-run}'[Print drop actions without changing anything]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_branch_audit "$@"
