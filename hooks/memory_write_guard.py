#!/usr/bin/env python3
"""PreToolUse guard: read-only agents with `memory:` may write only their own memory files.

These agents read untrusted input (PR comments, transcripts, diffs), so they stay
read-only, but `memory:` needs Write and Edit to keep its notes. Wired from
hooks/hooks.json on the file-write tools. For an agent in MEMORY_ONLY, a write passes
only when its real path lies under that agent's own memory directory matching its
declared scope (`memory: project` → `<cwd-or-parent>/.claude/agent-memory/<agent>/`,
never user memory; `memory: user` → `~/.claude/agent-memory/<agent>/` or
`$CLAUDE_CONFIG_DIR/agent-memory/<agent>/`, never project memory); anything else,
a symlink that leads out of those included, exits 2. Every other caller passes.
"""

import json
import os
import sys

MEMORY_ONLY = {
    "deepening-scout": "project",
    "dependency-auditor": "project",
    "finding-verifier": "project",
    "release-notes-collector": "user",
    "session-miner": "user",
    "standards-reviewer": "project",
    "upgrade-impact-scout": "project",
}
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
        here = os.path.abspath(cwd)
        while True:
            # Never treat `~/.claude/agent-memory/` as project memory even when cwd is under `~`.
            if os.path.realpath(here) == home:
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


def _check_payload(payload: dict) -> int:
    if not isinstance(payload, dict):
        raise TypeError("payload must be a JSON object")
    raw_agent = payload.get("agent_type") or payload.get("subagentType") or ""
    if not isinstance(raw_agent, str):
        raise TypeError("agent_type must be a string")
    agent = raw_agent.rsplit(":", 1)[-1]
    scope = MEMORY_ONLY.get(agent)
    if scope is None:
        return 0
    tool_input = payload.get("tool_input") if payload.get("tool_input") is not None else payload.get("toolInput")
    if tool_input is None:
        tool_input = {}
    if not isinstance(tool_input, dict):
        raise TypeError("tool_input must be a JSON object")
    path = next((tool_input[k] for k in PATH_KEYS if isinstance(tool_input.get(k), str)), "")
    cwd = payload.get("cwd", "")
    if not isinstance(cwd, str):
        raise TypeError("cwd must be a string")
    if path and memory_path(path, cwd, scope, raw_agent, agent):
        return 0
    where = (f".claude/agent-memory/{agent}/" if scope == "project"
             else f"~/.claude/agent-memory/{agent}/ (or $CLAUDE_CONFIG_DIR/agent-memory/{agent}/)")
    print(f"BLOCKED: {agent} is read-only; it may write only its own {scope} memory files under "
          f"{where}. Report what you found instead of changing files.",
          file=sys.stderr)
    return 2


def run_payload(payload: dict) -> int:
    try:
        return _check_payload(payload)
    except Exception as error:  # noqa: BLE001
        print(f"BLOCKED: memory-write guard failed ({type(error).__name__}: {error}). "
              "Report what you found instead of changing files.", file=sys.stderr)
        return 2


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception as error:  # noqa: BLE001
        print(f"BLOCKED: memory-write guard failed ({type(error).__name__}: {error}). "
              "Report what you found instead of changing files.", file=sys.stderr)
        return 2
    return run_payload(payload)


if __name__ == "__main__":
    sys.exit(main())
