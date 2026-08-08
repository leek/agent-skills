#!/bin/bash
# Detached Autopilot launcher.

set -e

TMUX_STATE_STATUS=""
TMUX_STATE_RUNNER_PID=""
TMUX_STATE_RUNNER_STARTED=""
TMUX_STATE_SESSION=""
TMUX_STATE_LAUNCH_ID=""
TMUX_STATE_RUN_ID=""
TMUX_STATE_LOG_FILE=""
TMUX_STATE_LOG_MIRROR_FILE=""

tmux_launch_failure() {
  local session_name="$1" reason="$2"
  tmux kill-session -t "$session_name" 2>/dev/null || true
  runner_failure "$reason"
}

read_tmux_state() {
  read_state_fields "$1" '[
    (.status // ""),
    ((.runner_pid // "") | tostring),
    (.runner_process_started // ""),
    (.tmux_session // ""),
    (.tmux_launch_id // ""),
    (.run_id // ""),
    (.log_file // ""),
    (.log_mirror_file // "")
  ]'
  TMUX_STATE_STATUS="${STATE_FIELDS[0]:-}"
  TMUX_STATE_RUNNER_PID="${STATE_FIELDS[1]:-}"
  TMUX_STATE_RUNNER_STARTED="${STATE_FIELDS[2]:-}"
  TMUX_STATE_SESSION="${STATE_FIELDS[3]:-}"
  TMUX_STATE_LAUNCH_ID="${STATE_FIELDS[4]:-}"
  TMUX_STATE_RUN_ID="${STATE_FIELDS[5]:-}"
  TMUX_STATE_LOG_FILE="${STATE_FIELDS[6]:-}"
  TMUX_STATE_LOG_MIRROR_FILE="${STATE_FIELDS[7]:-}"
}

launch_tmux() {
  command -v tmux >/dev/null 2>&1 || runner_failure "tmux is required for --tmux"

  local session_name="autopilot-${STATE_KEY:0:10}" launch_id
  launch_id="tmux-$(printf '%s\0%s\0%s' "$STATE_KEY" "$(timestamp)" "$$-$RANDOM" | git hash-object --stdin)"
  read_lock_owner "$LOCK_DIR/pid"
  if pid_is_alive "$LOCK_OWNER_PID" "$LOCK_OWNER_STARTED"; then
    runner_failure "another Autopilot process is active for this root (pid $LOCK_OWNER_PID)"
  fi
  if tmux has-session -t "$session_name" 2>/dev/null; then
    runner_failure "tmux session already exists: $session_name"
  fi

  local command_args=(
    env
    "AUTOPILOT_TMUX_CHILD=1"
    "AUTOPILOT_TMUX_SESSION=$session_name"
    "AUTOPILOT_TMUX_LAUNCH_ID=$launch_id"
    "AUTOPILOT_HEARTBEAT_SECONDS=$HEARTBEAT_SECONDS"
    "$PROVIDER_BIN_ENV_NAME=$PROVIDER_BIN_PATH"
    bash "$SCRIPT_PATH"
    --provider "$PROVIDER"
    --root "$ROOT_REF"
    --repo "$REPO_ROOT"
    --max-iterations "$MAX_ITERATIONS"
  )
  [[ -z "$LOG_FILE_OVERRIDE" ]] || command_args+=(--log-file "$LOG_FILE_OVERRIDE")

  local tmux_command
  tmux_command="$(shell_join "${command_args[@]}")"
  tmux new-session -d -s "$session_name" -c "$REPO_ROOT" "$tmux_command" || runner_failure "could not start tmux session: $session_name"

  local deadline
  deadline=$(( $(now_epoch) + TMUX_START_TIMEOUT_SECONDS ))
  while [[ "$(now_epoch)" -lt "$deadline" ]]; do
    if [[ -f "$STATE_FILE" ]] && validate_state "$STATE_FILE"; then
      read_tmux_state "$STATE_FILE"
      if [[ "$TMUX_STATE_SESSION" == "$session_name" && "$TMUX_STATE_LAUNCH_ID" == "$launch_id" && "$TMUX_STATE_STATUS" == "running" ]] && pid_is_alive "$TMUX_STATE_RUNNER_PID" "$TMUX_STATE_RUNNER_STARTED"; then
        break
      fi
      if [[ "$TMUX_STATE_SESSION" == "$session_name" && "$TMUX_STATE_LAUNCH_ID" == "$launch_id" && -n "$TMUX_STATE_STATUS" ]] && ! tmux has-session -t "$session_name" 2>/dev/null; then
        break
      fi
    fi
    sleep 0.1
  done

  if [[ ! -f "$STATE_FILE" ]] || ! validate_state "$STATE_FILE"; then
    tmux_launch_failure "$session_name" "tmux session did not create runner state within ${TMUX_START_TIMEOUT_SECONDS}s: $session_name"
  fi

  local run_id log_file log_mirror_file
  read_tmux_state "$STATE_FILE"
  run_id="$TMUX_STATE_RUN_ID"
  log_file="$TMUX_STATE_LOG_FILE"
  log_mirror_file="$TMUX_STATE_LOG_MIRROR_FILE"
  [[ -n "$log_file" ]] || log_file="$(run_log_file "$run_id")"

  [[ "$TMUX_STATE_SESSION" == "$session_name" && "$TMUX_STATE_LAUNCH_ID" == "$launch_id" ]] || tmux_launch_failure "$session_name" "tmux session did not own observable runner state within ${TMUX_START_TIMEOUT_SECONDS}s: $session_name"
  if [[ "$TMUX_STATE_STATUS" == "running" ]] && ! pid_is_alive "$TMUX_STATE_RUNNER_PID" "$TMUX_STATE_RUNNER_STARTED"; then
    tmux_launch_failure "$session_name" "tmux runner stopped before becoming observable: $session_name"
  fi
  [[ -n "$TMUX_STATE_STATUS" ]] || tmux_launch_failure "$session_name" "tmux runner state has no status: $session_name"

  local launch_status tmux_alive
  launch_status="$TMUX_STATE_STATUS"
  [[ "$TMUX_STATE_STATUS" != "running" ]] || launch_status="started"
  tmux_alive="false"
  tmux has-session -t "$session_name" 2>/dev/null && tmux_alive="true"

  emit_stderr "$launch_status $run_id in tmux session $session_name"
  emit_stderr "log $log_file"
  [[ -z "$log_mirror_file" ]] || emit_stderr "log mirror $log_mirror_file"
  print_observer_commands emit_stderr "$session_name" "$tmux_alive"
  jq -cn \
    --arg status "$launch_status" \
    --arg run_id "$run_id" \
    --arg tmux_session "$session_name" \
    --arg log_file "$log_file" \
    --arg log_mirror_file "$log_mirror_file" \
    '{status:$status,run_id:$run_id,tmux_session:$tmux_session,log_file:$log_file,log_mirror_file:(if $log_mirror_file == "" then null else $log_mirror_file end)}'
}
