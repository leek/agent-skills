#!/bin/bash
# Persisted Autopilot state and terminal result lifecycle.

set -e

json_failure() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg reason "$reason" '{status:"failed",completed_ref:"",next_ref:"",summary:"Autopilot stopped.",reason:$reason}'
  else
    local escaped="${reason//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '{"status":"failed","completed_ref":"","next_ref":"","summary":"Autopilot stopped.","reason":"%s"}\n' "$escaped"
  fi
}

read_state_fields() {
  local state_file="$1" query="$2" sentinel="__AUTOPILOT_STATE_END__" snapshot last_index
  snapshot="$(jq -jr --arg sentinel "$sentinel" \
    "(($query) + [\$sentinel]) | map(if . == null then \"\" else tostring end) | join(\"\\u001f\")" \
    "$state_file")" || return 1
  IFS=$'\x1f' read -r -a STATE_FIELDS <<<"$snapshot"
  last_index=$((${#STATE_FIELDS[@]} - 1))
  unset "STATE_FIELDS[$last_index]"
}

persist_state() {
  [[ "$STATE_ACTIVE" == "true" && -n "$STATE_FILE" && -n "$RUN_ID" ]] || return 0

  local state_temp run_state_temp
  state_temp="$(mktemp "$STATE_DIR/.state.XXXXXX")" || return 1
  jq -cn \
    --arg run_id "$RUN_ID" \
    --arg root_ref "$ROOT_REF" \
    --arg repo_root "$REPO_ROOT" \
    --arg created_at "$CREATED_AT" \
    --arg status "$RUN_STATUS" \
    --arg phase "$RUN_PHASE" \
    --arg provider "$PROVIDER" \
    --arg model "$WORKER_MODEL" \
    --arg model_source "$WORKER_MODEL_SOURCE" \
    --arg reported_model "$REPORTED_MODEL" \
    --arg effort "$WORKER_EFFORT" \
    --arg effort_source "$WORKER_EFFORT_SOURCE" \
    --arg runner_pid "$RUNNER_PID_STATE" \
    --arg worker_pid "$WORKER_PID_STATE" \
    --arg runner_process_started "$RUNNER_PROCESS_STARTED" \
    --arg worker_process_started "$WORKER_PROCESS_STARTED" \
    --arg worker_process_group "$WORKER_PROCESS_GROUP" \
    --arg worker_started_at "$WORKER_STARTED_AT" \
    --arg finished_at "$FINISHED_AT" \
    --arg iteration "$ITERATION" \
    --arg max_iterations "$MAX_ITERATIONS" \
    --arg heartbeat_seconds "$HEARTBEAT_SECONDS" \
    --arg quiet_seconds "$QUIET_SECONDS" \
    --arg log_file "$LOG_FILE" \
    --arg log_mirror_file "$LOG_MIRROR_FILE" \
    --arg activity_file "$ACTIVITY_FILE" \
    --arg tmux_session "$TMUX_SESSION" \
    --arg tmux_launch_id "$TMUX_LAUNCH_ID" \
    --arg summary "$SUMMARY" \
    --arg reason "$REASON" \
    --arg completed_ref "$LAST_COMPLETED_REF" \
    --arg next_ref "$NEXT_REF_STATE" \
    --arg result_file "$RESULT_FILE_STATE" \
    '{
      version: 3,
      run_id: $run_id,
      root_ref: $root_ref,
      repo_root: $repo_root,
      created_at: $created_at,
      status: $status,
      phase: $phase,
      provider: $provider,
      model: $model,
      model_source: $model_source,
      reported_model: (if $reported_model == "" then null else $reported_model end),
      effort: $effort,
      effort_source: $effort_source,
      runner_pid: (if $runner_pid == "" then null else ($runner_pid | tonumber) end),
      worker_pid: (if $worker_pid == "" then null else ($worker_pid | tonumber) end),
      runner_process_started: (if $runner_process_started == "" then null else $runner_process_started end),
      worker_process_started: (if $worker_process_started == "" then null else $worker_process_started end),
      worker_process_group: (if $worker_process_group == "" then null else ($worker_process_group | tonumber) end),
      worker_started_at: (if $worker_started_at == "" then null else $worker_started_at end),
      finished_at: (if $finished_at == "" then null else $finished_at end),
      iteration: ($iteration | tonumber),
      max_iterations: ($max_iterations | tonumber),
      heartbeat_seconds: ($heartbeat_seconds | tonumber),
      quiet_seconds: ($quiet_seconds | tonumber),
      log_file: $log_file,
      log_mirror_file: (if $log_mirror_file == "" then null else $log_mirror_file end),
      activity_file: $activity_file,
      tmux_session: (if $tmux_session == "" then null else $tmux_session end),
      tmux_launch_id: (if $tmux_launch_id == "" then null else $tmux_launch_id end),
      summary: $summary,
      reason: $reason,
      completed_ref: $completed_ref,
      next_ref: $next_ref,
      result_file: (if $result_file == "" then null else $result_file end)
    }' >"$state_temp"
  run_state_temp="$(mktemp "$RUN_DIR/.state.XXXXXX")" || {
    rm -f -- "$state_temp"
    return 1
  }
  cp -- "$state_temp" "$run_state_temp" || {
    rm -f -- "$state_temp" "$run_state_temp"
    return 1
  }
  mv -- "$run_state_temp" "$RUN_DIR/state.json"
  mv -- "$state_temp" "$STATE_FILE"
}

transition_to_terminal() {
  RUN_STATUS="$1"
  RUN_PHASE="terminal"
  FINISHED_AT="$(timestamp)"
  RUNNER_PID_STATE=""
  WORKER_PID_STATE=""
  WORKER_PROCESS_STARTED=""
  WORKER_PROCESS_GROUP=""
  WORKER_STARTED_AT=""
}

record_terminal_state() {
  local status="$1" summary="$2" reason="$3"
  [[ "$STATE_ACTIVE" == "true" && -n "$RUN_ID" ]] || return 0

  transition_to_terminal "$status"
  SUMMARY="$summary"
  REASON="$reason"
  LAST_COMPLETED_REF=""
  NEXT_REF_STATE=""
  RESULT_FILE_STATE="$RUN_DIR/last-result.json"
  jq -cn \
    --arg status "$status" \
    --arg summary "$summary" \
    --arg reason "$reason" \
    '{status:$status,completed_ref:"",next_ref:"",summary:$summary,reason:$reason}' >"$RESULT_FILE_STATE" || true
  persist_state || true
}

record_failure_state() {
  record_terminal_state "failed" "Autopilot stopped." "$1"
}

validate_state() {
  local state_file="$1"
  jq -e --arg root "$ROOT_REF" --arg repo "$REPO_ROOT" '
    (.version == 1 or .version == 2 or .version == 3) and
    .root_ref == $root and
    .repo_root == $repo and
    (.run_id | type == "string" and length > 0)
  ' "$state_file" >/dev/null 2>&1
}

run_log_file() {
  printf '%s/%s/autopilot.log' "$RUNS_DIR" "$1"
}

state_log_file() {
  local state_file="$1"
  local run_id log_file
  read_state_fields "$state_file" '[.run_id, (.log_file // "")]'
  run_id="${STATE_FIELDS[0]:-}"
  log_file="${STATE_FIELDS[1]:-}"
  [[ -n "$log_file" ]] || log_file="$(run_log_file "$run_id")"
  printf '%s' "$log_file"
}
