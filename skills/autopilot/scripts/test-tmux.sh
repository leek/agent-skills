#!/bin/bash
# Offline test for lib/tmux.sh: the launch environment file and the lock check in
# launch_tmux. Fixtures live under mktemp -d. The lock cases source the libraries and put a
# stub `tmux` first on PATH. The end-to-end case runs autopilot.sh --tmux with a stub
# provider binary (AUTOPILOT_CLAUDE_BIN) against a private tmux server (`tmux -L <name>`,
# socket under the fixture directory, started with a clean environment); it is skipped
# when tmux is not installed. The default tmux server and the real agent CLIs are never used.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
# shellcheck disable=SC2034 # globals the sourced libraries read
set -e
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
autopilot_sh="$here/autopilot.sh"
command -v jq >/dev/null 2>&1 || { echo "test-tmux.sh: jq is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "test-tmux.sh: git is required" >&2; exit 2; }

t="$(cd "$(mktemp -d)" && pwd -P)"
real_tmux="$(command -v tmux 2>/dev/null || true)"
socket="ap$$"
server_started="false"
finish() {
  if [ "$server_started" = "true" ]; then
    TMUX_TMPDIR="$t/s" "$real_tmux" -L "$socket" kill-server 2>/dev/null || true
  fi
  rm -rf "$t"
}
trap finish EXIT

fail() {
  echo "FAIL $1" >&2
  exit 1
}

eq() {
  [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"
}

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

mkdir -p "$t/bin" "$t/stub-bin" "$t/home/.claude" "$t/tmp" "$t/s"

# --- The launch environment file -------------------------------------------------------

env_file="$t/tmux-env"
written="$(
  umask 022
  unset OPENAI_BASE_URL XAI_API_KEY
  export OPENAI_API_KEY='launcher secret $(id) "quoted"'
  source "$here/lib/output.sh"
  source "$here/lib/state.sh"
  source "$here/lib/process.sh"
  source "$here/lib/tmux.sh"
  write_tmux_environment "$env_file" 2>&1
)"
eq "write prints nothing" "$written" ""
eq "environment file mode" "$(file_mode "$env_file")" "600"
grep -qx 'unset OPENAI_BASE_URL' "$env_file" || fail "no unset line for a variable the launcher lacks"
grep -qx 'unset XAI_API_KEY' "$env_file" || fail "no unset line for XAI_API_KEY"
grep -q '^export OPENAI_API_KEY=' "$env_file" || fail "no export line for a variable the launcher has"
grep -q '^export PATH=' "$env_file" || fail "no export line for PATH"
if grep -q '^unset OPENAI_API_KEY$' "$env_file"; then
  fail "a variable the launcher has is unset"
fi
eq "one line per forwarded variable" "$(grep -c -E '^(export [A-Z_]+=|unset [A-Z_]+$)' "$env_file")" "$(wc -l <"$env_file" | tr -d ' ')"
echo "ok an unset forwarded variable becomes an unset line in a 0600 file"

loaded="$(
  export OPENAI_BASE_URL='http://stale.invalid' OPENAI_API_KEY='stale-key'
  export AUTOPILOT_TMUX_CHILD=1 AUTOPILOT_TMUX_ENV_FILE="$env_file"
  LOG_FILE=""
  STATE_ACTIVE="false"
  RUN_ID=""
  source "$here/lib/output.sh"
  source "$here/lib/state.sh"
  source "$here/lib/process.sh"
  source "$here/lib/tmux.sh"
  load_tmux_environment
  printf '%s|%s|%s' "${OPENAI_BASE_URL-__unset__}" "$OPENAI_API_KEY" "${AUTOPILOT_TMUX_ENV_FILE-__unset__}"
)"
eq "child environment" "$loaded" '__unset__|launcher secret $(id) "quoted"|__unset__'
[ ! -e "$env_file" ] || fail "the environment file outlived its one read"
echo "ok the child drops the inherited value and removes the file"

status=0
out="$(
  export AUTOPILOT_TMUX_CHILD=1 AUTOPILOT_TMUX_ENV_FILE="$t/no-such-file"
  LOG_FILE=""
  STATE_ACTIVE="false"
  RUN_ID=""
  source "$here/lib/output.sh"
  source "$here/lib/state.sh"
  source "$here/lib/process.sh"
  source "$here/lib/tmux.sh"
  load_tmux_environment 2>/dev/null
)" || status=$?
eq "missing environment file exit" "$status" 5
case "$(printf '%s' "$out" | jq -r '.reason')" in
  "tmux launch environment file is missing:"*) ;;
  *) fail "missing environment file reason: $out" ;;
