#!/bin/bash
# Run one fresh top-level Claude Code or Codex process per pipeline unit.
# Human-readable progress goes to stderr; the terminal result is JSON on stdout.

set -euo pipefail

PROVIDER=""
ROOT_REF=""
REPO_DIR="$(pwd)"
MAX_ITERATIONS="${AUTOPILOT_MAX_ITERATIONS:-50}"
COMPLETED_REFS=""
TEMP_DIR=""
LOCK_DIR=""
LOCK_OWNED="false"
STATE_FILE=""
RUN_ID=""

usage() {
  cat >&2 <<'EOF'
Usage: autopilot.sh --provider <claude|codex> --root <ref> [options]

Options:
  --repo <path>          Target Git repository (default: current directory)
  --max-iterations <n>  Fresh-process limit (default: 50)
  -h, --help             Show this help
EOF
}

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

runner_failure() {
  local reason="$1"
  echo "Autopilot: $reason" >&2
  json_failure "$reason"
  exit 5
}

worker_failure() {
  local reason="$1"
  echo "Autopilot: $reason" >&2
  json_failure "$reason"
  exit 4
}

# shellcheck disable=SC2329 # invoked by traps
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
  if [[ "$LOCK_OWNED" == "true" && -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
    rm -f -- "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      runner_failure "unknown option: $1"
      ;;
  esac
done

[[ "$PROVIDER" == "claude" || "$PROVIDER" == "codex" ]] || runner_failure "--provider must be claude or codex"
[[ -n "$ROOT_REF" ]] || runner_failure "--root is required"
[[ "$MAX_ITERATIONS" =~ ^[1-9][0-9]*$ ]] || runner_failure "--max-iterations must be a positive integer"
command -v jq >/dev/null 2>&1 || runner_failure "jq is required"
command -v git >/dev/null 2>&1 || runner_failure "git is required"

ORIGINAL_DIR="$(cd "$REPO_DIR" 2>/dev/null && pwd -P)" || runner_failure "repository directory not found: $REPO_DIR"
REPO_ROOT="$(git -C "$ORIGINAL_DIR" rev-parse --show-toplevel 2>/dev/null)" || runner_failure "not a Git repository: $ORIGINAL_DIR"

if [[ "$ROOT_REF" != /* && -e "$ORIGINAL_DIR/$ROOT_REF" ]]; then
  ROOT_PARENT="$(cd "$(dirname "$ORIGINAL_DIR/$ROOT_REF")" && pwd -P)"
  ROOT_REF="$ROOT_PARENT/$(basename "$ROOT_REF")"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
WORKER_PATH="$SKILL_DIR/references/worker.md"
SCHEMA_PATH="$SCRIPT_DIR/result-schema.json"

[[ -f "$WORKER_PATH" ]] || runner_failure "worker contract missing: $WORKER_PATH"
[[ -f "$SCHEMA_PATH" ]] || runner_failure "result schema missing: $SCHEMA_PATH"
jq -e . "$SCHEMA_PATH" >/dev/null 2>&1 || runner_failure "result schema is invalid JSON"

find_skill() {
  local name="$1"
  local candidate=""
  local user_home="${HOME:-}"
  local codex_home="${CODEX_HOME:-}"
  # Target-repo skill dirs first so project-local overrides shadow user-global installs.
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

WAYFINDER_PATH="$(find_skill wayfinder)" || runner_failure "required skill not found: wayfinder"
TO_SPEC_PATH="$(find_skill to-spec)" || runner_failure "required skill not found: to-spec"
TO_TICKETS_PATH="$(find_skill to-tickets)" || runner_failure "required skill not found: to-tickets"
IMPLEMENT_PATH="$(find_skill implement)" || runner_failure "required skill not found: implement"

if [[ "$PROVIDER" == "claude" ]]; then
  PROVIDER_BIN="${AUTOPILOT_CLAUDE_BIN:-claude}"
else
  PROVIDER_BIN="${AUTOPILOT_CODEX_BIN:-codex}"
fi
command -v "$PROVIDER_BIN" >/dev/null 2>&1 || runner_failure "$PROVIDER executable not found: $PROVIDER_BIN"

GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || runner_failure "could not resolve the repository Git directory"
STATE_DIR="$GIT_DIR/autopilot"
STATE_KEY="$(printf '%s\0%s' "$REPO_ROOT" "$ROOT_REF" | git hash-object --stdin)"
STATE_FILE="$STATE_DIR/$STATE_KEY.json"
LOCK_DIR="$STATE_DIR/$STATE_KEY.lock"
mkdir -p -- "$STATE_DIR" || runner_failure "could not create runner state directory: $STATE_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  EXISTING_PID=""
  [[ ! -f "$LOCK_DIR/pid" ]] || EXISTING_PID="$(sed -n '1p' "$LOCK_DIR/pid")"
  if [[ "$EXISTING_PID" =~ ^[1-9][0-9]*$ ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    runner_failure "another Autopilot process is active for this root (pid $EXISTING_PID)"
  fi
  rm -f -- "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR" 2>/dev/null || runner_failure "could not recover stale runner lock: $LOCK_DIR"
  mkdir "$LOCK_DIR" || runner_failure "could not acquire runner lock: $LOCK_DIR"
fi
LOCK_OWNED="true"
printf '%s\n' "$$" >"$LOCK_DIR/pid" || runner_failure "could not record runner lock ownership"

if [[ -f "$STATE_FILE" ]]; then
  jq -e --arg root "$ROOT_REF" --arg repo "$REPO_ROOT" \
    '.version == 1 and .root_ref == $root and .repo_root == $repo and (.run_id | type == "string" and length > 0)' \
    "$STATE_FILE" >/dev/null 2>&1 || runner_failure "runner state is invalid: $STATE_FILE"
  RUN_ID="$(jq -r '.run_id' "$STATE_FILE")"
else
  CREATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  RUN_HASH="$(printf '%s\0%s\0%s\0%s' "$REPO_ROOT" "$ROOT_REF" "$CREATED_AT" "$$-$RANDOM" | git hash-object --stdin)"
  RUN_ID="autopilot-$RUN_HASH"
  STATE_TEMP="$(mktemp "$STATE_DIR/.state.XXXXXX")" || runner_failure "could not create runner state"
  jq -cn \
    --arg run_id "$RUN_ID" \
    --arg root_ref "$ROOT_REF" \
    --arg repo_root "$REPO_ROOT" \
    --arg created_at "$CREATED_AT" \
    '{version:1,run_id:$run_id,root_ref:$root_ref,repo_root:$repo_root,created_at:$created_at}' >"$STATE_TEMP"
  mv -- "$STATE_TEMP" "$STATE_FILE"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autopilot.XXXXXX")" || runner_failure "could not create a temporary directory"
SCHEMA_JSON="$(jq -c . "$SCHEMA_PATH")"
ROOT_JSON="$(jq -Rn --arg value "$ROOT_REF" '$value')"

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

iteration=1
while [[ "$iteration" -le "$MAX_ITERATIONS" ]]; do
  echo "Autopilot: iteration $iteration/$MAX_ITERATIONS ($PROVIDER)" >&2
  PROMPT="$(build_prompt)"
  RESULT_FILE="$TEMP_DIR/result-$iteration.json"

  if [[ "$PROVIDER" == "claude" ]]; then
    RAW_FILE="$TEMP_DIR/claude-$iteration.json"
    if ! (cd "$REPO_ROOT" && "$PROVIDER_BIN" -p "$PROMPT" \
      --dangerously-skip-permissions \
      --no-session-persistence \
      --output-format json \
      --json-schema "$SCHEMA_JSON" >"$RAW_FILE"); then
      worker_failure "Claude worker process failed in iteration $iteration"
    fi
    if ! jq -e '.structured_output | type == "object"' "$RAW_FILE" >/dev/null 2>&1; then
      worker_failure "Claude worker returned no structured_output in iteration $iteration"
    fi
    jq -c '.structured_output' "$RAW_FILE" >"$RESULT_FILE"
  else
    if ! "$PROVIDER_BIN" exec --ephemeral \
      --dangerously-bypass-approvals-and-sandbox \
      --cd "$REPO_ROOT" \
      --output-schema "$SCHEMA_PATH" \
      --output-last-message "$RESULT_FILE" \
      "$PROMPT" 1>&2; then
      worker_failure "Codex worker process failed in iteration $iteration"
    fi
  fi

  validate_result "$RESULT_FILE" || worker_failure "$PROVIDER worker returned an invalid result in iteration $iteration"

  STATUS="$(jq -r '.status' "$RESULT_FILE")"
  COMPLETED_REF="$(jq -r '.completed_ref' "$RESULT_FILE")"
  NEXT_REF="$(jq -r '.next_ref' "$RESULT_FILE")"
  SUMMARY="$(jq -r '.summary' "$RESULT_FILE")"
  REASON="$(jq -r '.reason' "$RESULT_FILE")"

  echo "Autopilot: $SUMMARY" >&2
  [[ -z "$NEXT_REF" ]] || echo "Autopilot: next $NEXT_REF" >&2

  case "$STATUS" in
    continue)
      [[ -n "$COMPLETED_REF" ]] || worker_failure "continue result omitted completed_ref in iteration $iteration"
      if printf '%s\n' "$COMPLETED_REFS" | grep -Fxq -- "$COMPLETED_REF"; then
        worker_failure "no progress: completed_ref repeated ($COMPLETED_REF)"
      fi
      COMPLETED_REFS="${COMPLETED_REFS}${COMPLETED_REF}
"
      ;;
    complete)
      rm -f -- "$STATE_FILE"
      jq -c . "$RESULT_FILE"
      exit 0
      ;;
    needs_input)
      jq -c . "$RESULT_FILE"
      exit 2
      ;;
    blocked)
      jq -c . "$RESULT_FILE"
      exit 3
      ;;
    failed)
      [[ -z "$REASON" ]] || echo "Autopilot: $REASON" >&2
      jq -c . "$RESULT_FILE"
      exit 4
      ;;
  esac

  iteration=$((iteration + 1))
done

runner_failure "maximum iterations reached without a terminal result"
