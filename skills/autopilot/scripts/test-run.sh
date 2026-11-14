#!/bin/bash
# Offline end-to-end test for the Autopilot run loop (lib/runner.sh, lib/tickets.sh, land.sh).
# Runs autopilot.sh in throwaway repositories under mktemp -d with a stub provider binary
# (AUTOPILOT_CLAUDE_BIN) that plays a worker: a build worker commits one file in its
# worktree and lands it with land.sh; the finish worker resolves the landed tickets with
# ticket.sh. No agent CLI, no tmux, no network.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
set -e
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
autopilot_sh="$here/autopilot.sh"
ticket_sh="$here/../../setup/scripts/ticket.sh"
for tool in jq git python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "test-run.sh: $tool is required" >&2; exit 2; }
done

t="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$t"' EXIT

fail() {
  echo "FAIL $1" >&2
  [ ! -f "$t/err" ] || tail -n 40 "$t/err" >&2
  exit 1
}

eq() {
  [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"
}

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$t/bin" "$t/home/.claude" "$t/tmp"

# The stub worker. STUB_DIR holds its log and its running/ markers.
cat >"$t/bin/claude-stub" <<'STUB'
#!/bin/bash
set -e
prompt=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-p" ]; then prompt="$2"; shift; fi
  shift
done
manifest="$(printf '%s\n' "$prompt" | sed -n 's/^Worker manifest (JSON): //p')"
m() { printf '%s' "$manifest" | jq -r "$1"; }
result() {
  jq -cn --arg status "$1" --arg ref "$2" --arg reason "$3" \
    '{type:"result",structured_output:{status:$status,completed_ref:$ref,next_ref:"",summary:("stub " + $status),reason:$reason}}'
}
mode="$(m .mode)"
if [ "$mode" = "build" ]; then
  ticket="$(m .ticket)"
  printf 'build %s %s %s\n' "$ticket" "$(m .selection)" "$(pwd -P)" >>"$STUB_DIR/log"
  if grep -q 'ASK' "$(m .ticket_file)"; then
    result needs_input "" "which colour?"
    exit 0
  fi
  if grep -q 'CRASH' "$(m .ticket_file)"; then
    exit 7
  fi
  mkdir -p "$STUB_DIR/running"
  touch "$STUB_DIR/running/$ticket"
  ls "$STUB_DIR/running" | wc -l | tr -d ' ' >>"$STUB_DIR/concurrency"
  sleep 2
  printf '%s\n' "$ticket" >"file-$ticket.txt"
  git add -- "file-$ticket.txt"
  git commit -q -m "feat: ticket $ticket"
  rm -f "$STUB_DIR/running/$ticket"
  until LAND_WAIT_SECONDS=3 bash "$(m .land)" begin --notes "$(m .notes)" --integration "$(m .integration)" >/dev/null 2>&1; do
    sleep 1
  done
  bash "$(m .land)" finish --notes "$(m .notes)" --integration "$(m .integration)" --ticket "$ticket" >/dev/null 2>&1
  printf 'Built %s.\nAssumed: colour -> blue\n' "$ticket" >"$(m .report_file)"
  result continue "$(m .ticket_ref)" "landed"
else
  printf 'finish %s %s\n' "$(m '.merged | join(",")')" "$(pwd -P)" >>"$STUB_DIR/log"
  printf 'resolved\n' >"$STUB_DIR/body"
  printf '{"stage":"review and verify round 1"}\n' >>"$(m .board_file)"
  for n in $(m '.merged[]'); do
    for f in "$(m .tracker_root)/.scratch/$(m .slug)/tickets/$n-"*.md; do
      bash "$TICKET_SH" --root "$(m .tracker_root)" resolve "$f" --body-file "$STUB_DIR/body" >/dev/null
    done
  done
  delivery="$(m '.delivery_ticket // ""')"
  if [ -n "$delivery" ]; then
    bash "$TICKET_SH" --root "$(m .tracker_root)" resolve "$delivery" --body-file "$STUB_DIR/body" >/dev/null
  fi
  result continue "$(m .spec_file)" "delivered"
fi
STUB
chmod +x "$t/bin/claude-stub"

# ticket <repo> <NN-name> <frontmatter lines> [body]
ticket() {
  mkdir -p "$1/.scratch/foo/tickets"
  printf -- '---\ntitle: "T %s"\nstatus: ready-for-agent\nclaimed-by:\n%s---\n\n%s\n' "$2" "$3" "${4:-body}" >"$1/.scratch/foo/tickets/$2.md"
}

# new_repo <dir>: a repository on the integration branch `foo`, with a spec.
new_repo() {
  mkdir -p "$1/.scratch/foo"
  git init -q "$1"
  printf -- '---\ntitle: "Spec"\nstatus: ready-for-agent\n---\n\n# Spec\n' >"$1/.scratch/foo/spec.md"
}

commit_repo() {
  git -C "$1" add -- .scratch
  git -C "$1" commit -q -m "docs(scratch): foo"
  git -C "$1" switch -q -c foo
}

# ap <repo> <stub dir> <arguments>: stdout is the script's JSON; stderr goes to $t/err.
ap() {
  local repo="$1" stub_dir="$2"
  shift 2
  mkdir -p "$stub_dir"
  (
    cd "$repo"
    env -u AUTOPILOT_MODEL -u AUTOPILOT_EFFORT -u AUTOPILOT_TMUX_CHILD -u AUTOPILOT_TMUX_ENV_FILE \
      HOME="$t/home" CLAUDE_CONFIG_DIR="$t/home/.claude" TMPDIR="$t/tmp" \
      AUTOPILOT_CLAUDE_BIN="$t/bin/claude-stub" AUTOPILOT_POLL_SECONDS=1 \
      STUB_DIR="$stub_dir" TICKET_SH="$ticket_sh" \
      bash "$autopilot_sh" "$@" 2>"$t/err"
  )
}

derived() {
  bash "$ticket_sh" --root "$1" frontier foo | jq -r --arg n "$2" '.tickets[] | select(.number == $n) | .derived'
}

# ---- a parallel frontier, a dependent, a delivery ticket, one finish --------------------
r="$t/a"
new_repo "$r"
ticket "$r" 01-a $'blocked-by: []\n'
ticket "$r" 02-b $'blocked-by: []\n'
ticket "$r" 03-c $'blocked-by: ["01", "02"]\n'
ticket "$r" 04-ship $'blocked-by: ["01", "02", "03"]\ndelivery: true\n'
commit_repo "$r"

status=0
out="$(ap "$r" "$t/a-stub" --provider claude --root .scratch/foo/spec.md)" || status=$?
eq "run exit" "$status" 0
eq "run status" "$(printf '%s' "$out" | jq -r '.status')" "complete"
eq "workers at once" "$(sort -n "$t/a-stub/concurrency" | tail -n 1)" "2"
eq "sessions" "$(cut -d' ' -f1,2 "$t/a-stub/log" | sort | paste -sd, -)" "build 01,build 02,build 03,finish 01,02,03"
[ "$(sed -n '3p' "$t/a-stub/log" | cut -d' ' -f1,2)" = "build 03" ] || fail "03 did not wait for its blockers: $(cat "$t/a-stub/log")"
echo "ok the ready frontier builds in parallel and a dependent waits for its blockers"

eq "build worktree" "$(sed -n '1p' "$t/a-stub/log" | cut -d' ' -f4 | sed 's|--0[12]$||')" "$r/.claude/worktrees/foo"
eq "finish runs in the integration checkout" "$(grep '^finish' "$t/a-stub/log" | cut -d' ' -f3)" "$r"
for n in 01 02 03; do
  [ -f "$r/file-$n.txt" ] || fail "ticket $n is not on the integration branch"
  eq "ticket $n" "$(derived "$r" "$n")" "closed"
done
eq "delivery ticket" "$(derived "$r" 04)" "closed"
eq "ticket merges on the integration branch" "$(git -C "$r" rev-list --first-parent --merges --count foo)" "3"
grep -q 'ticket 01 assumed: colour -> blue' "$t/err" || fail "an assumption was not announced"
grep -q 'ticket 03 merged (3 of 3' "$t/err" || fail "the last merge was not announced"
grep -q 'Autopilot: board {"stage":"review and verify round 1"}' "$t/err" || fail "the finish worker's board line was not relayed"
echo "ok every ticket lands on the integration branch and the finish worker closes them"

state="$(ap "$r" "$t/a-stub" --status --root .scratch/foo)"
eq "status by directory root" "$(printf '%s' "$state" | jq -r '[.status, .branch, .delivery, (.concurrency | tostring), (.workers | length | tostring)] | join(" ")')" "complete foo pr 5 0"
echo "ok --status reports the branch, delivery, concurrency and live workers"

# ---- a question releases one ticket and the rest keeps building -------------------------
r="$t/b"
new_repo "$r"
ticket "$r" 01-a $'blocked-by: []\n'
ticket "$r" 02-b $'blocked-by: []\n' "ASK"
ticket "$r" 03-c $'blocked-by: ["02"]\n'
commit_repo "$r"

status=0
out="$(ap "$r" "$t/b-stub" --provider claude --root .scratch/foo --concurrency 1)" || status=$?
eq "question exit" "$status" 2
case "$(printf '%s' "$out" | jq -r '.reason')" in
  *"02: which colour?"*) ;;
  *) fail "question reason: $out" ;;
