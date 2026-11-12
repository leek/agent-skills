#!/bin/bash
# Structural checks for the agent-skills collection.
# Compatible with both bash and zsh.
set -euo pipefail

export ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

# Without PyYAML the frontmatter checks fall back to regex and skip YAML validity, which CI
# (PyYAML installed) still enforces. Say so, or a local pass hides a CI failure.
python3 -c "import yaml" 2>/dev/null || echo "WARN: PyYAML is not installed; YAML validity is not checked here (CI checks it). Run: python3 -m pip install pyyaml" >&2

# VERIFY_ONLY=<text> runs only the checks whose name contains <text> (for work on one check;
# CI runs them all).
check() {
  local name="$1"
  shift
  if [[ -n "${VERIFY_ONLY:-}" && "$name" != *"$VERIFY_ONLY"* ]]; then
    return 0
  fi
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
    m = re.match(r"^---\n(.*?)\n---\n", open(f, encoding="utf-8").read(), re.S)
    if not m:
        continue
    fm = m.group(1)
    if not re.search(r"^disable-model-invocation:\s*true\s*$", fm, re.M):
        continue
    # The whole description value: its first line and every indented continuation line
    # (a folded or literal block scalar, or a plain scalar wrapped over several lines).
    desc = re.search(r"^description:(.*(?:\n[ \t]+.*|\n[ \t]*(?=\n[ \t]))*)", fm, re.M)
    if desc and re.search(r"Use this when|Use when the user|Triggers on", " ".join(desc.group(1).split()), re.I):
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
files = (sorted(glob.glob("skills/**/*.md", recursive=True)) + sorted(glob.glob("docs/**/*.md", recursive=True))
         + sorted(glob.glob("agents/*.md")) + ["README.md", "AGENTS.md"])
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

# 5b. Frontmatter inside a template (a ```markdown block that opens with ---) is what a
# skill writes into every file it generates, so it must be valid YAML with a quoted title.
check "every template frontmatter block is valid YAML with a quoted title" \
  python3 -c '
import glob, re, sys
try:
    import yaml
except ImportError:
    yaml = None
bad = []
for p in sorted(glob.glob("skills/**/*.md", recursive=True)):
    text = open(p, encoding="utf-8").read()
    for m in re.finditer(r"```markdown\n---\n(.*?)\n---\n", text, flags=re.S):
        fm = m.group(1)
        for line in fm.splitlines():
            if re.match(r"title:\s*[^\"\x27\s]", line):
                bad.append(f"{p}: unquoted title in template frontmatter: {line}")
        if yaml is not None:
            try:
                if not isinstance(yaml.safe_load(fm), dict):
                    bad.append(f"{p}: template frontmatter is not a mapping")
            except yaml.YAMLError as e:
                bad.append(f"{p}: template frontmatter is not valid YAML ({str(e).splitlines()[0]})")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

# 6. Junk (.DS_Store is gitignored, so only a tracked one ships)
check "no tracked skills/.DS_Store" bash -c '! git ls-files --error-unmatch skills/.DS_Store >/dev/null 2>&1'
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
# The eight skills pipeline-end-block.md names as its users, by name: each one points at the
# file, the file names each one, and no other SKILL.md points at it without being added here
# and there.
check "pipeline skills point at end-block" \
  python3 -c '
import glob, sys
USERS = ["code-review", "grill-me", "implement", "implement-spec", "to-questionnaire", "to-spec", "to-tickets", "wayfinder"]
ref = "skills/wayfinder/references/pipeline-end-block.md"
try:
    owner = open(ref, encoding="utf-8").read()
except OSError:
    sys.exit(ref + " is missing")
bad = []
for d in USERS:
    try:
        text = open(f"skills/{d}/SKILL.md", encoding="utf-8").read()
    except OSError:
        bad.append(f"skills/{d}/SKILL.md is missing (a pipeline skill)")
        continue
    if "pipeline-end-block.md" not in text:
        bad.append(f"skills/{d}/SKILL.md does not point at pipeline-end-block.md")
    if f"`{d}`" not in owner:
        bad.append(f"{ref} does not name `{d}` as one of its users")
for md in sorted(glob.glob("skills/*/SKILL.md")):
    d = md.split("/")[1]
    if d not in USERS and "pipeline-end-block.md" in open(md, encoding="utf-8").read():
        bad.append(f"{md} points at pipeline-end-block.md but is not a named pipeline skill (add it to USERS here and to the list in {ref})")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'
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
# The fallback sits beside the agent it covers: in the same paragraph (the run of non-blank
# lines around the reference), not merely somewhere in the file. A reference in frontmatter
# (`agent:` on a forked skill) has no paragraph, so its fallback may be anywhere in the body.
check "skills naming an agent keep a non-Claude fallback" \
  python3 -c '
import glob, os, re, sys
names = "|".join(sorted(re.escape(os.path.basename(f)[:-3]) for f in glob.glob("agents/*.md")))
ref = re.compile(rf"leek-skills:({names})\b")
fallback = re.compile(r"elsewhere|inline|other harness|plain Claude Code", re.I)
bad = []
for p in sorted(glob.glob("skills/**/*.md", recursive=True)):
    lines = open(p, encoding="utf-8").read().splitlines()
    body = 0
    if lines and lines[0] == "---" and "---" in lines[1:]:
        body = lines.index("---", 1) + 1
    for i, line in enumerate(lines):
        if not ref.search(line):
            continue
        if i < body:
            scope = lines[body:]
        else:
            a = i
            while a > body and lines[a - 1].strip():
                a -= 1
            b = i
            while b + 1 < len(lines) and lines[b + 1].strip():
                b += 1
            scope = lines[a:b + 1]
        if not fallback.search("\n".join(scope)):
            bad.append(f"{p}:{i + 1}: names an agent without a fallback clause in the same paragraph")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

# 9. which-skill names every skill a user can start (user-invoked or model-invoked; only
#    `user-invocable: false` protocols are left out), and harness tool names live only in harness-tools.
#    Hyphen-aware: \b treats "-" as a boundary, so "implement" would match "implement-spec".
check "which-skill names every skill that is not user-invocable: false" \
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
    if re.search(r"^user-invocable:\s*false\b", parts[1], re.M):
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
tools = re.compile(r"\b(spawn_subagent|spawn_agent|wait_agent|fork_turns|followup_task|send_message|resume_from|interrupt_agent|request_user_input|request_user_input_async|ask_user_question|multi_select|send_subagent_message|get_command_or_subagent_output|kill_command_or_subagent|invoke_subagent|manage_subagents|ask_question|is_multi_select)\b")
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
check "skill files naming a Claude Code harness tool also point at harness-tools" \
  python3 -c '
import os, re, sys
claude = re.compile(r"\b(AskUserQuestion|SendMessage|TaskStop)\b")
bad = []
for root, dirs, files in os.walk("skills"):
    if root.startswith(os.path.join("skills", "harness-tools")):
        continue
    for name in files:
        if name.endswith(".md"):
            p = os.path.join(root, name)
            text = open(p, encoding="utf-8").read()
            if claude.search(text) and "harness-tools" not in text:
                bad.append(p)
if bad:
    print("no harness-tools pointer beside a Claude Code tool:", ", ".join(bad), file=sys.stderr)
    sys.exit(1)
'
check "harness-tools has every move, with one row per harness in each table" \
  python3 -c '
import re, sys
text = open("skills/harness-tools/SKILL.md", encoding="utf-8").read()
want = ["Claude Code", "Codex", "Grok", "agy"]
moves = ["Dispatch and wait", "Dispatch in the background", "Follow up", "Stop", "Structured question"]
sections = {s.splitlines()[0].strip(): s for s in re.split(r"^## ", text, flags=re.M)[1:]}
bad = []
for move in moves:
    sec = sections.get(move)
    if sec is None:
        bad.append(move + ": section missing")
        continue
    lines = [l for l in sec.splitlines() if l.startswith("|")]
    if len(lines) < 3 or not lines[0].startswith("| Harness |"):
        bad.append(move + ": no harness table")
        continue
    rows = [l.split("|")[1].strip() for l in lines[2:]]
    if sorted(rows) != sorted(want):
        bad.append(move + ": rows " + ", ".join(rows) + " (want exactly " + ", ".join(want) + ")")
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
check "memory-write guard tests pass" \
  python3 -m unittest -q hooks/test_memory_write_guard.py
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
      # A spec built through tickets is never closed itself: all tickets closed means done.
      mkdir -p .scratch/built/tickets
      printf -- "---\ntitle: S\nstatus: ready-for-agent\n---\n" > .scratch/built/spec.md
      printf -- "---\ntitle: T\nstatus: closed\n---\n## Resolution\n%s\n" "$sha" > .scratch/built/tickets/01-a.md
      mkdir -p .agents .scratch/shut/tickets sub
      printf -- "| Role | Status | Meaning |\n| \`wontfix\` | \`not-planned\` | Will not be actioned |\n" > .agents/triage-labels.md
      printf -- "---\ntitle: T\nstatus: duplicate\n---\n" > .scratch/shut/tickets/01-a.md
      printf -- "---\ntitle: T\nstatus: not-planned\n---\n" > .scratch/shut/tickets/02-b.md
      printf -- "---\ntitle: T\nstatus: closed\n---\n## Comments\nCI run 18234567890 green\n" > .scratch/shut/tickets/03-c.md
    )
    out=$(cd "$t/sub" && bash "$ROOT/skills/scratch-status/scripts/scratch-state.sh")
    python3 -c "import json, sys; d = json.loads(sys.argv[1]); assert d[\"counts\"] == {\"open\": 1, \"stale\": 0, \"mismatched\": 1, \"done\": 3}, d[\"counts\"]; assert \"⚠\" not in sys.argv[1]" "$out"'

