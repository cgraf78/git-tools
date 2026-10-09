#!/usr/bin/env bash
# Shared helpers for resolving a branch's base: the default branch and the
# branch point (merge base) a topic branch diverged from.
#
# These helpers are intentionally free of any GitHub or gh dependency and never
# exit on their own. They return non-zero on failure so callers can decide
# whether an unresolved base is fatal (cleanup-repo) or merely "unknown"
# (repo-state). Keeping them side-effect free lets both lib-sourcing commands
# and standalone scripts compose them.

# Every `git` this library runs is Git's own binary, not a PATH wrapper.
_gt_lib_dir=${BASH_SOURCE[0]%/*}
[[ "$_gt_lib_dir" != "${BASH_SOURCE[0]}" ]] || _gt_lib_dir=.
# shellcheck source=lib/git-tools-git.sh
. "$_gt_lib_dir/git-tools-git.sh" || return 1
unset _gt_lib_dir

# Cache Git's documented repository-local environment inventory within this
# library load. Reset on source so inherited/exported private state cannot skip
# the safety probe or retain GIT_DIR/GIT_WORK_TREE across repositories.
_GT_GIT_LOCAL_ENV_VARS_READY=0
_GT_GIT_LOCAL_ENV_VARS=""
# Set by gt_record_uninspectable_worktree for gt_uninspectable_worktree_hint;
# an inherited value must not name a worktree this run never inspected.
GT_WORKTREE_FAILED_PATH=""
GT_WORKTREE_FAILED_LOCKED=0

# @brief Print the repository's default branch short name.
# @param remote Remote to consult for the default head (defaults to origin).
# Resolution order: <remote>/HEAD symbolic ref, then <remote>/{main,master,trunk}
# or a matching local branch. Returns 1 when none can be determined.
gt_default_branch() {
  local remote="${1:-origin}" ref candidate

  # Full ref names: --short would render an ambiguous name (one a tag or
  # local branch shares) as remotes/<remote>/<branch>.
  ref=$(git symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null || true)
  if [[ "$ref" == "refs/remotes/$remote/"?* ]]; then
    printf '%s\n' "${ref#"refs/remotes/$remote"/}"
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

# @brief Resolve an exact remote ref with status-preserving ls-remote semantics.
# Sets GT_REMOTE_REF_OID on success; returns 1 when absent and 2 for transport,
# protocol, or malformed-output failures.
gt_find_remote_ref() {
  local remote="$1" ref="$2" output status=0 oid found_ref extra

  GT_REMOTE_REF_OID=""
  output=$(git ls-remote --exit-code --refs "$remote" "$ref" 2>/dev/null) || status=$?
  case "$status" in
    0) ;;
    2) return 1 ;;
    *) return 2 ;;
  esac
  IFS=$'\t' read -r oid found_ref extra <<<"$output"
  [[ -n "$oid" && "$found_ref" == "$ref" && -z "$extra" ]] || return 2
  [[ "$output" != *$'\n'* ]] || return 2
  # Consumed by callers in the PR command scripts after this sourced helper
  # returns; ShellCheck cannot follow that cross-file global result.
  # shellcheck disable=SC2034
  GT_REMOTE_REF_OID=$oid
}

# @brief Create an unpredictable one-shot URL alias for an exact transport.
_gt_make_exact_url_alias() {
  local nonce_dir nonce

  nonce_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-tools-url.XXXXXX") || return 1
  nonce=${nonce_dir##*/}
  rmdir "$nonce_dir" || return 1
  GT_EXACT_URL_ALIAS="https://git-tools.invalid/$nonce"
}

