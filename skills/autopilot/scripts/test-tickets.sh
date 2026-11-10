#!/bin/bash
# Offline test for lib/tickets.sh: its claim and blocker reading must agree with the
# tracker's reference reader, skills/scratch-status/scripts/scratch-state.sh, on the same
# files. Sources lib/tickets.sh, runs scratch-state.sh --no-commits on one fixture effort
# under mktemp -d, and compares claim, blockers, and frontier ticket by ticket.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
# shellcheck disable=SC2034 # globals the sourced libraries read
set -e
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
state_sh="$here/../../scratch-status/scripts/scratch-state.sh"
command -v jq >/dev/null 2>&1 || { echo "test-tickets.sh: jq is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "test-tickets.sh: python3 is required" >&2; exit 2; }
[ -f "$state_sh" ] || { echo "test-tickets.sh: reference reader missing: $state_sh" >&2; exit 2; }

t="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$t"' EXIT

fail() {
  echo "FAIL $1" >&2
  exit 1
}

eq() {
  [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"
}

# md <file> <frontmatter lines> [body]
md() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\ntitle: T\n%s---\n\n%s\n' "$2" "${3:-body}" >"$1"
}

r="$t/repo"
d="$r/.scratch/e/tickets"
md "$d/01-a.md" $'status: closed\n'
md "$d/02-b.md" $'status: ready-for-agent\n'
md "$d/03-block-open.md" $'status: ready-for-agent\nblocked-by:\n  - "02"\n'
md "$d/04-block-closed.md" $'status: ready-for-agent\nblocked-by:\n  - "01"\n'
md "$d/05-none.md" $'status: ready-for-agent\nblocked-by: none\n'
md "$d/06-tilde.md" $'status: ready-for-agent\nblocked-by: ~\n'
md "$d/07-null.md" $'status: ready-for-agent\nblocked-by: null # nothing\n'
md "$d/08-empty.md" $'status: ready-for-agent\nblocked-by: []\n'
md "$d/09-body-claim.md" $'status: ready-for-agent\n' $'**Claimed by:** ann-1\n\nbody'
md "$d/10-body-claim-none.md" $'status: ready-for-agent\n' $'Claimed by: none\n\nbody'
md "$d/11-body-blocked.md" $'status: ready-for-agent\n' $'**Blocked by:** 02, 03\n\nbody'
md "$d/12-unpadded.md" $'status: ready-for-agent\nblocked-by: [1]\n'
md "$d/13-digits.md" $'status: ready-for-agent\nblocked-by: ["ticket-02"]\n'
md "$d/14-bare.md" $'status: ready-for-agent\nblocked-by: 01, "02" # waits\n'
md "$d/15-flow.md" $'status: ready-for-agent\nblocked-by: [\n  "01",\n  "02"\n]\n'
md "$d/16-block-comment.md" $'status: ready-for-agent\nblocked-by:\n  - \'02\' # waits\n  - 01\n'
md "$d/17-body-blocked-none.md" $'status: ready-for-agent\n' $'**Blocked by:** None\n\nbody'
md "$d/18-front-claim.md" $'status: ready-for-agent\nclaimed-by: bob-2 # since Monday\n'
md "$d/19-crlf.md" $'status: ready-for-agent\r\nblocked-by:\r\n  - "02"\r\n'
md "$d/20-body-claim-case.md" $'status: ready-for-agent\n' $'claimed BY: cy-3\n\nbody'
md "$d/21-inline.md" $'status: ready-for-agent\nblocked-by: ["01", 02] # see [03]\n'
# No frontmatter at all: every marker is a legacy body line.
mkdir -p "$d"
printf '# Legacy\n\n**Status:** open\n**Claimed by:** dee-4\n**Blocked by:** #02\n' >"$d/22-legacy.md"

REPO_ROOT="$r"
RUN_ID="autopilot-test-run"
ROOT_REF="$d"
# shellcheck source=lib/tickets.sh
source "$here/lib/tickets.sh"

json="$(bash "$state_sh" --root "$r" --no-commits e)"
count="$(printf '%s' "$json" | jq '.efforts[0].tickets | length')"
eq "reference reader sees every fixture" "$count" 22

# ticket_json <basename> <jq filter>
ticket_json() {
  printf '%s' "$json" | jq -r --arg p "tickets/$1" ".efforts[0].tickets[] | select(.path == \$p) | $2"
}

# The leading numbers of the files in RESOLVED_BLOCKERS, comma-joined.
resolved_numbers() {
  local file name out=""
  if [[ ${RESOLVED_BLOCKERS[0]+present} ]]; then
    for file in "${RESOLVED_BLOCKERS[@]}"; do
      name="${file##*/}"
      out="$out${out:+,}${name%%-*}"
    done
  fi
  printf '%s' "$out"
}

for file in "$d"/*.md; do
  name="${file##*/}"
  read_work_item_state "$file" || fail "$name: no state read"
  eq "$name claim" "$WORK_ITEM_CLAIM" "$(ticket_json "$name" '.claimed_by')"
  read_work_item_blockers "$file" build || fail "$name: $BLOCKER_ERROR"
  want="$(ticket_json "$name" '[.blocked_by[] | if length < 2 then "0" + . else . end] | join(",")')"
  eq "$name blockers" "$(resolved_numbers)" "$want"
