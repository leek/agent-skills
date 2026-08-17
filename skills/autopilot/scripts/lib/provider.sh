#!/bin/bash
# Claude Code, Codex, and Grok adapters behind one runner interface.

set -e

configure_provider() {
  case "$PROVIDER" in
    claude)
      PROVIDER_BIN="${AUTOPILOT_CLAUDE_BIN:-claude}"
      PROVIDER_BIN_ENV_NAME="AUTOPILOT_CLAUDE_BIN"
      PROVIDER_EVENT_FORMATTER="format_claude_event"
      PROVIDER_EXECUTOR="run_claude_provider"
      PROVIDER_RESULT_EXTRACTOR="extract_claude_result"
      PROVIDER_CONFIG_READER="claude_configured_value"
      PROVIDER_CONFIG_SOURCE="settings"
      PROVIDER_MODEL_KEY="model"
      PROVIDER_EFFORT_KEY="effortLevel"
      PROVIDER_EFFORT_LEVELS="low|medium|high|xhigh|max"
      ;;
    codex)
      PROVIDER_BIN="${AUTOPILOT_CODEX_BIN:-codex}"
      PROVIDER_BIN_ENV_NAME="AUTOPILOT_CODEX_BIN"
      PROVIDER_EVENT_FORMATTER="format_codex_event"
      PROVIDER_EXECUTOR="run_codex_provider"
      PROVIDER_RESULT_EXTRACTOR="extract_codex_result"
      PROVIDER_CONFIG_READER="codex_configured_value"
      PROVIDER_CONFIG_SOURCE="config"
      PROVIDER_MODEL_KEY="model"
      PROVIDER_EFFORT_KEY="model_reasoning_effort"
      PROVIDER_EFFORT_LEVELS="none|minimal|low|medium|high|xhigh|max"
      ;;
    grok)
      PROVIDER_BIN="${AUTOPILOT_GROK_BIN:-grok}"
      PROVIDER_BIN_ENV_NAME="AUTOPILOT_GROK_BIN"
      PROVIDER_EVENT_FORMATTER="format_claude_event"
      PROVIDER_EXECUTOR="run_grok_provider"
      PROVIDER_RESULT_EXTRACTOR="extract_claude_result"
      PROVIDER_CONFIG_READER="grok_configured_value"
      PROVIDER_CONFIG_SOURCE="config"
      PROVIDER_MODEL_KEY="default"
      PROVIDER_EFFORT_KEY="default_reasoning_effort"
      PROVIDER_EFFORT_LEVELS="none|minimal|low|medium|high|xhigh|max"
      ;;
    *)
      runner_failure "--provider must be claude, codex, or grok"
      ;;
  esac
}

