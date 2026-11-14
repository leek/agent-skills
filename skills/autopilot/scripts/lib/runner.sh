#!/bin/bash
# Stateful Autopilot run loop: a parallel frontier of fresh top-level worker processes, each
# build worker in its own worktree, landing on one integration branch; then one finish worker.

set -e

RUN_STAGE="build"
DISPATCH_NEEDED="true"
DRAINING="false"
LIMIT_REACHED="false"
FINISH_RAN="false"
FINISH_STATUS=""
FINISH_REASON=""
FINISH_NEXT_REF=""
FINISH_MERGED=""
RELEASED_LIST=""
BLOCKED_LIST=""
FAILED_LIST=""
QUESTIONS=""
BLOCKERS=""
FAILURE_REASON=""
CLAIM_REASON=""
TERMINAL_STATUS=""
TERMINAL_NEXT_REF=""
TERMINAL_REASON=""
TERMINAL_EXIT=0
NEXT_HEARTBEAT=0
BOARD_LINES_SEEN=0

find_skill() {
  local name="$1"
  local candidate=""
  local user_home="${HOME:-}"
  local codex_home="${CODEX_HOME:-}"
  local grok_home="${GROK_HOME:-}"
  local roots=("$REPO_ROOT/.agents/skills" "$REPO_ROOT/.claude/skills" "$REPO_ROOT/.codex/skills" "$REPO_ROOT/.grok/skills")

  roots+=("$(cd "$SKILL_DIR/.." && pwd -P)")
  if [[ -n "$user_home" ]]; then
    roots+=("$user_home/.agents/skills" "$user_home/.claude/skills")
    [[ -n "$codex_home" ]] || codex_home="$user_home/.codex"
    [[ -n "$grok_home" ]] || grok_home="$user_home/.grok"
  fi
  [[ -z "$codex_home" ]] || roots+=("$codex_home/skills")
  [[ -z "$grok_home" ]] || roots+=("$grok_home/skills")

  for candidate in "${roots[@]}"; do
    if [[ -f "$candidate/$name/SKILL.md" ]]; then
      (cd "$candidate/$name" && printf '%s/SKILL.md\n' "$(pwd -P)")
      return 0
    fi
  done
  return 1
}

