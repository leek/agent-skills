#!/usr/bin/env python3
"""PreToolUse guard for the browser-test read-only agents.

Wired from the plugin's hooks/hooks.json, so it sees every Bash call in the
session. It exits 0 at once unless the caller's agent_type is one of GUARDED.
For those, every segment of the command (split on &&, ||, ;, |) must be an
allowed read-only agent-browser call or a read-only text filter. Anything else
exits 2, which blocks the call and shows stderr to the agent.

Per-run scope comes from .scratch/browser-test/<run-id>/scope.json, written by
start-run.sh. The run id is read from the session name, bt-<run-id>-<tag>.
"""

import json
import os
import re
import shlex
import sys
from urllib.parse import urlsplit

GUARDED = {"browser-tester", "browser-test-planner"}

PROBE = (
    "(() => { const t = document.body.innerText; "
    "const hits = ['Server Error', 'Internal Server Error', 'Something went wrong', 'Page Expired', "
    "'Whoops', 'Application error', 'Unhandled Runtime Error', 'Not Found']"
    ".filter(s => t.includes(s)); "
    "if (t.trim().length < 40) hits.push('blank-page'); "
    "return hits.join(', ') || 'ok'; })()"
)

SESSION = re.compile(r"^bt-(\d{8}-\d{6})-[a-z0-9]+$")
SAFE_KEYS = {"Escape", "Tab", "Shift+Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
             "PageUp", "PageDown", "Home", "End"}
FIND_READ_ACTIONS = {"click", "hover", "focus", "text", "scrollintoview"}
# Flags any verb may carry. Everything else (--fn, --download, --profile, --auto-connect,
# --cdp, --headers, --headed, …) runs JS, writes files, or swaps the browser, so it is refused.
SAFE_FLAGS = {"--clear", "--filter", "--type", "--status", "--method", "--load", "--url", "--text", "--timeout",
              "--json", "--full", "-i", "--interactive", "-c", "--compact", "-d", "--depth",
              "-s", "--selector"}
ELEMENT_STATES = {"visible", "hidden", "attached", "detached"}
FILTERS = {"grep", "head", "tail", "wc", "sort", "uniq", "echo"}
SAFE_REDIRECTS = {("2", ">", "/dev/null"), ("2", ">&", "1"), ("2", ">", "&1")}


class Blocked(Exception):
    pass


def same_origin(url: str, origin: str) -> bool:
    a, b = urlsplit(url), urlsplit(origin)
    return a.scheme in ("http", "https") and (a.scheme, a.netloc) == (b.scheme, b.netloc)


def inside(path: str, run_dir: str) -> bool:
    real = os.path.realpath(path)
    return real.startswith(os.path.realpath(run_dir) + os.sep)


def check_find(rest: list[str]) -> None:
    # find <locator> <value> <action> [text]
    if len(rest) < 3:
        raise Blocked("`find` needs <locator> <value> <action>")
    locator, value, action = rest[0], rest[1], rest[2]
    if action in FIND_READ_ACTIONS:
        return
    if action in ("fill", "type"):
        search = (locator == "role" and value == "searchbox") or (
            locator in ("placeholder", "label") and "search" in value.lower())
        if search:
            return
        raise Blocked("typing is only allowed into a search box (`find role searchbox fill <text>`)")
    raise Blocked(f"`find … {action}` is not a read-only action")


