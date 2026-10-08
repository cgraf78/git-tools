#!/usr/bin/env bash
# Shared cleanup engine: merge proofs, the worktree removal gate, and exact
# branch retirement for commands that delete branches or remove checkouts.
#
# One copy of these rules keeps every cleanup command equally careful. Callers
# source lib/git-tools-base.sh first, set the GT_CLEANUP_* inputs below, and may
# redefine gt_cleanup_report after sourcing to render decisions their own way.
# Nothing here exits the caller: failures return non-zero. Branch decisions and
# removals are reported through gt_cleanup_report; the worktree gate and the
# worktree removal helpers instead set GT_CLEANUP_KEEP_* when a worktree must
# stay, so each caller reports it in its own terms.

# Results are published through GT_CLEANUP_* globals read by sourcing commands.
# shellcheck disable=SC2034

# Every `git` this library runs is Git's own binary, not a PATH wrapper.
_gt_lib_dir=${BASH_SOURCE[0]%/*}
[[ "$_gt_lib_dir" != "${BASH_SOURCE[0]}" ]] || _gt_lib_dir=.
# shellcheck source=lib/git-tools-git.sh
. "$_gt_lib_dir/git-tools-git.sh" || return 1
unset _gt_lib_dir

# Caller inputs. Reset on source so inherited values cannot widen what a run
# removes. GT_CLEANUP_SWITCHED_TO_BASE means the invoking worktree leaves
# GT_CLEANUP_CURRENT_BRANCH (or, in a dry run, would leave it) for the base.
# A non-empty GT_CLEANUP_WORKTREE_SCOPE limits removal to those worktree paths;
# GT_CLEANUP_ECHO_DRY_RUN=0 silences the dry-run command echo for callers that
# render every decision themselves.
{
  GT_CLEANUP_COMMAND=git-tools
  GT_CLEANUP_DRY_RUN=0
  GT_CLEANUP_REMOVE_WORKTREES=0
  GT_CLEANUP_SWITCHED_TO_BASE=0
  GT_CLEANUP_CURRENT_BRANCH=""
  GT_CLEANUP_CURRENT_WORKTREE=""
  GT_CLEANUP_WORKTREE_SCOPE=()
  GT_CLEANUP_ECHO_DRY_RUN=1
  GT_CLEANUP_PRUNE_PATHS=()
  GT_CLEANUP_ERROR=""
  GT_CLEANUP_UNINSPECTABLE_HINT=""
  GT_CLEANUP_PROOF=""
  GT_CLEANUP_KEEP_CODE=""
  GT_CLEANUP_KEEP_DETAIL=""
  GT_CLEANUP_KEEP_WHY=""
}

# @brief Report one cleanup decision. Callers may redefine this after sourcing.
# @param $1 Event: keep-branch, delete-branch, remove-worktree, or prune-entry;
#   a dry run reports would-delete-branch, would-remove-worktree, and
#   would-prune-entry instead.
# @param $2 Subject: a branch name, or a worktree path for worktree events.
# @param $3 Machine-readable reason code.
# @param $4 Machine-readable detail (an object ID, path, or process ID), or "".
# @param $5 Human-readable message, possibly empty when the dry-run command
#   echo already says it. Never parse it for control flow.
gt_cleanup_report() {
  [[ -z "$5" ]] || printf '%s: %s\n' "$GT_CLEANUP_COMMAND" "$5" >&2
}

# @brief Run a mutating command, or describe it in a dry run.
gt_cleanup_run() {
  if [[ "$GT_CLEANUP_DRY_RUN" == 1 ]]; then
    [[ "$GT_CLEANUP_ECHO_DRY_RUN" == 1 ]] || return 0
    printf '%s: would run:' "$GT_CLEANUP_COMMAND" >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    return 0
  fi
  "$@"
}

# @brief Succeed when a branch's upstream was its own remote branch and is gone.
# Only that combination suggests the branch was published and then retired,
# normally by a landed PR. A branch that tracks another branch (the base it was
# cut from, a teammate's branch, or a local one) may hold commits no remote ever
# saw, so that upstream's deletion proves nothing about the branch.
# @param $1 Branch name. @param $2 `%(upstream:track)`.
# @param $3 `%(upstream:remotename)`. @param $4 `%(upstream:remoteref)`.
gt_own_upstream_gone() {
  local branch="$1" upstream_track="$2" remote_name="$3" remote_ref="$4"

  [[ "$upstream_track" == "[gone]" && -n "$remote_name" &&
    "$remote_name" != . && "$remote_ref" == "refs/heads/$branch" ]]
}

# @brief Succeed when a branch's net change landed whole: the branch changes
# something relative to its merge base, and a first-parent commit of the base
# that descends from that merge base has exactly the branch's tree. A stacked
# landing can bring a branch to the base through several mainline commits that
# neither replay detector matches, yet the branch's result is then a mainline
# snapshot. Both conditions matter: a branch with no net change (an empty WIP
# commit, or work added and then removed) trivially equals an existing
# snapshot, and an unlanded revert equals the snapshot before the commit it
# reverts, yet neither has landed anything.
gt_tree_landed() {
  local tip="$1" base="$2" merge_base tree base_tree trees

  merge_base=$(git merge-base "$base" "$tip" 2>/dev/null) || return 1
  tree=$(git rev-parse --verify -q "$tip^{tree}" 2>/dev/null) || return 1
  base_tree=$(git rev-parse --verify -q "$merge_base^{tree}" 2>/dev/null) ||
    return 1
  [[ "$tree" != "$base_tree" ]] || return 1
  trees=$(git log --first-parent --ancestry-path --format=%T \
    "$merge_base..$base" -- 2>/dev/null) || return 1
  [[ $'\n'"$trees"$'\n' == *$'\n'"$tree"$'\n'* ]]
}

# @brief Prove that a pinned commit OID's work is already in a pinned base OID.
# Sets GT_CLEANUP_PROOF to merged (ancestry), content-merged (an exact squash,
# rebase, or cherry-pick replay), or tree-landed (its whole tree is a mainline
# snapshot). Returns 1 when no proof holds, including when Git cannot answer.
# @param $3 Optional `divergent`: the caller already knows the tip is not an
#   ancestor (from a left-right count, say), so skip that check.
gt_merge_proof() {
  local tip="$1" base="$2" ancestor_status=1

  GT_CLEANUP_PROOF=""
  if [[ "${3:-}" != divergent ]]; then
    ancestor_status=0
    git merge-base --is-ancestor "$tip" "$base" 2>/dev/null || ancestor_status=$?
  fi
  case "$ancestor_status" in
    0)
      GT_CLEANUP_PROOF=merged
      return 0
      ;;
    1) ;;
    *) return 1 ;;
  esac
  if _gt_branch_content_merged_oids "$tip" "$base"; then
    GT_CLEANUP_PROOF="content-merged"
    return 0
  fi
  if gt_tree_landed "$tip" "$base"; then
    GT_CLEANUP_PROOF="tree-landed"
    return 0
  fi
  return 1
}

_gt_cleanup_validate_prune_path() {
  local entry="$1" folded

  case "$entry" in
    "" | . | .. | */* | *\\* | *$'\n'* | *$'\r'*) return 1 ;;
  esac
  folded=$(printf '%s' "$entry" | LC_ALL=C tr '[:upper:]' '[:lower:]') ||
    return 1
  [[ "$folded" != .git ]]
}

