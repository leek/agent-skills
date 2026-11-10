#!/bin/bash
# Read and write the markdown ticket tracker under .scratch/ (see ../issue-tracker.md).
# Run from anywhere inside the target repo: .scratch/ is found at the git top level.
# No network. Every read goes through ../../scratch-status/scripts/scratch-state.sh
# (--no-commits), the tracker's one frontmatter reader, so this script, scratch-status and
# the /scratch board give the same status, claim, blockers and closed set for a file.
#
# Usage: ticket.sh [--root DIR] <subcommand> ...
#   --root DIR   use DIR/.scratch/ instead of the git top level's (tests)
#   <path>       a tracker file: .scratch/<slug>/spec.md, map.md, or a file under
#                decisions/, tickets/ or issues/; absolute, or relative to the current
#                directory or to the root
#
#   frontier <slug> [--kind tickets|decisions]                              read-only
#     {"slug","kind","tickets":[{"number","path","title","status","derived","claimed_by",
#      "claim_age_seconds","blocked_by":[..],"open_blockers":[..],"type","deploy_gate",
#      "delivery"}],"frontier":[..],"next","counts":{"open","closed","ready","blocked",
#      "claimed","in_progress","human"}}
#     "number" is the file's number as written ("01"); "path" is relative to the root.
#     "derived" is closed | ready | blocked | claimed (claimed-by set) | in-progress
#     (status in-progress, no claimant) | human (unblocked, unclaimed, at the ready-for-human
#     string) | unreadable (no status). "frontier" lists the ready numbers, lowest first;
#     "next" is the first of them or null. "claim_age_seconds" is the seconds since the
#     file last changed (its last commit when tracked, else its modification time) on a
#     claimed or in-progress ticket, else null: whether a claim is stale is the caller's
#     call. --kind defaults to tickets when the effort has build tickets, else decisions.
#     --built <n>[,<n>...] names tickets this run has built or merged but not closed yet
#     (a spec run closes its tickets at the end): they stop counting as open blockers, so
#     a ticket that waits only on them is "ready". They keep their own status.
#
#   claim <path> --as <id> [--built <n>[,<n>...]]
#     <id> may hold letters, digits, and . _ @ / + : - and inner spaces (autopilot:<run-id>).
#     --built is as for frontier: those blockers do not refuse the claim.
#     Build ticket or spec: sets status: in-progress and claimed-by: <id>. Decision ticket:
#     sets claimed-by only. Writes, reads the file again, and prints
#     {"won":true,"path","status","claimed_by"}. A second claim with the same id changes
#     nothing and wins. Refused, exit 1, nothing written:
#     {"won":false,"reason","path","status","claimed_by","open_blockers":[..]} with reason
#     closed | claimed | in-progress | blocked | unreadable | lost.
#
#   release <path> [--note <text>]
#     Clears claimed-by. A build ticket or spec at in-progress goes back to the AFK-ready
#     string (ready-for-agent, or what .agents/triage-labels.md maps that role to); any
#     other status (ready-for-human) stays. --note appends the text under ## Comments,
#     adding the heading when missing. Prints {"path","status","claimed_by":""}.
#
#   resolve <path> --body-file <file>
#     Appends ## Resolution with the file's content (fills an empty ## Resolution heading),
#     sets status: closed, clears claimed-by. Prints {"path","status":"closed","claimed_by":""}.
#     Refused when the item is closed or already has a ## Resolution with content.
#
#   close <path> --reason-file <file>
#     Out-of-scope or superseded close: appends ## Closed with the reason, sets
#     status: closed, clears claimed-by, writes no ## Resolution. Prints as resolve does.
#
#   set-status <path> <status>
#     Writes status only. Legal: open | closed on a map or decision ticket; a triage role's
#     status string, in-progress, or closed on a spec or build ticket.
#     Prints {"path","status","previous"}.
#
#   lint <slug>                                                             read-only
#     {"ok":bool,"errors":[{"file","rule","detail"}]}, exit 1 when not ok. Rules:
#     frontmatter, title-quoted, status-legal, no-comments, blocker-missing,
#     blocker-not-lower, delivery-count, delivery-not-last, delivery-blockers,
#     filename-number.
#
# A refusal of release, resolve, close or set-status prints
# {"error","detail","path","status","claimed_by"} (set-status adds "legal":[..]).
# A write changes only the status / claimed-by frontmatter lines and the appended section;
# every other byte of the file stays, and the file is replaced atomically.
#
# Stdout: one JSON object. Stderr: messages.
# Exit: 0 done, 1 refused or lint errors, 2 usage error or unreadable tracker.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
state_sh="$here/../../scratch-status/scripts/scratch-state.sh"
[ -f "$state_sh" ] || { echo "ticket.sh: scratch-state.sh not found at $state_sh" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "ticket.sh: python3 is required" >&2; exit 2; }

