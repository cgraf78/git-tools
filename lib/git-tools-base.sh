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

# @brief Resolve one full ref to a commit without conflating absence with an
# operational lookup failure. Sets GT_REF_OID on success; returns 1 when the ref
# is absent and 2 when Git cannot inspect or resolve it.
gt_find_ref_commit() {
  local ref="$1" status=0

  GT_REF_OID=""
  git show-ref --verify --quiet "$ref" || status=$?
  case "$status" in
    0) ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
  GT_REF_OID=$(git rev-parse --verify "$ref^{commit}" 2>/dev/null) || return 2
  [[ -n "$GT_REF_OID" ]] || return 2
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

# Stream a collapsed branch diff and base history through patch-id in a private
# workspace. Returns 0 for an exact patch-id match, 1 for a valid non-match, and
# 2 when any producer, parser, or cleanup operation fails.
_gt_squash_patch_merged() (
  set -o pipefail
  umask 077

  local branch="$1" base="$2" merge_base="$3"
  local _gt_squash_tmp_root="${TMPDIR:-/tmp}" _gt_squash_tmpdir="" \
    _gt_squash_branch_file="" _gt_squash_base_file="" \
    _gt_squash_exit_trap="" || exit 2
  local line="" patch_id="" patch_source="" extra=""
  local branch_patch_id="" native_width=${#branch} branch_records=0 matched=0

  _gt_valid_patch_record() {
    local record="$1" id="$2" source="$3" expected_width="${4:-0}"
    local width=${#id}

    [[ "$record" == "$id $source" ]] || return 1
    case "$width" in
      40 | 64) ;;
      *) return 1 ;;
    esac
    [[ "${#source}" == "$width" ]] || return 1
    [[ "$expected_width" == 0 || "$width" == "$expected_width" ]] || return 1
    [[ "$id" != *[!0-9a-f]* && "$source" != *[!0-9a-f]* ]]
  }

  case "$native_width" in
    40 | 64) ;;
    *) exit 2 ;;
  esac
  [[ "${#base}" == "$native_width" && "${#merge_base}" == "$native_width" ]] ||
    exit 2
  [[ "$branch" != *[!0-9a-f]* && "$base" != *[!0-9a-f]* ]] || exit 2
  [[ "$merge_base" != *[!0-9a-f]* ]] || exit 2

  # Invoked indirectly by the EXIT trap below.
  # shellcheck disable=SC2317,SC2329
  _gt_squash_patch_cleanup() {
    trap - EXIT HUP INT TERM
    local _gt_cleanup_status="$1" _gt_cleanup_branch_path="$2" \
      _gt_cleanup_base_path="$3" _gt_cleanup_tmp_path="$4" \
      _gt_cleanup_failed=0 || exit 2

    if [[ -n "$_gt_cleanup_branch_path" ]]; then
      rm -f -- "$_gt_cleanup_branch_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_base_path" ]]; then
      rm -f -- "$_gt_cleanup_base_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_tmp_path" ]]; then
      rmdir -- "$_gt_cleanup_tmp_path" || _gt_cleanup_failed=1
    fi
    ((_gt_cleanup_failed == 0)) || _gt_cleanup_status=2
    exit "$_gt_cleanup_status"
  }

  trap '_gt_squash_patch_cleanup 2 "$_gt_squash_branch_file" \
    "$_gt_squash_base_file" "$_gt_squash_tmpdir"' HUP INT TERM
  _gt_squash_tmpdir=$(mktemp -d \
    "$_gt_squash_tmp_root/git-tools-patch.XXXXXX") || exit 2
  _gt_squash_branch_file="$_gt_squash_tmpdir/branch.patch-ids"
  _gt_squash_base_file="$_gt_squash_tmpdir/base.patch-ids"
  # Bash 3.2 unwinds function locals before EXIT. Capture the concrete paths in
  # the trap command before replacing the setup-time signal cleanup handlers.
  printf -v _gt_squash_exit_trap \
    '_gt_squash_patch_cleanup "$?" %q %q %q' \
    "$_gt_squash_branch_file" "$_gt_squash_base_file" \
    "$_gt_squash_tmpdir" || exit 2
  # Expanding now is the Bash 3.2 compatibility fix.
  # shellcheck disable=SC2064
  trap "$_gt_squash_exit_trap" EXIT
  trap 'exit 2' HUP INT TERM

  git diff --no-ext-diff --no-textconv --binary --full-index \
    "$merge_base" "$branch" -- |
    git patch-id --stable >"$_gt_squash_branch_file" || exit 2
  git log --no-ext-diff --no-textconv --format='commit %H' \
    -p --binary --full-index "$merge_base..$base" -- |
    git patch-id --stable >"$_gt_squash_base_file" || exit 2

  while IFS= read -r line; do
    IFS=' ' read -r patch_id patch_source extra <<<"$line"
    [[ -z "$extra" ]] || exit 2
    _gt_valid_patch_record \
      "$line" "$patch_id" "$patch_source" "$native_width" || exit 2
    branch_records=$((branch_records + 1))
    branch_patch_id="$patch_id"
  done <"$_gt_squash_branch_file"
  [[ -z "$line" && "$branch_records" == 1 ]] || exit 2

  line=""
  while IFS= read -r line; do
    IFS=' ' read -r patch_id patch_source extra <<<"$line"
    [[ -z "$extra" ]] || exit 2
    _gt_valid_patch_record \
      "$line" "$patch_id" "$patch_source" "$native_width" || exit 2
    [[ "$patch_id" == "$branch_patch_id" ]] && matched=1
  done <"$_gt_squash_base_file"
  [[ -z "$line" ]] || exit 2

  ((matched)) && exit 0
  exit 1
)

