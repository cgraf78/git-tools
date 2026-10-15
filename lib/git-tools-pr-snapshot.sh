#!/usr/bin/env bash
# Batched GitHub pull-request snapshots: one GraphQL query per chunk of pull
# requests, a response classifier, and a jq checks classifier that reduces a
# snapshot to stateless facts. Callers own retries, timing, and judgment.
#
# Requires lib/git-tools-pr.sh: the argument builder pins every call to the
# verified checkout identity (GT_CURRENT_REPO_HOST and GT_CURRENT_REPO_SPEC).

# Pull requests per query. GitHub cancels a GraphQL query after about ten
# seconds, and query time grows with the number of checks returned, so large
# batches of busy pull requests time out. Callers halve a chunk on timeout.
# shellcheck disable=SC2034 # consumed by git-pr-watch after dynamic source
GT_PR_SNAPSHOT_CHUNK=8

# Never trust an inherited value: callers remove this path on exit.
GT_PR_SNAPSHOT_TMP=""
# Per-call time limit in seconds for gt_pr_snapshot_call; 0 means none.
GT_PR_CALL_TIMEOUT=0

# @brief Run gh with color and debug output forced off.
# Forced color (CLICOLOR_FORCE, GH_FORCE_TTY) wraps `gh api -i` header names in
# escape sequences, which would hide rate-limit and SSO headers from the
# classifier. NO_COLOR alone does not override CLICOLOR_FORCE. The subshell
# keeps the scrub from leaking into the caller.
gt_pr_gh() {
  (
    unset CLICOLOR_FORCE GH_FORCE_TTY GH_DEBUG
    export NO_COLOR=1
    command gh "$@"
  )
}

# @brief Print the snapshot GraphQL query for one chunk of pull requests.
# @param $1 Number of pull requests in the chunk.
# Aliases are zero-padded (p00, p01, ...) because gh's jq sorts object keys.
# Each alias takes its own integer variable so no number is interpolated into
# the query text.
# shellcheck disable=SC2016 # GraphQL variables, not shell expansions.
gt_pr_snapshot_query() {
  local count="$1" i alias var

  printf 'query PrWatchSnapshot($owner: String!, $name: String!'
  for ((i = 0; i < count; i++)); do
    printf ', $n%02d: Int!' "$i"
  done
  printf ') {\n  repository(owner: $owner, name: $name) {\n'
  for ((i = 0; i < count; i++)); do
    alias=$(printf 'p%02d' "$i")
    var=$(printf 'n%02d' "$i")
    cat <<EOF
    $alias: pullRequest(number: \$$var) {
      number url state isDraft mergeable mergeStateStatus reviewDecision
      baseRefName headRefName headRefOid isCrossRepository
      autoMergeRequest { enabledAt }
      commits(last: 1) { nodes { commit {
        oid
        statusCheckRollup { contexts(first: 100) { totalCount nodes {
          __typename
          ... on CheckRun {
            databaseId name status conclusion completedAt
            isRequired(pullRequestNumber: \$$var)
            checkSuite {
              databaseId status conclusion app { databaseId slug }
              workflowRun { event file { path } workflow { databaseId } }
            }
          }
          ... on StatusContext {
            context state createdAt isRequired(pullRequestNumber: \$$var)
          }
        } } }
        checkSuites(last: 50) { totalCount nodes {
          databaseId status conclusion app { slug }
          checkRuns(first: 0) { totalCount }
          workflowRun { event file { path } }
        } }
      } } }
    }
EOF
  done
  printf '  }\n}\n'
}

# @brief Print the branch lookup query used to resolve a head branch to a PR.
gt_pr_branch_query() {
  cat <<'EOF'
query PrWatchBranch($owner: String!, $name: String!, $head: String!) {
  repository(owner: $owner, name: $name) {
    pullRequests(headRefName: $head, first: 10,
        orderBy: { field: CREATED_AT, direction: DESC }) {
      nodes { number state isCrossRepository }
    }
  }
}
EOF
}

