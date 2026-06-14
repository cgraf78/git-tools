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
