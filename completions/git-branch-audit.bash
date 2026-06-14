# Bash completion for git-branch-audit
# shellcheck shell=bash disable=SC2207

_git_branch_audit() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  COMPREPLY=($(compgen -W "--porcelain --drop-merged --yes -b --base -n --dry-run -h --help" -- "$cur"))
}

complete -F _git_branch_audit git-branch-audit