esac
echo "ok a missing environment file fails the child"

# --- The lock check in launch_tmux -----------------------------------------------------

r="$t/repo"
mkdir -p "$r/.scratch/foo/tickets"
git init -q "$r"
printf -- '---\nstatus: ready-for-agent\n---\n\n# One\n' >"$r/.scratch/foo/tickets/01-a.md"

calls="$t/tmux-calls"
cat >"$t/stub-bin/tmux" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$calls"
[ "\$1" != "has-session" ] || exit 1
exit 0
EOF
chmod +x "$t/stub-bin/tmux"

lock_dir="$r/.git/autopilot/test-key.lock"
mkdir -p "$r/.git/autopilot"

# launch: launch_tmux as autopilot.sh calls it, with the stub tmux. Stdout is its JSON.
launch() {
  : >"$calls"
  (
    PATH="$t/stub-bin:$PATH"
    TMPDIR="$t/tmp"
    export PATH TMPDIR
    source "$here/lib/output.sh"
    source "$here/lib/state.sh"
    source "$here/lib/process.sh"
    source "$here/lib/tmux.sh"
    REPO_ROOT="$r"
    ROOT_REF="$r/.scratch/foo"
    STATE_KEY="test-key"
    STATE_FILE="$r/.git/autopilot/test-key.json"
    LOCK_DIR="$lock_dir"
    LOCK_OWNED="false"
    LOCK_OWNER_PID=""
    LOCK_OWNER_STARTED=""
    TEMP_DIR=""
    CHILD_PIDS=()
    CHILD_PROCESS_GROUPS=()
    LOG_FILE=""
    STATE_ACTIVE="false"
    RUN_ID=""
    TMUX_START_TIMEOUT_SECONDS=1
    HEARTBEAT_SECONDS=300
    MAX_ITERATIONS=1
    PROVIDER="claude"
    PROVIDER_BIN_ENV_NAME="AUTOPILOT_CLAUDE_BIN"
    PROVIDER_BIN_PATH="$t/bin/claude-stub"
    SCRIPT_PATH="$autopilot_sh"
    REQUESTED_MODEL=""
    REQUESTED_EFFORT=""
    LOG_FILE_OVERRIDE=""
    trap cleanup EXIT
    launch_tmux 2>/dev/null
  )
}

# expect_refused <case>: the lock stops the launch before any session starts.
expect_refused() {
  local status=0 out
  out="$(launch)" || status=$?
  eq "$1 exit" "$status" 5
  case "$(printf '%s' "$out" | jq -r '.reason')" in
    *"another Autopilot process is active"*) ;;
    *) fail "$1: not refused by the lock: $out" ;;
  esac
  if grep -q '^new-session' "$calls"; then
    fail "$1: a tmux session was started"
  fi
}

# expect_launched <case>: the lock does not stop the launch (the stub session then never
# writes state, so the launch fails on that instead).
expect_launched() {
  local status=0 out
  out="$(launch)" || status=$?
  grep -q '^new-session' "$calls" || fail "$1: no tmux session was started: $out"
  case "$(printf '%s' "$out" | jq -r '.reason')" in
    "tmux session did not create runner state"*) ;;
    *) fail "$1: unexpected result: $out" ;;
  esac
}

mkdir "$lock_dir"
expect_refused "pending lock"
case "$(launch | jq -r '.reason')" in
  *"not yet recorded"*) ;;
  *) fail "pending lock reason does not say the owner is not recorded yet" ;;
esac
echo "ok a lock being acquired (no pid yet) refuses the launch"

printf '%s\n%s\n' "$$" "$(ps -o lstart= -p "$$" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" >"$lock_dir/pid"
expect_refused "live lock"
echo "ok a lock with a live owner refuses the launch"

sleep 0 &
dead_pid=$!
wait "$dead_pid"
printf '%s\n%s\n' "$dead_pid" "Thu Jan  1 00:00:00 1970" >"$lock_dir/pid"
expect_launched "dead owner"
echo "ok a lock with a dead owner does not refuse the launch"

