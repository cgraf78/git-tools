#!/usr/bin/env bash
# Run Git's own binary for every `git` command in git-tools.
#
# A `git` earlier on PATH can be a launcher or wrapper that reroutes commands:
# a dotfiles launcher, for example, sends `git -C $HOME ...` to a GIT_DIR the
# caller just cleared, which once let a run by name merge into $HOME. Sourcing
# this file defines a `git` shell function that runs the binary in Git's exec
# path instead, so every plain `git` call in the sourcing script, its functions,
# and its subshells reaches real Git. Child processes that look `git` up on
# PATH (`env ... git`) must use "$GT_GIT" instead.
#
# The binary is resolved once per process when this file is first sourced:
# from GIT_EXEC_PATH, which Git exports to the commands it runs (so `git
# pr-land` costs nothing), or else from one `git --exec-path` with any stale
# GIT_EXEC_PATH cleared. Linux, Apple, Homebrew, and Termux Git all ship `git`
# in that directory. A command started by name then gets the environment Git
# gives its subcommands: GIT_EXEC_PATH exported and that directory first on
# PATH, so child commands (other git-tools, gh) skip the lookup and reach real
# Git too. When no exec-path binary exists, git-tools says so and falls back to
# `git` on PATH.
#
# GIT_TOOLS_TEST_PATH_GIT=1 is an explicit test override: test suites put fake
# `git` programs on PATH to inject failures, and this keeps them in the loop.

if [[ "${_GT_GIT_RESOLVED:-}" != "$$" ]]; then
  # An inherited GT_GIT is never trusted; it is recomputed for this process.
  GT_GIT=git
  if [[ "${GIT_TOOLS_TEST_PATH_GIT:-}" != 1 ]]; then
    # A usable GIT_EXEC_PATH answers without starting a process.
    if [[ -n "${GIT_EXEC_PATH:-}" && -f "$GIT_EXEC_PATH/git" &&
      -x "$GIT_EXEC_PATH/git" ]]; then
      _gt_git_dir=$GIT_EXEC_PATH
    else
      # A stale GIT_EXEC_PATH (inherited from a hook or an editor that Git
      # started, say, after a Git upgrade removed that directory) would only
      # echo back, so ask without it.
      _gt_git_reported=$(env -u GIT_EXEC_PATH git --exec-path 2>/dev/null) ||
        _gt_git_reported=""
      _gt_git_dir=$_gt_git_reported
      [[ -n "$_gt_git_dir" && -f "$_gt_git_dir/git" &&
        -x "$_gt_git_dir/git" ]] || _gt_git_dir=""
    fi
    if [[ -n "$_gt_git_dir" ]]; then
      GT_GIT=$_gt_git_dir/git
      export GIT_EXEC_PATH="$_gt_git_dir"
      case "$PATH" in
        "$_gt_git_dir" | "$_gt_git_dir":*) ;;
        *) export PATH="$_gt_git_dir:$PATH" ;;
      esac
    elif command -v git >/dev/null 2>&1; then
      # Name the directory Git itself reported, and drop a stale inherited one
      # so the fallback Git can still find its own helpers.
      printf 'git-tools: note: no git binary in Git exec path %s; using git from PATH\n' \
        "${_gt_git_reported:-${GIT_EXEC_PATH:-(unknown)}}" >&2
      unset GIT_EXEC_PATH
    fi
    unset _gt_git_dir _gt_git_reported
  fi
  _GT_GIT_RESOLVED=$$
fi

# @brief Run Git's own binary (see above) with the given arguments.
git() {
  command "$GT_GIT" "$@"
}
