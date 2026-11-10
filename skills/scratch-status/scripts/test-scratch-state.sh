#!/bin/bash
# Offline test for scratch-state.sh: pick order, frontmatter comments, the closed
# vocabulary, and the --root / --no-commits options. Fixtures live under mktemp -d.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
# The rows marked "pinned" are the same files and answers as hooks/mods/scratch-scan.test.ts
# (`unblock`, `comments`, `numeric`): change both together.
set -e
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
state_sh="$here/scratch-state.sh"
command -v jq >/dev/null 2>&1 || { echo "test-scratch-state.sh: jq is required" >&2; exit 2; }

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT

# A `gh` that records every call: --no-commits must never reach it.
mkdir -p "$t/bin"
printf '#!/bin/bash\necho called >> "%s/gh-called"\nexit 1\n' "$t" >"$t/bin/gh"
chmod +x "$t/bin/gh"
PATH="$t/bin:$PATH"
export PATH

fail() {
  echo "FAIL $1" >&2
  exit 1
}

eq() {
  [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"
}

# md <file> <status> [extra frontmatter lines]
md() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\ntitle: T\nstatus: %s\n%s---\n\nbody\n' "$2" "${3:-}" >"$1"
}

# effort <json> <slug> <jq filter on the effort>
effort() {
  printf '%s' "$1" | jq -c --arg slug "$2" ".efforts[] | select(.slug == \$slug) | $3"
}

r="$t/repo"
s="$r/.scratch"
# pinned: unblock
md "$s/unblock/spec.md" ready-for-agent
md "$s/unblock/tickets/01-a.md" ready-for-agent
md "$s/unblock/tickets/02-b.md" ready-for-agent
md "$s/unblock/tickets/03-c.md" ready-for-agent $'blocked-by: [02]\n'
md "$s/unblock/tickets/04-d.md" ready-for-agent $'blocked-by: [02]\n'
# pinned: comments
md "$s/comments/tickets/01-a.md" 'closed # shipped'
md "$s/comments/tickets/02-b.md" ready-for-agent $'claimed-by: ann-1 # since Monday\n'
md "$s/comments/tickets/03-c.md" ready-for-agent $'claimed-by: # nobody\nblocked-by: [01] # see [02]\n'
md "$s/comments/tickets/04-d.md" ready-for-agent $'blocked-by: 02 # waits\n'
md "$s/comments/tickets/05-e.md" ready-for-agent $'blocked-by:\n  - 02 # waits\n'
# pinned: numeric
md "$s/numeric/tickets/10-j.md" ready-for-agent
md "$s/numeric/tickets/9-i.md" ready-for-agent
# A quoted value keeps its #, and the extra fields ticket.sh reads.
md "$s/quoted/tickets/01-a.md" ready-for-agent $'type: task\ndeploy-gate: true\n'
printf -- '---\ntitle: "Fix #12: the queue" # a note\nstatus: "closed"\n---\n' >"$s/quoted/tickets/02-b.md"
# A closed ticket citing a commit that exists nowhere.
mkdir -p "$s/cited/tickets"
printf -- '---\ntitle: T\nstatus: closed\n---\n## Resolution\ndeadbeef1\n' >"$s/cited/tickets/01-a.md"

out="$(bash "$state_sh" --root "$r" --no-commits)"

eq "unblock next" "$(effort "$out" unblock '.next')" '"/implement .scratch/unblock/tickets/01-a.md"'
eq "unblock why" "$(effort "$out" unblock '.next_why')" '"lowest-numbered ready ticket (01)"'
eq "unblock frontier" "$(effort "$out" unblock '.frontier')" '["tickets/01-a.md","tickets/02-b.md"]'
eq "unblock also" "$(effort "$out" unblock '.also[1]')" '"other ready tickets: 02"'
echo "ok next is the lowest-numbered ready ticket, not the most-unblocking one"

