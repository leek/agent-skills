"""Read-only shell policy for the browser-test agents (browser-tester, browser-test-planner).

hooks/pre_tool_guard.py enforces this policy on their shell calls. Every segment
of the command (split on &&, ||, ;, |) must be an allowed read-only agent-browser
call or a read-only text filter under both bash and zsh rules.

Per-run scope comes from .scratch/browser-test/<run-id>/scope.json, written by
skills/browser-test/scripts/start-run.sh. The run id is read from the session
name, bt-<run-id>-<tag>.
"""

import json
import os
import re
from urllib.parse import urlsplit

from shell_syntax import Blocked, check_filter, parse_command

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
# Flags the other verbs may carry (find and screenshot take only their own, below). Everything else (--fn, --download, --profile, --auto-connect,
# --cdp, --headers, --headed, …) runs JS, writes files, or swaps the browser, so it is refused.
SAFE_BOOL_FLAGS = {"--clear", "--json", "--full", "-i", "--interactive", "-c", "--compact"}
SAFE_VALUE_FLAGS = {"--filter", "--type", "--status", "--method", "--load", "--url", "--text",
                    "--timeout", "-d", "--depth", "-s", "--selector"}
SAFE_FLAGS = SAFE_BOOL_FLAGS | SAFE_VALUE_FLAGS
# `agent-browser screenshot --help` (0.43): usage `screenshot [selector] [path]`, booleans
# --full/-f, --if-changed, --annotate, and these four value flags. Legal on screenshot only.
SCREENSHOT_VALUE_FLAGS = {"--threshold", "--screenshot-dir", "--screenshot-quality", "--screenshot-format"}
SCREENSHOT_FLAGS = {"-f", "--full", "--if-changed", "--annotate", "--json"} | SCREENSHOT_VALUE_FLAGS
# `agent-browser find --help` (0.43): only --name <name> and --exact, plus the global --json.
FIND_BOOL_FLAGS = {"--exact", "--json"}
FIND_VALUE_FLAGS = {"--name"}
VERB_FLAGS = {"screenshot": SCREENSHOT_FLAGS, "find": FIND_BOOL_FLAGS | FIND_VALUE_FLAGS}
ELEMENT_STATES = {"visible", "hidden", "attached", "detached"}
FILTERS = {"grep", "head", "tail", "wc", "sort", "uniq", "echo"}
SEARCH_LABEL = re.compile(r"\s*search\b", re.IGNORECASE)
# `agent-browser get --help` (0.43) subcommands, less `cdp-url`: the browser's CDP WebSocket
# URL, which drives the session outside this allowlist.
GET_SUBCOMMANDS = {"text", "html", "value", "attr", "title", "url", "count", "box", "styles"}


def same_origin(url: str, origin: str) -> bool:
    a, b = urlsplit(url), urlsplit(origin)
    return a.scheme in ("http", "https") and (a.scheme, a.netloc) == (b.scheme, b.netloc)


def inside(path: str, run_dir: str, cwd: str) -> bool:
    real = os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))
    return real.startswith(os.path.realpath(run_dir) + os.sep)


def check_screenshot(rest: list[str], save_dirs: list[str], cwd: str) -> None:
    """Only screenshot's own value flags consume a word, so every other flag's would-be value
    stays positional: `--timeout /tmp/x.png` saves to /tmp/x.png. Usage is `[selector] [path]`,
    so a third positional is refused and the last one (the path, or a lone word that may be one)
    must lie inside a save directory whatever it looks like, and so must --screenshot-dir. With
    neither a path nor --screenshot-dir, agent-browser saves to a temp directory, so that is refused.
    `--` never reaches here: check_browser refuses it, since agent-browser may not honor it."""
    positional: list[str] = []
    dirs: list[str] = []
    i = 0
    while i < len(rest):
        a = rest[i]
        i += 1
        if not a.startswith("-"):
            positional.append(a)
            continue
        name, eq, value = a.partition("=")
        if name in SCREENSHOT_VALUE_FLAGS:
            if not eq:
                if i >= len(rest):
                    raise Blocked(f"flag `{name}` needs a value")
                value = rest[i]
                i += 1
            if name == "--screenshot-dir":
                dirs.append(value)
    if len(positional) > 2:
        raise Blocked("`screenshot` takes at most a selector and a path")
    where = " or ".join(f"{d}/" for d in save_dirs)

    def saved_inside(p: str, may_be_dir: bool) -> bool:
        real = os.path.realpath(os.path.join(cwd, os.path.expanduser(p)))
        return any((may_be_dir and real == os.path.realpath(d)) or inside(p, d, cwd) for d in save_dirs)

    for d in dirs:
        if not saved_inside(d, True):
            raise Blocked(f"screenshots must be saved under {where}")
    if positional and not saved_inside(positional[-1], False):
        raise Blocked(f"screenshots must be saved under {where}")
    if not positional and not dirs:
        raise Blocked(f"screenshots must be saved under {where}: pass "
                      f"`screenshot [selector] {save_dirs[0]}/<name>.png`")


def strip_find_flags(rest: list[str]) -> list[str]:
    """Strip find's own flags (and --name's value), returning positionals. check_browser has
    already refused `--`, so every dash-prefixed word here is a flag."""
    positional: list[str] = []
    i = 0
    while i < len(rest):
        a = rest[i]
        if a.startswith("-"):
            name, eq, _ = a.partition("=")
            if name in FIND_BOOL_FLAGS:
                if eq:
                    raise Blocked(f"flag `{a}` is not allowed")
                i += 1
                continue
            if name in FIND_VALUE_FLAGS:
                if not eq:
                    if i + 1 >= len(rest):
                        raise Blocked(f"flag `{name}` needs a value")
                    i += 1
                i += 1
                continue
            raise Blocked(f"flag `{a}` is not allowed")
        positional.append(a)
        i += 1
    return positional