json_settings_value() {
  local file="$1" key="$2" value
  [[ -f "$file" ]] || return 1
  value="$(jq -r --arg key "$key" '(.[$key] // empty) | if type == "string" then . else empty end' "$file" 2>/dev/null)" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

claude_configured_value() {
  local key="$1" file value config_dir files=()
  config_dir="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  files+=("/Library/Application Support/ClaudeCode/managed-settings.json")
  files+=("/etc/claude-code/managed-settings.json")
  files+=("$REPO_ROOT/.claude/settings.local.json")
  files+=("$REPO_ROOT/.claude/settings.json")
  files+=("$config_dir/settings.json")

  for file in "${files[@]}"; do
    if value="$(json_settings_value "$file" "$key")"; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

codex_configured_value() {
  local key="$1" file value
  file="${CODEX_HOME:-${HOME:-}/.codex}/config.toml"
  [[ -f "$file" ]] || return 1
  value="$(awk -v key="$key" '
    /^[[:space:]]*\[/ { exit }
    /=/ {
      name = $0
      sub(/=.*$/, "", name)
      gsub(/[[:space:]]/, "", name)
      if (name != key) { next }
      sub(/^[^=]*=/, "", $0)
      sub(/[[:space:]]*#.*$/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print $0
      exit
    }
  ' "$file" | tr -d "\"'")" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

grok_configured_value() {
  local key="$1" file value
  file="${GROK_HOME:-${HOME:-}/.grok}/config.toml"
  [[ -f "$file" ]] || return 1
  value="$(awk -v key="$key" '
    /^[[:space:]]*\[models\][[:space:]]*$/ { in_models=1; next }
    /^[[:space:]]*\[/ { in_models=0; next }
    in_models && /=/ {
      name = $0
      sub(/=.*$/, "", name)
      gsub(/[[:space:]]/, "", name)
      if (name != key) { next }
      sub(/^[^=]*=/, "", $0)
      sub(/[[:space:]]*#.*$/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print $0
      exit
    }
  ' "$file" | tr -d "\"'")" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

validate_worker_tuning() {
  if [[ -n "$REQUESTED_MODEL" ]]; then
    [[ "$REQUESTED_MODEL" != -* && "$REQUESTED_MODEL" =~ ^[^[:space:]]+$ ]] ||
      runner_failure "--model must be a provider model name: $REQUESTED_MODEL"
  fi
  [[ -n "$REQUESTED_EFFORT" ]] || return 0
  [[ "$REQUESTED_EFFORT" =~ ^($PROVIDER_EFFORT_LEVELS)$ ]] ||
    runner_failure "--effort for $PROVIDER must be one of ${PROVIDER_EFFORT_LEVELS//|/, }"
  if [[ "$PROVIDER" == "claude" ]] && ! "$PROVIDER_BIN" --help 2>/dev/null | grep -q -- '--effort'; then
    runner_failure "this claude executable does not support --effort: $PROVIDER_BIN_PATH"
  fi
}

resolve_worker_tuning() {
  local configured=""
  validate_worker_tuning

  if [[ -n "$REQUESTED_MODEL" ]]; then
    WORKER_MODEL="$REQUESTED_MODEL"
    WORKER_MODEL_SOURCE="requested"
  elif configured="$("$PROVIDER_CONFIG_READER" "$PROVIDER_MODEL_KEY")"; then
    WORKER_MODEL="$configured"
    WORKER_MODEL_SOURCE="$PROVIDER_CONFIG_SOURCE"
  else
    WORKER_MODEL="unknown"
    WORKER_MODEL_SOURCE="provider default"
  fi

  if [[ -n "$REQUESTED_EFFORT" ]]; then
    WORKER_EFFORT="$REQUESTED_EFFORT"
    WORKER_EFFORT_SOURCE="requested"
  elif configured="$("$PROVIDER_CONFIG_READER" "$PROVIDER_EFFORT_KEY")"; then
    WORKER_EFFORT="$configured"
    WORKER_EFFORT_SOURCE="$PROVIDER_CONFIG_SOURCE"
  else
    WORKER_EFFORT="unknown"
    WORKER_EFFORT_SOURCE="provider default"
  fi
}

worker_tuning_summary() {
  printf 'model %s (%s), effort %s (%s)' \
    "$WORKER_MODEL" "$WORKER_MODEL_SOURCE" "$WORKER_EFFORT" "$WORKER_EFFORT_SOURCE"
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
    elif .type == "system" and (.subtype // "") == "init" then
      if (.parent_tool_use_id // "") == "" then
        ["model", (.model // "unknown")] | @tsv
      else
        ["event", ("subagent model " + (.model // "unknown"))] | @tsv
      end
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
      elif [[ "$kind" == "model" ]]; then
        [[ -z "$MODEL_CAPTURE_FILE" ]] || printf '%s\n' "$message" >"$MODEL_CAPTURE_FILE"
        if [[ "$message" == "$WORKER_MODEL" ]]; then
          record_activity "worker session model $message"
        else
          announce_activity "worker session model $message (reported)"
        fi
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
  local args=(
    -p "$prompt"
    --dangerously-skip-permissions
    --no-session-persistence
    --output-format stream-json
    --verbose
    --include-hook-events
    --forward-subagent-text
    --json-schema "$SCHEMA_JSON"
  )
  [[ -z "$REQUESTED_MODEL" ]] || args+=(--model "$REQUESTED_MODEL")
  [[ -z "$REQUESTED_EFFORT" ]] || args+=(--effort "$REQUESTED_EFFORT")
  (cd "$REPO_ROOT" && "$PROVIDER_BIN" "${args[@]}" >"$event_pipe" 2>"$error_pipe")
}

run_codex_provider() {
  local prompt="$1" result_file="$2" event_pipe="$3" error_pipe="$4"
  local args=(
    exec --ephemeral
    --dangerously-bypass-approvals-and-sandbox
    --cd "$REPO_ROOT"
    --json
    --output-schema "$SCHEMA_PATH"
    --output-last-message "$result_file"
  )
  [[ -z "$REQUESTED_MODEL" ]] || args+=(--model "$REQUESTED_MODEL")
  [[ -z "$REQUESTED_EFFORT" ]] || args+=(-c "model_reasoning_effort=$REQUESTED_EFFORT")
  "$PROVIDER_BIN" "${args[@]}" "$prompt" >"$event_pipe" 2>"$error_pipe"
}

run_grok_provider() {
  local prompt="$1" result_file="$2" event_pipe="$3" error_pipe="$4"
  : "$result_file"
  local args=(
    --verbatim
    --always-approve
    --output-format streaming-messages-json
    --json-schema "$SCHEMA_JSON"
    --cwd "$REPO_ROOT"
    --no-memory
    --no-plan
  )
  [[ -z "$REQUESTED_MODEL" ]] || args+=(--model "$REQUESTED_MODEL")
  [[ -z "$REQUESTED_EFFORT" ]] || args+=(--effort "$REQUESTED_EFFORT")
  args+=(-p "$prompt")
  "$PROVIDER_BIN" "${args[@]}" >"$event_pipe" 2>"$error_pipe"
}

extract_claude_result() {
  local event_file="$1" result_file="$2"
  jq -c 'select(.structured_output | type == "object") | .structured_output' "$event_file" | tail -n 1 >"$result_file"
}

extract_codex_result() {
  local event_file="$1" result_file="$2"
  : "$event_file" "$result_file"
}
