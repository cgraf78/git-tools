#compdef git-pr-submit
#description submit default-branch commits through a pull request

_git_pr_submit() {
  # No mutation-changing options are offered: submission always uses the exact
  # local commits and queues protected auto-merge only where it is available.
  _arguments -s \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_pr_submit "$@"
