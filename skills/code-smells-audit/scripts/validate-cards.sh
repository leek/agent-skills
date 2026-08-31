#!/bin/bash
# Structurally validate the code-smells-audit card set.
#
# Usage: validate-cards.sh [--partial] [skill-dir]
#
#   --partial   Missing cards are reported as pending instead of failing.
#               Default is strict mode: all 56 cards must exist (ship gate).
#   skill-dir   Skill folder to validate. Defaults to the script's parent.
#
# Human-readable status goes to stderr; a JSON result goes to stdout.
# Exit 0 on pass, 1 on fail.

set -e

MODE=strict
SKILL_DIR=""
ABORT_REASON=""
CHECKS=0

TAB="$(printf '\t')"
US="$(printf '\037')"  # failure-record field separator; cannot occur in content

# JSON string escaping: backslash, quote, tab; any other control char dropped
esc() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
    | tr -d '\000-\037'
}

# stdout must always carry parseable JSON, even if set -e aborts mid-run
JSON_EMITTED=""
on_exit() {
  status=$?
  if [ "$status" -ne 0 ] && [ -z "$JSON_EMITTED" ]; then
    printf '{"pass": false, "mode": "%s", "cards_present": 0, "cards_pending": 0, "checks": %s, "failures": [{"file": "-", "reason": "%s"}], "pending": []}\n' \
      "$MODE" "${CHECKS:-0}" "$(esc "${ABORT_REASON:-validator aborted unexpectedly before completing}")"
  fi
}
trap on_exit EXIT

for arg in "$@"; do
  case "$arg" in
    --partial) MODE=partial ;;
    --strict) MODE=strict ;;
    -h|--help) sed -n '2,11p' "$0" >&2; exit 0 ;;
    -*) ABORT_REASON="unknown option: $arg"; echo "unknown option: $arg" >&2; exit 2 ;;
    *) SKILL_DIR="$arg" ;;
  esac
done
if [ -z "$SKILL_DIR" ]; then
  SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi
if [ ! -d "$SKILL_DIR" ]; then
  ABORT_REASON="skill directory not found: $SKILL_DIR"
  echo "skill directory not found: $SKILL_DIR" >&2
  exit 2
fi
SMELLS_DIR="$SKILL_DIR/references/smells"
INDEX="$SKILL_DIR/references/index.md"

# Ground truth: slug|title|occurrence lens, derived from upstream frontmatter
# (Luzkan/smells). This table (not the index) is the source of record; the
# index is one of the things being validated against it.
CATALOG='afraid-to-fail|Afraid To Fail|Responsibility
alternative-classes-with-different-interfaces|Alternative Classes with Different Interfaces|Duplication
base-class-depends-on-subclass|Base Class depends on Subclass|Interfaces
binary-operator-in-name|Binary Operator in Name|Names
boolean-blindness|Boolean Blindness|Names
callback-hell|Callback Hell|Conditional Logic
clever-code|Clever Code|Unnecessary Complexity
combinatorial-explosion|Combinatorial Explosion|Responsibility
complicated-boolean-expression|Complicated Boolean Expression|Conditional Logic
complicated-regex-expression|Complicated Regex Expression|Names
conditional-complexity|Conditional Complexity|Conditional Logic
data-clump|Data Clump|Data
dead-code|Dead Code|Unnecessary Complexity
divergent-change|Divergent Change|Responsibility
dubious-abstraction|Dubious Abstraction|Responsibility
duplicated-code|Duplicated Code|Duplication
fallacious-comment|Fallacious Comment|Names
fallacious-method-name|Fallacious Method Name|Names
fate-over-action|Fate over Action|Responsibility
feature-envy|Feature Envy|Responsibility
flag-argument|Flag Argument|Conditional Logic
global-data|Global Data|Data
hidden-dependencies|Hidden Dependencies|Data
imperative-loops|Imperative Loops|Unnecessary Complexity
inappropriate-static|Inappropriate Static|Interfaces
incomplete-library-class|Incomplete Library Class|Interfaces
inconsistent-names|Inconsistent Names|Names
inconsistent-style|Inconsistent Style|Names
indecent-exposure|Indecent Exposure|Data
insider-trading|Insider Trading|Responsibility
large-class|Large Class|Measured Smells
lazy-element|Lazy Element|Unnecessary Complexity
long-method|Long Method|Measured Smells
long-parameter-list|Long Parameter List|Measured Smells
magic-number|Magic Number|Names
message-chain|Message Chain|Message Calls
middle-man|Middle Man|Message Calls
mutable-data|Mutable Data|Data
null-check|Null Check|Conditional Logic
obscured-intent|Obscured Intent|Unnecessary Complexity
oddball-solution|Oddball Solution|Duplication
parallel-inheritance-hierarchies|Parallel Inheritance Hierarchies|Responsibility
primitive-obsession|Primitive Obsession|Data
refused-bequest|Refused Bequest|Interfaces
required-setup-or-teardown-code|Required Setup or Teardown Code|Responsibility
shotgun-surgery|Shotgun Surgery|Responsibility
side-effects|Side Effects|Responsibility
special-case|Special Case|Conditional Logic
speculative-generality|Speculative Generality|Unnecessary Complexity
status-variable|Status Variable|Unnecessary Complexity
temporary-field|Temporary Field|Data
tramp-data|Tramp Data|Data
type-embedded-in-name|Type Embedded in Name|Names
uncommunicative-name|Uncommunicative Name|Names
vertical-separation|Vertical Separation|Measured Smells
what-comment|"What" Comment|Names'

