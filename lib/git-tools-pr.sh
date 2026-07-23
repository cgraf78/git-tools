#!/usr/bin/env bash
# Shared helpers for GitHub pull-request workflow commands.

gt_command=${gt_command:-git-tools}

# Never trust inherited values for destructive-operation safety checks.
GT_CURRENT_REPO_IDENTITY=""
GT_CURRENT_REPO_HOST=""
GT_CURRENT_REPO_SPEC=""
GT_CURRENT_REPO_DEFAULT_BRANCH=""

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
  local status

  status=$(git status --porcelain) || gt_die "could not inspect worktree status"
  if [[ -n "$status" ]]; then
    gt_die "worktree must be clean"
  fi
}

gt_require_gh() {
  command -v gh >/dev/null 2>&1 ||
    gt_usage_error "gh is not installed or not on PATH"
  gt_load_current_repo_identity ||
    gt_die "could not resolve the current GitHub repository"
  GH_REPO="$GT_CURRENT_REPO_SPEC" GH_HOST="$GT_CURRENT_REPO_HOST" \
    gh auth status --hostname "$GT_CURRENT_REPO_HOST" >/dev/null 2>&1 ||
    gt_die "gh is not authenticated"
}

# @brief Run a gh PR operation pinned to the verified checkout repository.
gt_gh_pr() {
  gt_load_current_repo_identity || return 2
  GH_REPO="$GT_CURRENT_REPO_SPEC" GH_HOST="$GT_CURRENT_REPO_HOST" \
    gh pr "$@" --repo "$GT_CURRENT_REPO_SPEC"
}

gt_current_branch() {
  git symbolic-ref -q --short HEAD 2>/dev/null ||
    gt_usage_error "detached HEAD is not supported"
}

gt_pr_view_tsv() {
  local target="$1" output expected_number="" expected_head=""
  local record_number record_head
  local -a args=(view) record_fields=()
  gt_validate_pr_target_repository "$target" || return 1
  [[ -z "$target" ]] || args+=("$target")

  # Keep field extraction in gh's structured output path. Human PR titles can
  # contain punctuation freely; using tab-separated fields avoids scraping the
  # default presentation output.
  output=$(gt_gh_pr "${args[@]}" \
    --json number,state,isDraft,mergeStateStatus,headRefName,headRefOid,baseRefName,headRepository,isCrossRepository,url,title \
    --jq '[.number,.state,.isDraft,.mergeStateStatus,.headRefName,.headRefOid,.baseRefName,(.headRepository.nameWithOwner // ""),.isCrossRepository,.url,.title] | @tsv') || return 1
  gt_validate_pr_record_tsv "$output" || return 1
  IFS=$'\t' read -r -a record_fields <<<"$output"
  record_number=${record_fields[0]}
  record_head=${record_fields[4]}
  case "$target" in
    http://* | https://*)
      gt_parse_pr_url "$target" || return 1
      expected_number=$GT_PR_URL_NUMBER
      ;;
    *)
      if [[ "$target" =~ ^[1-9][0-9]*$ ]]; then
        expected_number=$target
      elif [[ -n "$target" ]]; then
        git check-ref-format "refs/heads/$target" >/dev/null 2>&1 || return 1
        expected_head=$target
      fi
      ;;
  esac
  [[ -z "$expected_number" || "$record_number" == "$expected_number" ]] || return 1
  [[ -z "$expected_head" || "$record_head" == "$expected_head" ]] || return 1
  printf '%s\n' "$output"
}

gt_pr_list_open_tsv() {
  local output record count=0

  output=$(gt_gh_pr list --state open --limit 201 \
    --json number,state,isDraft,mergeStateStatus,headRefName,headRefOid,baseRefName,headRepository,isCrossRepository,url,title \
    --jq '.[] | [.number,.state,.isDraft,.mergeStateStatus,.headRefName,.headRefOid,.baseRefName,(.headRepository.nameWithOwner // ""),.isCrossRepository,.url,.title] | @tsv') || return 1
  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    gt_validate_pr_record_tsv "$record" || return 1
    count=$((count + 1))
  done <<<"$output"
  if ((count > 200)); then
    printf 'git-tools: open pull request inventory exceeds 200 entries\n' >&2
    return 1
  fi
  [[ -z "$output" ]] || printf '%s\n' "$output"
}

