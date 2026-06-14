#compdef git-pr-sync-stack
#description restack a GitHub pull request stack

_git_pr_sync_stack_refs() {
  local -a refs
  refs=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"})
  _describe -t refs 'git ref' refs
}

_git_pr_sync_stack() {
  _arguments -s \
    '(-b --base)'{-b,--base}'[Rebase the root PR onto this base branch]:base:_git_pr_sync_stack_refs' \
    '--no-push[Rebase locally without pushing or editing PR bases]' \
    '(-n --dry-run)'{-n,--dry-run}'[Print actions without changing anything]' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:pull request number, URL, or branch:_git_pr_sync_stack_refs'
}

_git_pr_sync_stack "$@"