python3 - "$state_sh" "$@" <<'PY'
# Annotations stay unevaluated, so `dict | None` loads on the macOS system Python 3.9.
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

STATE_SH = sys.argv[1]
ARGV = sys.argv[2:]
USAGE = """usage: ticket.sh [--root DIR] <subcommand> ...
  frontier <slug> [--kind tickets|decisions]
  claim <path> --as <id> [--built <n>[,<n>...]]
  release <path> [--note <text>]
  resolve <path> --body-file <file>
  close <path> --reason-file <file>
  set-status <path> <status>
  lint <slug>"""
TICKET_DIRS = {"decisions": "decision", "tickets": "ticket", "issues": "ticket"}


def usage(message: str) -> None:
    print(f"ticket.sh: {message}", file=sys.stderr)
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def emit(obj: dict) -> None:
    print(json.dumps(obj))


def refuse(obj: dict, message: str) -> None:
    emit(obj)
    print(f"ticket.sh: refused: {message}", file=sys.stderr)
    sys.exit(1)


# ---- arguments -------------------------------------------------------------------------

def take_options(args: list[str], names: tuple[str, ...]) -> tuple[list[str], dict[str, str]]:
    """Split `--name value` options (those in `names`) from the positional arguments."""
    rest: list[str] = []
    found: dict[str, str] = {}
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in names:
            if i + 1 >= len(args):
                usage(f"{arg} needs a value")
            found[arg] = args[i + 1]
            i += 2
        elif arg.startswith("--"):
            usage(f"unknown option: {arg}")
        else:
            rest.append(arg)
            i += 1
    return rest, found


def find_root(given: str | None) -> str:
    if given is not None:
        if not os.path.isdir(given):
            usage(f"no such directory: {given}")
        return os.path.realpath(given)
    try:
        res = subprocess.run(["git", "rev-parse", "--show-toplevel"], text=True, capture_output=True)
    except OSError:
        res = None
    if res is None or res.returncode != 0 or not res.stdout.strip():
        usage("not inside a git repository; pass --root DIR")
    return os.path.realpath(res.stdout.strip())


# ---- reading: scratch-state.sh is the one parser ---------------------------------------

def load_state(root: str, slug: str) -> tuple[dict, dict | None]:
    """scratch-state.sh's answer for one effort: (whole output, the effort or None)."""
    try:
        res = subprocess.run(
            ["bash", STATE_SH, "--root", root, "--no-commits", slug], text=True, capture_output=True
        )
    except OSError as exc:
        print(f"ticket.sh: cannot run scratch-state.sh: {exc}", file=sys.stderr)
        sys.exit(2)
    if res.returncode != 0:
        print(res.stderr.strip() or "ticket.sh: scratch-state.sh failed", file=sys.stderr)
        sys.exit(2)
    state = json.loads(res.stdout)
    effort = next((e for e in state["efforts"] if e["slug"] == slug), None)
    return state, effort


def effort_items(effort: dict) -> list[dict]:
    singles = [f for f in (effort.get("map"), effort.get("spec")) if f]
    return singles + effort["decisions"] + effort["tickets"]


def number_key(number: str) -> tuple[float, str]:
    return (float(int(number)) if number.isdigit() else float("inf"), number)


