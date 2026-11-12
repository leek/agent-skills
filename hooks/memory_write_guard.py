#!/usr/bin/env python3
"""PreToolUse guard: read-only agents with `memory:` may write only their memory files.

These agents read untrusted input (PR comments, transcripts, diffs), so they stay
read-only, but `memory:` needs Write and Edit to keep its notes. Wired from
hooks/hooks.json on the file-write tools. For an agent in MEMORY_ONLY, a write passes
only when its real path lies under `.claude/agent-memory/` of the working directory or one
of its parents (project memory) or `~/.claude/agent-memory/` (user memory; under a profile,
`$CLAUDE_CONFIG_DIR/agent-memory/`); anything else,
a symlink that leads out of those included, exits 2. Every other caller
passes. Grok's `search_replace` sends the same `file_path` key, so it is covered too.
"""

import json
import os
import sys

MEMORY_ONLY = {"deepening-scout", "dependency-auditor", "finding-verifier",
               "release-notes-collector", "session-miner", "standards-reviewer",
               "upgrade-impact-scout"}
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


def run_payload(payload: dict) -> int:
    agent = (payload.get("agent_type") or payload.get("subagentType") or "").rsplit(":", 1)[-1]
    if agent not in MEMORY_ONLY:
        return 0
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    path = next((tool_input[k] for k in PATH_KEYS if isinstance(tool_input.get(k), str)), "")
    if path and memory_path(path, payload.get("cwd", "")):
        return 0
    print(f"BLOCKED: {agent} is read-only; it may write only its memory files under "
          ".claude/agent-memory/ (or $CLAUDE_CONFIG_DIR/agent-memory/). Report what you found instead of changing files.",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(run_payload(json.load(sys.stdin)))
