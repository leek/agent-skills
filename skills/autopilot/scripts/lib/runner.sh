#!/bin/bash
# Stateful fresh-process Autopilot run loop.

set -e

find_skill() {
  local name="$1"
  local candidate=""
  local user_home="${HOME:-}"
  local codex_home="${CODEX_HOME:-}"
  local roots=("$REPO_ROOT/.agents/skills" "$REPO_ROOT/.claude/skills" "$REPO_ROOT/.codex/skills")

  roots+=("$(cd "$SKILL_DIR/.." && pwd -P)")
  if [[ -n "$user_home" ]]; then
    roots+=("$user_home/.agents/skills" "$user_home/.claude/skills")
    [[ -n "$codex_home" ]] || codex_home="$user_home/.codex"
  fi
  [[ -z "$codex_home" ]] || roots+=("$codex_home/skills")

  for candidate in "${roots[@]}"; do
    if [[ -f "$candidate/$name/SKILL.md" ]]; then
      (cd "$candidate/$name" && printf '%s/SKILL.md\n' "$(pwd -P)")
      return 0
    fi
  done
  return 1
}

resolve_workflow_skills() {
  WAYFINDER_PATH="$(find_skill wayfinder)" || runner_failure "required skill not found: wayfinder"
  TO_SPEC_PATH="$(find_skill to-spec)" || runner_failure "required skill not found: to-spec"
  TO_TICKETS_PATH="$(find_skill to-tickets)" || runner_failure "required skill not found: to-tickets"
  IMPLEMENT_PATH="$(find_skill implement)" || runner_failure "required skill not found: implement"
}