def legal_statuses(kind: str, state: dict) -> list[str]:
    if kind in ("map", "decision"):
        return ["open", "closed"]
    roles = state["vocabulary"]["roles"]
    legal = [roles[r] for r in ("needs-triage", "needs-info", "ready-for-agent", "ready-for-human", "wontfix")]
    return legal + ["in-progress", "closed"]


class Target:
    """One tracker file named on the command line, read through scratch-state.sh."""

    def __init__(self, root: str, arg: str) -> None:
        candidates = [arg] if os.path.isabs(arg) else [arg, os.path.join(root, arg)]
        found = next((c for c in candidates if os.path.isfile(c)), None)
        if found is None:
            usage(f"no such file: {arg}")
        self.root = root
        self.abs = os.path.realpath(found)
        parts = os.path.relpath(self.abs, root).split(os.sep)
        is_single = len(parts) == 3 and parts[2] in ("map.md", "spec.md")
        is_ticket = len(parts) == 4 and parts[2] in TICKET_DIRS and parts[3].endswith(".md")
        if parts[0] != ".scratch" or not (is_single or is_ticket):
            usage(
                f"not a tracker file: {arg} (want .scratch/<slug>/spec.md, map.md, "
                "or a file under decisions/, tickets/ or issues/)"
            )
        self.slug = parts[1]
        self.rel = "/".join(parts[2:])
        self.path = "/".join(parts)
        self.kind = TICKET_DIRS[parts[2]] if is_ticket else parts[2][:-3]
        self.is_build = self.kind in ("ticket", "spec")
        self.state: dict = {}
        self.item: dict = {}
        self.reload()

    def reload(self) -> None:
        self.state, effort = load_state(self.root, self.slug)
        item = next((f for f in effort_items(effort) if f["path"] == self.rel), None) if effort else None
        if item is None:
            print(f"ticket.sh: scratch-state.sh does not list {self.path}", file=sys.stderr)
            sys.exit(2)
        self.item = item

    @property
    def status(self) -> str:
        return self.item["status"]

    @property
    def claimed_by(self) -> str:
        return self.item["claimed_by"]

    @property
    def is_closed(self) -> bool:
        return self.item.get("derived_status") == "closed"

    def facts(self) -> dict:
        return {"path": self.path, "status": self.status, "claimed_by": self.claimed_by}


# ---- writing: line-level edits, every other byte kept -----------------------------------

def read_lines(path: str) -> list[str]:
    with open(path, "rb") as fh:
        text = fh.read().decode("utf-8", errors="surrogateescape")
    # Split after each \n only: \r\n pairs and every other byte stay inside their line.
    return [ln for ln in re.split(r"(?<=\n)", text) if ln != ""]


def write_lines(path: str, lines: list[str]) -> None:
    data = "".join(lines).encode("utf-8", errors="surrogateescape")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".ticket-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        shutil.copymode(path, tmp)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def bare(line: str) -> str:
    return line.rstrip("\r\n")


def front_end(lines: list[str]) -> int:
    """Index of the closing `---` of the frontmatter block, or -1 when there is none."""
    if not lines or bare(lines[0]) != "---":
        return -1
    for i in range(1, len(lines)):
        if bare(lines[i]) == "---":
            return i
    return -1


def eol_of(lines: list[str]) -> str:
    return "\r\n" if lines and lines[0].endswith("\r\n") else "\n"


def set_key(lines: list[str], key: str, value: str) -> None:
    """Rewrite `key:` inside the frontmatter, or add it before the closing `---`."""
    close = front_end(lines)
    new = f"{key}: {value}" if value else f"{key}:"
    for i in range(1, close):
        if lines[i].startswith(f"{key}:"):
            lines[i] = new + lines[i][len(bare(lines[i])):]
            return
    lines.insert(close, new + eol_of(lines))


def heading_index(lines: list[str], title: str | None, start: int) -> int:
    """First `## <title>` line at or after `start` (any `## ` heading when title is None),
    outside fenced code; -1 when there is none."""
    fence = ""
    pattern = re.compile(r"^##\s+\S" if title is None else rf"^##\s+{re.escape(title)}\s*$", re.I)
    for i in range(start, len(lines)):
        text = bare(lines[i])
        marker = re.match(r"^\s*(```+|~~~+)", text)
        if marker:
            if fence == "":
                fence = marker.group(1)[:3]
            elif marker.group(1).startswith(fence):
                fence = ""
            continue
        if fence == "" and pattern.match(text):
            return i
    return -1


