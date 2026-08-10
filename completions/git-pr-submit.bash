# Bash completion for git-pr-submit
# shellcheck shell=bash disable=SC2207

_git_pr_submit() {
  local cur

  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  # Submission intentionally has no behavioral flags: the default path must
  # always preserve protections and use commit-derived or human-edited text.
  COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
}

complete -F _git_pr_submit git-pr-submit
