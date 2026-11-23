#!/bin/bash
# Offline test for run-metrics.sh on a synthetic session and a local stack of refs.
# Usage: test-run-metrics.sh    (prints one "ok <case>" line per case; exits 1 on the first failure)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/run-metrics.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL $1" >&2; [ ! -f "$T/err" ] || sed 's/^/  stderr: /' "$T/err" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }

s="$T/sess.jsonl"
mkdir -p "$T/sess/subagents"
{
  echo '{"type":"user","timestamp":"2026-01-01T10:00:00Z","message":{"role":"user","content":"build it"}}'
  echo '{"type":"assistant","timestamp":"2026-01-01T10:01:00Z","message":{"id":"m1","usage":{"output_tokens":10,"cache_read_input_tokens":100},"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}'
  echo '{"type":"user","timestamp":"2026-01-01T10:06:00Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"q1","content":"yes"}]}}'
  echo '{"type":"assistant","timestamp":"2026-01-01T10:07:00Z","message":{"id":"m2","usage":{"output_tokens":5},"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{}}]}}'
  echo '{"type":"user","timestamp":"2026-01-01T10:08:00Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":true,"content":"boom"}]}}'
  echo '{"type":"user","timestamp":"2026-01-01T10:40:00Z","message":{"role":"user","content":"<task-notification>agent done</task-notification>"}}'
  echo '{"type":"user","timestamp":"2026-01-01T11:00:00Z","message":{"role":"user","content":"ship it"}}'
} > "$s"
echo '{"agentType":"leek-skills:implementer","description":"ticket 01","model":"m"}' > "$T/sess/subagents/agent-a.meta.json"
{
  echo '{"type":"user","timestamp":"2026-01-01T10:10:00Z","message":{"role":"user","content":"brief"}}'
  echo '{"type":"assistant","timestamp":"2026-01-01T10:30:00Z","message":{"id":"s1","usage":{"output_tokens":7,"cache_read_input_tokens":50},"content":[]}}'
} > "$T/sess/subagents/agent-a.jsonl"

out=$(bash "$script" "$s" 2>"$T/err") || fail "session: exit $?"
eq "wall" "$(jq -r .wall_min <<<"$out")" 60.0
eq "questions" "$(jq -r .questions_answered <<<"$out")" 1
# 5m question + the 20m gap ending in a human message; the 32m gap ends in a notification
eq "wait" "$(jq -r .wait_on_user_min <<<"$out")" 25.0
eq "humans" "$(jq -r .human_messages <<<"$out")" 2
eq "errors" "$(jq -r .tool_errors <<<"$out")" 1
eq "parent out" "$(jq -r .parent_tokens.output <<<"$out")" 15
echo "ok session timing, waits, errors and tokens"

eq "sub minutes" "$(jq -r '.subagents_by_type["leek-skills:implementer"].agent_minutes' <<<"$out")" 20.0
eq "sub out" "$(jq -r '.subagents[0].tokens.output' <<<"$out")" 7
eq "no tickets" "$(jq -r 'has("tickets")' <<<"$out")" false
echo "ok subagent rows"

r="$T/repo"
git init -q -b main "$r"
git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$r" update-ref refs/remotes/origin/feat HEAD
printf 'a\nb\n' > "$r/one.txt"
git -C "$r" add one.txt
git -C "$r" -c user.email=t@t -c user.name=t commit -q -m one
git -C "$r" update-ref refs/remotes/origin/feat-stack-01 HEAD
printf 'c\n' > "$r/two.txt"
git -C "$r" add two.txt
git -C "$r" -c user.email=t@t -c user.name=t commit -q -m two
git -C "$r" update-ref refs/remotes/origin/feat-stack-02 HEAD

out=$(bash "$script" "$s" --repo "$r" --stack feat 2>"$T/err") || fail "stack: exit $?"
eq "ticket count" "$(jq -r '.tickets|length' <<<"$out")" 2
eq "01 parent" "$(jq -r '.tickets[]|select(.ticket=="01").parent' <<<"$out")" origin/feat
eq "01 lines" "$(jq -r '.tickets[]|select(.ticket=="01").lines' <<<"$out")" 2
eq "02 parent" "$(jq -r '.tickets[]|select(.ticket=="02").parent' <<<"$out")" origin/feat-stack-01
eq "02 lines" "$(jq -r '.tickets[]|select(.ticket=="02").lines' <<<"$out")" 1
echo "ok stack tickets sized against their nearest ancestor"

bash "$script" "$s" --stack feat >/dev/null 2>"$T/err" && fail "stack without repo should fail"
echo "ok --stack needs --repo"
