#!/bin/bash
# Structural checks for the agent-skills collection.
# Compatible with both bash and zsh.
set -euo pipefail

export ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# 1. SKILL.md frontmatter validity and folder-name parity
check "every SKILL.md has valid frontmatter and name matching its folder" \
  python3 -c '
import glob, os, re, sys
try:
    import yaml
except ImportError:
    yaml = None

bad = []
for d in sorted(os.listdir("skills")):
    skill_dir = os.path.join("skills", d)
    if not os.path.isdir(skill_dir) or d.startswith("."):
        continue
    p = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(p):
        bad.append(f"{d}: missing SKILL.md")
        continue
    text = open(p, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        bad.append(f"{p}: missing YAML frontmatter block")
        continue
    fm_raw = m.group(1)
    if yaml is not None:
        try:
            data = yaml.safe_load(fm_raw)
            if not isinstance(data, dict):
                bad.append(f"{p}: frontmatter is not a mapping")
                continue
        except Exception as e:
            bad.append(f"{p}: {str(e).splitlines()[0]}")
            continue
        name = data.get("name")
        desc = data.get("description")
    else:
        fields = {}
        for line in fm_raw.splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            kv = re.match(r"^([a-z0-9-]+):\s*(.+)$", line)
            if not kv:
                bad.append(f"{p}: unparseable frontmatter line: {line}")
                continue
            k, v = kv.group(1), kv.group(2).strip()
            if not (v.startswith("\"") and v.endswith("\"")) and not (v.startswith("\x27") and v.endswith("\x27")):
                if ": " in v or v.endswith(":"):
                    bad.append(f"{p}: unquoted colon in {k}")
            fields[k] = v.strip("\"\x27")
        name = fields.get("name")
        desc = fields.get("description")
    if not name:
        bad.append(f"{p}: missing or empty name")
    elif name != d:
        bad.append(f"{p}: frontmatter name {name!r} != folder {d!r}")
    if not desc:
        bad.append(f"{p}: missing or empty description")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

# 2. Harness metadata (agents/openai.yaml) parity
check "every skill ships matching agents/openai.yaml metadata" \
  python3 -c '
import os, re, sys
try:
    import yaml
except ImportError:
    yaml = None

bad = []
for d in sorted(os.listdir("skills")):
    skill = os.path.join("skills", d)
    md = os.path.join(skill, "SKILL.md")
    if not os.path.isfile(md):
        continue
    y = os.path.join(skill, "agents", "openai.yaml")
    if not os.path.isfile(y):
        bad.append(f"{d}: missing agents/openai.yaml")
        continue
    raw_y = open(y, encoding="utf-8").read()
    if yaml is not None:
        try:
            meta = yaml.safe_load(raw_y) or {}
        except Exception as e:
            bad.append(f"{d}: unparseable openai.yaml ({e})")
            continue
        allowed = (meta.get("policy") or {}).get("allow_implicit_invocation")
        short_desc = (meta.get("interface") or {}).get("short_description")
        disp_name = (meta.get("interface") or {}).get("display_name")
    else:
        m_allow = re.search(r"^\s*allow_implicit_invocation:\s*(true|false)\s*$", raw_y, re.M)
        allowed = (m_allow.group(1) == "true") if m_allow else None
        m_short = re.search(r"^\s*short_description:\s*(.+)$", raw_y, re.M)
        short_desc = m_short.group(1).strip().strip("\"\x27") if m_short else ""
        m_disp = re.search(r"^\s*display_name:\s*(.+)$", raw_y, re.M)
        disp_name = m_disp.group(1).strip().strip("\"\x27") if m_disp else ""
    fm = re.match(r"^---\n(.*?)\n---\n", open(md, encoding="utf-8").read(), re.S)
    user_invoked = bool(fm and re.search(r"^disable-model-invocation:\s*true\s*$", fm.group(1), re.M))
    if allowed is not (not user_invoked):
        bad.append(f"{d}: allow_implicit_invocation={allowed} contradicts SKILL.md frontmatter")
    if not short_desc:
        bad.append(f"{d}: openai.yaml has no short_description")
    if not disp_name:
        bad.append(f"{d}: openai.yaml has no display_name")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

# 3. User-invoked descriptions without trigger catalogs
check "user-invoked descriptions have no trigger catalogs" \
  python3 -c '
import os, re, sys
bad = []
for d in sorted(os.listdir("skills")):
    f = f"skills/{d}/SKILL.md"
    if not os.path.isfile(f):
        continue
    parts = open(f, encoding="utf-8").read().split("---")
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
'

# 4. Marketplace, plugin.json, and README.md parity + alphabetical order
check "marketplace.json, plugin.json, and README.md match skills/ in alphabetical order" \
  python3 -c '
import json, os, re, sys

disk = sorted(d for d in os.listdir("skills") if os.path.isdir(f"skills/{d}") and not d.startswith("."))
mp = json.load(open(".claude-plugin/marketplace.json", encoding="utf-8"))
mp_list = [s.replace("./skills/", "") for s in mp["plugins"][0]["skills"]]

if set(mp_list) != set(disk):
    print("mp only:", sorted(set(mp_list) - set(disk)), file=sys.stderr)
    print("disk only:", sorted(set(disk) - set(mp_list)), file=sys.stderr)
    sys.exit(1)
if mp_list != sorted(mp_list):
    for a, b in zip(mp_list, sorted(mp_list)):
        if a != b:
            sys.exit(f"marketplace.json skills not sorted at {a!r} vs {b!r}")

p_ver = json.load(open(".claude-plugin/plugin.json", encoding="utf-8")).get("version")
m_ver = mp["metadata"]["version"]
if p_ver != m_ver:
    sys.exit(f"plugin.json {p_ver} != marketplace.json {m_ver}")

readme = open("README.md", encoding="utf-8").read()
rows = re.findall(r"^\| `([a-z0-9-]+)` \| (user|model) \|", readme, re.M)
r_names = [r[0] for r in rows]
if set(r_names) != set(disk):
    print("README only:", sorted(set(r_names) - set(disk)), file=sys.stderr)
    print("disk missing from README:", sorted(set(disk) - set(r_names)), file=sys.stderr)
    sys.exit(1)
if r_names != sorted(r_names):
    for a, b in zip(r_names, sorted(r_names)):
        if a != b:
            sys.exit(f"README.md skill table not sorted at {a!r} vs {b!r}")

r_map = dict(rows)
for s in disk:
    fm = open(f"skills/{s}/SKILL.md", encoding="utf-8").read().split("---")[1]
    is_user = bool(re.search(r"^disable-model-invocation:\s*true\s*$", fm, re.M))
    expected = "user" if is_user else "model"
    if r_map[s] != expected:
        sys.exit(f"README.md lists {s} as {r_map[s]!r}, expected {expected!r}")
'

# 5. Relative markdown links resolve on disk
check "every relative markdown link resolves on disk" \
  python3 -c '
import glob, os, re, sys
bad = []
files = sorted(glob.glob("skills/**/*.md", recursive=True)) + ["README.md", "AGENTS.md"]
for root_file in files:
    content = open(root_file, encoding="utf-8").read()
    content = re.sub(r"```.*?```", "", content, flags=re.S)
    # Blank inline code to a placeholder, not to nothing, so a link whose label is code,
    # [`path`](path), keeps a non-empty label and is still checked.
    content = re.sub(r"`[^`\n]+`", "code", content)
    base = os.path.dirname(root_file)
    for m in re.finditer(r"\[[^\]]+\]\(([^)#\s]+)(?:#[^)]*)?\)", content):
        target = m.group(1).strip()
        if target.startswith(("http://", "https://", "mailto:", "file://", "<")):
            continue
        resolved = os.path.normpath(os.path.join(base, target))
        if not os.path.exists(resolved):
            bad.append(f"{root_file}: {target} -> {resolved} (missing)")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

# 6. Junk
check "no skills/.DS_Store" test ! -e skills/.DS_Store
check "no skills/.gitkeep" test ! -e skills/.gitkeep

# 6b. Earlier audit regressions: each once shipped, so each stays pinned
check "tracker dialect clean" \
  bash -c "! rg -q 'AFK-ready label|publish it to the project.s issue tracker|shared map.*issue tracker|create the label if it doesn' skills/to-spec skills/triage skills/wayfinder"
check "merge-conflicts has title" \
  grep -q '^# Resolving Merge Conflicts' skills/resolving-merge-conflicts/SKILL.md
check "merge-conflicts description unquoted" \
  bash -c "! grep -q '^description: \"' skills/resolving-merge-conflicts/SKILL.md"
check "dependency-audit exists" test -d skills/dependency-audit
check "weekly-composer removed" test ! -d skills/weekly-composer-dependency-audit
check "weekly-npm removed" test ! -d skills/weekly-npm-dependency-audit
check "marketplace lists dependency-audit once" \
  bash -c 'n=$(rg -c "dependency-audit" .claude-plugin/marketplace.json); test "$n" -eq 1'
check "marketplace omits old weekly names" \
  bash -c '! rg -q "weekly-composer-dependency-audit|weekly-npm-dependency-audit" .claude-plugin/marketplace.json'
check "wayfinder SKILL.md <= 120 lines" \
  bash -c 'n=$(wc -l < skills/wayfinder/SKILL.md | tr -d " "); test "$n" -le 120'
check "wayfinder map-and-tickets ref" test -f skills/wayfinder/references/map-and-tickets.md
check "wayfinder ticket-types ref" test -f skills/wayfinder/references/ticket-types.md
check "wayfinder fog-and-scope ref" test -f skills/wayfinder/references/fog-and-scope.md
check "AGENTS has no dangling spec/ layout" \
  bash -c '! rg -q "^spec/" AGENTS.md'
check "marketplace description not Claude-only product claim" \
  bash -c '! rg -q "for Claude\"" .claude-plugin/marketplace.json'

# 7. Pipeline end-block SSOT and code-review portability
check "pipeline-end-block reference exists" \
  test -f skills/wayfinder/references/pipeline-end-block.md
check "pipeline skills point at end-block" \
  bash -c 'n=$(rg -l "pipeline-end-block.md" skills --glob "**/SKILL.md" | wc -l | tr -d " "); test "$n" -ge 6'
check "code-review has inline fallback" \
  rg -q 'sub-agents are unavailable|run both reviews inline' skills/code-review/SKILL.md
check "code-review AGENTS-first" \
  bash -c 'rg -n "AGENTS.md" skills/code-review/SKILL.md | head -1 | grep -q "1\."'
check "code-review not Claude-only" \
  bash -c '! rg -q "run_in_background: false" skills/code-review/SKILL.md'

# 8. Subagents: every agent has frontmatter, every reference resolves, fallbacks kept
check "agents dir exists" test -d agents
check "every agent has name + description" \
  bash -c '
    for f in agents/*.md; do
      n=$(basename "$f" .md)
      awk -v n="$n" "/^---\$/{c++} c==1 && /^name:[[:space:]]*\"?\"?\$/{exit 1} c==1 && /^name:/{if (\$2 != n) exit 1; found=1} c==1 && /^description:[[:space:]]*[^[:space:]]/{desc=1} c==2{exit} END{exit !(found && desc)}" "$f" || { echo "bad agent frontmatter: $f" >&2; exit 1; }
    done'
check "every leek-skills:<agent> reference resolves to agents/<agent>.md" \
  bash -c '
    rg -o "leek-skills:[a-z-]+" skills README.md AGENTS.md --no-filename | sort -u | sed "s/^leek-skills://" | while read -r a; do
      case "$a" in codebase-design|domain-modeling) continue;; esac   # skills preloaded by agents
      test -f "agents/$a.md" || { echo "dangling agent reference: $a" >&2; exit 1; }
    done'
check "every agent is referenced by some skill" \
  bash -c '
    for f in agents/*.md; do
      n=$(basename "$f" .md)
      rg -q "leek-skills:$n" skills || { echo "unreferenced agent: $n" >&2; exit 1; }
    done'
check "agent skills: preloads are scoped and model-invoked" \
  bash -c '
    rg -o "^\s+-\s+leek-skills:[a-z-]+" agents --no-filename | sed "s/.*leek-skills://" | sort -u | while read -r s; do
      test -f "skills/$s/SKILL.md" || { echo "preloaded skill missing: $s" >&2; exit 1; }
      ! rg -q "^disable-model-invocation: true" "skills/$s/SKILL.md" || { echo "preloading a user-invoked skill: $s" >&2; exit 1; }
    done'
check "forked skills name an existing agent and wait for the result" \
  bash -c '
    for f in $(rg -l "^context: fork" skills --glob "**/SKILL.md"); do
      a=$(rg -o "^agent: leek-skills:[a-z-]+" "$f" | sed "s/.*leek-skills://")
      test -n "$a" && test -f "agents/$a.md" || { echo "$f: context: fork without a resolvable agent:" >&2; exit 1; }
      rg -q "^background: false" "$f" || { echo "$f: forked skill must set background: false" >&2; exit 1; }
    done'
check "skills naming an agent keep a non-Claude fallback" \
  bash -c '
    for f in $(rg -l "subagent_type=leek-skills:" skills); do
      rg -qi "elsewhere|inline|other harness|plain Claude Code" "$f" || { echo "$f: names an agent without a fallback clause" >&2; exit 1; }
    done'

# 9. which-skill names every user-invoked skill, and harness tool names live only in harness-tools.
#    Hyphen-aware: \b treats "-" as a boundary, so "implement" would match "implement-spec".
check "which-skill names every user-invoked skill" \
  bash -c '
    python3 - <<'"'"'PY'"'"'
import os, re, sys
router = open("skills/which-skill/SKILL.md").read()
missing = []
for d in sorted(os.listdir("skills")):
    if d == "which-skill":
        continue
    f = f"skills/{d}/SKILL.md"
    if not os.path.isfile(f):
        continue
    parts = open(f).read().split("---")
    if len(parts) < 3:
        continue
    if not re.search(r"^disable-model-invocation:\s*true\b", parts[1], re.M):
        continue
    if not re.search(rf"(?<![a-z0-9-]){re.escape(d)}(?![a-z0-9-])", router):
        missing.append(d)
if missing:
    print("which-skill omits:", ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PY
  '
check "harness-tools is the only skill file naming non-Claude harness tools" \
  python3 -c '
import os, re, sys
tools = re.compile(r"\b(spawn_subagent|spawn_agent|wait_agent|fork_turns|followup_task|interrupt_agent|request_user_input|ask_user_question|send_subagent_message|get_command_or_subagent_output|kill_command_or_subagent|invoke_subagent|manage_subagents|ask_question)\b")
bad = []
for root, dirs, files in os.walk("skills"):
    if root.startswith(os.path.join("skills", "harness-tools")):
        continue
    for name in files:
        if name.endswith(".md"):
            p = os.path.join(root, name)
            hits = sorted(set(tools.findall(open(p, encoding="utf-8").read())))
            if hits:
                bad.append(p + ": " + ", ".join(hits) + " (point at harness-tools instead)")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'
check "harness-tools has a row per harness in every table" \
  python3 -c '
import re, sys
text = open("skills/harness-tools/SKILL.md", encoding="utf-8").read()
want = ["Claude Code", "Codex", "Grok", "agy"]
bad = []
for sec in re.split(r"^## ", text, flags=re.M)[1:]:
    rows = re.findall(r"^\| (Claude Code|Codex|Grok|agy) \|", sec, re.M)
    if rows and sorted(rows) != sorted(want):
        bad.append(sec.splitlines()[0] + ": rows " + ", ".join(rows))
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

# 10. Plugin manifests and hooks pass Claude Code's own validator (valid JSON, mod modules exist)
#     and its mod tests, and the browser-test and review-agent guards hold. This script never names
#     a mod file itself: the plugin directory holds any command that names one for manual review.
check "claude plugin validate passes the directory profile" \
  claude plugin validate . --profile directory
check "claude plugin test passes" \
  claude plugin test .
check "browser-test guard tests pass" \
  python3 -m unittest -q skills/browser-test/scripts/test_guard_browser.py
check "review-agent guard tests pass" \
  python3 -m unittest -q hooks/test_guard_review_agents.py
check "bare-worktree notice speaks only in a bare Laravel worktree" \
  bash -c '
    t=$(mktemp -d); trap "rm -rf \"$t\"" EXIT
    mkdir -p "$t/main/.git" "$t/wt"; echo "gitdir: x" > "$t/wt/.git"
    touch "$t/main/artisan" "$t/main/composer.json" "$t/wt/artisan" "$t/wt/composer.json"
    run() { CLAUDE_PROJECT_DIR="$1" bash hooks/bare-worktree-notice.sh </dev/null; }
    test -z "$(run "$t/main")" && test -n "$(run "$t/wt")" || exit 1
    mkdir "$t/wt/vendor"; test -z "$(run "$t/wt")"'
check "scratch-state.sh classifies open, mismatched, and done efforts" \
  bash -c '
    t=$(mktemp -d); trap "rm -rf \"$t\"" EXIT
    (
      cd "$t"
      git init -q -b main
      git config user.email "t@e.st"; git config user.name "T"
      echo x > f && git add f && git commit -q -m init
      sha=$(git rev-parse --short HEAD)
      mkdir -p .scratch/done/tickets .scratch/bad/tickets .scratch/open/tickets
      printf -- "---\ntitle: S\nstatus: closed\n---\n" > .scratch/done/spec.md
      printf -- "---\ntitle: T\nstatus: closed\n---\n## Resolution\n%s\n" "$sha" > .scratch/done/tickets/01-a.md
      printf -- "---\ntitle: S\nstatus: closed\n---\n" > .scratch/bad/spec.md
      printf -- "---\ntitle: T\nstatus: closed\n---\n## Resolution\ndeadbeef1\n" > .scratch/bad/tickets/01-a.md
      printf -- "---\ntitle: T\nstatus: ready-for-agent\n---\n" > .scratch/open/tickets/01-a.md
      mkdir -p .agents .scratch/shut/tickets sub
      printf -- "| Role | Status | Meaning |\n| \`wontfix\` | \`not-planned\` | Will not be actioned |\n" > .agents/triage-labels.md
      printf -- "---\ntitle: T\nstatus: duplicate\n---\n" > .scratch/shut/tickets/01-a.md
      printf -- "---\ntitle: T\nstatus: not-planned\n---\n" > .scratch/shut/tickets/02-b.md
      printf -- "---\ntitle: T\nstatus: closed\n---\n## Comments\nCI run 18234567890 green\n" > .scratch/shut/tickets/03-c.md
    )
    out=$(cd "$t/sub" && bash "$ROOT/skills/scratch-status/scripts/scratch-state.sh")
    python3 -c "import json, sys; d = json.loads(sys.argv[1]); assert d[\"counts\"] == {\"open\": 1, \"stale\": 0, \"mismatched\": 1, \"done\": 2}, d[\"counts\"]; assert \"⚠\" not in sys.argv[1]" "$out"'

if [[ "$fail" -ne 0 ]]; then
  echo "verify-skills-collection: FAILED" >&2
  exit 1
fi
echo "verify-skills-collection: all checks passed"
