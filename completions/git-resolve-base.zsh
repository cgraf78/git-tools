#compdef git-resolve-base
#description print the inferred branch point of the current branch

_git_resolve_base() {
  _arguments -s \
    '--ref[Print the resolved base ref instead of the merge-base commit]' \
    '--short[Abbreviate the merge-base commit id]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_resolve_base "$@"
