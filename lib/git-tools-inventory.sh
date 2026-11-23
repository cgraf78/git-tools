#!/usr/bin/env bash

_git_tools_command_files() (
  local root="$1"
  local file

  # A glob alone cannot distinguish an unreadable directory from an empty one.
  if [[ ! -d "$root/bin" || ! -r "$root/bin" || ! -x "$root/bin" ]]; then
    printf 'error: cannot discover Git-tools launchers in %s/bin\n' "$root" >&2
    return 1
  fi
  set -o pipefail
  shopt -s nullglob

  for file in "$root"/bin/git-*; do
    [[ -f "$file" || -L "$file" ]] || continue
    printf '%s\n' "$file"
  done | LC_ALL=C sort
)

git_tools_commands() {
  local root="$1"
  local file files

  # The PATH-visible git commands are the authoritative inventory. Install,
  # extras coverage, and test dispatch derive from this so adding a new
  # `bin/git-*` executable cannot silently skip one of those surfaces.
  files=$(_git_tools_command_files "$root") || return
  while IFS= read -r file; do
    [[ -f "$file" && -x "$file" && ! -L "$file" ]] || continue
    printf '%s\n' "${file##*/}"
  done <<<"$files"
}

git_tools_validate_commands() {
  local root="$1"
  local file files
  local status=0

  files=$(_git_tools_command_files "$root") || return
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ -L "$file" ]]; then
      printf 'error: Git-tools launcher must be a regular file, not a symlink: %s\n' \
        "${file#"$root/"}" >&2
      status=1
    elif [[ ! -x "$file" ]]; then
      printf 'error: Git-tools launcher is not executable: %s\n' \
        "${file#"$root/"}" >&2
      status=1
    fi
  done <<<"$files"

  return "$status"
}
