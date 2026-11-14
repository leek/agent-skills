#!/bin/bash
# Scan .scratch/ efforts, research files, and unclassified items into one JSON object.
# Performs frontmatter/legacy status parsing, blocker/claim resolution, git tracked/date
# lookups, and commit-ancestry checks (merge-base, merged PRs, git cherry, commit subject).
#
# Usage: scratch-state.sh [--days N] [--root DIR] [--no-commits] [slug]
#   --days N      days of inactivity before an open effort counts as stale (default 30)
#   --root DIR    read DIR/.scratch/ instead of the git top level's (tests, ticket.sh)
#   --no-commits  skip the cited-commit checks: no `gh` call, no network; every ticket then
#                 reports "commits": [] (setup's ticket.sh reads the tracker this way)
#   slug          optional effort slug to scan only .scratch/<slug>/
#
# Stdout: JSON object {"root", "exists", "default_branch", "stale_days", "vocabulary",
#   "counts", "efforts", "unreadable_efforts", "research", "unclassified"}
#   "vocabulary" is {"closed": [..], "wontfix": [..], "roles": {<triage role>: <status string>}},
#   read from .agents/triage-labels.md. Each map, spec, decision, and ticket carries "status",
#   "claimed_by", "blocked_by", "open_blockers", "derived_status", "type", "delivery",
#   "deploy_gate", "last_change", and "last_change_ts" (epoch seconds: the last commit when
#   tracked, else the modification time).
#   An effort's "next" names the lowest-numbered ready ticket an agent may build; "next_why"
#   says how many open tickets it unblocks. "frontier" is a status view: every unblocked,
#   unclaimed ticket, those at a human-gate status (the repo's string for ready-for-human,
#   needs-info or needs-triage) included. "next" never names one of those as `/implement`
#   work: it reads "waiting on a human: <path> (<status>)", or "after deploy: /implement
#   <path>" for the delivery ticket. ticket.sh's `frontier` leaves them out.
# Stderr: status/error messages. Read-only.
#
# This file holds the tracker's one frontmatter reader. skills/setup/scripts/ticket.sh calls
# it for every read (autopilot's runner reads the tracker through ticket.sh too), and
# hooks/mods/scratch-scan.ts ports it: change them together.
set -e

usage="usage: scratch-state.sh [--days N] [--root DIR] [--no-commits] [slug]"
days=30
slug=""
root_dir=""
check_commits=1
while [ $# -gt 0 ]; do
  case "$1" in
    --days)
      [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
      days="$2"
      shift 2
      ;;
    --root)
      [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
      root_dir="$2"
      shift 2
      ;;
    --no-commits)
      check_commits=0
      shift
      ;;
    --help|-h)
      echo "$usage" >&2
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      [ -z "$slug" ] || { echo "unexpected argument: $1" >&2; exit 2; }
      slug="$1"
      shift
      ;;
  esac
done

# Resolve .scratch/ against the repository root, so a run from a subdirectory still finds it.
if [ -n "$root_dir" ]; then
  cd "$root_dir" 2>/dev/null || { echo "no such directory: $root_dir" >&2; exit 2; }
else
  top=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$top"
fi

python3 - "$days" "$slug" "$check_commits" <<'PY'
# Annotations stay unevaluated, so `dict | None` loads on the macOS system Python 3.9.
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

try:
    stale_days = int(sys.argv[1])
except ValueError:
    print(f"invalid --days value: {sys.argv[1]}", file=sys.stderr)
    sys.exit(2)
only_slug = sys.argv[2].strip().strip("/")
if only_slug.startswith(".scratch/"):
    only_slug = only_slug[len(".scratch/"):].strip("/")
CHECK_COMMITS = sys.argv[3] == "1"

root = Path(".scratch")
now_ts = datetime.now(timezone.utc).timestamp()
stale_sec = stale_days * 86400


def run_cmd(args: list[str]) -> tuple[int, str]:
    try:
        res = subprocess.run(args, text=True, capture_output=True)
        return res.returncode, res.stdout.strip()
    except OSError:
        return 1, ""


