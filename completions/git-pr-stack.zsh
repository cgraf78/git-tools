#compdef git-pr-stack
#description discover a linear GitHub pull request stack

_git_pr_stack_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_pr_stack() {
  _arguments -s \
    '--porcelain[Print one stable tab-separated record per PR]' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:pull request number, URL, or branch:_git_pr_stack_refs'
}

_git_pr_stack "$@"
