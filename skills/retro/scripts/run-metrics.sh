#!/bin/bash
# Time and cost profile of one Claude Code session, read-only: span, waits on the user,
# parent and subagent token totals, and one row per subagent (type, description, start,
# minutes, tokens), so two runs of the same workflow can be compared.
# With --repo and --stack, also sizes each ticket of an implement-spec stack: for every
# `origin/<prefix>-stack-*` ref, the diff against its nearest ancestor among the other
# stack refs and `origin/<prefix>` (no ancestor: lines are null).
#
# Usage: run-metrics.sh <session .jsonl> [--repo DIR --stack PREFIX]
# Output: one JSON object on stdout. Times are UTC ISO strings; convert before showing.
#   wait_on_user_min: AskUserQuestion answer time plus gaps over 15 min that end in a
#   human message (a gap that ends in a task notification is the run waiting on agents).
# Claude Code only: subagents are read from <session dir>/subagents/*.meta.json.

set -e

f=${1:-}
[ -n "$f" ] || { echo "Usage: run-metrics.sh <session .jsonl> [--repo DIR --stack PREFIX]" >&2; exit 2; }
shift
repo=""; stack=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift ;;
    --stack) stack=$2; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -r "$f" ] || { echo "Unreadable: $f" >&2; exit 1; }
if [ -n "$stack" ] && [ -z "$repo" ]; then echo "--stack needs --repo" >&2; exit 2; fi

python3 -I - "$f" "$repo" "$stack" <<'PY'
import collections, datetime as dt, glob, json, os, re, subprocess, sys

path, repo, stack = sys.argv[1:4]

def ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))

def iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def load(p):
    rows = []
    with open(p) as fh:
        for line in fh:
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    return rows

def tokens(rows):
    t = collections.Counter()
    seen = set()
    for d in rows:
        if d.get("type") != "assistant":
            continue
        m = d.get("message") or {}
        if m.get("id") in seen:
            continue
        seen.add(m.get("id"))
        for k, v in (m.get("usage") or {}).items():
            if k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"):
                t[k] += v or 0
    return {"output": t["output_tokens"], "cache_write": t["cache_creation_input_tokens"],
            "cache_read": t["cache_read_input_tokens"], "input": t["input_tokens"]}

def text_of(content):
    if isinstance(content, str):
        return content
    if any(c.get("type") == "tool_result" for c in content):
        return ""
    return " ".join(c.get("text", "") for c in content if c.get("type") == "text")

def is_human(d):
    if d.get("type") != "user" or d.get("isMeta") or d.get("toolUseResult") is not None:
        return False
    t = text_of(d["message"].get("content", "")).strip()
    return bool(t) and not t.startswith(("<task-notification", "<system-reminder"))

rows = load(path)
timed = [d for d in rows if d.get("timestamp")]
if not timed:
    print("No timestamped entries", file=sys.stderr)
    sys.exit(1)
times = [ts(d["timestamp"]) for d in timed]
start, end = min(times), max(times)

wait = 0.0
for a, b in zip(timed, timed[1:]):
    gap = (ts(b["timestamp"]) - ts(a["timestamp"])).total_seconds()
    if gap > 900 and is_human(b):
        wait += gap
asks, pending, errors, tools = 0, {}, 0, collections.Counter()
for d in rows:
    if d.get("type") == "assistant":
        for c in d["message"].get("content", []):
            if c.get("type") == "tool_use":
                tools[c["name"]] += 1
                if c["name"] == "AskUserQuestion":
                    pending[c["id"]] = ts(d["timestamp"])
    elif d.get("type") == "user" and isinstance(d["message"].get("content"), list):
        for c in d["message"]["content"]:
            if c.get("type") != "tool_result":
                continue
            errors += bool(c.get("is_error"))
            if c.get("tool_use_id") in pending:
                asks += 1
                wait += (ts(d["timestamp"]) - pending.pop(c["tool_use_id"])).total_seconds()

subs = []
base = os.path.splitext(path)[0]
for meta in sorted(glob.glob(os.path.join(base, "subagents", "*.meta.json"))):
    with open(meta) as fh:
        m = json.load(fh)
    srows = load(meta[: -len(".meta.json")] + ".jsonl")
    st = [ts(d["timestamp"]) for d in srows if d.get("timestamp")]
    if not st:
        continue
    subs.append({"type": m.get("agentType", "?"), "description": m.get("description", ""),
                 "model": m.get("model"), "start": iso(min(st)),
                 "minutes": round((max(st) - min(st)).total_seconds() / 60, 1),
                 "turns": len({d["message"].get("id") for d in srows if d.get("type") == "assistant"}),
                 "tokens": tokens(srows)})
subs.sort(key=lambda s: s["start"])
by_type = {}
for s in subs:
    b = by_type.setdefault(s["type"], {"count": 0, "agent_minutes": 0.0, "output": 0, "cache_read": 0})
    b["count"] += 1
    b["agent_minutes"] = round(b["agent_minutes"] + s["minutes"], 1)
    b["output"] += s["tokens"]["output"]
    b["cache_read"] += s["tokens"]["cache_read"]

out = {"session": os.path.basename(base), "start": iso(start), "end": iso(end),
       "wall_min": round((end - start).total_seconds() / 60, 1),
       "wait_on_user_min": round(wait / 60, 1), "questions_answered": asks,
       "human_messages": sum(is_human(d) for d in rows), "tool_errors": errors,
       "parent_tools": dict(tools.most_common()), "parent_tokens": tokens(rows),
       "subagents_by_type": by_type, "subagents": subs}

if stack:
    def git(*a):
        r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)
        return r.returncode, r.stdout.strip()
    refs = [r for r in git("for-each-ref", "--format=%(refname:short)", f"refs/remotes/origin/{stack}-stack-*")[1].split("\n") if r]
    tickets = []
    for ref in refs:
        best, best_n = None, None
        for cand in [f"origin/{stack}"] + [r for r in refs if r != ref]:
            if git("merge-base", "--is-ancestor", cand, ref)[0] == 0:
                n = int(git("rev-list", "--count", f"{cand}..{ref}")[1])
                if best_n is None or n < best_n:
                    best, best_n = cand, n
        row = {"ref": ref, "ticket": ref.rsplit("-stack-", 1)[1], "parent": best,
               "commits": best_n, "files": None, "lines": None}
        if best:
            nums = git("diff", "--numstat", f"{best}..{ref}")[1]
            files = [l.split("\t") for l in nums.split("\n") if l]
            row["files"] = len(files)
            row["lines"] = sum(int(a) + int(b) for a, b, _ in files if a != "-")
        tickets.append(row)
    out["tickets"] = tickets

json.dump(out, sys.stdout, indent=1)
print()
PY
