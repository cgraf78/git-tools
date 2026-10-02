#!/usr/bin/env bash
# Default signal dispositions for suites that deliver signals to their cases.

# Re-exec the calling suite once with INT and TERM at their default action
# when it inherited either one ignored.
#
# A non-interactive shell starts background jobs with SIGINT ignored (for
# example `test/run &` from a script), and a parent may ignore TERM as well.
# Bash can neither trap nor reset a signal that was ignored when it started,
# and every fixture inherits the disposition, so a case that waits for INT or
# TERM to stop a child would wait forever. `env --default-signal` (GNU
# coreutils 8.31+) resets them; python3 is the fallback elsewhere, and it also
# resets SIGPIPE and SIGXFSZ, which the interpreter itself ignores. HUP is left
# alone: `nohup` asked for it to be ignored, so callers skip HUP cases instead.
#
# Call first, before the suite installs any trap (`trap -p` then reports only
# inherited dispositions), as: gt_test_default_signals "${BASH_SOURCE[0]}" "$@"
# Afterwards gt_test_signal_ignored tells cases whose signal still cannot be
# delivered (no reset tool was available) to report themselves as skipped.
gt_test_default_signals() {
  local script="$1" signal
  shift

  _GT_TEST_IGNORED_SIGNALS=""
  for signal in HUP INT TERM; do
    [[ -z "$(trap -p "$signal")" ]] ||
      _GT_TEST_IGNORED_SIGNALS+=" $signal"
  done
  # Bash before 4 may not list signals ignored at entry in `trap -p` (macOS
  # /bin/bash is 3.2), so ask python3, which reports an inherited SIG_IGN.
  if ((BASH_VERSINFO[0] < 4)) && [[ -z "$_GT_TEST_IGNORED_SIGNALS" ]] &&
    _gt_test_python_usable; then
    _GT_TEST_IGNORED_SIGNALS=" $(python3 -I -c '
import signal
print(" ".join(name for name in ("HUP", "INT", "TERM")
               if signal.getsignal(getattr(signal, "SIG" + name)) is signal.SIG_IGN))
' 2>/dev/null)"
  fi
  # The guard is one-shot and never reaches the suite's own children, so a
  # nested suite started with INT ignored still resets for itself.
  if [[ -n "${GIT_TOOLS_TEST_SIGNAL_RESET:-}" ]]; then
    unset GIT_TOOLS_TEST_SIGNAL_RESET
    return 0
  fi
  case "$_GT_TEST_IGNORED_SIGNALS " in
    *" INT "* | *" TERM "*) ;;
    *) return 0 ;;
  esac
  # The new shell would source a startup file again.
  unset BASH_ENV ENV
  if env --default-signal=INT,TERM true 2>/dev/null; then
    GIT_TOOLS_TEST_SIGNAL_RESET=1 exec env --default-signal=INT,TERM \
      "$BASH" "$script" "$@"
  fi
  if _gt_test_python_usable; then
    # shellcheck disable=SC2016 # Python source, not shell.
    GIT_TOOLS_TEST_SIGNAL_RESET=1 exec python3 -I -c '
import os, signal, sys
for name in ("SIGINT", "SIGTERM", "SIGPIPE", "SIGXFSZ"):
    if hasattr(signal, name):
        signal.signal(getattr(signal, name), signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])
' "$BASH" "$script" "$@"
  fi
  return 0
}

# A python3 that actually runs: macOS ships a /usr/bin/python3 stub that only
# offers to install developer tools, and a failed exec would end the suite.
_gt_test_python_usable() {
  command -v python3 >/dev/null 2>&1 && python3 -I -c '' >/dev/null 2>&1
}

# Succeed when SIGNAL was inherited ignored and is still ignored, so a case
# that needs to deliver it should skip rather than hang.
gt_test_signal_ignored() {
  [[ " ${_GT_TEST_IGNORED_SIGNALS:-} " == *" $1 "* ]]
}
