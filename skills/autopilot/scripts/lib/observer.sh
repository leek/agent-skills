#!/bin/bash
# Status, log following, history, and observer command presentation.

set -e

FOLLOW_STATE_STATUS=""
FOLLOW_STATE_RUNNER_PID=""
FOLLOW_STATE_RUNNER_STARTED=""

print_observer_commands() {
  local emitter="$1" tmux_session="${2:-}" tmux_alive="${3:-true}"

  "$emitter" "status: $(shell_join bash "$SCRIPT_PATH" --status --root "$ROOT_REF" --repo "$REPO_ROOT")"
  "$emitter" "follow: $(shell_join bash "$SCRIPT_PATH" --follow --root "$ROOT_REF" --repo "$REPO_ROOT")"
  "$emitter" "history: $(shell_join bash "$SCRIPT_PATH" --history --root "$ROOT_REF" --repo "$REPO_ROOT")"
  if [[ -n "$tmux_session" && "$tmux_alive" == "true" ]]; then
    "$emitter" "attach: $(shell_join tmux attach -t "$tmux_session")"
  elif [[ -n "$tmux_session" ]]; then
    "$emitter" "tmux session has already exited; use status or follow"
  fi
}

read_follow_state() {
  read_state_fields "$1" '[
    (.status // "interrupted"),
    ((.runner_pid // "") | tostring),
    (.runner_process_started // "")
  ]'
  FOLLOW_STATE_STATUS="${STATE_FIELDS[0]:-interrupted}"
  FOLLOW_STATE_RUNNER_PID="${STATE_FIELDS[1]:-}"
  FOLLOW_STATE_RUNNER_STARTED="${STATE_FIELDS[2]:-}"
}

print_status() {
  [[ -f "$STATE_FILE" ]] || runner_failure "no Autopilot run found for this root"
  validate_state "$STATE_FILE" || runner_failure "runner state is invalid: $STATE_FILE"

  local runner_pid worker_pid runner_process_started worker_process_started runner_alive worker_alive
  local tmux_session tmux_alive activity_file last_event_epoch last_event_at current_status current_iteration current_max log_file
  local current_model current_model_source current_reported_model current_effort current_effort_source model_display
  read_state_fields "$STATE_FILE" '[
    ((.runner_pid // "") | tostring),
    ((.worker_pid // "") | tostring),
    (.runner_process_started // ""),
    (.worker_process_started // ""),
    (.tmux_session // ""),
    (.activity_file // ""),
    (.status // "interrupted"),
    ((.iteration // 0) | tostring),
    ((.max_iterations // 0) | tostring),
    (.model // ""),
    (.model_source // ""),
    (.reported_model // ""),
    (.effort // ""),
    (.effort_source // "")
  ]'
  runner_pid="${STATE_FIELDS[0]:-}"
  worker_pid="${STATE_FIELDS[1]:-}"
  runner_process_started="${STATE_FIELDS[2]:-}"
  worker_process_started="${STATE_FIELDS[3]:-}"
  tmux_session="${STATE_FIELDS[4]:-}"
  activity_file="${STATE_FIELDS[5]:-}"
  current_status="${STATE_FIELDS[6]:-interrupted}"
  current_iteration="${STATE_FIELDS[7]:-0}"
  current_max="${STATE_FIELDS[8]:-0}"
  current_model="${STATE_FIELDS[9]:-}"
  current_model_source="${STATE_FIELDS[10]:-}"
  current_reported_model="${STATE_FIELDS[11]:-}"
  current_effort="${STATE_FIELDS[12]:-}"
  current_effort_source="${STATE_FIELDS[13]:-}"

  if pid_is_alive "$runner_pid" "$runner_process_started"; then runner_alive=true; else runner_alive=false; fi
  if pid_is_alive "$worker_pid" "$worker_process_started"; then worker_alive=true; else worker_alive=false; fi
  tmux_alive=false
  if [[ -n "$tmux_session" ]] && command -v tmux >/dev/null 2>&1 && tmux has-session -t "$tmux_session" 2>/dev/null; then
    tmux_alive=true
  fi
  last_event_epoch="$(file_mtime "$activity_file")"
  last_event_at="$(iso_from_epoch "$last_event_epoch")"
  log_file="$(state_log_file "$STATE_FILE")"

  printf 'Autopilot: status %s (iteration %s/%s); runner %s; worker %s\n' \
    "$current_status" "$current_iteration" "$current_max" \
    "$([[ "$runner_alive" == true ]] && printf alive || printf stopped)" \
    "$([[ "$worker_alive" == true ]] && printf alive || printf stopped)" >&2
  if [[ -n "$current_model" || -n "$current_reported_model" || -n "$current_effort" ]]; then
    if [[ -n "$current_reported_model" ]]; then
      model_display="$current_reported_model (reported)"
    else
      model_display="${current_model:-unknown} (${current_model_source:-unknown})"
    fi
    emit_stderr "worker session model $model_display, effort ${current_effort:-unknown} (${current_effort_source:-unknown})"
  fi
  emit_stderr "log $log_file"

  jq -c \
    --argjson runner_alive "$runner_alive" \
    --argjson worker_alive "$worker_alive" \
    --argjson tmux_alive "$tmux_alive" \
    --arg last_event_at "$last_event_at" \
    '. + {
      runner_alive: $runner_alive,
      worker_alive: $worker_alive,
      tmux_alive: $tmux_alive,
      last_event_at: (if $last_event_at == "" then null else $last_event_at end)
    }' "$STATE_FILE"
}

follow_log() {
  [[ -f "$STATE_FILE" ]] || runner_failure "no Autopilot run found for this root"
  validate_state "$STATE_FILE" || runner_failure "runner state is invalid: $STATE_FILE"

  local follow_run_id follow_state_file log_file current_status runner_pid runner_process_started tail_pid
  read_state_fields "$STATE_FILE" '[.run_id]'
  follow_run_id="${STATE_FIELDS[0]:-}"
  follow_state_file="$RUNS_DIR/$follow_run_id/state.json"
  [[ -f "$follow_state_file" ]] || follow_state_file="$STATE_FILE"
  log_file="$(state_log_file "$follow_state_file")"
  [[ -f "$log_file" ]] || runner_failure "run log not found: $log_file"

  read_follow_state "$follow_state_file"
  current_status="$FOLLOW_STATE_STATUS"
  runner_pid="$FOLLOW_STATE_RUNNER_PID"
  runner_process_started="$FOLLOW_STATE_RUNNER_STARTED"
  if [[ "$current_status" != "running" ]]; then
    emit_stderr "run is $current_status; showing the final log"
    tail -n 50 "$log_file"
    return 0
  fi
  if ! pid_is_alive "$runner_pid" "$runner_process_started"; then
    emit_stderr "runner stopped without recording terminal state"
    tail -n 50 "$log_file"
    return 5
  fi

  emit_stderr "following $log_file until the run stops (Ctrl-C to stop early)"
  tail -n 50 -F "$log_file" &
  tail_pid=$!
  CHILD_PIDS+=("$tail_pid")
  while kill -0 "$tail_pid" 2>/dev/null; do
    sleep 2
    read_follow_state "$follow_state_file"
    current_status="$FOLLOW_STATE_STATUS"
    runner_pid="$FOLLOW_STATE_RUNNER_PID"
    runner_process_started="$FOLLOW_STATE_RUNNER_STARTED"
    if [[ "$current_status" != "running" ]] || ! pid_is_alive "$runner_pid" "$runner_process_started"; then
      sleep 1
      kill "$tail_pid" 2>/dev/null || true
      wait "$tail_pid" 2>/dev/null || true
      CHILD_PIDS=()
      emit_stderr "final log tail"
      tail -n 5 "$log_file"
      if [[ "$current_status" == "running" ]]; then
        emit_stderr "runner stopped without recording terminal state"
        return 5
      fi
      emit_stderr "run reached $current_status"
      return 0
    fi
  done
}

print_history() {
  local history_files=() state_file skipped=0
  if [[ -d "$RUNS_DIR" ]]; then
    for state_file in "$RUNS_DIR"/*/state.json; do
      [[ -f "$state_file" ]] || continue
      if jq -e 'type == "object" and (.root_ref | type == "string") and (.repo_root | type == "string") and (.created_at | type == "string")' "$state_file" >/dev/null 2>&1; then
        history_files+=("$state_file")
      else
        skipped=$((skipped + 1))
      fi
    done
  fi

  if [[ "${#history_files[@]}" -eq 0 ]]; then
    emit_stderr "no run history found for this root"
    [[ "$skipped" -eq 0 ]] || emit_stderr "skipped $skipped malformed run state file(s)"
    jq -cn '[]'
    return 0
  fi

  local history count
  history="$(jq -sc --arg root "$ROOT_REF" --arg repo "$REPO_ROOT" '
    map(select(.root_ref == $root and .repo_root == $repo)) | sort_by(.created_at) | reverse
  ' "${history_files[@]}")"
  count="$(printf '%s\n' "$history" | jq 'length')"
  emit_stderr "$count run(s) found for this root"
  [[ "$skipped" -eq 0 ]] || emit_stderr "skipped $skipped malformed run state file(s)"
  printf '%s\n' "$history"
}