# @brief Normalize an HTTPS, SSH, or scp-style GitHub repository URL.
# Prints a case-folded host/owner/repository identity.
gt_github_repo_identity_from_url() {
  local url="$1" rest authority host path owner repo userinfo="" normalized

  case "$url" in
    *$'\n'* | *$'\r'* | *$'\t'* | *' '* | *'='* | *'?'* | *'#'*) return 1 ;;
  esac

  case "$url" in
    http://* | https://*)
      rest=${url#*://}
      authority=${rest%%/*}
      [[ "$authority" != "$rest" ]] || return 1
      path=${rest#*/}
      [[ "$authority" != *@* ]] || return 1
      host=$authority
      ;;
    ssh://*)
      rest=${url#ssh://}
      authority=${rest%%/*}
      [[ "$authority" != "$rest" ]] || return 1
      path=${rest#*/}
      host=${authority##*@}
      if [[ "$authority" == *@* ]]; then
        userinfo=${authority%@*}
        [[ "$userinfo" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
      fi
      ;;
    *@*:*)
      authority=${url%%:*}
      path=${url#*:}
      userinfo=${authority%@*}
      host=${authority##*@}
      [[ "$userinfo" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
      ;;
    *) return 1 ;;
  esac
  [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
  [[ "$host" != *..* && "$host" != *:* ]] || return 1
  path=${path#/}
  path=${path%/}
  path=${path%.git}
  owner=${path%%/*}
  repo=${path#*/}
  [[ -n "$host" && -n "$owner" && -n "$repo" && "$repo" != */* ]] || return 1
  normalized=$(gt_github_name_with_owner "$owner/$repo") || return 1
  printf '%s/%s\n' "$host" "$normalized" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

# @brief Normalize a structured GitHub nameWithOwner value.
gt_github_name_with_owner() {
  local name="$1" owner repo

  [[ "$name" == */* && "$name" != */*/* ]] || return 1
  owner=${name%%/*}
  repo=${name#*/}
  [[ "$owner" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  [[ "$repo" =~ ^[A-Za-z0-9._-]+$ && "$repo" != . && "$repo" != .. ]] || return 1
  printf '%s/%s\n' "$owner" "$repo" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

# @brief Derive the exact GitHub head-repository identity from structured PR data.
gt_pr_head_repo_identity() {
  local head_repo="$1" pr_url="$2" rest authority host normalized

  normalized=$(gt_github_name_with_owner "$head_repo") || return 1
  case "$pr_url" in
    http://* | https://*)
      rest=${pr_url#*://}
      authority=${rest%%/*}
      [[ "$authority" != "$rest" ]] || return 1
      host=${authority##*@}
      [[ "$authority" != *@* && "$host" != *:* ]] || return 1
      ;;
    *) return 1 ;;
  esac
  printf '%s/%s\n' "$host" "$normalized" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

# @brief Parse a GitHub pull request URL without conflating its repository and
# pull request identities. Sets GT_PR_URL_IDENTITY, GT_PR_URL_NUMBER, and whether
# a path follows the number. A suffix is accepted for user-supplied URLs, while
# structured gh output is required to be canonical by the record validator.
gt_parse_pr_url() {
  local url="$1" rest authority host path owner repo marker number suffix=""

  GT_PR_URL_IDENTITY=""
  GT_PR_URL_NUMBER=""
  GT_PR_URL_HAS_SUFFIX=0

  case "$url" in
    http://* | https://*)
      rest=${url#*://}
      authority=${rest%%/*}
      [[ "$authority" != "$rest" ]] || return 1
      host=${authority##*@}
      [[ "$authority" != *@* && "$host" != *:* ]] || return 1
      path=${rest#*/}
      ;;
    *) return 1 ;;
  esac
  owner=${path%%/*}
  path=${path#*/}
  repo=${path%%/*}
  path=${path#*/}
  marker=${path%%/*}
  path=${path#*/}
  if [[ "$path" == */* ]]; then
    number=${path%%/*}
    suffix=${path#*/}
    GT_PR_URL_HAS_SUFFIX=1
  else
    number=$path
  fi
  [[ -n "$owner" && -n "$repo" && "$marker" == pull ]] || return 1
  [[ "$number" =~ ^[1-9][0-9]*$ ]] || return 1
  GT_PR_URL_IDENTITY=$(printf '%s/%s/%s\n' "$host" "$owner" "$repo" |
    LC_ALL=C tr '[:upper:]' '[:lower:]')
  GT_PR_URL_NUMBER=$number
  # Keep the local referenced so set -u and older ShellCheck versions agree the
  # suffix split is intentional even though callers only need its presence.
  : "$suffix"
}

# @brief Derive a repository identity from a GitHub pull request URL.
gt_pr_repo_identity_from_url() {
  gt_parse_pr_url "$1" || return 1
  printf '%s\n' "$GT_PR_URL_IDENTITY"
}

# @brief Load the repository selected by gh for the current checkout.
gt_load_current_repo_identity() {
  local output name url extra identity normalized_name identity_name

  [[ -z "${GT_CURRENT_REPO_IDENTITY:-}" ]] || return 0
  output=$(
    unset GH_REPO GH_HOST
    gh repo view \
      --json nameWithOwner,url \
      --jq '[.nameWithOwner,.url] | @tsv'
  ) || return 1
  IFS=$'\t' read -r name url extra <<<"$output"
  [[ -n "$name" && -n "$url" && -z "$extra" ]] || return 1
  [[ "$output" != *$'\n'* ]] || return 1
  [[ "$name" == */* && "$name" != */*/* ]] || return 1
  identity=$(gt_github_repo_identity_from_url "$url") || return 1
  normalized_name=$(printf '%s\n' "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  identity_name=${identity#*/}
  [[ "$identity_name" == "$normalized_name" ]] || return 1
  GT_CURRENT_REPO_IDENTITY=$identity
  GT_CURRENT_REPO_HOST=${identity%%/*}
  GT_CURRENT_REPO_SPEC=$identity
}

# @brief Load the structured default branch for the already-validated checkout
# repository. The explicit route prevents a foreign remote or ambient gh
# configuration from selecting another repository's default.
gt_load_current_repo_default_branch() {
  local output

  [[ -z "${GT_CURRENT_REPO_DEFAULT_BRANCH:-}" ]] || return 0
  gt_load_current_repo_identity || return 1
  output=$(GH_REPO="$GT_CURRENT_REPO_SPEC" GH_HOST="$GT_CURRENT_REPO_HOST" \
    gh repo view --repo "$GT_CURRENT_REPO_SPEC" \
    --json defaultBranchRef \
    --jq '.defaultBranchRef.name // ""') || return 1
  [[ -n "$output" && "$output" != *$'\n'* ]] || return 1
  git check-ref-format "refs/heads/$output" >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2034 # consumed by git-pr-open after dynamic source
  GT_CURRENT_REPO_DEFAULT_BRANCH=$output
}

# @brief Validate a URL target before asking gh to resolve a pull request.
# Returns 1 for a foreign or malformed URL and 2 when current identity fails.
gt_validate_pr_target_repository() {
  local target="$1" identity

  case "$target" in
    http://* | https://*) ;;
    *) return 0 ;;
  esac
  identity=$(gt_pr_repo_identity_from_url "$target") || return 1
  gt_load_current_repo_identity || return 2
  [[ "$identity" == "$GT_CURRENT_REPO_IDENTITY" ]]
}

# @brief Validate the canonical URL returned in structured PR data.
gt_validate_pr_url_repository() {
  local url="$1" identity

  identity=$(gt_pr_repo_identity_from_url "$url") || return 1
  gt_load_current_repo_identity || return 2
  [[ "$identity" == "$GT_CURRENT_REPO_IDENTITY" ]]
}

# @brief Validate that one structured PR record belongs to this checkout.
gt_validate_pr_record_tsv() {
  local record="$1" rest field current_name head_name
  local number state draft merge_state head head_oid base head_repo cross url title
  local -a fields=()

  [[ -n "$record" && "$record" != *$'\n'* ]] || return 1
  rest=$record
  while [[ "$rest" == *$'\t'* ]]; do
    field=${rest%%$'\t'*}
    fields+=("$field")
    rest=${rest#*$'\t'}
  done
  fields+=("$rest")
  ((${#fields[@]} == 11)) || return 1
  number=${fields[0]}
  state=${fields[1]}
  draft=${fields[2]}
  merge_state=${fields[3]}
  head=${fields[4]}
  head_oid=${fields[5]}
  base=${fields[6]}
  head_repo=${fields[7]}
  cross=${fields[8]}
  url=${fields[9]}
  title=${fields[10]}

  [[ "$number" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$head_oid" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || return 1
  [[ -n "$state" && -n "$merge_state" && -n "$head" && -n "$base" ]] || return 1
  case "$draft" in true | false) ;; *) return 1 ;; esac
  case "$cross" in true | false) ;; *) return 1 ;; esac
  git check-ref-format "refs/heads/$head" >/dev/null 2>&1 || return 1
  git check-ref-format "refs/heads/$base" >/dev/null 2>&1 || return 1

  gt_load_current_repo_identity || return 1
  current_name=${GT_CURRENT_REPO_IDENTITY#*/}
  head_name=$(gt_github_name_with_owner "$head_repo") || return 1
  case "$cross" in
    false)
      [[ "$head_name" == "$current_name" && "$head" != "$base" ]] || return 1
      ;;
    true)
      [[ "$head_name" != "$current_name" ]] || return 1
      ;;
  esac

  gt_parse_pr_url "$url" || return 1
  [[ "$GT_PR_URL_HAS_SUFFIX" == 0 ]] || return 1
  [[ "$GT_PR_URL_IDENTITY" == "$GT_CURRENT_REPO_IDENTITY" ]] || return 1
  [[ "$GT_PR_URL_NUMBER" == "$number" ]] || return 1
  : "$title"
}

# @brief Print the mutation-relevant identity and topology of one validated PR
# record: number, head, head OID, base, normalized head repository,
# cross-repository flag, and canonical URL.
gt_pr_record_topology_tsv() {
  local record="$1" number state draft merge_state head head_oid base head_repo cross url title
  local normalized_head_repo

  gt_validate_pr_record_tsv "$record" || return 1
  IFS=$'\t' read -r number state draft merge_state head head_oid base head_repo \
    cross url title <<<"$record"
  normalized_head_repo=$(gt_github_name_with_owner "$head_repo") || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$number" "$head" "$head_oid" "$base" "$normalized_head_repo" "$cross" "$url"
  : "$state" "$draft" "$merge_state" "$title"
}

# @brief Build a canonical topology record from fields already carried by a
# stack handoff. Validation is shared with ordinary gh records.
gt_pr_topology_tsv() {
  local number="$1" head="$2" head_oid="$3" base="$4" head_repo="$5"
  local cross="$6" url="$7"
  local record

  record=$(printf '%s\tOPEN\tfalse\tCLEAN\t%s\t%s\t%s\t%s\t%s\t%s\texpected' \
    "$number" "$head" "$head_oid" "$base" "$head_repo" "$cross" "$url")
  gt_pr_record_topology_tsv "$record"
}

# @brief Require a live validated PR record to match an expected canonical
# topology string exactly.
gt_pr_record_matches_topology() {
  local record="$1" expected="$2" actual
  local number head head_oid base head_repo cross url extra canonical_expected

  [[ -n "$expected" && "$expected" != *$'\n'* ]] || return 1
  IFS=$'\t' read -r number head head_oid base head_repo cross url extra <<<"$expected"
  [[ -n "$number" && -n "$head" && -n "$head_oid" && -n "$base" && -n "$head_repo" &&
    -n "$cross" && -n "$url" && -z "$extra" ]] || return 1
  canonical_expected=$(gt_pr_topology_tsv \
    "$number" "$head" "$head_oid" "$base" "$head_repo" "$cross" "$url") || return 1
  actual=$(gt_pr_record_topology_tsv "$record") || return 1
  [[ "$actual" == "$canonical_expected" ]]
}

# @brief Require two independently read PR records to describe the same
# mutation-relevant identity and topology.
gt_pr_records_match_topology() {
  local first second

  first=$(gt_pr_record_topology_tsv "$1") || return 1
  second=$(gt_pr_record_topology_tsv "$2") || return 1
  [[ "$first" == "$second" ]]
}

# @brief Resolve one configured fetch remote whose sole effective URL maps to
# the current checkout repository. Sets GT_REPO_FETCH_REMOTE and
# GT_REPO_FETCH_REMOTE_URL. Returns 1 when no unique mapping exists and 2 when
# Git cannot inspect remote configuration.
gt_find_current_repo_fetch_remote() {
  local records remote urls identity match="" match_url="" matches=0
  local urls_rc

  GT_REPO_FETCH_REMOTE=""
  GT_REPO_FETCH_REMOTE_URL=""
  gt_load_current_repo_identity || return 2
  records=$(git remote) || return 2
  while IFS= read -r remote; do
    [[ -n "$remote" && "$remote" != "." ]] || continue
    urls_rc=0
    urls=$(git remote get-url --all "$remote" 2>/dev/null) || urls_rc=$?
    [[ "$urls_rc" == 0 ]] || return 2
    [[ -n "$urls" && "$urls" != *$'\n'* ]] || continue
    identity=$(gt_github_repo_identity_from_url "$urls") || continue
    [[ "$identity" == "$GT_CURRENT_REPO_IDENTITY" ]] || continue
    matches=$((matches + 1))
    match=$remote
    match_url=$urls
  done <<<"$records"

  [[ "$matches" == 1 && -n "$match" ]] || return 1
  # Consumed by PR command scripts after this sourced helper returns.
  # shellcheck disable=SC2034
  GT_REPO_FETCH_REMOTE=$match
  # shellcheck disable=SC2034
  GT_REPO_FETCH_REMOTE_URL=$match_url
}

# @brief Resolve the feature branch's push target independently of the base
# branch. Prefer explicit push configuration; with no preference, accept only a
# single configured remote. Sets the named remote, its captured expanded URL,
# and normalized GitHub repository identity.
gt_find_branch_push_remote() {
  local branch="$1" preferred="" status=0 records remote candidate=""
  local candidate_url="" configured expanded configured_identity expanded_identity matches=0

  GT_BRANCH_PUSH_REMOTE=""
  GT_BRANCH_PUSH_REPO_IDENTITY=""
  GT_BRANCH_PUSH_REMOTE_URL=""
  preferred=$(git config "branch.$branch.pushRemote" 2>/dev/null) || status=$?
  [[ "$status" == 0 || "$status" == 1 ]] || return 2
  if [[ -z "$preferred" ]]; then
    status=0
    preferred=$(git config remote.pushDefault 2>/dev/null) || status=$?
    [[ "$status" == 0 || "$status" == 1 ]] || return 2
  fi
  if [[ -z "$preferred" ]]; then
    status=0
    preferred=$(git config "branch.$branch.remote" 2>/dev/null) || status=$?
    [[ "$status" == 0 || "$status" == 1 ]] || return 2
  fi
  [[ "$preferred" != . ]] || return 1

  records=$(git remote) || return 2
  while IFS= read -r remote; do
    [[ -n "$remote" && "$remote" != "." ]] || continue
    [[ -z "$preferred" || "$remote" == "$preferred" ]] || continue
    status=0
    configured=$(git config --get-all "remote.$remote.pushurl" 2>/dev/null) || status=$?
    if [[ "$status" == 1 ]]; then
      status=0
      configured=$(git config --get-all "remote.$remote.url" 2>/dev/null) || status=$?
    fi
    [[ "$status" == 0 ]] || return 2
    [[ -n "$configured" && "$configured" != *$'\n'* ]] || continue
    configured_identity=$(gt_github_repo_identity_from_url "$configured") || continue
    expanded=$(git remote get-url --push --all "$remote" 2>/dev/null) || return 2
    [[ -n "$expanded" && "$expanded" != *$'\n'* ]] || continue
    expanded_identity=$(gt_github_repo_identity_from_url "$expanded") || continue
    [[ "$configured_identity" == "$expanded_identity" ]] || continue
    matches=$((matches + 1))
    candidate=$remote
    candidate_url=$expanded
    # shellcheck disable=SC2034 # consumed by git-pr-open after dynamic source
    GT_BRANCH_PUSH_REPO_IDENTITY=$expanded_identity
  done <<<"$records"

  [[ "$matches" == 1 && -n "$candidate" ]] || return 1
  # shellcheck disable=SC2034 # consumed by git-pr-open after dynamic source
  GT_BRANCH_PUSH_REMOTE=$candidate
  # shellcheck disable=SC2034 # consumed by git-pr-open after dynamic source
  GT_BRANCH_PUSH_REMOTE_URL=$candidate_url
}

# @brief Resolve one configured remote only when its sole push target maps to
# the structured PR head repository. Sets GT_PR_HEAD_REMOTE and the validated,
# once-expanded GT_PR_HEAD_REMOTE_URL; returns 1 when no exact mapping exists
# and 2 when Git cannot inspect remote configuration.
gt_find_pr_head_remote() {
  local head="$1" head_repo="$2" pr_url="$3"
  local expected preferred preferred_rc=0 records remote match="" match_url="" matches=0
  local configured configured_rc expanded expanded_rc identity

  GT_PR_HEAD_REMOTE=""
  GT_PR_HEAD_REMOTE_URL=""
  expected=$(gt_pr_head_repo_identity "$head_repo" "$pr_url") || return 1
  preferred=$(git config "branch.$head.remote" 2>/dev/null) || preferred_rc=$?
  [[ "$preferred_rc" == 0 || "$preferred_rc" == 1 ]] || return 2
  records=$(git remote) || return 2

  while IFS= read -r remote; do
    [[ -n "$remote" && "$remote" != "." ]] || continue
    configured_rc=0
    configured=$(git config --get-all "remote.$remote.pushurl" 2>/dev/null) ||
      configured_rc=$?
    if [[ "$configured_rc" == 1 ]]; then
      configured_rc=0
      configured=$(git config --get-all "remote.$remote.url" 2>/dev/null) ||
        configured_rc=$?
    fi
    [[ "$configured_rc" == 0 ]] || {
      [[ "$configured_rc" == 1 ]] && continue
      return 2
    }
    [[ -n "$configured" && "$configured" != *$'\n'* ]] || continue
    identity=$(gt_github_repo_identity_from_url "$configured") || continue
    [[ "$identity" == "$expected" ]] || continue

    expanded_rc=0
    expanded=$(git remote get-url --push --all "$remote" 2>/dev/null) ||
      expanded_rc=$?
    [[ "$expanded_rc" == 0 ]] || return 2
    [[ -n "$expanded" && "$expanded" != *$'\n'* ]] || continue
    identity=$(gt_github_repo_identity_from_url "$expanded") || continue
    [[ "$identity" == "$expected" ]] || continue
    matches=$((matches + 1))
    if [[ -z "$match" || "$remote" == "$preferred" ]]; then
      match=$remote
      match_url=$expanded
    fi
  done <<<"$records"

  [[ "$matches" == 1 && -n "$match" ]] || return 1
  # Consumed by PR command scripts after this sourced helper returns.
  # shellcheck disable=SC2034
  GT_PR_HEAD_REMOTE=$match
  # shellcheck disable=SC2034
  GT_PR_HEAD_REMOTE_URL=$match_url
}

gt_pr_checks_status() {
  local target="$1"
  local output status
  local -a args=(checks)
  # shellcheck disable=SC2016 # `$buckets` is jq state inside gh's --jq filter.
  local check_state_filter='[.[].bucket] as $buckets | if any($buckets[]; . != "pass" and . != "skipping" and . != "fail" and . != "cancel" and . != "pending") then error("unknown check bucket") elif ($buckets | length) == 0 then "none" elif any($buckets[]; . == "fail" or . == "cancel") then "fail" elif any($buckets[]; . == "pending") then "pending" else "pass" end'
  gt_validate_pr_target_repository "$target" || return 1
  [[ -z "$target" ]] || args+=("$target")

  set +e
  output=$(
    gt_gh_pr "${args[@]}" \
      --json bucket \
      --jq "$check_state_filter" 2>&1
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
          printf 'none\n'
          return 0
          ;;
      esac
      printf '%s\n' "$output" >&2
      return "$status"
      ;;
  esac
}

gt_checks_ready_state() {
  local state="$1"

  # Keep merge/readiness control flow on a small internal enum generated by
  # `gh --jq`, not on a best-effort parse of rendered JSON. Unknown states fail
  # closed so a GitHub schema/filter change cannot silently approve a PR.
  case "$state" in
    none | fail | pending | pass)
      printf '%s\n' "$state"
      ;;
    *)
      gt_die "could not parse pull request check status"
      ;;
  esac
}

gt_bool() {
  case "$1" in
    true | TRUE | 1) return 0 ;;
    *) return 1 ;;
  esac
}

# @brief Load open PRs once for repeated by-branch lookups.
# Best-effort: GitHub data is optional, so a missing or unauthenticated gh
# leaves GT_PR_AVAILABLE=false and callers fall back to local-only output.
# Sets GT_PR_AVAILABLE and caches records in GT_PR_RECORDS.
gt_pr_load() {
  GT_PR_AVAILABLE=false
  GT_PR_RECORDS=""

  command -v gh >/dev/null 2>&1 || return 0
  gt_load_current_repo_identity >/dev/null 2>&1 || return 0
  GH_REPO="$GT_CURRENT_REPO_SPEC" GH_HOST="$GT_CURRENT_REPO_HOST" \
    gh auth status --hostname "$GT_CURRENT_REPO_HOST" >/dev/null 2>&1 || return 0

  GT_PR_RECORDS=$(gt_pr_list_open_tsv 2>/dev/null || true)
  GT_PR_AVAILABLE=true
}

# @brief Print the open PR number whose head ref is the given branch.
# Requires a prior gt_pr_load. Returns 1 when no PR matches or PR data is
# unavailable.
gt_pr_number_for_branch() {
  local branch="$1" number head

  [[ "${GT_PR_AVAILABLE:-false}" == true ]] || return 1
  [[ -n "${GT_PR_RECORDS:-}" ]] || return 1

  # gt_pr_list_open_tsv fields: number, state, isDraft, mergeStateStatus,
  # headRefName, headRefOid, base, head repository, cross-repository flag, URL,
  # and title.
  while IFS=$'\t' read -r number _ _ _ head _; do
    [[ "$head" == "$branch" ]] || continue
    printf '%s\n' "$number"
    return 0
  done <<<"$GT_PR_RECORDS"

  return 1
}