EXPANSES='Within
Between'
OBSTRUCTIONS='Bloaters
Change Preventers
Couplers
Data Dealers
Dispensables
Functional Abusers
Lexical Abusers
Obfuscators
Object Oriented Abusers
Other'
LENSES='Responsibility
Names
Data
Unnecessary Complexity
Conditional Logic
Interfaces
Measured Smells
Duplication
Message Calls'
EDGE_TYPES='causes
caused
family
co-exist
antagonistic'
REQUIRED_HEADINGS='## Detection heuristics
### Agnostic
### PHP / Laravel
### TS / React
## Example
## Refactorings
## Related smells
## Also known as'

FAILURES=""   # one failure record per line: file<US>reason
PENDING=""    # one pending slug per line

# Canonical refactoring vocabulary, derived from the normalization map:
# '=' rows are canonical as-is; mapped rows contribute their canonical
# name(s), composites split on ' + '.
NAMES_MAP="$SKILL_DIR/references/refactoring-names.md"
CANONICAL_REFACTORS=""
if [ -f "$NAMES_MAP" ]; then
  CANONICAL_REFACTORS="$(sed -n 's/^| \(.*\) | \(.*\) |$/\1	\2/p' "$NAMES_MAP" \
    | awk -F'\t' '$1 != "Upstream name" && $1 !~ /^-+$/ {
        if ($2 == "=") { print $1 }
        else { n = split($2, parts, " \\+ "); for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", parts[i]); print parts[i] } }
      }' | sort -u)"
fi

check() { CHECKS=$((CHECKS + 1)); }
fail() { # $1 file, $2 reason
  FAILURES="${FAILURES}${1}${US}${2}
"
  echo "FAIL: $1: $2" >&2
}
in_list() { # $1 needle, $2 newline-separated haystack
  printf '%s\n' "$2" | grep -Fxq -- "$1"
}
catalog_field() { # $1 slug, $2 field number -> value
  printf '%s\n' "$CATALOG" | awk -F'|' -v s="$1" -v f="$2" '$1 == s { print $f }'
}

echo "Validating $SKILL_DIR (mode: $MODE)" >&2

if [ ! -d "$SMELLS_DIR" ]; then
  fail "references/smells" "directory missing"
fi
if [ ! -f "$INDEX" ]; then
  fail "references/index.md" "index missing"
fi

# --- Check 1: card set: every expected slug present, nothing unexpected ---
PRESENT=""
while IFS='|' read -r slug _title _lens; do
  check
  if [ -f "$SMELLS_DIR/$slug.md" ]; then
    PRESENT="${PRESENT}${slug}
"
  elif [ "$MODE" = partial ]; then
    PENDING="${PENDING}${slug}
"
  else
    fail "references/smells/$slug.md" "card missing (strict mode requires all 56)"
  fi
done <<EOF
$CATALOG
EOF