md "$s/unblock/tickets/01-a.md" closed
again="$(bash "$state_sh" --root "$r" --no-commits unblock)"
eq "unblock count" "$(effort "$again" unblock '[.next, .next_why]')" \
  '["/implement .scratch/unblock/tickets/02-b.md","lowest-numbered ready ticket (02), unblocks 2"]'
echo "ok next_why carries the unblock count as information"

eq "numeric frontier" "$(effort "$out" numeric '[.frontier, .next]')" \
  '[["tickets/9-i.md","tickets/10-j.md"],"/implement .scratch/numeric/tickets/9-i.md"]'
echo "ok lowest number first is numeric: 9 before 10"

eq "comments rows" "$(effort "$out" comments '[.tickets[] | [.status, .claimed_by, .blocked_by, .derived_status]]')" \
  '[["closed","",[],"closed"],["ready-for-agent","ann-1",[],"in progress"],["ready-for-agent","",["01"],"ready"],["ready-for-agent","",["02"],"blocked"],["ready-for-agent","",["02"],"blocked"]]'
eq "comments next" "$(effort "$out" comments '[.frontier, .next]')" \
  '[["tickets/03-c.md"],"/implement .scratch/comments/tickets/03-c.md"]'
eq "quoted title" "$(effort "$out" quoted '.tickets[1] | [.title, .status]')" '["Fix #12: the queue","closed"]'
echo "ok an unquoted trailing comment is dropped from every field; a quoted # stays"

eq "new fields" "$(effort "$out" quoted '.tickets[0] | [.type, .deploy_gate, (.last_change_ts | type)]')" '["task",true,"number"]'
eq "vocabulary" "$(printf '%s' "$out" | jq -c '.vocabulary')" \
  '{"closed":["closed","declined","done","duplicate","resolved","wontfix"],"wontfix":["declined","duplicate","wontfix"],"roles":{"needs-triage":"needs-triage","needs-info":"needs-info","ready-for-agent":"ready-for-agent","ready-for-human":"ready-for-human","wontfix":"wontfix"}}'
echo "ok items carry type, deploy_gate, last_change_ts; the vocabulary is printed"

mkdir -p "$r/.agents"
printf '| Role | Status | Meaning |\n| `wontfix` | `not-planned` | x |\n| `ready-for-agent` | `afk-ready` | x |\n' >"$r/.agents/triage-labels.md"
md "$s/shut/tickets/01-a.md" not-planned
md "$s/shut/tickets/02-b.md" duplicate
md "$s/shut/tickets/03-c.md" declined
md "$s/shut/tickets/04-d.md" 'done'
md "$s/shut/tickets/05-e.md" resolved
md "$s/shut/tickets/06-f.md" wontfix
custom="$(bash "$state_sh" --root "$r" --no-commits shut)"
eq "closed words" "$(effort "$custom" shut '[.state, ([.tickets[] | .wontfix] | map(select(.)) | length)]')" '["done",4]'
eq "custom roles" "$(printf '%s' "$custom" | jq -c '[.vocabulary.roles["ready-for-agent"], (.vocabulary.closed | index("not-planned") != null)]')" '["afk-ready",true]'
echo "ok every closed word and the repo's wontfix string count as closed"

eq "no-commits" "$(effort "$out" cited '[.state, .tickets[0].commits]')" '["done",[]]'
[ ! -e "$t/gh-called" ] || fail "--no-commits called gh"
echo "ok --no-commits skips the cited-commit check and never calls gh"

rc=0
bash "$state_sh" --root "$t/nowhere" >/dev/null 2>&1 || rc=$?
eq "bad root" "$rc" 2
rc=0
bash "$state_sh" --bogus >/dev/null 2>&1 || rc=$?
eq "bad option" "$rc" 2
mkdir -p "$t/empty"
eq "no scratch" "$(bash "$state_sh" --root "$t/empty" | jq -c '[.exists, .efforts]')" '[false,[]]'
echo "ok a bad --root or option exits 2; a root with no .scratch/ reports exists: false"
echo "test-scratch-state.sh: all cases passed"
