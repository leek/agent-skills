"""File-write policy: read-only agents with `memory:` may write only their own memory files.

These agents read untrusted input (PR comments, transcripts, diffs), so they stay
read-only, but `memory:` needs Write and Edit to keep its notes. hooks/pre_tool_guard.py
enforces this policy on file-write tool calls (including Grok's `search_replace`). A write
passes only when its real path lies under that agent's own memory directory matching its
declared scope (`memory: project` → `<cwd-or-parent>/.claude/agent-memory/<agent>/`, never
user memory; `memory: user` → `~/.claude/agent-memory/<agent>/` or
`$CLAUDE_CONFIG_DIR/agent-memory/<agent>/`, never project memory). Symlinks leading outside
those directories are blocked.
"""

import os

from shell_syntax import Blocked

PATH_KEYS = ("file_path", "path", "target_file", "notebook_path", "target_notebook")


def agent_subdirs(raw_agent: str, agent: str) -> list[str]:
    """The agent's own subdirectory name(s) under `agent-memory/`: bare and plugin-namespaced."""
    names = [agent]
    if ":" in raw_agent:
        ns = raw_agent.replace(":", "-")
        if ns != agent and "/" not in ns and "\\" not in ns and ".." not in ns:
            names.append(ns)
    return names


def memory_roots(cwd: str, scope: str, subdirs: list[str]) -> list[str]:
    """The memory directories this agent owns under its declared scope (`project` or `user`)."""
    bases: list[str] = []
    home = os.path.realpath(os.path.expanduser("~"))
    if scope == "project":
        start = here = os.path.abspath(cwd)
        while True:
            # `~/.claude/agent-memory/` is project memory only when the session runs from `~`
            # itself, never when `~` is reached as a parent of the working directory.
            if os.path.realpath(here) == home:
                if here == start:
                    bases.append(os.path.join(here, ".claude", "agent-memory"))
                break
            bases.append(os.path.join(here, ".claude", "agent-memory"))
            parent = os.path.dirname(here)
            if parent == here:
                break
            here = parent
    elif scope == "user":
        bases.append(os.path.join(home, ".claude", "agent-memory"))
        # A profile (CLAUDE_CONFIG_DIR) moves user memory to <config dir>/agent-memory/.
        config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
        if config_dir:
            bases.append(os.path.join(os.path.expanduser(config_dir), "agent-memory"))
    return [os.path.realpath(os.path.join(base, sd)) for base in bases for sd in subdirs]


def memory_path(path: str, cwd: str, scope: str, raw_agent: str, agent: str) -> bool:
    cwd = cwd or os.getcwd()
    # realpath, not normpath: a symlink inside the memory directory must not lead a write
    # elsewhere, and `/anywhere/.claude/agent-memory/x` is not this session's memory.
    full = os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))
    subdirs = agent_subdirs(raw_agent, agent)
    return any(full.startswith(root + os.sep) for root in memory_roots(cwd, scope, subdirs))


def check(tool_input: dict, cwd: str, scope: str, raw_agent: str) -> None:
    if not isinstance(tool_input, dict):
        raise TypeError(f"tool_input must be a dict, got {type(tool_input).__name__}")
    if cwd and not isinstance(cwd, str):
        raise TypeError(f"cwd must be a str, got {type(cwd).__name__}")
    agent = raw_agent.rsplit(":", 1)[-1]
    path = next((tool_input[k] for k in PATH_KEYS if isinstance(tool_input.get(k), str)), "")
    if path and memory_path(path, cwd, scope, raw_agent, agent):
        return
    where = (f".claude/agent-memory/{agent}/" if scope == "project"
             else f"~/.claude/agent-memory/{agent}/ (or $CLAUDE_CONFIG_DIR/agent-memory/{agent}/)")
    raise Blocked(f"it may write only its own {scope} memory files under {where}")