if [ -d "$SMELLS_DIR" ]; then
  for f in "$SMELLS_DIR"/*; do
    [ -e "$f" ] || continue
    check
    name="$(basename "$f")"
    case "$name" in
      *.md)
        if [ -z "$(catalog_field "${name%.md}" 1)" ]; then
          fail "references/smells/$name" "unexpected card: slug not in the 56-smell catalog"
        fi
        ;;
      *) fail "references/smells/$name" "unexpected non-card file in smells directory" ;;
    esac
  done
fi

# --- Checks 2-4: per-card format, taxonomy vocabulary, related-smell links ---
while read -r slug; do
  [ -n "$slug" ] || continue
  file="references/smells/$slug.md"
  path="$SMELLS_DIR/$slug.md"
  card="$(cat "$path" 2>/dev/null || true)"
  check
  if [ -z "$card" ]; then
    fail "$file" "card is empty or unreadable"
    continue
  fi
  title="$(catalog_field "$slug" 2)"
  lens="$(catalog_field "$slug" 3)"

  # Title heading
  check
  if [ "$(printf '%s\n' "$card" | head -n 1)" != "# $title" ]; then
    fail "$file" "first line is not '# $title'"
  fi

  # Taxonomy line: `Expanse · Obstruction · Occurrence`
  check
  tax="$(printf '%s\n' "$card" | grep -m1 '^`.*·.*·.*`$' || true)"
  if [ -z "$tax" ]; then
    fail "$file" "taxonomy line (\`Expanse · Obstruction · Occurrence\`) missing"
  else
    tax="${tax#\`}"; tax="${tax%\`}"
    expanse="$(printf '%s' "$tax" | awk -F' · ' '{print $1}')"
    obstruction="$(printf '%s' "$tax" | awk -F' · ' '{print $2}')"
    occurrence="$(printf '%s' "$tax" | awk -F' · ' '{print $3}')"
    check; in_list "$expanse" "$EXPANSES" || fail "$file" "expanse '$expanse' not in closed vocabulary"
    check; in_list "$obstruction" "$OBSTRUCTIONS" || fail "$file" "obstruction '$obstruction' not in closed vocabulary"
    check; in_list "$occurrence" "$LENSES" || fail "$file" "occurrence '$occurrence' not in closed vocabulary"
    check
    if [ "$occurrence" != "$lens" ] && in_list "$occurrence" "$LENSES"; then
      fail "$file" "occurrence '$occurrence' does not match catalog lens '$lens'"
    fi
  fi

  # Required section headings, each exactly once
  while read -r heading; do
    check
    n="$(printf '%s\n' "$card" | grep -cFx -- "$heading" || true)"
    if [ "$n" -eq 0 ]; then
      fail "$file" "required section '$heading' missing"
    elif [ "$n" -gt 1 ]; then
      fail "$file" "section '$heading' appears $n times"
    fi
  done <<EOF
$REQUIRED_HEADINGS
EOF

  # Definition: prose between the taxonomy line and '## Detection heuristics'
  check
  def="$(printf '%s\n' "$card" | sed -n '/^`.*·.*·.*`$/,/^## Detection heuristics$/p' | sed '1d;$d' | grep -cv '^[[:space:]]*$' || true)"
  if [ "$def" -eq 0 ]; then
    fail "$file" "no definition prose between taxonomy line and detection heuristics"
  fi

  # Every leaf section must have content, not just a heading ('## Detection
  # heuristics' is a container; its content is the three ### subsections)
  while read -r heading; do
    [ "$heading" = "## Detection heuristics" ] && continue
    check
    body="$(printf '%s\n' "$card" | awk -v h="$heading" '
      $0 == h { insec = 1; next }
      insec && /^#/ { exit }
      insec && NF > 0 { n++ }
      END { print n + 0 }')"
    if [ "$body" -eq 0 ]; then
      fail "$file" "section '$heading' is empty"
    fi
  done <<EOF
$REQUIRED_HEADINGS
EOF

  # Code fences: at least one PHP/TS example; Python explicitly banned.
  # Capture the whole info string so 'JS', 'py3', or 'php title=x' can't
  # slip past a lowercase-only pattern.
  check
  fences="$(printf '%s\n' "$card" | sed -n 's/^```\(..*\)$/\1/p')"
  if [ -z "$fences" ]; then
    fail "$file" "no code example fence"
  else
    check
    printf '%s\n' "$fences" | grep -qx 'php\|ts\|tsx' || fail "$file" "no PHP or TS example fence (php/ts/tsx)"
    while read -r lang; do
      check
      case "$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')" in
        py|python|py3|python3) fail "$file" "code fence language '$lang' is banned (examples are PHP or TS)" ;;
      esac
    done <<EOF
$fences
EOF
  fi

  # Example provenance: translated from upstream or authored from definition
  check
  prov="$(printf '%s\n' "$card" | awk '
    $0 == "## Example" { insec = 1; next }
    insec && /^#/ { exit }
    insec && tolower($0) ~ /upstream/ { n++ }
    END { print n + 0 }')"
  if [ "$prov" -eq 0 ]; then
    fail "$file" "example section does not state provenance (translated from upstream / authored, no upstream example)"
  fi

  # Refactoring names must be canonical per references/refactoring-names.md
  if [ -n "$CANONICAL_REFACTORS" ]; then
    refs="$(printf '%s\n' "$card" | awk '
      $0 == "## Refactorings" { insec = 1; next }
      insec && /^#/ { exit }
      insec && /^- / { sub(/^- /, ""); sub(/, .*$/, ""); print }')"
    while read -r rname; do
      [ -n "$rname" ] || continue
      check
      in_list "$rname" "$CANONICAL_REFACTORS" || fail "$file" "refactoring '$rname' is not a canonical name from refactoring-names.md"
    done <<EOF
$refs
EOF
  fi

  # Derivative-work footer
  check
  printf '%s\n' "$card" | grep -q 'Derivative work' || fail "$file" "derivative-work attribution footer missing"

  # Related smells: at least one row; every table row parseable; no duplicate
  # targets; targets in catalog; edges in vocabulary; links resolvable
  # (strict: must exist; partial: pending targets allowed)
  rel="$(printf '%s\n' "$card" | sed -n '/^## Related smells$/,/^## /p' | sed '1d')"
  rows="$(printf '%s\n' "$rel" | sed -n 's/^| \[\(.*\)](\([a-z-]*\)\.md) | \(.*\) |$/\2	\3/p')"
  check
  if [ -z "$rows" ]; then
    fail "$file" "related-smells table has no rows (every smell has at least one upstream relation)"
  fi
  # any table line that is neither header, separator, nor a parsed row is a
  # silent exemption, fail loudly instead
  check
  data_rows="$(printf '%s\n' "$rel" | grep -c '^|' || true)"
  meta_rows="$(printf '%s\n' "$rel" | grep -Ec '^\| Smell \| Edge \|$|^\|[-| ]*\|$' || true)"
  parsed_rows="$(printf '%s\n' "$rows" | grep -c . || true)"
  if [ "$((data_rows - meta_rows))" -ne "$parsed_rows" ]; then
    fail "$file" "related-smells table has $((data_rows - meta_rows)) data row(s) but only $parsed_rows parse as '| [Title](slug.md) | edges |'"
  fi
  check
  dup_targets="$(printf '%s\n' "$rows" | cut -f1 | sort | uniq -d)"
  while read -r dup; do
    [ -n "$dup" ] || continue
    fail "$file" "related-smell target '$dup' appears in multiple rows (merge edge types into one row)"
  done <<EOF
$dup_targets
EOF
  # edge-vocabulary legend (card convention from the pilot)
  check
  printf '%s\n' "$rel" | grep -q '^Edge vocabulary:' || fail "$file" "edge-vocabulary legend line missing from related-smells section"
  while IFS='	' read -r target edges; do
    [ -n "$target" ] || continue
    check
    if [ -z "$(catalog_field "$target" 1)" ]; then
      fail "$file" "related-smell link '$target.md' is not a catalog slug"
    elif [ ! -f "$SMELLS_DIR/$target.md" ] && [ "$MODE" = strict ]; then
      fail "$file" "related-smell link '$target.md' does not resolve to a card"
    fi
    old_ifs="$IFS"; IFS=','
    for edge in $edges; do
      IFS="$old_ifs"
      edge="$(printf '%s' "$edge" | sed 's/^ *//; s/ *$//')"
      [ -n "$edge" ] || continue
      check
      in_list "$edge" "$EDGE_TYPES" || fail "$file" "edge type '$edge' not in vocabulary (causes/caused/family/co-exist/antagonistic)"
    done
    IFS="$old_ifs"
  done <<EOF