_gt_cleanup_emit_prune_paths() {
  # Keep the unpredictable completion marker in positional parameters. A
  # named local can inherit an exported attribute from the caller and leak the
  # marker to the Git producer's environment on Bash 3.2.
  set -- "$1" 0
  git config --local --null --get-all \
    cleanupRepo.worktreePrunePath || set -- "$1" "$?"
  printf '%s:%s\0' "$1" "$2"
}

# @brief Load repository-local disposable worktree entry names into
# GT_CLEANUP_PRUNE_PATHS. Returns 1 with GT_CLEANUP_ERROR set on any failure.
gt_cleanup_load_prune_paths() {
  local candidate completion_status="" config_fd="" configured entry existing
  local complete=0 invalid=0 invalid_entry="" malformed=0 saw_entry=0
  local trailing=0

  GT_CLEANUP_PRUNE_PATHS=()
  GT_CLEANUP_ERROR="could not read repository-local worktree prune paths"
  for candidate in 9 8 7 6 5 4 3; do
    if ! { true <&"$candidate"; } 2>/dev/null; then
      config_fd=$candidate
      break
    fi
  done
  if [[ -z "$config_fd" ]]; then
    GT_CLEANUP_ERROR="could not reserve a descriptor for worktree prune paths"
    return 1
  fi
  set -- "$(LC_ALL=C od -An -N16 -tx1 /dev/urandom 2>/dev/null && printf x)"
  set -- "${1//[[:space:]]/}"
  if [[ ${#1} -ne 33 || "$1" != *x || "${1%x}" == *[!0-9a-f]* ]]; then
    GT_CLEANUP_ERROR="could not create a worktree prune path completion record"
    return 1
  fi
  set -- $'\036git-tools-worktree-prune-paths-complete-'"${1%x}"
  eval "exec $config_fd< <(_gt_cleanup_emit_prune_paths \"\$1\")" || return 1

  # Deletion authority must be granted by this repository. In particular,
  # inherited global and command-scope values cannot silently opt every
  # checkout into removing a common name such as .cache.
  while :; do
    entry=""
    if IFS= read -r -d '' entry <&"$config_fd"; then
      if [[ "$entry" == "$1":* ]]; then
        if [[ "$complete" == 1 ]]; then
          trailing=1
        else
          completion_status=${entry#"$1":}
          [[ -n "$completion_status" &&
            "$completion_status" != *[!0-9]* ]] || malformed=1
          complete=1
        fi
        continue
      fi
      if [[ "$complete" == 1 ]]; then
        trailing=1
        continue
      fi
      saw_entry=1
      if ! _gt_cleanup_validate_prune_path "$entry"; then
        if [[ "$invalid" == 0 ]]; then
          invalid=1
          invalid_entry=$entry
        fi
        continue
      fi
      configured=0
      for existing in \
        ${GT_CLEANUP_PRUNE_PATHS[@]+"${GT_CLEANUP_PRUNE_PATHS[@]}"}; do
        if [[ "$existing" == "$entry" ]]; then
          configured=1
          break
        fi
      done
      [[ "$configured" == 1 ]] || GT_CLEANUP_PRUNE_PATHS+=("$entry")
      continue
    fi
    [[ -z "$entry" ]] || malformed=1
    break
  done
  eval "exec $config_fd<&-"

  [[ "$complete" == 1 && "$trailing" == 0 && "$malformed" == 0 ]] || return 1
  case "$completion_status" in
    0) ;;
    1)
      [[ "$saw_entry" == 0 ]] || return 1
      GT_CLEANUP_ERROR=""
      return 0
      ;;
    *) return 1 ;;
  esac
  if [[ "$invalid" != 0 ]]; then
    GT_CLEANUP_ERROR="invalid repository-local worktree prune path: $invalid_entry"
    return 1
  fi
  GT_CLEANUP_ERROR=""
}

_gt_cleanup_entry_has_cache_tag() {
  local path="$1" entry="$2" signature=""

  # Restrict automatic recognition to real, top-level directories and real
  # tags. A symlink must never turn cache pruning into traversal outside the
  # worktree.
  case "$entry" in
    "" | . | .. | .git | */*) return 1 ;;
  esac
  [[ -d "$path/$entry" && ! -L "$path/$entry" ]] || return 1
  [[ -f "$path/$entry/CACHEDIR.TAG" &&
    ! -L "$path/$entry/CACHEDIR.TAG" ]] || return 1
  IFS= read -r signature <"$path/$entry/CACHEDIR.TAG" || return 1
  [[ "$signature" == "Signature: 8a477f597d28d172789f06886806bc55" ]]
}

_gt_cleanup_entry_is_disposable() {
  local path="$1" entry="$2" configured

  for configured in \
    ${GT_CLEANUP_PRUNE_PATHS[@]+"${GT_CLEANUP_PRUNE_PATHS[@]}"}; do
    [[ "$configured" != "$entry" ]] || return 0
  done
  _gt_cleanup_entry_has_cache_tag "$path" "$entry"
}

_gt_cleanup_classify_status() {
  local path="$1" entry record="" top
  local has_dirty=0 has_disposable=0 has_hidden=0 malformed=0

  while :; do
    record=""
    if IFS= read -r -d '' record; then
      # A rename or copy has a second, headerless pathname record. Once any
      # tracked status is present, the worktree is ineligible; drain the rest
      # without interpreting continuation records or risking producer SIGPIPE.
      [[ "$has_dirty" == 0 ]] || continue
      case "$record" in
        '?? '* | '!! '*)
          entry=${record#???}
          if [[ -z "$entry" ]]; then
            malformed=1
            continue
          fi
          top=${entry%%/*}
          if _gt_cleanup_entry_is_disposable "$path" "$top"; then
            has_disposable=1
          else
            has_hidden=1
          fi
          ;;
        ??' '*) has_dirty=1 ;;
        *) malformed=1 ;;
      esac
      continue
    fi
    [[ -z "$record" ]] || malformed=1
    break
  done

  [[ "$malformed" == 0 ]] || return 1
  if [[ "$has_dirty" == 1 ]]; then
    printf 'dirty\n'
  elif [[ "$has_hidden" == 1 ]]; then
    printf 'hidden\n'
  elif [[ "$has_disposable" == 1 ]]; then
    printf 'disposable\n'
  else
    printf 'clean\n'
  fi
}

_gt_cleanup_status_state() {
  local path="$1" state status=0

  state=$(
    set -o pipefail
    GIT_OPTIONAL_LOCKS=0 gt_git_without_local_env -C "$path" status \
      --porcelain=v1 -z --ignored=matching --untracked-files=all \
      2>/dev/null | _gt_cleanup_classify_status "$path"
  ) || status=$?
  [[ "$status" == 0 ]] || return 1
  printf '%s\n' "$state"
}

# @brief Print a worktree's content state: clean, disposable (only untracked or
# ignored entries that are cache-tagged or configured as disposable), dirty
# (tracked changes), hidden (other untracked or ignored content, or index
# entries marked skip-worktree or assume-unchanged), or unknown.
# Ignored files such as .env or local databases count as hidden: Git's own
# removal check cannot see them, and removing the worktree would destroy them.
gt_worktree_content_state() {
  local path="$1" entry index_state state

  if ! state=$(_gt_cleanup_status_state "$path"); then
    printf 'unknown\n'
  elif [[ "$state" == dirty ]]; then
    printf 'dirty\n'
  elif ! index_state=$(GIT_OPTIONAL_LOCKS=0 \
    gt_git_without_local_env -C "$path" ls-files -v 2>/dev/null); then
    printf 'unknown\n'
  else
    while IFS= read -r entry; do
      case "$entry" in
        [a-z]' '* | S' '*)
          printf 'hidden\n'
          return 0
          ;;
      esac
    done <<<"$index_state"
    printf '%s\n' "$state"
  fi
}

_gt_cleanup_prune_entry() {
  local path="$1" entry="$2"

  [[ -e "$path/$entry" || -L "$path/$entry" ]] || return 0
  if [[ "$GT_CLEANUP_DRY_RUN" == 1 ]]; then
    gt_cleanup_report would-prune-entry "$path" disposable "$entry" \
      "would prune disposable worktree entry: $path/$entry"
  else
    gt_cleanup_report prune-entry "$path" disposable "$entry" \
      "pruning disposable worktree entry: $path/$entry"
    # One force flag deliberately preserves nested repositories. The literal
    # top-level pathspec and the post-clean state check are additional guards;
    # this never broadens into a worktree-wide clean. Quiet, because its
    # per-path output would land among a caller's records.
    GIT_OPTIONAL_LOCKS=0 gt_git_without_local_env -C "$path" \
      clean -q -fdx -- ":(top,literal)$entry" || return 1
  fi
}

_gt_cleanup_prune_disposable_entries() {
  local path="$1" configured entry existing seen tag
  local -a entries=()

  for configured in \
    ${GT_CLEANUP_PRUNE_PATHS[@]+"${GT_CLEANUP_PRUNE_PATHS[@]}"}; do
    entries+=("$configured")
  done

  for tag in \
    "$path"/*/CACHEDIR.TAG \
    "$path"/.[!.]*/CACHEDIR.TAG \
    "$path"/..?*/CACHEDIR.TAG; do
    entry=${tag#"$path"/}
    entry=${entry%/CACHEDIR.TAG}
    _gt_cleanup_entry_has_cache_tag "$path" "$entry" || continue
    seen=0
    for existing in ${entries[@]+"${entries[@]}"}; do
      if [[ "$existing" == "$entry" ]]; then
        seen=1
        break
      fi
    done
    [[ "$seen" == 1 ]] || entries+=("$entry")
  done

  for entry in ${entries[@]+"${entries[@]}"}; do
    _gt_cleanup_prune_entry "$path" "$entry" || return 1
  done
}

# @brief Succeed when a local branch still points at an expected commit OID.
gt_branch_still_at() {
  local branch="$1" expected_oid="$2" status=0

  gt_find_ref_commit "refs/heads/$branch" || status=$?
  [[ "$status" == 0 && "$GT_REF_OID" == "$expected_oid" ]]
}

_gt_cleanup_note_uninspectable() {
  [[ -z "$GT_WORKTREE_FAILED_PATH" ]] ||
    GT_CLEANUP_UNINSPECTABLE_HINT=$(gt_uninspectable_worktree_hint)
}

_gt_cleanup_keep() {
  local branch="$1" code="$2" detail="$3" message="$4"

  gt_cleanup_report keep-branch "$branch" "$code" "$detail" \
    "skipping $branch; $message"
  return 1
}

# Record why a worktree must stay for the caller to report, and fail.
_gt_cleanup_block() {
  GT_CLEANUP_KEEP_CODE=$1
  GT_CLEANUP_KEEP_DETAIL=$2
  GT_CLEANUP_KEEP_WHY=$3
  return 1
}

# Succeed when Git's worktree inventory, as last materialized, marks the
# worktree at a path locked. `git worktree remove` refuses those, and a lock
# is the owner's explicit request to leave the checkout alone.
_gt_cleanup_locked() {
  local path="$1" field current=""

  for field in ${_GT_WORKTREE_FIELDS[@]+"${_GT_WORKTREE_FIELDS[@]}"}; do
    case "$field" in
      "worktree "*) current=${field#worktree } ;;
      locked | "locked "*)
        [[ "$current" == "$path" || "$current" -ef "$path" ]] && return 0
        ;;
    esac
  done
  return 1
}

# @brief Check that a linked worktree may be removed, pruning disposable
# entries when that is all that stands in the way. Reports nothing: when
# removal must not happen it sets GT_CLEANUP_KEEP_CODE, GT_CLEANUP_KEEP_DETAIL,
# and GT_CLEANUP_KEEP_WHY for the caller to report, and returns 1.
# @param $1 Worktree path. @param $2 Branch checked out there, or "".
# @param $3 Branch tip OID that must not move before pruning, or "".
gt_cleanup_worktree_gate() {
  local path="$1" branch="$2" branch_oid="$3" operation state in_use_status

  GT_CLEANUP_KEEP_CODE=""
  GT_CLEANUP_KEEP_DETAIL=""
  GT_CLEANUP_KEEP_WHY=""
  # Git refuses to remove the main worktree only after cache pruning has
  # already touched it, so it is never eligible, even with --remove-worktrees.
  # Both paths come from the same inventory, so they agree even when the main
  # worktree is listed by its Git directory.
  gt_find_main_worktree ||
    _gt_cleanup_block uninspectable "$path" "could not inspect worktrees" ||
    return 1
  if [[ "$path" == "$GT_WORKTREE_PATH" || "$path" -ef "$GT_WORKTREE_PATH" ]]; then
    _gt_cleanup_block main-worktree "$path" \
      "checked out in the main worktree $path"
    return 1
  fi
  if _gt_cleanup_locked "$path"; then
    _gt_cleanup_block locked "$path" "worktree is locked: $path"
    return 1
  fi

  if ! operation=$(gt_worktree_operation "$path"); then
    _gt_cleanup_block uninspectable "$path" \
      "could not inspect worktree operation state: $path"
    return 1
  fi
  if [[ -n "$operation" ]]; then
    _gt_cleanup_block operation "$operation" \
      "worktree has active $operation: $path"
    return 1
  fi
  # Git removes a worktree that a shell or agent session is parked in, which
  # strands that session in a deleted directory. Check before cache pruning
  # too, since a live session may be using that cache.
  in_use_status=0
  gt_worktree_in_use "$path" || in_use_status=$?
  case "$in_use_status" in
    0)
      _gt_cleanup_block in-use "$GT_WORKTREE_USER_PID" \
        "worktree is in use by process $GT_WORKTREE_USER_PID: $path"
      return 1
      ;;
    1) ;;
    *)
      _gt_cleanup_block uninspectable "$path" \
        "could not inspect process working directories: $path"
      return 1
      ;;
  esac

  state=$(gt_worktree_content_state "$path")
  case "$state" in
    clean) ;;
    disposable)
      if [[ -n "$branch_oid" ]] && ! gt_branch_still_at "$branch" "$branch_oid"; then
        _gt_cleanup_block branch-changed "$path" \
          "branch changed before cache pruning"
        return 1
      fi
      if ! _gt_cleanup_prune_disposable_entries "$path"; then
        _gt_cleanup_block prune-failed "$path" \
          "disposable entry could not be pruned safely: $path"
        return 1
      fi
      if [[ "$GT_CLEANUP_DRY_RUN" != 1 ]]; then
        state=$(gt_worktree_content_state "$path")
        case "$state" in
          clean) ;;
          dirty)
            _gt_cleanup_block dirty "$path" \
              "worktree changed while pruning cache: $path"
            return 1
            ;;
          hidden)
            _gt_cleanup_block hidden "$path" \
              "worktree has hidden local content: $path"
            return 1
            ;;
          disposable)
            _gt_cleanup_block prune-failed "$path" \
              "disposable entry could not be pruned safely: $path"
            return 1
            ;;
          *)
            _gt_cleanup_block uninspectable "$path" \
              "could not recheck worktree status: $path"
            return 1
            ;;
        esac
      fi
      ;;
    dirty)
      _gt_cleanup_block dirty "$path" "worktree has uncommitted changes: $path"
      return 1
      ;;
    hidden)
      _gt_cleanup_block hidden "$path" "worktree has hidden local content: $path"
      return 1
      ;;
    *)
      _gt_cleanup_block uninspectable "$path" \
        "could not inspect worktree status: $path"
      return 1
      ;;
  esac
}

