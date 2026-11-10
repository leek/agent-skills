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

# The effort directory holds the map, spec, decisions/, and tickets/ for one effort.
# Older efforts may still use issues/ as the build folder.
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
    [[ "$parent" == "tickets" || "$parent" == "issues" || "$parent" == "decisions" ]] || break
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

# True when the work item's frontmatter carries `deploy-gate: true`: the unit
# must be deployed on its own before its dependents are built.
work_item_is_deploy_gate() {
  local file="$1" value
  [[ -f "$file" ]] || file="$REPO_ROOT/$1"
  [[ -f "$file" ]] || return 1
  value="$(awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR > 1 && /^---[[:space:]]*$/ { exit }
    /^deploy-gate:[[:space:]]*/ { sub(/^deploy-gate:[[:space:]]*/, ""); print; exit }
  ' "$file" 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]#].*$//')"
  [[ "$value" == true || "$value" == yes ]]
}

# A frontmatter value without its quotes or an unquoted trailing ` # comment`: the same rule
# as clean_value in skills/scratch-status/scripts/scratch-state.sh. Change them together.
YAML_CLEAN_AWK='
  function clean(v,   q, e, rest) {
    sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
    q = substr(v, 1, 1)
    if (q == "\"" || q == "\047") {
      e = index(substr(v, 2), q)
      if (e > 0) {
        rest = substr(v, e + 2)
        sub(/^[ \t]+/, "", rest)
        if (rest == "" || substr(rest, 1, 1) == "#") return substr(v, 2, e - 1)
      }
    }
    if (substr(v, 1, 1) == "#") v = ""
    else if (match(v, /[ \t]#/)) v = substr(v, 1, RSTART - 1)
    sub(/[ \t]+$/, "", v)
    gsub(/^["\047]+|["\047]+$/, "", v)
    return v
  }
'

strip_yaml_comment() {
  awk "$YAML_CLEAN_AWK"'{ print clean($0) }'
}

# The items of a frontmatter list, one per line, in the three spellings parse_list in
# scratch-state.sh accepts: an inline `key: [a, "b"]` (the brackets may span lines), a block
# list (`key:` then `  - a` lines), and a bare `key: a, b`. A bare none, null, ~ or [] is an
# empty list. Change them together.
frontmatter_list_items() {
  local file="$1" key="$2"
  awk -v key="$key" "$YAML_CLEAN_AWK"'
    function trim_quotes(s) {
      gsub(/^[ \t\r]+|[ \t\r]+$/, "", s)
      gsub(/^["\047]+|["\047]+$/, "", s)
      return s
    }
    function print_items(s,   n, parts, i, item) {
      n = split(s, parts, ",")
      for (i = 1; i <= n; i++) {
        item = trim_quotes(parts[i])
        if (item != "") print item
      }
    }
    function print_bare(s,   value, lowered) {
      value = clean(s)
      lowered = tolower(value)
      if (lowered == "none" || lowered == "null" || lowered == "~" || lowered == "[]") return
      print_items(value)
    }
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR == 1 { next }
    /^---[[:space:]]*$/ { exit }
    in_flow {
      line = $0
      sub(/\r$/, "", line)
      close_at = index(line, "]")
      if (close_at == 0) { flow = flow " " line; next }
      print_items(flow " " substr(line, 1, close_at - 1))
      in_flow = 0
      exit
    }
    in_block {
      if ($0 !~ /^[ \t]*-/) exit
      item = $0
      sub(/^[ \t]*-[ \t]*/, "", item)
      item = clean(item)
      if (item != "") print item
      next
    }
    index($0, key ":") == 1 {
      rest = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", rest); sub(/[ \t\r]+$/, "", rest)
      if (rest == "") { in_block = 1; next }
      if (substr(rest, 1, 1) == "[") {
        close_at = index(rest, "]")
        if (close_at > 0) { print_items(substr(rest, 2, close_at - 2)); exit }
        in_flow = 1; flow = substr(rest, 2); unclosed = rest
        next
      }
      print_bare(rest)
      exit
    }
    END { if (in_flow) print_bare(unclosed) }
  ' "$file" 2>/dev/null
}

# The value of the first legacy body line `**<Label>:** value` or `<Label>: value`, any
# letter case, below the frontmatter: the lines scratch-state.sh reads for `Claimed by` and
# `Blocked by`. The label is given in lower case. Prints nothing when no line carries a value.
legacy_body_value() {
  local file="$1" label="$2"
  awk -v label="$label" '
    NR == 1 && /^---[[:space:]]*$/ { in_front = 1; next }
    in_front { if ($0 ~ /^---[[:space:]]*$/) in_front = 0; next }
    {
      line = $0
      sub(/\r$/, "", line)
      lowered = tolower(line)
      bold = "**" label ":**"
      plain = label ":"
      if (index(lowered, bold) == 1) rest = substr(line, length(bold) + 1)
      else if (index(lowered, plain) == 1) rest = substr(line, length(plain) + 1)
      else next
      gsub(/^[ \t]+|[ \t]+$/, "", rest)
      if (rest == "") next
      print rest
      exit
    }
  ' "$file" 2>/dev/null
}

# True when a legacy body value says "nobody" or "nothing", as scratch-state.sh reads it.
legacy_value_is_empty() {
  local lowered
  lowered="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ -z "$lowered" || "$lowered" == "none" || "$lowered" == "null" || "$lowered" == "-" ]]
}

# The status string the repo's triage table maps a role to (`| `role` | `string` | … |` in
# .agents/triage-labels.md, legacy docs/agents/), lowercased; the role's own name when the
# table is missing or does not list it.
triage_role_string() {
  local role="$1" candidate labels_file="" value=""
  for candidate in "${REPO_ROOT:-.}/.agents/triage-labels.md" "${REPO_ROOT:-.}/docs/agents/triage-labels.md"; do
    if [[ -f "$candidate" ]]; then
      labels_file="$candidate"
      break
    fi
  done
  if [[ -n "$labels_file" ]]; then
    value="$(awk -F'|' -v role="$role" '
      /^\|/ {
        key = $2; gsub(/[ \t`]/, "", key)
        if (tolower(key) != role) next
        if (match($3, /`[^`]+`/)) { print tolower(substr($3, RSTART + 1, RLENGTH - 2)); exit }
      }
    ' "$labels_file" 2>/dev/null | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')" || true
  fi
  printf '%s' "${value:-$role}"
}

# The first word of a status, lowercased, without backticks or asterisks: `closed (abc123)`
# and a legacy `**closed**` both read `closed`, as scratch-state.sh reads them.
status_word() {
  printf '%s' "$1" | tr -d '`*' | awk '{ print tolower($1); exit }'
}

# Reads status/claim from YAML frontmatter (all pipeline files now use it),
# falling back to a legacy bold "**Status:**" line and a legacy "**Claimed by:**"
# body line for older files.
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

  WORK_ITEM_STATUS="$(printf '%s' "$status" | tr -d '\r' | strip_yaml_comment)"
  WORK_ITEM_CLAIM="$(printf '%s' "$claim" | tr -d '\r' | strip_yaml_comment)"
  if [[ -z "$WORK_ITEM_CLAIM" ]]; then
    claim="$(legacy_body_value "$file" "claimed by")" || true
    legacy_value_is_empty "$claim" || WORK_ITEM_CLAIM="$claim"
  fi
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
  WORK_ITEM_TYPE="$(printf '%s' "$type" | tr -d '\r' | strip_yaml_comment)"
  [[ -n "$WORK_ITEM_TYPE" ]]
}

# The tracker's one closed vocabulary (load_closed_vocabulary in scratch-state.sh): closed,
# done, resolved, wontfix, declined, duplicate, and the repo's own wontfix string. A wontfix
# ticket is closed, never frontier work.
work_item_is_closed() {
  local status
  status="$(status_word "$1")"
  case "$status" in
    closed|done|resolved|wontfix|declined|duplicate) return 0 ;;
    "") return 1 ;;
  esac
  [[ "$status" == "$(triage_role_string wontfix)" ]]
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
  normalized_status="$(status_word "$normalized_status")"
  case "$normalized_status" in
    ready-for-human|needs-info|needs-triage) return 0 ;;
    "") ;;
    *)
      # The same three statuses ticket.sh refuses to claim as `human`.
      if [[ "$normalized_status" == "$(triage_role_string ready-for-human)" || "$normalized_status" == "$(triage_role_string needs-info)" || "$normalized_status" == "$(triage_role_string needs-triage)" ]]; then
        return 0
      fi
      ;;
  esac
  [[ "$mode" == "decision" && ("$normalized_type" == "grilling" || "$normalized_type" == "prototype") ]]
}