resolve_workflow_skills() {
  local setup_path
  IMPLEMENT_SPEC_PATH="$(find_skill implement-spec)" || runner_failure "required skill not found: implement-spec"
  IMPLEMENT_PATH="$(find_skill implement)" || runner_failure "required skill not found: implement"
  TO_TICKETS_PATH="$(find_skill to-tickets)" || runner_failure "required skill not found: to-tickets"
  setup_path="$(find_skill setup)" || runner_failure "required skill not found: setup"
  TICKET_SH="$(dirname "$setup_path")/scripts/ticket.sh"
  [[ -f "$TICKET_SH" ]] || runner_failure "tracker script missing: $TICKET_SH"
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
  WORKERS_JSON="[]"
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

# The integration checkout, its branch, the run's notes directory (the one
# implement-spec's spec-run-state.sh names), and the main checkout that holds the worktrees.
prepare_integration() {
  local resolved origin_default common
  resolved="$(cd "$INTEGRATION_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" ||
    runner_failure "integration checkout not found: $INTEGRATION_DIR"
  INTEGRATION_DIR="$resolved"
  BRANCH="$(git -C "$INTEGRATION_DIR" branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || runner_failure "the integration checkout is on no branch: $INTEGRATION_DIR"
  origin_default="$(git -C "$INTEGRATION_DIR" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')" || true
  DEFAULT_BRANCH="${origin_default:-main}"
  if [[ "$BRANCH" == "$DEFAULT_BRANCH" || ( -z "$origin_default" && "$BRANCH" == "master" ) ]]; then
    runner_failure "the integration checkout is on $BRANCH: create the spec's integration branch first (the autopilot skill does it), then pass its checkout as --integration"
  fi
  common="$(cd "$INTEGRATION_DIR" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ||
    runner_failure "could not resolve the Git common directory"
  NOTES_DIR="$common/implement-spec/$BRANCH"
  mkdir -p -- "$NOTES_DIR/screenshots" || runner_failure "could not create the notes directory: $NOTES_DIR"
  MAIN_CHECKOUT="$(git -C "$INTEGRATION_DIR" worktree list --porcelain | sed -n '1s/^worktree //p')"
  [[ -n "$MAIN_CHECKOUT" ]] || MAIN_CHECKOUT="$REPO_ROOT"
  BASE_SHA=""
  [[ ! -f "$NOTES_DIR/base_sha" ]] || BASE_SHA="$(tr -d '[:space:]' <"$NOTES_DIR/base_sha")"
  # No worker of this root is running (the runner lock says so): a landing lock left by an
  # interrupted run is stale.
  rm -f -- "$NOTES_DIR/land.lock/owner"
  rmdir "$NOTES_DIR/land.lock" 2>/dev/null || true
  # Board lines an earlier run wrote were relayed then.
  [[ ! -f "$NOTES_DIR/board.jsonl" ]] || BOARD_LINES_SEEN="$(wc -l <"$NOTES_DIR/board.jsonl" | tr -d ' ')"
}

# The finish worker has no ticket-board tool: it appends one JSON object per board change to
# $NOTES_DIR/board.jsonl (a stage, one finding, one open entry). Each new line is announced
# as `board <json>`, and the launching session sends it to the board.
relay_board() {
  local file="$NOTES_DIR/board.jsonl" total line
  [[ -f "$file" ]] || return 0
  total="$(wc -l <"$file" | tr -d ' ')"
  [[ "$total" -gt "$BOARD_LINES_SEEN" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    announce_activity "board $line"
  done < <(sed -n "$((BOARD_LINES_SEEN + 1)),${total}p" "$file")
  BOARD_LINES_SEEN="$total"
}

clear_land_lock() {
  local ticket_branch="$1" owner=""
  [[ -f "$NOTES_DIR/land.lock/owner" ]] && owner="$(sed -n '1p' "$NOTES_DIR/land.lock/owner")"
  [[ "$owner" == "$ticket_branch" ]] || return 0
  rm -f -- "$NOTES_DIR/land.lock/owner"
  rmdir "$NOTES_DIR/land.lock" 2>/dev/null || true
}

build_prompt() {
  local cwd="$1" manifest="$2"
  printf '%s\n' \
    "You are one fresh top-level worker in an external Autopilot loop." \
    "Read and follow this worker contract completely: $WORKER_PATH" \
    "Target repository (main checkout): $MAIN_CHECKOUT" \
    "Your working directory: $cwd" \
    "Autopilot run ID: $RUN_ID" \
    "Workflow: $IMPLEMENT_SPEC_PATH" \
    "Worker manifest (JSON): $manifest" \
    "Do exactly the manifest's unit, in its mode. Your first output must be a tool call that reads the worker contract. Emit the structured result once, as your last action. continue requires a non-empty completed_ref and an empty next_ref."
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

# ---- worker slots ----------------------------------------------------------------------
# One directory per worker under $TEMP_DIR/w/<label>: <label> is the ticket number, or
# "finish". Bash 3.2 has no associative arrays, so the files are the table.

running_labels() {
  local slot
  for slot in "$TEMP_DIR"/w/*/; do
    [[ -f "${slot}pid" && ! -f "${slot}reaped" ]] || continue
    slot="${slot%/}"
    printf '%s\n' "${slot##*/}"
  done
  return 0
}

running_count() {
  running_labels | wc -l | tr -d ' '
}

worker_is_running() {
  [[ -f "$TEMP_DIR/w/$1/pid" && ! -f "$TEMP_DIR/w/$1/reaped" ]]
}

list_has() {
  [[ " $1 " == *" $2 "* ]]
}

# Rebuilds what cleanup() kills and what --status shows from the live slots.
refresh_children() {
  local label slot pid entries=""
  CHILD_PIDS=()
  CHILD_PROCESS_GROUPS=()
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    slot="$TEMP_DIR/w/$label"
    pid="$(sed -n '1p' "$slot/pid")"
    CHILD_PIDS+=("$pid" "$(sed -n '1p' "$slot/event_reader_pid")" "$(sed -n '1p' "$slot/error_reader_pid")")
    [[ ! -f "$slot/pgid" ]] || CHILD_PROCESS_GROUPS+=("$(sed -n '1p' "$slot/pgid")")
    entries="$entries$(jq -cn \
      --arg label "$label" \
      --arg mode "$(sed -n '1p' "$slot/mode")" \
      --arg pid "$pid" \
      --arg process_started "$(sed -n '1p' "$slot/process_started")" \
      --arg started_at "$(sed -n '1p' "$slot/started_at")" \
      --arg cwd "$(sed -n '1p' "$slot/cwd")" \
      '{label:$label,mode:$mode,pid:($pid|tonumber),process_started:$process_started,started_at:$started_at,cwd:$cwd}')
"
  done < <(running_labels)
  WORKERS_JSON="$(printf '%s' "$entries" | jq -sc '.')"
}

capture_reported_model() {
  local label captured changed=1
  while IFS= read -r label; do
    [[ -n "$label" && -s "$TEMP_DIR/w/$label/model" ]] || continue
    captured="$(sed -n '1p' "$TEMP_DIR/w/$label/model")"
    if [[ -n "$captured" && "$captured" != "$REPORTED_MODEL" ]]; then
      REPORTED_MODEL="$captured"
      changed=0
    fi
  done < <(running_labels)
  return "$changed"
}

# launch_worker <label> <mode> <cwd> <prompt> <ref>
launch_worker() {
  local label="$1" mode="$2" cwd="$3" prompt="$4" ref="$5"
  local slot="$TEMP_DIR/w/$label" attempt_id event_file worker_pid worker_pgid runner_pgid

  LAUNCHES=$((LAUNCHES + 1))
  ITERATION="$LAUNCHES"
  rm -rf -- "$slot"
  mkdir -p -- "$slot"
  attempt_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$-$LAUNCHES"
  event_file="$RUN_DIR/$attempt_id.$label.$PROVIDER.events.jsonl"
  touch "$event_file" "$slot/activity"
  : >"$slot/model"
  printf '%s\n' "$event_file" >"$slot/event_file"
  printf '%s\n' "$mode" >"$slot/mode"
  printf '%s\n' "$ref" >"$slot/ref"
  printf '%s\n' "$cwd" >"$slot/cwd"
  mkfifo "$slot/events.pipe" "$slot/errors.pipe"

  # The readers and the provider are forked with these set: each keeps its own copy.
  WORKER_LABEL="$label"
  WORKER_CWD="$cwd"
  WORKER_ACTIVITY_FILE="$slot/activity"
  MODEL_CAPTURE_FILE="$slot/model"

  process_event_stream "$event_file" <"$slot/events.pipe" &
  printf '%s\n' "$!" >"$slot/event_reader_pid"
  process_error_stream <"$slot/errors.pipe" &
  printf '%s\n' "$!" >"$slot/error_reader_pid"

  set -m
  (
    set +e
    "$PROVIDER_EXECUTOR" "$prompt" "$slot/result.json" "$slot/events.pipe" "$slot/errors.pipe" </dev/null
    worker_exit=$?
    printf '%s\n' "$worker_exit" >"$slot/exit"
    exit "$worker_exit"
  ) &
  worker_pid=$!
  set +m

  WORKER_LABEL=""
  WORKER_CWD=""
  WORKER_ACTIVITY_FILE=""
  MODEL_CAPTURE_FILE=""

  worker_pgid="$(ps -o pgid= -p "$worker_pid" 2>/dev/null | tr -d '[:space:]')"
  runner_pgid="$(ps -o pgid= -p "$$" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$worker_pgid" =~ ^[1-9][0-9]*$ && "$worker_pgid" != "$runner_pgid" ]]; then
    printf '%s\n' "$worker_pgid" >"$slot/pgid"
  fi
  now_epoch >"$slot/started"
  timestamp >"$slot/started_at"
  process_started_at "$worker_pid" >"$slot/process_started"
  printf '%s\n' "$worker_pid" >"$slot/pid"

  refresh_children
  RUN_PHASE="workers"
  persist_state || runner_failure "could not update worker state"
  announce_activity "worker $label started (session $LAUNCHES/$MAX_ITERATIONS, $mode, $(worker_tuning_summary))"
}

reap_workers() {
  local label pid labels=()
  while IFS= read -r label; do
    [[ -n "$label" ]] && labels+=("$label")
  done < <(running_labels)
  [[ ${labels[0]+present} ]] || return 0
  for label in "${labels[@]}"; do
    pid="$(sed -n '1p' "$TEMP_DIR/w/$label/pid")"
    if [[ -f "$TEMP_DIR/w/$label/exit" ]] || ! kill -0 "$pid" 2>/dev/null; then
      reap_worker "$label"
    fi
  done
}

reap_worker() {
  local label="$1" slot="$TEMP_DIR/w/$1" pid pgid="" reader waited=0 worker_exit=1
  pid="$(sed -n '1p' "$slot/pid")"
  [[ ! -f "$slot/exit" ]] || worker_exit="$(sed -n '1p' "$slot/exit")"
  wait "$pid" 2>/dev/null || true
  [[ ! -f "$slot/pgid" ]] || pgid="$(sed -n '1p' "$slot/pgid")"

  # The session is over. Whatever it left running (a dev server, a watcher) still holds the
  # event pipes open: end it, so the readers finish.
  [[ -z "$pgid" ]] || kill -TERM -- "-$pgid" 2>/dev/null || true
  for reader in "$(sed -n '1p' "$slot/event_reader_pid")" "$(sed -n '1p' "$slot/error_reader_pid")"; do
    while kill -0 "$reader" 2>/dev/null && [[ "$waited" -lt 50 ]]; do
      sleep 0.1
      waited=$((waited + 1))
    done
    if kill -0 "$reader" 2>/dev/null; then
      [[ -z "$pgid" ]] || kill -KILL -- "-$pgid" 2>/dev/null || true
      kill "$reader" 2>/dev/null || true
    fi
    wait "$reader" 2>/dev/null || true
  done

  if [[ -s "$slot/model" ]]; then
    REPORTED_MODEL="$(sed -n '1p' "$slot/model")"
  fi
  "$PROVIDER_RESULT_EXTRACTOR" "$(sed -n '1p' "$slot/event_file")" "$slot/result.json" || true
  touch "$slot/reaped"
  refresh_children
  [[ "$(running_count)" -gt 0 ]] || RUN_PHASE="reconciling"
  persist_state || runner_failure "could not update worker state"
  DISPATCH_NEEDED="true"
  handle_worker_result "$label" "$worker_exit"
}

# A unit that failed keeps its claim and its worktree: the next run of the same command
# resumes it. The run stops dispatching, lets the other workers land, and ends failed.
fail_unit() {
  local label="$1" reason="$2"
  FAILED_LIST="$FAILED_LIST $label"
  [[ -n "$FAILURE_REASON" ]] || FAILURE_REASON="$label: $reason"
  DRAINING="true"
  announce_activity "worker $label failed: $reason"
}

handle_worker_result() {
  local label="$1" worker_exit="$2" slot="$TEMP_DIR/w/$1" mode ref status completed reason summary next
  mode="$(sed -n '1p' "$slot/mode")"
  ref="$(sed -n '1p' "$slot/ref")"
  [[ "$mode" != "build" ]] || clear_land_lock "$BRANCH--$label"

  if [[ "$worker_exit" != "0" ]]; then
    fail_unit "$label" "the $PROVIDER worker process exited $worker_exit"
    return 0
  fi
  if ! validate_result "$slot/result.json"; then
    fail_unit "$label" "the $PROVIDER worker returned an invalid result"
    return 0
  fi
  cp -- "$slot/result.json" "$RUN_DIR/result-$label.json" || true
  status="$(jq -r '.status' "$slot/result.json")"
  completed="$(jq -r '.completed_ref' "$slot/result.json")"
  next="$(jq -r '.next_ref' "$slot/result.json")"
  reason="$(jq -r '.reason' "$slot/result.json")"
  summary="$(jq -r '.summary' "$slot/result.json")"
  announce_activity "worker $label result $status: $summary"

  if [[ "$mode" == "finish" ]]; then
    FINISH_STATUS="$status"
    FINISH_REASON="$reason"
    FINISH_NEXT_REF="$next"
    return 0
  fi

  case "$status" in
    continue|complete)
      if [[ -z "$completed" || "${completed##*/}" != "${ref##*/}" ]]; then
        fail_unit "$label" "the worker completed '${completed:-nothing}' instead of $ref"
        return 0
      fi
      if ! ticket_is_landed "$label" || ! git -C "$INTEGRATION_DIR" merge-base --is-ancestor "$BRANCH--$label" "$BRANCH" 2>/dev/null; then
        fail_unit "$label" "the worker reported $ref built, but $BRANCH--$label is not landed on $BRANCH"
        return 0
      fi
      LAST_COMPLETED_REF="$ref"
      frontier_refresh
      announce_activity "ticket $label merged ($(landed_numbers | wc -l | tr -d ' ') of $(frontier_query '[.tickets[] | select(.delivery | not)] | length') landed on $BRANCH)"
      announce_assumptions "$label"
      if [[ "$(ticket_field "$label" '.deploy_gate')" == "true" ]]; then
        announce_activity "ticket $label is a deploy gate: its dependents wait for the deploy"
      fi
      ;;
    needs_input)
      release_ticket "$ref" "autopilot $RUN_ID: needs an answer before this is built: $reason"
      RELEASED_LIST="$RELEASED_LIST $label"
      QUESTIONS="$QUESTIONS${QUESTIONS:+; }$label: $reason"
      announce_activity "question $label: $reason"
      ;;
    blocked)
      release_ticket "$ref" "autopilot $RUN_ID: blocked: $reason"
      BLOCKED_LIST="$BLOCKED_LIST $label"
      BLOCKERS="$BLOCKERS${BLOCKERS:+; }$label: $reason"
      announce_activity "ticket $label blocked: $reason"
      ;;
    failed)
      fail_unit "$label" "$reason"
      ;;
  esac
}

