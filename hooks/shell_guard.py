#!/usr/bin/env python3
"""Shared shell parser and PreToolUse Bash dispatcher for read-only agent guards.

Parses commands under rules that hold in both bash and zsh: blocks multi-line
commands (\\n, \\r), command/process/arithmetic substitutions (``, $(), =(), $[]),
unsafe redirects and background operators (<, >, &(, <(, >(, |&, &), and
unquoted subshells or zsh glob qualifiers ((, ), ;).

Wired from hooks/hooks.json so every Bash tool call spawns one Python process
instead of one per guard, exiting 0 at once unless agent_type is guarded.
Grok loads the same hooks.json; normalize() maps its payload onto Claude's keys.
"""

import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import sys

SAFE_REDIRECTS = {("2", ">", "/dev/null"), ("2", ">&", "1"), ("2", ">", "&1")}
REVIEW_GUARDED = {"finding-verifier", "pr-reviewer"}
BROWSER_GUARDED = {"browser-tester", "browser-test-planner"}


class Blocked(Exception):
    pass


def segments(command: str) -> list[list[str]]:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    tokens = list(lexer)
    cleaned, i = [], 0
    while i < len(tokens):
        if tuple(tokens[i:i + 3]) in SAFE_REDIRECTS:
            i += 3
            continue
        cleaned.append(tokens[i])
        i += 1
    out, current = [], []
    for token in cleaned:
        if token in {"&&", "||", ";", "|"}:
            if current:
                out.append(current)
            current = []
        else:
            current.append(token)
    if current:
        out.append(current)
    return out


def parse_command(command: str) -> list[list[str]]:
    if "\n" in command or "\r" in command:
        raise Blocked("multi-line commands are not allowed")
    if "`" in command or "$(" in command or "=(" in command or "$[" in command:
        raise Blocked("command substitution is not allowed")
    try:
        parts = segments(command)
    except ValueError as error:
        raise Blocked(f"could not parse the command ({error})")
    if not parts:
        raise Blocked("empty command")
    for seg in parts:
        if any(re.fullmatch(r"[();<>|&]+", t) and any(c in t for c in "<>&") for t in seg):
            raise Blocked("redirects are not allowed")
        if any(re.fullmatch(r"[();<>|&]+", t) for t in seg):
            raise Blocked("subshells and glob qualifiers are not allowed")
    return parts


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SHELL_TOOLS = {"Bash", "run_terminal_command"}


def normalize(payload: dict) -> dict:
    """Map Grok's hook envelope onto Claude Code's keys.

    Grok names the subagent `subagentType` (never `agent_type`), calls its shell
    tool `run_terminal_command`, and sends `toolName`/`toolInput` in camelCase
    beside the `tool_name`/`tool_input` aliases. The guards read Claude's shape.
    """
    tool = payload.get("tool_name") or payload.get("toolName") or "Bash"
    return {
        **payload,
        "agent_type": payload.get("agent_type") or payload.get("subagentType") or "",
        "tool_name": "Bash" if tool in SHELL_TOOLS else tool,
        "tool_input": payload.get("tool_input") or payload.get("toolInput") or {},
    }


def dispatch(payload: dict) -> int:
    payload = normalize(payload)
    agent = payload["agent_type"].rsplit(":", 1)[-1]
    if payload["tool_name"] != "Bash":
        return 0
    hooks_dir = Path(__file__).resolve().parent
    if agent in REVIEW_GUARDED:
        mod = _load_module("guard_review_agents", hooks_dir / "guard-review-agents.py")
        return mod.run_payload(payload)
    if agent in BROWSER_GUARDED:
        browser_guard = hooks_dir.parent / "skills" / "browser-test" / "scripts" / "guard-browser.py"
        mod = _load_module("guard_browser", browser_guard)
        return mod.run_payload(payload)
    return 0


def main() -> int:
    return dispatch(json.load(sys.stdin))


if __name__ == "__main__":
    sys.exit(main())