# 11. Skill scripts: their tests run, a skill pre-approves the scripts it runs, and a script
#     path names the skill directory.
#     Every skills/*/scripts/test-*.sh runs with bash from the repo root, each in its own process
#     group under a time limit (SKILL_TEST_TIMEOUT seconds, default 120; perl, because macOS has no
#     `timeout`). No test files is a pass.
run_skill_script_tests() {
  local t out code failed=""
  for t in skills/*/scripts/test-*.sh; do
    [[ -e "$t" ]] || continue
    code=0
    out=$(perl -e '
      my $limit = shift;
      my $pid = fork();
      die "fork: $!" unless defined $pid;
      if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127; }
      setpgrp($pid, $pid);
      $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 124; };
      alarm $limit;
      waitpid($pid, 0);
      exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
    ' "${SKILL_TEST_TIMEOUT:-120}" bash "$t" 2>&1) || code=$?
    if [[ "$code" -ne 0 ]]; then
      failed="$failed $t"
      if [[ "$code" -eq 124 ]]; then
        echo "$t: timed out after ${SKILL_TEST_TIMEOUT:-120}s" >&2
      else
        echo "$t: exit $code" >&2
      fi
      printf '%s\n' "$out" | tail -n 15 | sed 's/^/    /' >&2
    fi
  done
  if [[ -n "$failed" ]]; then
    echo "failed script tests:$failed" >&2
    return 1
  fi
}
check "every skills/*/scripts/test-*.sh passes" run_skill_script_tests

# maintaining.md asks for this after every card edit; strict mode is the ship gate.
check "code-smells-audit cards pass validate-cards.sh" \
  bash -c 'out=$(bash skills/code-smells-audit/scripts/validate-cards.sh 2>&1 >/dev/null) || { printf "%s\n" "$out" | grep "^FAIL" >&2; exit 1; }'

# A skill with allowed-tools that names one of its own scripts/*.sh, in SKILL.md or in any
# other .md file of the skill (references/, skill-root companions), runs that script, so
# allowed-tools must cover it (docs/authoring.md), or every run stops for a prompt.
# EXEMPT holds "<skill>/<script>" for a script that must keep its prompt: a write the body says
# to ask about first, or a maintainer-only script. Each entry carries its reason.
check "allowed-tools covers each script a skill body runs" \
  python3 -c '
import glob, os, re, sys
EXEMPT = {
    # Maintainer-only: references/maintaining.md runs it after a card edit, never a skill run.
    "code-smells-audit/validate-cards.sh",
}
bad = []
for md in sorted(glob.glob("skills/*/SKILL.md")):
    d = md.split("/")[1]
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(md, encoding="utf-8").read(), re.S)
    if not m:
        continue
    allowed = re.search(r"^allowed-tools:\s*(.+)$", m.group(1), re.M)
    if not allowed:
        continue
    # SKILL.md body first (line numbers count from the top of the file), then every other
    # .md file of the skill.
    texts = [(md, m.group(2), m.group(1).count("\n") + 3)]
    for other in sorted(glob.glob(f"skills/{d}/**/*.md", recursive=True)):
        if other != md:
            texts.append((other, open(other, encoding="utf-8").read(), 1))
    for script in sorted(glob.glob(f"skills/{d}/scripts/*.sh")):
        name = os.path.basename(script)
        if name.startswith("test-") or f"{d}/{name}" in EXEMPT:
            continue
        if f"scripts/{name}" in allowed.group(1):
            continue
        # Its own script: scripts/<name> with no other skill folder in front of it.
        own = re.compile(rf"(?:(?<![A-Za-z0-9_-]/)|(?<=/{re.escape(d)}/)|(?<=\*{re.escape(d)}/))scripts/{re.escape(name)}(?![A-Za-z0-9_.-])")
        for path, text, first in texts:
            hit = next((n for n, line in enumerate(text.splitlines(), first) if own.search(line)), None)
            if hit is not None:
                bad.append(f"{path}:{hit}: names scripts/{name} but {md} allowed-tools does not cover it (add Bash(bash ${{CLAUDE_PLUGIN_ROOT}}/skills/{d}/scripts/{name} *), or exempt it in the verifier with the reason)")
                break
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

