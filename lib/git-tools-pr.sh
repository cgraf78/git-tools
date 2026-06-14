#!/usr/bin/env bash
# Shared helpers for GitHub pull-request workflow commands.

gt_command=${gt_command:-git-tools}

gt_usage_error() {
  printf '%s: %s\n' "$gt_command" "$*" >&2
  exit 2
}

gt_die() {
  printf '%s: %s\n' "$gt_command" "$*" >&2
  exit 1
}

gt_say() {
  printf '%s: %s\n' "$gt_command" "$*" >&2
}

gt_require_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 ||
    gt_usage_error "not inside a git repository"
  [[ "$(git rev-parse --is-bare-repository)" == "false" ]] ||
    gt_usage_error "bare repositories are not supported"
}

gt_require_clean_worktree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    gt_die "worktree must be clean"
  fi
}

gt_require_gh() {
  command -v gh >/dev/null 2>&1 ||
    gt_usage_error "gh is not installed or not on PATH"
  gh auth status >/dev/null 2>&1 ||
    gt_die "gh is not authenticated"
}

gt_current_branch() {
  git symbolic-ref -q --short HEAD 2>/dev/null ||
    gt_usage_error "detached HEAD is not supported"
}

gt_pr_view_tsv() {
  local target="$1"
  local -a args=(pr view)
  [[ -z "$target" ]] || args+=("$target")

  # Keep field extraction in gh's structured output path. Human PR titles can
  # contain punctuation freely; using tab-separated fields avoids scraping the
  # default presentation output.
  gh "${args[@]}" \
    --json number,state,isDraft,mergeStateStatus,headRefName,baseRefName,url,title \
    --jq '[.number,.state,.isDraft,.mergeStateStatus,.headRefName,.baseRefName,.url,.title] | @tsv'
}

gt_pr_list_open_tsv() {
  gh pr list --state open --limit 200 \
    --json number,state,isDraft,mergeStateStatus,headRefName,baseRefName,url,title \
    --jq '.[] | [.number,.state,.isDraft,.mergeStateStatus,.headRefName,.baseRefName,.url,.title] | @tsv'
}

gt_pr_checks_status() {
  local target="$1"
  local output status
  local -a args=(pr checks)
  [[ -z "$target" ]] || args+=("$target")

  set +e
  output=$(
    gh "${args[@]}" \
      --json bucket \
      --jq '[.[].bucket] | group_by(.) | map({key: .[0], value: length}) | from_entries' 2>&1
  )
  status=$?
  set -e

  case "$status" in
    0 | 8)
      printf '%s\n' "$output"
      return 0
      ;;
    *)
      case "$output" in
        *"no checks reported"*)
          printf '{"none":1}\n'
          return 0
          ;;
      esac
      printf '%s\n' "$output" >&2
      return "$status"
      ;;
  esac
}

gt_checks_bucket_count() {
  local json="$1"
  local bucket="$2"
  case "$json" in
    *\"$bucket\":*)
      printf '%s\n' "$json" |
        sed -n "s/.*\"$bucket\":[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p"
      ;;
    *)
      printf '0\n'
      ;;
  esac
}

gt_checks_ready_state() {
  local json="$1"
  local fail pending cancel
  local none

  none=$(gt_checks_bucket_count "$json" none)
  fail=$(gt_checks_bucket_count "$json" fail)
  pending=$(gt_checks_bucket_count "$json" pending)
  cancel=$(gt_checks_bucket_count "$json" cancel)

  if [[ "$none" != 0 ]]; then
    printf 'none\n'
  elif [[ "$fail" != 0 || "$cancel" != 0 ]]; then
    printf 'fail\n'
  elif [[ "$pending" != 0 ]]; then
    printf 'pending\n'
  else
    printf 'pass\n'
  fi
}

gt_bool() {
  case "$1" in
    true | TRUE | 1) return 0 ;;
    *) return 1 ;;
  esac
}