# @brief Reject transport strings that cannot be embedded safely in git -c URL
# keys. HTTP credentials are never accepted; SSH usernames remain valid.
gt_exact_url_is_safe() {
  local url="$1" rest authority host path="" owner repo userinfo=""

  [[ -n "$url" && "$url" != -* ]] || return 1
  case "$url" in
    *$'\n'* | *$'\r'* | *$'\t'* | *' '* | *'='* | *'?'* | *'#'*) return 1 ;;
  esac
  case "$url" in
    http://* | https://*)
      rest=${url#*://}
      authority=${rest%%/*}
      [[ "$authority" != "$rest" && "$authority" != *@* ]] || return 1
      host=$authority
      path=${rest#*/}
      ;;
    ssh://*)
      rest=${url#ssh://}
      authority=${rest%%/*}
      [[ "$authority" != "$rest" ]] || return 1
      host=${authority##*@}
      path=${rest#*/}
      if [[ "$authority" == *@* ]]; then
        userinfo=${authority%@*}
        [[ "$userinfo" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
      fi
      ;;
    *@*:*)
      authority=${url%%:*}
      userinfo=${authority%@*}
      host=${authority##*@}
      path=${url#*:}
      [[ "$userinfo" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
      ;;
    /* | ./* | ../* | file://*) return 0 ;;
    *) return 1 ;;
  esac
  [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
  [[ "$host" != *..* ]] || return 1
  path=${path#/}
  path=${path%/}
  path=${path%.git}
  owner=${path%%/*}
  repo=${path#*/}
  [[ -n "$owner" && -n "$repo" && "$repo" != */* ]] || return 1
  [[ "$owner" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  [[ "$repo" =~ ^[A-Za-z0-9._-]+$ && "$repo" != . && "$repo" != .. ]]
}

# @brief Inspect one already-expanded URL without allowing another URL rewrite.
gt_find_remote_ref_exact_url() {
  local url="$1" ref="$2" alias output status=0 oid found_ref extra

  GT_REMOTE_REF_OID=""
  gt_exact_url_is_safe "$url" || return 2
  _gt_make_exact_url_alias || return 2
  alias=$GT_EXACT_URL_ALIAS
  output=$(git \
    -c "url.$url.insteadOf=$alias" \
    -c "url.$url.pushInsteadOf=$alias" \
    ls-remote --exit-code --refs "$alias" "$ref" 2>/dev/null) || status=$?
  case "$status" in
    0) ;;
    2) return 1 ;;
    *) return 2 ;;
  esac
  IFS=$'\t' read -r oid found_ref extra <<<"$output"
  [[ -n "$oid" && "$found_ref" == "$ref" && -z "$extra" ]] || return 2
  [[ "$output" != *$'\n'* ]] || return 2
  # shellcheck disable=SC2034 # consumed by PR command scripts
  GT_REMOTE_REF_OID=$oid
}

# @brief Push to one already-expanded URL without allowing another URL rewrite.
gt_push_exact_url() {
  local url="$1" alias
  shift
  gt_exact_url_is_safe "$url" || return 1
  _gt_make_exact_url_alias || return 1
  alias=$GT_EXACT_URL_ALIAS
  git \
    -c "url.$url.insteadOf=$alias" \
    -c "url.$url.pushInsteadOf=$alias" \
    push "$alias" "$@"
}

# @brief Fetch one named ref from an already-expanded URL without allowing
# another URL rewrite. Sets GT_FETCHED_REF_OID to the fetched commit OID.
gt_fetch_ref_exact_url() {
  local url="$1" ref="$2" alias oid

  GT_FETCHED_REF_OID=""
  gt_exact_url_is_safe "$url" || return 1
  _gt_make_exact_url_alias || return 1
  alias=$GT_EXACT_URL_ALIAS
  git \
    -c "url.$url.insteadOf=$alias" \
    -c "url.$url.pushInsteadOf=$alias" \
    fetch --quiet --no-tags "$alias" "$ref" || return 1
  oid=$(git rev-parse --verify "FETCH_HEAD^{commit}" 2>/dev/null) || return 1
  [[ -n "$oid" ]] || return 1
  # shellcheck disable=SC2034 # consumed by PR command scripts
  GT_FETCHED_REF_OID=$oid
}

# @brief Snapshot and fetch one exact remote ref, requiring both operations to
# resolve the same immutable commit. Sets GT_EXACT_REF_OID; returns 1 when the
# ref is absent and 2 for transport, malformed output, or concurrent movement.
gt_snapshot_and_fetch_ref_exact_url() {
  local url="$1" ref="$2" snapshot status=0

  GT_EXACT_REF_OID=""
  gt_find_remote_ref_exact_url "$url" "$ref" || status=$?
  case "$status" in
    0) snapshot=$GT_REMOTE_REF_OID ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
  gt_fetch_ref_exact_url "$url" "$ref" || return 2
  [[ "$GT_FETCHED_REF_OID" == "$snapshot" ]] || return 2
  # shellcheck disable=SC2034 # consumed by PR command scripts
  GT_EXACT_REF_OID=$snapshot
}

# @brief Print the merge base of HEAD and the given ref.
gt_merge_base() {
  local base
  base=$(git merge-base HEAD "$1" 2>/dev/null) || return 1
  [[ -n "$base" ]] || return 1
  printf '%s\n' "$base"
}

# @brief Print HEAD's branch point relative to one exact ref snapshot.
# fork-point handles rebased upstreams more accurately than a graph merge-base.
# Validate the ref after consulting its reflog; when no fork point exists, bind
# the graph calculation to the commit captured before lookup. Returns 1 for an
# absent ref or unrelated history and 2 for lookup failures or concurrent ref
# movement.
gt_branch_base() {
  local ref="$1" expected_oid head_oid base status=0 ref_status=0

  gt_find_ref_commit "$ref" || ref_status=$?
  case "$ref_status" in
    0) expected_oid=$GT_REF_OID ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
  head_oid=$(git rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || return 2

  base=$(git merge-base --fork-point "$ref" "$head_oid" 2>/dev/null) ||
    status=$?
  case "$status" in
    0)
      ref_status=0
      gt_find_ref_commit "$ref" || ref_status=$?
      [[ "$ref_status" == 0 && "$GT_REF_OID" == "$expected_oid" ]] ||
        return 2
      ;;
    1)
      status=0
      base=$(git merge-base "$head_oid" "$expected_oid" 2>/dev/null) ||
        status=$?
      case "$status" in
        0) ;;
        1) return 1 ;;
        *) return 2 ;;
      esac
      ;;
    *) return 2 ;;
  esac
  [[ -n "$base" ]] || return 2
  printf '%s\n' "$base"
}

# @brief Set GT_UPSTREAM_REF to HEAD's configured full upstream ref.
# An empty result is a valid branch without an upstream. Returns 1 for detached
# HEAD and 2 when Git cannot inventory the current branch.
_gt_find_head_upstream() {
  local head_ref records record_ref upstream extra found=0 status=0

  GT_UPSTREAM_REF=""
  head_ref=$(git symbolic-ref -q HEAD 2>/dev/null) || status=$?
  case "$status" in
    0) ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
  records=$(git for-each-ref \
    --format='%(refname)%09%(upstream)' "$head_ref" 2>/dev/null) || return 2
  while IFS=$'\t' read -r record_ref upstream extra; do
    [[ "$record_ref" == "$head_ref" ]] || continue
    [[ "$found" == 0 && -z "$extra" ]] || return 2
    GT_UPSTREAM_REF=$upstream
    found=1
  done <<<"$records"
  [[ "$found" == 1 ]] || return 2
}

# @brief Print candidate refs for the remote default branch, most specific
# first. Output may contain duplicates; callers dedupe.
gt_remote_default_candidates() {
  local remote ref refs remotes

  printf '%s\n' refs/remotes/origin/HEAD
  refs=$(git for-each-ref --format='%(refname)' refs/remotes 2>/dev/null) ||
    return 1
  while IFS= read -r ref; do
    case "$ref" in
      refs/remotes/*/HEAD) printf '%s\n' "$ref" ;;
    esac
  done <<<"$refs"

  printf '%s\n' refs/remotes/origin/main refs/remotes/origin/master \
    refs/remotes/origin/trunk
  remotes=$(git remote 2>/dev/null) || return 1
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    printf '%s\n' "refs/remotes/$remote/main" \
      "refs/remotes/$remote/master" "refs/remotes/$remote/trunk"
  done <<<"$remotes"
}

# @brief Resolve the branch point of HEAD.
# On success prints "<ref>\t<merge-base-commit>" where <ref> is the base ref
# that won resolution and <merge-base-commit> is HEAD's branch point against it.
# Resolution order mirrors a topic-branch workflow: the configured upstream,
# then a remote default branch, then a local default branch. Returns 1 when no
# base can be determined.
gt_resolve_base() {
  local ref base candidate display candidates base_status
  local seen=$'\n'

  _gt_find_head_upstream || return 1
  ref=$GT_UPSTREAM_REF
  if [[ -n "$ref" ]]; then
    base_status=0
    base=$(gt_branch_base "$ref") || base_status=$?
    case "$base_status" in
      0)
        display="$ref"
        display=${display#refs/remotes/}
        display=${display#refs/heads/}
        printf '%s\t%s\n' "$display" "$base"
        return 0
        ;;
      1) ;;
      *) return 1 ;;
    esac
  fi

  candidates=$(gt_remote_default_candidates) || return 1
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    case "$seen" in
      *$'\n'"$candidate"$'\n'*) continue ;;
    esac
    seen="${seen}${candidate}"$'\n'
    base_status=0
    base=$(gt_branch_base "$candidate") || base_status=$?
    case "$base_status" in
      0)
        display=${candidate#refs/remotes/}
        printf '%s\t%s\n' "$display" "$base"
        return 0
        ;;
      1) continue ;;
      *) return 1 ;;
    esac
  done <<<"$candidates"

  for candidate in main master trunk; do
    ref="refs/heads/$candidate"
    base_status=0
    base=$(gt_branch_base "$ref") || base_status=$?
    case "$base_status" in
      0)
        printf '%s\t%s\n' "$candidate" "$base"
        return 0
        ;;
      1) continue ;;
      *) return 1 ;;
    esac
  done

  return 1
}

