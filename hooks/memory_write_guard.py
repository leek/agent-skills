#!/usr/bin/env python3
"""PreToolUse guard: read-only agents with `memory:` may write only their memory files.

These agents read untrusted input (PR comments, transcripts, diffs), so they stay
read-only, but `memory:` needs Write and Edit to keep its notes. Wired from
hooks/hooks.json on the file-write tools. For an agent in MEMORY_ONLY, a write passes
only when its path lies under a `.claude/agent-memory/` directory (project memory) or
`~/.claude/agent-memory/` (user memory); anything else exits 2. Every other caller
passes. Grok's `search_replace` sends the same `file_path` key, so it is covered too.
"""

import json
import os
import sys

MEMORY_ONLY = {"deepening-scout", "dependency-auditor", "finding-verifier",
               "session-miner", "standards-reviewer"}
PATH_KEYS = ("file_path", "path", "target_file")


def memory_path(path: str, cwd: str) -> bool:
    full = os.path.normpath(os.path.join(cwd or os.getcwd(), os.path.expanduser(path)))
    parts = full.split(os.sep)
    return any(parts[i:i + 2] == [".claude", "agent-memory"] and len(parts) > i + 2
               for i in range(len(parts) - 1))


def run_payload(payload: dict) -> int:
    agent = (payload.get("agent_type") or payload.get("subagentType") or "").rsplit(":", 1)[-1]
    if agent not in MEMORY_ONLY:
        return 0
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    path = next((tool_input[k] for k in PATH_KEYS if isinstance(tool_input.get(k), str)), "")
    if path and memory_path(path, payload.get("cwd", "")):
        return 0
    print(f"BLOCKED: {agent} is read-only; it may write only its memory files under "
          ".claude/agent-memory/. Report what you found instead of changing files.",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(run_payload(json.load(sys.stdin)))
