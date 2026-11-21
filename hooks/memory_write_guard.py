"""File-write policy: read-only agents with `memory:` may write only their memory files.

These agents read untrusted input (PR comments, transcripts, diffs), so they stay
read-only, but `memory:` needs Write and Edit to keep its notes. hooks/pre_tool_guard.py
enforces this policy on file-write tool calls (including Grok's `search_replace`). A write
passes only when its real path lies under `.claude/agent-memory/` of the working directory
or one of its parents (project memory) or `~/.claude/agent-memory/` (user memory; under a
profile, `$CLAUDE_CONFIG_DIR/agent-memory/`). Symlinks leading outside those roots are blocked.
"""

import os

from shell_syntax import Blocked

PATH_KEYS = ("file_path", "path", "target_file")


def memory_roots(cwd: str) -> list[str]:
    """The memory directories this session owns: the working directory's and each parent's
    (project memory sits at the repo or worktree root), and the user's."""
    roots, here = [os.path.expanduser("~")], os.path.abspath(cwd)
    while True:
        roots.append(here)
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    dirs = [os.path.realpath(os.path.join(r, ".claude", "agent-memory")) for r in roots]
    # A profile (CLAUDE_CONFIG_DIR) moves user memory to <config dir>/agent-memory/.
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if config_dir:
        dirs.append(os.path.realpath(os.path.join(os.path.expanduser(config_dir), "agent-memory")))
    return dirs


def memory_path(path: str, cwd: str) -> bool:
    cwd = cwd or os.getcwd()
    # realpath, not normpath: a symlink inside the memory directory must not lead a write
    # elsewhere, and `/anywhere/.claude/agent-memory/x` is not this session's memory.
    full = os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))
    return any(full.startswith(root + os.sep) for root in memory_roots(cwd))


def check(tool_input: dict, cwd: str) -> None:
    if not isinstance(tool_input, dict):
        raise TypeError(f"tool_input must be a dict, got {type(tool_input).__name__}")
    if cwd and not isinstance(cwd, str):
        raise TypeError(f"cwd must be a str, got {type(cwd).__name__}")
    path = next((tool_input[k] for k in PATH_KEYS if isinstance(tool_input.get(k), str)), "")
    if path and memory_path(path, cwd):
        return
    raise Blocked("it may write only its memory files under .claude/agent-memory/ "
                  "(or $CLAUDE_CONFIG_DIR/agent-memory/)")