# Stream a collapsed branch diff and first-parent base history through patch-id
# in a private workspace. Patch IDs only locate candidates: a match is accepted
# after the branch's raw delta exactly matches the candidate commit's raw delta
# from its first parent. Returns 0 for an exact historical match, 1 for a valid
# non-match, and 2 when any producer, parser, comparison, or cleanup fails.
_gt_squash_patch_merged() (
  set -o pipefail
  umask 077
  local LC_ALL=C

  local branch="$1" base="$2" merge_base="$3"
  local _gt_squash_tmp_root="${TMPDIR:-/tmp}" _gt_squash_tmpdir="" \
    _gt_squash_branch_file="" _gt_squash_base_file="" \
    _gt_squash_path_file="" \
    _gt_squash_branch_delta_file="" _gt_squash_candidate_delta_file="" \
    _gt_squash_comparison_error_file="" \
    _gt_squash_exit_trap="" || exit 2
  local line="" patch_id="" patch_source="" extra=""
  local candidate="" comparison_status=0 path=""
  local branch_patch_id="" native_width=${#branch} branch_records=0 matched=0
  local path_filter=1 pathspec_bytes=0 pathspec_count=0
  local pathspec_limit=32768 pathspec_count_limit=256
  local -a base_pathspec_args=(--)

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
      _gt_cleanup_path_path="$5" _gt_cleanup_branch_delta_path="$6" \
      _gt_cleanup_candidate_delta_path="$7" \
      _gt_cleanup_comparison_error_path="$8" \
      _gt_cleanup_failed=0 || exit 2

    if [[ -n "$_gt_cleanup_branch_path" ]]; then
      rm -f -- "$_gt_cleanup_branch_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_base_path" ]]; then
      rm -f -- "$_gt_cleanup_base_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_path_path" ]]; then
      rm -f -- "$_gt_cleanup_path_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_branch_delta_path" ]]; then
      rm -f -- "$_gt_cleanup_branch_delta_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_candidate_delta_path" ]]; then
      rm -f -- "$_gt_cleanup_candidate_delta_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_comparison_error_path" ]]; then
      rm -f -- "$_gt_cleanup_comparison_error_path" || _gt_cleanup_failed=1
    fi
    if [[ -n "$_gt_cleanup_tmp_path" ]]; then
      rmdir -- "$_gt_cleanup_tmp_path" || _gt_cleanup_failed=1
    fi
    ((_gt_cleanup_failed == 0)) || _gt_cleanup_status=2
    exit "$_gt_cleanup_status"
  }

  trap '_gt_squash_patch_cleanup 2 "$_gt_squash_branch_file" \
    "$_gt_squash_base_file" "$_gt_squash_tmpdir" \
    "$_gt_squash_path_file" \
    "$_gt_squash_branch_delta_file" \
    "$_gt_squash_candidate_delta_file" \
    "$_gt_squash_comparison_error_file"' HUP INT TERM
  _gt_squash_tmpdir=$(mktemp -d \
    "$_gt_squash_tmp_root/git-tools-patch.XXXXXX") || exit 2
  _gt_squash_branch_file="$_gt_squash_tmpdir/branch.patch-ids"
  _gt_squash_base_file="$_gt_squash_tmpdir/base.patch-ids"
  _gt_squash_path_file="$_gt_squash_tmpdir/branch.paths"
  _gt_squash_branch_delta_file="$_gt_squash_tmpdir/branch.raw"
  _gt_squash_candidate_delta_file="$_gt_squash_tmpdir/candidate.raw"
  _gt_squash_comparison_error_file="$_gt_squash_tmpdir/comparison.stderr"
  # Bash 3.2 unwinds function locals before EXIT. Capture the concrete paths in
  # the trap command before replacing the setup-time signal cleanup handlers.
  printf -v _gt_squash_exit_trap \
    '_gt_squash_patch_cleanup "$?" %q %q %q %q %q %q %q' \
    "$_gt_squash_branch_file" "$_gt_squash_base_file" \
    "$_gt_squash_tmpdir" "$_gt_squash_path_file" \
    "$_gt_squash_branch_delta_file" \
    "$_gt_squash_candidate_delta_file" \
    "$_gt_squash_comparison_error_file" || exit 2
  # Expanding now is the Bash 3.2 compatibility fix.
  # shellcheck disable=SC2064
  trap "$_gt_squash_exit_trap" EXIT
  trap 'exit 2' HUP INT TERM
  : >"$_gt_squash_comparison_error_file" || exit 2

  git diff --no-ext-diff --no-textconv --binary --full-index \
    --ignore-submodules=none \
    "$merge_base" "$branch" -- |
    git patch-id --stable >"$_gt_squash_branch_file" || exit 2
  git diff --name-only -z --no-renames --ignore-submodules=none \
    "$merge_base" "$branch" -- >"$_gt_squash_path_file" || exit 2
  while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || exit 2
    if ((path_filter)); then
      pathspec_count=$((pathspec_count + 1))
      pathspec_bytes=$((pathspec_bytes + ${#path} + 15))
      if ((pathspec_bytes > pathspec_limit || \
        pathspec_count > pathspec_count_limit)); then
        path_filter=0
        base_pathspec_args=(--)
      else
        base_pathspec_args+=(":(top,literal)$path")
      fi
    fi
  done <"$_gt_squash_path_file"
  [[ -z "$path" ]] || exit 2
  # -m is the Git 2.29-compatible way to emit merge transitions. Only a
  # candidate's first-parent delta can pass the exact comparison below.
  git -c log.diffMerges=first-parent log \
    --first-parent --ancestry-path -m --no-ext-diff --no-textconv \
    --format='commit %H' -p --binary --full-index --ignore-submodules=none \
    "$merge_base..$base" "${base_pathspec_args[@]}" |
    git patch-id --stable >"$_gt_squash_base_file" || exit 2
  git -c core.quotePath=true diff-tree --no-commit-id --raw -r -z \
    --no-renames --no-abbrev --ignore-submodules=none \
    "$merge_base" "$branch" -- >"$_gt_squash_branch_delta_file" || exit 2

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
    if [[ "$patch_id" == "$branch_patch_id" && "$matched" == 0 ]]; then
      candidate=$patch_source
      # --ancestry-path guarantees that this first-parent transition follows
      # the branch merge base, even when that base is another merge parent.
      git -c core.quotePath=true diff-tree --no-commit-id --raw -r -z \
        --no-renames --no-abbrev --ignore-submodules=none \
        "$candidate^1" "$candidate" -- \
        >"$_gt_squash_candidate_delta_file" || exit 2
      comparison_status=0
      exec 3>"$_gt_squash_comparison_error_file" || exit 2
      git diff --no-index --quiet --no-ext-diff --no-textconv -- \
        "$_gt_squash_branch_delta_file" \
        "$_gt_squash_candidate_delta_file" 2>&3 || comparison_status=$?
      exec 3>&- || exit 2
      [[ ! -s "$_gt_squash_comparison_error_file" ]] || exit 2
      case "$comparison_status" in
        0) matched=1 ;;
        1) ;;
        *) exit 2 ;;
      esac
    fi
  done <"$_gt_squash_base_file"
  [[ -z "$line" ]] || exit 2

  ((matched)) && exit 0
  exit 1
)

