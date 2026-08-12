# shellcheck shell=bash
# Sourceable interactive Git workflows for Bash and zsh.
#
# This file deliberately contains functions only. It must be safe to cache by
# content, source more than once, and load into a long-lived interactive shell
# without changing the caller's options, traps, IFS, umask, or working
# directory. Consumers choose their own shorthand; git-tools exports only
# namespaced behavior.

# Public marker for loaders that need to verify that the cached integration ran.
# shellcheck disable=SC2034 # Read by the sourcing consumer, not this file.
GIT_TOOLS_SHELL_LOADED=1

# ---------------------------------------------------------------------------
# Consumer hooks
# ---------------------------------------------------------------------------
# Define any of these functions before sourcing this file to keep local policy:
#
#   git_tools_fzf_preview ARGS...  fzf used for preview-oriented pickers
#   git_tools_fzf_pick ARGS...     fzf used for compact path pickers
#   git_tools_edit_file PATH       editor used by the changed-file picker
#
# Defaults make a standalone checkout immediately useful. The conditional
# definitions matter for shell reloads: re-sourcing a provider must never erase
# presentation or editor choices installed by the consumer.
if ! typeset -f git_tools_fzf_preview >/dev/null 2>&1; then
  git_tools_fzf_preview() {
    command fzf "$@"
  }
fi

if ! typeset -f git_tools_fzf_pick >/dev/null 2>&1; then
  git_tools_fzf_pick() {
    command fzf "$@"
  }
fi

if ! typeset -f git_tools_edit_file >/dev/null 2>&1; then
  git_tools_edit_file() {
    local file="$1"

    if [[ -z "$file" ]]; then
      printf 'error: missing file path\n' >&2
      return 1
    fi
    "${EDITOR:-vi}" "$file"
  }
fi

_git_tools_require_repo() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'error: not in a git repo\n' >&2
    return 1
  fi
}

# Print the main worktree without ending the producer side of a pipeline early.
# `git worktree list | head -1` looks equivalent, but with `pipefail` enabled
# Git can receive SIGPIPE as soon as a linked worktree adds a second output
# line. Reading the complete porcelain stream makes this safe in caller shells
# and also preserves spaces in the main worktree path.
_git_tools_main_worktree() {
  git worktree list --porcelain |
    awk 'NR == 1 { sub(/^worktree /, ""); main = $0 } END { print main }'
}

# ---------------------------------------------------------------------------
# fzf-backed Git inspection
# ---------------------------------------------------------------------------

# Select a recent local or remote branch, deduplicating origin/foo and foo.
git_tools_fzf_branch() {
  _git_tools_require_repo || return

  local branch
  branch=$(
    git branch -a --sort=-committerdate --format='%(refname:short)' |
      sed 's|^origin/||' | awk '!seen[$0]++' |
      git_tools_fzf_preview \
        --prompt="branch> " \
        --preview="git log --oneline --graph --color=always -20 {}"
  ) || return

  [[ -n "$branch" ]] || return
  # `checkout` retains compatibility with older Git versions that predate
  # `switch`; suppress only switch's expected unsupported/fallback diagnostic.
  git switch "$branch" 2>/dev/null || git checkout "$branch"
}

# Select one recent commit and render its full show output.
git_tools_fzf_log() {
  _git_tools_require_repo || return

  local commit
  commit=$(
    git log --oneline --graph --color=always --decorate -200 |
      git_tools_fzf_preview --ansi \
        --prompt="commit> " \
        --preview="echo {} | grep -oE '[0-9a-f]{7,}' | head -1 | xargs git show --color=always --stat -p" |
      grep -oE '[0-9a-f]{7,}' | head -1
  ) || return

  [[ -n "$commit" ]] || return
  git show "$commit"
}

# Select a changed path and open it through the consumer editor hook.
git_tools_fzf_status() {
  _git_tools_require_repo || return

  local file
  file=$(
    git -c color.status=always status --short |
      git_tools_fzf_preview --ansi \
        --prompt="changed> " \
        --preview="
          f=\$(echo {} | sed 's/\x1b\[[0-9;]*m//g; s/^...//')
          git diff --color=always -- \"\$f\" 2>/dev/null
          git diff --cached --color=always -- \"\$f\" 2>/dev/null
        "
  ) || return

  [[ -n "$file" ]] || return
  file=$(echo "$file" | sed 's/\x1b\[[0-9;]*m//g; s/^...//')
  git_tools_edit_file "$file"
}

