#!/bin/bash
# Work-item status observation for the markdown tracker under .scratch/.

set -e

WORK_ITEM_STATUS=""
WORK_ITEM_CLAIM=""

# The effort directory holds the map, spec, decisions/, and issues/ for one effort.
effort_dir_for_ref() {
  local ref="$1" dir parent
  [[ -e "$ref" ]] || return 1
  if [[ -d "$ref" ]]; then
    dir="$(cd "$ref" && pwd -P)"
  else
    dir="$(cd "$(dirname "$ref")" && pwd -P)"
  fi
  while [[ "$dir" != "/" && "$dir" != "$REPO_ROOT" ]]; do
    parent="$(basename "$dir")"
    [[ "$parent" == "issues" || "$parent" == "decisions" ]] || break
    dir="$(dirname "$dir")"
  done
  printf '%s' "$dir"
}

resolve_work_item() {
  local ref="$1"
  [[ -n "$ref" ]] || return 1
  if [[ "$ref" != /* ]]; then
    [[ -f "$REPO_ROOT/$ref" ]] || return 1
    printf '%s/%s' "$REPO_ROOT" "$ref"
    return 0
  fi
  [[ -f "$ref" ]] || return 1
  printf '%s' "$ref"
}

# Reads both tracker shapes: YAML frontmatter (wayfinder decision tickets) and a
# bold "**Status:**" line (to-tickets build tickets, specs, maps).
read_work_item_state() {
  local file="$1" status="" claim=""
  WORK_ITEM_STATUS=""
  WORK_ITEM_CLAIM=""
  [[ -f "$file" ]] || return 1

  status="$(awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR > 1 && /^---[[:space:]]*$/ { exit }
    /^status:[[:space:]]*/ { sub(/^status:[[:space:]]*/, ""); print; exit }
  ' "$file" 2>/dev/null)" || true
  claim="$(awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR > 1 && /^---[[:space:]]*$/ { exit }
    /^claimed-by:[[:space:]]*/ { sub(/^claimed-by:[[:space:]]*/, ""); print; exit }
  ' "$file" 2>/dev/null)" || true

  if [[ -z "$status" ]]; then
    status="$(sed -n -E 's/^\*\*Status:\*\*[[:space:]]*(.*)$/\1/p' "$file" 2>/dev/null | sed -n '1p')" || true
  fi

  WORK_ITEM_STATUS="$(printf '%s' "$status" | tr -d '\r' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  WORK_ITEM_CLAIM="$(printf '%s' "$claim" | tr -d '\r' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  [[ -n "$WORK_ITEM_STATUS$WORK_ITEM_CLAIM" ]]
}

work_item_is_closed() {
  local status
  status="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$status" == closed* || "$status" == resolved* || "$status" == done* ]]
}

snapshot_work_items() {
  local out_file="$1" effort_dir file relative
  : >"$out_file"
  effort_dir="$(effort_dir_for_ref "$ROOT_REF")" || return 0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    read_work_item_state "$file" || continue
    relative="${file#"$REPO_ROOT"/}"
    printf '%s\t%s\t%s\n' "$relative" "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM" >>"$out_file"
  done < <(find "$effort_dir" -maxdepth 2 -type f -name '*.md' 2>/dev/null | sort)
}

# Announces every work item whose status changed while the worker ran.
announce_work_item_changes() {
  local before="$1" after="$2" relative status claim previous changed=0
  [[ -f "$after" ]] || return 0
  while IFS=$'\t' read -r relative status claim; do
    [[ -n "$relative" ]] || continue
    previous=""
    if [[ -f "$before" ]]; then
      previous="$(awk -F'\t' -v key="$relative" '$1 == key { print $2; exit }' "$before")"
    fi
    [[ "$previous" != "$status" ]] || continue
    changed=1
    announce_activity "ticket $relative: ${previous:-untracked} -> ${status:-untracked}"
  done <"$after"
  [[ "$changed" -eq 1 ]] || record_activity "no ticket status changed in iteration $ITERATION"
}

# The completed unit must read closed before the loop trusts the tracker.
verify_completed_ref_closed() {
  local ref="$1" file
  [[ -n "$ref" ]] || return 0
  if ! file="$(resolve_work_item "$ref")"; then
    announce "could not verify ticket status: no work-item file at $ref"
    return 0
  fi
  if ! read_work_item_state "$file"; then
    announce "could not verify ticket status: no status marker in $ref"
    return 0
  fi
  if ! work_item_is_closed "$WORK_ITEM_STATUS"; then
    COMPLETED_REF_STATUS="$WORK_ITEM_STATUS"
    return 1
  fi
  record_activity "ticket $ref closed"
}

# A unit this run claimed but left open is a tracker leak on a continue/complete.
warn_open_claims() {
  local snapshot="$1" completed_ref="$2" relative status claim
  [[ -f "$snapshot" ]] || return 0
  while IFS=$'\t' read -r relative status claim; do
    [[ -n "$relative" ]] || continue
    [[ "$relative" != "$completed_ref" && "$REPO_ROOT/$relative" != "$completed_ref" ]] || continue
    # This run's identity appears in the status text (build tickets) or claimed-by (decision tickets).
    if [[ "$status" == *"$RUN_ID"* || "$claim" == *"$RUN_ID"* ]]; then
      work_item_is_closed "$status" && continue
      announce "ticket $relative is still open under this run's claim (${status:-no status})"
    fi
  done <"$snapshot"
}