esac
eq "one at a time" "$(sort -n "$t/b-stub/concurrency" | tail -n 1)" "1"
eq "released ticket" "$(derived "$r" 02)" "ready"
[ -f "$r/file-01.txt" ] || fail "the independent ticket was not built"
if grep -q '^finish' "$t/b-stub/log"; then
  fail "the finish worker ran while a question was open"
fi
grep -q 'question 02: which colour?' "$t/err" || fail "the question was not announced"
echo "ok a question releases its ticket, the rest builds, and the run stops before finishing"

# The answer arrives: the same command builds what is left, then finishes once.
ticket "$r" 02-b $'blocked-by: []\n' "answered"
status=0
out="$(ap "$r" "$t/b-stub" --provider claude --root .scratch/foo --concurrency 1)" || status=$?
eq "rerun exit" "$status" 0
eq "rerun sessions" "$(sed -n '3,$p' "$t/b-stub/log" | cut -d' ' -f1,2,3 | sed "s| $r\$||" | paste -sd, -)" "build 02 resume,build 03 frontier,finish 01,02,03"
eq "rerun closes everything" "$(bash "$ticket_sh" --root "$r" frontier foo | jq -r '.counts.open')" "0"
echo "ok the same command resumes: the released ticket reuses its worktree"

# ---- tickets that name the same file never build at once --------------------------------
r="$t/c"
new_repo "$r"
ticket "$r" 01-a $'blocked-by: []\n' $'## Files\n\n- `app/One.php`\n- `app/Shared.php`'
ticket "$r" 02-b $'blocked-by: []\n' $'## Files\n\n- `app/Shared.php`'
commit_repo "$r"
status=0
ap "$r" "$t/c-stub" --provider claude --root .scratch/foo >/dev/null || status=$?
eq "overlap exit" "$status" 0
eq "overlap workers at once" "$(sort -n "$t/c-stub/concurrency" | tail -n 1)" "1"
echo "ok tickets whose Files overlap build one after the other"