# A build worker that built on an assumed answer writes one `Assumed:` line per choice in
# its report. Each one is announced, so the launching session can put it to the user.
announce_assumptions() {
  local label="$1" line
  [[ -f "$NOTES_DIR/$label.md" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    line="${line#Assumed:}"
    announce_activity "ticket $label assumed: ${line# }"
  done < <(grep -E '^Assumed:' "$NOTES_DIR/$label.md" || true)
}

# ---- dispatch --------------------------------------------------------------------------

# ensure_worktree <ticket branch> <path>: prints "new" or "existing".
ensure_worktree() {
  local ticket_branch="$1" worktree="$2" current
  if [[ -d "$worktree" ]]; then
    current="$(git -C "$worktree" branch --show-current 2>/dev/null || true)"
    [[ "$current" == "$ticket_branch" ]] || return 1
    printf 'existing'
    return 0
  fi
  mkdir -p -- "$(dirname "$worktree")" || return 1
  if git -C "$MAIN_CHECKOUT" rev-parse --verify -q "refs/heads/$ticket_branch" >/dev/null; then
    git -C "$MAIN_CHECKOUT" worktree add "$worktree" "$ticket_branch" >/dev/null 2>&1 || return 1
    printf 'existing'
  else
    git -C "$MAIN_CHECKOUT" worktree add -b "$ticket_branch" "$worktree" "$BRANCH" >/dev/null 2>&1 || return 1
    printf 'new'
  fi
}

ticket_overlaps_running() {
  local number="$1" mine="$TEMP_DIR/files-$1" label
  ticket_files "$TRACKER_ROOT/$(ticket_ref "$number")" >"$mine"
  [[ -s "$mine" ]] || return 1
  while IFS= read -r label; do
    [[ -n "$label" && -s "$TEMP_DIR/w/$label/files" ]] || continue
    if [[ -n "$(comm -12 "$mine" "$TEMP_DIR/w/$label/files")" ]]; then
      return 0
    fi
  done < <(running_labels)
  return 1
}

build_manifest() {
  local number="$1" selection="$2" ref="$3" ticket_branch="$4" worktree="$5" blockers
  blockers="$(frontier_query -c --arg n "$number" --arg notes "$NOTES_DIR" \
    '[.tickets[] | select(.number == $n) | .blocked_by[] | {number: ., report: ($notes + "/" + . + ".md")}]')"
  jq -cn \
    --arg selection "$selection" \
    --arg ticket "$number" \
    --arg ticket_ref "$ref" \
    --arg ticket_file "$TRACKER_ROOT/$ref" \
    --arg spec_file "$TRACKER_ROOT/.scratch/$SPEC_SLUG/spec.md" \
    --arg decisions_dir "$TRACKER_ROOT/.scratch/$SPEC_SLUG/decisions" \
    --arg slug "$SPEC_SLUG" \
    --arg branch "$BRANCH" \
    --arg ticket_branch "$ticket_branch" \
    --arg worktree "$worktree" \
    --arg integration "$INTEGRATION_DIR" \
    --arg notes "$NOTES_DIR" \
    --arg delivery "$DELIVERY" \
    --arg land "$LAND_PATH" \
    --arg head "$(git -C "$INTEGRATION_DIR" rev-parse HEAD 2>/dev/null || true)" \
    --argjson blockers "$blockers" \
    '{
      mode: "build",
      selection: $selection,
      ticket: $ticket,
      ticket_ref: $ticket_ref,
      ticket_file: $ticket_file,
      spec_file: $spec_file,
      decisions_dir: $decisions_dir,
      slug: $slug,
      branch: $branch,
      ticket_branch: $ticket_branch,
      worktree: $worktree,
      integration: $integration,
      notes: $notes,
      report_file: ($notes + "/" + $ticket + ".md"),
      screenshots: ($notes + "/screenshots"),
      delivery: $delivery,
      land: $land,
      blockers: $blockers,
      integration_head: $head
    }'
}

# start_build_worker <number> <frontier|resume>
start_build_worker() {
  local number="$1" selection="$2" ref ticket_branch worktree worktree_state manifest
  ref="$(ticket_ref "$number")"
  if [[ "$LAUNCHES" -ge "$MAX_ITERATIONS" ]]; then
    LIMIT_REACHED="true"
    DRAINING="true"
    return 0
  fi
  if [[ "$selection" == "frontier" ]] && ! claim_ticket "$ref"; then
    BLOCKED_LIST="$BLOCKED_LIST $number"
    BLOCKERS="$BLOCKERS${BLOCKERS:+; }$number: claim refused ($CLAIM_REASON)"
    announce_activity "ticket $number not claimed ($CLAIM_REASON)"
    return 0
  fi
  ticket_branch="$BRANCH--$number"
  worktree="$MAIN_CHECKOUT/.claude/worktrees/$ticket_branch"
  if ! worktree_state="$(ensure_worktree "$ticket_branch" "$worktree")"; then
    fail_unit "$number" "could not create the worktree $worktree for $ticket_branch"
    return 0
  fi
  [[ "$worktree_state" == "new" ]] || selection="resume"
  manifest="$(build_manifest "$number" "$selection" "$ref" "$ticket_branch" "$worktree")"
  announce_activity "selected $ref ($selection, worktree $worktree)"
  launch_worker "$number" build "$worktree" "$(build_prompt "$worktree" "$manifest")" "$ref"
  ticket_files "$TRACKER_ROOT/$ref" >"$TEMP_DIR/w/$number/files"
}

unit_is_skipped() {
  list_has "$RELEASED_LIST" "$1" || list_has "$BLOCKED_LIST" "$1" || list_has "$FAILED_LIST" "$1"
}

dispatch_frontier() {
  local number own=() ready=()
  frontier_refresh
  while IFS= read -r number; do
    [[ -n "$number" ]] && own+=("$number")
  done < <(frontier_query --arg id "autopilot:$RUN_ID" \
    '.tickets[] | select(.claimed_by == $id and .derived != "closed" and (.delivery | not)) | .number')
  while IFS= read -r number; do
    [[ -n "$number" ]] && ready+=("$number")
  done < <(frontier_query '.tickets[] | select(.derived == "ready" and (.delivery | not)) | .number')

  # This run's own interrupted claims first, then the ready frontier, lowest number first.
  if [[ ${own[0]+present} ]]; then
    for number in "${own[@]}"; do
      [[ "$DRAINING" == "false" && "$(running_count)" -lt "$CONCURRENCY" ]] || return 0
      if unit_is_skipped "$number" || worker_is_running "$number" || ticket_is_landed "$number"; then
        continue
      fi
      start_build_worker "$number" resume
    done
  fi
  if [[ ${ready[0]+present} ]]; then
    for number in "${ready[@]}"; do
      [[ "$DRAINING" == "false" && "$(running_count)" -lt "$CONCURRENCY" ]] || return 0
      if unit_is_skipped "$number" || worker_is_running "$number" || ticket_is_landed "$number"; then
        continue
      fi
      ticket_waits_on_gate "$number" && continue
      if ticket_overlaps_running "$number"; then
        record_activity "ticket $number waits: its Files overlap a running ticket's"
        continue
      fi
      start_build_worker "$number" frontier
    done
  fi
}

start_finish_worker() {
  local pending="$1" delivery_ticket="$2" manifest
  if [[ "$LAUNCHES" -ge "$MAX_ITERATIONS" ]]; then
    runner_failure "maximum worker sessions reached ($MAX_ITERATIONS) before the finish worker could start"
  fi
  FINISH_RAN="true"
  FINISH_MERGED="$pending"
  RUN_STAGE="finish"
  manifest="$(jq -cn \
    --arg spec_file "$TRACKER_ROOT/.scratch/$SPEC_SLUG/spec.md" \
    --arg tracker_root "$TRACKER_ROOT" \
    --arg slug "$SPEC_SLUG" \
    --arg branch "$BRANCH" \
    --arg default_branch "$DEFAULT_BRANCH" \
    --arg integration "$INTEGRATION_DIR" \
    --arg notes "$NOTES_DIR" \
    --arg base_sha "$BASE_SHA" \
    --arg delivery "$DELIVERY" \
    --arg cleanup "$CLEANUP" \
    --arg board_file "$NOTES_DIR/board.jsonl" \
    --arg merged "$pending" \
    --arg delivery_ticket "$delivery_ticket" \
    --arg gates "$(landed_gate_numbers | paste -sd' ' -)" \
    --arg released "$QUESTIONS${QUESTIONS:+${BLOCKERS:+; }}$BLOCKERS" \
    '{
      mode: "finish",
      spec_file: $spec_file,
      tracker_root: $tracker_root,
      slug: $slug,
      branch: $branch,
      default_branch: $default_branch,
      integration: $integration,
      notes: $notes,
      base_sha: (if $base_sha == "" then null else $base_sha end),
      delivery: $delivery,
      cleanup: $cleanup,
      board_file: $board_file,
      merged: ($merged | split(" ") | map(select(. != ""))),
      delivery_ticket: (if $delivery_ticket == "" then null else $delivery_ticket end),
      deploy_gates: ($gates | split(" ") | map(select(. != ""))),
      left_open: (if $released == "" then null else $released end)
    }')"
  announce_activity "every buildable ticket is landed: starting the finish worker (review, verify, resolve, deliver as $DELIVERY)"
  launch_worker "finish" finish "$INTEGRATION_DIR" "$(build_prompt "$INTEGRATION_DIR" "$manifest")" ".scratch/$SPEC_SLUG/spec.md"
}