check "no openai.yaml short_description is cut off with ..." \
  python3 -c '
import glob, re, sys
bad = []
for y in sorted(glob.glob("skills/*/agents/openai.yaml")):
    m = re.search(r"^\s*short_description:\s*(.+)$", open(y, encoding="utf-8").read(), re.M)
    if m and re.search(r"(\.\.\.|…)$", m.group(1).strip().strip("\"\x27").rstrip()):
        bad.append(f"{y}: short_description ends in an ellipsis; write the whole sentence")
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

# A command that runs scripts/<name>.sh with no skill directory in front only works from the
# skill folder, and a skill runs from the target repo. The spelling is
# <this-skill-dir>/scripts/<name>.sh. A markdown link to a script and a mention in prose are
# fine; a command is `bash scripts/x.sh`, a code-block line that starts with scripts/x.sh, or
# an inline code span that starts with scripts/x.sh and goes on with arguments.
# A link used AS the command is a command too: a link to scripts/x.sh followed by an inline
# code span (its arguments), or one after "run"/"bash" in a file that never spells the full
# <this-skill-dir>/scripts/x.sh command. The agent reads "run scripts/x.sh <args>" and its
# shell is in the target repo.
# LINK_EXEMPT holds "<file>:<script>" for link-form commands in files outside the
# panel-findings file set; each is a TODO for its owner, to be rewritten and removed here.
check "script commands name the skill directory, not a bare scripts/ path" \
  python3 -c '
