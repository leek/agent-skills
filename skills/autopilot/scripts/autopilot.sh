#!/bin/bash
# Build one spec with fresh top-level Claude Code, Codex, or Grok processes: a parallel
# frontier of build workers, each in its own worktree, landing on one integration branch,
# then one finish worker that reviews, verifies, resolves, and delivers.
# Human-readable progress goes to stderr; terminal results and status use JSON on stdout.

set -euo pipefail
umask 077

PROVIDER=""
ROOT_REF=""
REPO_DIR="$(pwd)"
MAX_ITERATIONS="${AUTOPILOT_MAX_ITERATIONS:-50}"
CONCURRENCY="${AUTOPILOT_CONCURRENCY:-5}"
INTEGRATION_DIR=""
DELIVERY="pr"
CLEANUP="list"
FINISH_NOW="false"
HEARTBEAT_SECONDS="${AUTOPILOT_HEARTBEAT_SECONDS:-300}"
QUIET_SECONDS=""
POLL_SECONDS="${AUTOPILOT_POLL_SECONDS:-5}"
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
BRANCH=""
DEFAULT_BRANCH=""
NOTES_DIR=""
MAIN_CHECKOUT=""
BASE_SHA=""
LAUNCHES=0
WORKERS_JSON="[]"
WORKER_LABEL=""
WORKER_CWD=""
WORKER_ACTIVITY_FILE=""

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
RUNNER_PROCESS_STARTED=""
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
LAND_PATH="$SCRIPT_DIR/land.sh"
GIT_DIR=""
IMPLEMENT_SPEC_PATH=""
IMPLEMENT_PATH=""
TO_TICKETS_PATH=""
TICKET_SH=""
SCHEMA_JSON=""

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
  autopilot.sh --provider <claude|codex|grok> --root <spec> --integration <path> [options]
  autopilot.sh --status --root <spec> [--repo <path>]
  autopilot.sh --follow --root <spec> [--repo <path>]
  autopilot.sh --history --root <spec> [--repo <path>]
  autopilot.sh --wait --root <spec> [--repo <path>]    # block until terminal; exit = run status

<spec> is .scratch/<slug>/spec.md (or its directory). Its tickets must exist, and its
integration branch must be checked out at --integration: the autopilot skill does both
before it starts this script.

Run options:
  --repo <path>         Target Git repository (default: current directory)
  --integration <path>  Checkout that has the integration branch checked out (default:
                        --repo). Never the default branch.
  --delivery <shape>    pr (default), stack (stacked PRs), or branch (push, no PR)
  --concurrency <n>     Build workers at once (default: 5; AUTOPILOT_CONCURRENCY)
  --cleanup <auto|list> What the finish worker does with leftovers: remove them, or
                        list them for the user (default: list)
  --finish-now          Deliver what is landed without the tickets a worker released
  --max-iterations <n>  Worker-session limit for this invocation (default: 50)
  --model <name>        Model for every worker session (default: provider config)
  --effort <level>      Reasoning effort for every worker session
                        claude: low|medium|high|xhigh|max
                        codex/grok: none|minimal|low|medium|high|xhigh|max
  --log-file <path>     Mirror the durable human-readable log to this path
  --tmux                Start the run in a detached tmux session
  -h, --help            Show this help

Each ready ticket gets a build worker in <main checkout>/.claude/worktrees/<branch>--<NN>
on the branch <branch>--<NN>; a ticket whose Files overlap a running ticket's waits. A
worker lands its branch with land.sh, one at a time. When nothing more can be built, one
finish worker runs in the integration checkout. Run notes (reports, landed/, the landing
lock, screenshots) are in <git-common-dir>/implement-spec/<branch>.

Autopilot writes raw provider events and a human-readable log under the target
repository's Git directory. Heartbeats default to every five minutes. Set
AUTOPILOT_HEARTBEAT_SECONDS to a positive number of seconds to change them.
AUTOPILOT_MODEL and AUTOPILOT_EFFORT are the environment equivalents of --model
and --effort. Every run reports the model and effort its worker sessions use: at
run start, per worker, in each heartbeat, and in --status (model, model_source,
effort, effort_source, reported_model). A source is "requested" (flag or env),
"settings" (Claude Code settings chain: model, effortLevel; honors CLAUDE_CONFIG_DIR),
"config" ($CODEX_HOME/config.toml: model, model_reasoning_effort; $GROK_HOME/config.toml:
[models].default, [models].default_reasoning_effort), or "provider default". Claude
and Grok workers also report the model the session resolved (reported_model),
announced when it differs from the requested one.