set_terminal() {
  TERMINAL_STATUS="$1"
  TERMINAL_NEXT_REF="$2"
  TERMINAL_REASON="$3"
}

# Nothing is running and nothing was dispatched: finish, or stop.
decide_when_idle() {
  local pending delivery_ticket=""
  if [[ -n "$FAILED_LIST" ]]; then
    set_terminal failed "" "$FAILURE_REASON"
    return 0
  fi
  if [[ "$LIMIT_REACHED" == "true" ]]; then
    runner_failure "maximum worker sessions reached ($MAX_ITERATIONS) before the spec was built"
  fi
  frontier_refresh
  if [[ -n "$RELEASED_LIST$BLOCKED_LIST" && "$FINISH_NOW" != "true" ]]; then
    if [[ -n "$RELEASED_LIST" ]]; then
      set_terminal needs_input "" "answers needed before these tickets are built: $QUESTIONS. Record each answer in the spec's decisions/ on $BRANCH, then run the same command again; add --finish-now to deliver what is landed without them."
    else
      set_terminal blocked "" "tickets that could not be built: $BLOCKERS. Unblock them and run the same command again; add --finish-now to deliver what is landed without them."
    fi
    return 0
  fi
  pending="$(merged_pending_numbers | paste -sd' ' -)"
  delivery_ticket="$(frontier_query '[.tickets[] | select(.delivery and .derived == "ready")][0].path // ""')"
  if [[ "$FINISH_RAN" != "true" && -n "$pending$delivery_ticket" ]]; then
    start_finish_worker "$pending" "$delivery_ticket"
    return 0
  fi
  tracker_idle_outcome
  set_terminal "$TRACKER_OUTCOME" "$TRACKER_NEXT_REF" "$TRACKER_REASON"
}

