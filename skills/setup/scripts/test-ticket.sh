#!/bin/bash
# Offline test for ticket.sh, and for its agreement with scratch-state.sh and autopilot's
# lib/tickets.sh on one shared fixture. Builds every fixture under mktemp -d.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
set -e
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
ticket_sh="$here/ticket.sh"
state_sh="$here/../../scratch-status/scripts/scratch-state.sh"
tickets_lib="$here/../../autopilot/scripts/lib/tickets.sh"
command -v jq >/dev/null 2>&1 || { echo "test-ticket.sh: jq is required" >&2; exit 2; }

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT

# No subcommand may reach the network: a `gh` that records every call sits first on PATH.
mkdir -p "$t/bin"
printf '#!/bin/bash\necho called >> "%s/gh-called"\nexit 1\n' "$t" >"$t/bin/gh"
chmod +x "$t/bin/gh"
PATH="$t/bin:$PATH"
export PATH

fail() {
  echo "FAIL $1" >&2
  exit 1
}

# eq <case> <got> <want>
eq() {
  [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"
}

# q <json> <jq filter>: the filter's result, compact.
q() {
  printf '%s' "$1" | jq -c "$2"
}

# run <root> <args...>: sets $out (stdout) and $rc.
run() {
  local root="$1"
  shift
  rc=0
  out="$(bash "$ticket_sh" --root "$root" "$@" 2>"$t/stderr")" || rc=$?
}

# ticket <file> <status> [extra frontmatter lines]: a build ticket with a fixed body.
BODY='
# 03: Sample

## What to build

Trailing spaces
	a tab, a `status: fake` line, and a fenced heading:

```markdown
## Resolution
status: built
```

- [ ] criterion
'
ticket() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\ntitle: "T"\nstatus: %s\n%s---\n%s' "$2" "${3:-}" "$BODY" >"$1"
}

# ---- fixture: one effort every reader is asked about --------------------------------------
r="$t/main"
a="$r/.scratch/auth/tickets"
ticket "$a/01-a.md" 'closed # shipped' $'claimed-by:\nblocked-by: []\n'
ticket "$a/02-b.md" wontfix
ticket "$a/03-c.md" ready-for-agent $'claimed-by:\nblocked-by: [01, 02]\ndeploy-gate: true\n'
ticket "$a/04-d.md" ready-for-agent $'claimed-by:\nblocked-by: [03]\n'
ticket "$a/05-e.md" in-progress $'claimed-by: "bo-2" # since Monday\nblocked-by: []\n'
ticket "$a/06-f.md" in-progress $'claimed-by:\n'
ticket "$a/07-g.md" ready-for-agent $'claimed-by:\nblocked-by: []\ndeploy-gate: false\n'
ticket "$a/08-ship.md" ready-for-human $'claimed-by:\nblocked-by: [01, 02]\ndelivery: true\n'
touch -t 200001010000 "$a/05-e.md"

run "$r" frontier auth
eq "frontier exit" "$rc" 0
f="$out"
eq "frontier order" "$(q "$f" '.frontier')" '["03","07"]'
eq "frontier next" "$(q "$f" '.next')" '"03"'
eq "frontier kind" "$(q "$f" '.kind')" '"tickets"'
eq "frontier numbers" "$(q "$f" '[.tickets[].number]')" '["01","02","03","04","05","06","07","08"]'
echo "ok frontier lists tickets and the ready numbers lowest first"

eq "derived states" "$(q "$f" '[.tickets[].derived]')" \
  '["closed","closed","ready","blocked","claimed","in-progress","ready","human"]'
eq "wontfix closed" "$(q "$f" '.tickets[1] | [.status, .derived]')" '["wontfix","closed"]'
eq "blocked" "$(q "$f" '.tickets[3] | [.blocked_by, .open_blockers]')" '[["03"],["03"]]'
eq "claimed" "$(q "$f" '.tickets[4].claimed_by')" '"bo-2"'
eq "in-progress no claimant" "$(q "$f" '.tickets[5] | [.status, .claimed_by]')" '["in-progress",""]'
eq "delivery human" "$(q "$f" '.tickets[7] | [.status, .delivery, .derived]')" '["ready-for-human",true,"human"]'
eq "deploy gate" "$(q "$f" '[.tickets[2].deploy_gate, .tickets[6].deploy_gate]')" '[true,false]'
eq "counts" "$(q "$f" '.counts')" \
  '{"open":6,"closed":2,"ready":2,"blocked":1,"claimed":1,"in_progress":1,"human":1}'
eq "path" "$(q "$f" '.tickets[2].path')" '".scratch/auth/tickets/03-c.md"'
echo "ok frontier derives closed, ready, blocked, claimed, in-progress, human; wontfix is closed"

eq "claim age unclaimed" "$(q "$f" '.tickets[2].claim_age_seconds')" 'null'
eq "claim age old" "$(q "$f" '.tickets[4].claim_age_seconds > 100000000')" 'true'
eq "claim age fresh" "$(q "$f" '.tickets[5].claim_age_seconds < 3600')" 'true'
echo "ok frontier reports claim_age_seconds and leaves staleness to the caller"

# ---- agreement with scratch-state.sh and autopilot's tickets.sh ---------------------------
s="$(bash "$state_sh" --root "$r" --no-commits auth)"
eq "state closed set" "$(q "$s" '[.efforts[0].tickets[] | select(.derived_status == "closed") | .number]')" \
  "$(q "$f" '[.tickets[] | select(.derived == "closed") | .number]')"