# @brief Return 0 when <branch>'s changes are already present in <base> via a
# squash, rebase, or cherry-pick merge.
# These merge methods replay a branch's changes as brand-new commit(s) on the
# base, so the branch tip is never an ancestor of the base and both
# `git merge-base --is-ancestor` and `git branch -d` report it as unmerged.
# Use patch IDs to find candidate equivalence, then require the branch's changed
# paths to match the base tree exactly. Two history shapes must be handled:
#
#   1. Squash merge: the whole branch lands as ONE new commit. Stream the
#      branch's collapsed diff and base history into stable patch-ID records.
#   2. Rebase / cherry-pick merge: each branch commit is replayed separately, so
#      every merge-base..branch commit has an equivalent patch-id in the base.
#      `git cherry` prints '+' for any branch commit NOT yet in the base; none
#      missing (with at least one compared) means the whole branch is applied.
#
# The squash patch ID and per-commit check are complementary: a multi-commit
# squash matches only #1, a multi-commit rebase matches only #2. Returns 1 for a
# branch with no unique diff; that degenerate case has no patch-id to match and
# is already covered by the plain ancestor check.
gt_branch_content_merged() {
  local branch base merge_base tree base_tree cherry squash_status=0
  local branch_delta base_delta missing grep_rc=0

  branch=$(git rev-parse --verify "$1^{commit}" 2>/dev/null) || return 1
  base=$(git rev-parse --verify "$2^{commit}" 2>/dev/null) || return 1
  merge_base=$(git merge-base "$base" "$branch" 2>/dev/null) || return 1
  tree=$(git rev-parse "$branch^{tree}" 2>/dev/null) || return 1
  base_tree=$(git rev-parse "$merge_base^{tree}" 2>/dev/null) || return 1
  [[ "$tree" != "$base_tree" ]] || return 1

  # Patch IDs ignore whitespace and are only a historical match signal. Before
  # relying on one, compare exact raw tree deltas from the common ancestor. The
  # branch delta must be a subset of the base delta, including full object IDs,
  # modes, gitlinks, paths, and deletion states. --no-renames makes rename
  # representation deterministic; quoted output keeps unusual paths on one
  # sortable record per tree entry.
  #
  # Materialize and status-check each producer. Process-substitution failures
  # are not reflected in `comm`'s status, which could otherwise make a failed
  # branch producer look like an empty, fully merged delta.
  branch_delta=$(
    git -c core.quotePath=true diff-tree --no-commit-id --raw -r \
      --no-renames --no-abbrev "$merge_base" "$branch" --
  ) || return 1
  base_delta=$(
    git -c core.quotePath=true diff-tree --no-commit-id --raw -r \
      --no-renames --no-abbrev "$merge_base" "$base" --
  ) || return 1
  branch_delta=$(LC_ALL=C sort <<<"$branch_delta") || return 1
  base_delta=$(LC_ALL=C sort <<<"$base_delta") || return 1
  missing=$(
    LC_ALL=C comm -23 \
      <(printf '%s\n' "$branch_delta") \
      <(printf '%s\n' "$base_delta")
  ) || return 1
  [[ -z "$missing" ]] || return 1

  # Shape 1: squash merge. Keep binary patch streams out of shell variables,
  # observe both sides of each pipeline, and fail closed on operational errors.
  _gt_squash_patch_merged "$branch" "$base" "$merge_base" || squash_status=$?
  case "$squash_status" in
    0) return 0 ;;
    1) ;;
    *) return 1 ;;
  esac

  # Shape 2: rebase / cherry-pick merge.
  cherry=$(git cherry "$base" "$branch" 2>/dev/null) || return 1
  [[ -n "$cherry" ]] || return 1
  grep -q '^+' <<<"$cherry" || grep_rc=$?
  case "$grep_rc" in
    0) return 1 ;;
    1) return 0 ;;
    *) return 1 ;;
  esac
}

