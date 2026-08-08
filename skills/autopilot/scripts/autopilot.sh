#!/bin/bash
# Run one fresh top-level Claude Code or Codex process per pipeline unit.
# Human-readable progress goes to stderr; terminal results and status use JSON on stdout.

set -euo pipefail
umask 077

PROVIDER=""
ROOT_REF=""
REPO_DIR="$(pwd)"
MAX_ITERATIONS="${AUTOPILOT_MAX_ITERATIONS:-50}"
HEARTBEAT_SECONDS="${AUTOPILOT_HEARTBEAT_SECONDS:-300}"
QUIET_SECONDS=""
POLL_SECONDS=5
TMUX_START_TIMEOUT_SECONDS=30
MODE="run"
USE_TMUX="false"
LOG_FILE_OVERRIDE=""
REQUESTED_MODEL="${AUTOPILOT_MODEL:-}"
REQUESTED_EFFORT="${AUTOPILOT_EFFORT:-}"
MODEL_FLAG_PROVIDED="false"
EFFORT_FLAG_PROVIDED="false"
WORKER_MODEL=""
WORKER_MODEL_SOURCE=""
WORKER_EFFORT=""
WORKER_EFFORT_SOURCE=""
REPORTED_MODEL=""
MODEL_CAPTURE_FILE=""
COMPLETED_REF_STATUS=""

COMPLETED_REFS=""
TEMP_DIR=""
LOCK_DIR=""
LOCK_OWNED="false"
LOCK_OWNER_PID=""
LOCK_OWNER_STARTED=""
STATE_DIR=""
STATE_FILE=""
STATE_KEY=""
STATE_ACTIVE="false"
STATE_FIELDS=()
RUNS_DIR=""
RUN_DIR=""
RUN_ID=""
RUN_STATUS=""
RUN_PHASE=""
CREATED_AT=""
FINISHED_AT=""
SUMMARY=""
REASON=""
LAST_COMPLETED_REF=""
NEXT_REF_STATE=""
RESULT_FILE_STATE=""
ITERATION=0
RUNNER_PID_STATE=""
WORKER_PID_STATE=""
RUNNER_PROCESS_STARTED=""
WORKER_PROCESS_STARTED=""
WORKER_PROCESS_GROUP=""
WORKER_STARTED_AT=""
LOG_FILE=""
LOG_MIRROR_FILE=""
ACTIVITY_FILE=""
TMUX_SESSION="${AUTOPILOT_TMUX_SESSION:-}"
TMUX_LAUNCH_ID="${AUTOPILOT_TMUX_LAUNCH_ID:-}"
CHILD_PIDS=()
CHILD_PROCESS_GROUPS=()

PROVIDER_BIN=""
PROVIDER_BIN_PATH=""
PROVIDER_BIN_ENV_NAME=""
PROVIDER_EVENT_FORMATTER=""
PROVIDER_EXECUTOR=""
PROVIDER_RESULT_EXTRACTOR=""
PROVIDER_CONFIG_READER=""
PROVIDER_CONFIG_SOURCE=""
PROVIDER_MODEL_KEY=""
PROVIDER_EFFORT_KEY=""
PROVIDER_EFFORT_LEVELS=""

REPO_ROOT=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/autopilot.sh"
WORKER_PATH="$SKILL_DIR/references/worker.md"
SCHEMA_PATH="$SCRIPT_DIR/result-schema.json"
GIT_DIR=""
WAYFINDER_PATH=""
TO_SPEC_PATH=""
TO_TICKETS_PATH=""
IMPLEMENT_PATH=""
SCHEMA_JSON=""
ROOT_JSON=""

require_module() {
  if [[ ! -f "$1" ]]; then
    printf 'Autopilot: required module missing: %s\n' "$1" >&2
    exit 5
  fi
}

module_path="$SCRIPT_DIR/lib/output.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/output.sh
source "$module_path"
module_path="$SCRIPT_DIR/lib/state.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/state.sh
source "$module_path"
module_path="$SCRIPT_DIR/lib/process.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/process.sh
source "$module_path"
module_path="$SCRIPT_DIR/lib/observer.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/observer.sh
source "$module_path"
module_path="$SCRIPT_DIR/lib/provider.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/provider.sh
source "$module_path"
module_path="$SCRIPT_DIR/lib/tickets.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/tickets.sh
source "$module_path"
module_path="$SCRIPT_DIR/lib/tmux.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/tmux.sh
source "$module_path"
module_path="$SCRIPT_DIR/lib/runner.sh"
require_module "$module_path"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/runner.sh
source "$module_path"
unset module_path
unset -f require_module

usage() {
  cat >&2 <<'EOF'
Usage:
  autopilot.sh --provider <claude|codex> --root <ref> [options]
  autopilot.sh --status --root <ref> [--repo <path>]
  autopilot.sh --follow --root <ref> [--repo <path>]
  autopilot.sh --history --root <ref> [--repo <path>]

Run options:
  --repo <path>         Target Git repository (default: current directory)
  --max-iterations <n>  Fresh-process limit (default: 50)
  --model <name>        Model for every worker session (default: provider config)
  --effort <level>      Reasoning effort for every worker session
                        claude: low|medium|high|xhigh|max
                        codex:  none|minimal|low|medium|high|xhigh|max
  --log-file <path>     Mirror the durable human-readable log to this path
  --tmux                Start the run in a detached tmux session
  -h, --help            Show this help

Autopilot writes raw provider events and a human-readable log under the target
repository's Git directory. Heartbeats default to every five minutes. Set
AUTOPILOT_HEARTBEAT_SECONDS to a positive number of seconds to change them.
AUTOPILOT_MODEL and AUTOPILOT_EFFORT are the environment equivalents of --model
and --effort. Every run reports the model and effort its worker sessions use.
EOF
}