eq "state next" "$(q "$s" '.efforts[0].next')" "\"/implement $(printf '%s' "$f" | jq -r '.tickets[] | select(.number == "03") | .path')\""
eq "state frontier" "$(q "$s" '.efforts[0].frontier')" '["tickets/03-c.md","tickets/07-g.md","tickets/08-ship.md"]'
eq "state statuses" "$(q "$s" '[.efforts[0].tickets[] | [.status, .claimed_by, .blocked_by]]')" \
  "$(q "$f" '[.tickets[] | [.status, .claimed_by, (.blocked_by | map(tostring))]]')"
echo "ok scratch-state.sh gives the same closed set, statuses, claims, and next ticket"

lib_closed="$(
  REPO_ROOT="$r"
  # shellcheck source=/dev/null
  . "$tickets_lib"
  for file in "$a"/*.md; do
    read_work_item_state "$file" || true
    if work_item_is_closed "$WORK_ITEM_STATUS"; then
      basename "$file" | cut -d- -f1
    fi
  done | jq -Rsc 'split("\n")[:-1]'
)"
eq "tickets.sh closed set" "$lib_closed" "$(q "$f" '[.tickets[] | select(.derived == "closed") | .number]')"
lib_facts="$(
  REPO_ROOT="$r"
  # shellcheck source=/dev/null
  . "$tickets_lib"
  read_work_item_state "$a/05-e.md"
  printf '%s|%s|' "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM"
  read_work_item_state "$a/01-a.md"
  printf '%s|' "$WORK_ITEM_STATUS"
  work_item_is_human_gate build needs-info "" && printf 'info-gate|'
  work_item_is_human_gate build ready-for-human "" && printf 'human-gate|'
  work_item_is_human_gate build needs-triage "" && printf 'triage-gate|'
  work_item_is_human_gate build needs-input "" || printf 'no-input-gate|'
  work_item_is_closed wontfix && printf 'wontfix-closed|'
  work_item_is_closed 'closed (abc1234)' && printf 'cited-closed|'
  work_item_is_closed closing || printf 'closing-open'
)"
eq "tickets.sh facts" "$lib_facts" \
  'in-progress|bo-2|closed|info-gate|human-gate|triage-gate|no-input-gate|wontfix-closed|cited-closed|closing-open'
echo "ok autopilot tickets.sh agrees: closed set, comment stripping, needs-info gate"

# ---- claim ---------------------------------------------------------------------------------
cp "$a/03-c.md" "$t/before-claim.md"
run "$r" claim "$a/03-c.md" --as ann-1
eq "claim win exit" "$rc" 0
eq "claim win" "$(q "$out" '.')" '{"won":true,"path":".scratch/auth/tickets/03-c.md","status":"in-progress","claimed_by":"ann-1"}'
ticket "$t/expect.md" in-progress $'claimed-by: ann-1\nblocked-by: [01, 02]\ndeploy-gate: true\n'
cmp -s "$a/03-c.md" "$t/expect.md" || fail "claim changed more than status and claimed-by"
echo "ok claim wins, sets status and claimed-by, and keeps every other byte"

run "$r" claim .scratch/auth/tickets/03-c.md --as ann-1
eq "claim again exit" "$rc" 0
eq "claim again" "$(q "$out" '[.won, .claimed_by]')" '[true,"ann-1"]'
cmp -s "$a/03-c.md" "$t/expect.md" || fail "an idempotent claim rewrote the file"
echo "ok claim with the same id is a no-op success"

run "$r" claim "$a/03-c.md" --as zed-9
eq "claim lose exit" "$rc" 1
eq "claim lose" "$(q "$out" '[.won, .reason, .claimed_by, .status]')" '[false,"claimed","ann-1","in-progress"]'
cmp -s "$a/03-c.md" "$t/expect.md" || fail "a lost claim wrote the file"
echo "ok claim loses to another claimant and writes nothing"

run "$r" claim "$a/04-d.md" --as zed-9
eq "claim blocked exit" "$rc" 1
eq "claim blocked" "$(q "$out" '[.won, .reason, .open_blockers]')" '[false,"blocked",["03"]]'
run "$r" claim "$a/01-a.md" --as zed-9
eq "claim closed" "$rc $(q "$out" '.reason')" '1 "closed"'
run "$r" claim "$a/02-b.md" --as zed-9
eq "claim wontfix" "$rc $(q "$out" '.reason')" '1 "closed"'
run "$r" claim "$a/06-f.md" --as zed-9
eq "claim in-progress" "$rc $(q "$out" '[.reason, .claimed_by]')" '1 ["in-progress",""]'
echo "ok claim refuses a blocked, closed, wontfix, or unclaimed in-progress item"

# --built: a spec run closes its tickets at the end, so a blocker it already built must not
# hold the next wave. 03 is claimed and open here; 04 waits on it.
cp "$a/04-d.md" "$t/before-built.md"
run "$r" frontier auth --built 3
eq "frontier --built" "$(q "$out" '.tickets[3] | [.derived, .open_blockers]')" '["ready",[]]'
eq "frontier --built keeps status" "$(q "$out" '.tickets[2].derived')" '"claimed"'
run "$r" claim "$a/04-d.md" --as autopilot:run-1 --built 02
eq "claim --built other ticket" "$rc $(q "$out" '[.reason, .open_blockers]')" '1 ["blocked",["03"]]'
run "$r" claim "$a/04-d.md" --as autopilot:run-1 --built 02,03
eq "claim --built" "$rc $(q "$out" '[.won, .status, .claimed_by]')" '0 [true,"in-progress","autopilot:run-1"]'
run "$r" frontier auth
eq "colon id reads back" "$(q "$out" '.tickets[3].claimed_by')" '"autopilot:run-1"'
run "$r" frontier auth --built x
eq "bad --built" "$rc" 2
cp "$t/before-built.md" "$a/04-d.md"
echo "ok --built lets a run claim past blockers it built; an id may hold a colon"

run "$r" claim "$a/07-g.md"
eq "claim without --as" "$rc" 2
run "$r" claim "$a/07-g.md" --as 'bad # id'
eq "claim bad id" "$rc" 2
run "$r" claim "$a/missing.md" --as ann-1
eq "claim missing file" "$rc" 2
printf 'a loose note\n' >"$r/.scratch/auth/notes.md"
run "$r" claim "$r/.scratch/auth/notes.md" --as ann-1
eq "claim non-tracker file" "$rc" 2
run "$r" bogus
eq "unknown subcommand" "$rc" 2
echo "ok usage errors exit 2"

# A decision ticket: claimed-by only.
d="$r/.scratch/chart/decisions"
mkdir -p "$d"
printf -- '---\ntitle: "Chart"\nstatus: open\n---\n\n## Destination\n\nx\n' >"$r/.scratch/chart/map.md"
printf -- '---\ntitle: "Which queue?"\ntype: research\nstatus: open\nclaimed-by:\nblocked-by: []\n---\n\n## Question\n\nWhich queue?\n' >"$d/01-queue.md"
printf -- '---\ntitle: "Retry rule"\ntype: grilling\nstatus: open\nclaimed-by:\nblocked-by: [01]\n---\n\n## Question\n\nHow many?\n' >"$d/02-retry.md"
run "$r" frontier chart
eq "decision frontier" "$(q "$out" '[.kind, .frontier, .next, .tickets[0].type, .tickets[1].derived]')" \
  '["decisions",["01"],"01","research","blocked"]'
run "$r" claim "$d/01-queue.md" --as ann-1
eq "decision claim" "$rc $(q "$out" '[.won, .status, .claimed_by]')" '0 [true,"open","ann-1"]'
eq "decision file" "$(sed -n '2,6p' "$d/01-queue.md" | tr '\n' '|')" \
  'title: "Which queue?"|type: research|status: open|claimed-by: ann-1|blocked-by: []|'
run "$r" claim "$d/02-retry.md" --as ann-1
eq "decision blocked" "$rc $(q "$out" '.reason')" '1 "blocked"'
run "$r" release "$d/01-queue.md"
eq "decision release" "$rc $(q "$out" '.')" '0 {"path":".scratch/chart/decisions/01-queue.md","status":"open","claimed_by":""}'
echo "ok a decision ticket's claim and release leave status alone"

# ---- release -------------------------------------------------------------------------------
run "$r" release "$a/03-c.md"
eq "release exit" "$rc" 0
eq "release" "$(q "$out" '.')" '{"path":".scratch/auth/tickets/03-c.md","status":"ready-for-agent","claimed_by":""}'
cmp -s "$a/03-c.md" "$t/before-claim.md" || fail "claim then release did not restore the file byte for byte"
echo "ok release of a build ticket clears the claim and returns it to ready-for-agent"

ticket "$a/08-ship.md" ready-for-human $'claimed-by: ann-1\nblocked-by: [01, 02]\ndelivery: true\n'
run "$r" release "$a/08-ship.md" --note 'Deploy PR 12, then run pass 2.'
eq "release human" "$rc $(q "$out" '[.status, .claimed_by]')" '0 ["ready-for-human",""]'
ticket "$t/expect.md" ready-for-human $'claimed-by:\nblocked-by: [01, 02]\ndelivery: true\n'
printf '\n## Comments\n\nDeploy PR 12, then run pass 2.\n' >>"$t/expect.md"
cmp -s "$a/08-ship.md" "$t/expect.md" || fail "release --note did not append ## Comments exactly"
run "$r" release "$a/08-ship.md" --note 'Second note.'
printf '\nSecond note.\n' >>"$t/expect.md"
cmp -s "$a/08-ship.md" "$t/expect.md" || fail "a second note did not land under the existing ## Comments"
echo "ok release keeps ready-for-human and appends notes under ## Comments"

printf -- '---\ntitle: "N"\nstatus: in-progress\nclaimed-by: ann-1\n---\n\n## Comments\n\nFirst.\n\n## Files\n\n- `a.php`\n' >"$a/09-n.md"
run "$r" release "$a/09-n.md" --note 'Waits on the questionnaire.'
printf -- '---\ntitle: "N"\nstatus: ready-for-agent\nclaimed-by:\n---\n\n## Comments\n\nFirst.\n\nWaits on the questionnaire.\n\n## Files\n\n- `a.php`\n' >"$t/expect.md"
cmp -s "$a/09-n.md" "$t/expect.md" || fail "a note was not inserted at the end of a mid-file ## Comments"
run "$r" release "$a/01-a.md"
eq "release closed" "$rc $(q "$out" '.error')" '1 "closed"'
echo "ok release inserts into a mid-file ## Comments and refuses a closed item"

# The AFK-ready and wontfix strings come from the repo's triage table.
c="$t/custom"
mkdir -p "$c/.agents"
printf '| Role | Status | Meaning |\n| --- | --- | --- |\n| `ready-for-agent` | `afk-ready` | x |\n| `ready-for-human` | `hitl` | x |\n| `wontfix` | `not-planned` | x |\n' >"$c/.agents/triage-labels.md"
ticket "$c/.scratch/pay/tickets/01-a.md" not-planned
ticket "$c/.scratch/pay/tickets/02-b.md" in-progress $'claimed-by: ann-1\nblocked-by: [01]\n'
run "$c" frontier pay
eq "custom wontfix" "$(q "$out" '[.tickets[0].derived, .tickets[1].derived, .tickets[1].open_blockers]')" '["closed","claimed",[]]'
run "$c" release "$c/.scratch/pay/tickets/02-b.md"
eq "custom release" "$(q "$out" '.status')" '"afk-ready"'
# set-status takes a role's canonical name or the repo's string, and writes the repo's string.
run "$c" set-status "$c/.scratch/pay/tickets/02-b.md" ready-for-human
eq "role name mapped" "$rc $(q "$out" '.')" '0 {"path":".scratch/pay/tickets/02-b.md","status":"hitl","previous":"afk-ready"}'
eq "role name file" "$(grep -c '^status: hitl$' "$c/.scratch/pay/tickets/02-b.md")" 1
run "$c" set-status "$c/.scratch/pay/tickets/02-b.md" ready-for-agent
eq "role name back" "$rc $(q "$out" '[.status, .previous]')" '0 ["afk-ready","hitl"]'
run "$c" set-status "$c/.scratch/pay/tickets/02-b.md" hitl
eq "mapped string" "$rc $(q "$out" '[.status, .previous]')" '0 ["hitl","afk-ready"]'
run "$c" set-status "$c/.scratch/pay/tickets/02-b.md" afk-ready
run "$c" set-status "$c/.scratch/pay/tickets/02-b.md" built
eq "custom illegal" "$rc $(q "$out" '[.error, .status, .legal]')" \
  '1 ["illegal-status","afk-ready",["needs-triage","needs-info","afk-ready","hitl","not-planned","in-progress","closed"]]'
echo "ok set-status takes a role name or the repo's string and writes the repo's string"

# The repo's own ready-for-human string is the human gate.
ticket "$c/.scratch/pay/tickets/03-c.md" hitl $'claimed-by:\n'
cp "$c/.scratch/pay/tickets/03-c.md" "$t/expect.md"
run "$c" frontier pay
eq "custom human" "$(q "$out" '[.frontier, .tickets[2].derived]')" '[["02"],"human"]'
run "$c" claim "$c/.scratch/pay/tickets/03-c.md" --as ann-1
eq "custom human claim" "$rc $(q "$out" '[.won, .reason, .status]')" '1 [false,"human","hitl"]'
cmp -s "$c/.scratch/pay/tickets/03-c.md" "$t/expect.md" || fail "a refused claim wrote a remapped human-gate ticket"
echo "ok the repo's own ready-for-human string is a human gate"

run "$c" set-status "$c/.scratch/pay/tickets/02-b.md" not-planned
eq "custom legal" "$rc $(q "$out" '[.status, .previous]')" '0 ["not-planned","afk-ready"]'
custom_closed="$(
  # shellcheck disable=SC2034
  REPO_ROOT="$c"
  # shellcheck source=/dev/null
  . "$tickets_lib"
  work_item_is_closed not-planned && printf yes
)"
eq "tickets.sh custom wontfix" "$custom_closed" yes
echo "ok the repo's own AFK-ready and wontfix strings are honoured by every reader"

# ---- resolve -------------------------------------------------------------------------------
printf 'Built in abc1234.\n\n- seam: `Foo::bar()`\n' >"$t/resolution.md"
run "$r" claim "$a/07-g.md" --as ann-1
run "$r" resolve "$a/07-g.md" --body-file "$t/resolution.md"
eq "resolve exit" "$rc" 0
eq "resolve" "$(q "$out" '.')" '{"path":".scratch/auth/tickets/07-g.md","status":"closed","claimed_by":""}'
ticket "$t/expect.md" closed $'claimed-by:\nblocked-by: []\ndeploy-gate: false\n'
printf '\n## Resolution\n\nBuilt in abc1234.\n\n- seam: `Foo::bar()`\n' >>"$t/expect.md"
cmp -s "$a/07-g.md" "$t/expect.md" || fail "resolve did not append ## Resolution exactly (the fenced one is not a section)"
echo "ok resolve appends ## Resolution, closes, clears the claim, and keeps the body"

cp "$a/07-g.md" "$t/resolved.md"
run "$r" resolve "$a/07-g.md" --body-file "$t/resolution.md"
eq "double resolve" "$rc $(q "$out" '.error')" '1 "closed"'
cmp -s "$a/07-g.md" "$t/resolved.md" || fail "a refused resolve changed the file"
run "$r" resolve "$a/04-d.md" --body-file "$t/none.md"
eq "resolve missing body" "$rc" 2
echo "ok resolve refuses a closed item"

# A reopened ticket is resolved again: the new text goes under the heading it already has.
run "$r" set-status "$a/07-g.md" ready-for-agent
printf 'Reworked in def5678.\n' >"$t/resolution-2.md"
run "$r" resolve "$a/07-g.md" --body-file "$t/resolution-2.md"
eq "resolve reopened" "$rc $(q "$out" '.')" '0 {"path":".scratch/auth/tickets/07-g.md","status":"closed","claimed_by":""}'
cp "$t/resolved.md" "$t/expect.md"
printf '\nReworked in def5678.\n' >>"$t/expect.md"
cmp -s "$a/07-g.md" "$t/expect.md" || fail "a second resolve did not append under the existing ## Resolution"
run "$r" resolve "$a/07-g.md" --body-file "$t/resolution-2.md"
eq "resolve reopened, closed again" "$rc $(q "$out" '.error')" '1 "closed"'
echo "ok resolve on a reopened ticket appends under its ## Resolution; closed is still refused"

printf -- '---\ntitle: "E"\nstatus: open\nclaimed-by: ann-1\nblocked-by: []\n---\n\n## Question\n\nQ?\n\n## Resolution\n' >"$d/03-empty.md"
run "$r" resolve "$d/03-empty.md" --body-file "$t/resolution.md"
printf -- '---\ntitle: "E"\nstatus: closed\nclaimed-by:\nblocked-by: []\n---\n\n## Question\n\nQ?\n\n## Resolution\n\nBuilt in abc1234.\n\n- seam: `Foo::bar()`\n' >"$t/expect.md"
cmp -s "$d/03-empty.md" "$t/expect.md" || fail "resolve did not fill the empty ## Resolution heading"
echo "ok resolve fills an empty ## Resolution heading on a decision ticket"

# ---- close ---------------------------------------------------------------------------------
printf 'Out of scope: the billing rewrite covers it.\n' >"$t/reason.md"
run "$r" close "$d/02-retry.md" --reason-file "$t/reason.md"
eq "close" "$rc $(q "$out" '[.status, .claimed_by]')" '0 ["closed",""]'
eq "close tail" "$(tail -n 3 "$d/02-retry.md" | tr '\n' '|')" '## Closed||Out of scope: the billing rewrite covers it.|'
grep -q '^## Resolution' "$d/02-retry.md" && fail "close wrote a ## Resolution"
run "$r" close "$d/02-retry.md" --reason-file "$t/reason.md"
eq "close twice" "$rc $(q "$out" '.error')" '1 "closed"'
echo "ok close appends ## Closed, writes no ## Resolution, and refuses a second close"

# ---- set-status ----------------------------------------------------------------------------
cp "$a/04-d.md" "$t/before-status.md"
run "$r" set-status "$a/04-d.md" built
eq "set-status built" "$rc $(q "$out" '[.error, .status, .legal]')" \
  '1 ["illegal-status","ready-for-agent",["needs-triage","needs-info","ready-for-agent","ready-for-human","wontfix","in-progress","closed"]]'
cmp -s "$a/04-d.md" "$t/before-status.md" || fail "a refused set-status wrote the file"
run "$r" set-status "$d/01-queue.md" in-progress
eq "set-status decision" "$rc $(q "$out" '.legal')" '1 ["open","closed"]'
run "$r" set-status "$r/.scratch/chart/map.md" closed
eq "set-status map" "$rc $(q "$out" '.')" '0 {"path":".scratch/chart/map.md","status":"closed","previous":"open"}'
run "$r" set-status "$a/04-d.md" ready-for-human
eq "set-status human" "$rc $(q "$out" '[.status, .previous]')" '0 ["ready-for-human","ready-for-agent"]'
echo "ok set-status writes only a status legal for the file kind and refuses built"

run "$r" set-status "$d/01-queue.md" ready-for-agent
eq "role name on a decision" "$rc $(q "$out" '.legal')" '1 ["open","closed"]'
echo "ok a role name is not a status of a decision ticket"

# ---- human gates ---------------------------------------------------------------------------
h="$r/.scratch/gate/tickets"
ticket "$h/01-a.md" needs-info $'claimed-by:\nblocked-by: []\n'
ticket "$h/02-b.md" needs-triage $'claimed-by:\nblocked-by: []\n'
ticket "$h/03-c.md" ready-for-human $'claimed-by:\nblocked-by: []\n'
ticket "$h/04-d.md" ready-for-agent $'claimed-by:\nblocked-by: [01]\n'
ticket "$h/05-e.md" ready-for-agent $'claimed-by:\nblocked-by: []\n'
ticket "$h/06-f.md" needs-info $'claimed-by:\nblocked-by: [05]\n'
run "$r" frontier gate
eq "gate frontier" "$(q "$out" '[.frontier, .next, [.tickets[].derived], .counts.human, .counts.ready]')" \
  '[["05"],"05",["human","human","human","blocked","ready","blocked"],3,1]'
run "$r" frontier gate --built 05
eq "gate --built" "$(q "$out" '.tickets[5].derived')" '"human"'
echo "ok frontier leaves needs-info, needs-triage and ready-for-human tickets out as derived human"

for n in 01-a 02-b 03-c; do
  cp "$h/$n.md" "$t/expect.md"
  run "$r" claim "$h/$n.md" --as zed-9
  eq "gate claim $n" "$rc $(q "$out" '[.won, .reason, .claimed_by]')" '1 [false,"human",""]'
  cmp -s "$h/$n.md" "$t/expect.md" || fail "a refused claim wrote the human-gate ticket $n"
done
# The reviewer's case: claim then release once turned ready-for-human into ready-for-agent.
run "$r" release "$h/03-c.md"
eq "gate release" "$rc $(q "$out" '.status')" '0 "ready-for-human"'
cmp -s "$h/03-c.md" "$t/expect.md" || fail "claim and release changed a ready-for-human ticket"
printf -- '---\ntitle: "Spec"\nstatus: needs-info\n---\n\n## Problem Statement\n\nx\n' >"$r/.scratch/gate/spec.md"
run "$r" claim "$r/.scratch/gate/spec.md" --as zed-9
eq "gate spec" "$rc $(q "$out" '.reason')" '1 "human"'
gate_lib="$(
  # shellcheck disable=SC2034
  REPO_ROOT="$r"
  # shellcheck source=/dev/null
  . "$tickets_lib"
  for status in needs-info ready-for-human ready-for-agent; do
    if work_item_is_human_gate build "$status" ""; then printf '%s|' "$status"; fi
  done
)"
eq "tickets.sh gates" "$gate_lib" 'needs-info|ready-for-human|'
echo "ok claim refuses a human-gate ticket or spec with reason human and writes nothing"

# ---- an older ticket's body line **Claimed by:** --------------------------------------------
l="$r/.scratch/older/tickets"
mkdir -p "$l"
# older <file> <status> <claim line>
older() {
  printf -- '---\ntitle: "L"\nstatus: %s\n---\n\n# L\n\n%s\n\nbody line\n' "$2" "$3" >"$1"
}
# claim_of <file>: what scratch-state.sh reads as the claimant.
claim_of() {
  bash "$state_sh" --root "$r" --no-commits older |
    jq -r --arg p "tickets/$(basename "$1")" '.efforts[0].tickets[] | select(.path == $p) | .claimed_by'
}
older "$l/01-a.md" in-progress '**Claimed by:** old-1'
eq "older read" "$(claim_of "$l/01-a.md")" old-1
run "$r" release "$l/01-a.md"
eq "older release" "$rc $(q "$out" '.')" '0 {"path":".scratch/older/tickets/01-a.md","status":"ready-for-agent","claimed_by":""}'
older "$t/expect.md" ready-for-agent '**Claimed by:**'
cmp -s "$l/01-a.md" "$t/expect.md" || fail "release did not empty the body claim line, or added a frontmatter key"
eq "older released read" "$(claim_of "$l/01-a.md")" ''
run "$r" frontier older
eq "older frontier" "$(q "$out" '.frontier')" '["01"]'
echo "ok release empties an older body claim line and adds no frontmatter key"

run "$r" claim "$l/01-a.md" --as ann-1
eq "older claim" "$rc $(q "$out" '[.won, .status, .claimed_by]')" '0 [true,"in-progress","ann-1"]'
printf -- '---\ntitle: "L"\nstatus: in-progress\nclaimed-by: ann-1\n---\n\n# L\n\n**Claimed by:** ann-1\n\nbody line\n' >"$t/expect.md"
cmp -s "$l/01-a.md" "$t/expect.md" || fail "claim on an older ticket did not write the frontmatter key and the body line"
older_lib="$(
  # shellcheck disable=SC2034
  REPO_ROOT="$r"
  # shellcheck source=/dev/null
  . "$tickets_lib"
  read_work_item_state "$l/01-a.md"
  printf '%s|%s' "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM"
)"
eq "older claim: tickets.sh" "$older_lib" 'in-progress|ann-1'
eq "older claim: scratch-state.sh" "$(claim_of "$l/01-a.md")" ann-1
run "$r" claim "$l/01-a.md" --as zed-9
eq "older claim held" "$rc $(q "$out" '[.reason, .claimed_by]')" '1 ["claimed","ann-1"]'
echo "ok claim on an older ticket writes the claim where every reader finds it"

run "$r" resolve "$l/01-a.md" --body-file "$t/reason.md"
printf -- '---\ntitle: "L"\nstatus: closed\nclaimed-by:\n---\n\n# L\n\n**Claimed by:**\n\nbody line\n\n## Resolution\n\nOut of scope: the billing rewrite covers it.\n' >"$t/expect.md"
cmp -s "$l/01-a.md" "$t/expect.md" || fail "resolve did not clear both claim lines of an older ticket"
older "$l/02-b.md" in-progress 'Claimed by: bo-2'
run "$r" close "$l/02-b.md" --reason-file "$t/reason.md"
eq "older close" "$rc $(q "$out" '[.status, .claimed_by]')" '0 ["closed",""]'
older "$t/expect.md" closed 'Claimed by:'
printf '\n## Closed\n\nOut of scope: the billing rewrite covers it.\n' >>"$t/expect.md"
cmp -s "$l/02-b.md" "$t/expect.md" || fail "close did not empty the plain body claim line"
older "$l/03-c.md" ready-for-agent 'Claimed by: none'
cp "$l/03-c.md" "$t/expect.md"
run "$r" release "$l/03-c.md"
cmp -s "$l/03-c.md" "$t/expect.md" || fail "release rewrote an unclaimed older ticket"
printf '# No frontmatter\n\n**Status:** ready-for-agent\n**Claimed by:** old-1\n' >"$l/04-d.md"
cp "$l/04-d.md" "$t/expect.md"
run "$r" release "$l/04-d.md"
eq "no frontmatter" "$rc $(q "$out" '[.error, .claimed_by]')" '1 ["no-frontmatter","old-1"]'
cmp -s "$l/04-d.md" "$t/expect.md" || fail "a refused release wrote a file with no frontmatter"
echo "ok resolve and close clear an older claim line; a file with no frontmatter is refused, not half-released"

# ---- a claim id plain YAML would misread ----------------------------------------------------
y="$r/.scratch/quote/tickets"
ticket "$y/01-a.md" ready-for-agent $'claimed-by:\nblocked-by: []\n'
run "$r" claim "$y/01-a.md" --as 'alice: session'
eq "quoted id" "$rc $(q "$out" '[.won, .claimed_by]')" '0 [true,"alice: session"]'
ticket "$t/expect.md" in-progress $'claimed-by: "alice: session"\nblocked-by: []\n'
cmp -s "$y/01-a.md" "$t/expect.md" || fail "an id holding ': ' was not written in double quotes"
run "$r" claim "$y/01-a.md" --as 'alice: session'
eq "quoted id again" "$rc $(q "$out" '.won')" '0 true'
run "$r" claim "$y/01-a.md" --as zed-9
eq "quoted id held" "$rc $(q "$out" '[.reason, .claimed_by]')" '1 ["claimed","alice: session"]'
quoted_lib="$(
  # shellcheck disable=SC2034
  REPO_ROOT="$r"
  # shellcheck source=/dev/null
  . "$tickets_lib"
  read_work_item_state "$y/01-a.md"
  printf '%s' "$WORK_ITEM_CLAIM"
)"
eq "quoted id: tickets.sh" "$quoted_lib" 'alice: session'
eq "quoted id: scratch-state.sh" \
  "$(bash "$state_sh" --root "$r" --no-commits quote | jq -r '.efforts[0].tickets[0].claimed_by')" 'alice: session'
run "$r" lint quote
eq "quoted id lint" "$rc" 0
run "$r" release "$y/01-a.md"
run "$r" claim "$y/01-a.md" --as 'bob:'
eq "trailing colon" "$rc $(q "$out" '.claimed_by') $(grep -c '^claimed-by: "bob:"$' "$y/01-a.md")" '0 "bob:" 1'
echo "ok an id holding ': ' or ending in ':' is written quoted, and every reader returns the same id"

# ---- the write lock ------------------------------------------------------------------------
# A slow `git` holds every read open, so sessions started together all read the same state:
# without the lock they would all pass the checks and write.
mkdir -p "$t/slow"
printf '#!/bin/bash\nsleep 0.1\nexit 1\n' >"$t/slow/git"
chmod +x "$t/slow/git"
k="$r/.scratch/race/tickets"
ticket "$k/01-a.md" ready-for-agent $'claimed-by:\nblocked-by: []\n'
for i in 1 2 3 4 5; do
  (PATH="$t/slow:$PATH" bash "$ticket_sh" --root "$r" claim "$k/01-a.md" --as "racer-$i" >"$t/race-$i.json" 2>/dev/null || true) &
done
wait
race="$(cat "$t"/race-?.json | jq -sc '.')"
eq "race winners" "$(q "$race" '[.[] | select(.won)] | length')" 1
eq "race losers" "$(q "$race" '[.[] | select(.won | not) | .reason]')" '["claimed","claimed","claimed","claimed"]'
run "$r" frontier race
eq "race file" "$(q "$out" '.tickets[0].claimed_by')" "$(q "$race" '.[] | select(.won) | .claimed_by')"
echo "ok concurrent claims on one ticket: one wins, the rest are refused as claimed and write nothing"

ticket "$k/02-b.md" ready-for-agent $'claimed-by:\nblocked-by: []\n'
for i in 1 2 3 4; do
  printf 'Resolution %s, first line.\n\nResolution %s, last line.\n' "$i" "$i" >"$t/body-$i.md"
  (
    code=0
    PATH="$t/slow:$PATH" bash "$ticket_sh" --root "$r" resolve "$k/02-b.md" --body-file "$t/body-$i.md" >/dev/null 2>&1 || code=$?
    echo "$code" >"$t/resolve-$i.rc"
  ) &
done
wait
eq "resolve race codes" "$(cat "$t"/resolve-?.rc | sort | tr '\n' ' ')" '0 1 1 1 '
winner="$(grep -l '^0$' "$t"/resolve-?.rc | sed -E 's/.*resolve-([0-9])\.rc/\1/')"
ticket "$t/expect.md" closed $'claimed-by:\nblocked-by: []\n'
printf '\n## Resolution\n\n' >>"$t/expect.md"
cat "$t/body-$winner.md" >>"$t/expect.md"
cmp -s "$k/02-b.md" "$t/expect.md" || fail "the winning Resolution is not intact after concurrent resolves"
[ -z "$(find "$r/.scratch/race" -name '.*')" ] || fail "the lock left a file behind"
echo "ok concurrent resolves on one ticket: one succeeds with its Resolution intact, and no lock file remains"

# ---- byte preservation on CRLF and odd bytes ------------------------------------------------
printf -- '---\r\ntitle: "W"\r\nblocked-by: []\r\n---\r\n\r\nbody \377 bytes\r\nno newline at end' >"$a/10-w.md"
cp "$a/10-w.md" "$t/expect.md"
run "$r" claim "$a/10-w.md" --as ann-1
eq "claim unreadable" "$rc $(q "$out" '[.won, .reason]')" '1 [false,"unreadable"]'
cmp -s "$a/10-w.md" "$t/expect.md" || fail "a refused claim wrote a status-less ticket"
echo "ok a ticket with no status is refused as unreadable"
printf -- '---\r\ntitle: "W"\r\nstatus: ready-for-agent\r\nblocked-by: []\r\n---\r\n\r\nbody \377 bytes\r\nno newline at end' >"$a/10-w.md"
run "$r" claim "$a/10-w.md" --as ann-1
eq "crlf claim" "$rc" 0
printf -- '---\r\ntitle: "W"\r\nstatus: in-progress\r\nblocked-by: []\r\nclaimed-by: ann-1\r\n---\r\n\r\nbody \377 bytes\r\nno newline at end' >"$t/expect.md"
cmp -s "$a/10-w.md" "$t/expect.md" || fail "claim on a CRLF file: the missing key was not added with CRLF, or bytes changed"
run "$r" resolve "$a/10-w.md" --body-file "$t/reason.md"
printf -- '---\r\ntitle: "W"\r\nstatus: closed\r\nblocked-by: []\r\nclaimed-by:\r\n---\r\n\r\nbody \377 bytes\r\nno newline at end\r\n\r\n## Resolution\r\n\r\nOut of scope: the billing rewrite covers it.\r\n' >"$t/expect.md"
cmp -s "$a/10-w.md" "$t/expect.md" || fail "resolve on a CRLF file changed other bytes"
[ -z "$(find "$r/.scratch" -name '.ticket-*')" ] || fail "a temp file was left behind"
echo "ok writes keep CRLF, non-UTF-8 bytes, and add a missing key; no temp file remains"

# ---- lint ----------------------------------------------------------------------------------
# The published templates, filled in, pass.
g="$t/good"
k="$g/.scratch/ship"
mkdir -p "$k/decisions" "$k/tickets"
printf -- '---\ntitle: "Map: ship it"\nstatus: closed\n---\n\n## Destination\n\nx\n' >"$k/map.md"
printf -- '---\ntitle: "Spec: ship it"\nstatus: ready-for-agent\n---\n\n## Problem Statement\n\nx\n' >"$k/spec.md"
printf -- '---\ntitle: "Build decisions"\ntype: grilling\nstatus: closed\nclaimed-by:\nblocked-by: []\n---\n\n## Question\n\nx\n\n## Resolution\n\nNone open\n' >"$k/decisions/01-build-decisions.md"
printf -- '---\ntitle: "SLA report: LAT"\nstatus: ready-for-agent\nclaimed-by:\nblocked-by: []\ndeploy-gate: false\n---\n\n# 01: SLA report\n' >"$k/tickets/01-sla.md"
printf -- '---\ntitle: "Export #2"\nstatus: ready-for-agent\nclaimed-by:\nblocked-by: [01]\ndeploy-gate: true\n---\n\n# 02: Export\n' >"$k/tickets/02-export.md"
printf -- '---\ntitle: "Delivery check: ship it"\nstatus: ready-for-agent\nclaimed-by:\nblocked-by: [01, 02]\ndeploy-gate: false\ndelivery: true\n---\n\n# 03: Delivery check\n' >"$k/tickets/03-delivery.md"
run "$g" lint ship
eq "lint clean" "$rc $(q "$out" '.')" '0 {"ok":true,"errors":[]}'
run "$g" frontier ship
eq "template round trip" "$(q "$out" '[.frontier, .tickets[1].title, .tickets[1].deploy_gate, .tickets[2].delivery, .tickets[2].blocked_by]')" \
  '[["01"],"Export #2",true,true,["01","02"]]'
run "$g" claim "$k/tickets/01-sla.md" --as ann-1
run "$g" release "$k/tickets/01-sla.md"
run "$g" lint ship
eq "lint after claim and release" "$rc" 0
echo "ok lint passes the filled-in templates, before and after a claim and release"

# has <rule> <file suffix>: lint reported that rule on that file.
has() {
  printf '%s' "$out" | jq -e --arg rule "$1" --arg file "$2" \
    '.errors | any(.rule == $rule and (.file | endswith($file)))' >/dev/null ||
    fail "lint did not report $1 on $2: $out"
}
b="$g/.scratch/bad/tickets"
mkdir -p "$b"
printf -- '---\ntitle: "Fine"\nstatus: closed\n---\n' >"$b/01-fine.md"
printf -- '---\ntitle: Bare: title\nstatus: closed\n---\n' >"$b/02-bare.md"
printf -- '---\ntitle: "Built"\nstatus: built\n---\n' >"$b/03-built.md"
printf -- '---\ntitle: "Comment"\n# a note\nstatus: closed\nclaimed-by: # nobody\n---\n' >"$b/04-comment.md"
printf -- '---\ntitle: "Missing"\nstatus: ready-for-agent\nblocked-by: [77]\n---\n' >"$b/05-missing.md"
printf -- '---\ntitle: "Higher"\nstatus: ready-for-agent\nblocked-by: [07]\n---\n' >"$b/06-higher.md"
printf -- '---\ntitle: "Ship"\nstatus: ready-for-agent\nblocked-by: [01]\ndelivery: true\n---\n' >"$b/07-ship.md"
printf -- '---\ntitle: "Unpadded"\nstatus: closed\n---\n' >"$b/9-unpadded.md"
printf '# No frontmatter\n\n**Status:** ready-for-agent\n' >"$b/10-legacy.md"
printf -- '---\ntitle: "Junk"\nstatus: closed\nnot a key line\n---\n' >"$b/11-junk.md"
printf -- '---\ntitle: "Done"\nstatus: done\n---\n' >"$b/12-done.md"
run "$g" lint bad
eq "lint bad exit" "$rc $(q "$out" '.ok')" '1 false'
has title-quoted tickets/02-bare.md
has status-legal tickets/03-built.md
has status-legal tickets/12-done.md
has no-comments tickets/04-comment.md
eq "both comment forms" "$(q "$out" '[.errors[] | select(.rule == "no-comments")] | length')" 2
has blocker-missing tickets/05-missing.md
has blocker-not-lower tickets/06-higher.md
has delivery-not-last tickets/07-ship.md
has delivery-blockers tickets/07-ship.md
has filename-number tickets/9-unpadded.md
has frontmatter tickets/10-legacy.md
has frontmatter tickets/11-junk.md
eq "clean file" "$(q "$out" '[.errors[] | select(.file | endswith("01-fine.md"))] | length')" 0
echo "ok lint reports each rule: frontmatter, title-quoted, status-legal, no-comments, blocker-missing, blocker-not-lower, delivery-not-last, delivery-blockers, filename-number"

w="$g/.scratch/twin/tickets"
mkdir -p "$w"
printf -- '---\ntitle: "A"\nstatus: closed\n---\n' >"$w/01-a.md"
printf -- '---\ntitle: "B"\nstatus: ready-for-agent\nblocked-by: [01]\ndelivery: true\n---\n' >"$w/02-b.md"
printf -- '---\ntitle: "C"\nstatus: ready-for-agent\nblocked-by: [01, 02]\ndelivery: true\n---\n' >"$w/03-c.md"
printf -- '---\ntitle: "D"\nstatus: closed\n---\n' >"$w/03-d.md"
run "$g" lint twin
eq "lint twin exit" "$rc" 1
has delivery-count tickets
has filename-number tickets
run "$g" lint nowhere
eq "lint unknown slug" "$rc" 2
run "$g" frontier nowhere
eq "frontier unknown slug" "$rc" 2
echo "ok lint reports two delivery tickets and a repeated number; an unknown slug exits 2"

# ---- root discovery ------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  git init -q "$g"
  mkdir -p "$g/app/deep"
  found="$(cd "$g/app/deep" && bash "$ticket_sh" frontier ship)"
  eq "git root" "$(q "$found" '.frontier')" '["01"]'
  found="$(cd "$g/app/deep" && bash "$ticket_sh" claim ../../.scratch/ship/tickets/01-sla.md --as ann-1)"
  eq "relative path" "$(q "$found" '[.won, .path]')" '[true,".scratch/ship/tickets/01-sla.md"]'
  echo "ok without --root the tracker is found at the git top level, from a subdirectory"
fi

[ ! -e "$t/gh-called" ] || fail "a subcommand called gh"
echo "ok no subcommand called gh"
echo "test-ticket.sh: all cases passed"
