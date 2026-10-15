#compdef git-pr-watch
#description report whether GitHub pull requests are green, merged, or need action

_git_pr_watch_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"})
  _describe -t refs 'branch' refs
}

_git_pr_watch() {
  _arguments -s \
    '(-w --wait)'{-w,--wait}'[Keep checking until done, action needed, or stalled]' \
    '--timeout[With --wait, stop after this many seconds]:seconds' \
    '--interval[With --wait, seconds between checks]:seconds' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '*:pull request number, URL, or branch:_git_pr_watch_refs'
}

_git_pr_watch "$@"
