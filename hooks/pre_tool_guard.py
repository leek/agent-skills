#!/usr/bin/env python3
"""PreToolUse guard entrypoint for read-only plugin agents.

Wired from hooks/hooks.json on both the shell (Bash|run_terminal_command|Shell) and
file-write (Write|Edit|MultiEdit|search_replace|write|hashline_edit|StrReplace|EditNotebook|
Delete) matchers. Every call spawns one
Python process, exiting 0 before importing any parser or policy unless agent_type
names a guarded agent.

Grok loads the same hooks.json; normalize() maps its camelCase envelope onto
Claude Code's keys. Once a payload identifies a guarded agent, any policy
violation, malformed input, unrecognized tool, or unexpected exception fails
closed (exit 2 with a reason on stderr).
"""

import json
import os
import sys

SHELL_TOOLS = {"Bash", "run_terminal_command", "Shell"}
WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "search_replace", "write", "hashline_edit",
               "StrReplace", "EditNotebook", "Delete"}

REVIEW_GUARDED = {"deepening-scout", "finding-verifier", "pr-reviewer",
                  "spec-reviewer", "standards-reviewer"}
BROWSER_GUARDED = {"browser-tester", "browser-test-planner"}
# Each read-only agent with `memory:`, mapped to its declared memory scope.
MEMORY_ONLY = {
    "deepening-scout": "project",
    "dependency-auditor": "project",
    "finding-verifier": "project",
    "release-notes-collector": "user",
    "session-miner": "user",
    "standards-reviewer": "project",
    "upgrade-impact-scout": "project",
}
ALL_GUARDED = REVIEW_GUARDED | BROWSER_GUARDED | set(MEMORY_ONLY)


def _agent_name(payload: dict) -> str:
    raw = payload.get("agent_type") or payload.get("subagentType") or ""
    return raw.rsplit(":", 1)[-1] if isinstance(raw, str) else ""


def _tool_input(payload: dict) -> dict:
    if "tool_input" in payload and payload["tool_input"] is not None:
        raw = payload["tool_input"]
    elif "toolInput" in payload and payload["toolInput"] is not None:
        raw = payload["toolInput"]
    elif "tool_input" in payload or "toolInput" in payload:
        raise TypeError("tool_input is null")
    else:
        return {}
    if not isinstance(raw, dict):
        raise TypeError(f"tool_input must be an object, got {type(raw).__name__}")
    return raw


def _run_shell_guard(agent: str, payload: dict) -> int:
    if agent not in REVIEW_GUARDED and agent not in BROWSER_GUARDED:
        return 0
    tool_input = _tool_input(payload)
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        raise TypeError(f"command must be a string, got {type(command).__name__}")
    from shell_syntax import Blocked
    if agent in REVIEW_GUARDED:
        import review_guard
        try:
            review_guard.check(command)
        except Blocked as reason:
            print(f"BLOCKED by review-agent guard: {reason}. You are read-only; do not look for "
                  "another way. Use the Read and Grep tools, or write UNSURE with what you checked.",
                  file=sys.stderr)
            return 2
        return 0
    import browser_guard
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if not isinstance(cwd, str):
        raise TypeError(f"cwd must be a string, got {type(cwd).__name__}")
    try:
        browser_guard.check(command, cwd)
    except Blocked as reason:
        print(f"BLOCKED by browser-test guard: {reason}. This is a read-only test; do not look for "
              "another way. Record what you could not do and move on.", file=sys.stderr)
        return 2
    return 0


def _run_write_guard(agent: str, payload: dict) -> int:
    if agent not in MEMORY_ONLY:
        return 0
    tool_input = _tool_input(payload)
    import memory_write_guard
    from shell_syntax import Blocked
    cwd = payload.get("cwd") or ""
    try:
        raw_agent = payload.get("agent_type") or payload.get("subagentType") or ""
        memory_write_guard.check(tool_input, cwd, MEMORY_ONLY[agent], raw_agent)
    except Blocked as reason:
        print(f"BLOCKED: {agent} is read-only; {reason}. Report what you found instead of changing files.",
              file=sys.stderr)
        return 2
    return 0


def dispatch(payload: dict) -> int:
    """Route a guarded agent's tool call to its policy; every other caller passes."""
    if not isinstance(payload, dict):
        return 0
    agent = _agent_name(payload)
    if agent not in ALL_GUARDED:
        return 0
    try:
        tool = payload.get("tool_name") or payload.get("toolName") or ""
        if tool in SHELL_TOOLS:
            return _run_shell_guard(agent, payload)
        if tool in WRITE_TOOLS:
            return _run_write_guard(agent, payload)
        raise RuntimeError(f"unrecognized tool {tool!r}")
    except Exception as error:  # noqa: BLE001
        # Only exit 2 blocks a tool call, so a guard that crashes must not let the call run.
        print(f"BLOCKED: the {agent} guard failed ({type(error).__name__}: {error}). "
              "You are read-only; report what you could not do.", file=sys.stderr)
        return 2


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, UnicodeDecodeError):
        return 0
    return dispatch(payload)


if __name__ == "__main__":
    sys.exit(main())
