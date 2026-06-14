# git-tools

![Tests](https://github.com/cgraf78/git-tools/actions/workflows/test.yml/badge.svg?branch=main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D3.2-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Small Git workflow tools.

## Commands

### `git pr-ready`

Checks whether a GitHub pull request is open, non-draft, conflict-free, and has
passing checks.

```sh
git pr-ready
git pr-ready 123
git pr-ready feature/my-branch
```

Use `--porcelain` for stable `key=value` output that other scripts can compose:

```sh
git pr-ready --porcelain
```

### `git pr-checks`

Summarizes GitHub pull request checks with stable aggregate output.

```sh
git pr-checks
git pr-checks 123
git pr-checks feature/my-branch --watch
```

Use `--porcelain` for stable aggregate fields and tab-separated check records:

```sh
git pr-checks --porcelain
```

The command returns `0` when checks pass, `8` while checks are pending, and `1`
when checks fail, are cancelled, or are missing.

### `git pr-open`

Pushes the current branch with upstream tracking and creates a GitHub pull
request without interactive prompts.

```sh
git pr-open --title "Add thing" --body-file /tmp/pr-body.md
git pr-open --title "Add thing" --draft
git pr-open --fill --dry-run
```

The command refuses dirty worktrees, refuses to open from the base branch, fetches
the base remote, and rejects a stale local base branch when it differs from its
remote-tracking branch.

### `git repo-state`

Prints a read-only repository workflow report: current branch, default branch,
upstream divergence, dirty worktree counts, active operation, stash count, and
current-branch PR details when GitHub data is available.

```sh
git repo-state
git repo-state --porcelain
git repo-state --json
```

The command does not require GitHub access. If `gh` is unavailable or
unauthenticated, local repository state is still reported.

### `git pr-stack`

Discovers the linear GitHub PR stack connected to a target PR and prints it in
parent-to-child order.

```sh
git pr-stack
git pr-stack 123
git pr-stack feature/my-branch
```

Use `--porcelain` for tab-separated records that other scripts can compose:

```sh
git pr-stack --porcelain
```

If a stack branches into multiple child PRs, the command stops instead of
guessing a landing order.

### `git pr-sync-stack`

Restacks every PR in a linear stack, parent-to-child, without merging anything.

```sh
git pr-sync-stack 123
git pr-sync-stack 123 --dry-run
git pr-sync-stack 123 --base main --no-push
```

The command composes `git pr-stack` and `git pr-restack`. Use `--base` to
override only the root PR's base; child PRs continue to rebase onto their parent
heads.

### `git pr-restack`

Rebases one open PR's head branch onto a target base and pushes with
`--force-with-lease`.

```sh
git pr-restack 123
git pr-restack 123 --base main
git pr-restack 123 --base main --no-push
```

Use `--base` when a parent PR landed and the child should now target the landed
base branch. The command updates the PR base after the local rebase succeeds.
With `--no-push`, it rebases locally and skips remote PR base edits.

### `git pr-land`

Verifies and merges one ready GitHub PR, then syncs the base branch locally and
deletes the local PR branch.

```sh
git pr-land 123
git pr-land 123 --method merge
git pr-land 123 --keep-branch
```

The default merge method is `squash`. The command refuses draft PRs, merge
conflicts, and non-passing checks.

### `git pr-land-stack`

Lands a linear stack of ready GitHub PRs from parent to child.

```sh
git pr-land-stack 123
git pr-land-stack 123 --method merge
git pr-land-stack 123 --dry-run
```

The command composes `git pr-stack`, `git pr-land`, and `git pr-restack`. It
refuses the whole stack before merging anything if any PR is not ready. As each
parent lands, the next child is restacked onto the root base branch before it is
landed.

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

### `git stash-audit`

Lists stashes, shows one stash, drops one explicit stash, or drops stashes whose
origin branch can be inferred and no longer exists locally.

```sh
git stash-audit
git stash-audit --porcelain
git stash-audit --show 0
git stash-audit --drop-obsolete --dry-run
git stash-audit --drop-obsolete --yes
```

Obsolete classification is conservative: a stash is obsolete only when Git's
stash subject identifies a local origin branch and that local branch is gone.

### `git resolve-base`

Resolves the branch point the current branch diverged from and prints it. The
base ref is inferred in order: the configured upstream, a remote default branch
(`origin/HEAD` and friends), then a local default branch (`main`, `master`, or
`trunk`).

```sh
git resolve-base
git resolve-base --ref
git resolve-base --short
```

By default the merge-base commit (the branch point) is printed. Use `--ref` to
print the base ref that resolution selected instead. This is the single source
of branch-base detection that `git absorb-and-rebase` and other commands
compose, so the inference logic lives in one place.

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

Put `bin/` on `PATH`, or link the command files under `bin/` into a directory
on `PATH`. Git discovers executable files named `git-*`, so the installed
commands are invoked as:

```sh
git cleanup-repo
git absorb-and-rebase
git pr-checks
git pr-land
git pr-land-stack
git pr-open
git pr-ready
git pr-restack
git pr-stack
git pr-sync-stack
git repo-state
git resolve-base
git stash-audit
```

For a simple local install:

```sh
./install.sh
```

Set `PREFIX` or `BIN_DIR` to choose another command destination. The installer
also links bundled man pages and completions using standard XDG-style
subdirectories under `PREFIX/share`:

```text
share/man/man1/
share/bash-completion/completions/
share/zsh/site-functions/
share/fish/vendor_completions.d/
```

Override `MAN_DIR`, `BASH_COMPLETION_DIR`, `ZSH_COMPLETION_DIR`, or
`FISH_COMPLETION_DIR` when a shell expects a different local directory. The
repo also keeps the source files in the shdeps-discoverable layout:
`man/man1/*.1` and `completions/*.{bash,zsh,fish}`.

## Test

Run the complete local test suite:

```sh
test/run
```

Or run the focused command test directly:

```sh
test/extras-test
test/git-absorb-and-rebase-test
test/git-resolve-base-test
test/git-cleanup-repo-test
test/git-pr-land-test
test/git-pr-land-stack-test
test/git-pr-ready-test
test/git-pr-restack-test
test/git-pr-stack-test
```

If `git-absorb` is not installed, the test suite verifies the dependency error
path and skips rewrite integration cases.
