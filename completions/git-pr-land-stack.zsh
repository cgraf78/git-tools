#compdef git-pr-land-stack
#description land a ready linear GitHub pull request stack

_git_pr_land_stack_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_pr_land_stack() {
  _arguments -s \
    '(-m --method)'{-m,--method}'[Merge method]:method:(squash merge rebase)' \
    '--keep-branch[Pass --keep-branch to git pr-land]' \
    '(-n --dry-run)'{-n,--dry-run}'[Print actions without changing anything]' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:pull request number, URL, or branch:_git_pr_land_stack_refs'
}

_git_pr_land_stack "$@"