conclude_finish() {
  local number
  if [[ -n "$FAILED_LIST" ]]; then
    set_terminal failed "" "$FAILURE_REASON"
    return 0
  fi
  case "$FINISH_STATUS" in
    continue|complete)
      frontier_refresh
      for number in $FINISH_MERGED; do
        if [[ "$(ticket_field "$number" '.derived')" != "closed" ]]; then
          set_terminal failed "" "the finish worker reported success, but ticket $number is not closed ($(ticket_field "$number" '.status'))"
          return 0
        fi
        record_activity "ticket $number closed"
      done
      tracker_idle_outcome
      if [[ "$TRACKER_OUTCOME" != "complete" && -n "$QUESTIONS$BLOCKERS" ]]; then
        set_terminal needs_input "" "delivered without these tickets: $QUESTIONS${QUESTIONS:+${BLOCKERS:+; }}$BLOCKERS"
      else
        set_terminal "$TRACKER_OUTCOME" "$TRACKER_NEXT_REF" "${FINISH_REASON:+$FINISH_REASON; }$TRACKER_REASON"
      fi
      ;;
    needs_input|blocked|failed)
      set_terminal "$FINISH_STATUS" "$FINISH_NEXT_REF" "$FINISH_REASON"
      ;;
    *)
      set_terminal failed "" "the finish worker returned no result"
      ;;
  esac
}

