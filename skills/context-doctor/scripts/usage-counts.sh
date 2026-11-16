#!/bin/bash
# Count what the user actually invoked across recent Claude Code sessions: skills (Skill tool
# calls), typed slash commands, MCP servers (mcp__<server>__* tool calls), and subagent types.
# Read-only over the logs. Session selection and log reading are retro's scripts, called by
# path, so there is one log walker in the collection.
#
# Usage: usage-counts.sh --out <dir> [--count N] [--project <dir>] [--exclude <session id>]...
#   --count N     parent sessions to scan, newest first, automated runs excluded (default 200)
#   --project dir also count, per name, the sessions started in this repo (its root, a
#                 subdirectory, or a worktree under it): "project_count", "project_sessions"
#   --exclude id  a session to leave out (the current one)
#
# Writes <dir>/usage.json and prints it:
#   {"sessions": n, "from": ts, "to": ts,
#    "project_sessions": n, "skills": {name: {"count", "sessions", "last", "project_count",
#    "project_sessions"}}, "slash": {...},
#    "mcp_servers": {...}, "agents": {...}}
# Counts span every Claude Code config dir and project on this machine. Names are as invoked:
# a plugin item is <plugin>:<name> (inventory.json usage_key). A skill typed as /name lands in
# "slash", not "skills": add both. A name absent from a map was never invoked in the window. Codex, Grok, and
# agy logs are not counted; their skills and tools have no structured invocation event here.

set -e

out=""; count=200; excludes=(); project=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out=$2; shift ;;
    --count) count=$2; shift ;;
    --project) project=$2; shift ;;
    --exclude) excludes+=(--exclude "$2"); shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$out" ] || { echo "--out <dir> is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

retro="$(cd "$(dirname "$0")/../../retro/scripts" && pwd)"
[ -f "$retro/select-sessions.sh" ] || { echo "retro's scripts not found beside this skill: $retro" >&2; exit 1; }
mkdir -p "$out/sessions"
# Claude Code names a session's log directory after its cwd, every non-alphanumeric character
# a "-"; a session in this repo has a directory name starting with the repo root's.
slug=""
if [ -n "$project" ]; then
  root=$(git -C "$project" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  case "$root" in */.git) root=${root%/.git} ;; "") root=$(cd "$project" && pwd -P) ;; esac
  slug=$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')
fi
events=$(mktemp); trap 'rm -f "$events"' EXIT

bash "$retro/select-sessions.sh" --out "$out/sessions" --count "$count" --harness claude ${excludes[@]+"${excludes[@]}"} > "$out/sessions/summary.json"

# One row per log: the parent and each child, all stamped with the parent's id and timestamp.
jq -r --arg slug "$slug" '. as $r | ($slug != "" and ($r.path | split("/") | .[-2] | startswith($slug))) as $in
  | ([$r.path] + ($r.children // []))[] | [., $r.id, ($r.timestamp // ""), $in] | @tsv' "$out/sessions/parents.jsonl" |
while IFS=$'\t' read -r log id ts inproj; do
  # A large --max-chars: an Agent call's subagent_type comes after its prompt, so a short cut
  # would drop it. Fields are matched by pattern because a cut input is no longer valid JSON.
  bash "$retro/extract-signal.sh" "$log" --max-chars 1000000 2>/dev/null |
    jq -c --arg id "$id" --arg ts "$ts" --argjson in "$inproj" '
      def field($k): (capture("\"" + $k + "\":\"(?<v>[^\"]+)\"")? | .v);
      if .kind == "tool_call" then
        (.text | capture("^(?<tool>[^ ]+) (?<input>[\\s\\S]*)$")? // empty) as $c
        | if $c.tool == "Skill" then ($c.input | field("skill") // empty | {type:"skills", name:.})
          elif ($c.tool == "Agent" or $c.tool == "Task") then {type:"agents", name:($c.input | field("subagent_type") // "general-purpose")}
          elif ($c.tool | startswith("mcp__")) then {type:"mcp_servers", name:($c.tool | split("__")[1])}
          else empty end
      elif .kind == "user" then
        (.text | capture("<command-name>/?(?<n>[^<]+)</command-name>")? // empty | {type:"slash", name:.n})
      else empty end
      | . + {id:$id, ts:$ts, in_project:$in}' >> "$events" || true
done

jq -s --slurpfile p "$out/sessions/parents.jsonl" --arg slug "$slug" '
  def tally($t): map(select(.type == $t)) | group_by(.name)
    | map({key: .[0].name, value: {count: length, sessions: (map(.id) | unique | length), last: (map(.ts) | max),
        project_count: (map(select(.in_project)) | length), project_sessions: (map(select(.in_project) | .id) | unique | length)}})
    | from_entries;
  {sessions: ($p | length), project_sessions: ($p | map(select(.path | split("/") | .[-2] | startswith($slug) and $slug != "")) | length), from: ($p | map(.timestamp // empty) | min), to: ($p | map(.timestamp // empty) | max),
   skills: tally("skills"), slash: tally("slash"), mcp_servers: tally("mcp_servers"), agents: tally("agents")}' "$events" > "$out/usage.json"
cat "$out/usage.json"