def detect_default_branch() -> str:
    rc, out = run_cmd(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
    if rc == 0 and out:
        return out.split("/", 1)[-1]
    for candidate in ("main", "master"):
        rc, _ = run_cmd(["git", "rev-parse", "--verify", "--quiet", candidate])
        if rc == 0:
            return candidate
    return "main"


TRIAGE_ROLES = ("needs-triage", "needs-info", "ready-for-agent", "ready-for-human", "wontfix")


def load_closed_vocabulary() -> tuple[set[str], set[str], dict[str, str]]:
    wontfix = {"wontfix", "declined", "duplicate"}
    closed = {"closed", "done", "resolved"} | wontfix
    # Each triage role's status string; a role the table does not list keeps its own name.
    roles = {role: role for role in TRIAGE_ROLES}
    for candidate in (Path(".agents/triage-labels.md"), Path("docs/agents/triage-labels.md")):
        if candidate.is_file():
            text = candidate.read_text(encoding="utf-8", errors="replace")
            # The setup table's rows: | `<role>` | `<status string>` | <meaning> |
            for m in re.finditer(r"^\|\s*`([a-z-]+)`\s*\|\s*`([^`]+)`", text, re.M | re.I):
                role = m.group(1).lower()
                label = m.group(2).strip().lower()
                if role in roles:
                    roles[role] = label
                if role == "wontfix":
                    closed.add(label)
                    wontfix.add(label)
            break
    return closed, wontfix, roles


CLOSED_SET, WONTFIX_SET, ROLE_STRINGS = load_closed_vocabulary()
# The statuses that wait on a person: ticket.sh refuses a claim on them, and autopilot stops.
HUMAN_STATUSES = {ROLE_STRINGS[role] for role in ("ready-for-human", "needs-info", "needs-triage")}
DEFAULT_BRANCH = detect_default_branch()
HAS_GH = shutil.which("gh") is not None

rc_tracked, tracked_out = run_cmd(["git", "ls-files", ".scratch"])
TRACKED_FILES = set(tracked_out.splitlines()) if rc_tracked == 0 and tracked_out else set()


def file_date_and_ts(path: Path) -> tuple[str, float, bool]:
    rel = path.as_posix()
    tracked = rel in TRACKED_FILES
    if tracked:
        rc, out = run_cmd(["git", "log", "-1", "--format=%ct %cs", "--", rel])
        if rc == 0 and " " in out:
            ts_s, date_s = out.split(" ", 1)
            try:
                return date_s.strip(), float(ts_s), True
            except ValueError:
                pass
    try:
        mtime = path.stat().st_mtime
    except OSError:
        mtime = now_ts
    date_s = datetime.fromtimestamp(mtime, tz=timezone.utc).strftime("%Y-%m-%d")
    return date_s, mtime, tracked


def extract_section(body: str, heading_pattern: str) -> str:
    m = re.search(rf"^##\s+(?:{heading_pattern})\s*$([\s\S]*?)(?=^##\s+|\Z)", body, re.M | re.I)
    return m.group(1).strip() if m else ""


def one_line(text: str) -> str:
    for line in text.splitlines():
        cleaned = line.strip()
        if cleaned and not cleaned.startswith("<!--"):
            return re.sub(r"\s+", " ", cleaned)
    return ""


def clean_value(raw: str) -> str:
    """A frontmatter value without its quotes or an unquoted trailing ` # comment`."""
    val = raw.strip()
    if val[:1] in ("\"", "'"):
        end = val.find(val[0], 1)
        if end > 0:
            rest = val[end + 1:].strip()
            if rest == "" or rest.startswith("#"):
                return val[1:end]
    m = re.search(r"(?:^|\s)#", val)
    if m is not None:
        val = val[:m.start()]
    return val.strip().strip("\"'")


def number_key(number: str) -> tuple[float, str]:
    """Lowest number first: 9 before 10, and a file with no number last."""
    return (float(int(number)) if number.isdigit() else float("inf"), number)


def parse_list(front: str, key: str) -> list[str]:
    inline = re.search(rf"^{re.escape(key)}:[ \t]*\[([^\]]*)\]", front, re.M)
    if inline is not None:
        return [
            s.strip().strip("\"'")
            for s in inline.group(1).split(",")
            if s.strip().strip("\"'")
        ]
    block = re.search(rf"^{re.escape(key)}:[ \t]*\r?\n((?:[ \t]*-.*\r?\n?)+)", front, re.M)
    if block is not None:
        return [
            clean_value(re.sub(r"^\s*-\s*", "", line))
            for line in block.group(1).splitlines()
            if clean_value(re.sub(r"^\s*-\s*", "", line))
        ]
    bare = re.search(rf"^{re.escape(key)}:[ \t]*(\S.*)$", front, re.M)
    if bare is not None:
        val = clean_value(bare.group(1))
        if val.lower() in ("none", "null", "~", "[]"):
            return []
        return [s.strip().strip("\"'") for s in val.split(",") if s.strip().strip("\"'")]
    return []


def normalize_blocker_id(token: str) -> str:
    m = re.search(r"(\d+)", token)
    return m.group(1) if m else token.strip()


COMMIT_CACHE: dict[str, dict] = {}


def check_commit(sha: str) -> dict:
    if sha in COMMIT_CACHE:
        return COMMIT_CACHE[sha]
    rc_anc, _ = run_cmd(["git", "merge-base", "--is-ancestor", sha, DEFAULT_BRANCH])
    if rc_anc == 0:
        res = {"sha": sha, "on_default_branch": True, "via": "ancestor"}
        COMMIT_CACHE[sha] = res
        return res
    if HAS_GH:
        rc_pr, pr_out = run_cmd([
            "gh", "api", f"repos/{{owner}}/{{repo}}/commits/{sha}/pulls",
            "--jq", ".[] | select(.merged_at) | .number",
        ])
        if rc_pr == 0 and pr_out.strip():
            res = {"sha": sha, "on_default_branch": True, "via": "pr"}
            COMMIT_CACHE[sha] = res
            return res
    rc_ch, ch_out = run_cmd(["git", "cherry", DEFAULT_BRANCH, sha, f"{sha}~1"])
    if rc_ch == 0 and any(line.startswith("- ") for line in ch_out.splitlines()):
        res = {"sha": sha, "on_default_branch": True, "via": "cherry"}
        COMMIT_CACHE[sha] = res
        return res
    rc_subj, subj = run_cmd(["git", "log", "-1", "--format=%s", sha])
    if rc_subj == 0 and subj:
        rc_match, match_out = run_cmd([
            "git", "log", DEFAULT_BRANCH, "--fixed-strings", f"--grep={subj}", "-1", "--format=%h",
        ])
        if rc_match == 0 and match_out:
            res = {"sha": sha, "on_default_branch": True, "via": "subject"}
            COMMIT_CACHE[sha] = res
            return res
    res = {"sha": sha, "on_default_branch": False, "via": "missing"}
    COMMIT_CACHE[sha] = res
    return res


def extract_commits(status_raw: str, body: str) -> list[dict]:
    res_sec = extract_section(body, "Resolution|Closed")
    com_sec = extract_section(body, "Comments")
    haystack = "\n".join([status_raw, res_sec, com_sec])
    seen: list[str] = []
    for m in re.finditer(r"\b([0-9a-f]{7,40})\b", haystack):
        cand = m.group(1)
        if cand in seen:
            continue
        # A real abbreviated SHA mixes letters and digits; an all-letter word ("defaced") or
        # an all-digit number (a CI run id) only counts when it resolves to a commit.
        if cand.isdigit() or not any(c.isdigit() for c in cand):
            rc, _ = run_cmd(["git", "rev-parse", "--verify", "--quiet", f"{cand}^{{commit}}"])
            if rc != 0:
                continue
        seen.append(cand)
    return [check_commit(sha) for sha in seen]


def parse_md(full_path: Path, rel_in_effort: str, kind: str) -> dict:
    text = full_path.read_text(encoding="utf-8", errors="replace")
    name = full_path.name
    number = ""
    if kind in ("decision", "ticket"):
        m_num = re.match(r"^(\d+)", name)
        number = m_num.group(1) if m_num else ""

    m_fm = re.match(r"^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$", text)
    front = m_fm.group(1) if m_fm else ""
    body = m_fm.group(2) if m_fm else text

    def field(key: str) -> str:
        m = re.search(rf"^{re.escape(key)}:[ \t]*(.*)$", front, re.M)
        return clean_value(m.group(1)) if m else ""

    status_raw = field("status")
    if not status_raw:
        head = "\n".join(text.splitlines()[:30])
        m_st = re.search(r"^\*\*Status:\*\*\s*(.+)$", head, re.M) or re.search(r"^Status:\s*(.+)$", head, re.M)
        status_raw = m_st.group(1).strip() if m_st else ""

    tokens = status_raw.strip().replace("`", "").replace("*", "").split()
    status = tokens[0].lower() if tokens else ""

    title = field("title")
    if not title:
        m_h1 = re.search(r"^#\s+(.+)$", body, re.M)
        title = m_h1.group(1).strip() if m_h1 else name.removesuffix(".md")

    claimed_by = field("claimed-by")
    if not claimed_by:
        # The value sits on the line itself: an emptied `**Claimed by:**` names nobody.
        m_cl = re.search(r"^(?:\*\*Claimed by:\*\*|Claimed by:)[ \t]*(\S.*)$", body, re.M | re.I)
        if m_cl:
            val = m_cl.group(1).strip()
            if val.lower() not in ("none", "null", "-"):
                claimed_by = val

    blocked_by = [normalize_blocker_id(x) for x in parse_list(front, "blocked-by")]
    if not blocked_by:
        m_bl = re.search(r"^(?:\*\*Blocked by:\*\*|Blocked by:)\s*(.+)$", body, re.M | re.I)
        if m_bl:
            raw_bl = m_bl.group(1).strip()
            if raw_bl.lower() not in ("none", "null", "-"):
                blocked_by = [normalize_blocker_id(x) for x in re.findall(r"\b\d+\b", raw_bl)]

    date_s, ts, tracked = file_date_and_ts(full_path)
    item: dict = {
        "path": rel_in_effort,
        "full_path": full_path.as_posix(),
        "kind": kind,
        "number": number,
        "title": title,
        "status": status,
        "claimed_by": claimed_by,
        "blocked_by": blocked_by,
        "type": field("type").lower(),
        "delivery": field("delivery").lower() == "true",
        "deploy_gate": field("deploy-gate").lower() in ("true", "yes"),
        "last_change": date_s,
        "last_change_ts": int(ts),
        "mtime_ts": ts,
        "tracked": tracked,
    }

    if kind == "map":
        item["destination"] = one_line(extract_section(body, "Destination"))
    elif kind == "spec":
        item["problem"] = one_line(extract_section(body, "Problem Statement|Problem"))
        oq_sec = extract_section(body, "Open Questions")
        oq_lines = [
            ln.strip()
            for ln in oq_sec.splitlines()
            if ln.strip() and not re.fullmatch(r"[-*]*\s*(?:none\.?|n/a)\s*", ln.strip(), re.I)
        ]
        item["open_questions"] = len(oq_lines)
    elif kind == "decision":
        item["resolution"] = one_line(extract_section(body, "Resolution|Closed"))
    elif kind == "ticket":
        commits = extract_commits(status_raw, body) if CHECK_COMMITS else []
        item["commits"] = commits
        item["missing_commits"] = [c["sha"] for c in commits if not c["on_default_branch"]]

    return item


def is_closed(item: dict) -> bool:
    return item["status"] in CLOSED_SET


def analyze_effort(slug_name: str, effort_dir: Path) -> dict | None:
    ticket_dirs = {"decisions": "decision", "tickets": "ticket", "issues": "ticket"}
    found: list[tuple[Path, str, str]] = []
    for entry in sorted(effort_dir.iterdir(), key=lambda p: p.name):
        if entry.name.startswith("."):
            continue
        if entry.is_file() and entry.name.endswith(".md"):
            kind = "map" if entry.name == "map.md" else "spec" if entry.name == "spec.md" else "request"
            found.append((entry, entry.name, kind))
        elif entry.is_dir() and entry.name in ticket_dirs:
            kind = ticket_dirs[entry.name]
            for inner in sorted(entry.iterdir(), key=lambda p: p.name):
                if inner.is_file() and inner.name.endswith(".md") and not inner.name.startswith("."):
                    found.append((inner, f"{entry.name}/{inner.name}", kind))

    if not found:
        return None

    files: list[dict] = []
    for full_p, rel_p, kind in found:
        parsed = parse_md(full_p, rel_p, kind)
        if kind == "request" and parsed["status"] == "":
            continue
        files.append(parsed)

    if not files:
        return {
            "slug": slug_name,
            "path": effort_dir.as_posix(),
            "unreadable_only": True,
        }

    # Resolve open blockers and derived_status for decisions and tickets
    for f in files:
        if f["status"] == "":
            f["derived_status"] = "unreadable"
            f["open_blockers"] = []
            f["wontfix"] = False
            continue
        f["wontfix"] = f["status"] in WONTFIX_SET
        if is_closed(f):
            f["derived_status"] = "closed"
            f["open_blockers"] = []
            continue
        open_blockers: list[str] = []
        if f["kind"] in ("decision", "ticket"):
            width = len(f["number"]) or 2
            for b in f["blocked_by"]:
                padded = b.zfill(width) if b.isdigit() else b
                target = next(
                    (x for x in files if x["kind"] == f["kind"] and (x["number"] == padded or x["number"] == b)),
                    None,
                )
                if target is None or not is_closed(target):
                    open_blockers.append(padded)
        f["open_blockers"] = open_blockers
        if f["claimed_by"] or f["status"] == "in-progress":
            f["derived_status"] = "in progress"
        elif open_blockers:
            f["derived_status"] = "blocked"
        else:
            f["derived_status"] = "ready"

    # Frontier of ready decisions/tickets
    ready_items = [
        f for f in files
        if f["kind"] in ("decision", "ticket") and f["derived_status"] == "ready"
    ]
    ready_items.sort(key=lambda x: number_key(x["number"]))
    frontier = [f["path"] for f in ready_items]

    # Check contradictions / mismatch
    mismatch = None
    unread = next((f for f in files if f["status"] == ""), None)
    map_f = next((f for f in files if f["kind"] == "map"), None)
    spec_f = next((f for f in files if f["kind"] == "spec"), None)
    decisions = [f for f in files if f["kind"] == "decision"]
    tickets = [f for f in files if f["kind"] == "ticket"]
    requests = [f for f in files if f["kind"] == "request"]

    # A spec built through tickets is complete when every ticket is closed: nothing writes
    # `closed` onto it, so its own status never keeps the effort open. A spec with no tickets
    # was implemented directly and needs its own closed status.
    spec_complete = spec_f is not None and (
        is_closed(spec_f) or (bool(tickets) and all(is_closed(t) for t in tickets))
    )
    if spec_f is not None:
        spec_f["complete"] = spec_complete

    if unread is not None:
        mismatch = f"no readable status: {unread['path']}"
    elif map_f and not is_closed(map_f) and spec_f is not None:
        mismatch = "map still open though spec.md exists"
    else:
        for t in tickets:
            if is_closed(t) and t.get("missing_commits"):
                sha = t["missing_commits"][0]
                mismatch = f"closed ticket {t['path']} cites missing commit {sha}"
                break

    last_ts = max(f["mtime_ts"] for f in files)
    last_date = max(files, key=lambda f: f["mtime_ts"])["last_change"]
    open_files = [f for f in files if not is_closed(f) and not (f is spec_f and spec_complete)]

    if mismatch is not None:
        state = "mismatched"
        is_stale = False
    elif not open_files:
        state = "done"
        is_stale = False
    else:
        state = "open"
        is_stale = (now_ts - last_ts) > stale_sec

    # Compute how many open items each ticket/decision unblocks
    unblock_counts: dict[str, int] = {}
    for f in tickets:
        num = f["number"]
        unblock_counts[num] = sum(1 for other in tickets if not is_closed(other) and num in other.get("open_blockers", []))

    at = lambda p: f".scratch/{slug_name}/{p}"
    also: list[str] = []
    if state == "mismatched":
        next_cmd = mismatch
        next_why = "settle the contradiction before removing or advancing"
    elif state == "done":
        next_cmd = "/scratch-cleanup"
        next_why = "nothing is left open and cited commits are on the default branch"
    else:
        ready_decisions = sorted(
            (d for d in decisions if d["derived_status"] == "ready"), key=lambda d: number_key(d["number"])
        )
        ready_tickets = [t for t in tickets if t["derived_status"] == "ready"]
        waits_on_deploy = lambda t: t["delivery"] and t["status"] == ROLE_STRINGS["ready-for-human"]
        buildable_tickets = [t for t in ready_tickets if t["status"] not in HUMAN_STATUSES]
        delivery_waiting = [t for t in ready_tickets if waits_on_deploy(t)]
        human_waiting = sorted(
            (t for t in ready_tickets if t["status"] in HUMAN_STATUSES and not waits_on_deploy(t)),
            key=lambda t: number_key(t["number"]),
        )

        if ready_decisions:
            pick = ready_decisions[0]
            # An open map's decisions are worked through wayfinder, which picks the frontier ticket.
            if map_f and not is_closed(map_f):
                next_cmd = f"/wayfinder {at(map_f['path'])}"
            else:
                next_cmd = f"/grill-me {at(pick['path'])}"
            next_why = f"lowest-numbered ready decision ({pick['number']})"
            if len(ready_decisions) >= 2 and map_f:
                also.append(f"/wayfinder {at(map_f['path'])} all")
                also.append("other ready decisions: " + ", ".join(d["number"] for d in ready_decisions[1:]))
        elif map_f and not is_closed(map_f) and not decisions:
            next_cmd = f"/wayfinder {at(map_f['path'])}"
            next_why = "map has no decision tickets yet"
        elif map_f and not is_closed(map_f) and decisions and all(is_closed(d) for d in decisions) and not spec_f:
            next_cmd = f"/to-spec {at(map_f['path'])}"
            next_why = "every decision is closed and no spec exists yet"
        elif spec_f and not is_closed(spec_f) and spec_f.get("open_questions", 0) > 0 and not any(is_closed(t) or t["derived_status"] == "in progress" for t in tickets):
            next_cmd = f"/grill-me {at(spec_f['path'])}"
            next_why = f"settle {spec_f['open_questions']} open question(s) in spec.md before building"
        elif spec_f and not is_closed(spec_f) and not tickets:
            next_cmd = f"/to-tickets {at(spec_f['path'])}"
            next_why = "spec has no build tickets yet"
        elif buildable_tickets:
            # Lowest number first, the tracker's Frontier rule; the unblock count only informs.
            buildable_tickets.sort(key=lambda t: number_key(t["number"]))
            pick = buildable_tickets[0]
            unblocks = unblock_counts.get(pick["number"], 0)
            next_cmd = f"/implement {at(pick['path'])}"
            next_why = f"lowest-numbered ready ticket ({pick['number']})" + (f", unblocks {unblocks}" if unblocks > 0 else "")
            if len(buildable_tickets) >= 2 and spec_f:
                also.append(f"/implement-spec {at(spec_f['path'])}")
                also.append("other ready tickets: " + ", ".join(t["number"] for t in buildable_tickets[1:]))
        elif delivery_waiting:
            pick = delivery_waiting[0]
            next_cmd = f"after deploy: /implement {at(pick['path'])}"
            next_why = "only the delivery ticket remains at ready-for-human"
        elif human_waiting:
            pick = human_waiting[0]
            next_cmd = f"waiting on a human: {at(pick['path'])} ({pick['status']})"
            next_why = "every unblocked ticket is at a human-gate status, which no agent claims"
        elif any(not is_closed(r) for r in requests):
            next_cmd = "/triage"
            next_why = "open triage request awaiting categorisation"
        else:
            claimed = [f"{f['number'] or f['path']} by {f['claimed_by']}" for f in open_files if f["claimed_by"]]
            if claimed:
                next_cmd = f"waiting on {', '.join(claimed)}"
                next_why = "all unblocked work is currently claimed"
            else:
                most_blocking = max(unblock_counts.items(), key=lambda kv: kv[1], default=("", 0))
                next_cmd = "everything open is blocked"
                next_why = f"clear blocker {most_blocking[0]}" if most_blocking[1] > 0 else "check dependency chain"

    def clean_item(f: dict | None) -> dict | None:
        if f is None:
            return None
        out = {k: v for k, v in f.items() if k not in ("mtime_ts", "full_path")}
        return out

    all_paths_in_dir = [p for p in effort_dir.rglob("*") if p.is_file()]
    untracked_in_dir = [p.as_posix() for p in all_paths_in_dir if p.as_posix() not in TRACKED_FILES]
    any_tracked = any(p.as_posix() in TRACKED_FILES for p in all_paths_in_dir)

    return {
        "slug": slug_name,
        "path": effort_dir.as_posix(),
        "state": state,
        "stale": is_stale,
        "last_change": last_date,
        "last_ts": last_ts,
        "tracked": any_tracked,
        "untracked_files": untracked_in_dir,
        "mismatch": mismatch,
        "map": clean_item(map_f),
        "spec": clean_item(spec_f),
        "decisions": [clean_item(d) for d in decisions],
        "tickets": [clean_item(t) for t in tickets],
        "requests": [clean_item(r) for r in requests],
        "frontier": frontier,
        "next": next_cmd,
        "next_why": next_why,
        "also": also[:2],
    }


VOCABULARY = {"closed": sorted(CLOSED_SET), "wontfix": sorted(WONTFIX_SET), "roles": ROLE_STRINGS}

if not root.is_dir():
    print(json.dumps({
        "root": ".scratch",
        "exists": False,
        "default_branch": DEFAULT_BRANCH,
        "stale_days": stale_days,
        "vocabulary": VOCABULARY,
        "counts": {"open": 0, "stale": 0, "mismatched": 0, "done": 0},
        "efforts": [],
        "unreadable_efforts": [],
        "research": [],
        "unclassified": [],
    }, indent=2))
    sys.exit(0)

efforts: list[dict] = []
unreadable_efforts: list[str] = []
research: list[dict] = []
unclassified: list[dict] = []

for entry in sorted(root.iterdir(), key=lambda p: p.name):
    if only_slug and entry.name != only_slug:
        continue
    if entry.name == ".DS_Store":
        if not only_slug:
            unclassified.append({"path": entry.as_posix(), "tracked": False, "last_change": "", "junk": True})
        continue
    if entry.name.startswith("."):
        continue
    if entry.is_dir() and entry.name == "research":
        if not only_slug:
            for rfile in sorted(entry.rglob("*")):
                if rfile.is_file():
                    if rfile.name == ".DS_Store":
                        unclassified.append({"path": rfile.as_posix(), "tracked": False, "last_change": "", "junk": True})
                    else:
                        d_s, _, trk = file_date_and_ts(rfile)
                        research.append({"path": rfile.as_posix(), "tracked": trk, "last_change": d_s})
        continue
    if entry.is_dir():
        for ds in entry.rglob(".DS_Store"):
            unclassified.append({"path": ds.as_posix(), "tracked": False, "last_change": "", "junk": True})
        res = analyze_effort(entry.name, entry)
        if res is None:
            if not only_slug:
                for sub in sorted(entry.rglob("*")):
                    if sub.is_file() and sub.name != ".DS_Store":
                        d_s, _, trk = file_date_and_ts(sub)
                        unclassified.append({"path": sub.as_posix(), "tracked": trk, "last_change": d_s, "junk": False})
        elif res.get("unreadable_only"):
            unreadable_efforts.append(res["path"])
        else:
            efforts.append(res)
    elif entry.is_file() and not only_slug:
        d_s, _, trk = file_date_and_ts(entry)
        text = entry.read_text(encoding="utf-8", errors="replace") if entry.name.endswith(".md") else ""
        if re.search(r"(?:^##\s+|\*\*)What this unblocks", text, re.M | re.I):
            research.append({"path": entry.as_posix(), "tracked": trk, "last_change": d_s})
        else:
            unclassified.append({"path": entry.as_posix(), "tracked": trk, "last_change": d_s, "junk": False})


def effort_rank(e: dict) -> int:
    if e["state"] == "open":
        if e["stale"]:
            return 2
        return 0 if e["frontier"] else 1
    if e["state"] == "mismatched":
        return 3
    return 4


efforts.sort(key=lambda e: (effort_rank(e), -e["last_ts"]))
for e in efforts:
    e.pop("last_ts", None)

counts = {
    "open": sum(1 for e in efforts if e["state"] == "open"),
    "stale": sum(1 for e in efforts if e["stale"]),
    "mismatched": sum(1 for e in efforts if e["state"] == "mismatched"),
    "done": sum(1 for e in efforts if e["state"] == "done"),
}

print(json.dumps({
    "root": ".scratch",
    "exists": True,
    "default_branch": DEFAULT_BRANCH,
    "stale_days": stale_days,
    "vocabulary": VOCABULARY,
    "counts": counts,
    "efforts": efforts,
    "unreadable_efforts": unreadable_efforts,
    "research": research,
    "unclassified": unclassified,
}, indent=2))
PY
