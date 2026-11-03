#!/usr/bin/env python3
"""PreToolUse guard for the PR-review agents (finding-verifier, pr-reviewer).

Both agents read untrusted text: review comments, bot findings, and the PR diff.
Their bodies say read-only; this hook enforces it. hooks/shell_guard.py calls
run_payload only for those agents' shell calls. Every segment of the command
(split on &&, ||, ;, |) must be a read-only git, gh, rg, find, `sed -n '<range>p'`, or text command
under both bash and zsh rules. Anything else returns 2, which blocks the call and
shows stderr to the agent.
"""

from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shell_guard import Blocked, check_filter, long_option_in, parse_command  # noqa: E402

FILTERS = {"cat", "head", "tail", "wc", "sort", "uniq", "cut", "tr", "echo", "ls", "jq",
           "grep", "egrep", "cd", "pwd", "basename", "dirname", "true"}
GIT_READ = {"log", "show", "diff", "ls-files", "ls-tree", "blame", "grep", "rev-parse",
            "rev-list", "merge-base", "cat-file", "status", "range-diff", "shortlog",
            "describe", "name-rev", "for-each-ref", "fetch"}
GH_READ = {("pr", "view"), ("pr", "diff"), ("pr", "checks"), ("pr", "list"),
           ("issue", "view"), ("issue", "list"), ("run", "view"), ("repo", "view")}
GH_FIELDS = {"-f", "-F", "--field", "--raw-field"}


def check_git(args: list[str]) -> None:
    while args[:1] == ["--no-pager"] or args[:1] == ["-C"]:
        args = args[2:] if args[0] == "-C" else args[1:]
    if not args or args[0] not in GIT_READ:
        raise Blocked(f"`git {args[0] if args else ''}` is not a read-only git command")
    if args[0] == "grep" and any(
            long_option_in(a, ("--open-files-in-pager",)) or (a.startswith("-") and not a.startswith("--") and "O" in a)
            for a in args[1:]):
        raise Blocked("`git grep -O` runs a program")
    for a in args[1:]:
        if long_option_in(a, ("--output", "--upload-pack", "--ext-diff", "--exec")):
            raise Blocked(f"`git {args[0]} {a}` writes files or runs a program")


def check_gh(args: list[str]) -> None:
    if tuple(args[:2]) in GH_READ:
        if "--web" in args or "-w" in args:
            raise Blocked("`--web` opens a browser")
        return
    if args[:1] != ["api"]:
        raise Blocked(f"`gh {' '.join(args[:2])}` is not a read-only gh command")
    rest = args[1:]
    method, fields, i = "GET", [], 0
    while i < len(rest):
        a = rest[i]
        if a in ("-X", "--method"):
            method = rest[i + 1].upper() if i + 1 < len(rest) else ""
            i += 2
            continue
        if a.startswith("--method="):
            method = a.split("=", 1)[1].upper()
        elif a in GH_FIELDS:
            fields.append(rest[i + 1] if i + 1 < len(rest) else "")
            i += 2
            continue
        elif a.startswith("--input"):
            raise Blocked("`gh api --input` sends a request body")
        i += 1
    if method != "GET":
        raise Blocked(f"`gh api` with method {method} is not read-only")
    if rest[:1] == ["graphql"]:
        if any("mutation" in f.lower() for f in fields):
            raise Blocked("GraphQL mutations are not read-only")
        return
    if fields and "-X" not in rest and "--method" not in rest and not any(
            a.startswith("--method=") for a in rest):
        raise Blocked("`gh api` with -f/-F sends a POST; add `-X GET` for a read")


def check_rg(args: list[str]) -> None:
    if any(a.startswith("--pre") for a in args):
        raise Blocked("`rg --pre` runs a program")


def check_find(args: list[str]) -> None:
    bad = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}
    if bad.intersection(args):
        raise Blocked("`find` with -exec, -delete, or -fprint is not read-only")


SED_PRINT = re.compile(r"(\d+|\$)(,(\d+|\$))?p")


def check_sed(args: list[str]) -> None:
    """Allow only `sed -n '<line>[,<line>]p' [file …]`, the read-a-range form."""
    if len(args) < 2 or args[0] != "-n" or not SED_PRINT.fullmatch(args[1]):
        raise Blocked("only `sed -n '<start>,<end>p' <file>` is allowed; use the Read tool")
    files = args[2:]
    if files[:1] == ["--"]:
        files = files[1:]
    elif any(f.startswith("-") for f in files):
        raise Blocked("only `sed -n '<start>,<end>p' <file>` is allowed; use the Read tool")


def check(command: str) -> None:
    parts = parse_command(command)
    for seg in parts:
        name, args = seg[0], seg[1:]
        if name in FILTERS:
            check_filter(name, args)
            continue
        if name == "git":
            check_git(args)
        elif name == "gh":
            check_gh(args)
        elif name == "rg":
            check_rg(args)
        elif name == "find":
            check_find(args)
        elif name == "sed":
            check_sed(args)
        else:
            raise Blocked(f"`{name}` is not allowed — only read-only git, gh, rg, find, and text filters")


def run_payload(payload: dict) -> int:
    command = (payload.get("tool_input") or {}).get("command", "")
    try:
        check(command)
    except Blocked as reason:
        print(f"BLOCKED by review-agent guard: {reason}. You are read-only; do not look for "
              "another way. Use the Read and Grep tools, or write UNSURE with what you checked.",
              file=sys.stderr)
        return 2
    return 0
