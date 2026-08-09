#!/bin/bash
# Structural checks for the agent-skills collection (audit-fix acceptance).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name" >&2
    fail=1
  fi
}

# 1. Tracker dialect
check "tracker dialect clean" \
  bash -c "! rg -q 'AFK-ready label|publish it to the project.s issue tracker|shared map.*issue tracker|create the label if it doesn' skills/to-spec skills/triage skills/wayfinder"

# 2. resolving-merge-conflicts
check "merge-conflicts has title" \
  grep -q '^# Resolving Merge Conflicts' skills/resolving-merge-conflicts/SKILL.md
check "merge-conflicts description unquoted" \
  bash -c "! grep -q '^description: \"' skills/resolving-merge-conflicts/SKILL.md"

# 3. Junk
check "no skills/.DS_Store" test ! -e skills/.DS_Store
check "no skills/.gitkeep" test ! -e skills/.gitkeep

# 4. Weekly audits merged
check "dependency-audit exists" test -d skills/dependency-audit
check "weekly-composer removed" test ! -d skills/weekly-composer-dependency-audit
check "weekly-npm removed" test ! -d skills/weekly-npm-dependency-audit
check "marketplace lists dependency-audit once" \
  bash -c 'n=$(rg -c "dependency-audit" .claude-plugin/marketplace.json); test "$n" -eq 1'
check "marketplace omits old weekly names" \
  bash -c '! rg -q "weekly-composer-dependency-audit|weekly-npm-dependency-audit" .claude-plugin/marketplace.json'

# 5. Pipeline end-block SSOT
check "pipeline-end-block reference exists" \
  test -f skills/wayfinder/references/pipeline-end-block.md
check "pipeline skills point at end-block" \
  bash -c 'n=$(rg -l "pipeline-end-block.md" skills --glob "**/SKILL.md" | wc -l | tr -d " "); test "$n" -ge 6'

# 6. Wayfinder length + refs
check "wayfinder SKILL.md <= 120 lines" \
  bash -c 'n=$(wc -l < skills/wayfinder/SKILL.md | tr -d " "); test "$n" -le 120'
check "wayfinder map-and-tickets ref" test -f skills/wayfinder/references/map-and-tickets.md
check "wayfinder ticket-types ref" test -f skills/wayfinder/references/ticket-types.md
check "wayfinder fog-and-scope ref" test -f skills/wayfinder/references/fog-and-scope.md

# 7. code-review portability
check "code-review has inline fallback" \
  rg -q 'sub-agents are unavailable|run both reviews inline' skills/code-review/SKILL.md
check "code-review AGENTS-first" \
  bash -c 'rg -n "AGENTS.md" skills/code-review/SKILL.md | head -1 | grep -q "1\."'
check "code-review not Claude-only" \
  bash -c '! rg -q "run_in_background: false" skills/code-review/SKILL.md'

# 8. User-invoked descriptions without trigger catalogs
check "user-invoked descriptions have no trigger catalogs" \
  bash -c '
    python3 - <<'"'"'PY'"'"'
import os, re, sys
bad = []
for d in sorted(os.listdir("skills")):
    f = f"skills/{d}/SKILL.md"
    if not os.path.isfile(f):
        continue
    parts = open(f).read().split("---")
    if len(parts) < 3:
        continue
    fm = parts[1]
    if "disable-model-invocation" not in fm:
        continue
    for line in fm.splitlines():
        if line.startswith("description:") and re.search(
            r"Use this when|Use when the user|Triggers on", line, re.I
        ):
            bad.append(d)
if bad:
    print("bad:", ", ".join(bad), file=sys.stderr)
    sys.exit(1)
PY
  '

# 9. Marketplace/disk parity
check "marketplace and disk skill counts match" \
  bash -c '
    python3 - <<'"'"'PY'"'"'
import json, os, sys
mp = json.load(open(".claude-plugin/marketplace.json"))
skills = {s.replace("./skills/", "") for s in mp["plugins"][0]["skills"]}
disk = {d for d in os.listdir("skills") if os.path.isdir(f"skills/{d}") and not d.startswith(".")}
if skills != disk:
    print("mp only:", sorted(skills - disk), file=sys.stderr)
    print("disk only:", sorted(disk - skills), file=sys.stderr)
    sys.exit(1)
PY
  '

# 10. AGENTS no phantom spec/ dir; multi-agent wording
check "AGENTS has no dangling spec/ layout" \
  bash -c '! rg -q "^spec/" AGENTS.md'
check "marketplace description not Claude-only product claim" \
  bash -c '! rg -q "for Claude\"" .claude-plugin/marketplace.json'

if [[ "$fail" -ne 0 ]]; then
  echo "verify-skills-collection: FAILED" >&2
  exit 1
fi
echo "verify-skills-collection: all checks passed"