# @brief Return 0 when <branch> is merged into <base> by any means.
# True when the branch tip is an ancestor of the base (plain merge / fast
# forward) OR when its changes have matching patch IDs in the base and its exact
# net tree delta is present there (squash, rebase, or cherry-pick merge). This is
# the merge predicate branch-cleanup tooling should use so squash/rebase-merged
# branches are not stranded as "unmerged".
gt_branch_merged() {
  local branch base ancestor_status=0
  branch=$(git rev-parse --verify "$1^{commit}" 2>/dev/null) || return 1
  base=$(git rev-parse --verify "$2^{commit}" 2>/dev/null) || return 1
  git merge-base --is-ancestor "$branch" "$base" 2>/dev/null ||
    ancestor_status=$?
  case "$ancestor_status" in
    0) return 0 ;;
    1) gt_branch_content_merged "$branch" "$base" ;;
    *) return 1 ;;
  esac
}

# @brief Run git after clearing repository-local environment inherited from git.
# @param ... Arguments passed to git.
#
# Git external commands are launched with local state such as GIT_DIR,
# GIT_WORK_TREE, GIT_PREFIX, and GIT_COMMON_DIR exported for the repository that
# resolved the command. That is correct for normal same-repo subcommands, but it
# makes `git -C <other-worktree> ...` inspect the original worktree instead of
# the requested path. Clear exactly the variables Git documents as local before
# crossing to another worktree or repository.
gt_git_without_local_env() {
  local name
  local -a env_args=()

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    env_args+=("-u" "$name")
  done < <(git rev-parse --local-env-vars)

  env "${env_args[@]}" git "$@"
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

# @brief Print the worktree path that owns or reserves the given branch.
#
# A rebase temporarily detaches HEAD while retaining the original branch in
# rebase metadata. Irreversible workflows need this stronger check, while
# ordinary inventory consumers retain the checked-out-only contract above.
gt_worktree_reserving_branch() {
  local branch="$1"
  local line path state_file state_head

  path=$(gt_worktree_for_branch "$branch")
  if [[ -n "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi

  while IFS= read -r line; do
    [[ "$line" == "worktree "* ]] || continue
    path="${line#worktree }"
    for state_file in rebase-merge/head-name rebase-apply/head-name; do
      state_file=$(gt_git_without_local_env -C "$path" rev-parse --git-path "$state_file" 2>/dev/null || true)
      [[ -f "$state_file" ]] || continue
      IFS= read -r state_head <"$state_file" || true
      if [[ "$state_head" == "refs/heads/$branch" ]]; then
        printf '%s\n' "$path"
        return 0
      fi
    done

    state_file=$(gt_git_without_local_env -C "$path" rev-parse --git-path BISECT_START 2>/dev/null || true)
    if [[ -f "$state_file" ]]; then
      IFS= read -r state_head <"$state_file" || true
      if [[ "$state_head" == "$branch" || "$state_head" == "refs/heads/$branch" ]]; then
        printf '%s\n' "$path"
        return 0
      fi
    fi
  done < <(git worktree list --porcelain)
}

# @brief Print the active sequencer operation in a worktree, if any.
gt_worktree_operation() {
  local path="$1"
  local entry label state_path

  while IFS=$'\t' read -r entry label; do
    state_path=$(gt_git_without_local_env -C "$path" rev-parse --git-path "$entry" 2>/dev/null || true)
    [[ -e "$state_path" ]] || continue
    printf '%s\n' "$label"
    return 0
  done <<'EOF'
rebase-merge	rebase
rebase-apply	rebase
MERGE_HEAD	merge
CHERRY_PICK_HEAD	cherry-pick
REVERT_HEAD	revert
BISECT_START	bisect
EOF
}
