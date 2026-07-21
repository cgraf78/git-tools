#!/usr/bin/env bash

_git_tools_command_files() {
  local root="$1"
  local had_nullglob=0
  local files=()
  local file

  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  files=("$root"/bin/git-*)
  [[ "$had_nullglob" -eq 1 ]] || shopt -u nullglob

  for file in "${files[@]}"; do
    [[ -f "$file" || -L "$file" ]] || continue
    printf '%s\n' "$file"
  done | LC_ALL=C sort
}

git_tools_commands() {
  local root="$1"
  local file

  # The PATH-visible git commands are the authoritative inventory. Install,
  # extras coverage, and test dispatch derive from this so adding a new
  # `bin/git-*` executable cannot silently skip one of those surfaces.
  while IFS= read -r file; do
    [[ -f "$file" && -x "$file" && ! -L "$file" ]] || continue
    basename "$file"
  done < <(_git_tools_command_files "$root")
}

git_tools_validate_commands() {
  local root="$1"
  local file
  local status=0

  while IFS= read -r file; do
    if [[ -L "$file" ]]; then
      printf 'error: Git-tools launcher must be a regular file, not a symlink: %s\n' \
        "${file#"$root/"}" >&2
      status=1
    elif [[ ! -x "$file" ]]; then
      printf 'error: Git-tools launcher is not executable: %s\n' \
        "${file#"$root/"}" >&2
      status=1
    fi
  done < <(_git_tools_command_files "$root")

  return "$status"
}
