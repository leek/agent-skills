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
# `gh api` flags, by long name. Every flag must be one of these: an unknown flag is refused,
# because a flag this guard takes for a boolean could swallow `-X GET` as its value.
GH_API_VALUE = {"--cache", "--header", "--hostname", "--jq", "--method", "--preview",
                "--raw-field", "--field", "--template"}
GH_API_BOOL = {"--include", "--paginate", "--silent", "--slurp", "--verbose"}
GH_API_SHORT = {"H": "--header", "q": "--jq", "X": "--method", "p": "--preview",
                "f": "--raw-field", "F": "--field", "t": "--template", "i": "--include"}


FETCH_FLAGS = {"-q", "--quiet", "-v", "--verbose", "--all", "--no-tags", "--dry-run",
               "--no-recurse-submodules"}
FETCH_DEPTH = re.compile(r"--(depth|deepen)=\d+")


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
    if args[0] == "fetch":
        # Flags are an allowlist, none taking a separate value, so the positionals are exact:
        # `--stdin` and `--refmap` add refspecs this guard would not see. The first positional
        # is the remote; a later `src:dst` or `tag <name>` writes a local ref.
        positional = []
        for a in args[1:]:
            if not a.startswith("-"):
                positional.append(a)
            elif a not in FETCH_FLAGS and not FETCH_DEPTH.fullmatch(a):
                raise Blocked(f"`git fetch {a}` is not allowed; use only {', '.join(sorted(FETCH_FLAGS))}, --depth=<n>")
        if any(":" in a or a == "tag" for a in positional[1:]):
            raise Blocked("`git fetch <remote> <src>:<dst>` and `tag <name>` write a local ref; fetch without a destination")


def parse_gh_api(rest: list[str]) -> tuple[list[tuple[str, str]], list[str]]:
    """Split `gh api` arguments into (long flag, value) pairs and positionals, the way pflag does.

    pflag takes a value attached to its flag (`-XDELETE`, `-X=DELETE`, `-fa=b`, `--field=a=b`)
    as well as in the next argument, and clusters short booleans (`-iXDELETE`).
    """
    flags: list[tuple[str, str]] = []
    positional: list[str] = []
    i = 0

    def value_after(name: str) -> str:
        nonlocal i
        i += 1
        if i >= len(rest):
            raise Blocked(f"`gh api {name}` needs a value")
        return rest[i]

    while i < len(rest):
        a = rest[i]
        if a == "--":
            positional.extend(rest[i + 1:])
            break
        if a.startswith("--"):
            name, eq, attached = a.partition("=")
            if name == "--input":
                raise Blocked("`gh api --input` sends a request body")
            if name in GH_API_BOOL:
                flags.append((name, attached))
            elif name in GH_API_VALUE:
                flags.append((name, attached if eq else value_after(name)))
            else:
                raise Blocked(f"`gh api {name}` is not a flag this guard knows")
        elif a.startswith("-") and len(a) > 1:
            j = 1
            while j < len(a):
                name = GH_API_SHORT.get(a[j])
                if name is None:
                    raise Blocked(f"`gh api -{a[j]}` is not a flag this guard knows")
                if name in GH_API_BOOL:
                    flags.append((name, ""))
                    j += 1
                    continue
                attached = a[j + 1:]
                flags.append((name, attached[1:] if attached.startswith("=") else attached)
                             if attached else (name, value_after(a[:1] + a[j])))
                break
        else:
            positional.append(a)
        i += 1
    return flags, positional


def check_gh(args: list[str]) -> None:
    if tuple(args[:2]) in GH_READ:
        if any(long_option_in(a, ("--web",)) or (a.startswith("-") and not a.startswith("--") and "w" in a)
               for a in args[2:]):
            raise Blocked("`--web` opens a browser")
        return
    if args[:1] != ["api"]:
        raise Blocked(f"`gh {' '.join(args[:2])}` is not a read-only gh command")
    flags, positional = parse_gh_api(args[1:])
    methods = [v.upper() for name, v in flags if name == "--method"]
    fields = [(name, v) for name, v in flags if name in ("--field", "--raw-field")]
    if any(m != "GET" for m in methods):
        raise Blocked(f"`gh api` with method {next(m for m in methods if m != 'GET')} is not read-only")
    if positional[:1] == ["graphql"]:
        for name, v in fields:
            if "mutation" in v.lower():
                raise Blocked("GraphQL mutations are not read-only")
            if name == "--field" and v.partition("=")[2].startswith("@"):
                raise Blocked("`gh api graphql -F key=@file` reads the query from a file this guard cannot check")
        return
    if fields and not methods:
        raise Blocked("`gh api` with -f/-F sends a POST; add `-X GET` for a read")


def check_rg(args: list[str]) -> None:
    for flag in ("--pre", "--hostname-bin"):
        if any(a.startswith(flag) for a in args):
            raise Blocked(f"`rg {flag}` runs a program")


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
