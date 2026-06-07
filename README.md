# git-tools

![Tests](https://github.com/cgraf78/git-tools/actions/workflows/test.yml/badge.svg?branch=main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D3.2-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Small Git workflow tools.

## Commands

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
`PATH`. Git discovers executable files named `git-*`, so the installed command
is invoked as:

```sh
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
```

If `git-absorb` is not installed, the test suite verifies the dependency error
path and skips rewrite integration cases.
