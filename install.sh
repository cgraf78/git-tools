#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p "$BIN_DIR"
ln -sf "$ROOT/bin/git-absorb-and-rebase" "$BIN_DIR/git-absorb-and-rebase"
ln -sf "$ROOT/bin/git-cleanup-repo" "$BIN_DIR/git-cleanup-repo"
ln -sf "$ROOT/bin/git-pr-ready" "$BIN_DIR/git-pr-ready"
ln -sf "$ROOT/bin/git-pr-stack" "$BIN_DIR/git-pr-stack"

printf 'installed git-absorb-and-rebase to %s\n' "$BIN_DIR"
printf 'installed git-cleanup-repo to %s\n' "$BIN_DIR"
printf 'installed git-pr-ready to %s\n' "$BIN_DIR"
printf 'installed git-pr-stack to %s\n' "$BIN_DIR"
