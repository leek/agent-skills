#!/bin/bash
# Deterministic tracker parsing, frontier selection, and status observation.

set -e

WORK_ITEM_STATUS=""
WORK_ITEM_CLAIM=""
WORK_ITEM_TYPE=""
RESOLVED_BLOCKERS=()
BLOCKER_ERROR=""

TRACKER_MODE=""
TRACKER_WORK_DIR=""
TRACKER_PARENT_FILE=""
TRACKER_SELECTED_FILE=""
TRACKER_SELECTED_REF=""
TRACKER_SELECTED_STATUS=""
TRACKER_SELECTED_CLAIM=""
TRACKER_SELECTED_TYPE=""
TRACKER_SELECTION=""
TRACKER_OUTCOME=""
TRACKER_NEXT_REF=""
TRACKER_REASON=""
TRACKER_CONTEXT_JSON=""
TRACKER_FRONTIER_FILES=()
TRACKER_DIRECT_BLOCKERS=()

repo_relative_ref() {
  local file="$1"
  if [[ "$file" == "$REPO_ROOT"/* ]]; then
    printf '%s' "${file#"$REPO_ROOT"/}"
  else
    printf '%s' "$file"
  fi
}

canonical_existing_file() {
  local file="$1" parent
  [[ -f "$file" ]] || return 1
  parent="$(cd "$(dirname "$file")" && pwd -P)" || return 1
  printf '%s/%s' "$parent" "$(basename "$file")"
}

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
    canonical_existing_file "$REPO_ROOT/$ref"
    return
  fi
  canonical_existing_file "$ref"
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

read_work_item_type() {
  local file="$1" type=""
  WORK_ITEM_TYPE=""
  [[ -f "$file" ]] || return 1
  type="$(awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR > 1 && /^---[[:space:]]*$/ { exit }
    /^type:[[:space:]]*/ { sub(/^type:[[:space:]]*/, ""); print; exit }
  ' "$file" 2>/dev/null)" || true
  WORK_ITEM_TYPE="$(printf '%s' "$type" | tr -d '\r' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  [[ -n "$WORK_ITEM_TYPE" ]]
}

work_item_is_closed() {
  local status
  status="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$status" == closed* || "$status" == resolved* || "$status" == done* ]]
}

work_item_is_claimed() {
  local status claim
  status="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  claim="$2"
  [[ -n "$claim" || "$status" == in-progress* || "$status" == *"claimed "* || "$status" == *"claimed("* ]]
}

work_item_is_human_gate() {
  local mode="$1" status="$2" type="$3" normalized_status normalized_type
  normalized_status="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
  normalized_type="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized_status" == ready-for-human* || "$normalized_status" == needs-input* ]]; then
    return 0
  fi
  [[ "$mode" == "decision" && ("$normalized_type" == "grilling" || "$normalized_type" == "prototype") ]]
}

path_tracker_mode() {
  local path="$1"
  case "$path" in
    */decisions|*/decisions/*) printf 'decision' ;;
    */issues|*/issues/*) printf 'build' ;;
    *) return 1 ;;
  esac
}

set_default_tracker_parent() {
  case "$TRACKER_MODE" in
    decision)
      [[ -f "$(dirname "$TRACKER_WORK_DIR")/map.md" ]] && TRACKER_PARENT_FILE="$(dirname "$TRACKER_WORK_DIR")/map.md"
      ;;
    build)
      [[ -f "$(dirname "$TRACKER_WORK_DIR")/spec.md" ]] && TRACKER_PARENT_FILE="$(dirname "$TRACKER_WORK_DIR")/spec.md"
      ;;
  esac
}

read_linked_tracker_dir() {
  local parent_file="$1" mode="$2" target candidate resolved_mode
  local matches=() unique_matches=()
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    target="${target%%#*}"
    [[ "$target" != /* ]] || candidate="$target"
    [[ "$target" == /* ]] || candidate="$(dirname "$parent_file")/$target"
    [[ -d "$candidate" ]] || continue
    candidate="$(cd "$candidate" && pwd -P)"
    resolved_mode="$(path_tracker_mode "$candidate" 2>/dev/null || true)"
    [[ "$resolved_mode" == "$mode" ]] && matches+=("$candidate")
  done < <(sed -n -E 's/.*\]\(([^)]+\/)\).*/\1/p' "$parent_file")

  if [[ ${matches[0]+present} ]]; then
    for candidate in "${matches[@]}"; do
      if [[ ! " ${unique_matches[*]-} " == *" $candidate "* ]]; then
        unique_matches+=("$candidate")
      fi
    done
  fi
  if [[ ${unique_matches[0]+present} && "${#unique_matches[@]}" -eq 1 ]]; then
    printf '%s' "${unique_matches[0]}"
    return 0
  fi
  return 1
}

