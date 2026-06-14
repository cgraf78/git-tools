#compdef git-absorb-and-rebase

_git_absorb_and_rebase_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_absorb_and_rebase() {
  _arguments -s \
    '(-b --base)'{-b,--base}'[Rebase from this base revision]:base:_git_absorb_and_rebase_refs' \
    '(-h --help)'{-h,--help}'[Show help]'
}

_git_absorb_and_rebase "$@"