# ---- a crashed worker keeps its claim and fails the run after the others land -----------
r="$t/d"
new_repo "$r"
ticket "$r" 01-a $'blocked-by: []\n' "CRASH"
ticket "$r" 02-b $'blocked-by: []\n'
commit_repo "$r"
status=0
out="$(ap "$r" "$t/d-stub" --provider claude --root .scratch/foo)" || status=$?
eq "crash exit" "$status" 4
eq "crashed ticket keeps its claim" "$(derived "$r" 01)" "claimed"
[ -f "$r/file-02.txt" ] || fail "the other worker did not land"
if grep -q '^finish' "$t/d-stub/log"; then
  fail "the finish worker ran after a failure"
fi
echo "ok a failed worker keeps its claim, the others land, and the run ends failed"

# ---- the integration branch in its own worktree: the spec is only on that branch --------
r="$t/w"
mkdir -p "$r"
git init -q "$r"
printf 'readme\n' >"$r/README.md"
git -C "$r" add -- README.md
git -C "$r" commit -q -m init
i="$r/.claude/worktrees/foo"
git -C "$r" worktree add -q -b foo "$i"
mkdir -p "$i/.scratch/foo"
printf -- '---\ntitle: "Spec"\nstatus: ready-for-agent\n---\n\n# Spec\n' >"$i/.scratch/foo/spec.md"
ticket "$i" 01-a $'blocked-by: []\n'
git -C "$i" add -- .scratch
git -C "$i" commit -q -m "docs(scratch): foo"
main_branch="$(git -C "$r" branch --show-current)"
status=0
out="$(ap "$r" "$t/w-stub" --provider claude --root .scratch/foo --integration .claude/worktrees/foo --delivery branch --cleanup auto)" || status=$?
eq "worktree run exit" "$status" 0
eq "worktree build directory" "$(sed -n '1p' "$t/w-stub/log" | cut -d' ' -f4)" "$r/.claude/worktrees/foo--01"
eq "worktree finish directory" "$(grep '^finish' "$t/w-stub/log" | cut -d' ' -f3)" "$i"
eq "worktree ticket" "$(derived "$i" 01)" "closed"
[ -f "$i/file-01.txt" ] || fail "the ticket did not land in the integration worktree"
[ ! -e "$r/file-01.txt" ] || fail "the ticket landed in the main checkout"
eq "main checkout branch" "$(git -C "$r" branch --show-current)" "$main_branch"
eq "worktree status" "$(ap "$r" "$t/w-stub" --status --root .scratch/foo/spec.md | jq -r '[.status, .delivery, .cleanup, .integration] | join(" ")')" "complete branch auto $i"
echo "ok an integration worktree is the tracker and the landing place; the main checkout stays put"

