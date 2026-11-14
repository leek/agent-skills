#!/bin/bash
# The spec's task graph. Every read and write goes through the tracker's own ticket.sh
# (skills/setup/scripts/ticket.sh), so the runner, implement-spec, scratch-status and the
# /scratch board give one status, claim and frontier for a ticket.

set -e

SPEC_SLUG=""
TRACKER_ROOT=""
FRONTIER_JSON=""
TRACKER_OUTCOME=""
TRACKER_NEXT_REF=""
TRACKER_REASON=""

repo_relative_ref() {
  local file="$1"
  if [[ "$file" == "$REPO_ROOT"/* ]]; then
    printf '%s' "${file#"$REPO_ROOT"/}"
  else
    printf '%s' "$file"
  fi
}

# Autopilot takes one spec: .scratch/<slug>/spec.md. Sets SPEC_SLUG, or TRACKER_OUTCOME and
# TRACKER_REASON when the root is not a spec with tickets.
resolve_spec_scope() {
  local dir spec="$ROOT_REF"
  TRACKER_OUTCOME=""
  TRACKER_REASON=""
  TRACKER_NEXT_REF=""
  # The spec may live only on the integration branch: PR delivery moves .scratch/<slug>/
  # there, so the launch checkout no longer holds it.
  if [[ ! -e "$spec" && "$spec" == "$REPO_ROOT"/* && -e "$INTEGRATION_DIR/${spec#"$REPO_ROOT"/}" ]]; then
    spec="$INTEGRATION_DIR/${spec#"$REPO_ROOT"/}"
  fi
  if [[ ! -e "$spec" ]]; then
    TRACKER_OUTCOME="blocked"
    TRACKER_REASON="root reference does not exist: $ROOT_REF"
    return 1
  fi
  dir="$(dirname "$ROOT_REF")"
  if [[ ! -f "$spec" || "$(basename "$ROOT_REF")" != "spec.md" || "$(basename "$(dirname "$dir")")" != ".scratch" ]]; then
    TRACKER_OUTCOME="blocked"
    TRACKER_REASON="autopilot takes a spec (.scratch/<slug>/spec.md), not $(repo_relative_ref "$ROOT_REF"): build one ticket with implement, and finish a map with wayfinder and to-spec"
    return 1
  fi
  SPEC_SLUG="$(basename "$dir")"
}

# The checkout whose .scratch/ is the tracker of record: the integration checkout, or the
# launch checkout when the repository keeps .scratch/ out of Git.
resolve_tracker_root() {
  TRACKER_ROOT="$INTEGRATION_DIR"
  [[ -d "$INTEGRATION_DIR/.scratch/$SPEC_SLUG" ]] || TRACKER_ROOT="$REPO_ROOT"
  if ! find "$TRACKER_ROOT/.scratch/$SPEC_SLUG/tickets" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q .; then
    TRACKER_OUTCOME="blocked"
    TRACKER_REASON="the spec has no tickets in $TRACKER_ROOT/.scratch/$SPEC_SLUG/tickets: the autopilot skill cuts and commits them before it starts the runner"
    return 1
  fi
}

ticket_sh() {
  bash "$TICKET_SH" --root "$TRACKER_ROOT" "$@"
}

# The tickets landed on this integration branch, as ticket.sh's --built list: land.sh writes
# one landed/<NN> file per ticket. They close only when the finish worker resolves them.
landed_numbers() {
  local file
  [[ -d "$NOTES_DIR/landed" ]] || return 0
  for file in "$NOTES_DIR/landed"/*; do
    [[ -f "$file" ]] && printf '%s\n' "${file##*/}"
  done
  return 0
}

landed_csv() {
  landed_numbers | paste -sd, -
}

ticket_is_landed() {
  [[ -f "$NOTES_DIR/landed/$1" ]]
}

frontier_refresh() {
  local built args=(frontier "$SPEC_SLUG" --kind tickets)
  built="$(landed_csv)"
  [[ -z "$built" ]] || args+=(--built "$built")
  FRONTIER_JSON="$(ticket_sh "${args[@]}")" || runner_failure "could not read the tracker for $SPEC_SLUG"
}

# frontier_query <jq filter>: raw output of the filter over the last frontier read.
frontier_query() {
  printf '%s' "$FRONTIER_JSON" | jq -r "$@"
}

ticket_field() {
  frontier_query --arg n "$1" ".tickets[] | select(.number == \$n) | $2"
}

ticket_ref() {
  ticket_field "$1" '.path'
}

# Landed tickets the tracker still shows open: what the finish worker resolves.
merged_pending_numbers() {
  local number
  while IFS= read -r number; do
    [[ -n "$number" ]] || continue
    [[ "$(ticket_field "$number" '.derived')" == "closed" ]] || printf '%s\n' "$number"
  done < <(landed_numbers)
}

# Deploy gates landed on this branch: their dependents wait for the deploy, on a later branch.
landed_gate_numbers() {
  local number
  while IFS= read -r number; do
    [[ -n "$number" ]] || continue
    [[ "$(ticket_field "$number" '.deploy_gate')" != "true" ]] || printf '%s\n' "$number"
  done < <(landed_numbers)
}

# True when a direct blocker of the ticket is a deploy gate landed on this branch.
ticket_waits_on_gate() {
  local number="$1" gate
  while IFS= read -r gate; do
    [[ -n "$gate" ]] || continue
    if [[ "$(frontier_query --arg n "$number" --arg g "$gate" \
      '[.tickets[] | select(.number == $n) | .blocked_by[] | select((tonumber? // -1) == ($g | tonumber))] | length')" != "0" ]]; then
      return 0
    fi
  done < <(landed_gate_numbers)
  return 1
}

# The paths a ticket's `## Files` section names, one per line, sorted.
ticket_files() {
  awk '
    /^## Files[[:space:]]*$/ { inside = 1; next }
    inside && /^##[[:space:]]/ { exit }
    inside {
      line = $0
      while (match(line, /`[^`]+`/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$1" 2>/dev/null | sort -u
}

claim_ticket() {
  local ref="$1" built args out
  args=(claim "$ref" --as "autopilot:$RUN_ID")
  built="$(landed_csv)"
  [[ -z "$built" ]] || args+=(--built "$built")
  out="$(ticket_sh "${args[@]}" 2>/dev/null)" || true
  CLAIM_REASON="$(printf '%s' "$out" | jq -r '.reason // "unreadable"' 2>/dev/null || printf 'unreadable')"
  [[ "$(printf '%s' "$out" | jq -r '.won // false' 2>/dev/null)" == "true" ]]
}

release_ticket() {
  local ref="$1" note="$2"
  ticket_sh release "$ref" --note "$note" >/dev/null 2>&1 ||
    announce "could not release $ref; its claim stays"
}

# Sets TRACKER_OUTCOME, TRACKER_NEXT_REF and TRACKER_REASON from the tracker when nothing is
# running and nothing can be dispatched. Call frontier_refresh first.
tracker_idle_outcome() {
  local open human gate_waiting="" number waiting=""
  TRACKER_NEXT_REF=""
  open="$(frontier_query '.counts.open')"
  if [[ "$open" == "0" ]]; then
    TRACKER_OUTCOME="complete"
    TRACKER_REASON="every ticket of the spec is closed"
    return 0
  fi
  while IFS= read -r number; do
    [[ -n "$number" ]] || continue
    if ticket_waits_on_gate "$number"; then
      gate_waiting="$gate_waiting${gate_waiting:+, }$number"
    fi
  done < <(frontier_query '.tickets[] | select(.derived != "closed") | .number')
  if [[ -n "$gate_waiting" ]]; then
    TRACKER_OUTCOME="needs_input"
    TRACKER_REASON="deploy gate $(landed_gate_numbers | paste -sd, -) is built: deploy its pull request, then run the same autopilot command again for $gate_waiting"
    return 0
  fi
  human="$(frontier_query '[.tickets[] | select(.derived == "human")][0].path // ""')"
  if [[ -n "$human" ]]; then
    TRACKER_OUTCOME="needs_input"
    TRACKER_NEXT_REF="$human"
    TRACKER_REASON="$human waits on a person ($(frontier_query --arg p "$human" '.tickets[] | select(.path == $p) | .status'))"
    return 0
  fi
  waiting="$(frontier_query '[.tickets[] | select(.derived != "closed") | "\(.number) (\(.derived)\(if .claimed_by != "" and .claimed_by != null then " by " + .claimed_by else "" end))"] | join(", ")')"
  TRACKER_OUTCOME="blocked"
  TRACKER_REASON="no ticket can be built among $open open: $waiting"
}
