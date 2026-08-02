# git-tools

![Tests](https://github.com/cgraf78/git-tools/actions/workflows/test.yml/badge.svg?branch=main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D3.2-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Small Git workflow tools. Runtime support requires Bash 3.2 or newer and Git
2.29 or newer.

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

The command refuses dirty worktrees, refuses to open from the base branch, and
rejects a stale local base branch when it differs from the exact remote base OID.
Pull request creation and structured default-branch discovery are pinned to the
host and owner/repository derived from the current checkout. Ambient `GH_REPO`
and `GH_HOST` values, a foreign remote named `origin`, and local remote-HEAD
configuration cannot redirect them. The base fetch remote is validated against
that checkout repository, then the exact `refs/heads/<base>` source is fetched
through its validated URL without applying the remote's fetch refspecs or
importing tags. The feature push target is resolved independently;
fork heads are qualified as `owner:branch`, so a base branch tracking upstream
cannot redirect the feature push upstream.
The feature branch is pushed by immutable OID through the captured validated
URL, then its remote OID is verified. Upstream tracking is written locally only
after the named remote is revalidated against that captured URL; a concurrent
configuration change leaves the pushed branch intact but aborts PR creation
with a tracking-incomplete diagnostic.
The remote head is checked again immediately before creation. After GitHub
returns, the created PR's canonical repository, head and base refs, head
repository, cross-repository state, and head OID must match the requested
topology. A PR created during a server-side race is reported with its URL as an
actionable nonzero state instead of clean success.

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
unauthenticated, local repository state is still reported. When PR data is
available, lookup is pinned to the checkout repository.

### `git pr-stack`

Discovers the linear GitHub PR stack connected to a target PR and prints it in
parent-to-child order.

```sh
git pr-stack
git pr-stack 123
git pr-stack feature/my-branch
```

Use `--porcelain` for the original tab-separated schema-v1 records that other
scripts can compose. Its nine columns remain fixed as `kind`, `index`, `number`,
`base`, `head`, `ready`, `reason`, `checks`, and `url`. Use `--porcelain=v2`
when exact-operation metadata is required; v2 appends `head_oid`,
`head_repository`, and `cross_repository`.

```sh
git pr-stack --porcelain
git pr-stack --porcelain=v2
```

If a stack branches, contains a cycle, or has multiple same-repository PRs for
one parent head, the command stops instead of guessing a landing order. URL
targets must belong to the current GitHub repository. Discovery fetches one
sentinel beyond its 200-PR safety cap and fails closed instead of returning a
truncated stack. Repository identity is derived with ambient GitHub CLI routing
removed, and every list, view, and checks request is pinned to that identity.
Structured records must keep their number, canonical URL, draft/cross-repository
flags, canonical 40- or 64-digit lowercase hexadecimal head OID, head
repository, and head/base refs internally consistent. Explicit
numeric and URL targets must resolve back to the same pull request number;
branch targets must resolve back to that exact head branch.
The target's independently viewed topology must also match its inventory record;
a concurrent retarget stops discovery instead of yielding a stale stack.

### `git pr-sync-stack`

Restacks every PR in a linear stack, parent-to-child, without merging anything.

```sh
git pr-sync-stack 123
git pr-sync-stack 123 --dry-run
git pr-sync-stack 123 --base main --no-push
```

The command composes `git pr-stack` and `git pr-restack`. Use `--base` to
override only the root PR's base; child PRs continue to rebase onto their parent
heads. Qualified PR URLs and expected topology are preserved between discovery
and every restack. Each child uses its parent's original head OID as the
immutable fork boundary, and every pushed rewrite must match both the local
branch and a fresh GitHub PR record before the next restack begins. In
`--no-push` mode, each rewritten local parent OID becomes the child's exact
local base instead of falling back to a stale remote parent branch.

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

Before rebasing, the command separately resolves one fetch URL for the
checkout/base repository and one push remote whose sole effective push URL
matches the structured PR head repository. It requires the live head OID from
that exact push URL to equal the PR record. Named base and fork branches are
fetched as exact `refs/heads/*` sources through the validated base-repository
URL, without named-remote refspecs or tags, and converted to immutable commit
OIDs before rebase. Internal commit handoffs use an explicit `oid:<hex>`
namespace, so hex-looking branch names remain unambiguous branches. The PR head
is fetched directly from the validated head URL and must yield the same OID
before checkout. The push transport is pinned against further Git URL
rewrites and uses an explicit lease. Missing heads, multiple push URLs,
ambiguous remotes, rewrite mismatches, and concurrent updates fail closed.
After pushing, GitHub must report the exact local rewritten OID before the
command edits the PR base.
The checked-out PR branch, `HEAD`, worktree cleanliness, and expected OID are
revalidated after checkout and immediately before rebase and push. The push
source is the captured immutable OID, so checkout hooks or concurrent local ref
updates cannot inject another commit into the force-push.
Credential-bearing HTTP URLs, query/fragment suffixes, unsafe git-config key
bytes, and invalid GitHub owner/repository components are rejected before exact
transport helpers run. SSH usernames in normal `user@host:path` remotes remain
supported.
When called by stack orchestration, the command binds the discovered PR number,
head, head OID, base, head repository, cross-repository state, and canonical URL
at every rebase, push, and base-edit boundary.

A plain rebase replays everything since the merge base, which re-applies a
squash-merged parent's commits and conflicts. Use `--fork <ref>` to name the old
base so its commits are dropped instead (`git rebase --onto <base> <ref>`):

```sh
git pr-restack 123 --base main --fork parent-branch
```

### `git pr-land`

Verifies and merges one ready GitHub PR and syncs the base branch locally. Local
and remote PR heads are retained and reported with exact OIDs for manual cleanup.

```sh
git pr-land 123
git pr-land 123 --method merge
git pr-land 123 --keep-branch
```

The default merge method is `squash`. The command refuses draft PRs, merge
conflicts, non-passing checks, and local base branches that cannot fast-forward.
URL targets are repository-qualified before PR lookup, so a same-number PR URL
from another repository cannot redirect the merge. Numeric and branch targets,
checks, merge, and post-merge verification are also pinned to the checkout
repository regardless of ambient GitHub CLI routing.
Returned structured data must bind the requested number to its canonical URL
and describe a coherent same-repository or fork head before any merge begins.
The base fetch URL is validated against the checkout repository before the
irreversible merge. Preflight and post-merge synchronization fetch only the
exact `refs/heads/<base>` source and merge its captured OID; named-remote
refspecs, tracking refs, and colliding tags are not trusted. Stack-driven
landing revalidates the discovered topology
immediately before merging, and post-merge verification remains bound to that
same PR number and topology. The merge request is pinned with GitHub's
`--match-head-commit`, and an exactly mapped live remote head must equal the
structured PR head OID.
An already-checked-out base is synchronized in its owning worktree. If GitHub
reports an error after completing the server-side merge,
the command rechecks structured PR state and identifies any remaining work as
incomplete cleanup instead of incorrectly reporting that the merge failed.
Local deletion is intentionally manual because Git has no portable primitive
that serializes branch deletion with a checkout that already resolved the ref
but has not yet updated its worktree `HEAD`. Remote deletion is also manual: a
repository-scoped open-PR query cannot prove that a fork head is unused by PRs
targeting another base repository, and a new consumer can appear after any
query. `--keep-branch` remains accepted for compatibility; all branches are kept.

### `git pr-land-stack`

Lands a linear stack of ready GitHub PRs from parent to child.

```sh
git pr-land-stack 123
git pr-land-stack 123 --method merge
git pr-land-stack 123 --dry-run
```

The command composes `git pr-stack`, `git pr-land`, and `git pr-restack`. It
refuses the whole stack before merging anything if any PR is not ready. URL
targets and every discovered PR must belong to the current GitHub repository.
Qualified URLs are retained across stack, land, restack, and readiness polling
handoffs.
As each parent lands, the next child is restacked onto the root base branch
before it is landed. The restack passes the just-landed parent's original head
OID as `git pr-restack --fork`, so squash-merged parent commits drop out cleanly
instead of conflicting
when they are replayed onto the root base. This works for every merge method.
After each restack, the next expected topology accepts the rewritten head OID
only when it matches both the local branch and a fresh GitHub PR record.
Local and remote heads are retained for manual cleanup. Stack topology uses
repository identity as well as branch names, so a same-named fork head cannot
be mistaken for a base-repository parent. Cycles and ambiguous parents fail
closed.
Every land and restack handoff re-reads the live PR and requires its
mutation-relevant topology to match the expected stack state. Retargeting during
discovery, a parent action, or readiness polling stops before the next mutation.

### `git branch-audit`

Lists local branches with their state relative to the default branch: last
commit age, ahead/behind counts, merged-into-default status, and the open PR
number when GitHub data is available. The default branch is the reference point
and is omitted from the listing.

```sh
git branch-audit
git branch-audit --porcelain
git branch-audit --base main
```

Use `--porcelain` for stable tab-separated `branch` records (name, merged,
ahead, behind, PR number, commit timestamp, and a `gone` flag for deleted
upstreams) that other scripts can filter.

PR lookup is best-effort: when `gh` is missing or unauthenticated, the audit
still reports local branch state and omits PR numbers.

A branch counts as merged when its pinned tip is an ancestor of a pinned default
branch snapshot, or when patch IDs identify a replay and the branch's exact net
tree delta is present in that snapshot. The delta includes full object IDs,
types, modes, paths, and deletions. This recognizes squash-, rebase-, and
cherry-pick-merged branches without treating patch-ID-equivalent but
byte-distinct content as merged. If the default branch later changes one of the
same paths, the branch is kept conservatively.

Use `--drop-merged` to report exact local cleanup candidates, including each
branch's current OID. It intentionally does not delete branches: worktree
inventory and lock observations cannot prove that another Git process has not
already resolved a branch for checkout. The compatibility option remains
confirmation-gated with `--yes` unless `--dry-run` is also given:

```sh
git branch-audit --drop-merged --dry-run
git branch-audit --drop-merged --yes
```

### `git cleanup-repo`

Resolves the remote's fetch endpoint, fetches the exact default-branch ref, then
deletes stale local branches whose exact OIDs are proven merged.

```sh
git cleanup-repo
```

By default the command deletes local branches that are already merged into the
base branch. This includes squash-, rebase-, and cherry-pick-merged branches:
patch IDs identify candidate matches, and the exact net tree delta must also be
present in a pinned base snapshot. A clean squash merge is therefore recognized
even though its commits are not ancestors of the base, while byte-, mode-, or
later same-path differences are excluded. The complete branch and upstream-state
inventory is validated before the first mutation. Each candidate is rechecked
before deletion, and the ref is deleted only if it still has the exact proven
OID. Use `--gone` to also delete branches whose existing upstream-tracking state
is gone. The command deliberately does not run configured fetch or prune
mappings; refresh other remote-tracking state separately when needed.

Base updates do not depend on configured fetch refspecs or short ref names. The
command pins exactly `refs/heads/<base>` from the resolved endpoint, fetches it
without tags or remote-tracking ref updates, validates its native SHA-1 or
SHA-256 object ID, and checks the local fast-forward relationship before
switching branches. It then creates or
fast-forwards the base using that same OID. A divergent base fails before the
current branch or local base is changed. Dry-run uses isolated temporary object
storage, so it leaves no permanent objects or refs behind. The command retains
the single raw configured fetch URL for both remote inspection and fetch, which
lets Git apply any `insteadOf` rewrite exactly once per operation. Remotes with
zero or multiple fetch URLs are rejected because there is no single endpoint to
pin.

Use `--all` to delete every local branch except the base branch regardless of
merge state:

```sh
git cleanup-repo --all
```

Branches checked out or reserved by another worktree are skipped by default.
Use `--remove-worktrees` to remove a linked worktree before deleting its branch.
Only worktrees with no uncommitted, ignored, or index-hidden local content and
no active rebase/merge/cherry-pick/revert/bisect operation are eligible, and
removal never uses `--force`:

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
rebase/merge/cherry-pick/revert. Git cannot atomically combine worktree
reservation checks with ref deletion, so do not create, switch, or mutate
worktrees concurrently with cleanup. The command rechecks observable state and
uses expected-old-OID ref deletion to preserve a branch that advances during
cleanup.

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

### `git worktree-audit`

Reports state across every worktree: path, checked-out branch, dirty state, last
commit age, and the open PR number when GitHub data is available. Worktrees whose
directory no longer exists are reported as orphans.

```sh
git worktree-audit
git worktree-audit --porcelain
```

Use `--porcelain` for stable tab-separated `worktree` records (path, branch,
dirty, orphan, PR number, HEAD commit, commit timestamp). Dirty state is
`unknown` for bare or orphaned worktrees, which have no working tree to inspect.
PR lookup is best-effort and degrades to local-only output without `gh`.

Use `--prune-orphan` to prune worktrees whose directory no longer exists. With
`--dry-run` it prints what would be pruned:

```sh
git worktree-audit --prune-orphan --dry-run
git worktree-audit --prune-orphan
```

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
- remote default branches such as `origin/HEAD`, `origin/main`,
  `origin/master`, or `origin/trunk`
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
git branch-audit
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
git worktree-audit
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

The runner uses four workers by default. Set `GIT_TOOLS_TEST_JOBS` to a
positive integer to tune concurrency, or to `1` for serial execution.

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
