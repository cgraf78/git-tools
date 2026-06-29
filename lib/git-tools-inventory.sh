#!/usr/bin/env bash

git_tools_commands() {
  local root="$1"
  local had_nullglob=0
  local files=()
  local file

  # The PATH-visible git commands are the authoritative inventory. Install,
  # extras coverage, and test dispatch derive from this so adding a new
  # `bin/git-*` executable cannot silently skip one of those surfaces.
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  files=("$root"/bin/git-*)
  [[ "$had_nullglob" -eq 1 ]] || shopt -u nullglob

  for file in "${files[@]}"; do
    [[ -f "$file" && -x "$file" ]] || continue
    basename "$file"
  done | LC_ALL=C sort
}