# The checks classifier. It turns one snapshot response into stateless facts,
# one line per record, fields separated by single spaces with `-` for an empty
# value and any free text last as a JSON string:
#
#   pr <alias> num=<n> state=<E> mergeable=<E> mss=<E> review=<E> head=<oid>
#      judged=<oid> headmatch=<yes|no> cross=<true|false> am=<true|false>
#      checks=<verdict> zero=<-|pending|approval|fail> nchecks=<n> ref=<ref>
#   chk <alias> class=<fail|cancel> running=<y|n|-> req=<yes|no>
#       kind=<actions|app|status> id=<n> done=<iso> name=<json>
#   suite <alias> conclusion=<E> workflow=<json>
#
# checks verdict priority: too-many > fail-running > fail-completed > pending
# > pass > none. `pass` needs every judged check's suite COMPLETED because
# Actions creates a dependent (`needs:`) job only after the jobs it waits on
# finish; until then a passing first stage would look like a finished run.
# A failure is final at once ("fail-running") only while a job in its suite
# that was created before it is still unfinished: the run is genuinely still
# going. A failure in a suite that is open again with only newer unfinished
# jobs, or none yet, belongs to an attempt being re-run (a re-run creates new
# jobs, with higher ids, before replacing the old ones): pending, and no `chk`
# record, so it is never confirmed as a failure. Any other failure in a
# finished suite is "fail-completed" and waits out the confirmation window.
#
# The newest Actions suite per workflow and event replaces older suites on the
# same commit (a re-run, or a run that cancelled an older one through a
# concurrency group), including dependent jobs the newer run has not created
# yet. Once the newest run has finished, an older run's failure for a job name
# the newest run does not have still counts, as it does on GitHub (a later run
# that skipped that job, say); older cancelled or skipped jobs do not. Zero-run Actions suites that await
# approval, failed to start, or are still queued count as runs too, so they
# cannot be mistaken for "no CI". A zero-run suite that ended any other way
# (cancelled while queued, say) replaces nothing: it must not hide an older
# run's failure.
#
# Display text is sanitized by Unicode category before it is JSON-escaped:
# control and format characters (incl. bidi controls, zero-width characters,
# and tag characters), line/paragraph separators, and variation selectors are
# removed, then the text is truncated. Check names come from workflow files,
# which a pull request author can write.
#
# The program sticks to what both jq 1.6 and gh's built-in gojq support:
# RE2-compatible regexes and no reliance on object key order (aliases are
# sorted explicitly). Times stay raw ISO strings; jq 1.6 date functions depend
# on the local time zone, so callers convert them in shell.
# shellcheck disable=SC2016,SC2034 # jq variables; consumed by callers.
GT_PR_CHECKS_JQ='
def clean: tostring
  | gsub("[\\p{Cc}\\p{Cf}\\x{2028}\\x{2029}\\x{FE00}-\\x{FE0F}\\x{E0100}-\\x{E01EF}]"; "")
  | .[:80] | tojson;
def oid: if type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$") then . else "-" end;
def int: if type == "number" and . == floor and . >= 0 then tostring else "-" end;
def enum: if type == "string" and test("^[A-Z_]{1,40}$") then . else "-" end;
def iso: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$") then . else "-" end;
def ref: if type == "string" and test("^[A-Za-z0-9._/+=@,-]{1,255}$")
    and (test("\\.\\.|//|^/|/$|\\.lock$|\\.$|^-|@\\{") | not) then . else "-" end;
def kind: if .__typename == "StatusContext" then "status"
  elif .checkSuite.workflowRun != null then "actions" else "app" end;