resolve_tracker_scope() {
  local root="$ROOT_REF" mode="" basename_value spec_suffix=""
  TRACKER_MODE=""
  TRACKER_WORK_DIR=""
  TRACKER_PARENT_FILE=""

  [[ -e "$root" ]] || {
    TRACKER_OUTCOME="blocked"
    TRACKER_REASON="root reference does not exist: $root"
    return 1
  }

  if [[ -d "$root" ]]; then
    root="$(cd "$root" && pwd -P)"
    if mode="$(path_tracker_mode "$root")"; then
      TRACKER_MODE="$mode"
      TRACKER_WORK_DIR="$root"
      set_default_tracker_parent
    elif [[ -d "$root/issues" ]]; then
      TRACKER_MODE="build"
      TRACKER_WORK_DIR="$root/issues"
      [[ -f "$root/spec.md" ]] && TRACKER_PARENT_FILE="$root/spec.md"
    elif [[ -d "$root/decisions" ]]; then
      TRACKER_MODE="decision"
      TRACKER_WORK_DIR="$root/decisions"
      [[ -f "$root/map.md" ]] && TRACKER_PARENT_FILE="$root/map.md"
    else
      TRACKER_OUTCOME="blocked"
      TRACKER_REASON="root directory contains no issues/ or decisions/ tracker: $(repo_relative_ref "$root")"
      return 1
    fi
    return 0
  fi

  root="$(canonical_existing_file "$root")" || return 1
  basename_value="$(basename "$root")"
  if mode="$(path_tracker_mode "$root")"; then
    TRACKER_MODE="$mode"
    TRACKER_WORK_DIR="$(dirname "$root")"
  elif [[ "$basename_value" == "map.md" ]]; then
    TRACKER_MODE="decision"
    TRACKER_PARENT_FILE="$root"
    TRACKER_WORK_DIR="$(dirname "$root")/decisions"
  elif [[ "$basename_value" == spec*.md ]]; then
    TRACKER_MODE="build"
    TRACKER_PARENT_FILE="$root"
    if [[ "$basename_value" == spec-*.md ]]; then
      spec_suffix="${basename_value#spec-}"
      spec_suffix="${spec_suffix%.md}"
    fi
    if TRACKER_WORK_DIR="$(read_linked_tracker_dir "$root" build)"; then
      :
    elif [[ -n "$spec_suffix" && -d "$(dirname "$root")/issues/$spec_suffix" ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/issues/$spec_suffix"
    elif [[ -d "$(dirname "$root")/issues" ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/issues"
    else
      TRACKER_MODE="direct-spec"
      TRACKER_WORK_DIR="$(dirname "$root")"
    fi
  else
    read_work_item_type "$root" || true
    if [[ -n "$WORK_ITEM_TYPE" ]]; then
      TRACKER_MODE="decision"
    else
      TRACKER_MODE="build"
    fi
    TRACKER_WORK_DIR="$(dirname "$root")"
  fi
  [[ -n "$TRACKER_PARENT_FILE" ]] || set_default_tracker_parent
}

resolve_link_target() {
  local source_file="$1" token="$2" candidate="" matches=()
  token="$(printf '%s' "$token" | sed -E 's/^[[:space:]`"]+//;s/[[:space:]`"]+$//')"
  token="${token#\'}"
  token="${token%\'}"
  token="${token%%#*}"
  [[ -n "$token" ]] || return 1

  if [[ "$token" == /* ]]; then
    candidate="$token"
  else
    candidate="$(dirname "$source_file")/$token"
  fi
  if [[ -f "$candidate" ]]; then
    canonical_existing_file "$candidate"
    return
  fi

  if [[ "$token" =~ ^[0-9]+$ ]]; then
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] && matches+=("$candidate")
    done < <(find "$(dirname "$source_file")" -maxdepth 1 -type f -name "${token}-*.md" 2>/dev/null | sort)
    if [[ ${matches[0]+present} && "${#matches[@]}" -eq 1 ]]; then
      canonical_existing_file "${matches[0]}"
      return
    fi
  fi
  return 1
}

read_work_item_blockers() {
  local file="$1" mode="$2" raw="" line token resolved
  local tokens=()
  RESOLVED_BLOCKERS=()
  BLOCKER_ERROR=""

  if [[ "$mode" == "decision" ]]; then
    raw="$(awk '
      NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
      NR > 1 && /^---[[:space:]]*$/ { exit }
      /^blocked-by:[[:space:]]*/ { sub(/^blocked-by:[[:space:]]*/, ""); print; exit }
    ' "$file" 2>/dev/null)" || true
    raw="$(printf '%s' "$raw" | tr -d '[]')"
    while IFS= read -r token; do
      token="$(printf '%s' "$token" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
      [[ -n "$token" ]] && tokens+=("$token")
    done < <(printf '%s' "$raw" | tr ',' '\n')
  else
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      if printf '%s' "$line" | grep -Eiq 'none|nothing|no blockers'; then
        continue
      fi
      token="$(printf '%s' "$line" | sed -n -E 's/.*\]\(([^)]+)\).*/\1/p')"
      if [[ -z "$token" ]]; then
        token="$(printf '%s' "$line" | sed -n -E 's/.*`([^`]+\.md)`.*/\1/p')"
      fi
      if [[ -z "$token" ]]; then
        token="$(printf '%s' "$line" | grep -Eo '([.][.]\/|[[:alnum:]_.-]+\/)*[[:alnum:]_.-]+\.md' | sed -n '1p')" || true
      fi
      [[ -n "$token" ]] && tokens+=("$token")
    done < <(awk '
      /^## Blocked by[[:space:]]*$/ { inside=1; next }
      inside && /^##[[:space:]]/ { exit }
      inside { print }
    ' "$file")
  fi

  if [[ ${tokens[0]+present} ]]; then
    for token in "${tokens[@]}"; do
      if ! resolved="$(resolve_link_target "$file" "$token")"; then
        BLOCKER_ERROR="missing or ambiguous blocker '$token' referenced by $(repo_relative_ref "$file")"
        return 1
      fi
      RESOLVED_BLOCKERS+=("$resolved")
    done
  fi
}

read_parent_file() {
  local file="$1" target="" resolved=""
  target="$(awk '
    /^## Parent[[:space:]]*$/ { inside=1; next }
    inside && /^##[[:space:]]/ { exit }
    inside { print }
  ' "$file" | sed -n -E 's/.*\]\(([^)]+)\).*/\1/p' | sed -n '1p')"
  if [[ -n "$target" ]] && resolved="$(resolve_link_target "$file" "$target")"; then
    printf '%s' "$resolved"
    return 0
  fi
  return 1
}

candidate_files() {
  [[ -d "$TRACKER_WORK_DIR" ]] || return 0
  find "$TRACKER_WORK_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort
}

candidate_blockers_are_closed() {
  local file="$1" blocker
  read_work_item_blockers "$file" "$TRACKER_MODE" || return 2
  if [[ ${RESOLVED_BLOCKERS[0]+present} ]]; then
    for blocker in "${RESOLVED_BLOCKERS[@]}"; do
      if ! read_work_item_state "$blocker" || ! work_item_is_closed "$WORK_ITEM_STATUS"; then
        return 1
      fi
    done
  fi
  return 0
}

select_tracker_item() {
  local file="$1" selection="$2" parent=""
  TRACKER_SELECTED_FILE="$file"
  TRACKER_SELECTED_REF="$(repo_relative_ref "$file")"
  read_work_item_state "$file" || true
  TRACKER_SELECTED_STATUS="$WORK_ITEM_STATUS"
  TRACKER_SELECTED_CLAIM="$WORK_ITEM_CLAIM"
  read_work_item_type "$file" || true
  TRACKER_SELECTED_TYPE="$WORK_ITEM_TYPE"
  TRACKER_SELECTION="$selection"
  read_work_item_blockers "$file" "$TRACKER_MODE" || true
  if [[ ${RESOLVED_BLOCKERS[0]+present} ]]; then
    TRACKER_DIRECT_BLOCKERS=("${RESOLVED_BLOCKERS[@]}")
  else
    TRACKER_DIRECT_BLOCKERS=()
  fi

  if [[ -z "$TRACKER_PARENT_FILE" ]] && parent="$(read_parent_file "$file")"; then
    TRACKER_PARENT_FILE="$parent"
  elif [[ -z "$TRACKER_PARENT_FILE" && "$TRACKER_MODE" == "decision" && -f "$(dirname "$TRACKER_WORK_DIR")/map.md" ]]; then
    TRACKER_PARENT_FILE="$(dirname "$TRACKER_WORK_DIR")/map.md"
  elif [[ -z "$TRACKER_PARENT_FILE" && "$TRACKER_MODE" == "build" && -f "$(dirname "$TRACKER_WORK_DIR")/spec.md" ]]; then
    TRACKER_PARENT_FILE="$(dirname "$TRACKER_WORK_DIR")/spec.md"
  fi
}

json_array_from_refs() {
  if [[ "$#" -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s\n' "$@" | jq -Rsc 'split("\n")[:-1]'
}

tracker_manifest_json() {
  local frontier_refs=() blocker_objects="[]" blocker ref status claim head_sha parent_ref=""
  if [[ ${TRACKER_FRONTIER_FILES[0]+present} ]]; then
    for ref in "${TRACKER_FRONTIER_FILES[@]}"; do
      frontier_refs+=("$(repo_relative_ref "$ref")")
    done
  fi
  if [[ ${TRACKER_DIRECT_BLOCKERS[0]+present} ]]; then
    blocker_objects="$({
      for blocker in "${TRACKER_DIRECT_BLOCKERS[@]}"; do
        read_work_item_state "$blocker" || true
        ref="$(repo_relative_ref "$blocker")"
        status="$WORK_ITEM_STATUS"
        claim="$WORK_ITEM_CLAIM"
        jq -cn --arg ref "$ref" --arg status "$status" --arg claim "$claim" \
          '{ref:$ref,status:$status,claim:(if $claim == "" then null else $claim end)}'
      done
    } | jq -sc '.')"
  fi
  [[ -z "$TRACKER_PARENT_FILE" ]] || parent_ref="$(repo_relative_ref "$TRACKER_PARENT_FILE")"
  head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
  jq -cn \
    --arg mode "$TRACKER_MODE" \
    --arg root "$(repo_relative_ref "$ROOT_REF")" \
    --arg selected_ref "$TRACKER_SELECTED_REF" \
    --arg selection "$TRACKER_SELECTION" \
    --arg status "$TRACKER_SELECTED_STATUS" \
    --arg claim "$TRACKER_SELECTED_CLAIM" \
    --arg type "$TRACKER_SELECTED_TYPE" \
    --arg parent_ref "$parent_ref" \
    --arg head "$head_sha" \
    --argjson frontier "$(if [[ ${frontier_refs[0]+present} ]]; then json_array_from_refs "${frontier_refs[@]}"; else json_array_from_refs; fi)" \
    --argjson direct_blockers "$blocker_objects" \
    '{
      mode:$mode,
      root_ref:$root,
      selected_ref:$selected_ref,
      selection:$selection,
      status:$status,
      claim:(if $claim == "" then null else $claim end),
      type:(if $type == "" then null else $type end),
      parent_ref:(if $parent_ref == "" then null else $parent_ref end),
      direct_blockers:$direct_blockers,
      frontier:$frontier,
      head:$head
    }'
}

tracker_refresh() {
  local file state root_file="" blocker_result open_count=0 claimed_count=0 closed_count=0
  local own_claims=() candidates=() human_frontier=()
  TRACKER_SELECTED_FILE=""
  TRACKER_SELECTED_REF=""
  TRACKER_SELECTED_STATUS=""
  TRACKER_SELECTED_CLAIM=""
  TRACKER_SELECTED_TYPE=""
  TRACKER_SELECTION=""
  TRACKER_OUTCOME=""
  TRACKER_NEXT_REF=""
  TRACKER_REASON=""
  TRACKER_CONTEXT_JSON=""
  TRACKER_FRONTIER_FILES=()
  TRACKER_DIRECT_BLOCKERS=()

  resolve_tracker_scope || return 0

  if [[ "$TRACKER_MODE" == "direct-spec" ]]; then
    root_file="$(canonical_existing_file "$ROOT_REF")" || {
      TRACKER_OUTCOME="blocked"
      TRACKER_REASON="direct spec does not exist: $ROOT_REF"
      return 0
    }
    read_work_item_state "$root_file" || WORK_ITEM_STATUS="open"
    if work_item_is_closed "$WORK_ITEM_STATUS"; then
      TRACKER_OUTCOME="complete"
      TRACKER_REASON="direct spec is closed"
      return 0
    fi
    if [[ "$WORK_ITEM_STATUS" == *"$RUN_ID"* || "$WORK_ITEM_CLAIM" == *"$RUN_ID"* ]]; then
      select_tracker_item "$root_file" "resume"
    elif work_item_is_claimed "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM"; then
      TRACKER_OUTCOME="blocked"
      TRACKER_REASON="the direct spec is claimed by another session: $(repo_relative_ref "$root_file")"
      return 0
    else
      select_tracker_item "$root_file" "direct"
    fi
    TRACKER_FRONTIER_FILES=("$root_file")
    TRACKER_OUTCOME="selected"
    TRACKER_NEXT_REF="$TRACKER_SELECTED_REF"
    TRACKER_CONTEXT_JSON="$(tracker_manifest_json)"
    return 0
  fi

  while IFS= read -r file; do
    [[ -n "$file" ]] && candidates+=("$file")
  done < <(candidate_files)

  if [[ ! ${candidates[0]+present} ]]; then
    if [[ "$TRACKER_MODE" == "decision" ]]; then
      TRACKER_OUTCOME="needs_input"
      TRACKER_NEXT_REF="$(repo_relative_ref "${TRACKER_PARENT_FILE:-$ROOT_REF}")"
      TRACKER_REASON="the map has no autonomous decision ticket; continue wayfinding interactively"
    else
      TRACKER_OUTCOME="blocked"
      TRACKER_REASON="the build scope contains no ticket files"
    fi
    return 0
  fi

  for file in "${candidates[@]}"; do
    read_work_item_state "$file" || continue
    if work_item_is_closed "$WORK_ITEM_STATUS"; then
      closed_count=$((closed_count + 1))
      continue
    fi
    open_count=$((open_count + 1))
    if [[ "$WORK_ITEM_STATUS" == *"$RUN_ID"* || "$WORK_ITEM_CLAIM" == *"$RUN_ID"* ]]; then
      own_claims+=("$file")
    elif work_item_is_claimed "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM"; then
      claimed_count=$((claimed_count + 1))
    fi

    if candidate_blockers_are_closed "$file"; then
      read_work_item_state "$file" || true
      read_work_item_type "$file" || true
      if ! work_item_is_claimed "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM"; then
        if work_item_is_human_gate "$TRACKER_MODE" "$WORK_ITEM_STATUS" "$WORK_ITEM_TYPE"; then
          human_frontier+=("$file")
        else
          TRACKER_FRONTIER_FILES+=("$file")
        fi
      fi
    else
      blocker_result=$?
      if [[ "$blocker_result" -eq 2 ]]; then
        TRACKER_OUTCOME="blocked"
        TRACKER_REASON="$BLOCKER_ERROR"
        return 0
      fi
    fi
  done

  if [[ ${own_claims[0]+present} && "${#own_claims[@]}" -gt 1 ]]; then
    TRACKER_OUTCOME="blocked"
    TRACKER_REASON="this run owns more than one open claim; resolve the tracker before resuming"
    return 0
  fi
  if [[ ${own_claims[0]+present} && "${#own_claims[@]}" -eq 1 ]]; then
    select_tracker_item "${own_claims[0]}" "resume"
    TRACKER_OUTCOME="selected"
    TRACKER_NEXT_REF="$TRACKER_SELECTED_REF"
    TRACKER_CONTEXT_JSON="$(tracker_manifest_json)"
    return 0
  fi

  if [[ -f "$ROOT_REF" ]]; then
    root_file="$(canonical_existing_file "$ROOT_REF")" || true
    if [[ -n "$root_file" && "$(dirname "$root_file")" == "$TRACKER_WORK_DIR" ]]; then
      read_work_item_state "$root_file" || true
      if [[ -n "$WORK_ITEM_STATUS" ]] && ! work_item_is_closed "$WORK_ITEM_STATUS"; then
        if work_item_is_claimed "$WORK_ITEM_STATUS" "$WORK_ITEM_CLAIM"; then
          TRACKER_OUTCOME="blocked"
          TRACKER_REASON="the requested unit is claimed by another session: $(repo_relative_ref "$root_file")"
          return 0
        fi
        if candidate_blockers_are_closed "$root_file"; then
          read_work_item_state "$root_file" || true
          read_work_item_type "$root_file" || true
          if work_item_is_human_gate "$TRACKER_MODE" "$WORK_ITEM_STATUS" "$WORK_ITEM_TYPE"; then
            TRACKER_OUTCOME="needs_input"
            TRACKER_NEXT_REF="$(repo_relative_ref "$root_file")"
            TRACKER_REASON="the requested frontier unit requires a live human session"
            return 0
          fi
          select_tracker_item "$root_file" "requested"
          TRACKER_OUTCOME="selected"
          TRACKER_NEXT_REF="$TRACKER_SELECTED_REF"
          TRACKER_CONTEXT_JSON="$(tracker_manifest_json)"
          return 0
        fi
        blocker_result=$?
        TRACKER_OUTCOME="blocked"
        if [[ "$blocker_result" -eq 2 ]]; then
          TRACKER_REASON="$BLOCKER_ERROR"
        else
          TRACKER_REASON="the requested unit is blocked: $(repo_relative_ref "$root_file")"
        fi
        return 0
      fi
    fi
  fi

  if [[ ${TRACKER_FRONTIER_FILES[0]+present} ]]; then
    select_tracker_item "${TRACKER_FRONTIER_FILES[0]}" "frontier"
    TRACKER_OUTCOME="selected"
    TRACKER_NEXT_REF="$TRACKER_SELECTED_REF"
    TRACKER_CONTEXT_JSON="$(tracker_manifest_json)"
    return 0
  fi

  if [[ ${human_frontier[0]+present} ]]; then
    TRACKER_OUTCOME="needs_input"
    TRACKER_NEXT_REF="$(repo_relative_ref "${human_frontier[0]}")"
    TRACKER_REASON="the next frontier unit requires a live human session"
  elif [[ "$open_count" -eq 0 && "$closed_count" -gt 0 ]]; then
    if [[ "$TRACKER_MODE" == "decision" ]]; then
      TRACKER_OUTCOME="needs_input"
      TRACKER_NEXT_REF="$(repo_relative_ref "${TRACKER_PARENT_FILE:-$ROOT_REF}")"
      TRACKER_REASON="every decision ticket is closed; hand the map to to-spec"
    else
      TRACKER_OUTCOME="complete"
      TRACKER_REASON="every build ticket in scope is closed"
    fi
  else
    TRACKER_OUTCOME="blocked"
    TRACKER_REASON="no autonomous frontier exists among $open_count open items ($claimed_count claimed)"
  fi
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
    return 1
  fi
  if ! read_work_item_state "$file"; then
    announce "could not verify ticket status: no status marker in $ref"
    return 1
  fi
  if ! work_item_is_closed "$WORK_ITEM_STATUS"; then
    COMPLETED_REF_STATUS="$WORK_ITEM_STATUS"
    return 1
  fi
  record_activity "ticket $ref closed"
}

verify_completed_ref_selected() {
  local completed_ref="$1" selected_file="$2" completed_file
  completed_file="$(resolve_work_item "$completed_ref")" || return 1
  [[ "$completed_file" == "$selected_file" ]]
}

# A unit this run claimed but left open is a tracker leak on a continue/complete.
warn_open_claims() {
  local snapshot="$1" completed_ref="$2" relative status claim
  [[ -f "$snapshot" ]] || return 0
  while IFS=$'\t' read -r relative status claim; do
    [[ -n "$relative" ]] || continue
    [[ "$relative" != "$completed_ref" && "$REPO_ROOT/$relative" != "$completed_ref" ]] || continue
    if [[ "$status" == *"$RUN_ID"* || "$claim" == *"$RUN_ID"* ]]; then
      work_item_is_closed "$status" && continue
      announce "ticket $relative is still open under this run's claim (${status:-no status})"
    fi
  done <"$snapshot"
}
