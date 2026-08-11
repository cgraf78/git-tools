#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
SHARE_DIR="${SHARE_DIR:-$PREFIX/share}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
MAN_DIR="${MAN_DIR:-$SHARE_DIR/man/man1}"
BASH_COMPLETION_DIR="${BASH_COMPLETION_DIR:-$SHARE_DIR/bash-completion/completions}"
ZSH_COMPLETION_DIR="${ZSH_COMPLETION_DIR:-$SHARE_DIR/zsh/site-functions}"
FISH_COMPLETION_DIR="${FISH_COMPLETION_DIR:-$SHARE_DIR/fish/vendor_completions.d}"
ROOT=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

# shellcheck source=../lib/git-tools-inventory.sh
. "$ROOT/lib/git-tools-inventory.sh"

git_tools_validate_commands "$ROOT"

COMMANDS=()
while IFS= read -r command; do
  COMMANDS+=("$command")
done < <(git_tools_commands "$ROOT")

_require_file() {
  local source="$1"

  if [[ ! -f "$source" ]]; then
    printf 'git-tools: source is missing: %s\n' "$source" >&2
    return 1
  fi
}

_refuse_non_symlink() {
  local target="$1"

  if [[ (-e "$target" || -L "$target") && ! -L "$target" ]]; then
    printf 'git-tools: refusing to replace non-symlink path: %s\n' \
      "$target" >&2
    return 1
  fi
}

# Validate the complete provider tree before touching installation state. The
# inventory defines one command family, so a release without any one command's
# manual or completion would otherwise look successful while publishing only a
# partial interface.
for command in "${COMMANDS[@]}"; do
  _require_file "$ROOT/bin/$command"
  _require_file "$ROOT/man/man1/$command.1"
  _require_file "$ROOT/completions/$command.bash"
  _require_file "$ROOT/completions/$command.zsh"
  _require_file "$ROOT/completions/$command.fish"
done

# Build the publication order once so destination validation, rollback state,
# and the actual ln calls describe the same complete command family.
LINK_SOURCES=()
LINK_TARGETS=()
for command in "${COMMANDS[@]}"; do
  LINK_SOURCES+=("$ROOT/bin/$command")
  LINK_TARGETS+=("$BIN_DIR/$command")
done
for page in "$ROOT"/man/man1/*.1; do
  LINK_SOURCES+=("$page")
  LINK_TARGETS+=("$MAN_DIR/$(basename "$page")")
done
for completion in "$ROOT"/completions/*.bash; do
  name=$(basename "$completion" .bash)
  LINK_SOURCES+=("$completion")
  LINK_TARGETS+=("$BASH_COMPLETION_DIR/$name")
done
for completion in "$ROOT"/completions/*.zsh; do
  name=$(basename "$completion" .zsh)
  LINK_SOURCES+=("$completion")
  LINK_TARGETS+=("$ZSH_COMPLETION_DIR/_$name")
done
for completion in "$ROOT"/completions/*.fish; do
  LINK_SOURCES+=("$completion")
  LINK_TARGETS+=("$FISH_COMPLETION_DIR/$(basename "$completion")")
done

# Symlinks are installer-owned and may be retargeted to a newer checkout. Real
# files and directories are not: reject every collision up front so a late
# completion or manpage conflict cannot leave half of the command family live.
for target in "${LINK_TARGETS[@]}"; do
  _refuse_non_symlink "$target"
done

# Preflight cannot prevent an I/O failure during a later ln call. Snapshot the
# old symlink targets so that such a failure removes links created by this run
# and restores every link that was already installer-managed. Indexed arrays
# retain compatibility with the stock Bash 3.2 on macOS.
LINK_WAS_SYMLINK=()
LINK_OLD_TARGETS=()
for target in "${LINK_TARGETS[@]}"; do
  if [[ -L "$target" ]]; then
    LINK_WAS_SYMLINK+=(1)
    LINK_OLD_TARGETS+=("$(readlink "$target")")
  else
    LINK_WAS_SYMLINK+=(0)
    LINK_OLD_TARGETS+=("")
  fi
done

_rollback_links() {
  local last="$1" index target

  for ((index = last; index >= 0; index--)); do
    target="${LINK_TARGETS[index]}"
    if [[ (-e "$target" || -L "$target") && ! -L "$target" ]]; then
      printf 'git-tools: rollback preserved non-symlink path: %s\n' \
        "$target" >&2
      continue
    fi
    if [[ "${LINK_WAS_SYMLINK[index]}" -eq 1 ]]; then
      if ! ln -sfn -- "${LINK_OLD_TARGETS[index]}" "$target"; then
        printf 'git-tools: rollback could not restore symlink: %s\n' \
          "$target" >&2
      fi
    elif [[ -L "$target" ]] && ! rm -f -- "$target"; then
      printf 'git-tools: rollback could not remove new symlink: %s\n' \
        "$target" >&2
    fi
  done
}

mkdir -p "$BIN_DIR" "$MAN_DIR" "$BASH_COMPLETION_DIR" \
  "$ZSH_COMPLETION_DIR" "$FISH_COMPLETION_DIR"
for ((link_index = 0; link_index < ${#LINK_TARGETS[@]}; link_index++)); do
  if ln -sfn -- "${LINK_SOURCES[link_index]}" "${LINK_TARGETS[link_index]}"; then
    continue
  else
    link_status=$?
    _rollback_links "$link_index"
    exit "$link_status"
  fi
done

for command in "${COMMANDS[@]}"; do
  printf 'installed %s to %s\n' "$command" "$BIN_DIR"
done
printf 'installed man pages to %s\n' "$MAN_DIR"
printf 'installed bash completions to %s\n' "$BASH_COMPLETION_DIR"
printf 'installed zsh completions to %s\n' "$ZSH_COMPLETION_DIR"
printf 'installed fish completions to %s\n' "$FISH_COMPLETION_DIR"
