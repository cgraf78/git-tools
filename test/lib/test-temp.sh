#!/usr/bin/env bash
# Private, invocation-owned temporary roots for shell test harnesses.

GT_TEST_TEMP_ROOT=${GT_TEST_TEMP_ROOT:-}
_GT_TEST_TEMP_PARENT=${_GT_TEST_TEMP_PARENT:-}

gt_test_temp_cleanup() {
  local root=${GT_TEST_TEMP_ROOT:-}

  [[ -n "$root" && -n "${_GT_TEST_TEMP_PARENT:-}" ]] || return 0
  case "$root" in
    "$_GT_TEST_TEMP_PARENT"/git-tools-test.*) ;;
    *) return 1 ;;
  esac
  rm -rf -- "$root" || return 1
  GT_TEST_TEMP_ROOT=""
}

_gt_test_temp_on_exit() {
  local status=$?

  trap - EXIT HUP INT TERM
  gt_test_temp_cleanup || status=1
  exit "$status"
}

_gt_test_temp_on_signal() {
  local status="$1"

  trap - EXIT HUP INT TERM
  gt_test_temp_cleanup || true
  exit "$status"
}

gt_test_temp_init() {
  local old_umask parent root

  [[ -z "${GT_TEST_TEMP_ROOT:-}" ]] || return 1
  parent=$(cd -P -- "${TMPDIR:-/tmp}" 2>/dev/null && pwd) || return 1
  old_umask=$(umask)
  umask 077
  root=$(mktemp -d "$parent/git-tools-test.XXXXXX") || {
    umask "$old_umask"
    return 1
  }
  chmod 700 "$root" || {
    rm -rf -- "$root"
    umask "$old_umask"
    return 1
  }
  umask "$old_umask"
  _GT_TEST_TEMP_PARENT=$parent
  GT_TEST_TEMP_ROOT=$root
  trap _gt_test_temp_on_exit EXIT
  trap '_gt_test_temp_on_signal 129' HUP
  trap '_gt_test_temp_on_signal 130' INT
  trap '_gt_test_temp_on_signal 143' TERM
}

gt_test_temp_dir() {
  local old_umask dir

  [[ -n "${GT_TEST_TEMP_ROOT:-}" && -d "$GT_TEST_TEMP_ROOT" &&
    ! -L "$GT_TEST_TEMP_ROOT" ]] || return 1
  old_umask=$(umask)
  umask 077
  dir=$(mktemp -d "$GT_TEST_TEMP_ROOT/case.XXXXXX") || {
    umask "$old_umask"
    return 1
  }
  chmod 700 "$dir" || {
    rm -rf -- "$dir"
    umask "$old_umask"
    return 1
  }
  umask "$old_umask"
  printf '%s\n' "$dir"
}
