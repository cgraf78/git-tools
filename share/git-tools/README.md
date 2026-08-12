# Shell integration

`shell.sh` is the reusable interactive-shell surface of git-tools. It owns the
Git and worktree mechanics while leaving aliases, picker layout, editor
routing, and worktree placement to each consumer.

That split is deliberate: a dotfiles repository should be able to express
local policy without carrying a fork of the underlying workflows. Keeping the
integration in one self-contained file also lets content-caching loaders such
as shdeps source one immutable artifact.

## Loading contract

The file supports Bash 3.2 or newer and zsh. It contains function definitions
and one marker assignment only; sourcing it does not change shell options,
traps, `IFS`, `umask`, or the working directory. It is safe to source more than
once.

After the standard installer runs, load it from its default data path:

```sh
. "$HOME/.local/share/git-tools/shell.sh"
```

A repository manager may instead source `share/git-tools/shell.sh` directly
from its managed checkout. `GIT_TOOLS_SHELL_LOADED=1` confirms that the file
ran.

## Consumer policy hooks

Define these functions before loading `shell.sh` to replace the standalone
defaults:

- `git_tools_fzf_preview ARGS...` invokes the preview-oriented picker.
- `git_tools_fzf_pick ARGS...` invokes the compact path picker.
- `git_tools_edit_file PATH` opens the selected changed file.

The provider defines a hook only when the consumer has not already done so.
That condition is important for reloadable shell configurations: sourcing the
provider again must not silently replace consumer policy.

Set `GIT_TOOLS_WORKTREE_PARENT` before invoking a worktree function to choose
the parent directory. The value is read at invocation time, so one sourced
integration can serve shells whose environment changes later.

The public functions and a complete customization example are documented in
the repository [README](../../README.md#interactive-shell-workflows).
