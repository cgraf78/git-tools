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

# git-tools builds its own pathspecs (`:(top,literal)<path>` for the
# overwrite prediction, cache pruning, and squash proofs) and takes none from
# the user. A global pathspec mode inherited from the caller (`git
# --literal-pathspecs <tool>` exports GIT_LITERAL_PATHSPECS=1 to the tool)
# would make Git read that magic as a literal file name, so a safety check
# matches nothing and passes: an ignored file in a sparse checkout was then
# overwritten. Clear every such mode so each pathspec means what it says.
unset GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS \
  GIT_ICASE_PATHSPECS

# Git's auto maintenance never runs from git-tools. Fetch, merge, rebase,
# commit, and am start `git maintenance run --auto` when they finish, and its
# default strategy since Git 2.54 (like any `gc --auto` that decides to
# collect) runs `git worktree prune`: a linked worktree moved without `git
# worktree repair`, idle past gc.worktreePruneExpire, loses its registration
# for good, and its branch then reads as checked out nowhere, free to delete.
# maintenance.auto=false stops it, and gc.auto=0 stops the `gc --auto` that
# Git without maintenance.auto (before 2.30) runs instead. Exported as
# command-scope configuration, which outranks every config file, so it covers
# every Git write here and in the git-tools commands these start without a
# flag at each call site, and dry-run output still shows the plain command.
# The old 'key=value' form is the one every supported Git reads; appended last
# so it wins over an inherited value, and only once per environment.
GT_GIT_NO_AUTO_MAINTENANCE="'maintenance.auto=false' 'gc.auto=0'"
case "${GIT_CONFIG_PARAMETERS:-}" in
  "$GT_GIT_NO_AUTO_MAINTENANCE" | *" $GT_GIT_NO_AUTO_MAINTENANCE") ;;
  "") export GIT_CONFIG_PARAMETERS="$GT_GIT_NO_AUTO_MAINTENANCE" ;;
  *) export GIT_CONFIG_PARAMETERS="$GIT_CONFIG_PARAMETERS $GT_GIT_NO_AUTO_MAINTENANCE" ;;
esac

# @brief Run Git's own binary (see above) with the given arguments.
git() {
  command "$GT_GIT" "$@"
}
