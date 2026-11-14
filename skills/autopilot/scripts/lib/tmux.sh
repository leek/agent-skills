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

# A tmux session starts with the tmux server's environment, not the launcher's.
# These are the variables that change which executables, configuration, and
# credentials the provider CLIs resolve; the launcher's values go to the child.
TMUX_FORWARDED_VARIABLES=(
  PATH
  CLAUDE_CONFIG_DIR CODEX_HOME GROK_HOME
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_OAUTH_TOKEN
  OPENAI_API_KEY OPENAI_BASE_URL CODEX_API_KEY
  XAI_API_KEY GROK_CODE_XAI_API_KEY
)

# Values may be secrets, so they never go on a command line (`ps` shows it) or
# into the log or state: the launcher writes them to an owner-only file with the
# `printf` builtin, and the child reads the file once and removes it. A variable
# the launcher does not have is unset in the child, so the child never keeps the
# value the tmux server inherited when it started.
write_tmux_environment() {
  local env_file="$1" name
  (umask 077 && : >"$env_file") || return 1
  for name in "${TMUX_FORWARDED_VARIABLES[@]}"; do
    if [[ -n "${!name+set}" ]]; then
      printf 'export %s=%q\n' "$name" "${!name}" >>"$env_file" || return 1
    else
      printf 'unset %s\n' "$name" >>"$env_file" || return 1
    fi
  done
}

load_tmux_environment() {
  local env_file="${AUTOPILOT_TMUX_ENV_FILE:-}" load_status=0
  [[ "${AUTOPILOT_TMUX_CHILD:-}" == "1" && -n "$env_file" ]] || return 0
  unset AUTOPILOT_TMUX_ENV_FILE
  [[ -f "$env_file" && -O "$env_file" ]] || runner_failure "tmux launch environment file is missing: $env_file"
  # shellcheck disable=SC1090 # written by write_tmux_environment at launch
  source "$env_file" || load_status=$?
  rm -f -- "$env_file"
  [[ "$load_status" -eq 0 ]] || runner_failure "could not load the tmux launch environment: $env_file"
}

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
  if lock_dir_is_held "$LOCK_DIR"; then
    runner_failure "another Autopilot process is active for this root (pid ${LOCK_OWNER_PID:-not yet recorded})"
  fi
  if tmux has-session -t "$session_name" 2>/dev/null; then
    runner_failure "tmux session already exists: $session_name"
  fi

  # The EXIT trap removes TEMP_DIR, so the file cannot outlive a failed launch.
  local env_file
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autopilot.XXXXXX")" || runner_failure "could not create a temporary directory"
  env_file="$TEMP_DIR/tmux-env"
  write_tmux_environment "$env_file" || runner_failure "could not write the tmux launch environment: $env_file"

  local command_args=(
    env
    "AUTOPILOT_TMUX_CHILD=1"
    "AUTOPILOT_TMUX_ENV_FILE=$env_file"
    "AUTOPILOT_TMUX_SESSION=$session_name"
    "AUTOPILOT_TMUX_LAUNCH_ID=$launch_id"
    "AUTOPILOT_HEARTBEAT_SECONDS=$HEARTBEAT_SECONDS"
    "$PROVIDER_BIN_ENV_NAME=$PROVIDER_BIN_PATH"
    bash "$SCRIPT_PATH"
    --provider "$PROVIDER"
    --root "$ROOT_REF"
    --repo "$REPO_ROOT"
    --max-iterations "$MAX_ITERATIONS"
    --integration "$INTEGRATION_DIR"
    --delivery "$DELIVERY"
    --concurrency "$CONCURRENCY"
    --cleanup "$CLEANUP"
  )
  [[ "$FINISH_NOW" != "true" ]] || command_args+=(--finish-now)
  [[ -z "$REQUESTED_MODEL" ]] || command_args+=(--model "$REQUESTED_MODEL")
  [[ -z "$REQUESTED_EFFORT" ]] || command_args+=(--effort "$REQUESTED_EFFORT")
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
  emit_stderr "worker session $(worker_tuning_summary)"
  emit_stderr "log $log_file"
  [[ -z "$log_mirror_file" ]] || emit_stderr "log mirror $log_mirror_file"
  print_observer_commands emit_stderr "$session_name" "$tmux_alive"
  jq -cn \
    --arg status "$launch_status" \
    --arg run_id "$run_id" \
    --arg tmux_session "$session_name" \
    --arg model "$WORKER_MODEL" \
    --arg model_source "$WORKER_MODEL_SOURCE" \
    --arg effort "$WORKER_EFFORT" \
    --arg effort_source "$WORKER_EFFORT_SOURCE" \
    --arg log_file "$log_file" \
    --arg log_mirror_file "$log_mirror_file" \
    '{status:$status,run_id:$run_id,tmux_session:$tmux_session,model:$model,model_source:$model_source,effort:$effort,effort_source:$effort_source,log_file:$log_file,log_mirror_file:(if $log_mirror_file == "" then null else $log_mirror_file end)}'
}
