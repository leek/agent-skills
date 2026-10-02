#!/usr/bin/env python3
"""PreToolUse guard for the PR-review agents (finding-verifier, pr-reviewer).

Both agents read untrusted text: review comments, bot findings, and the PR diff.
Their bodies say read-only; this hook enforces it. Wired from the plugin's
hooks/hooks.json, so it sees every Bash call in the session, and it exits 0 at
once unless the caller's agent_type is one of GUARDED. For those, every segment
of the command (split on &&, ||, ;, |) must be a read-only git, gh, rg, or text
command. Anything else exits 2, which blocks the call and shows stderr to the agent.
"""

import json
import re
import shlex
import sys

GUARDED = {"finding-verifier", "pr-reviewer"}

FILTERS = {"cat", "head", "tail", "wc", "sort", "uniq", "cut", "tr", "echo", "ls", "jq",
           "grep", "egrep", "cd", "pwd", "basename", "dirname", "true"}
GIT_READ = {"log", "show", "diff", "ls-files", "ls-tree", "blame", "grep", "rev-parse",
            "rev-list", "merge-base", "cat-file", "status", "range-diff", "shortlog",
            "describe", "name-rev", "for-each-ref", "fetch"}
GH_READ = {("pr", "view"), ("pr", "diff"), ("pr", "checks"), ("pr", "list"),
           ("issue", "view"), ("issue", "list"), ("run", "view"), ("repo", "view")}
GH_FIELDS = {"-f", "-F", "--field", "--raw-field"}
SAFE_REDIRECTS = {("2", ">", "/dev/null"), ("2", ">&", "1"), ("2", ">", "&1")}


class Blocked(Exception):
    pass


def check_git(args: list[str]) -> None:
    while args[:1] == ["--no-pager"] or args[:1] == ["-C"]:
        args = args[2:] if args[0] == "-C" else args[1:]
    if not args or args[0] not in GIT_READ:
        raise Blocked(f"`git {args[0] if args else ''}` is not a read-only git command")
    for a in args[1:]:
        if a.startswith(("--output", "--upload-pack", "--ext-diff", "--exec")):
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


def check(command: str) -> None:
    if "`" in command or "$(" in command:
        raise Blocked("command substitution is not allowed")
    try:
        parts = segments(command.replace("\\\n", " "))
    except ValueError as error:
        raise Blocked(f"could not parse the command ({error})")
    if not parts:
        raise Blocked("empty command")
    for seg in parts:
        if any(re.fullmatch(r"[();<>|&\n]+", t) and any(c in t for c in "<>&\n") for t in seg):
            raise Blocked("redirects, background jobs, and multi-line commands are not allowed")
        name, args = seg[0], seg[1:]
        if name in FILTERS:
            continue
        if name == "git":
            check_git(args)
        elif name == "gh":
            check_gh(args)
        elif name == "rg":
            check_rg(args)
        elif name == "find":
            check_find(args)
        else:
            raise Blocked(f"`{name}` is not allowed — only read-only git, gh, rg, find, and text filters")


def main() -> int:
    payload = json.load(sys.stdin)
    agent = (payload.get("agent_type") or "").rsplit(":", 1)[-1]
    if agent not in GUARDED or payload.get("tool_name", "Bash") != "Bash":
        return 0
    command = (payload.get("tool_input") or {}).get("command", "")
    try:
        check(command)
    except Blocked as reason:
        print(f"BLOCKED by review-agent guard: {reason}. You are read-only; do not look for "
              "another way. Use the Read and Grep tools, or write UNSURE with what you checked.",
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
