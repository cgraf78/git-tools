#compdef git-pr-restack
#description rebase one GitHub pull request branch onto a base

_git_pr_restack_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_pr_restack() {
  _arguments -s \
    '(-b --base)'{-b,--base}'[Rebase onto this branch and update the PR base]:base branch:_git_pr_restack_refs' \
    '--fork[Replay only commits after this ref (drops a squash-merged base)]:fork ref:_git_pr_restack_refs' \
    '--no-push[Rebase locally without pushing or editing the PR base]' \
    '(-n --dry-run)'{-n,--dry-run}'[Print actions without changing anything]' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:pull request number, URL, or branch:_git_pr_restack_refs'
}

_git_pr_restack "$@"
