# git-tools

![Tests](https://github.com/cgraf78/git-tools/actions/workflows/test.yml/badge.svg?branch=main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D3.2-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Small Git workflow tools.

## Commands

### `git cleanup-repo`

Fetches and prunes the remote, updates the repository's default branch, then
removes stale local branches.

```sh
git cleanup-repo
```

By default the command deletes only local branches that are already merged into
the base branch. Use `--gone` to also delete local branches whose upstream
branch was removed.

Use `--all` when a stack was squash-merged and you intentionally want to delete
every local branch except the base branch:

```sh
git cleanup-repo --all
```

If a branch is checked out in a linked worktree, the command skips it by
default. To remove clean linked worktrees for branches being deleted:

```sh
git cleanup-repo --all --remove-worktrees
```

Useful options:

```sh
git cleanup-repo --dry-run
git cleanup-repo --gone
git cleanup-repo --base main
git cleanup-repo --remote upstream
```

The command refuses to run with a dirty current worktree or an active
rebase/merge/cherry-pick/revert.

### `git absorb-and-rebase`

Creates `git-absorb` fixup commits for staged changes, then folds those fixups
with a non-interactive autosquash rebase.

```sh
git add path/to/fix
git absorb-and-rebase
```

By default the command derives the branch base from, in order:

- the branch upstream
- remote default branches such as `origin/HEAD`, `origin/main`, or
  `origin/master`
- local default branches such as `main`, `master`, or `trunk`

Pass an explicit base when the branch point is ambiguous:

```sh
git absorb-and-rebase --base origin/main
```

The command only operates on staged changes. It refuses dirty-but-unstaged
changes when nothing is staged, refuses active rebase/merge/cherry-pick/revert
states, and rolls back partial fixup generation if `git absorb` leaves staged
changes behind.

## Requirements

- Bash
- Git
- [`git-absorb`](https://github.com/tummychow/git-absorb)

## Install

Put `bin/` on `PATH`, or link `bin/git-absorb-and-rebase` into a directory on
`PATH`. Git discovers executable files named `git-*`, so the installed commands
are invoked as:

```sh
git cleanup-repo
git absorb-and-rebase
```

For a simple local install:

```sh
./install.sh
```

Set `PREFIX` or `BIN_DIR` to choose another destination.

## Test

Run the complete local test suite:

```sh
test/run
```

Or run the focused command test directly:

```sh
test/git-absorb-and-rebase-test
test/git-cleanup-repo-test
```

If `git-absorb` is not installed, the test suite verifies the dependency error
path and skips rewrite integration cases.