def section_bounds(lines: list[str], title: str) -> tuple[int, int]:
    """(heading index, index after the section's last line), or (-1, -1)."""
    head = heading_index(lines, title, front_end(lines) + 1)
    if head < 0:
        return -1, -1
    nxt = heading_index(lines, None, head + 1)
    return head, (nxt if nxt >= 0 else len(lines))


def section_has_content(lines: list[str], title: str) -> bool:
    head, end = section_bounds(lines, title)
    return head >= 0 and any(ln.strip() for ln in lines[head + 1:end])


def content_lines(text: str, eol: str) -> list[str]:
    body = text.replace("\r\n", "\n").strip("\n")
    return [ln + eol for ln in body.split("\n")]


def add_to_section(lines: list[str], title: str, text: str) -> None:
    """Append `text` under `## <title>`, adding the heading at the end of the file when
    the file has none."""
    eol = eol_of(lines)
    new = content_lines(text, eol)
    head, end = section_bounds(lines, title)
    if head < 0:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += eol
        if lines and lines[-1].strip() != "":
            lines.append(eol)
        lines.extend([f"## {title}{eol}", eol] + new)
        return
    last = end
    while last > head + 1 and lines[last - 1].strip() == "":
        last -= 1
    if not lines[last - 1].endswith("\n"):
        lines[last - 1] += eol
    block = [eol] + new
    if last == end and end < len(lines):
        block.append(eol)
    lines[last:last] = block


def read_text_arg(path: str, option: str) -> str:
    try:
        with open(path, "rb") as fh:
            text = fh.read().decode("utf-8", errors="surrogateescape")
    except OSError as exc:
        usage(f"cannot read {option} {path}: {exc.strerror}")
    if not text.strip():
        usage(f"{option} {path} is empty")
    return text


def editable_lines(target: Target) -> list[str]:
    lines = read_lines(target.abs)
    if front_end(lines) < 0:
        refuse(
            {"error": "no-frontmatter", "detail": "the file has no --- frontmatter block to edit", **target.facts()},
            f"{target.path} has no frontmatter block",
        )
    return lines


# ---- subcommands -----------------------------------------------------------------------

def built_set(opts: dict) -> set:
    """Numbers passed as --built 01,02: compared as integers, so 1 and 01 are one ticket."""
    raw = opts.get("--built", "")
    names = [n.strip() for n in raw.split(",") if n.strip()]
    if any(not n.isdigit() for n in names):
        usage("--built takes ticket numbers separated by commas")
    return {int(n) for n in names}


def still_open(blockers: list, built: set) -> list:
    return [b for b in blockers if not (b.isdigit() and int(b) in built)]


