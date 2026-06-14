#compdef git-pr-ready
#description check whether a GitHub pull request is landable

_git_pr_ready_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_pr_ready() {
  _arguments -s \
    '--porcelain[Print stable key=value output]' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:pull request number, URL, or branch:_git_pr_ready_refs'
}

_git_pr_ready "$@"