emit_terminal() {
  local result_file="$TEMP_DIR/terminal.json"
  case "$TERMINAL_STATUS" in
    complete) SUMMARY="Autopilot scope is complete." ;;
    needs_input) SUMMARY="Autopilot reached a human gate." ;;
    blocked) SUMMARY="Autopilot has no autonomous frontier." ;;
    failed) SUMMARY="Autopilot stopped." ;;
    *) runner_failure "cannot terminate with status: $TERMINAL_STATUS" ;;
  esac
  REASON="$TERMINAL_REASON"
  NEXT_REF_STATE="$TERMINAL_NEXT_REF"
  jq -cn \
    --arg status "$TERMINAL_STATUS" \
    --arg completed_ref "$LAST_COMPLETED_REF" \
    --arg next_ref "$TERMINAL_NEXT_REF" \
    --arg summary "$SUMMARY" \
    --arg reason "$REASON" \
    '{status:$status,completed_ref:$completed_ref,next_ref:$next_ref,summary:$summary,reason:$reason}' >"$result_file"
  RESULT_FILE_STATE="$RUN_DIR/last-result.json"
  cp -- "$result_file" "$RESULT_FILE_STATE" || runner_failure "could not persist the terminal result"
  TERMINAL_EXIT="$(terminal_exit_for_status "$TERMINAL_STATUS")"
  transition_to_terminal "$TERMINAL_STATUS"
  persist_state || runner_failure "could not persist terminal state"
  announce_activity "$SUMMARY"
  [[ -z "$REASON" ]] || announce "$REASON"
  [[ -z "$NEXT_REF_STATE" ]] || announce_activity "next $NEXT_REF_STATE"
  jq -c . "$result_file"
}

