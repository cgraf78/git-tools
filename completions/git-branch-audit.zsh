#compdef git-branch-audit
#description audit local branches against the default branch

_git_branch_audit() {
  _arguments -s \
    '--porcelain[Print stable tab-separated branch records]' \
    '(-b --base)'{-b,--base}'[Use this branch as the default]:branch:__git_branch_names' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_branch_audit "$@"
