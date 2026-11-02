#!/usr/bin/env python3
"""Shared shell parser and PreToolUse Bash dispatcher for read-only agent guards.

Tokenizes commands under rules that hold in both bash and zsh, tracking quotes
itself: blocks unquoted newlines and any \\r, command/process/arithmetic
substitutions (``, $(), =(), $[], and ${( in double quotes), unsafe redirects and
background operators (<, >, <(, >(, |&, &), and unquoted subshells or zsh glob
qualifiers ((, )). Quoted or escaped operators and newlines stay data, and a
backslash-newline is a line continuation.

Wired from hooks/hooks.json so every Bash tool call spawns one Python process
instead of one per guard, exiting 0 at once unless agent_type is guarded.
Grok loads the same hooks.json; normalize() maps its payload onto Claude's keys.
"""

import importlib.util
import json
from pathlib import Path
import sys

SAFE_REDIRECTS = {("2", ">", "/dev/null"), ("2", ">&", "1")}
REVIEW_GUARDED = {"finding-verifier", "pr-reviewer"}
BROWSER_GUARDED = {"browser-tester", "browser-test-planner"}


class Blocked(Exception):
    pass


class Op(str):
    """An unquoted shell operator run (`&&`, `|`, `>`, `(` …), as opposed to a word."""


OPERATOR_CHARS = set("();<>|&")
SEPARATORS = {"&&", "||", ";", "|"}


def tokenize(command: str) -> list[str]:
    """Split a command into words and Op tokens, the way bash and zsh both would.

    Quoting is tracked here rather than by shlex, so a quoted or escaped `(`, `>` or
    newline stays data inside its word, while the same character unquoted becomes an
    operator or blocks the command. Anything this tokenizer is unsure of is blocked.
    """
    tokens: list[str] = []
    word: list[str] = []
    in_word = False
    i, n = 0, len(command)

    def flush() -> None:
        nonlocal word, in_word
        if in_word:
            tokens.append("".join(word))
        word, in_word = [], False

    while i < n:
        c = command[i]
        if c == "\r":
            raise Blocked("multi-line commands are not allowed")
        if c == "\\":
            if i + 1 >= n:
                raise Blocked("could not parse the command (trailing backslash)")
            if command[i + 1] == "\n":  # line continuation
                i += 2
                continue
            word.append(command[i + 1])
            in_word = True
            i += 2
            continue
        if c == "'":
            end = command.find("'", i + 1)
            if end < 0:
                raise Blocked("could not parse the command (no closing quotation)")
            word.append(command[i + 1:end])
            in_word = True
            i = end + 1
            continue
        if c == '"':
            j = i + 1
            while True:
                if j >= n:
                    raise Blocked("could not parse the command (no closing quotation)")
                d = command[j]
                if d == '"':
                    break
                # Double quotes still expand: refuse every substitution form inside them,
                # escaped or not, since zsh's (e) flag can re-evaluate an escaped one.
                if d == "`" or command.startswith(("$(", "$[", "${("), j):
                    raise Blocked("command substitution is not allowed")
                if d == "\\" and j + 1 < n and command[j + 1] in '"\\$`\n':
                    if command[j + 1] != "\n":
                        word.append(command[j + 1])
                    j += 2
                    continue
                word.append(d)
                j += 1
            in_word = True
            i = j + 1
            continue
        if c == "`" or command.startswith(("$(", "$[", "=(", "$'"), i):
            if command.startswith("$'", i):
                raise Blocked("$'…' quoting is not allowed")
            raise Blocked("command substitution is not allowed")
        if c == "\n":
            raise Blocked("multi-line commands are not allowed")
        if c in " \t":
            flush()
            i += 1
            continue
        if c in OPERATOR_CHARS:
            flush()
            j = i
            while j < n and command[j] in OPERATOR_CHARS:
                j += 1
            tokens.append(Op(command[i:j]))
            i = j
            continue
        word.append(c)
        in_word = True
        i += 1
    flush()
    return tokens


def segments(command: str) -> list[list[str]]:
    tokens = tokenize(command)
    cleaned, i = [], 0
    while i < len(tokens):
        window = tokens[i:i + 3]
        if (len(window) == 3 and not isinstance(window[0], Op) and isinstance(window[1], Op)
                and not isinstance(window[2], Op) and tuple(window) in SAFE_REDIRECTS):
            i += 3
            continue
        cleaned.append(tokens[i])
        i += 1
    out, current = [], []
    for token in cleaned:
        if isinstance(token, Op) and token in SEPARATORS:
            if current:
                out.append(current)
            current = []
        elif isinstance(token, Op):
            if any(c in token for c in "<>&"):
                raise Blocked("redirects are not allowed")
            raise Blocked("subshells and glob qualifiers are not allowed")
        else:
            current.append(str(token))
    if current:
        out.append(current)
    return out


def parse_command(command: str) -> list[list[str]]:
    parts = segments(command)
    if not parts:
        raise Blocked("empty command")
    return parts


UNIQ_VALUE_FLAGS = {"-f", "-s", "-w", "--skip-fields", "--skip-chars", "--check-chars"}


def check_filter(name: str, args: list[str]) -> None:
    """Refuse the text-filter forms that write a file or run a program."""
    if name == "sort":
        for a in args:
            if a.startswith(("--output", "--compress-program")) or (
                    a.startswith("-") and not a.startswith("--") and "o" in a[1:]):
                raise Blocked("`sort -o` and `--compress-program` write files or run a program")
    elif name == "uniq":
        positional, skip, ended = 0, False, False
        for a in args:
            if skip:
                skip = False
            elif not ended and a == "--":
                ended = True
            elif not ended and a in UNIQ_VALUE_FLAGS:
                skip = True
            elif ended or a == "-" or not a.startswith("-"):
                positional += 1
        if positional > 1:
            raise Blocked("`uniq <in> <out>` writes a file")

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
    """Route a guarded agent's shell call to its guard; every other call passes."""
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