resolve_log_file() {
  local requested="$1" parent
  if [[ "$requested" != /* ]]; then
    requested="$REPO_ROOT/$requested"
  fi
  parent="$(dirname "$requested")"
  mkdir -p -- "$parent" || return 1
  parent="$(cd "$parent" && pwd -P)" || return 1
  printf '%s/%s' "$parent" "$(basename "$requested")"
}

initialize_run() {
  local new_run="true" existing_status="" existing_run_id="" existing_created_at=""
  local existing_log_mirror="" existing_activity="" existing_completed_ref="" existing_next_ref="" existing_result_file=""

  if [[ -f "$STATE_FILE" ]]; then
    validate_state "$STATE_FILE" || runner_failure "runner state is invalid: $STATE_FILE"
    read_state_fields "$STATE_FILE" '[
      (.status // "interrupted"),
      .run_id,
      .created_at,
      (.log_mirror_file // ""),
      (.activity_file // ""),
      (.completed_ref // ""),
      (.next_ref // ""),
      (.result_file // "")
    ]'
    existing_status="${STATE_FIELDS[0]:-interrupted}"
    existing_run_id="${STATE_FIELDS[1]:-}"
    existing_created_at="${STATE_FIELDS[2]:-}"
    existing_log_mirror="${STATE_FIELDS[3]:-}"
    existing_activity="${STATE_FIELDS[4]:-}"
    existing_completed_ref="${STATE_FIELDS[5]:-}"
    existing_next_ref="${STATE_FIELDS[6]:-}"
    existing_result_file="${STATE_FIELDS[7]:-}"
    [[ "$existing_status" == "complete" ]] || new_run="false"
  fi

  if [[ "$new_run" == "true" ]]; then
    CREATED_AT="$(timestamp)"
    local run_hash
    run_hash="$(printf '%s\0%s\0%s\0%s' "$REPO_ROOT" "$ROOT_REF" "$CREATED_AT" "$$-$RANDOM" | git hash-object --stdin)"
    RUN_ID="autopilot-$run_hash"
  else
    RUN_ID="$existing_run_id"
    CREATED_AT="$existing_created_at"
    LAST_COMPLETED_REF="$existing_completed_ref"
    NEXT_REF_STATE="$existing_next_ref"
    RESULT_FILE_STATE="$existing_result_file"
  fi

  RUN_DIR="$RUNS_DIR/$RUN_ID"
  mkdir -p -- "$RUN_DIR" || runner_failure "could not create run directory: $RUN_DIR"
  LOG_FILE="$(run_log_file "$RUN_ID")"

  if [[ -n "$LOG_FILE_OVERRIDE" ]]; then
    LOG_MIRROR_FILE="$(resolve_log_file "$LOG_FILE_OVERRIDE")" || runner_failure "could not resolve log path: $LOG_FILE_OVERRIDE"
    if [[ -n "$existing_log_mirror" && "$LOG_MIRROR_FILE" != "$existing_log_mirror" ]]; then
      runner_failure "resumed run already mirrors its log to: $existing_log_mirror"
    fi
  elif [[ -n "$existing_log_mirror" ]]; then
    LOG_MIRROR_FILE="$existing_log_mirror"
  fi

  if [[ "$new_run" == "false" && -n "$existing_activity" ]]; then
    ACTIVITY_FILE="$existing_activity"
  else
    ACTIVITY_FILE="$RUN_DIR/activity"
  fi
  touch "$LOG_FILE" "$ACTIVITY_FILE" || runner_failure "could not initialize run log: $LOG_FILE"
  [[ -z "$LOG_MIRROR_FILE" ]] || touch "$LOG_MIRROR_FILE" || runner_failure "could not initialize log mirror: $LOG_MIRROR_FILE"

  RUN_STATUS="running"
  RUN_PHASE="starting"
  RUNNER_PID_STATE="$$"
  WORKER_PID_STATE=""
  FINISHED_AT=""
  SUMMARY=""
  REASON=""
  ITERATION=0
  STATE_ACTIVE="true"
  persist_state || runner_failure "could not persist runner state: $STATE_FILE"

  announce_activity "run $RUN_ID started ($PROVIDER)"
  announce "worker session $(worker_tuning_summary)"
  announce "log $LOG_FILE"
  [[ -z "$LOG_MIRROR_FILE" ]] || announce "log mirror $LOG_MIRROR_FILE"
  print_observer_commands announce "$TMUX_SESSION"
}

build_prompt() {
  local context_json="$1" workflow_line=""
  case "$TRACKER_MODE" in
    decision) workflow_line="Decision workflow: $WAYFINDER_PATH" ;;
    build|direct-spec) workflow_line="Build workflow: $IMPLEMENT_PATH" ;;
    *) runner_failure "unsupported tracker mode: $TRACKER_MODE" ;;
  esac

  printf '%s\n' \
    "You are one fresh top-level worker in an external Autopilot loop." \
    "Read and follow this worker contract completely: $WORKER_PATH" \
    "Target repository: $REPO_ROOT" \
    "Autopilot run ID: $RUN_ID" \
    "$workflow_line" \
    "The runner selected the exact unit from current tracker and Git state." \
    "Iteration context manifest (JSON): $context_json" \
    "Perform exactly that unit. On success return it as completed_ref with an empty next_ref; the runner computes the next frontier. Return only the required structured result."
}

tracker_terminal_result() {
  local result_file="$1" status summary next_ref
  status="$TRACKER_OUTCOME"
  next_ref="$TRACKER_NEXT_REF"
  case "$status" in
    complete) summary="Autopilot scope is complete." ;;
    needs_input) summary="Autopilot reached a human gate." ;;
    blocked) summary="Autopilot has no autonomous frontier." ;;
    *) runner_failure "cannot terminate from tracker outcome: $status" ;;
  esac
  jq -cn \
    --arg status "$status" \
    --arg next_ref "$next_ref" \
    --arg summary "$summary" \
    --arg reason "$TRACKER_REASON" \
    '{status:$status,completed_ref:"",next_ref:$next_ref,summary:$summary,reason:$reason}' >"$result_file"
}

reconcile_successful_result() {
  local result_file="$1" status next_ref reason
  tracker_refresh
  case "$TRACKER_OUTCOME" in
    selected)
      status="continue"
      next_ref="$TRACKER_SELECTED_REF"
      reason="Runner selected $next_ref from the current tracker frontier."
      ;;
    complete)
      status="complete"
      next_ref=""
      reason="$TRACKER_REASON"
      ;;
    needs_input)
      status="needs_input"
      next_ref="$TRACKER_NEXT_REF"
      reason="$TRACKER_REASON"
      ;;
    blocked)
      status="blocked"
      next_ref=""
      reason="$TRACKER_REASON"
      ;;
    *) runner_failure "unsupported tracker outcome after worker success: $TRACKER_OUTCOME" ;;
  esac
  jq \
    --arg status "$status" \
    --arg next_ref "$next_ref" \
    --arg reason "$reason" \
    '.status = $status | .next_ref = $next_ref | .reason = $reason' \
    "$result_file" >"$result_file.reconciled"
  mv -- "$result_file.reconciled" "$result_file"
}

terminal_exit_for_status() {
  case "$1" in
    complete) printf '0' ;;
    needs_input) printf '2' ;;
    blocked) printf '3' ;;
    failed) printf '4' ;;
    *) return 1 ;;
  esac
}

validate_result() {
  local result_file="$1"
  jq -e '
    type == "object" and
    (.status == "continue" or .status == "complete" or .status == "needs_input" or .status == "blocked" or .status == "failed") and
    (.completed_ref | type == "string") and
    (.next_ref | type == "string") and
    (.summary | type == "string") and
    (.reason | type == "string") and
    (keys | sort == ["completed_ref", "next_ref", "reason", "status", "summary"])
  ' "$result_file" >/dev/null 2>&1
}

capture_reported_model() {
  local captured
  [[ -n "$MODEL_CAPTURE_FILE" && -s "$MODEL_CAPTURE_FILE" ]] || return 1
  captured="$(sed -n '1p' "$MODEL_CAPTURE_FILE")"
  [[ -n "$captured" && "$captured" != "$REPORTED_MODEL" ]] || return 1
  REPORTED_MODEL="$captured"
}

monitor_worker() {
  local worker_pid="$1" exit_file="$2" started_epoch="$3"
  local next_heartbeat now last_event age elapsed message
  next_heartbeat=$((started_epoch + HEARTBEAT_SECONDS))

  while [[ ! -f "$exit_file" ]] && kill -0 "$worker_pid" 2>/dev/null; do
    sleep "$POLL_SECONDS"
    if capture_reported_model; then
      persist_state || true
    fi
    now="$(now_epoch)"
    if [[ "$now" -ge "$next_heartbeat" ]]; then
      last_event="$(file_mtime "$ACTIVITY_FILE")"
      age=$((now - last_event))
      elapsed=$((now - started_epoch))
      message="worker alive (iteration $ITERATION/$MAX_ITERATIONS, model ${REPORTED_MODEL:-$WORKER_MODEL}, effort $WORKER_EFFORT, elapsed $(format_duration "$elapsed"), last event $(format_duration "$age") ago)"
      if [[ "$age" -ge "$QUIET_SECONDS" ]]; then
        message="$message; quiet threshold reached"
      fi
      announce "$message"
      next_heartbeat=$((now + HEARTBEAT_SECONDS))
    fi
  done
}

run_worker() {
  local prompt="$1" result_file="$2" event_file="$3"
  local event_pipe="$TEMP_DIR/events-$ITERATION.pipe"
  local error_pipe="$TEMP_DIR/errors-$ITERATION.pipe"
  local exit_file="$TEMP_DIR/exit-$ITERATION"
  local event_reader_pid error_reader_pid worker_pid worker_pgid runner_pgid started_epoch worker_exit

  MODEL_CAPTURE_FILE="$TEMP_DIR/model-$ITERATION"
  : >"$MODEL_CAPTURE_FILE"

  mkfifo "$event_pipe" "$error_pipe"
  process_event_stream "$event_file" <"$event_pipe" &
  event_reader_pid=$!
  CHILD_PIDS+=("$event_reader_pid")
  process_error_stream <"$error_pipe" &
  error_reader_pid=$!
  CHILD_PIDS+=("$error_reader_pid")

  set -m
  (
    set +e
    "$PROVIDER_EXECUTOR" "$prompt" "$result_file" "$event_pipe" "$error_pipe"
    worker_exit=$?
    printf '%s\n' "$worker_exit" >"$exit_file"
    exit "$worker_exit"
  ) &
  worker_pid=$!
  set +m
  CHILD_PIDS+=("$worker_pid")
  worker_pgid="$(ps -o pgid= -p "$worker_pid" 2>/dev/null | tr -d '[:space:]')"
  runner_pgid="$(ps -o pgid= -p "$$" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$worker_pgid" =~ ^[1-9][0-9]*$ && "$worker_pgid" != "$runner_pgid" ]]; then
    CHILD_PROCESS_GROUPS+=("$worker_pgid")
    WORKER_PROCESS_GROUP="$worker_pgid"
  fi

  started_epoch="$(now_epoch)"
  WORKER_PID_STATE="$worker_pid"
  WORKER_PROCESS_STARTED="$(process_started_at "$worker_pid")"
  WORKER_STARTED_AT="$(timestamp)"
  RUN_PHASE="worker"
  persist_state || worker_failure "could not update worker state"
  monitor_worker "$worker_pid" "$exit_file" "$started_epoch"

  worker_exit=1
  [[ ! -f "$exit_file" ]] || worker_exit="$(sed -n '1p' "$exit_file")"
  wait "$worker_pid" 2>/dev/null || true
  wait "$event_reader_pid" 2>/dev/null || true
  wait "$error_reader_pid" 2>/dev/null || true
  CHILD_PIDS=()
  CHILD_PROCESS_GROUPS=()

  WORKER_PID_STATE=""
  WORKER_PROCESS_STARTED=""
  WORKER_PROCESS_GROUP=""
  WORKER_STARTED_AT=""
  RUN_PHASE="reconciling"
  capture_reported_model || true
  persist_state || worker_failure "could not update worker state"

  "$PROVIDER_RESULT_EXTRACTOR" "$event_file" "$result_file"
  [[ "$worker_exit" == "0" ]] || return "$worker_exit"
}

run_autopilot_loop() {
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autopilot.XXXXXX")" || runner_failure "could not create a temporary directory"
  SCHEMA_JSON="$(jq -c . "$SCHEMA_PATH")"

  ITERATION=1
  while [[ "$ITERATION" -le "$MAX_ITERATIONS" ]]; do
    announce_activity "iteration $ITERATION/$MAX_ITERATIONS ($PROVIDER, $(worker_tuning_summary))"
    persist_state || runner_failure "could not persist iteration state"
    local prompt result_file attempt_id event_file result_status completed_ref next_ref terminal_exit
    local tickets_before tickets_after selected_file
    result_file="$TEMP_DIR/result-$ITERATION.json"
    attempt_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$-$ITERATION"
    event_file="$RUN_DIR/$attempt_id.$PROVIDER.events.jsonl"
    touch "$event_file"
    tickets_before="$TEMP_DIR/tickets-$ITERATION.before"
    tickets_after="$TEMP_DIR/tickets-$ITERATION.after"
    snapshot_work_items "$tickets_before"

    tracker_refresh
    if [[ "$TRACKER_OUTCOME" != "selected" ]]; then
      tracker_terminal_result "$result_file"
      result_status="$(jq -r '.status' "$result_file")"
      SUMMARY="$(jq -r '.summary' "$result_file")"
      REASON="$(jq -r '.reason' "$result_file")"
      NEXT_REF_STATE="$(jq -r '.next_ref' "$result_file")"
      RESULT_FILE_STATE="$RUN_DIR/last-result.json"
      cp -- "$result_file" "$RESULT_FILE_STATE" || runner_failure "could not persist tracker result"
      terminal_exit="$(terminal_exit_for_status "$result_status")"
      transition_to_terminal "$result_status"
      persist_state || runner_failure "could not persist terminal tracker state"
      announce_activity "$SUMMARY"
      [[ -z "$NEXT_REF_STATE" ]] || announce_activity "next $NEXT_REF_STATE"
      jq -c . "$result_file"
      return "$terminal_exit"
    fi

    selected_file="$TRACKER_SELECTED_FILE"
    announce_activity "selected $TRACKER_SELECTED_REF ($TRACKER_SELECTION, $TRACKER_MODE)"
    prompt="$(build_prompt "$TRACKER_CONTEXT_JSON")"

    if ! run_worker "$prompt" "$result_file" "$event_file"; then
      worker_failure "$PROVIDER worker process failed in iteration $ITERATION"
    fi
    validate_result "$result_file" || worker_failure "$PROVIDER worker returned an invalid result in iteration $ITERATION"

    result_status="$(jq -r '.status' "$result_file")"
    completed_ref="$(jq -r '.completed_ref' "$result_file")"

    snapshot_work_items "$tickets_after"
    announce_work_item_changes "$tickets_before" "$tickets_after"
    if [[ "$result_status" == "continue" || "$result_status" == "complete" ]]; then
      [[ -n "$completed_ref" ]] || worker_failure "$result_status result omitted completed_ref in iteration $ITERATION"
      verify_completed_ref_selected "$completed_ref" "$selected_file" ||
        worker_failure "worker completed $completed_ref instead of selected unit $(repo_relative_ref "$selected_file") in iteration $ITERATION"
      verify_completed_ref_closed "$completed_ref" ||
        worker_failure "worker reported $result_status but $completed_ref is not closed (${COMPLETED_REF_STATUS:-no status marker}) in iteration $ITERATION"
      warn_open_claims "$tickets_after" "$completed_ref"
      reconcile_successful_result "$result_file"
    fi

    result_status="$(jq -r '.status' "$result_file")"
    completed_ref="$(jq -r '.completed_ref' "$result_file")"
    next_ref="$(jq -r '.next_ref' "$result_file")"
    SUMMARY="$(jq -r '.summary' "$result_file")"
    REASON="$(jq -r '.reason' "$result_file")"
    LAST_COMPLETED_REF="$completed_ref"
    NEXT_REF_STATE="$next_ref"
    RESULT_FILE_STATE="$RUN_DIR/last-result.json"
    cp -- "$result_file" "$RESULT_FILE_STATE" || worker_failure "could not persist worker result"
    persist_state || worker_failure "could not persist worker result state"

    announce_activity "$SUMMARY"
    [[ -z "$next_ref" ]] || announce_activity "next $next_ref"

    terminal_exit=""
    case "$result_status" in
      continue)
        if printf '%s\n' "$COMPLETED_REFS" | grep -Fxq -- "$completed_ref"; then
          worker_failure "no progress: completed_ref repeated ($completed_ref)"
        fi
        COMPLETED_REFS="${COMPLETED_REFS}${completed_ref}
"
        ;;
      complete|needs_input|blocked|failed) terminal_exit="$(terminal_exit_for_status "$result_status")" ;;
    esac

    if [[ -n "$terminal_exit" ]]; then
      transition_to_terminal "$result_status"
      persist_state || runner_failure "could not persist terminal state"
      [[ "$result_status" != "failed" || -z "$REASON" ]] || announce "$REASON"
      jq -c . "$result_file"
      return "$terminal_exit"
    fi

    ITERATION=$((ITERATION + 1))
  done

  runner_failure "maximum iterations reached without a terminal result"
}

run_autopilot() {
  mkdir -p -- "$STATE_DIR" "$RUNS_DIR" || runner_failure "could not create runner state directory: $STATE_DIR"
  acquire_runner_lock
  initialize_run
  run_autopilot_loop
}