def check_browser(args: list[str], scope: dict | None, run_dir: str | None) -> None:
    if len(args) < 2 or args[0] != "--session" or not SESSION.match(args[1]):
        raise Blocked("every agent-browser call must start with `--session bt-<run-id>-<tag>`")
    if scope is None:
        raise Blocked(f"no scope.json for this run under .scratch/browser-test/ — the run was not started")
    args = args[2:]
    if args[:1] == ["--state"]:
        if len(args) < 2 or not scope.get("state") or args[1] != scope["state"]:
            raise Blocked("`--state` must be the exact auth file from your brief")
        args = args[2:]
    if not args:
        raise Blocked("missing agent-browser verb")

    verb, rest = args[0], args[1:]
    for i, a in enumerate(rest):
        if not a.startswith("-") or a == PROBE:
            continue
        if a == "--state" and verb == "wait" and rest[i + 1:i + 2] and rest[i + 1] in ELEMENT_STATES:
            continue
        if a.split("=", 1)[0] not in SAFE_FLAGS:
            raise Blocked(f"flag `{a}` is not allowed")
    if verb in ("snapshot", "click", "hover", "focus", "scroll", "scrollintoview", "wait", "get",
                "is", "back", "forward", "reload"):
        return
    if verb in ("console", "errors"):
        if rest not in ([], ["--clear"]):
            raise Blocked(f"`{verb}` takes only `--clear`")
        return
    if verb == "network":
        if rest[:1] != ["requests"]:
            raise Blocked("only `network requests` is allowed")
        return
    if verb in ("open", "read"):
        if verb == "read" and not rest:
            return
        if len(rest) != 1 or not same_origin(rest[0], scope["origin"]):
            raise Blocked(f"`{verb}` is only allowed on {scope['origin']} — navigate by clicking")
        return
    if verb == "screenshot":
        paths = [a for a in rest if not a.startswith("--")]
        if any(not inside(p, run_dir) for p in paths):
            raise Blocked(f"screenshots must be saved under {run_dir}/")
        return
    if verb == "press":
        if len(rest) != 1 or rest[0] not in SAFE_KEYS:
            raise Blocked("only navigation keys (Escape, Tab, arrows) may be pressed; never Enter or Space")
        return
    if verb == "tab":
        if rest == ["list"] or (len(rest) == 1 and rest[0].isdigit()) or (
                rest[:1] == ["close"] and all(a.isdigit() for a in rest[1:])):
            return
        raise Blocked("`tab` allows only list, <n>, and close")
    if verb == "eval":
        if rest != [PROBE]:
            raise Blocked("only the exact probe from your instructions may be eval'd")
        return
    if verb == "find":
        check_find(rest)
        return
    if verb == "close":
        if rest:
            raise Blocked("`close` takes no arguments (never --all)")
        return
    raise Blocked(f"`{verb}` is not an allowed verb for a read-only browser test")


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


def load_scope(cwd: str, segments_: list[list[str]]) -> tuple[dict | None, str | None]:
    for seg in segments_:
        if seg[:2] == ["agent-browser", "--session"] and len(seg) > 2:
            m = SESSION.match(seg[2])
            if m:
                run_dir = os.path.join(cwd, ".scratch", "browser-test", m.group(1))
                try:
                    with open(os.path.join(run_dir, "scope.json")) as fh:
                        return json.load(fh), run_dir
                except (OSError, ValueError):
                    return None, run_dir
    return None, None


def check(command: str, cwd: str) -> None:
    if "\n" in command or "\r" in command:
        raise Blocked("multi-line commands are not allowed")
    if "`" in command or "$(" in command:
        raise Blocked("command substitution is not allowed")
    try:
        parts = segments(command)
    except ValueError as error:
        raise Blocked(f"could not parse the command ({error})")
    if not parts:
        raise Blocked("empty command")
    scope, run_dir = load_scope(cwd, parts)
    for seg in parts:
        if any(re.fullmatch(r"[();<>|&]+", t) and any(c in t for c in "<>&") for t in seg):
            raise Blocked("redirects are not allowed")
        if seg[0] in FILTERS:
            continue
        if seg[0] != "agent-browser":
            raise Blocked(f"`{seg[0]}` is not allowed — only agent-browser and read-only filters")
        check_browser(seg[1:], scope, run_dir)


def main() -> int:
    payload = json.load(sys.stdin)
    agent = (payload.get("agent_type") or "").rsplit(":", 1)[-1]
    if agent not in GUARDED or payload.get("tool_name", "Bash") != "Bash":
        return 0
    command = (payload.get("tool_input") or {}).get("command", "")
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        check(command, cwd)
    except Blocked as reason:
        print(f"BLOCKED by browser-test guard: {reason}. This is a read-only test; do not look for "
              "another way. Record what you could not do and move on.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