# @brief Remove a linked worktree that passed gt_cleanup_worktree_gate, and
# report the removal under a reason code. On failure it sets the keep fields
# like the gate and returns 1, leaving the report to the caller.
# Git's own clean check runs status with the repository's configuration, so
# make it see untracked files even where status.showUntrackedFiles=no hides
# them: a file created after the gate then still stops the removal.
# @param $1 Worktree path. @param $2 Branch checked out there, or "".
# @param $3 Reason code, such as the branch's deletion proof.
gt_cleanup_remove_worktree() {
  local path="$1" branch="$2" code="$3"

  if ! gt_cleanup_run git -c status.showUntrackedFiles=normal \
    worktree remove "$path"; then
    _gt_cleanup_block remove-failed "$path" \
      "worktree could not be removed safely: $path"
    return 1
  fi
  if [[ "$GT_CLEANUP_DRY_RUN" == 1 ]]; then
    gt_cleanup_report would-remove-worktree "$path" "$code" "$branch" ""
  else
    gt_cleanup_report remove-worktree "$path" "$code" "$branch" \
      "removed worktree $path"
  fi
}

# @brief Succeed when GT_CLEANUP_WORKTREE_SCOPE is empty or names this path.
gt_cleanup_in_scope() {
  local path="$1" scoped

  ((${#GT_CLEANUP_WORKTREE_SCOPE[@]} > 0)) || return 0
  for scoped in "${GT_CLEANUP_WORKTREE_SCOPE[@]}"; do
    [[ "$scoped" == "$path" || "$scoped" -ef "$path" ]] && return 0
  done
  return 1
}

# @brief Release a branch from its worktree when cleanup may remove it.
# Returns 0 when the branch is not checked out (or no longer will be), and 1
# after reporting why its checkout keeps it.
_gt_cleanup_release_branch() {
  local branch="$1" branch_oid="$2" code="$3" path

  if ! gt_find_worktree_reserving_branch "$branch"; then
    _gt_cleanup_note_uninspectable
    _gt_cleanup_keep "$branch" uninspectable "" \
      "could not inspect worktree reservations"
    return 1
  fi
  path=$GT_WORKTREE_PATH

  # A dry run does not really switch to the base, but the real run releases
  # the branch the current worktree leaves, so report that outcome.
  if [[ "$GT_CLEANUP_DRY_RUN" == 1 && "$GT_CLEANUP_SWITCHED_TO_BASE" == 1 &&
    -n "$GT_CLEANUP_CURRENT_BRANCH" &&
    "$branch" == "$GT_CLEANUP_CURRENT_BRANCH" ]]; then
    return 0
  fi
  # Never delete the invoking checkout's branch, and never remove that
  # checkout. The branch-name check runs first because the inventory can miss
  # it entirely: a bare repository used through GIT_DIR and GIT_WORK_TREE has
  # no branch line, and other main worktrees are listed by their Git
  # directory. The path check covers a branch the current worktree reserves
  # without having it checked out, such as during a detached bisect.
  if [[ "$GT_CLEANUP_SWITCHED_TO_BASE" != 1 &&
    -n "$GT_CLEANUP_CURRENT_BRANCH" &&
    "$branch" == "$GT_CLEANUP_CURRENT_BRANCH" ]] ||
    [[ -n "$path" && -n "$GT_CLEANUP_CURRENT_WORKTREE" &&
      "$path" -ef "$GT_CLEANUP_CURRENT_WORKTREE" ]]; then
    gt_cleanup_report keep-branch "$branch" current-worktree "$path" \
      "keeping $branch; checked out in the current worktree"
    return 1
  fi
  [[ -n "$path" ]] || return 0
  if [[ "$GT_CLEANUP_REMOVE_WORKTREES" != 1 ]] || ! gt_cleanup_in_scope "$path"; then
    _gt_cleanup_keep "$branch" checked-out "$path" \
      "checked out in worktree $path"
    return 1
  fi
  if ! gt_cleanup_worktree_gate "$path" "$branch" "$branch_oid"; then
    _gt_cleanup_keep "$branch" "$GT_CLEANUP_KEEP_CODE" \
      "$GT_CLEANUP_KEEP_DETAIL" "$GT_CLEANUP_KEEP_WHY"
    return 1
  fi
  if ! gt_branch_still_at "$branch" "$branch_oid"; then
    _gt_cleanup_keep "$branch" branch-changed "$path" \
      "branch changed during cleanup"
    return 1
  fi
  if ! gt_cleanup_remove_worktree "$path" "$branch" "$code"; then
    _gt_cleanup_keep "$branch" "$GT_CLEANUP_KEEP_CODE" \
      "$GT_CLEANUP_KEEP_DETAIL" "$GT_CLEANUP_KEEP_WHY"
    return 1
  fi
}

# @brief Delete a proven branch, removing its eligible worktree first when
# GT_CLEANUP_REMOVE_WORKTREES allows. The ref is deleted only while it still
# holds the proven OID and no worktree has claimed it in the meantime.
# @param $1 Branch. @param $2 Proven tip OID. @param $3 Proof reason code:
#   merged, content-merged, tree-landed, merged-pr, upstream-gone, or all.
# @param $4 Optional human label for the reason; defaults to the code.
# Returns 0 when the branch was deleted (or would be in a dry run).
gt_cleanup_retire_branch() {
  local branch="$1" branch_oid="$2" code="$3" reason="${4:-}"

  _gt_cleanup_release_branch "$branch" "$branch_oid" "$code" || return 1

  if ! gt_find_worktree_reserving_branch "$branch"; then
    _gt_cleanup_note_uninspectable
    _gt_cleanup_keep "$branch" uninspectable "" \
      "could not recheck worktree reservations"
    return 1
  fi
  if [[ -n "$GT_WORKTREE_PATH" && "$GT_CLEANUP_DRY_RUN" != 1 ]]; then
    _gt_cleanup_keep "$branch" reserved "$GT_WORKTREE_PATH" \
      "branch became reserved by worktree $GT_WORKTREE_PATH"
    return 1
  fi
  if ! gt_branch_still_at "$branch" "$branch_oid"; then
    _gt_cleanup_keep "$branch" branch-changed "" "branch changed during cleanup"
    return 1
  fi

  if [[ -z "$reason" ]]; then
    reason=$code
    [[ "$code" != upstream-gone ]] || reason="upstream gone"
  fi
  if [[ "$GT_CLEANUP_DRY_RUN" == 1 ]]; then
    gt_cleanup_report would-delete-branch "$branch" "$code" "$branch_oid" \
      "would delete $branch at $branch_oid ($reason)"
  else
    gt_cleanup_report delete-branch "$branch" "$code" "$branch_oid" \
      "deleting $branch ($reason)"
  fi
  if ! gt_cleanup_run git update-ref -d "refs/heads/$branch" "$branch_oid"; then
    _gt_cleanup_keep "$branch" ref-delete-failed "$branch_oid" \
      "exact ref deletion failed"
    return 1
  fi
}

# @brief Print `<kind> TAB <number>` for the GitHub pull request evidence about
# an exact commit on a repository's base branch: open (a PR still under review
# contains it, or an open PR is named after the branch), merged (a merged PR
# contains it and its merge commit is in the pinned base), closed (only a closed,
# unmerged PR contains it), or none after a complete observation. Prints nothing
# and fails on any tool, transport, paging, or shape problem: missing evidence
# is never proof. Membership is checked against the PR's own commit list, so a
# commit that merely shares a branch name proves nothing.
# @param $1 GitHub host. @param $2 owner/repository. @param $3 Branch name.
# @param $4 Commit OID. @param $5 Pinned base OID. @param $6 Base branch name.
gt_cleanup_pr_lineage() (
  local host="$1" repo="$2" branch="$3" target_oid="$4" base_oid="$5" ref="$6"
  local owner named associated pages candidates number state merged merge_oid
  local members verified merged_number='' closed_number='' open_number=''
  export LC_ALL=C

  command -v gh >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  [[ $target_oid =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ &&
    $base_oid =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || return 1
  [[ $repo =~ ^[a-z0-9][a-z0-9-]*/[a-z0-9._-]+$ ]] || return 1
  [[ -n "$host" && -n "$branch" && -n "$ref" ]] || return 1
  owner=${repo%%/*}
  # Ambient GH_REPO and GH_HOST must not redirect any query.
  unset GH_REPO GH_HOST

  # gh must finish every page before any record is considered.
  if ! associated=$(gh api --hostname "$host" --paginate --slurp \
    "repos/$repo/commits/$target_oid/pulls" 2>/dev/null); then
    # An unpublished local commit has no server object. That endpoint's
    # structured 422 response still permits the branch-name observation;
    # any other failure withholds evidence. Never parse error prose.
    jq -se 'length == 1 and (.[0] | type == "array" and length == 1
      and (.[0] | type == "object" and (.status == "422" or .status == 422)
        and .errors == null))' <<<"$associated" >/dev/null 2>&1 || return 1
    associated='[[]]'
  fi
  named=$(gh api --hostname "$host" --method GET --paginate --slurp \
    "repos/$repo/pulls" -f state=all -f "head=$owner:$branch" \
    -f per_page=100 2>/dev/null) || return 1
  named=$(jq -sce --arg repo "$repo" --arg branch "$branch" '
    if length != 1 then error("response") else .[0] end
    | if type != "array" or any(.[]; type != "array") then error("pages") else . end
    | add // []
    | if any(.[]; type != "object" or (.head.ref | type != "string") or
        (.head.repo.full_name | type != "string")) then error("head shape") else . end
    | [.[] | select(.head.ref == $branch and
        (.head.repo.full_name | ascii_downcase) == $repo)]
    | [.]
  ' <<<"$named" 2>/dev/null) || return 1
  pages=$(jq -sc --argjson named "$named" '
    if length != 1 or (.[0] | type != "array" or any(.[]; type != "array"))
    then error("pages") else .[0] + $named end
  ' <<<"$associated" 2>/dev/null) || return 1
  candidates=$(jq --slurp --raw-output --arg repo "$repo" --arg ref "$ref" '
    if length != 1 then error("response") else .[0] end
    | if type != "array" or any(.[]; type != "array") then error("pages") else . end
    | add // []
    | if any(.[]; type != "object" or
        (.number | type != "number") or .number < 1 or (.number | floor) != .number or
        (.state != "open" and .state != "closed") or
        (.base.ref | type != "string") or (.base.repo.full_name | type != "string") or
        (.merged_at != null and (.merged_at | type != "string")) or
        (.merge_commit_sha != null and (.merge_commit_sha | type != "string")))
      then error("pull request shape") else . end
    | unique_by(.number) | .[]
    | select((.base.repo.full_name | ascii_downcase) == $repo and .base.ref == $ref)
    | [.number, .state, (.merged_at != null), (.merge_commit_sha // "-")] | @tsv
  ' <<<"$pages" 2>/dev/null) || return 1
  while IFS=$'\t' read -r number state merged merge_oid; do
    [[ -n $number ]] || continue
    # An open PR on the branch itself protects later unpublished local work.
    # Associated PRs on other branches still require exact membership below.
    if [[ $state == open ]] && jq -e --argjson number "$number" \
      'any(.[][]; .number == $number)' <<<"$named" >/dev/null 2>&1; then
      open_number=$number
      continue
    fi
    members=$(gh api --hostname "$host" --paginate --slurp \
      "repos/$repo/pulls/$number/commits" 2>/dev/null) || return 1
    verified=$(jq --slurp --exit-status --raw-output --arg oid "$target_oid" '
      if length != 1 then error("response") else .[0] end
      | if type != "array" or any(.[]; type != "array") then error("pages") else . end
      | add // []
      | if any(.[]; type != "object" or (.sha | type != "string") or
          (.sha | test("^([0-9a-f]{40}|[0-9a-f]{64})$") | not)) then error("commit shape") else . end
      | any(.[]; .sha == $oid) | tostring
    ' <<<"$members" 2>/dev/null) || return 1
    [[ $verified == true ]] || continue
    if [[ $state == open ]]; then
      open_number=$number
    elif [[ $merged == true ]]; then
      # A server merge record proves landing only on this pinned local base.
      # Never fetch an unknown merge or substitute the current remote head.
      if [[ $merge_oid =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] &&
        git merge-base --is-ancestor "$merge_oid" "$base_oid" 2>/dev/null; then
        merged_number=$number
      fi
    else
      closed_number=$number
    fi
  done <<<"$candidates"
  # An exact commit still under review in another PR is live work even if an
  # earlier PR landed it, so an open PR outranks every other observation.
  if [[ -n $open_number ]]; then
    printf 'open\t%s\n' "$open_number"
  elif [[ -n $merged_number ]]; then
    printf 'merged\t%s\n' "$merged_number"
  elif [[ -n $closed_number ]]; then
    printf 'closed\t%s\n' "$closed_number"
  else
    printf 'none\t-\n'
  fi
)