# @brief Internal content-merge proof for pinned commit OIDs.
# These merge methods replay a branch's changes as brand-new commit(s) on the
# base, so the branch tip is never an ancestor of the base and both
# `git merge-base --is-ancestor` and `git branch -d` report it as unmerged.
# Use patch IDs to find candidate equivalence, then require exact raw-delta
# evidence. Two history shapes must be handled:
#
#   1. Squash merge: the whole branch lands as ONE new first-parent transition.
#      Patch IDs locate historical candidates after the branch merge base, then
#      the branch delta must equal the candidate's first-parent-to-commit delta
#      exactly. Later mainline edits do not erase that historical proof.
#   2. Rebase / cherry-pick merge: each branch commit is replayed separately, so
#      every merge-base..branch commit has an equivalent patch-id in the base.
#      `git cherry` prints '+' for any branch commit NOT yet in the base; none
#      missing (with at least one compared) means the whole branch is applied.
#      Its exact net delta must still be present in the pinned base snapshot.
#
# The squash patch ID and per-commit check are complementary: a multi-commit
# squash matches only #1, a multi-commit rebase matches only #2. Returns 1 for a
# branch with no unique diff; that degenerate case has no patch-id to match and
# is already covered by the plain ancestor check.
_gt_branch_content_merged_oids() {
  local branch="$1" base="$2" merge_base cherry squash_status=0
  local branch_delta base_delta missing grep_rc=0
  local native_width=${#branch}

  # This entry point avoids subprocess validation only for OIDs already pinned
  # by Git ref inventory or by the public wrappers below. Retain a cheap format
  # check so an accidental future caller cannot turn a ref expression into an
  # unchecked revision lookup.
  case "$native_width" in
    40 | 64) ;;
    *) return 1 ;;
  esac
  [[ "${#base}" == "$native_width" ]] || return 1
  [[ "$branch" != *[!0-9a-f]* && "$base" != *[!0-9a-f]* ]] || return 1

  merge_base=$(git merge-base "$base" "$branch" 2>/dev/null) || return 1

  # Shape 1: squash merge. Keep binary and NUL-delimited streams out of shell
  # variables, observe both sides of each pipeline, and fail closed on every
  # operational error. This proof compares the branch against the historical
  # first-parent commit that landed it, rather than against today's base tip.
  _gt_squash_patch_merged "$branch" "$base" "$merge_base" || squash_status=$?
  case "$squash_status" in
    0) return 0 ;;
    1) ;;
    *) return 1 ;;
  esac

  # Patch IDs ignore whitespace. The multi-commit replay fallback therefore
  # still requires the branch's exact raw tree delta to be present in the
  # current base snapshot. The branch delta must be a subset of the base delta,
  # including full object IDs, modes, gitlinks, paths, and deletion states.
  # --no-renames makes rename representation deterministic; quoted output keeps
  # unusual paths on one sortable record per tree entry.
  #
  # Materialize and status-check each producer. Process-substitution failures
  # are not reflected in `comm`'s status, which could otherwise make a failed
  # branch producer look like an empty, fully merged delta.
  branch_delta=$(
    git -c core.quotePath=true diff-tree --no-commit-id --raw -r \
      --no-renames --no-abbrev --ignore-submodules=none \
      "$merge_base" "$branch" --
  ) || return 1
  # The raw delta is already the exact tree comparison needed here. Reusing it
  # avoids resolving both tree OIDs separately before producing the same diff.
  [[ -n "$branch_delta" ]] || return 1
  base_delta=$(
    git -c core.quotePath=true diff-tree --no-commit-id --raw -r \
      --no-renames --no-abbrev --ignore-submodules=none \
      "$merge_base" "$base" --
  ) || return 1
  branch_delta=$(LC_ALL=C sort <<<"$branch_delta") || return 1
  base_delta=$(LC_ALL=C sort <<<"$base_delta") || return 1
  missing=$(
    LC_ALL=C comm -23 \
      <(printf '%s\n' "$branch_delta") \
      <(printf '%s\n' "$base_delta")
  ) || return 1
  [[ -z "$missing" ]] || return 1

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

