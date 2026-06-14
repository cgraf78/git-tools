# Bash completion for git-stash-audit
# shellcheck shell=bash disable=SC2207

_git_stash_audit() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"

  COMPREPLY=($(compgen -W "--porcelain --show --patch --drop --drop-obsolete --yes -n --dry-run -h --help" -- "$cur"))
}

complete -F _git_stash_audit git-stash-audit