set_mode() {
  local requested="$1"
  [[ "$MODE" == "run" ]] || runner_failure "--status, --follow, and --history are mutually exclusive"
  MODE="$requested"
}

trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      [[ $# -ge 2 ]] || runner_failure "--provider requires a value"
      PROVIDER="$2"
      shift 2
      ;;
    --root)
      [[ $# -ge 2 ]] || runner_failure "--root requires a value"
      ROOT_REF="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || runner_failure "--repo requires a value"
      REPO_DIR="$2"
      shift 2
      ;;
    --max-iterations)
      [[ $# -ge 2 ]] || runner_failure "--max-iterations requires a value"
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || runner_failure "--model requires a value"
      REQUESTED_MODEL="$2"
      MODEL_FLAG_PROVIDED="true"
      shift 2
      ;;
    --effort)
      [[ $# -ge 2 ]] || runner_failure "--effort requires a value"
      REQUESTED_EFFORT="$2"
      EFFORT_FLAG_PROVIDED="true"
      shift 2
      ;;
    --log-file)
      [[ $# -ge 2 ]] || runner_failure "--log-file requires a value"
      LOG_FILE_OVERRIDE="$2"
      shift 2
      ;;
    --status)
      set_mode "status"
      shift
      ;;
    --follow)
      set_mode "follow"
      shift
      ;;
    --history)
      set_mode "history"
      shift
      ;;
    --tmux)
      USE_TMUX="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      runner_failure "unknown option: $1"
      ;;
  esac
done

[[ -n "$ROOT_REF" ]] || runner_failure "--root is required"
if [[ "$MODE" == "run" ]]; then
  [[ "$MAX_ITERATIONS" =~ ^[1-9][0-9]*$ ]] || runner_failure "--max-iterations must be a positive integer"
  [[ "$HEARTBEAT_SECONDS" =~ ^[1-9][0-9]*$ ]] || runner_failure "AUTOPILOT_HEARTBEAT_SECONDS must be a positive integer"
  QUIET_SECONDS=$((HEARTBEAT_SECONDS * 2))
else
  [[ "$USE_TMUX" == "false" ]] || runner_failure "--tmux is only valid when starting a run"
  [[ -z "$LOG_FILE_OVERRIDE" ]] || runner_failure "--log-file is only valid when starting a run"
  [[ "$MODEL_FLAG_PROVIDED" == "false" ]] || runner_failure "--model is only valid when starting a run"
  [[ "$EFFORT_FLAG_PROVIDED" == "false" ]] || runner_failure "--effort is only valid when starting a run"
fi
command -v jq >/dev/null 2>&1 || runner_failure "jq is required"
command -v git >/dev/null 2>&1 || runner_failure "git is required"

ORIGINAL_DIR="$(cd "$REPO_DIR" 2>/dev/null && pwd -P)" || runner_failure "repository directory not found: $REPO_DIR"
REPO_ROOT="$(git -C "$ORIGINAL_DIR" rev-parse --show-toplevel 2>/dev/null)" || runner_failure "not a Git repository: $ORIGINAL_DIR"

if [[ "$ROOT_REF" != /* && -e "$ORIGINAL_DIR/$ROOT_REF" ]]; then
  ROOT_PARENT="$(cd "$(dirname "$ORIGINAL_DIR/$ROOT_REF")" && pwd -P)"
  ROOT_REF="$ROOT_PARENT/$(basename "$ROOT_REF")"
fi

GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || runner_failure "could not resolve the repository Git directory"
STATE_DIR="$GIT_DIR/autopilot"
STATE_KEY="$(printf '%s\0%s' "$REPO_ROOT" "$ROOT_REF" | git hash-object --stdin)"
STATE_FILE="$STATE_DIR/$STATE_KEY.json"
LOCK_DIR="$STATE_DIR/$STATE_KEY.lock"
RUNS_DIR="$STATE_DIR/runs"

case "$MODE" in
  status)
    print_status
    exit 0
    ;;
  follow)
    follow_log
    exit 0
    ;;
  history)
    print_history
    exit 0
    ;;
esac

[[ -f "$WORKER_PATH" ]] || runner_failure "worker contract missing: $WORKER_PATH"
[[ -f "$SCHEMA_PATH" ]] || runner_failure "result schema missing: $SCHEMA_PATH"
jq -e . "$SCHEMA_PATH" >/dev/null 2>&1 || runner_failure "result schema is invalid JSON"
resolve_workflow_skills
configure_provider
PROVIDER_BIN_PATH="$(command -v "$PROVIDER_BIN" 2>/dev/null)" || runner_failure "$PROVIDER executable not found: $PROVIDER_BIN"
resolve_worker_tuning

if [[ "$USE_TMUX" == "true" && "${AUTOPILOT_TMUX_CHILD:-}" != "1" ]]; then
  launch_tmux
  exit 0
fi

run_autopilot
