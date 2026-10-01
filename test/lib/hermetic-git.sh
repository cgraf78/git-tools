#!/usr/bin/env bash
# Hermetic Git environment for shell test harnesses.

# Point the current suite at the real Git with private configuration.
#
# Fixtures and the tools under test both run plain `git`, so anything the
# caller's environment feeds Git would otherwise reach every case: a Git
# launcher earlier on PATH, global, XDG, or system settings (`commit.gpgSign`,
# hooks, `init.defaultBranch`), command-scope configuration exported by a login
# shell (`GIT_CONFIG_COUNT`, `GIT_CONFIG_PARAMETERS`), repository variables
# inherited from a Git hook or alias (`GIT_DIR`, `GIT_INDEX_FILE`), identity or
# date overrides, and SSH overrides the push-target checks deliberately reject.
#
# Call once near the top of a suite, before any fixture or tool runs. Suites set
# their own GIT_* and GIT_TOOLS_* variables per case after this point, so every
# inherited GIT_* name is dropped except the `GIT_TOOLS_TEST_*` harness
# namespace. HOME moves under ROOT, and the XDG cache, data, and state roots
# follow it so tools cannot write into the caller's real directories.
#
# Real Git is GIT_TOOLS_TEST_REAL_GIT when the caller sets it (to test a
# specific build), otherwise the last `git` on PATH: the convention suites
# already use to bypass wrappers in their own fake-git shims. It is reached
# through a regular-file wrapper first on PATH rather than a symlink, because
# install.sh skips symlinked Git and would otherwise fall through to whatever
# launcher follows on PATH.
gt_test_git_isolate() {
  local root="$1" real name quoted

  # A physical path keeps HOME acceptable to install.sh, which rejects a HOME
  # with `//`, `.`, `..`, or a trailing slash. An empty root must fail rather
  # than resolve to the current directory.
  if [[ -z "$root" ]] || ! root=$(cd -P -- "$root" 2>/dev/null && pwd); then
    printf 'hermetic-git: root is not a directory: %s\n' "$1" >&2
    return 1
  fi
  real=${GIT_TOOLS_TEST_REAL_GIT:-$(type -a -p git | tail -n 1)}
  [[ "$real" == /* && -x "$real" ]] || {
    printf 'hermetic-git: no absolute executable Git: %s\n' "$real" >&2
    return 1
  }
  mkdir "$root/git-bin" "$root/git-home" || return 1
  quoted=${real//\'/\'\\\'\'}
  printf "#!/bin/sh\nexec '%s' \"\$@\"\n" "$quoted" >"$root/git-bin/git" ||
    return 1
  chmod 755 "$root/git-bin/git" || return 1
  while IFS= read -r name; do
    case "$name" in
      GIT_TOOLS_TEST_*) ;;
      GIT_*) unset "$name" ;;
    esac
  done < <(compgen -e)
  # An exported shell function named git would shadow the PATH entry in every
  # bash child, including the tools under test.
  unset -f git
  # Bash sources BASH_ENV on every non-interactive start, so a caller's
  # startup file would otherwise run inside each bash tool under test.
  unset BASH_ENV
  unset XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
  export HOME="$root/git-home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export GIT_TOOLS_TEST_REAL_GIT="$real"
  PATH="$root/git-bin:$PATH"
}
