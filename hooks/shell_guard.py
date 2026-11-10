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
import re
import sys

SAFE_REDIRECTS = {("2", ">", "/dev/null"), ("2", ">&", "1")}
REVIEW_GUARDED = {"finding-verifier", "pr-reviewer"}
BROWSER_GUARDED = {"browser-tester", "browser-test-planner"}


class Blocked(Exception):
    pass


class Op(str):
    """An unquoted shell operator run (`&&`, `|`, `>`, `(` …), as opposed to a word."""


class Word(str):
    """A shell word, with `unquoted` marking which of its characters the shell may still expand."""

    unquoted: str = ""


BRACE_EXPANSION = re.compile(r"\{[^{}]*(,|\.\.)[^{}]*\}")


def check_expansion(word: "Word") -> None:
    """Refuse a word the shell would expand into arguments this guard never sees.

    The checks below read the word as typed, but the shell expands it first: `-de*` or `*`
    can become a file named `-delete` or `-oout`, `a*` can become two files where a check
    counted one argument, and `{-o,out}` becomes `-o out`. So every unquoted glob is refused;
    a quoted one (`-g '*.php'`, `-name '*.php'`) reaches the command as written.
    """
    live = word.unquoted
    if BRACE_EXPANSION.search(live):
        raise Blocked("brace expansion is not allowed; write the arguments out")
    if any(c in live for c in "*?["):
        raise Blocked("an unquoted glob is not allowed; quote it, or name the files")


OPERATOR_CHARS = set("();<>|&")
# What makes `$` an expansion in bash or zsh: a name, a special parameter, or `{`.
PARAMETER_START = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_{@*#?$!-")


# `${X:--o}` is `-o` when X is unset, and "$X" is whatever the environment holds: either way
# the command gets an argument the checks never read.
PARAMETER_REASON = "parameter expansion ($VAR, ${VAR}) is not allowed; write the value, or single-quote a literal $"


def is_parameter(command: str, at: int) -> bool:
    return command[at] == "$" and at + 1 < len(command) and command[at + 1] in PARAMETER_START
SEPARATORS = {"&&", "||", ";", "|"}


def tokenize(command: str) -> list[str]:
    """Split a command into words and Op tokens, the way bash and zsh both would.

    Quoting is tracked here rather than by shlex, so a quoted or escaped `(`, `>` or
    newline stays data inside its word, while the same character unquoted becomes an
    operator or blocks the command. Anything this tokenizer is unsure of is blocked.
    """
    tokens: list[str] = []
    word: list[str] = []
    live: list[str] = []  # the same word with every quoted or escaped character blanked
    in_word = False
    i, n = 0, len(command)

    def flush() -> None:
        nonlocal word, live, in_word
        if in_word:
            token = Word("".join(word))
            token.unquoted = "".join(live)
            tokens.append(token)
        word, live, in_word = [], [], False

    def quoted(text: str) -> None:
        word.append(text)
        live.append("\0" * len(text))

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
            quoted(command[i + 1])
            in_word = True
            i += 2
            continue
        if c == "'":
            end = command.find("'", i + 1)
            if end < 0:
                raise Blocked("could not parse the command (no closing quotation)")
            quoted(command[i + 1:end])
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
                if is_parameter(command, j):
                    raise Blocked(PARAMETER_REASON)
                if d == "\\" and j + 1 < n and command[j + 1] in '"\\$`\n':
                    if command[j + 1] != "\n":
                        quoted(command[j + 1])
                    j += 2
                    continue
                quoted(d)
                j += 1
            in_word = True
            i = j + 1
            continue
        if c == "`" or command.startswith(("$(", "$[", "=(", "$'"), i):
            if command.startswith("$'", i):
                raise Blocked("$'…' quoting is not allowed")
            raise Blocked("command substitution is not allowed")
        if is_parameter(command, i):
            raise Blocked(PARAMETER_REASON)
        if c == "\n":
            raise Blocked("multi-line commands are not allowed")
        if c in " \t":
            flush()
            i += 1
            continue
        if c == "#" and not in_word:
            # Both shells start a comment here, and a comment hides quotes from them but
            # not from this tokenizer: `echo # '<newline>rm x #'` would run `rm x`.
            raise Blocked("comments are not allowed")
        if c in OPERATOR_CHARS:
            flush()
            j = i
            while j < n and command[j] in OPERATOR_CHARS:
                j += 1
            tokens.append(Op(command[i:j]))
            i = j
            continue
        word.append(c)
        live.append(c)
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
    # After the operator checks, so an operator is reported before the glob beside it.
    for token in cleaned:
        if isinstance(token, Word):
            check_expansion(token)
    return out


def parse_command(command: str) -> list[list[str]]:
    parts = segments(command)
    if not parts:
        raise Blocked("empty command")
    return parts


def long_option_in(arg: str, names: tuple[str, ...]) -> bool:
    """True when arg is one of names, carries a value or suffix after one, or abbreviates one.

    GNU getopt and git's parse-options accept any unambiguous prefix of a long option, so
    `--out=x` is `--output=x`; matching only the full spelling lets the short form through.
    """
    if not arg.startswith("--") or arg == "--":
        return False
    name = arg.split("=", 1)[0]
    return any(name.startswith(n) or n.startswith(name) for n in names)


UNIQ_VALUE_FLAGS = {"-f", "-s", "-w", "--skip-fields", "--skip-chars", "--check-chars"}


def check_filter(name: str, args: list[str]) -> None:
    """Refuse the text-filter forms that write a file or run a program."""
    if name == "sort":
        for a in args:
            if long_option_in(a, ("--output", "--compress-program")) or (
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
        guard = hooks_dir / "guard-review-agents.py"
    elif agent in BROWSER_GUARDED:
        guard = hooks_dir.parent / "skills" / "browser-test" / "scripts" / "guard-browser.py"
    else:
        return 0
    try:
        return _load_module(guard.stem.replace("-", "_"), guard).run_payload(payload)
    except Exception as error:  # noqa: BLE001
        # Only exit 2 blocks a tool call, so a guard that crashes must not let the command run.
        print(f"BLOCKED: the {agent} guard failed ({type(error).__name__}: {error}). "
              "You are read-only; report what you could not do.", file=sys.stderr)
        return 2


def main() -> int:
    return dispatch(json.load(sys.stdin))


if __name__ == "__main__":
    sys.exit(main())