def cmd_frontier(root: str, args: list[str]) -> None:
    rest, opts = take_options(args, ("--kind", "--built"))
    if len(rest) != 1:
        usage("frontier takes one slug")
    built = built_set(opts)
    slug = rest[0].strip("/")
    if slug.startswith(".scratch/"):
        slug = slug[len(".scratch/"):]
    kind = opts.get("--kind")
    if kind not in (None, "tickets", "decisions"):
        usage("--kind is tickets or decisions")
    if not os.path.isdir(os.path.join(root, ".scratch", slug)):
        usage(f"no effort at .scratch/{slug}/")
    state, effort = load_state(root, slug)
    tickets_in = effort["tickets"] if effort else []
    decisions_in = effort["decisions"] if effort else []
    if kind is None:
        kind = "tickets" if tickets_in or not decisions_in else "decisions"
    human = state["vocabulary"]["roles"]["ready-for-human"]
    now = time.time()

    def derive(item: dict) -> str:
        raw = item["derived_status"]
        if raw == "in progress":
            return "claimed" if item["claimed_by"] else "in-progress"
        if raw == "ready" and item["status"] == human:
            return "human"
        return raw

    rows = []
    for item in sorted(tickets_in if kind == "tickets" else decisions_in, key=lambda f: number_key(f["number"])):
        width = len(item["number"]) or 2
        derived = derive(item)
        open_blockers = still_open(item["open_blockers"], built)
        if derived == "blocked" and not open_blockers:
            derived = "human" if item["status"] == human else "ready"
        rows.append({
            "number": item["number"],
            "path": f".scratch/{slug}/{item['path']}",
            "title": item["title"],
            "status": item["status"],
            "derived": derived,
            "claimed_by": item["claimed_by"],
            "claim_age_seconds": max(0, int(now - item["last_change_ts"])) if derived in ("claimed", "in-progress") else None,
            "blocked_by": [b.zfill(width) if b.isdigit() else b for b in item["blocked_by"]],
            "open_blockers": open_blockers,
            "type": item["type"],
            "deploy_gate": item["deploy_gate"],
            "delivery": item["delivery"],
        })
    frontier = [r["number"] for r in rows if r["derived"] == "ready"]
    count = lambda name: sum(1 for r in rows if r["derived"] == name)
    emit({
        "slug": slug,
        "kind": kind,
        "tickets": rows,
        "frontier": frontier,
        "next": frontier[0] if frontier else None,
        "counts": {
            "open": sum(1 for r in rows if r["derived"] != "closed"),
            "closed": count("closed"),
            "ready": count("ready"),
            "blocked": count("blocked"),
            "claimed": count("claimed"),
            "in_progress": count("in-progress"),
            "human": count("human"),
        },
    })


def cmd_claim(root: str, args: list[str]) -> None:
    rest, opts = take_options(args, ("--as", "--built"))
    if len(rest) != 1 or "--as" not in opts:
        usage("claim takes one path and --as <id>")
    claim_id = opts["--as"]
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9._@/+: -]*[A-Za-z0-9._@/+:-])?", claim_id):
        usage("--as wants letters, digits, and . _ @ / + : - or inner spaces")
    built = built_set(opts)
    target = Target(root, rest[0])
    if target.kind == "map":
        usage("a map is not claimed")

    def lose(reason: str, message: str) -> None:
        refuse({"won": False, "reason": reason, **target.facts(),
                "open_blockers": still_open(target.item["open_blockers"], built)}, message)

    if target.item["derived_status"] == "unreadable":
        lose("unreadable", f"{target.path} has no readable status")
    if target.is_closed:
        lose("closed", f"{target.path} is {target.status}")
    if target.claimed_by == claim_id:
        emit({"won": True, **target.facts()})
        return
    if target.claimed_by:
        lose("claimed", f"{target.path} is claimed by {target.claimed_by}")
    if target.is_build and target.status == "in-progress":
        lose("in-progress", f"{target.path} is in-progress with no claimant; release it first to take it over")
    waiting = still_open(target.item["open_blockers"], built)
    if waiting:
        lose("blocked", f"{target.path} waits on {', '.join(waiting)}")

    lines = editable_lines(target)
    if target.is_build:
        set_key(lines, "status", "in-progress")
    set_key(lines, "claimed-by", claim_id)
    write_lines(target.abs, lines)

    # Compare after write: another session may have saved its own claim over this one.
    target.reload()
    if target.claimed_by != claim_id:
        lose("lost", f"{target.path} now reads claimed-by {target.claimed_by or '(empty)'}")
    emit({"won": True, **target.facts()})


def cmd_release(root: str, args: list[str]) -> None:
    rest, opts = take_options(args, ("--note",))
    if len(rest) != 1:
        usage("release takes one path")
    note = opts.get("--note")
    if note is not None and not note.strip():
        usage("--note is empty")
    target = Target(root, rest[0])
    if target.kind == "map":
        usage("a map is not claimed or released")
    if target.is_closed:
        refuse({"error": "closed", "detail": "a closed item has nothing to release", **target.facts()}, f"{target.path} is closed")
    lines = editable_lines(target)
    before = list(lines)
    if target.is_build and target.status == "in-progress":
        set_key(lines, "status", target.state["vocabulary"]["roles"]["ready-for-agent"])
    if target.claimed_by:
        set_key(lines, "claimed-by", "")
    if note is not None:
        add_to_section(lines, "Comments", note)
    if lines != before:
        write_lines(target.abs, lines)
        target.reload()
    emit(target.facts())