heartbeat() {
  local now label slot started last_event age elapsed message
  if capture_reported_model; then
    persist_state || true
  fi
  now="$(now_epoch)"
  [[ "$now" -ge "$NEXT_HEARTBEAT" ]] || return 0
  NEXT_HEARTBEAT=$((now + HEARTBEAT_SECONDS))
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    slot="$TEMP_DIR/w/$label"
    started="$(sed -n '1p' "$slot/started")"
    last_event="$(file_mtime "$slot/activity")"
    age=$((now - last_event))
    elapsed=$((now - started))
    message="worker $label alive (session $LAUNCHES/$MAX_ITERATIONS, model ${REPORTED_MODEL:-$WORKER_MODEL}, effort $WORKER_EFFORT, elapsed $(format_duration "$elapsed"), last event $(format_duration "$age") ago)"
    if [[ "$age" -ge "$QUIET_SECONDS" ]]; then
      message="$message; quiet threshold reached"
    fi
    announce "$message"
  done < <(running_labels)
}

run_autopilot_loop() {
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autopilot.XXXXXX")" || runner_failure "could not create a temporary directory"
  SCHEMA_JSON="$(jq -c . "$SCHEMA_PATH")"
  mkdir -p -- "$TEMP_DIR/w"
  LAUNCHES=0

  prepare_integration
  if ! resolve_spec_scope; then
    set_terminal "$TRACKER_OUTCOME" "" "$TRACKER_REASON"
    emit_terminal
    return "$TERMINAL_EXIT"
  fi
  if ! resolve_tracker_root; then
    set_terminal "$TRACKER_OUTCOME" "" "$TRACKER_REASON"
    emit_terminal
    return "$TERMINAL_EXIT"
  fi
  persist_state || runner_failure "could not persist run state"
  announce_activity "spec $SPEC_SLUG on $BRANCH ($INTEGRATION_DIR); delivery $DELIVERY; up to $CONCURRENCY workers at once; notes $NOTES_DIR"

  NEXT_HEARTBEAT=$(( $(now_epoch) + HEARTBEAT_SECONDS ))
  while :; do
    reap_workers
    relay_board
    if [[ "$RUN_STAGE" == "build" ]]; then
      if [[ "$DRAINING" == "false" && "$DISPATCH_NEEDED" == "true" ]]; then
        DISPATCH_NEEDED="false"
        dispatch_frontier
      fi
      if [[ "$(running_count)" -eq 0 ]]; then
        decide_when_idle
      fi
    elif [[ "$(running_count)" -eq 0 ]]; then
      conclude_finish
    fi
    if [[ -n "$TERMINAL_STATUS" ]]; then
      emit_terminal
      return "$TERMINAL_EXIT"
    fi
    heartbeat
    sleep "$POLL_SECONDS"
  done
}

run_autopilot() {
  mkdir -p -- "$STATE_DIR" "$RUNS_DIR" || runner_failure "could not create runner state directory: $STATE_DIR"
  acquire_runner_lock
  initialize_run
  run_autopilot_loop
}