rm -f "$lock_dir/pid"
touch -t 202001010000 "$lock_dir"
expect_launched "stale pending lock"
rmdir "$lock_dir"
expect_launched "no lock"
echo "ok a stale ownerless lock and no lock do not refuse the launch"

# --- End to end on a private tmux server ----------------------------------------------

if [ -z "$real_tmux" ]; then
  echo "ok forwarded-variable launch on a private tmux server (skipped: tmux is not installed)"
  exit 0
fi

# The provider stub records what the worker process sees, then fails the worker.
cat >"$t/bin/claude-stub" <<EOF
#!/bin/bash
printf '%s\n%s\n%s\n' "\${OPENAI_BASE_URL-__unset__}" "\${OPENAI_API_KEY-__unset__}" "\${CODEX_HOME-__unset__}" >"$t/worker-env"
exit 1
EOF
chmod +x "$t/bin/claude-stub"

# Every tmux call the launcher and the runner make goes to the private socket.
cat >"$t/bin/tmux" <<EOF
#!/bin/bash
unset TMUX
export TMUX_TMPDIR="$t/s"
exec "$real_tmux" -L "$socket" "\$@"
EOF
chmod +x "$t/bin/tmux"

# The server starts with a clean environment that holds a stale value for two forwarded
# variables: one the launcher will not have, one the launcher will set differently.
env -i PATH="/usr/bin:/bin" HOME="$t/home" TMUX_TMPDIR="$t/s" \
  OPENAI_BASE_URL="http://stale.invalid" OPENAI_API_KEY="stale-key" CODEX_HOME="/stale/codex" \
  "$real_tmux" -L "$socket" -f /dev/null new-session -d -s keepalive 'sleep 600'
server_started="true"
case "$("$t/bin/tmux" show-environment -g OPENAI_BASE_URL)" in
  "OPENAI_BASE_URL=http://stale.invalid") ;;
  *) fail "the private tmux server does not hold the stale variable" ;;
esac

ap() {
  (
    cd "$r"
    env -u TMUX -u OPENAI_BASE_URL -u CODEX_HOME -u AUTOPILOT_MODEL -u AUTOPILOT_EFFORT \
      -u AUTOPILOT_TMUX_CHILD -u AUTOPILOT_TMUX_ENV_FILE -u AUTOPILOT_TMUX_SESSION -u AUTOPILOT_TMUX_LAUNCH_ID \
      PATH="$t/bin:$PATH" TMPDIR="$t/tmp" HOME="$t/home" CLAUDE_CONFIG_DIR="$t/home/.claude" \
      OPENAI_API_KEY="launcher-secret-value" AUTOPILOT_CLAUDE_BIN="$t/bin/claude-stub" \
      AUTOPILOT_WAIT_INTERVAL_SECONDS=1 \
      bash "$autopilot_sh" "$@"
  )
}

status=0
ap --provider claude --root .scratch/foo --tmux >"$t/launch.out" 2>"$t/launch.err" || status=$?
eq "tmux launch exit" "$status" 0
jq -e '.status == "started" or .status == "failed"' "$t/launch.out" >/dev/null || fail "launch result: $(cat "$t/launch.out")"

status=0
ap --wait --root .scratch/foo >"$t/wait.out" 2>/dev/null || status=$?
eq "run exit (the stub fails the worker)" "$status" 4
[ -f "$t/worker-env" ] || fail "the provider stub never ran"
eq "variable unset in the launcher" "$(sed -n '1p' "$t/worker-env")" "__unset__"
eq "variable set in the launcher" "$(sed -n '2p' "$t/worker-env")" "launcher-secret-value"
eq "second variable unset in the launcher" "$(sed -n '3p' "$t/worker-env")" "__unset__"
echo "ok the detached worker does not keep the tmux server's stale variables"

if grep -q -e 'launcher-secret-value' -e 'stale-key' "$t/launch.out" "$t/launch.err" "$t/wait.out"; then
  fail "a forwarded value was printed"
fi
if grep -rq -e 'launcher-secret-value' "$r/.git/autopilot"; then
  fail "a forwarded value reached the run state or log"
fi
[ -z "$(find "$t/tmp" -name tmux-env)" ] || fail "the launch environment file was left behind"
echo "ok forwarded values stay out of output, state and log, and the file is gone"