done
echo "ok claim and blockers agree with scratch-state.sh on every fixture"

# The cases the panel named, pinned to their values so agreement cannot hide two wrong readers.
read_work_item_state "$d/09-body-claim.md"
eq "legacy body claim" "$WORK_ITEM_CLAIM" "ann-1"
work_item_is_claimed "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM" || fail "a body-claimed ticket reads free"
read_work_item_state "$d/10-body-claim-none.md"
eq "legacy body claim none" "$WORK_ITEM_CLAIM" ""
read_work_item_state "$d/22-legacy.md"
eq "legacy file claim" "$WORK_ITEM_CLAIM" "dee-4"
echo "ok legacy Claimed by body line is a claim"

read_work_item_blockers "$d/03-block-open.md" build
eq "block list" "$(resolved_numbers)" "02"
if candidate_blockers_are_closed "$d/03-block-open.md"; then
  fail "a ticket blocked through a YAML block list reads unblocked"
fi
candidate_blockers_are_closed "$d/04-block-closed.md" || fail "a closed block-list blocker still blocks"
read_work_item_blockers "$d/19-crlf.md" build
eq "CRLF block list" "$(resolved_numbers)" "02"
read_work_item_blockers "$d/15-flow.md" build
eq "multi-line inline list" "$(resolved_numbers)" "01,02"
echo "ok YAML block list blockers are read"

for name in 05-none.md 06-tilde.md 07-null.md 08-empty.md 17-body-blocked-none.md; do
  read_work_item_blockers "$d/$name" build || fail "$name: $BLOCKER_ERROR"
  eq "$name has no blockers" "$(resolved_numbers)" ""
done
echo "ok none, null, ~ and [] mean no blockers"

read_work_item_blockers "$d/11-body-blocked.md" build
eq "legacy body blockers" "$(resolved_numbers)" "02,03"
read_work_item_blockers "$d/12-unpadded.md" build
eq "unpadded number" "$(resolved_numbers)" "01"
read_work_item_blockers "$d/13-digits.md" build
eq "digits in a word" "$(resolved_numbers)" "02"
echo "ok blocker ids normalise to the ticket number"

tracker_refresh
frontier=""
for file in "${TRACKER_FRONTIER_FILES[@]}"; do
  frontier="$frontier${frontier:+,}tickets/${file##*/}"
done
eq "frontier" "$frontier" "$(printf '%s' "$json" | jq -r '.efforts[0].frontier | join(",")')"
eq "selected" "$TRACKER_SELECTED_REF" ".scratch/e/tickets/02-b.md"
echo "ok frontier agrees with scratch-state.sh"

# Failure paths: a blocker no ticket carries, and a number two tickets carry.
x="$r/.scratch/x/tickets"
md "$x/01-a.md" $'status: ready-for-agent\nblocked-by:\n  - "07"\n'
if read_work_item_blockers "$x/01-a.md" build; then
  fail "a missing blocker resolved"
fi
case "$BLOCKER_ERROR" in
  *"missing or ambiguous blocker '07'"*) ;;
  *) fail "missing blocker error: $BLOCKER_ERROR" ;;
esac
ROOT_REF="$x"
tracker_refresh
eq "missing blocker outcome" "$TRACKER_OUTCOME" "blocked"
md "$x/02-b.md" $'status: closed\n'
md "$x/02-c.md" $'status: closed\n'
md "$x/03-d.md" $'status: ready-for-agent\nblocked-by: [02]\n'
if read_work_item_blockers "$x/03-d.md" build; then
  fail "an ambiguous blocker resolved"
fi
echo "ok a missing or ambiguous blocker stops the tracker"