def check_find(rest: list[str]) -> None:
    pos = strip_find_flags(rest)
    if not pos:
        raise Blocked("`find` needs <locator> <value> <action>")
    if pos[0] == "nth":
        # find nth <n> <selector> <action> [text]
        if len(pos) < 4 or not pos[1].isdigit():
            raise Blocked("`find nth` needs <n> <selector> <action>")
        locator, value, action, extra = pos[0], pos[2], pos[3], pos[4:]
    else:
        # find <locator> <value> <action> [text]
        if len(pos) < 3:
            raise Blocked("`find` needs <locator> <value> <action>")
        locator, value, action, extra = pos[0], pos[1], pos[2], pos[3:]
    if action in FIND_READ_ACTIONS:
        if extra:
            raise Blocked(f"`find … {action}` takes no extra arguments")
        return
    if action in ("fill", "type"):
        if len(extra) != 1:
            raise Blocked(f"`find … {action}` needs exactly one text argument")
        # The page writes its own labels, so the word must open the label: "Search users"
        # passes, "Research budget" and "Not a search" do not.
        search = (locator == "role" and value == "searchbox") or (
            locator in ("placeholder", "label") and SEARCH_LABEL.match(value) is not None)
        if search:
            return
        raise Blocked("typing is only allowed into a search box (`find role searchbox fill <text>`)")
    raise Blocked(f"`find … {action}` is not a read-only action")


def load_scope(cwd: str, run_id: str) -> tuple[dict | None, str]:
    run_dir = os.path.join(cwd, ".scratch", "browser-test", run_id)
    try:
        with open(os.path.join(run_dir, "scope.json")) as fh:
            data = json.load(fh)
            if not isinstance(data, dict):
                return None, run_dir
            return data, run_dir
    except (OSError, ValueError):
        return None, run_dir


def check_browser(args: list[str], cwd: str) -> None:
    if len(args) < 2 or args[0] != "--session":
        raise Blocked("every agent-browser call must start with `--session bt-<run-id>-<tag>`")
    m = SESSION.match(args[1])
    if not m:
        raise Blocked("every agent-browser call must start with `--session bt-<run-id>-<tag>`")
    scope, run_dir = load_scope(cwd, m.group(1))
    if scope is None:
        raise Blocked("no scope.json for this run under .scratch/browser-test/ — the run was not started")
    args = args[2:]
    if args[:1] == ["--state"]:
        if len(args) < 2 or not scope.get("state") or args[1] != scope["state"]:
            raise Blocked("`--state` must be the exact auth file from your brief")
        args = args[2:]
    if not args:
        raise Blocked("missing agent-browser verb")
    check_verb(args[0], args[1:], cwd, [run_dir], scope["origin"])


def check_verb(verb: str, rest: list[str], cwd: str, save_dirs: list[str], origin: str | None) -> None:
    """One read-only agent-browser verb. `origin` holds open/read to one site (a browser-test
    run); None allows any http(s) URL and the rendering-only `set` forms (ui-reviewer)."""
    for i, a in enumerate(rest):
        if not a.startswith("-") or a == PROBE:
            continue
        if a == "--state" and verb == "wait" and rest[i + 1:i + 2] and rest[i + 1] in ELEMENT_STATES:
            continue
        allowed = VERB_FLAGS.get(verb, SAFE_FLAGS)
        if a.split("=", 1)[0] not in allowed:
            raise Blocked(f"flag `{a}` is not allowed")
    if verb == "get":
        if not rest or rest[0] not in GET_SUBCOMMANDS:
            raise Blocked(f"`get` allows only {', '.join(sorted(GET_SUBCOMMANDS))}")
        return
    if verb in ("snapshot", "click", "hover", "focus", "scroll", "scrollintoview", "wait",
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
        if origin is None:
            if len(rest) != 1 or urlsplit(rest[0]).scheme not in ("http", "https"):
                raise Blocked(f"`{verb}` takes one http(s) URL")
            return
        if len(rest) != 1 or not same_origin(rest[0], origin):
            raise Blocked(f"`{verb}` is only allowed on {origin} — navigate by clicking")
        return
    if verb == "set" and origin is None:
        if (rest[:1] == ["viewport"] and len(rest) == 3 and rest[1].isdigit() and rest[2].isdigit()) or (
                rest[:1] == ["device"] and len(rest) == 2) or (
                rest[:1] == ["media"] and 1 <= len(rest) <= 3
                and set(rest[1:]) <= {"dark", "light", "reduced-motion"}):
            return
        raise Blocked("`set` allows only viewport <w> <h>, device <name>, and media [dark|light] [reduced-motion]")
    if verb == "screenshot":
        check_screenshot(rest, save_dirs, cwd)
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


def check(command: str, cwd: str) -> None:
    parts = parse_command(command)
    for seg in parts:
        if seg[0] in FILTERS:
            check_filter(seg[0], seg[1:])
            continue
        if seg[0] != "agent-browser":
            raise Blocked(f"`{seg[0]}` is not allowed — only agent-browser and read-only filters")
        check_browser(seg[1:], cwd)