$rows
EOF
done <<EOF
$PRESENT
EOF

# --- Check 5: index lists all 56 exactly once, under the right lens ---
if [ -f "$INDEX" ]; then
  # entries as: lens<TAB>title<TAB>slug-or-empty
  ENTRIES="$(awk '
    BEGIN { lens = "" }
    /^## / { lens = $0; sub(/^## /, "", lens); sub(/ \([0-9]+\)$/, "", lens); next }
    /^- \*\*/ {
      line = $0
      sub(/^- \*\*/, "", line)
      slug = ""
      if (line ~ /^\[/) {
        title = line; sub(/^\[/, "", title); sub(/\]\(.*$/, "", title)
        slug = line; sub(/^.*\(smells\//, "", slug); sub(/\.md\).*$/, "", slug)
      } else {
        title = line; sub(/\*\*.*$/, "", title)
      }
      print lens "\t" title "\t" slug
    }' "$INDEX" 2>/dev/null || true)"

  total="$(printf '%s\n' "$ENTRIES" | grep -c . || true)"
  check
  if [ "$total" -ne 56 ]; then
    fail "references/index.md" "index has $total entries, expected 56"
  fi

  while IFS='|' read -r slug title lens; do
    matches="$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v t="$title" '$2 == t' | wc -l | tr -d ' ')"
    check
    if [ "$matches" -eq 0 ]; then
      fail "references/index.md" "smell '$title' missing from index"
      continue
    elif [ "$matches" -gt 1 ]; then
      fail "references/index.md" "smell '$title' listed $matches times, expected exactly once"
      continue
    fi
    entry_lens="$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v t="$title" '$2 == t { print $1 }')"
    entry_slug="$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v t="$title" '$2 == t { print $3 }')"
    check
    if [ "$entry_lens" != "$lens" ]; then
      fail "references/index.md" "'$title' listed under '$entry_lens', catalog says '$lens'"
    fi
    check
    if [ -n "$entry_slug" ]; then
      if [ "$entry_slug" != "$slug" ]; then
        fail "references/index.md" "'$title' links to '$entry_slug.md', expected '$slug.md'"
      elif [ ! -f "$SMELLS_DIR/$slug.md" ]; then
        fail "references/index.md" "'$title' links to smells/$slug.md but the card does not exist"
      fi
    elif [ -f "$SMELLS_DIR/$slug.md" ]; then
      fail "references/index.md" "card smells/$slug.md exists but '$title' is unlinked in the index"
    fi
  done <<EOF
$CATALOG
EOF

  # per-lens counts in headings must match actual entry counts
  while read -r hline; do
    lens_name="$(printf '%s' "$hline" | sed 's/^## //; s/ ([0-9]*)$//')"
    declared="$(printf '%s' "$hline" | sed -n 's/^.*(\([0-9]*\))$/\1/p')"
    actual="$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v l="$lens_name" '$1 == l' | wc -l | tr -d ' ')"
    check
    if [ -n "$declared" ] && [ "$declared" -ne "$actual" ]; then
      fail "references/index.md" "lens '$lens_name' declares $declared entries but lists $actual"
    fi
  done <<EOF
$(grep '^## ' "$INDEX")
EOF
fi

# --- JSON result to stdout ---
PASS=true
[ -z "$FAILURES" ] || PASS=false
PRESENT_COUNT="$(printf '%s' "$PRESENT" | grep -c . || true)"
PENDING_COUNT="$(printf '%s' "$PENDING" | grep -c . || true)"
FAILURE_COUNT="$(printf '%s' "$FAILURES" | grep -c . || true)"

{
  printf '{"pass": %s, "mode": "%s", "cards_present": %s, "cards_pending": %s, "checks": %s, "failures": [' \
    "$PASS" "$MODE" "$PRESENT_COUNT" "$PENDING_COUNT" "$CHECKS"
  first=true
  while IFS="$US" read -r ffile freason; do
    [ -n "$ffile" ] || continue
    $first || printf ', '
    first=false
    printf '{"file": "%s", "reason": "%s"}' "$(esc "$ffile")" "$(esc "$freason")"
  done <<EOF
$FAILURES
EOF
  printf '], "pending": ['
  first=true
  while read -r p; do
    [ -n "$p" ] || continue
    $first || printf ', '
    first=false
    printf '"%s"' "$p"
  done <<EOF
$PENDING
EOF
  printf ']}\n'
}
JSON_EMITTED=1

if $PASS; then
  echo "PASS: $PRESENT_COUNT cards validated, $PENDING_COUNT pending, $CHECKS checks" >&2
  exit 0
else
  echo "FAIL: $FAILURE_COUNT failure(s) across $CHECKS checks ($PRESENT_COUNT cards present, $PENDING_COUNT pending)" >&2
  exit 1
fi
