#compdef git-pr-checks
#description summarize GitHub pull request checks

_git_pr_checks_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_pr_checks() {
  _arguments -s \
    '--porcelain[Print stable key=value output and tab-separated records]' \
    '--required-only[Only include required checks]' \
    '--required[Only include required checks]' \
    '(-w --watch)'{-w,--watch}'[Wait for checks to finish before summarizing]' \
    '(-i --interval)'{-i,--interval}'[Refresh interval in seconds for --watch]:seconds' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:pull request number, URL, or branch:_git_pr_checks_refs'
}

_git_pr_checks "$@"
