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

  ACTIVITY_FILE="$existing_activity"
  [[ -n "$ACTIVITY_FILE" ]] || ACTIVITY_FILE="$RUN_DIR/activity"
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
  announce "log $LOG_FILE"
  [[ -z "$LOG_MIRROR_FILE" ]] || announce "log mirror $LOG_MIRROR_FILE"
  print_observer_commands announce "$TMUX_SESSION"
}

build_prompt() {
  printf '%s\n' \
    "You are one fresh top-level worker in an external Autopilot loop." \
    "Read and follow this worker contract completely: $WORKER_PATH" \
    "Target repository: $REPO_ROOT" \
    "Root reference as a JSON string: $ROOT_JSON" \
    "Autopilot run ID: $RUN_ID" \
    "Workflow files:" \
    "- wayfinder: $WAYFINDER_PATH" \
    "- to-spec: $TO_SPEC_PATH" \
    "- to-tickets: $TO_TICKETS_PATH" \
    "- implement: $IMPLEMENT_PATH" \
    "Perform exactly one unit, reconcile current tracker state, and return only the required structured result."
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

monitor_worker() {
  local worker_pid="$1" exit_file="$2" started_epoch="$3"
  local next_heartbeat now last_event age elapsed message
  next_heartbeat=$((started_epoch + HEARTBEAT_SECONDS))

  while [[ ! -f "$exit_file" ]] && kill -0 "$worker_pid" 2>/dev/null; do
    sleep "$POLL_SECONDS"
    now="$(now_epoch)"
    if [[ "$now" -ge "$next_heartbeat" ]]; then
      last_event="$(file_mtime "$ACTIVITY_FILE")"
      age=$((now - last_event))
      elapsed=$((now - started_epoch))
      message="worker alive (iteration $ITERATION/$MAX_ITERATIONS, elapsed $(format_duration "$elapsed"), last event $(format_duration "$age") ago)"
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
  persist_state || worker_failure "could not update worker state"

  "$PROVIDER_RESULT_EXTRACTOR" "$event_file" "$result_file"
  [[ "$worker_exit" == "0" ]] || return "$worker_exit"
}

run_autopilot_loop() {
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autopilot.XXXXXX")" || runner_failure "could not create a temporary directory"
  SCHEMA_JSON="$(jq -c . "$SCHEMA_PATH")"
  ROOT_JSON="$(jq -Rn --arg value "$ROOT_REF" '$value')"

  ITERATION=1
  while [[ "$ITERATION" -le "$MAX_ITERATIONS" ]]; do
    announce_activity "iteration $ITERATION/$MAX_ITERATIONS ($PROVIDER)"
    persist_state || runner_failure "could not persist iteration state"
    local prompt result_file attempt_id event_file result_status completed_ref next_ref terminal_exit
    prompt="$(build_prompt)"
    result_file="$TEMP_DIR/result-$ITERATION.json"
    attempt_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$-$ITERATION"
    event_file="$RUN_DIR/$attempt_id.$PROVIDER.events.jsonl"
    touch "$event_file"

    if ! run_worker "$prompt" "$result_file" "$event_file"; then
      worker_failure "$PROVIDER worker process failed in iteration $ITERATION"
    fi
    validate_result "$result_file" || worker_failure "$PROVIDER worker returned an invalid result in iteration $ITERATION"

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
        [[ -n "$completed_ref" ]] || worker_failure "continue result omitted completed_ref in iteration $ITERATION"
        if printf '%s\n' "$COMPLETED_REFS" | grep -Fxq -- "$completed_ref"; then
          worker_failure "no progress: completed_ref repeated ($completed_ref)"
        fi
        COMPLETED_REFS="${COMPLETED_REFS}${completed_ref}
"
        ;;
      complete) terminal_exit=0 ;;
      needs_input) terminal_exit=2 ;;
      blocked) terminal_exit=3 ;;
      failed) terminal_exit=4 ;;
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