# @brief Return 0 when <branch>'s changes are already present in <base> via a
# squash, rebase, or cherry-pick merge.
# Resolve arbitrary caller refs to immutable commit OIDs before entering the
# internal fast path. Branch-audit can skip these subprocesses because its OIDs
# come directly from one successful `for-each-ref` snapshot.
gt_branch_content_merged() {
  local branch base
  branch=$(git rev-parse --verify "$1^{commit}" 2>/dev/null) || return 1
  base=$(git rev-parse --verify "$2^{commit}" 2>/dev/null) || return 1
  _gt_branch_content_merged_oids "$branch" "$base"
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
  local name local_vars
  local -a env_args=()

  # Resolve lazily so commands that never cross repositories pay nothing.
  if [[ "${_GT_GIT_LOCAL_ENV_VARS_READY:-}" != 1 ]]; then
    _GT_GIT_LOCAL_ENV_VARS=$(git rev-parse --local-env-vars) || return 1
    _GT_GIT_LOCAL_ENV_VARS_READY=1
  fi
  local_vars=${_GT_GIT_LOCAL_ENV_VARS:-}
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    env_args+=("-u" "$name")
  done <<<"$local_vars"
  # GIT_CONFIG_PARAMETERS is among them, but a write in the other worktree must
  # still never start auto maintenance (see lib/git-tools-git.sh).
  env_args+=("GIT_CONFIG_PARAMETERS=$GT_GIT_NO_AUTO_MAINTENANCE")

  env "${env_args[@]}" "$GT_GIT" "$@"
}

# @brief Set GT_WORKTREE_PATH to the current worktree without losing newlines.
# The sentinel keeps command substitution from stripping the path's terminal
# newlines; removing Git's single record delimiter then recovers the exact path.
gt_find_current_worktree() {
  local output sentinel=$'\034'

  GT_WORKTREE_PATH=""
  output=$(git rev-parse --show-toplevel && printf '%s' "$sentinel") || return 1
  [[ "$output" == *"$sentinel" ]] || return 1
  output=${output%"$sentinel"}
  [[ "$output" == *$'\n' ]] || return 1
  GT_WORKTREE_PATH=${output%$'\n'}
}

