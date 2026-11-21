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
# Review-guarded too, plus each one's own commands (hooks/agent_policies.py).
POLICY_GUARDED = {"dependency-auditor", "session-miner", "ui-reviewer"}
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
# Read-only agents with no `memory:`: they write no file at all. Their `disallowedTools`
# already drop Write and Edit on Claude Code; this holds on a harness that ignores it.
NO_WRITES = {"browser-test-planner", "browser-tester", "pr-reviewer", "spec-reviewer",
             "ui-reviewer"}
ALL_GUARDED = REVIEW_GUARDED | BROWSER_GUARDED | POLICY_GUARDED | set(MEMORY_ONLY) | NO_WRITES


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


def _cwd(payload: dict) -> str:
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if not isinstance(cwd, str):
        raise TypeError(f"cwd must be a string, got {type(cwd).__name__}")
    return cwd


def _run_shell_guard(agent: str, payload: dict) -> int:
    if agent not in REVIEW_GUARDED and agent not in BROWSER_GUARDED and agent not in POLICY_GUARDED:
        return 0
    tool_input = _tool_input(payload)
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        raise TypeError(f"command must be a string, got {type(command).__name__}")
    from shell_syntax import Blocked
    if agent in REVIEW_GUARDED or agent in POLICY_GUARDED:
        import review_guard
        extra = None
        if agent in POLICY_GUARDED:
            import agent_policies
            extra = agent_policies.POLICIES[agent](_cwd(payload))
        try:
            review_guard.check(command, extra)
        except Blocked as reason:
            print(f"BLOCKED by review-agent guard: {reason}. You are read-only; do not look for "
                  "another way. Use the Read and Grep tools, or write UNSURE with what you checked.",
                  file=sys.stderr)
            return 2
        return 0
    import browser_guard
    try:
        browser_guard.check(command, _cwd(payload))
    except Blocked as reason:
        print(f"BLOCKED by browser-test guard: {reason}. This is a read-only test; do not look for "
              "another way. Record what you could not do and move on.", file=sys.stderr)
        return 2
    return 0


def _run_write_guard(agent: str, payload: dict) -> int:
    if agent in NO_WRITES:
        print(f"BLOCKED: {agent} is read-only and writes no files. Report what you found instead.",
              file=sys.stderr)
        return 2
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
