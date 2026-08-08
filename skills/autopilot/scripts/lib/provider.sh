#!/bin/bash
# Claude Code and Codex adapters behind one runner interface.

set -e

configure_provider() {
  case "$PROVIDER" in
    claude)
      PROVIDER_BIN="${AUTOPILOT_CLAUDE_BIN:-claude}"
      PROVIDER_BIN_ENV_NAME="AUTOPILOT_CLAUDE_BIN"
      PROVIDER_EVENT_FORMATTER="format_claude_event"
      PROVIDER_EXECUTOR="run_claude_provider"
      PROVIDER_RESULT_EXTRACTOR="extract_claude_result"
      ;;
    codex)
      PROVIDER_BIN="${AUTOPILOT_CODEX_BIN:-codex}"
      PROVIDER_BIN_ENV_NAME="AUTOPILOT_CODEX_BIN"
      PROVIDER_EVENT_FORMATTER="format_codex_event"
      PROVIDER_EXECUTOR="run_codex_provider"
      PROVIDER_RESULT_EXTRACTOR="extract_codex_result"
      ;;
    *)
      runner_failure "--provider must be claude or codex"
      ;;
  esac
}

format_claude_event() {
  jq -r '
    if .type == "assistant" then
      (.parent_tool_use_id // "") as $parent_tool_use_id |
      .message.content[]? |
      if .type == "text" and ((.text // "") | test("^\\s*\\{") | not) and ($parent_tool_use_id == "") then
        ["milestone", .text] | @tsv
      elif .type == "tool_use" then
        ["tool", ("tool " + (.name // "unknown") + " started")] | @tsv
      else empty end
    elif .type == "system" and ((.subtype // "") | startswith("hook_")) then
      ["event", ("hook " + (.subtype // "event"))] | @tsv
    elif .type == "result" then
      ["event", "worker result received"] | @tsv
    else empty end
  ' 2>/dev/null
}

format_codex_event() {
  jq -r '
    if .type == "item.started" then
      if .item.type == "command_execution" then ["tool", "command started"] | @tsv
      elif .item.type == "mcp_tool_call" then ["tool", ("MCP tool " + (.item.tool // .item.name // "unknown") + " started")] | @tsv
      elif .item.type == "file_change" then ["event", "file change started"] | @tsv
      else empty end
    elif .type == "item.completed" then
      if .item.type == "agent_message" and ((.item.text // "") | test("^\\s*\\{") | not) then
        ["milestone", .item.text] | @tsv
      elif .item.type == "command_execution" then
        ["tool", ("command finished" + (if .item.exit_code == null then "" else " (exit " + (.item.exit_code | tostring) + ")" end))] | @tsv
      elif .item.type == "mcp_tool_call" then ["tool", "MCP tool finished"] | @tsv
      elif .item.type == "file_change" then ["event", "file change completed"] | @tsv
      else empty end
    elif .type == "turn.failed" then
      ["milestone", ("worker turn failed: " + (.error.message // "unknown error"))] | @tsv
    else empty end
  ' 2>/dev/null
}

process_event_stream() {
  local event_file="$1" line formatted kind message
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >>"$event_file"
    mark_activity
    formatted="$(printf '%s\n' "$line" | "$PROVIDER_EVENT_FORMATTER" || true)"
    while IFS=$'\t' read -r kind message; do
      [[ -n "$kind" && -n "$message" ]] || continue
      message="$(sanitize_message "$message")"
      if [[ "$kind" == "milestone" ]]; then
        announce_activity "worker: $message"
      else
        record_activity "$message"
      fi
    done <<<"$formatted"
  done
}

process_error_stream() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    announce_activity "$PROVIDER: $line"
  done
}

run_claude_provider() {
  local prompt="$1" result_file="$2" event_pipe="$3" error_pipe="$4"
  : "$result_file"
  (cd "$REPO_ROOT" && "$PROVIDER_BIN" -p "$prompt" \
    --dangerously-skip-permissions \
    --no-session-persistence \
    --output-format stream-json \
    --verbose \
    --include-hook-events \
    --forward-subagent-text \
    --json-schema "$SCHEMA_JSON" >"$event_pipe" 2>"$error_pipe")
}

run_codex_provider() {
  local prompt="$1" result_file="$2" event_pipe="$3" error_pipe="$4"
  "$PROVIDER_BIN" exec --ephemeral \
    --dangerously-bypass-approvals-and-sandbox \
    --cd "$REPO_ROOT" \
    --json \
    --output-schema "$SCHEMA_PATH" \
    --output-last-message "$result_file" \
    "$prompt" >"$event_pipe" 2>"$error_pipe"
}

extract_claude_result() {
  local event_file="$1" result_file="$2"
  jq -c 'select(.structured_output | type == "object") | .structured_output' "$event_file" | tail -n 1 >"$result_file"
}

extract_codex_result() {
  local event_file="$1" result_file="$2"
  : "$event_file" "$result_file"
}