path_tracker_mode() {
  local path="$1" dir parent
  case "$path" in
    */decisions|*/decisions/*) printf 'decision' ;;
    */issues|*/issues/*) printf 'build' ;;
    */tickets|*/tickets/*)
      dir="$path"
      [[ -d "$dir" ]] || dir="$(dirname "$path")"
      parent="$(dirname "$dir")"
      if [[ -d "$parent/decisions" ]]; then
        printf 'build'
      elif [[ -d "$parent/issues" ]]; then
        printf 'decision'
      else
        printf 'build'
      fi
      ;;
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
  # A missing parent is fine: the ticket's own `## Parent` link may still name one.
  return 0
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
    elif [[ -d "$root/tickets" && -d "$root/decisions" ]]; then
      TRACKER_MODE="build"
      TRACKER_WORK_DIR="$root/tickets"
      [[ -f "$root/spec.md" ]] && TRACKER_PARENT_FILE="$root/spec.md"
    elif [[ -d "$root/issues" ]]; then
      TRACKER_MODE="build"
      TRACKER_WORK_DIR="$root/issues"
      [[ -f "$root/spec.md" ]] && TRACKER_PARENT_FILE="$root/spec.md"
    elif [[ -d "$root/tickets" ]]; then
      TRACKER_MODE="build"
      TRACKER_WORK_DIR="$root/tickets"
      [[ -f "$root/spec.md" ]] && TRACKER_PARENT_FILE="$root/spec.md"
    elif [[ -d "$root/decisions" ]]; then
      TRACKER_MODE="decision"
      TRACKER_WORK_DIR="$root/decisions"
      [[ -f "$root/map.md" ]] && TRACKER_PARENT_FILE="$root/map.md"
    else
      TRACKER_OUTCOME="blocked"
      TRACKER_REASON="root directory contains no tickets/ or decisions/ tracker: $(repo_relative_ref "$root")"
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
    if [[ -d "$(dirname "$root")/decisions" ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/decisions"
    else
      TRACKER_WORK_DIR="$(dirname "$root")/tickets"
    fi
  elif [[ "$basename_value" == spec*.md ]]; then
    TRACKER_MODE="build"
    TRACKER_PARENT_FILE="$root"
    if [[ "$basename_value" == spec-*.md ]]; then
      spec_suffix="${basename_value#spec-}"
      spec_suffix="${spec_suffix%.md}"
    fi
    if TRACKER_WORK_DIR="$(read_linked_tracker_dir "$root" build)"; then
      :
    elif [[ -n "$spec_suffix" && -d "$(dirname "$root")/tickets/$spec_suffix" ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/tickets/$spec_suffix"
    elif [[ -n "$spec_suffix" && -d "$(dirname "$root")/issues/$spec_suffix" ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/issues/$spec_suffix"
    elif [[ -d "$(dirname "$root")/tickets" && ( -d "$(dirname "$root")/decisions" || ! -d "$(dirname "$root")/issues" ) ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/tickets"
    elif [[ -d "$(dirname "$root")/issues" ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/issues"
    elif [[ -d "$(dirname "$root")/tickets" ]]; then
      TRACKER_WORK_DIR="$(dirname "$root")/tickets"
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
  return 0
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

# The one ticket beside the source file whose leading number is the first run of digits in
# the token, as written or zero-padded to the width of the source file's own number: how
# scratch-state.sh matches a blocker id to a ticket.
resolve_blocker_number() {
  local source_file="$1" token="$2" number padded width=2 candidate name matches=()
  [[ "$token" =~ ([0-9]+) ]] || return 1
  number="${BASH_REMATCH[1]}"
  name="$(basename "$source_file")"
  if [[ "$name" =~ ^([0-9]+) ]]; then
    width="${#BASH_REMATCH[1]}"
  fi
  padded="$number"
  while [[ "${#padded}" -lt "$width" ]]; do
    padded="0$padded"
  done
  for candidate in "$(dirname "$source_file")"/*.md; do
    [[ -f "$candidate" ]] || continue
    name="${candidate##*/}"
    [[ "$name" =~ ^([0-9]+) ]] || continue
    if [[ "${BASH_REMATCH[1]}" == "$padded" || "${BASH_REMATCH[1]}" == "$number" ]]; then
      matches+=("$candidate")
    fi
  done
  [[ ${matches[0]+present} && "${#matches[@]}" -eq 1 ]] || return 1
  canonical_existing_file "${matches[0]}"
}