# ---- refusals before any worker ----------------------------------------------------------
r="$t/e"
new_repo "$r"
ticket "$r" 01-a $'blocked-by: []\n'
git -C "$r" add -- .scratch
git -C "$r" commit -q -m "docs(scratch): foo"
default_branch="$(git -C "$r" branch --show-current)"
if [ "$default_branch" = "main" ] || [ "$default_branch" = "master" ]; then
  status=0
  out="$(ap "$r" "$t/e-stub" --provider claude --root .scratch/foo)" || status=$?
  eq "default branch exit" "$status" 5
  case "$(printf '%s' "$out" | jq -r '.reason')" in
    "the integration checkout is on $default_branch:"*) ;;
    *) fail "default branch reason: $out" ;;
  esac
fi
git -C "$r" switch -q -c foo
status=0
out="$(ap "$r" "$t/e-stub" --provider claude --root .scratch/foo/tickets/01-a.md)" || status=$?
eq "ticket root exit" "$status" 3
case "$(printf '%s' "$out" | jq -r '.reason')" in
  "autopilot takes a spec"*) ;;
  *) fail "ticket root reason: $out" ;;
esac
[ ! -e "$t/e-stub/log" ] || fail "a worker started for a refused root"
echo "ok the default branch and a non-spec root are refused before any worker"
