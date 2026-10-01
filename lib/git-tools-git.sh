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
# pr-land` costs nothing), or else from one `git --exec-path`. Linux, Apple,
# Homebrew, and Termux Git all ship `git` in that directory. When it is missing
# there, git-tools says so and falls back to `git` on PATH.
#
# GIT_TOOLS_TEST_PATH_GIT=1 is an explicit test override: test suites put fake
# `git` programs on PATH to inject failures, and this keeps them in the loop.

if [[ "${_GT_GIT_RESOLVED:-}" != "$$" ]]; then
  # An inherited GT_GIT is never trusted; it is recomputed for this process.
  GT_GIT=git
  if [[ "${GIT_TOOLS_TEST_PATH_GIT:-}" != 1 ]]; then
    _gt_git_exec_path=${GIT_EXEC_PATH:-}
    [[ -n "$_gt_git_exec_path" ]] ||
      _gt_git_exec_path=$(command git --exec-path 2>/dev/null) ||
      _gt_git_exec_path=""
    if [[ -n "$_gt_git_exec_path" && -f "$_gt_git_exec_path/git" &&
      -x "$_gt_git_exec_path/git" ]]; then
      GT_GIT=$_gt_git_exec_path/git
    elif command -v git >/dev/null 2>&1; then
      printf 'git-tools: note: no git binary in Git exec path %s; using git from PATH\n' \
        "${_gt_git_exec_path:-(unknown)}" >&2
    fi
    unset _gt_git_exec_path
  fi
  _GT_GIT_RESOLVED=$$
fi

# @brief Run Git's own binary (see above) with the given arguments.
git() {
  command "$GT_GIT" "$@"
}