def wfkey: [.app.slug // "", (.workflowRun.file.path // (.workflowRun.workflow.databaseId // "" | tostring)), .workflowRun.event // ""];
def bucket:
  if kind == "status" then
    ({"SUCCESS": "pass", "PENDING": "pending", "EXPECTED": "pending",
      "FAILURE": "fail", "ERROR": "fail"}[.state // ""] // "fail")
  elif (.status // "") != "COMPLETED" then "pending"
  else
    ({"SUCCESS": "pass", "SKIPPED": "skipping", "NEUTRAL": "skipping",
      "FAILURE": "fail", "ERROR": "fail", "TIMED_OUT": "fail",
      "ACTION_REQUIRED": "fail", "STARTUP_FAILURE": "fail", "STALE": "fail",
      "CANCELLED": "cancel"}[.conclusion // ""] // "fail")
  end;
def dkey:
  if kind == "status" then ["s", .context]
  elif kind == "actions" then ["a", (.checkSuite.app.databaseId // 0 | tostring)] + (.checkSuite | wfkey) + [.name]
  else ["c", .checkSuite.app.slug // "", .name] end;

.data.repository | to_entries | sort_by(.key)[] | .key as $alias | .value as $p
| select($p != null)
| ($p.commits.nodes[0].commit // {}) as $c
| ($c.statusCheckRollup.contexts // {nodes: [], totalCount: 0}) as $ctx
| ([$ctx.nodes[]? | objects]) as $all
| ([$c.checkSuites.nodes[]? | objects
    | select(.app.slug == "github-actions" and .workflowRun != null
        and (.workflowRun.event // "") != "dynamic" and .checkRuns.totalCount == 0)
    | . + {z: (if .conclusion == "ACTION_REQUIRED" then "approval"
        elif (.conclusion // "") as $k | ["FAILURE", "STARTUP_FAILURE"] | index($k) then "fail"
        elif .status != "COMPLETED" then "pending" else "-" end)}
    | select(.z != "-")]) as $zero_all
| (reduce ($all[] | select(kind == "actions") | .checkSuite) as $s ({};
      .[($s | wfkey | tojson)] as $cur
      | if ($s.databaseId // 0) >= ($cur.id // 0)
        then .[($s | wfkey | tojson)] = {id: ($s.databaseId // 0), done: ($s.status == "COMPLETED")}
        else . end)
   | reduce ($zero_all[]) as $s (.;
      .[($s | wfkey | tojson)] as $cur
      | if ($s.databaseId // 0) >= ($cur.id // 0)
        then .[($s | wfkey | tojson)] = {id: ($s.databaseId // 0), done: ($s.status == "COMPLETED")}
        else . end)) as $newest
| ([$all[] | select(kind == "actions"
      and (.checkSuite.databaseId // 0) == ($newest[(.checkSuite | wfkey | tojson)].id // 0))
    | [(.checkSuite | wfkey | tojson), .name] | tojson] | unique) as $newest_names
| ([$all[] | . as $k | select(kind != "actions"
      or (.checkSuite.databaseId // 0) == ($newest[(.checkSuite | wfkey | tojson)].id // 0)
      or (($newest[(.checkSuite | wfkey | tojson)].done // false)
        and ([[(.checkSuite | wfkey | tojson), .name] | tojson] | inside($newest_names) | not)
        and (bucket != "cancel" and bucket != "skipping")))]
   | group_by(dkey) | map(max_by(.databaseId // 0) | . + {b: bucket})) as $checks
| ($checks | map(select(kind != "status" and (.status // "") != "COMPLETED")
    | {suite: .checkSuite.databaseId, id: (.databaseId // 0)})) as $unfinished
| ($checks | map(. as $k | . + {
      open: (kind != "status" and (.checkSuite.status // "") != "COMPLETED"),
      run: (if kind == "status" then "-"
        elif any($unfinished[]; .suite == $k.checkSuite.databaseId) then "y" else "n" end),
      early: (kind != "status" and any($unfinished[];
        .suite == $k.checkSuite.databaseId and .id < ($k.databaseId // 0)))})) as $checks
| ($checks | map(select((.b == "fail" or .b == "cancel") and (.early or (.open | not))))) as $failing
| ($zero_all | map(select((.databaseId // 0) == ($newest[(wfkey | tojson)].id // 0)))) as $zero
| (if ($ctx.totalCount // 0) > 100 or ($c.checkSuites.totalCount // 0) > 50 then "too-many"
   elif any($failing[]; .b == "fail" and .early) then "fail-running"
   elif ($failing | length) > 0 then "fail-completed"
   elif any($checks[]; .b == "pending" or .run == "y" or .open or .b == "fail" or .b == "cancel") then "pending"
   elif ($checks | length) > 0 then "pass"
   else "none" end) as $verdict
| (if any($zero[]; .z == "fail") then "fail"
   elif any($zero[]; .z == "approval") then "approval"
   elif any($zero[]; .z == "pending") then "pending" else "-" end) as $zv
| ($c.oid // null | oid) as $judged
| "pr \($alias) num=\($p.number | int) state=\($p.state | enum) mergeable=\($p.mergeable | enum) mss=\($p.mergeStateStatus | enum) review=\($p.reviewDecision | enum) head=\($p.headRefOid | oid) judged=\($judged) headmatch=\(if $judged != "-" and $judged == ($p.headRefOid | oid) then "yes" else "no" end) cross=\($p.isCrossRepository == true) am=\($p.autoMergeRequest != null) checks=\($verdict) zero=\($zv) nchecks=\($checks | length) ref=\($p.headRefName | ref)",
  ($failing[]
   | "chk \($alias) class=\(.b) running=\(if .early then "y" elif kind == "status" then "-" else "n" end) req=\(if .isRequired == true then "yes" else "no" end) kind=\(kind) id=\(.databaseId // null | int) done=\((.completedAt // .createdAt // null) | iso) name=\((.name // .context // "") | clean)"),
  ($zero[] | select(.z == "fail")
   | "suite \($alias) conclusion=\(.conclusion | enum) workflow=\((.workflowRun.file.path // "") | clean)")
'

# @brief Build the gh argv for one snapshot or lookup call.
# Sets GT_PR_GH_ARGV. The repository host comes from the verified checkout
# identity, never from ambient GH_HOST/GH_REPO, which are unset for the call.
# @param $1 Query text.
# @param $2 jq program.
# @param $@ Remaining arguments: extra `-f`/`-F` variable assignments.
# shellcheck disable=SC2034 # GT_PR_GH_ARGV is consumed by callers.
gt_pr_snapshot_argv() {
  local query="$1" jq_program="$2" owner name
  shift 2

  owner=${GT_CURRENT_REPO_SPEC#*/}
  name=${owner#*/}
  owner=${owner%%/*}
  GT_PR_GH_ARGV=(api graphql -i --hostname "$GT_CURRENT_REPO_HOST"
    -f "query=$query" -f "owner=$owner" -f "name=$name" "$@"
    --jq "$jq_program")
}

# @brief Print the epoch seconds for a UTC calendar time.
# Pure shell so results never depend on the local time zone or on which date(1)
# is installed. Uses the days-from-civil algorithm.
_gt_civil_epoch() {
  local y=$((10#$1)) m=$((10#$2)) d=$((10#$3))
  local hh=$((10#$4)) mm=$((10#$5)) ss=$((10#$6)) era yoe doy doe days

  ((m <= 2)) && y=$((y - 1))
  era=$(((y >= 0 ? y : y - 399) / 400))
  yoe=$((y - era * 400))
  doy=$(((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  days=$((era * 146097 + doe - 719468))
  printf '%s\n' $((days * 86400 + hh * 3600 + mm * 60 + ss))
}

# @brief Convert a GitHub ISO-8601 UTC timestamp (2026-10-15T14:14:10Z) to epoch.
gt_iso_epoch() {
  local value="$1"

  [[ "$value" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?Z$ ]] ||
    return 1
  _gt_civil_epoch "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
    "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
}

# @brief Convert an HTTP Date header (Thu, 15 Oct 2026 14:14:10 GMT) to epoch.
gt_http_date_epoch() {
  local value="$1" month

  [[ "$value" =~ ^[A-Za-z]{3},\ ([0-9]{1,2})\ ([A-Za-z]{3})\ ([0-9]{4})\ ([0-9]{2}):([0-9]{2}):([0-9]{2})\ GMT$ ]] ||
    return 1
  case "${BASH_REMATCH[2]}" in
    Jan) month=1 ;; Feb) month=2 ;; Mar) month=3 ;; Apr) month=4 ;;
    May) month=5 ;; Jun) month=6 ;; Jul) month=7 ;; Aug) month=8 ;;
    Sep) month=9 ;; Oct) month=10 ;; Nov) month=11 ;; Dec) month=12 ;;
    *) return 1 ;;
  esac
  _gt_civil_epoch "${BASH_REMATCH[3]}" "$month" "${BASH_REMATCH[1]}" \
    "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
}

# @brief Classify one `gh api -i` result.
# @param $1 File holding gh's stdout (status line, headers, blank line, body).
# @param $2 gh's exit status.
# @param $3 gh's stderr, if captured.
# Sets GT_PR_RESPONSE_CLASS to one of ok, rate-limited, auth, sso, not-found,
# timeout, transient, error (a permanent failure); GT_PR_RESPONSE_BODY (jq
# output on success, raw body otherwise); GT_PR_RESPONSE_DATE (server epoch
# from the Date header, or empty); GT_PR_RESPONSE_RESET (epoch when a rate
# limit lifts, or empty); GT_PR_RESPONSE_MESSAGE (a sanitized diagnostic for
# error and transient classes, or empty).
#
# gh applies --jq only to a successful response. On GraphQL errors (also on
# HTTP 200) it prints the raw body and exits 1; on a body that is not JSON
# (gateway errors) it prints only the headers. Header names arrive in Go's
# canonical case (X-Ratelimit-Remaining), so they are compared case-folded.
# shellcheck disable=SC2034 # result globals are consumed by callers.
gt_pr_classify_response() {
  local file="$1" rc="$2" errors="${3:-}" line status="" name value in_body=0
  local body="" restore="" remaining="" reset="" retry_after="" sso=0 date=""

  GT_PR_RESPONSE_CLASS=transient
  GT_PR_RESPONSE_BODY=""
  GT_PR_RESPONSE_DATE=""
  GT_PR_RESPONSE_RESET=""
  GT_PR_RESPONSE_MESSAGE=""

  # nocasematch folds header-name case without a process per header; it is
  # turned back off before returning so the caller's matching is unaffected.
  if ! shopt -q nocasematch; then
    restore=1
    shopt -s nocasematch
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_body" == 1 ]]; then
      body+="$line"$'\n'
      continue
    fi
    line=${line%$'\r'}
    if [[ -z "$status" ]]; then
      [[ "$line" =~ ^HTTP/[0-9.]+\ ([0-9]{3}) ]] || break
      status=${BASH_REMATCH[1]}
      continue
    fi
    if [[ -z "$line" ]]; then
      in_body=1
      continue
    fi
    name=${line%%:*}
    value=${line#*:}
    value=${value# }
    case "$name" in
      x-ratelimit-remaining) remaining=$value ;;
      x-ratelimit-reset) reset=$value ;;
      retry-after) retry_after=$value ;;
      x-github-sso) sso=1 ;;
      date) date=$value ;;
    esac
  done <"$file"
  [[ -z "$restore" ]] || shopt -u nocasematch
  body=${body%$'\n'}
  GT_PR_RESPONSE_BODY=$body
  GT_PR_RESPONSE_DATE=$(gt_http_date_epoch "$date" 2>/dev/null) || GT_PR_RESPONSE_DATE=""

  if [[ -z "$status" ]]; then
    # No response at all. gh exits 4 when it has no usable credentials;
    # anything else (a network failure, say) may succeed on a retry.
    [[ "$rc" != 4 ]] || GT_PR_RESPONSE_CLASS=auth
    GT_PR_RESPONSE_MESSAGE=$(_gt_pr_first_line "$errors")
    return 0
  fi
  # A successful response is used even when it spent the last rate-limit
  # point (X-RateLimit-Remaining: 0 on the call that reached the limit).
  if [[ "$status" == 200 && "$rc" == 0 ]]; then
    GT_PR_RESPONSE_CLASS=ok
  elif [[ "$status" == 401 ]]; then
    GT_PR_RESPONSE_CLASS=auth
  elif [[ "$status" == 403 && "$sso" == 1 ]]; then
    GT_PR_RESPONSE_CLASS=sso
  elif [[ "$status" == 200 && "$body" == *'"type":"NOT_FOUND"'* ]]; then
    # Structured error types are checked before the plain-text matches below:
    # a partial-error body still carries the found pull requests' data, whose
    # check names a pull request author can write.
    GT_PR_RESPONSE_CLASS=not-found
  elif [[ "$remaining" == 0 || "$retry_after" =~ ^[0-9]+$ || "$status" == 429 ||
    "$body" == *'"type":"RATE_LIMITED"'* || "$body" == *"secondary rate limit"* ]]; then
    GT_PR_RESPONSE_CLASS=rate-limited
    if [[ "$retry_after" =~ ^[0-9]+$ && "$GT_PR_RESPONSE_DATE" =~ ^[0-9]+$ ]]; then
      GT_PR_RESPONSE_RESET=$((GT_PR_RESPONSE_DATE + retry_after))
    elif [[ "$remaining" == 0 && "$reset" =~ ^[0-9]+$ ]]; then
      GT_PR_RESPONSE_RESET=$reset
    elif [[ "$GT_PR_RESPONSE_DATE" =~ ^[0-9]+$ ]]; then
      # A secondary limit without Retry-After: GitHub asks for at least a
      # minute's pause.
      GT_PR_RESPONSE_RESET=$((GT_PR_RESPONSE_DATE + 60))
    fi
  elif [[ "$status" == 502 || "$status" == 504 ||
    "$body" == *'"type":"RESOURCE_LIMITS_EXCEEDED"'* ||
    "$body" == *"result of a timeout"* ]]; then
    GT_PR_RESPONSE_CLASS=timeout
  elif [[ "$status" == 200 && -z "$body" ]]; then
    # gh prints nothing on stdout both when GitHub cut a query off (an empty
    # body gh cannot parse) and when the jq program failed on the response.
    # Only the first is worth retrying.
    case "$errors" in
      "" | *"unexpected end of JSON input"*) GT_PR_RESPONSE_CLASS=timeout ;;
      *)
        GT_PR_RESPONSE_CLASS=error
        GT_PR_RESPONSE_MESSAGE=$(_gt_pr_first_line "$errors")
        ;;
    esac
  elif [[ "$status" == 4?? || "$body" == *'"type":"FORBIDDEN"'* ||
    "$body" == *'"type":"INSUFFICIENT_SCOPES"'* ||
    "$body" == *'"code":"undefinedField"'* ||
    "$body" == *'"code":"argumentNotAccepted"'* ]]; then
    # Errors that fail the same way on every retry: a client error, missing
    # token scopes, or a field an older GitHub Enterprise does not have.
    # Anything unrecognized stays transient and is retried.
    GT_PR_RESPONSE_CLASS=error
    GT_PR_RESPONSE_MESSAGE=$(_gt_pr_error_message "$body")
  else
    GT_PR_RESPONSE_MESSAGE=$(_gt_pr_error_message "$body")
  fi
}

# @brief Print the first line of a diagnostic as printable ASCII, capped.
# GitHub's and gh's messages are ASCII; anything else (control characters,
# escape sequences, C1 bytes) becomes `?` so it cannot drive a terminal.
_gt_pr_first_line() {
  local LC_ALL=C text="${1%%$'\n'*}"

  text=${text//[^ -~]/?}
  printf '%s' "${text:0:200}"
}

# @brief Print the first "message" in a GitHub error body, sanitized.
_gt_pr_error_message() {
  local body="$1"

  if [[ "$body" =~ \"message\":\"([^\"]{1,200}) ]]; then
    _gt_pr_first_line "${BASH_REMATCH[1]}"
  fi
}

# @brief Print the aliases a NOT_FOUND response names in its error paths.
# Every alias is a key under `data`, so only the error `path` identifies the
# missing ones.
gt_pr_not_found_aliases() {
  local body="$1" rest alias

  rest=$body
  while [[ "$rest" =~ \"path\":\[\"repository\",\"(p[0-9]{2})\"\] ]]; do
    alias=${BASH_REMATCH[1]}
    printf '%s\n' "$alias"
    rest=${rest#*\"path\":\[\"repository\",\""$alias"\"\]}
  done
}

# @brief Build the per-alias number variables for one snapshot chunk.
# Sets GT_PR_SNAPSHOT_VARS. Numbers are validated because gh reads an `-F`
# value that starts with `@` as a file path.
# shellcheck disable=SC2034 # GT_PR_SNAPSHOT_VARS is consumed by callers.
gt_pr_snapshot_vars() {
  local i=0 number

  GT_PR_SNAPSHOT_VARS=()
  for number in "$@"; do
    [[ "$number" =~ ^[1-9][0-9]{0,9}$ ]] || return 1
    GT_PR_SNAPSHOT_VARS+=(-F "$(printf 'n%02d' "$i")=$number")
    i=$((i + 1))
  done
}

# @brief Run the gh call in GT_PR_GH_ARGV and classify its response.
# The response and gh's diagnostics go through a private temporary directory
# whose path is published in GT_PR_SNAPSHOT_TMP for the duration of the call,
# so a caller's signal handler can remove it.
#
# With GT_PR_CALL_TIMEOUT set to a positive number of seconds, gh runs in the
# background under a watchdog that kills it when the time is up; a call ended
# that way classifies as `timeout`. The watchdog kills gh itself, so it works
# even if the caller dies first. It sleeps in one-second slices so a
# termination that arrives before its first sleep starts leaves at most a
# one-second orphan. Callers that trap signals should kill their background
# jobs (`jobs -p`) in the handler.
gt_pr_snapshot_call() {
  local rc=0 errors="" dir gh_pid watchdog limit=${GT_PR_CALL_TIMEOUT:-0}

  GT_PR_SNAPSHOT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/git-pr-snapshot.XXXXXX") || {
    GT_PR_SNAPSHOT_TMP=""
    GT_PR_RESPONSE_CLASS=transient
    return 1
  }
  dir=$GT_PR_SNAPSHOT_TMP
  if [[ "$limit" =~ ^[1-9][0-9]*$ ]]; then
    # env replaces itself with gh, so the job's pid is gh's own and killing
    # it cannot leave gh running behind a wrapper shell. Same scrub as
    # gt_pr_gh.
    env -u GH_HOST -u GH_REPO -u CLICOLOR_FORCE -u GH_FORCE_TTY -u GH_DEBUG \
      NO_COLOR=1 gh "${GT_PR_GH_ARGV[@]}" >"$dir/out" 2>"$dir/err" &
    gh_pid=$!
    (
      slept=0
      sleeper=""
      # Reap the sleep it kills, so no zombie is left where orphans go to a
      # process that never reaps them (a container's minimal init, say).
      trap '[[ -z "$sleeper" ]] || { kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; }; exit 0' TERM
      while ((slept < limit)); do
        # The `done` marker also stops the watchdog: a TERM sent before this
        # freshly forked shell installed its trap can be lost.
        [[ ! -e "$dir/done" ]] || exit 0
        sleep 1 &
        sleeper=$!
        wait "$sleeper" || true
        sleeper=""
        slept=$((slept + 1))
      done
      [[ ! -e "$dir/done" ]] || exit 0
      : >"$dir/timed-out"
      kill -TERM "$gh_pid" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    watchdog=$!
    wait "$gh_pid" || rc=$?
    : >"$dir/done"
    kill -TERM "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
  else
    (
      unset GH_HOST GH_REPO
      gt_pr_gh "${GT_PR_GH_ARGV[@]}"
    ) >"$dir/out" 2>"$dir/err" || rc=$?
  fi
  errors=$(cat "$dir/err" 2>/dev/null) || errors=""
  gt_pr_classify_response "$dir/out" "$rc" "$errors"
  if [[ -e "$dir/timed-out" ]]; then
    GT_PR_RESPONSE_CLASS=timeout
    GT_PR_RESPONSE_MESSAGE="gh did not answer within $limit seconds"
  fi
  rm -rf -- "$dir"
  GT_PR_SNAPSHOT_TMP=""
}

# @brief Snapshot one chunk of pull requests with a jq program.
# @param $1 jq program (GT_PR_CHECKS_JQ, or a caller's own projection).
# @param $@ Pull request numbers (at most GT_PR_SNAPSHOT_CHUNK).
# Classifies the response into the GT_PR_RESPONSE_* globals. Returns 1 only
# when the numbers are invalid or no temporary file could be created.
gt_pr_snapshot() {
  local jq_program="$1"
  shift

  gt_pr_snapshot_vars "$@" || return 1
  gt_pr_snapshot_argv "$(gt_pr_snapshot_query $#)" "$jq_program" \
    "${GT_PR_SNAPSHOT_VARS[@]}"
  gt_pr_snapshot_call
}

# Resolves a head branch to one pull request number from this repository: the
# open one, else the newest merged or closed one (so a branch keeps resolving
# after auto-merge lands it). Pull requests from forks never match: anyone can
# open one with any head branch name, so a fork must not stand in for this
# repository's own pull request; watch those by number or URL. Prints the
# number, `ambiguous` when several open pull requests match, or nothing.
# shellcheck disable=SC2016,SC2034 # jq variables; consumed by callers.
GT_PR_BRANCH_JQ='
[.data.repository.pullRequests.nodes[]? | objects
  | select(.isCrossRepository == false)] as $own
| ($own | map(select(.state == "OPEN"))) as $open
| (if ($open | length) == 1 then $open[0].number
   elif ($open | length) > 1 then "ambiguous"
   else ($own[0].number // "") end)
| tostring
'