# @brief Succeed when Git in a work tree, on its own, reaches the Git directory.
# A checkout whose `.git` directory or gitfile leads back (an ordinary clone, a
# separate Git directory, a submodule) passes. One that Git reaches only
# through GIT_DIR/GIT_WORK_TREE or another directory's `core.worktree`, as a
# dotfiles checkout of $HOME is, does not.
_gt_work_tree_reaches_git_dir() {
  local top="$1" git_dir="$2" found

  # The `.git` entry is checked on disk first: when a command is run by name,
  # `git` on PATH can be a launcher that routes `git -C $HOME` back into the
  # dotfiles repository, so asking Git alone would report that it leads back.
  [[ -e "$top/.git" || -L "$top/.git" ]] || return 1
  found=$(gt_git_without_local_env -C "$top" rev-parse --git-dir \
    2>/dev/null) || return 1
  [[ "$found" == /* ]] || found=$top/$found
  [[ "$found" -ef "$git_dir" ]]
}

# @brief Succeed when the invoking checkout is a main worktree that Git reaches
# only through GIT_DIR/GIT_WORK_TREE or `core.worktree`.
# Such a checkout belongs to whatever tooling sets that up (a dotfiles manager
# for $HOME, say), and a Git launcher may route unrelated directories into it,
# so being run there is not a deliberate choice of that checkout. Sets
# GT_WORKTREE_PATH to its work tree. Returns 1 for any other checkout and 2
# when the checkout cannot be inspected.
gt_current_checkout_is_external() {
  local common_dir git_dir

  gt_find_current_worktree || return 2
  git_dir=$(git rev-parse --git-dir) || return 2
  common_dir=$(git rev-parse --git-common-dir) || return 2
  [[ "$git_dir" -ef "$common_dir" ]] || return 1
  ! _gt_work_tree_reaches_git_dir "$GT_WORKTREE_PATH" "$git_dir"
}

# @brief Materialize Git's NUL-delimited worktree inventory and check its
# producer status. Reading process substitution directly hides producer
# failures from the consuming loop.
_gt_materialize_worktree_list() {
  local candidate field list_fd="" complete=0 trailing=0

  _GT_WORKTREE_FIELDS=()
  # Bash 3.2 has no automatic {var} descriptor allocation. Pick an unused
  # descriptor without overwriting one owned by a caller.
  for candidate in 9 8 7 6 5 4 3; do
    if ! { true <&"$candidate"; } 2>/dev/null; then
      list_fd=$candidate
      break
    fi
  done
  [[ -n "$list_fd" ]] || return 1
  # Positional parameters are function-scoped and cannot inherit a caller's
  # export attribute, so the producer cannot read the nonce from its environment.
  # The nonhex suffix is emitted only after od succeeds, preserving its status.
  set -- "$(LC_ALL=C od -An -N16 -tx1 /dev/urandom 2>/dev/null && printf x)"
  set -- "${1//[[:space:]]/}"
  [[ ${#1} -eq 33 && "$1" == *x && "${1%x}" != *[!0-9a-f]* ]] || return 1
  set -- $'\036git-tools-worktree-list-complete-'"${1%x}"
  # The unpredictable completion record carries the producer status through
  # the pipe. Bash 3.2 does not reliably retain process-substitution children
  # for `wait`.
  if ! eval "exec $list_fd< <(git worktree list --porcelain -z && printf '%s\\0' \"\$1\")"; then
    return 1
  fi
  while IFS= read -r -d '' field <&"$list_fd"; do
    if [[ "$field" == "$1" && "$complete" == 0 ]]; then
      complete=1
    elif ((complete)); then
      trailing=1
    else
      _GT_WORKTREE_FIELDS+=("$field")
    fi
  done
  if [[ -n "$field" || "$complete" != 1 || "$trailing" != 0 ]]; then
    eval "exec $list_fd<&-"
    _GT_WORKTREE_FIELDS=()
    return 1
  fi
  eval "exec $list_fd<&-"
}

# @brief Set GT_WORKTREE_PATH to the repository's main worktree.
# Git always lists the main worktree first, including when invoked from a
# linked worktree. For a bare repository this is the bare directory itself.
gt_find_main_worktree() {
  local field

  GT_WORKTREE_PATH=""
  _gt_materialize_worktree_list || return 1
  for field in ${_GT_WORKTREE_FIELDS[@]+"${_GT_WORKTREE_FIELDS[@]}"}; do
    case "$field" in
      "worktree "*)
        GT_WORKTREE_PATH=${field#worktree }
        return 0
        ;;
    esac
  done
  return 1
}

# @brief Decide how the invoking checkout may advance a local base branch.
# @param $1 Base branch name.
# @param $2 Optional: 1 to inspect rebase and bisect reservations even when the
#   main worktree could simply switch. `git switch` refuses a reserved branch
#   on its own, so only callers that must refuse before an irreversible step
#   need to pay for scanning every worktree.
#
# Only the checkout that has the base checked out may merge into it, and only
# the main worktree may take the base over: a linked worktree that switched to
# the base would release its own branch and lock the main worktree out of the
# base. A main worktree whose files live outside its Git directory (a
# `core.worktree` or separate-Git-directory checkout, or a bare repository used
# through an external work tree) is left to the tooling that manages it, which
# may validate, back up, or normalize what it checks out.
#
# Facts about the invoking checkout come from HEAD and the Git directories, not
# from `git worktree list` paths, which name such main worktrees by their Git
# directory and list a bare repository's external work tree not at all.
#
# The invoking checkout is held to the same rule: when it is a main worktree
# that Git reaches only through GIT_DIR/GIT_WORK_TREE or `core.worktree` (see
# gt_current_checkout_is_external), it is never switched or merged into, and
# is planned like a linked worktree.
#
# Sets GT_BASE_SYNC_MAY_SWITCH to 1 when the invoking checkout is a main
# worktree that may take the base over, and GT_BASE_SYNC_ACTION to one of:
#   current   the invoking checkout has the base checked out
#   switch    the invoking main worktree may check the base out
#   worktree  ordinary worktree GT_BASE_SYNC_PATH has the base checked out
#   external  main worktree GT_BASE_SYNC_PATH, whose files live outside its Git
#             directory, has the base checked out; GT_BASE_SYNC_REASON is
#             index when that is inferred from a bare repository's index,
#             current when it is the invoking checkout, and unlocated when
#             GT_BASE_SYNC_PATH is its Git directory because its work tree
#             cannot be found (see gt_base_sync_external_message)
#   reserved  a rebase or bisect in GT_BASE_SYNC_PATH reserves the base
#   ref       nothing has the base checked out; only the ref may move
#   unknown   GT_BASE_SYNC_REASON (inventory or reservations) is uninspectable
# Returns nonzero only when the invoking checkout itself cannot be inspected.
# shellcheck disable=SC2034 # results are consumed by base-updating commands
gt_plan_base_sync() {
  local base="$1" scan_main="${2:-0}" common_dir field git_dir head index=0
  local head_status=0 main_bare=0 main_path="" path="" target="" top

  GT_BASE_SYNC_ACTION=""
  GT_BASE_SYNC_PATH=""
  GT_BASE_SYNC_REASON=""
  GT_BASE_SYNC_MAY_SWITCH=0
  head=$(git symbolic-ref -q HEAD) || head_status=$?
  case "$head_status" in
    0) ;;
    1) head="" ;;
    *) return 1 ;;
  esac
  git_dir=$(git rev-parse --git-dir) || return 1
  common_dir=$(git rev-parse --git-common-dir) || return 1
  if [[ "$git_dir" -ef "$common_dir" ]]; then
    gt_find_current_worktree || return 1
    if _gt_work_tree_reaches_git_dir "$GT_WORKTREE_PATH" "$git_dir"; then
      GT_BASE_SYNC_MAY_SWITCH=1
    elif [[ "$head" == "refs/heads/$base" ]]; then
      GT_BASE_SYNC_ACTION=external
      GT_BASE_SYNC_PATH=$GT_WORKTREE_PATH
      GT_BASE_SYNC_REASON=current
      return 0
    fi
  fi
  if [[ "$head" == "refs/heads/$base" ]]; then
    GT_BASE_SYNC_ACTION=current
    return 0
  fi

  if ! _gt_materialize_worktree_list 2>/dev/null; then
    GT_BASE_SYNC_ACTION=unknown
    GT_BASE_SYNC_REASON=inventory
    return 0
  fi
  # Git always lists the main worktree first.
  for field in ${_GT_WORKTREE_FIELDS[@]+"${_GT_WORKTREE_FIELDS[@]}"}; do
    case "$field" in
      "worktree "*)
        path=${field#worktree }
        index=$((index + 1))
        [[ "$index" != 1 ]] || main_path=$path
        ;;
      bare) [[ "$index" != 1 ]] || main_bare=1 ;;
      "branch refs/heads/$base") [[ -n "$target" ]] || target=$path ;;
    esac
  done

  if [[ -n "$target" ]]; then
    GT_BASE_SYNC_PATH=$target
    GT_BASE_SYNC_ACTION=worktree
    [[ "$target" == "$main_path" ]] || return 0
    # Git lists an ordinary main worktree as the parent of its `.git`
    # directory and any other main worktree as the Git directory itself. A Git
    # directory named `.git` can still carry `core.worktree`, so the checkout
    # must also resolve to that parent. When it resolves elsewhere, name the
    # real work tree in messages.
    # The sentinel keeps command substitution from stripping a path's own
    # trailing newlines; only Git's record delimiter is removed.
    if top=$(gt_git_without_local_env -C "$target" rev-parse --show-toplevel \
      2>/dev/null && printf x); then
      top=${top%x}
      top=${top%$'\n'}
    else
      top=""
    fi
    if [[ "$target/.git" -ef "$common_dir" ]] &&
      [[ -z "$top" || "$top" -ef "$target" ]]; then
      return 0
    fi
    GT_BASE_SYNC_ACTION=external
    if [[ -n "$top" ]]; then
      GT_BASE_SYNC_PATH=$top
    else
      # A separate Git directory or a symlinked `.git` records nothing about
      # where its work tree is, so only the Git directory can be named.
      GT_BASE_SYNC_REASON=unlocated
    fi
    return 0
  fi
  if [[ "$GT_BASE_SYNC_MAY_SWITCH" == 1 && "$scan_main" != 1 ]]; then
    GT_BASE_SYNC_ACTION=switch
    return 0
  fi

  # A rebase or bisect can reserve the base while its HEAD is detached, and
  # moving the ref underneath it would corrupt that operation. A worktree whose
  # directory is gone makes this uninspectable.
  if ! gt_find_worktree_reserving_branch "$base"; then
    GT_BASE_SYNC_ACTION=unknown
    GT_BASE_SYNC_REASON=reservations
    return 0
  fi
  if [[ -n "$GT_WORKTREE_PATH" ]]; then
    GT_BASE_SYNC_ACTION=reserved
    GT_BASE_SYNC_PATH=$GT_WORKTREE_PATH
    return 0
  fi
  if [[ "$GT_BASE_SYNC_MAY_SWITCH" == 1 ]]; then
    GT_BASE_SYNC_ACTION=switch
    return 0
  fi

  # A bare repository has no worktree of its own, but one used through
  # GIT_DIR and GIT_WORK_TREE keeps an index, and its HEAD names the branch
  # that external work tree has checked out. A bare clone that only hosts
  # linked worktrees has no index.
  if [[ "$main_bare" == 1 && -e "$common_dir/index" ]]; then
    head_status=0
    head=$(gt_git_without_local_env --git-dir="$common_dir" \
      symbolic-ref -q HEAD) || head_status=$?
    case "$head_status" in
      0) ;;
      1) head="" ;;
      *)
        GT_BASE_SYNC_ACTION=unknown
        GT_BASE_SYNC_REASON=inventory
        return 0
        ;;
    esac
    if [[ "$head" == "refs/heads/$base" ]]; then
      GT_BASE_SYNC_ACTION=external
      GT_BASE_SYNC_PATH=$main_path
      GT_BASE_SYNC_REASON=index
      return 0
    fi
  fi
  GT_BASE_SYNC_ACTION=ref
}

# @brief Print why an `external` base sync leaves the base alone, for the
# "not updating <base> ..." diagnostics of every base-updating command.
gt_base_sync_external_message() {
  local base="$1" path=$GT_BASE_SYNC_PATH

  case "$GT_BASE_SYNC_REASON" in
    index)
      printf 'not updating %s in %s; update that checkout with its own tooling (a bare repository with an index counts as checked out; remove %s/index if no work tree uses it)\n' \
        "$base" "$path" "$path"
      ;;
    unlocated)
      printf 'not updating %s; it is checked out in the main worktree, whose work tree location is unknown (Git directory %s); update that checkout with its own tooling\n' \
        "$base" "$path"
      ;;
    *)
      printf 'not updating %s in %s; update that checkout with its own tooling\n' \
        "$base" "$path"
      ;;
  esac
}

# @brief Set GT_WORKTREE_PATH to the worktree that has a branch checked out.
# The global result avoids command substitution, which cannot preserve trailing
# newlines. An empty result means the branch is not checked out.
gt_find_worktree_for_branch() {
  local branch="$1"
  local field path=""

  GT_WORKTREE_PATH=""
  _gt_materialize_worktree_list || return 1

  for field in "${_GT_WORKTREE_FIELDS[@]}"; do
    case "$field" in
      "worktree "*) path=${field#worktree } ;;
      "branch refs/heads/$branch")
        GT_WORKTREE_PATH=$path
        return 0
        ;;
      '') path="" ;;
    esac
  done
}

# @brief Print the worktree path that has the given branch checked out.
# Prefer gt_find_worktree_for_branch when the path will be consumed by shell.
gt_worktree_for_branch() {
  gt_find_worktree_for_branch "$1" || return 1
  [[ -z "$GT_WORKTREE_PATH" ]] || printf '%s\n' "$GT_WORKTREE_PATH"
}

# @brief Set GT_GIT_PATH to a Git metadata path of another worktree.
# Git prints `--git-path` relative to the directory it ran in when the Git
# directory is below it (`.git/<name>` for an ordinary main worktree, `<name>`
# for a Git directory listed as itself), and absolute for linked worktrees. The
# caller tests the result from its own directory, so a relative path is
# anchored at the worktree; otherwise the main worktree's rebase, bisect, or
# merge state would be looked up under the caller's directory and missed.
_gt_find_worktree_git_path() {
  local worktree="$1" name="$2" result

  GT_GIT_PATH=""
  result=$(gt_git_without_local_env -C "$worktree" rev-parse --git-path \
    "$name" 2>/dev/null) || return 1
  [[ "$result" == /* ]] || result=$worktree/$result
  GT_GIT_PATH=$result
}

# @brief Print the worktree path that owns or reserves the given branch.
#
# A rebase temporarily detaches HEAD while retaining the original branch in
# rebase metadata. Irreversible workflows need this stronger check, while
# ordinary inventory consumers retain the checked-out-only contract above.
gt_find_worktree_reserving_branch() {
  local branch="$1"
  local field path state_file state_head
  local -a paths=()

  GT_WORKTREE_PATH=""
  GT_WORKTREE_FAILED_PATH=""
  GT_WORKTREE_FAILED_LOCKED=0
  _gt_materialize_worktree_list || return 1

  for field in "${_GT_WORKTREE_FIELDS[@]}"; do
    case "$field" in
      "worktree "*)
        path=${field#worktree }
        paths+=("$path")
        ;;
      "branch refs/heads/$branch")
        GT_WORKTREE_PATH=$path
        return 0
        ;;
    esac
  done

  for path in "${paths[@]}"; do
    for state_file in rebase-merge/head-name rebase-apply/head-name; do
      _gt_find_worktree_git_path "$path" "$state_file" ||
        gt_record_uninspectable_worktree "$path" || return 1
      state_file=$GT_GIT_PATH
      [[ -f "$state_file" ]] || continue
      IFS= read -r state_head <"$state_file" || return 1
      if [[ "$state_head" == "refs/heads/$branch" ]]; then
        GT_WORKTREE_PATH=$path
        return 0
      fi
    done

    _gt_find_worktree_git_path "$path" BISECT_START ||
      gt_record_uninspectable_worktree "$path" || return 1
    state_file=$GT_GIT_PATH
    if [[ -f "$state_file" ]]; then
      IFS= read -r state_head <"$state_file" || return 1
      if [[ "$state_head" == "$branch" || "$state_head" == "refs/heads/$branch" ]]; then
        GT_WORKTREE_PATH=$path
        return 0
      fi
    fi
  done
}

# @brief Record a worktree that could not be inspected for
# gt_uninspectable_worktree_hint, noting whether the inventory marks it locked.
# Always returns 1 so callers can chain it onto the failed inspection.
gt_record_uninspectable_worktree() {
  local field path=""

  GT_WORKTREE_FAILED_PATH=$1
  GT_WORKTREE_FAILED_LOCKED=0
  for field in ${_GT_WORKTREE_FIELDS[@]+"${_GT_WORKTREE_FIELDS[@]}"}; do
    case "$field" in
      "worktree "*) path=${field#worktree } ;;
      locked | "locked "*)
        [[ "$path" != "$1" ]] || GT_WORKTREE_FAILED_LOCKED=1
        ;;
    esac
  done
  return 1
}

# @brief Print the advice for a worktree a reservation scan could not inspect,
# usually one whose directory was deleted without `git worktree prune`. Every
# command gives the same advice, whichever checkout it runs from.
gt_uninspectable_worktree_hint() {
  local path=$GT_WORKTREE_FAILED_PATH

  [[ -n "$path" ]] || return 0
  if [[ "$GT_WORKTREE_FAILED_LOCKED" == 1 ]]; then
    printf 'if worktree %s was deleted, run git worktree unlock %q, then git worktree prune\n' \
      "$path" "$path"
  else
    printf 'if worktree %s was deleted, run git worktree prune\n' "$path"
  fi
}

# @brief Print the worktree path that owns or reserves the given branch.
# Prefer gt_find_worktree_reserving_branch when the path is consumed by shell.
gt_worktree_reserving_branch() {
  gt_find_worktree_reserving_branch "$1" || return 1
  [[ -z "$GT_WORKTREE_PATH" ]] || printf '%s\n' "$GT_WORKTREE_PATH"
}

# @brief Print the active sequencer operation in a worktree, if any.
# @param $1 Worktree path, or empty for the invoking checkout. The invoking
#   checkout keeps its inherited Git environment, because a checkout driven by
#   GIT_DIR (dotfiles-style) cannot be found again from its work tree path.
gt_worktree_operation() {
  local path="$1"
  local entry label state_path

  while IFS=$'\t' read -r entry label; do
    if [[ -z "$path" ]]; then
      state_path=$(git rev-parse --git-path "$entry" 2>/dev/null) || return 1
    else
      _gt_find_worktree_git_path "$path" "$entry" || return 1
      state_path=$GT_GIT_PATH
    fi
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

# lsof scans every process on the system (seconds on a busy host), so one scan
# serves the checks that follow it within a short window; /proc reads are cheap
# and always fresh.
_GT_LSOF_CWDS=""
_GT_LSOF_AT=""
_GT_LSOF_TTL=30

# Print `<pid> TAB <cwd>` records from lsof, reusing a scan younger than
# _GT_LSOF_TTL seconds. Must run in the main shell for the reuse to stick.
_gt_lsof_cwds() {
  local record pid="" records=""

  if [[ -n "$_GT_LSOF_AT" ]] && ((SECONDS - _GT_LSOF_AT < _GT_LSOF_TTL)); then
    printf '%s' "$_GT_LSOF_CWDS"
    return 0
  fi
  command -v lsof >/dev/null 2>&1 || return 1
  while IFS= read -r record; do
    case "$record" in
      p*) pid=${record#p} ;;
      n*) [[ -z "$pid" ]] || records+="$pid"$'\t'"${record#n}"$'\n' ;;
    esac
  done < <(lsof -n -w -a -d cwd -Fpn 2>/dev/null)
  [[ -n "$records" ]] || return 1
  _GT_LSOF_CWDS=$records
  _GT_LSOF_AT=$SECONDS
  printf '%s' "$records"
}

# @brief Succeed when some process's working directory is the worktree or lies
# inside it. An idle shell or agent session parked in a checkout is still using
# it, and removing the directory under it strands that session.
# @param $1 Worktree path.
# Returns 0 when in use (GT_WORKTREE_USER_PID names one such process), 1 when
# no visible process uses it, and 2 when process working directories cannot be
# listed. Linux reads /proc; elsewhere (macOS, BSD) lsof supplies the same view.
# Processes of other users are invisible either way, so this guards the
# caller's own sessions, which are the ones a cleanup could strand. Only working
# directories count: an editor or build that merely holds files open from
# elsewhere is not seen.
# shellcheck disable=SC2034 # GT_WORKTREE_USER_PID is consumed by cleanup commands
gt_worktree_in_use() {
  local target proc=${GIT_TOOLS_TEST_PROC_ROOT:-/proc} record pid cwd prefix
  local lsof_records escaped=0
  local -a records=()

  GT_WORKTREE_USER_PID=""
  target=$(cd -P -- "$1" 2>/dev/null && pwd -P) || return 2
  if [[ -d "$proc" ]]; then
    # One subshell resolves every `<pid>/cwd` link with builtins: `cd -P`
    # follows the kernel's link and $PWD reads the physical result back, so
    # there is no process per pid. NUL framing keeps any path literal. An
    # unreadable or vanished process simply prints nothing.
    while IFS= read -r -d '' record; do
      records+=("$record")
    done < <(
      for record in "$proc"/[0-9]*/cwd; do
        cd -P -- "$record" 2>/dev/null || continue
        pid=${record%/cwd}
        printf '%s\t%s\0' "${pid##*/}" "$PWD"
      done
    )
  fi
  # A /proc that resolves nothing at all, not even this process, is masked or
  # foreign rather than idle, so fall through to lsof instead of reporting
  # that nothing uses the worktree.
  if ((${#records[@]} == 0)); then
    # Capture in the main shell so the scan is reused by later checks.
    _gt_lsof_cwds >/dev/null || return 2
    lsof_records=$_GT_LSOF_CWDS
    while IFS= read -r record; do
      [[ -n "$record" ]] && records+=("$record")
    done <<<"$lsof_records"
    escaped=1
  fi
  for record in "${records[@]}"; do
    pid=${record%%$'\t'*}
    cwd=${record#*$'\t'}
    if [[ "$cwd" == "$target" || "$cwd" == "$target"/* ]]; then
      GT_WORKTREE_USER_PID=$pid
      return 0
    fi
    # lsof escapes tabs, newlines, and (outside a UTF-8 locale) non-ASCII
    # bytes in names, so such a name cannot be compared exactly. Count it as
    # a use when the part before its first escape could lead into the
    # worktree, failing closed rather than stranding a session.
    if ((escaped == 1)) && [[ "$cwd" == *\\* ]]; then
      prefix=${cwd%%\\*}
      if [[ "$target" == "$prefix"* || "$prefix" == "$target"/* ]]; then
        GT_WORKTREE_USER_PID=$pid
        return 0
      fi
    fi
  done
  return 1
}
