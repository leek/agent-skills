#!/bin/bash
# Process identity, lock ownership, cleanup, and signal handling.

set -e

process_started_at() {
  local pid="$1"
  ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

pid_is_alive() {
  local pid="$1" expected_start="${2:-}" actual_start
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null || return 1
  [[ -z "$expected_start" ]] && return 0
  actual_start="$(process_started_at "$pid")"
  [[ -n "$actual_start" && "$actual_start" == "$expected_start" ]]
}

read_lock_owner() {
  local lock_file="$1"
  LOCK_OWNER_PID=""
  LOCK_OWNER_STARTED=""
  if [[ -f "$lock_file" ]]; then
    LOCK_OWNER_PID="$(sed -n '1p' "$lock_file")"
    LOCK_OWNER_STARTED="$(sed -n '2p' "$lock_file")"
  fi
}

# A lock directory with no recorded owner is held while it is this young: its
# owner is between `mkdir` and writing the pid file.
LOCK_PENDING_SECONDS=10

# True when the lock directory belongs to a live runner, or to one still
# recording its ownership. Sets LOCK_OWNER_PID and LOCK_OWNER_STARTED.
lock_dir_is_held() {
  local lock_dir="$1" age
  read_lock_owner "$lock_dir/pid"
  if [[ -n "$LOCK_OWNER_PID" ]]; then
    pid_is_alive "$LOCK_OWNER_PID" "$LOCK_OWNER_STARTED"
    return
  fi
  [[ -d "$lock_dir" ]] || return 1
  age=$(( $(now_epoch) - $(file_mtime "$lock_dir") ))
  [[ "$age" -lt "$LOCK_PENDING_SECONDS" ]]
}

acquire_runner_lock() {
  local stale_dir="$LOCK_DIR.stale.$$" recovery_dir="$LOCK_DIR.recover" attempt=0
  RUNNER_PROCESS_STARTED="$(process_started_at "$$")"
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    attempt=$((attempt + 1))
    [[ "$attempt" -le 100 ]] || runner_failure "could not acquire runner lock: $LOCK_DIR"
    if lock_dir_is_held "$LOCK_DIR"; then
      runner_failure "another Autopilot process is active for this root (pid ${LOCK_OWNER_PID:-not yet recorded})"
    fi
    # Stale. Only the process that creates the recovery directory may remove
    # the lock, and it checks again once it holds that directory: a recoverer
    # acting on an earlier check cannot remove a lock someone has since taken.
    if ! mkdir "$recovery_dir" 2>/dev/null; then
      if [[ $(( $(now_epoch) - $(file_mtime "$recovery_dir") )) -ge "$LOCK_PENDING_SECONDS" ]]; then
        rmdir "$recovery_dir" 2>/dev/null || true
      else
        sleep 0.1
      fi
      continue
    fi
    if lock_dir_is_held "$LOCK_DIR"; then
      rmdir "$recovery_dir" 2>/dev/null || true
      runner_failure "another Autopilot process is active for this root (pid ${LOCK_OWNER_PID:-not yet recorded})"
    fi
    if [[ -d "$LOCK_DIR" ]]; then
      # Rename aside before removing, so the stale lock disappears in one step.
      rm -f -- "$stale_dir/pid"
      rmdir "$stale_dir" 2>/dev/null || true
      if [[ -e "$stale_dir" ]] || ! mv -- "$LOCK_DIR" "$stale_dir" 2>/dev/null; then
        rmdir "$recovery_dir" 2>/dev/null || true
        runner_failure "could not recover stale runner lock: $LOCK_DIR"
      fi
      rm -f -- "$stale_dir/pid"
      rmdir "$stale_dir" 2>/dev/null || true
    fi
    rmdir "$recovery_dir" 2>/dev/null || true
  done
  LOCK_OWNED="true"
  printf '%s\n%s\n' "$$" "$RUNNER_PROCESS_STARTED" >"$LOCK_DIR/pid" || runner_failure "could not record runner lock ownership"
}

runner_failure() {
  local reason="$1"
  if [[ -n "$LOG_FILE" ]]; then
    announce "$reason"
  else
    emit_stderr "$reason"
  fi
  record_failure_state "$reason"
  json_failure "$reason"
  exit 5
}

worker_failure() {
  local reason="$1"
  announce "$reason"
  record_failure_state "$reason"
  json_failure "$reason"
  exit 4
}

# shellcheck disable=SC2329 # invoked by traps
cleanup() {
  local pid process_group attempt
  for process_group in "${CHILD_PROCESS_GROUPS[@]-}"; do
    if [[ "$process_group" =~ ^[1-9][0-9]*$ ]]; then
      kill -TERM -- "-$process_group" 2>/dev/null || true
      attempt=0
      while kill -0 -- "-$process_group" 2>/dev/null && [[ "$attempt" -lt 20 ]]; do
        sleep 0.1
        attempt=$((attempt + 1))
      done
      if kill -0 -- "-$process_group" 2>/dev/null; then
        kill -KILL -- "-$process_group" 2>/dev/null || true
        attempt=0
        while kill -0 -- "-$process_group" 2>/dev/null && [[ "$attempt" -lt 20 ]]; do
          sleep 0.1
          attempt=$((attempt + 1))
        done
      fi
    fi
  done
  for pid in "${CHILD_PIDS[@]-}"; do
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for pid in "${CHILD_PIDS[@]-}"; do
    wait "$pid" 2>/dev/null || true
  done

  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
  if [[ "$LOCK_OWNED" == "true" && -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
    rm -f -- "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

# shellcheck disable=SC2329 # invoked by traps
handle_signal() {
  local exit_code="$1" reason="Autopilot runner was interrupted."
  if [[ "$STATE_ACTIVE" == "true" && -n "$RUN_ID" ]]; then
    record_terminal_state "interrupted" "Autopilot interrupted." "$reason"
    announce "$reason"
  fi
  exit "$exit_code"
}