def cmd_finish(root: str, args: list[str], option: str, heading: str) -> None:
    """resolve (## Resolution) and close (## Closed)."""
    name = "resolve" if heading == "Resolution" else "close"
    rest, opts = take_options(args, (option,))
    if len(rest) != 1 or option not in opts:
        usage(f"{name} takes one path and {option} <file>")
    text = read_text_arg(opts[option], option)
    target = Target(root, rest[0])
    if target.kind == "map":
        usage(f"a map is closed with set-status, not {name}")
    if target.is_closed:
        refuse({"error": "closed", "detail": f"already {target.status}", **target.facts()}, f"{target.path} is already closed")
    lines = editable_lines(target)
    if heading == "Resolution" and section_has_content(lines, "Resolution"):
        refuse(
            {"error": "has-resolution", "detail": "the item already has a ## Resolution", **target.facts()},
            f"{target.path} already has a ## Resolution",
        )
    set_key(lines, "status", "closed")
    if target.claimed_by:
        set_key(lines, "claimed-by", "")
    add_to_section(lines, heading, text)
    write_lines(target.abs, lines)
    target.reload()
    emit(target.facts())


def cmd_set_status(root: str, args: list[str]) -> None:
    rest, _ = take_options(args, ())
    if len(rest) != 2:
        usage("set-status takes one path and one status")
    target = Target(root, rest[0])
    wanted = rest[1].strip().lower()
    legal = legal_statuses(target.kind, target.state)
    if wanted not in legal:
        refuse(
            {
                "error": "illegal-status",
                "detail": f"{rest[1]} is not a status of a {target.kind}; legal: {', '.join(legal)}",
                "legal": legal,
                **target.facts(),
            },
            f"{rest[1]} is not legal on {target.path}; legal: {', '.join(legal)}",
        )
    previous = target.status
    if previous != wanted:
        lines = editable_lines(target)
        set_key(lines, "status", wanted)
        write_lines(target.abs, lines)
        target.reload()
    emit({"path": target.path, "status": target.status, "previous": previous})


def has_comment(value: str) -> bool:
    val = value.strip()
    if val[:1] in ("\"", "'"):
        end = val.find(val[0], 1)
        if end > 0:
            return val[end + 1:].strip().startswith("#")
    return re.search(r"(?:^|\s)#", val) is not None