# Select one stash and pop it only after an explicit confirmation.
git_tools_fzf_stash() {
  _git_tools_require_repo || return

  local entry stash_id reply
  entry=$(
    git stash list --color=always |
      git_tools_fzf_preview --ansi \
        --prompt="stash> " \
        --preview="echo {} | grep -oE 'stash@\{[0-9]+\}' | xargs git stash show -p --color=always"
  ) || return

  stash_id=$(echo "$entry" | grep -oE 'stash@\{[0-9]+\}')
  [[ -n "$stash_id" ]] || return

  printf 'Apply %s? [y/N] ' "$stash_id"
  read -r reply
  [[ "$reply" =~ ^[Yy] ]] && git stash pop "$stash_id"
}

# ---------------------------------------------------------------------------
# Parallel worktree lifecycle
# ---------------------------------------------------------------------------

# Print the repository-specific worktree root. Consumers may set
# GIT_TOOLS_WORKTREE_PARENT before invocation; the default preserves the common
# ~/worktrees/<repository> layout without freezing a consumer's HOME at source
# time. Deriving the repository name from Git's first worktree keeps linked
# worktree invocations anchored to the same main checkout.
git_tools_worktree_root() {
  _git_tools_require_repo || return

  local main_path parent

  main_path=$(_git_tools_main_worktree) || return 1
  if [[ -n "${GIT_TOOLS_WORKTREE_PARENT:-}" ]]; then
    parent="$GIT_TOOLS_WORKTREE_PARENT"
  elif [[ -n "${HOME:-}" ]]; then
    parent="$HOME/worktrees"
  else
    printf 'error: HOME is not set and GIT_TOOLS_WORKTREE_PARENT is empty\n' >&2
    return 1
  fi
  printf '%s/%s\n' "${parent%/}" "$(basename "$main_path")"
}

# Create a branch worktree, enter an existing one, or delegate an argument-free
# invocation to the interactive worktree picker.
git_tools_worktree() {
  _git_tools_require_repo || return

  if [[ $# -eq 0 ]]; then
    git_tools_worktree_list
    return
  fi

  local branch="$1"
  local base="${2:-HEAD}"
  local worktree_root worktree_path
  worktree_root=$(git_tools_worktree_root) || return 1
  worktree_path="$worktree_root/${branch//\//__}"

  if [[ -d "$worktree_path" ]]; then
    cd "$worktree_path" || return
    printf 'switched to existing worktree: %s\n' "$worktree_path"
    return
  fi

  mkdir -p "$worktree_root"

  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git worktree add "$worktree_path" "$branch"
  else
    git worktree add -b "$branch" "$worktree_path" "$base"
  fi || return

  cd "$worktree_path" || return
  printf 'created worktree: %s\n' "$worktree_path"
}

# Select an existing worktree and change the caller's working directory to it.
git_tools_worktree_list() {
  _git_tools_require_repo || return

  local worktree
  worktree=$(
    git worktree list |
      git_tools_fzf_pick --prompt="worktree> " |
      awk '{print $1}'
  ) || return

  [[ -n "$worktree" ]] || return
  cd "$worktree" || return
}

# Remove a named branch worktree or, with no argument, the current worktree.
git_tools_worktree_remove() {
  _git_tools_require_repo || return

  local worktree_root worktree_path main_path
  worktree_root=$(git_tools_worktree_root) || return 1
  main_path=$(_git_tools_main_worktree) || return 1

  if [[ $# -gt 0 ]]; then
    worktree_path="$worktree_root/${1//\//__}"
  else
    worktree_path="$PWD"
  fi

  # Git reports a physical worktree path while an interactive shell may retain
  # an equivalent logical spelling (notably `/var` versus `/private/var` on
  # macOS). Compare filesystem identity so aliases cannot bypass the guard.
  if [[ "$worktree_path" -ef "$main_path" ]]; then
    printf 'error: cannot remove the main worktree\n' >&2
    return 1
  fi

  if [[ "$PWD" == "$worktree_path" || "$PWD" == "$worktree_path/"* ]]; then
    cd "$main_path" || return
  fi

  git worktree remove "$worktree_path" &&
    printf 'removed worktree: %s\n' "$worktree_path"
}

# Prune Git's stale registrations and consumer-root directories that are empty.
git_tools_worktree_prune() {
  _git_tools_require_repo || return
  git worktree prune -v

  local worktree_root
  worktree_root=$(git_tools_worktree_root) 2>/dev/null || return 0
  [[ -d "$worktree_root" ]] &&
    find "$worktree_root" -maxdepth 1 -type d -empty -delete 2>/dev/null
}
