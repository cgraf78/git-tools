#compdef git-pr-open
#description push a branch and create a pull request

_git_pr_open_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_pr_open() {
  _arguments -s \
    '(-t --title)'{-t,--title}'[Pull request title]:title' \
    '(-b --body)'{-b,--body}'[Pull request body]:body' \
    '(-F --body-file)'{-F,--body-file}'[Read pull request body from file]:file:_files' \
    '(-B --base)'{-B,--base}'[Base branch]:base:_git_pr_open_refs' \
    '(-H --head)'{-H,--head}'[Head branch name for GitHub]:head:_git_pr_open_refs' \
    '(-d --draft)'{-d,--draft}'[Create a draft pull request]' \
    '--fill[Use commit info for title and body]' \
    '--fill-first[Use first commit info for title and body]' \
    '--fill-verbose[Use commit messages and bodies for description]' \
    '--no-maintainer-edit[Disable maintainer edits]' \
    '(-n --dry-run)'{-n,--dry-run}'[Print actions without changing anything]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_pr_open "$@"
