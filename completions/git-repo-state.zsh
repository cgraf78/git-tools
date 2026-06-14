#compdef git-repo-state
#description report repository workflow state

_git_repo_state() {
  _arguments -s \
    '--porcelain[Print stable key=value output]' \
    '--json[Print a flat JSON object]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_repo_state "$@"
