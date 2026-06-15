#!/usr/bin/env bash
# Shared helpers for resolving a branch's base: the default branch and the
# branch point (merge base) a topic branch diverged from.
#
# These helpers are intentionally free of any GitHub or gh dependency and never
# exit on their own. They return non-zero on failure so callers can decide
# whether an unresolved base is fatal (cleanup-repo) or merely "unknown"
# (repo-state). Keeping them side-effect free lets both lib-sourcing commands
# and standalone scripts compose them.

# @brief Print the repository's default branch short name.
# @param remote Remote to consult for the default head (defaults to origin).
# Resolution order: <remote>/HEAD symbolic ref, then <remote>/{main,master,trunk}
# or a matching local branch. Returns 1 when none can be determined.
gt_default_branch() {
  local remote="${1:-origin}" ref candidate

  ref=$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)
  if [[ "$ref" == "$remote/"* ]]; then
    printf '%s\n' "${ref#"$remote"/}"
    return 0
  fi

  for candidate in main master trunk; do
    if git show-ref --verify --quiet "refs/remotes/$remote/$candidate" ||
      git show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# @brief Print the commit id for a revision when it resolves to a commit.
gt_commit() {
  git rev-parse --verify -q "$1^{commit}" 2>/dev/null
}

# @brief Print the merge base of HEAD and the given ref.
gt_merge_base() {
  local base
  base=$(git merge-base HEAD "$1" 2>/dev/null) || return 1
  [[ -n "$base" ]] || return 1
  printf '%s\n' "$base"
}

# @brief Print the branch point of HEAD relative to the given ref.
# fork-point handles the common case where an upstream branch was rebased and
# Git's reflog can identify the original branch point more accurately than a
# plain graph merge-base. Fall back to merge-base for repos without reflogs.
gt_branch_base() {
  git merge-base --fork-point "$1" HEAD 2>/dev/null ||
    gt_merge_base "$1"
}

# @brief Print candidate refs for the remote default branch, most specific
# first. Output may contain duplicates; callers dedupe.
gt_remote_default_candidates() {
  local remote ref

  printf '%s\n' origin/HEAD
  while IFS= read -r ref; do
    case "$ref" in
      */HEAD) printf '%s\n' "$ref" ;;
    esac
  done < <(git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null)

  printf '%s\n' origin/main origin/master
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    printf '%s\n' "$remote/main" "$remote/master"
  done < <(git remote 2>/dev/null)
}

# @brief Resolve the branch point of HEAD.
# On success prints "<ref>\t<merge-base-commit>" where <ref> is the base ref
# that won resolution and <merge-base-commit> is HEAD's branch point against it.
# Resolution order mirrors a topic-branch workflow: the configured upstream,
# then a remote default branch, then a local default branch. Returns 1 when no
# base can be determined.
gt_resolve_base() {
  local ref base candidate seen=$'\n'

  ref=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
  if [[ -n "$ref" ]] && base=$(gt_branch_base "$ref"); then
    printf '%s\t%s\n' "$ref" "$base"
    return 0
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    case "$seen" in
      *$'\n'"$candidate"$'\n'*) continue ;;
    esac
    seen="${seen}${candidate}"$'\n'
    gt_commit "$candidate" >/dev/null || continue
    if base=$(gt_branch_base "$candidate"); then
      printf '%s\t%s\n' "$candidate" "$base"
      return 0
    fi
  done < <(gt_remote_default_candidates)

  for candidate in main master trunk; do
    gt_commit "$candidate" >/dev/null || continue
    if base=$(gt_branch_base "$candidate"); then
      printf '%s\t%s\n' "$candidate" "$base"
      return 0
    fi
  done

  return 1
}

# @brief Return 0 when <branch>'s changes are already present in <base> via a
# squash, rebase, or cherry-pick merge.
# These merge methods replay a branch's changes as brand-new commit(s) on the
# base, so the branch tip is never an ancestor of the base and both
# `git merge-base --is-ancestor` and `git branch -d` report it as unmerged.
# Detect content-equivalence by patch-id instead. Two shapes must be handled:
#
#   1. Squash merge: the whole branch lands as ONE new commit. Collapse the
#      branch's entire diff (merge-base..branch) into a single probe commit and
#      look for its patch-id in the base.
#   2. Rebase / cherry-pick merge: each branch commit is replayed separately, so
#      every merge-base..branch commit has an equivalent patch-id in the base.
#      `git cherry` prints '+' for any branch commit NOT yet in the base; none
#      missing (with at least one compared) means the whole branch is applied.
#
# The squash probe and the per-commit check are complementary: a multi-commit
# squash matches only #1, a multi-commit rebase matches only #2. Returns 1 for a
# branch with no unique diff; that degenerate case has no patch-id to match and
# is already covered by the plain ancestor check.
gt_branch_content_merged() {
  local branch="$1" base="$2"
  local merge_base tree base_tree probe cherry

  merge_base=$(git merge-base "$base" "$branch" 2>/dev/null) || return 1
  tree=$(git rev-parse "$branch^{tree}" 2>/dev/null) || return 1
  base_tree=$(git rev-parse "$merge_base^{tree}" 2>/dev/null) || return 1
  [[ "$tree" != "$base_tree" ]] || return 1

  # Shape 1: squash merge.
  probe=$(git commit-tree "$tree" -p "$merge_base" -m gt-content-probe 2>/dev/null) ||
    return 1
  [[ "$(git cherry "$base" "$probe" 2>/dev/null)" == "-"* ]] && return 0

  # Shape 2: rebase / cherry-pick merge.
  cherry=$(git cherry "$base" "$branch" 2>/dev/null) || return 1
  [[ -n "$cherry" ]] || return 1
  if grep -q '^+' <<<"$cherry"; then
    return 1
  fi
  return 0
}

# @brief Return 0 when <branch> is merged into <base> by any means.
# True when the branch tip is an ancestor of the base (plain merge / fast
# forward) OR when its changes are already in the base by patch-id (squash,
# rebase, or cherry-pick merge). This is the merge predicate branch-cleanup
# tooling should use so squash/rebase-merged branches are not stranded as
# "unmerged".
gt_branch_merged() {
  local branch="$1" base="$2"
  git merge-base --is-ancestor "$branch" "$base" 2>/dev/null && return 0
  gt_branch_content_merged "$branch" "$base"
}

# @brief Print the worktree path that has the given branch checked out.
# Prints nothing and returns 0 when the branch is not checked out in any
# worktree; callers test for an empty result.
gt_worktree_for_branch() {
  local branch="$1"
  git worktree list --porcelain |
    awk -v want="branch refs/heads/$branch" '
      /^worktree / {
        path = substr($0, 10)
        next
      }
      $0 == want {
        print path
        exit
      }
    '
}
