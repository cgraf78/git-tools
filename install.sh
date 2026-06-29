#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
SHARE_DIR="${SHARE_DIR:-$PREFIX/share}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
MAN_DIR="${MAN_DIR:-$SHARE_DIR/man/man1}"
BASH_COMPLETION_DIR="${BASH_COMPLETION_DIR:-$SHARE_DIR/bash-completion/completions}"
ZSH_COMPLETION_DIR="${ZSH_COMPLETION_DIR:-$SHARE_DIR/zsh/site-functions}"
FISH_COMPLETION_DIR="${FISH_COMPLETION_DIR:-$SHARE_DIR/fish/vendor_completions.d}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/git-tools-inventory.sh
. "$ROOT/lib/git-tools-inventory.sh"

COMMANDS=()
while IFS= read -r command; do
  COMMANDS+=("$command")
done < <(git_tools_commands "$ROOT")

mkdir -p "$BIN_DIR"
for command in "${COMMANDS[@]}"; do
  ln -sf "$ROOT/bin/$command" "$BIN_DIR/$command"
  printf 'installed %s to %s\n' "$command" "$BIN_DIR"
done

mkdir -p "$MAN_DIR"
for page in "$ROOT"/man/man1/*.1; do
  ln -sf "$page" "$MAN_DIR/$(basename "$page")"
done
printf 'installed man pages to %s\n' "$MAN_DIR"

mkdir -p "$BASH_COMPLETION_DIR"
for completion in "$ROOT"/completions/*.bash; do
  name=$(basename "$completion" .bash)
  ln -sf "$completion" "$BASH_COMPLETION_DIR/$name"
done
printf 'installed bash completions to %s\n' "$BASH_COMPLETION_DIR"

mkdir -p "$ZSH_COMPLETION_DIR"
for completion in "$ROOT"/completions/*.zsh; do
  name=$(basename "$completion" .zsh)
  ln -sf "$completion" "$ZSH_COMPLETION_DIR/_$name"
done
printf 'installed zsh completions to %s\n' "$ZSH_COMPLETION_DIR"

mkdir -p "$FISH_COMPLETION_DIR"
for completion in "$ROOT"/completions/*.fish; do
  ln -sf "$completion" "$FISH_COMPLETION_DIR/$(basename "$completion")"
done
printf 'installed fish completions to %s\n' "$FISH_COMPLETION_DIR"