# The whole numbers in a legacy `Blocked by` line (`\b\d+\b` in scratch-state.sh), one per line.
whole_numbers() {
  printf '%s\n' "$1" | awk '{
    s = $0
    while (match(s, /[0-9]+/)) {
      before = RSTART > 1 ? substr(s, RSTART - 1, 1) : ""
      after = substr(s, RSTART + RLENGTH, 1)
      if (before !~ /[A-Za-z_]/ && after !~ /[A-Za-z_]/) print substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
    }
  }'
}

read_work_item_blockers() {
  local file="$1" mode="$2" raw="" line token resolved by_number="true"
  local tokens=()
  RESOLVED_BLOCKERS=()
  BLOCKER_ERROR=""

  # Every ticket now carries blockers in `blocked-by` frontmatter (decision and
  # build alike), as an inline list, a block list, or a bare value. Read that
  # first; fall back to a legacy "**Blocked by:**" body line, then to a legacy
  # "## Blocked by" body section, only when the frontmatter list is absent or empty.
  while IFS= read -r token; do
    [[ -n "$token" ]] && tokens+=("$token")
  done < <(frontmatter_list_items "$file" "blocked-by")
  if [[ ! ${tokens[0]+present} ]]; then
    raw="$(legacy_body_value "$file" "blocked by")" || true
    if ! legacy_value_is_empty "$raw"; then
      while IFS= read -r token; do
        [[ -n "$token" ]] && tokens+=("$token")
      done < <(whole_numbers "$raw")
    fi
  fi
  if [[ ! ${tokens[0]+present} ]]; then
    by_number="false"
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
      if resolved="$(resolve_link_target "$file" "$token")"; then
        :
      elif [[ "$by_number" == "true" ]] && resolved="$(resolve_blocker_number "$file" "$token")"; then
        :
      else
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

# Snapshot rows are `ref<US>status<US>claim`. The unit separator is not
# whitespace, so `read` keeps an empty status in its own field.
SNAPSHOT_FIELD_SEPARATOR=$'\x1f'

snapshot_work_items() {
  local out_file="$1" effort_dir work_dir file relative
  : >"$out_file"
  effort_dir="$(effort_dir_for_ref "$ROOT_REF")" || return 0
  # The effort directory two levels deep, plus the directory the frontier is
  # selected from: a suffixed spec's tickets/<suffix>/ or a linked directory
  # sits outside that depth. The subshell keeps the TRACKER_* globals untouched.
  work_dir="$(resolve_tracker_scope >/dev/null 2>&1 || true; printf '%s' "$TRACKER_WORK_DIR")"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    read_work_item_state "$file" || continue
    relative="${file#"$REPO_ROOT"/}"
    printf '%s%s%s%s%s\n' "$relative" "$SNAPSHOT_FIELD_SEPARATOR" "$WORK_ITEM_STATUS" "$SNAPSHOT_FIELD_SEPARATOR" "$WORK_ITEM_CLAIM" >>"$out_file"
  done < <({
    find "$effort_dir" -maxdepth 2 -type f -name '*.md' 2>/dev/null
    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
      find "$work_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null
    fi
  } | sort -u)
}

# Announces every work item whose status changed while the worker ran.
announce_work_item_changes() {
  local before="$1" after="$2" relative status claim previous changed=0
  [[ -f "$after" ]] || return 0
  while IFS="$SNAPSHOT_FIELD_SEPARATOR" read -r relative status claim; do
    [[ -n "$relative" ]] || continue
    previous=""
    if [[ -f "$before" ]]; then
      previous="$(awk -F"$SNAPSHOT_FIELD_SEPARATOR" -v key="$relative" '$1 == key { print $2; exit }' "$before")"
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
  while IFS="$SNAPSHOT_FIELD_SEPARATOR" read -r relative status claim; do
    [[ -n "$relative" ]] || continue
    [[ "$relative" != "$completed_ref" && "$REPO_ROOT/$relative" != "$completed_ref" ]] || continue
    if [[ "$status" == *"$RUN_ID"* || "$claim" == *"$RUN_ID"* ]]; then
      work_item_is_closed "$status" && continue
      announce "ticket $relative is still open under this run's claim (${status:-no status})"
    fi
  done <"$snapshot"
}
