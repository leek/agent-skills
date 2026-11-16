#!/bin/bash
# Offline test for usage-counts.sh against fixture Claude Code sessions under a fixture HOME
# (retro's selector reads ~/.claude/projects): Skill, Agent, MCP, and slash-command events,
# and the per-project split.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; unset CLAUDE_CONFIG_DIR
proj="$tmp/work/app"; mkdir -p "$proj"
inside="$HOME/.claude/projects/$(printf '%s' "$proj" | sed 's/[^A-Za-z0-9]/-/g')"
outside="$HOME/.claude/projects/-elsewhere"
mkdir -p "$inside" "$outside"
fail() { echo "FAIL: $*" >&2; exit 1; }

long=$(printf 'x%.0s' $(seq 1 900))
{
  echo '{"type":"user","timestamp":"2026-11-01T10:00:00Z","message":{"role":"user","content":"Please audit the context."}}'
  echo '{"type":"assistant","timestamp":"2026-11-01T10:00:05Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"acme:lint"}}]}}'
  echo "{\"type\":\"assistant\",\"timestamp\":\"2026-11-01T10:00:06Z\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"name\":\"Agent\",\"input\":{\"description\":\"d\",\"prompt\":\"$long\",\"subagent_type\":\"acme:reviewer\"}}]}}"
  echo '{"type":"assistant","timestamp":"2026-11-01T10:00:07Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"mcp__posthog__query","input":{"q":"x"}}]}}'
  echo '{"type":"user","timestamp":"2026-11-01T10:00:08Z","message":{"role":"user","content":"<command-name>/acme:audit</command-name><command-args></command-args>"}}'
  echo '{"type":"assistant","timestamp":"2026-11-01T10:00:09Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"acme:lint"}}]}}'
} > "$inside/11111111-2222-3333-4444-555555555555.jsonl"
{
  echo '{"type":"user","timestamp":"2026-11-02T10:00:00Z","message":{"role":"user","content":"Fix the build."}}'
  echo '{"type":"assistant","timestamp":"2026-11-02T10:00:05Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"acme:lint"}}]}}'
} > "$outside/66666666-7777-8888-9999-000000000000.jsonl"

u=$(bash "$here/usage-counts.sh" --out "$tmp/out" --count 5 --project "$proj" 2>/dev/null)
[ "$(echo "$u" | jq .sessions)" = 2 ] || fail "sessions: $u"
[ "$(echo "$u" | jq .project_sessions)" = 1 ] || fail "project sessions: $u"
[ "$(echo "$u" | jq '.skills["acme:lint"].count')" = 3 ] || fail "skill count: $u"
[ "$(echo "$u" | jq '.skills["acme:lint"].sessions')" = 2 ] || fail "skill sessions: $u"
[ "$(echo "$u" | jq '.skills["acme:lint"].project_count')" = 2 ] || fail "skill project count: $u"
[ "$(echo "$u" | jq '.agents["acme:reviewer"].count')" = 1 ] || fail "agent behind a long prompt: $u"
[ "$(echo "$u" | jq '.mcp_servers.posthog.count')" = 1 ] || fail "mcp: $u"
[ "$(echo "$u" | jq '.slash["acme:audit"].count')" = 1 ] || fail "slash: $u"

echo "test-usage-counts: ok"