import glob, re, sys
script = r"(?:\./)?scripts/[A-Za-z0-9_.-]+\.sh"
with_shell = re.compile(r"(?<![A-Za-z0-9_>}/.*-])(?:bash|sh|zsh)\s+" + script)
line_start = re.compile(r"^\s*(?:\$\s+)?" + script + r"(?![A-Za-z0-9_.-])")
span = re.compile(r"`" + script + r"\s+[^`]+`")
link = re.compile(r"\[[^\]]*\]\([^)]*\)")
script_link = re.compile(r"\[[^\]]*\]\((?:\.\.?/)*scripts/([A-Za-z0-9_.-]+\.sh)\)")
LINK_EXEMPT = set()
bad = []
for p in sorted(glob.glob("skills/**/*.md", recursive=True)):
    fenced = False
    whole = open(p, encoding="utf-8").read()
    for n, line in enumerate(whole.splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        text = link.sub("LINK", line)
        if with_shell.search(text) or span.search(text) or (fenced and line_start.search(text)):
            bad.append(f"{p}:{n}: {line.strip()[:110]}")
            continue
        if fenced:
            continue
        for m in script_link.finditer(line):
            name = m.group(1)
            if f"{p}:{name}" in LINK_EXEMPT:
                continue
            with_args = re.match(r"\s+`[^`]+`", line[m.end():])
            told_to_run = re.search(r"\b(?:run|bash)\s+$", line[:m.start()], re.I)
            spelled = re.search(r"<this-skill-dir>/(?:\.\./[A-Za-z0-9_-]+/)?scripts/" + re.escape(name), whole)
            if with_args or (told_to_run and not spelled):
                bad.append(f"{p}:{n}: a link used as the command: {line.strip()[:90]}")
if bad:
    print("bare scripts/ path in a command (write <this-skill-dir>/scripts/<name>.sh):", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
'

if [[ "$fail" -ne 0 ]]; then
  echo "verify-skills-collection: FAILED" >&2
  exit 1
fi
echo "verify-skills-collection: all checks passed"