Output:
  run        progress on stderr; one terminal result object on stdout
  --status   one state object ({"status":"none",...} and exit 1 when no run exists);
             "workers" lists the live worker sessions
  --history  an array of retained states for the root
  --tmux     one launch object (status, follow and tmux attach commands); read the
             exact terminal result from the result_file in --status
  --follow   the human-readable log ("<timestamp> Autopilot: <message>") until the
             run ends
  --wait     the final state object once the run leaves "running"

Progress lines to watch for ("<timestamp> Autopilot: <message>"):
  selected <ticket> (...)            a build worker was dispatched
  worker <NN> started|alive|result   worker lifecycle; <NN> is "finish" for the last one
  ticket <NN> merged (k of n ...)    the ticket landed on the integration branch
  ticket <NN> assumed: <choice>      it was built on an assumed answer: confirm it
  question <NN>: <text>              it needs an answer; the ticket was released
  ticket <NN> blocked: <text>        it could not be built; the ticket was released
  worker <NN> failed: <text>         the run stops dispatching and ends failed
  board <json>                       a ticket-board change from the finish worker (a review
                                     stage, a finding, an open entry): send it to the board

Exit codes: 0 complete, 2 needs input, 3 blocked, 4 worker failure,
  5 runner/configuration failure, 129 hangup, 130 interrupted, 143 terminated.
  --wait exits with the run's terminal code.
EOF
}

set_mode() {
  local requested="$1"
  [[ "$MODE" == "run" ]] || runner_failure "--status, --follow, --wait, and --history are mutually exclusive"
  MODE="$requested"
}

trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

load_tmux_environment

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
    --integration)
      [[ $# -ge 2 ]] || runner_failure "--integration requires a value"
      INTEGRATION_DIR="$2"
      shift 2
      ;;
    --delivery)
      [[ $# -ge 2 ]] || runner_failure "--delivery requires a value"
      DELIVERY="$2"
      shift 2
      ;;
    --concurrency)
      [[ $# -ge 2 ]] || runner_failure "--concurrency requires a value"
      CONCURRENCY="$2"
      shift 2
      ;;
    --cleanup)
      [[ $# -ge 2 ]] || runner_failure "--cleanup requires a value"
      CLEANUP="$2"
      shift 2
      ;;
    --finish-now)
      FINISH_NOW="true"
      shift
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
    --wait)
      set_mode "wait"
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
  [[ "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]] || runner_failure "--concurrency must be a positive integer"
  [[ "$DELIVERY" =~ ^(pr|stack|branch)$ ]] || runner_failure "--delivery must be pr, stack, or branch"
  [[ "$CLEANUP" =~ ^(auto|list)$ ]] || runner_failure "--cleanup must be auto or list"
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

ROOT_REF="$(canonical_root_ref "$ROOT_REF")" || runner_failure "could not resolve root: $ROOT_REF"
# A spec's directory names its spec: one root, one run, however it is spelled. The
# directory may be missing here when the spec lives only on the integration branch.
if [[ -d "$ROOT_REF" && -f "$ROOT_REF/spec.md" ]] || [[ ! -e "$ROOT_REF" && "$(basename "$(dirname "$ROOT_REF")")" == ".scratch" ]]; then
  ROOT_REF="$ROOT_REF/spec.md"
fi
[[ -n "$INTEGRATION_DIR" ]] || INTEGRATION_DIR="$REPO_ROOT"

GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || runner_failure "could not resolve the repository Git directory"
resolve_state_paths

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
  wait)
    wait_for_run
    exit $?
    ;;
esac

[[ -f "$WORKER_PATH" ]] || runner_failure "worker contract missing: $WORKER_PATH"
[[ -f "$SCHEMA_PATH" ]] || runner_failure "result schema missing: $SCHEMA_PATH"
[[ -f "$LAND_PATH" ]] || runner_failure "landing script missing: $LAND_PATH"
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