def cmd_lint(root: str, args: list[str]) -> None:
    rest, _ = take_options(args, ())
    if len(rest) != 1:
        usage("lint takes one slug")
    slug = rest[0].strip("/")
    if slug.startswith(".scratch/"):
        slug = slug[len(".scratch/"):]
    if not os.path.isdir(os.path.join(root, ".scratch", slug)):
        usage(f"no effort at .scratch/{slug}/")
    state, effort = load_state(root, slug)
    errors: list[dict] = []
    at = lambda rel: f".scratch/{slug}/{rel}"

    def err(rel: str, rule: str, detail: str) -> None:
        errors.append({"file": at(rel), "rule": rule, "detail": detail})

    items = effort_items(effort) if effort else []
    for item in items:
        rel, kind = item["path"], item["kind"]
        lines = read_lines(os.path.join(root, ".scratch", slug, rel))
        close = front_end(lines)
        keys: dict[str, str] = {}
        if close < 0:
            err(rel, "frontmatter", "no --- frontmatter block at the top of the file")
        else:
            last_key = ""
            for n in range(1, close):
                raw = bare(lines[n])
                if raw.strip() == "":
                    continue
                if raw.lstrip().startswith("#"):
                    err(rel, "no-comments", f"line {n + 1} is a comment: {raw.strip()}")
                    continue
                pair = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):(?:[ \t]+(.*))?$", raw)
                if pair:
                    last_key, value = pair.group(1), (pair.group(2) or "").strip()
                    if last_key in keys:
                        err(rel, "frontmatter", f"line {n + 1} repeats the key {last_key}")
                    keys[last_key] = value
                elif re.match(r"^\s*-\s+\S", raw) and last_key and keys[last_key] == "":
                    value = raw
                else:
                    err(rel, "frontmatter", f"line {n + 1} is not `key: value`: {raw.strip()}")
                    continue
                if has_comment(value):
                    err(rel, "no-comments", f"line {n + 1} ends in a comment: {raw.strip()}")
            title = keys.get("title")
            if title is None:
                err(rel, "title-quoted", "no title key")
            elif not re.fullmatch(r'"[^"]*"(\s+#.*)?', title):
                err(rel, "title-quoted", f"title is not one double-quoted string: {title}")

        legal = legal_statuses(kind, state)
        if item["status"] not in legal:
            shown = item["status"] or "(none)"
            err(rel, "status-legal", f"status {shown} is not legal on a {kind}; legal: {', '.join(legal)}")

    by_dir: dict[str, list[dict]] = {}
    for item in items:
        if item["kind"] in ("decision", "ticket"):
            by_dir.setdefault(item["path"].split("/")[0], []).append(item)

    for folder, group in sorted(by_dir.items()):
        numbers: dict[int, list[str]] = {}
        for item in group:
            name = item["path"].split("/", 1)[1]
            if not re.match(r"^\d{2,}-", name):
                err(item["path"], "filename-number", "the file name does not start with a zero-padded number and a hyphen (01-...)")
            if item["number"]:
                numbers.setdefault(int(item["number"]), []).append(name)
        for num, names in sorted(numbers.items()):
            if len(names) > 1:
                err(folder, "filename-number", f"number {num} is used by {', '.join(sorted(names))}")

        for item in group:
            own = int(item["number"]) if item["number"] else None
            for blocker in item["blocked_by"]:
                if not blocker.isdigit() or int(blocker) not in numbers:
                    err(item["path"], "blocker-missing", f"blocked-by {blocker} names no file in {folder}/")
                elif own is not None and int(blocker) >= own:
                    err(item["path"], "blocker-not-lower", f"blocked-by {blocker} is not lower than the ticket's own number {item['number']}")

        deliveries = [item for item in group if item["delivery"]]
        if len(deliveries) > 1:
            names = ", ".join(sorted(d["path"] for d in deliveries))
            err(folder, "delivery-count", f"{len(deliveries)} tickets carry delivery: true ({names}); want at most one")
        elif len(deliveries) == 1 and deliveries[0]["number"]:
            delivery = deliveries[0]
            own = int(delivery["number"])
            others = sorted(n for n in numbers if n != own)
            if others and own < others[-1]:
                err(delivery["path"], "delivery-not-last", f"the delivery ticket is {delivery['number']} but ticket {others[-1]} has a higher number")
            listed = {int(b) for b in delivery["blocked_by"] if b.isdigit()}
            missing = [str(n).zfill(len(delivery["number"])) for n in others if n not in listed]
            if missing:
                err(delivery["path"], "delivery-blockers", f"the delivery ticket's blocked-by leaves out {', '.join(missing)}")

    emit({"ok": not errors, "errors": errors})
    if errors:
        print(f"ticket.sh: {len(errors)} lint error(s) in .scratch/{slug}/", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    args = list(ARGV)
    root_arg = None
    while "--root" in args:
        i = args.index("--root")
        if i + 1 >= len(args):
            usage("--root needs a directory")
        root_arg = args[i + 1]
        del args[i:i + 2]
    if not args or args[0] in ("-h", "--help"):
        print(USAGE, file=sys.stderr)
        sys.exit(0 if args else 2)
    command, rest = args[0], args[1:]
    commands = {
        "frontier": cmd_frontier,
        "claim": cmd_claim,
        "release": cmd_release,
        "resolve": lambda r, a: cmd_finish(r, a, "--body-file", "Resolution"),
        "close": lambda r, a: cmd_finish(r, a, "--reason-file", "Closed"),
        "set-status": cmd_set_status,
        "lint": cmd_lint,
    }
    if command not in commands:
        usage(f"unknown subcommand: {command}")
    commands[command](find_root(root_arg), rest)


main()
PY
