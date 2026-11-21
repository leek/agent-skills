#!/bin/bash
# Inventory every source of persistent agent context for one project, read-only: what exists,
# its scope, whether and when the harness loads it, its size, and what it imports. Splits the
# editable sources into audit units, flags near-duplicate units, and writes sweep batches.
#
# Usage: inventory.sh --out <dir> [--project <dir>] [--home <dir>] [--config-dir <dir>]
#                     [--managed-dir <dir>] [--declined <declined.jsonl>] [--batch-size N]
#                     [--max-batches N] [--audited <audited.jsonl>] [--audited-days N]
#   --project      the working directory sessions start in (default: $PWD)
#   --home         the home directory (default: $HOME); tests pass a fixture
#   --config-dir   Claude Code's config dir (default: $CLAUDE_CONFIG_DIR, else <home>/.claude)
#   --managed-dir  managed-policy dir (default: the platform path)
#   --declined     units whose fingerprint is listed here are marked declined (state.sh ledger)
#   --batch-size   audit units per sweep batch (default 40), raised as needed to fit --max-batches
#   --max-batches  most sweep batches to write (default 10): a bigger run gets bigger batches
#   --audited      state.sh ledger of files a past run audited; a file whose bytes are unchanged and
#                  whose audit is under --audited-days old (default 14) keeps its units, marked
#                  audited and left out of every batch
#   --scope        comma list of instructions, memory, config: which units to write and batch
#                  (default all). Sources, issues, and totals always cover everything.
#   --upstream     a checkout the project syncs instruction files from (repeatable). A project
#                  file at the same relative path there is marked upstream: identical files get
#                  no units (fix them upstream), changed ones raise an upstream-drift issue.
#
# Writes into <dir>:
#   inventory.json  {project, config_dir, memory_dir, sources[], issues[], totals}
#     issue: {type, path, line?, detail, fingerprint, declined}
#       types: imports and links (import-unresolved, import-too-deep, import-outside-roots,
#       link-not-import, pointer-unresolved), sources (source-outside-roots, glob-unmatched,
#       identical-files, generated-file, upstream-drift), memory (memory-index-truncated,
#       memory-pointer-broken, memory-orphan, memory-index-duplicate-row, memory-name-duplicate,
#       memory-dir-rejected, agent-memory-orphan), config (skill-override-dead, skill-link-broken,
#       skill-unlinked, mcp-setting-dead, permission-dead, hook-script-missing,
#       hook-script-outside), safety (sensitive-file-skipped, symlink-to-non-markdown)
#     source: {path, kind, scope, activation, why, bytes, lines, approx_tokens,
#              loaded_bytes?, listing_chars?, imports[], plugin?, generated?, upstream?}
#     kinds beyond the harness's own files: pointer-doc (a .md an instruction file names, up to
#       two hops), generator-source (what a generated instruction file is built from),
#       hook-script (a script a settings hook runs; its messages reach the agent)
#     activation: always (every session) | listing (name+description every turn, body on
#       demand) | lazy (when a file under its directory or paths: glob is touched) | agent
#       (when that subagent runs) | on-demand (read only when the agent opens it) | config
#       (settings, never text in context) | never | uncertain
#   config.json     settings keys, hooks, MCP servers, plugins: names and structure only.
#                   Values of env, headers, args, and anything token-shaped are never emitted.
#   units.jsonl     one audit unit per line: {id, path, line, end_line, heading, kind, scope,
#                   activation, text, fingerprint, declined, audited}
#     A skill a lock or generator installs (~/.agents/.skill-lock.json for user skills, the
#     project's skills-lock.json or boost.json for project skills) is third-party: its listed
#     description is a unit, its body is not (fixed upstream or by removing the skill).
#   dupes.jsonl     {a, b, score}: unit pairs whose word sets overlap >= 0.6
#   batch_<k>.jsonl units split for the sweep, whole sources kept together where they fit
# Prints a JSON summary to stdout. Token counts are bytes/4: an estimate, not a measurement.

set -e

out=""; project="$PWD"; home="$HOME"; config=""; managed=""; declined=""; batch=40; max_batches=10; audited=""; audited_days=14
scope="instructions,memory,config"; upstream=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out=$2; shift ;;
    --project) project=$2; shift ;;
    --home) home=$2; shift ;;
    --config-dir) config=$2; shift ;;
    --managed-dir) managed=$2; shift ;;
    --declined) declined=$2; shift ;;
    --batch-size) batch=$2; shift ;;
    --max-batches) max_batches=$2; shift ;;
    --audited) audited=$2; shift ;;
    --audited-days) audited_days=$2; shift ;;
    --scope) scope=$2; shift ;;
    --upstream) upstream="$upstream${upstream:+:}$2"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$out" ] || { echo "--out <dir> is required" >&2; exit 2; }
[ -d "$project" ] || { echo "Not a directory: $project" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
if [ -z "$config" ]; then
  if [ "$home" = "$HOME" ] && [ -n "$CLAUDE_CONFIG_DIR" ]; then config=$CLAUDE_CONFIG_DIR; else config="$home/.claude"; fi
fi
if [ -z "$managed" ]; then
  case "$(uname -s)" in
    Darwin) managed="/Library/Application Support/ClaudeCode" ;;
    *) managed="/etc/claude-code" ;;
  esac
fi
mkdir -p "$out"
rm -f "$out"/batch_*.jsonl
echo ">> inventory: project=$project config=$config" >&2

python3 - "$project" "$home" "$config" "$managed" "$out" "$declined" "$batch" "$scope" "$upstream" "$max_batches" "$audited" "$audited_days" <<'PY'
import datetime, glob, hashlib, json, math, os, re, subprocess, sys, urllib.parse
from fnmatch import fnmatch

project, home, config, managed, out, declined_path, batch_size, scope_arg, upstream_arg, max_batches, audited_path, audited_days = sys.argv[1:13]
upstreams = [os.path.realpath(os.path.expanduser(u)) for u in upstream_arg.split(":") if u]
SCOPES = {"instructions": {"claude-md", "claude-local", "rule", "agents-md", "import", "output-style", "pointer-doc", "generator-source"},
          "memory": {"memory-index", "memory", "agent-memory"},
          "config": {"skill", "agent", "command", "hook-script"}}
bad = [x for x in scope_arg.split(",") if x not in SCOPES]
if bad:
    sys.exit(f"Unknown --scope value(s): {bad}; use instructions, memory, config")
in_scope = set().union(*(SCOPES[x] for x in scope_arg.split(",")))
project_given = os.path.abspath(project)
project = os.path.realpath(project)
home = os.path.realpath(home)
config = os.path.realpath(os.path.expanduser(config))
batch_size, max_batches, audited_days = int(batch_size), int(max_batches), int(audited_days)

RANK = ["always", "listing", "lazy", "agent", "on-demand", "config", "uncertain", "never"]
SECRET = re.compile(
    r"(?<![A-Za-z0-9_-])(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    r"|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)"
    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)")
# Keep the key, drop the value: NAME_TOKEN=..., "password": "...", Bearer ..., --password ...,
# and user:pass@ or a long token@ in a URL. Short values (counts like "tokens: 1200") are left.
_STRONG = r"(?:secret|passw(?:or)?d|passphrase|api[_-]?key|access[_-]?key|private[_-]?key|credential|client[_-]?secret)"
_KEY = r"[A-Za-z0-9_.-]*{}[A-Za-z0-9_.-]*[\"']?\s*[=:]\s*"
_QVAL = r"(?:\\.|(?!\2)[^\\\n])"  # one quoted character: an escape, or anything but the quote, a backslash, a newline
SECRET_KV = [
    # A quoted value goes whole, commas and braces included, to its closing quote or, unterminated,
    # to the end of the line. The two alternatives of one character cannot both match it, so the
    # match is linear however long the value or its run of backslashes. `token` alone needs 8+ characters.
    (re.compile(r"(?i)(" + _KEY.format(_STRONG) + r")([\"'])" + _QVAL + r"*(?:\2|(?=\n)|$)"), r"\1\2[REDACTED]\2"),
    (re.compile(r"(?i)(" + _KEY.format("token") + r")([\"'])" + _QVAL + r"{8,}(?:\2|(?=\n)|$)"), r"\1\2[REDACTED]\2"),
    # Unquoted: a strong keyword's value at any length; a `token` value only from 8 characters, so a
    # count such as "tokens: 1200" stays readable. Only an already-redacted value is skipped.
    (re.compile(r"(?i)(" + _KEY.format(_STRONG) + r")(?![\"']|\[REDACTED\])([^\s\"',}]+)"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(" + _KEY.format("token") + r")(?![\"']|\[REDACTED\])([^\s\"',}]{8,})"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]{8,}"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(--(?:password|passwd|token|api-key|secret)(?:=|\s+))\S+"), r"\1[REDACTED]"),
    (re.compile(r"(://[^/\s:@]+:)[^/\s@]+(@)"), r"\1[REDACTED]\2"),
    (re.compile(r"(://)[^/\s:@]{16,}(@)"), r"\1[REDACTED]\2"),
]
# Files whose text never goes into units, however they are reached (@.env, a symlinked key).
SENSITIVE = re.compile(r"(?:^|/)\.env(?:\.[^/]*)?$|\.(?:pem|key|p12|pfx|keystore)$|(?:^|/)id_[a-z0-9]+$|(?:^|/)\.netrc$|(?:^|/)\.npmrc$")
SKIP_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".next", ".nuxt", "storage", ".venv", "venv", "__pycache__"}

def redact(s):
    s = SECRET.sub("[REDACTED]", s or "")
    for rx, sub in SECRET_KV:
        s = rx.sub(sub, s)
    return s

# ---- the repo boundary, fixed before any file is read ---------------------------------------
def git_root():
    try:
        r = subprocess.run(["git", "-C", project, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            common = r.stdout.strip()
            return os.path.dirname(common) if os.path.basename(common) == ".git" else common
    except (OSError, subprocess.SubprocessError):
        pass
    return project

repo_root = git_root()
# A repo file may reach only the repo itself. The git root counts only when it contains the
# project: a crafted .git file pointing elsewhere must not widen the boundary.
REPO = sorted({project} | ({os.path.realpath(repo_root)} if project.startswith(os.path.realpath(repo_root).rstrip("/") + "/") else set()))
def repo_controlled(path):
    a = os.path.abspath(path)
    return any(a == t or a.startswith(t.rstrip("/") + "/") for t in REPO)
def blocked(source_path, target):
    return repo_controlled(source_path) and not repo_controlled(os.path.realpath(target))

# ---- globs: Claude Code style (* within a segment, ** across, {a,b}, [abc]) --------------------
def expand_braces(g):
    m = re.search(r"\{([^{}]*)\}", g)
    if not m:
        return [g]
    return [x for alt in m.group(1).split(",") for x in expand_braces(g[:m.start()] + alt + g[m.end():])]

def glob_rx(g):
    rx, i = "", 0
    while i < len(g):
        if g.startswith("**/", i):
            rx, i = rx + "(?:.*/)?", i + 3
        elif g.startswith("**", i):
            rx, i = rx + ".*", i + 2
        elif g[i] == "[" and "]" in g[i + 2:]:
            j = g.index("]", i + 2)
            cls = g[i + 1:j]
            rx, i = rx + "[" + ("^" + cls[1:] if cls.startswith("!") else cls).replace("\\", "\\\\") + "]", j + 1
        else:
            rx, i = rx + {"*": "[^/]*", "?": "[^/]"}.get(g[i], re.escape(g[i])), i + 1
    return re.compile(rx + "$")

def glob_rxs(g):
    return [glob_rx(x) for x in expand_braces(g)]

def read(p):
    # The one read seam: a secrets file is never opened, so it is never sized, walked, or hashed.
    if blocked(p, p) or SENSITIVE.search(p) or SENSITIVE.search(os.path.realpath(p)):
        return None
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None

def load_json(p):
    t = read(p)
    if not t:
        return None
    try:
        return json.loads(t)
    except ValueError:
        return None

def tok(n):
    return (n + 3) // 4

def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text or "", re.S)
    return m.group(1) if m else ""

def fm_value(fm, key):
    m = re.search(rf"^{key}:\s*(.*)$", fm, re.M)
    if not m:
        return None
    v = m.group(1).strip()
    if v in (">", "|", ">-", "|-", ""):
        rest = fm[m.end():].split("\n")
        cont = []
        for line in rest[1:]:
            if line.startswith((" ", "\t")):
                cont.append(line.strip())
            else:
                break
        v = " ".join(cont)
    return v.strip("\"'")

sources, issues = {}, []

def add(path, kind, scope, activation, why, **kw):
    path = os.path.abspath(path)
    key = os.path.realpath(path)  # a symlinked file is one source, listed under the first path seen
    if key in sources:
        s = sources[key]
        if RANK.index(activation) < RANK.index(s["activation"]):
            s["activation"], s["why"] = activation, why + "; also " + s["why"]
        return s
    text = read(path)
    b = len(text.encode("utf-8")) if text is not None else 0
    s = dict(path=path, real_path=key, kind=kind, scope=scope, activation=activation, why=why, bytes=b,
             lines=(text.count("\n") + (0 if text.endswith("\n") else 1)) if text else 0,
             approx_tokens=tok(b), imports=[])
    s.update(kw)
    sources[key] = s
    return s

def known(path):
    return sources.get(os.path.realpath(path))

# ---- settings ---------------------------------------------------------------------------
settings_files = [("managed", os.path.join(managed, "managed-settings.json")),
                  ("user", os.path.join(config, "settings.json")),
                  ("project", os.path.join(project, ".claude", "settings.json")),
                  ("local", os.path.join(project, ".claude", "settings.local.json"))]
settings = {}
for scope, p in settings_files:
    data = load_json(p)
    if isinstance(data, dict):
        settings[scope] = data
        add(p, "settings", scope, "config", "settings file: shapes behaviour, adds no text")

def merged(key, order=("user", "project", "local", "managed")):
    val = None
    for sc in order:
        if key in settings.get(sc, {}):
            val = settings[sc][key]
    return val

excludes = []
for sc in settings:
    excludes += [os.path.expanduser(g) for g in settings[sc].get("claudeMdExcludes", []) or []]
env = {}
for sc in ("user", "project", "local", "managed"):
    env.update(settings.get(sc, {}).get("env", {}) or {})
enabled_plugins = {}
for sc in ("user", "project", "local", "managed"):
    enabled_plugins.update(settings.get(sc, {}).get("enabledPlugins", {}) or {})
# cc-plugin-agents-md@builtin's instructionFiles: "claude-md-or-agents-md" is the default
# (AGENTS.md only when no CLAUDE.md), an "-and-" value loads both, anything else is unverified.
skill_overrides, override_src = {}, {}
for sc in ("user", "project", "local", "managed"):
    for k, v in (settings.get(sc, {}).get("skillOverrides") or {}).items():
        skill_overrides[k], override_src[k] = v, dict(settings_files)[sc]
agents_md_mode = "claude-md-or-agents-md"
for sc in ("user", "project", "local", "managed"):
    pc = (settings.get(sc, {}).get("pluginConfigs") or {}).get("cc-plugin-agents-md@builtin") or {}
    agents_md_mode = (pc.get("options") or {}).get("instructionFiles", agents_md_mode)

exclude_rxs = [r for g in excludes for r in glob_rxs(g)]
def excluded(p):
    return any(r.match(c) for r in exclude_rxs for c in {os.path.abspath(p), os.path.realpath(p)})

def add_instruction(p, kind, scope, activation, why):
    if excluded(p):
        return add(p, kind, scope, "never", "matched claudeMdExcludes")
    return add(p, kind, scope, activation, why)

# ---- managed + user instructions -----------------------------------------------------------
if os.path.isfile(os.path.join(managed, "CLAUDE.md")):
    add(os.path.join(managed, "CLAUDE.md"), "claude-md", "managed", "always", "managed policy CLAUDE.md")
user_md = os.path.join(config, "CLAUDE.md")
if os.path.isfile(user_md):
    add_instruction(user_md, "claude-md", "user", "always", "user CLAUDE.md in the config dir")

def scan_rules(d, scope):
    for p in sorted(glob.glob(os.path.join(d, "**", "*.md"), recursive=True)):
        fm = frontmatter(read(p))
        if re.search(r"^paths:", fm, re.M):
            add_instruction(p, "rule", scope, "lazy", "rule with paths: loads when a matching file is read or edited")
        else:
            add_instruction(p, "rule", scope, "always", "rule without paths: loads every session")

scan_rules(os.path.join(config, "rules"), "user")

# ---- the cwd chain, root first -----------------------------------------------------------------
chain, d = [], project
while True:
    chain.append(d)
    parent = os.path.dirname(d)
    if parent == d:
        break
    d = parent
chain.reverse()
claude_in_chain = False
default_user_md = os.path.join(home, ".claude", "CLAUDE.md")
for d in chain:
    scope = "project" if d == project else "ancestor"
    for name, kind in (("CLAUDE.md", "claude-md"), (".claude/CLAUDE.md", "claude-md"), ("CLAUDE.local.md", "claude-local")):
        p = os.path.join(d, name)
        if not os.path.isfile(p):
            continue
        if p == default_user_md:
            # The default config dir's CLAUDE.md is the user file, never a project one. Under
            # CLAUDE_CONFIG_DIR it loads only when the active config dir's CLAUDE.md is the same file.
            if not known(p):
                add(p, "claude-md", "user", "never", "default config dir's CLAUDE.md; CLAUDE_CONFIG_DIR points elsewhere")
            continue
        if add_instruction(p, kind, scope, "always", f"{name} in the cwd chain")["activation"] != "never":
            claude_in_chain = True
scan_rules(os.path.join(project, ".claude", "rules"), "project")
for d in chain:
    p = os.path.join(d, "AGENTS.md")
    if os.path.isfile(p):
        scope = "project" if d == project else "ancestor"
        if "-and-" in agents_md_mode:
            add(p, "agents-md", scope, "always", f"instructionFiles is {agents_md_mode}")
        elif agents_md_mode != "claude-md-or-agents-md":
            add(p, "agents-md", scope, "uncertain", f"instructionFiles is {agents_md_mode}, a value this script has not verified")
        elif claude_in_chain:
            add(p, "agents-md", scope, "never", "a CLAUDE.md exists in the cwd chain, so Claude Code skips AGENTS.md unless it is imported")
        else:
            add(p, "agents-md", scope, "always", "no CLAUDE.md in the cwd chain, so Claude Code reads AGENTS.md (v2.1.277+)")

# ---- nested files under the project ---------------------------------------------------------------
def project_files(patterns):
    try:
        r = subprocess.run(["git", "-C", project, "ls-files", "--cached", "--others", "--exclude-standard", "--"] + patterns,
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            return [os.path.join(project, f) for f in r.stdout.splitlines() if f]
    except (OSError, subprocess.SubprocessError):
        pass
    found = []
    for root, dirs, files in os.walk(project):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), project)
            if any(fnmatch(rel, pat) or fnmatch(f, pat.split("/")[-1]) for pat in patterns):
                found.append(os.path.join(root, f))
    return found

def ignored_files(patterns):
    try:
        r = subprocess.run(["git", "-C", project, "ls-files", "--others", "--ignored", "--exclude-standard", "--"] + patterns,
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            # git also lists ignored nested repos (worktrees) as bare directories: keep real files
            # whose name matches, nothing else.
            names = {pat.split("/")[-1] for pat in patterns}
            return [os.path.join(project, f) for f in r.stdout.splitlines()
                    if f and os.path.basename(f) in names and os.path.isfile(os.path.join(project, f))
                    and not set(f.split("/")) & SKIP_DIRS]
    except (OSError, subprocess.SubprocessError):
        pass
    return []

for p in project_files(["**/CLAUDE.md", "**/CLAUDE.local.md", "**/AGENTS.md", "CLAUDE.md", "AGENTS.md", "CLAUDE.local.md"]) \
        + ignored_files(["**/CLAUDE.local.md", "CLAUDE.local.md"]):
    p = os.path.abspath(p)
    if known(p) or os.path.dirname(p) == project or "/.claude/rules/" in p:
        continue
    if os.path.basename(p) == "AGENTS.md":
        add(p, "agents-md", "directory", "uncertain", "nested AGENTS.md: loading not documented")
    else:
        add_instruction(p, "claude-md" if p.endswith("CLAUDE.md") else "claude-local", "directory", "lazy",
                        "nested file: loads when a file under its directory is read or edited")

for name in (".cursorrules", ".windsurfrules", ".clinerules", "GEMINI.md", ".github/copilot-instructions.md"):
    p = os.path.join(project, name)
    if os.path.isfile(p):
        add(p, "other-tool", "project", "never", "another tool's instruction file; Claude Code never reads it")
for p in glob.glob(os.path.join(project, ".cursor", "rules", "**", "*"), recursive=True):
    if os.path.isfile(p):
        add(p, "other-tool", "project", "never", "Cursor rule; Claude Code never reads it")

# ---- auto memory ------------------------------------------------------------------------------------
def memory_window(text):
    """Bytes and whole lines of a MEMORY.md that load: the first 200 lines or 25KB."""
    used, n = 0, 0
    for line in text.splitlines(keepends=True)[:200]:
        b = len(line.encode("utf-8"))
        if used + b > 25000:
            break
        used, n = used + b, n + 1
    return used, n

def memory_checks(d, index, topics):
    """Index rows that point nowhere or repeat, topic files nothing links, and two files that
    share one frontmatter name (the agent cannot tell which one the name means)."""
    linked, seen_rows, names = set(), {}, {}
    if os.path.isfile(index):
        for n, line in enumerate((read(index) or "").splitlines(), 1):
            for target in re.findall(r"\]\(([^)#\s]+\.md)\)", line):
                full = os.path.normpath(os.path.join(d, target))
                linked.add(full)
                if not os.path.isfile(full):
                    issues.append(dict(type="memory-pointer-broken", path=index, line=n, detail=f"points at missing {target}"))
                elif full in seen_rows:
                    issues.append(dict(type="memory-index-duplicate-row", path=index, line=n,
                                       detail=f"{target} is already indexed on line {seen_rows[full]}"))
                else:
                    seen_rows[full] = n
    for p in topics:
        if os.path.isfile(index) and p not in linked:
            issues.append(dict(type="memory-orphan", path=p, detail="topic file not linked from MEMORY.md, so nothing points the agent at it"))
        name = fm_value(frontmatter(read(p)), "name")
        if name:
            names.setdefault(name, []).append(p)
    for name, ps in sorted(names.items()):
        if len(ps) > 1:
            issues.append(dict(type="memory-name-duplicate", path=ps[0],
                               detail=f'name "{name}" is shared by {", ".join(os.path.basename(p) for p in ps)}'))

slug = re.sub(r"[^A-Za-z0-9]", "-", repo_root)
# Never from project settings: a repo must not be able to point this audit at another directory.
# Only user and managed settings: a repo can commit .claude/settings.local.json too. A value
# resolving to / or the home directory is ignored, since it would make everything trusted.
mem_setting = merged("autoMemoryDirectory", order=("user", "managed"))
mem_default = os.path.join(config, "projects", slug, "memory")
mem_dir = os.path.expanduser(mem_setting) if mem_setting else mem_default
if os.path.realpath(mem_dir) in ("/", home):
    issues.append(dict(type="memory-dir-rejected", path=mem_dir, detail="autoMemoryDirectory resolves to / or the home directory; the default was audited instead"))
    mem_dir = mem_default
mem_off = merged("autoMemoryEnabled") is False or str(env.get("CLAUDE_CODE_DISABLE_AUTO_MEMORY", os.environ.get("CLAUDE_CODE_DISABLE_AUTO_MEMORY", ""))) == "1"
if os.path.isdir(mem_dir):
    index = os.path.join(mem_dir, "MEMORY.md")
    topics = sorted(p for p in glob.glob(os.path.join(mem_dir, "**", "*.md"), recursive=True) if p != index)
    if os.path.isfile(index):
        loaded, window_lines = memory_window(read(index) or "")
        s = add(index, "memory-index", "project-memory", "never" if mem_off else "always",
                "auto memory disabled" if mem_off else "auto-memory index: first 200 lines or 25KB load every session",
                loaded_bytes=loaded, window_lines=window_lines)
        if loaded < s["bytes"]:
            issues.append(dict(type="memory-index-truncated", path=index,
                               detail=f"MEMORY.md is {s['lines']} lines / {s['bytes']} bytes; only the first 200 lines or 25KB load"))
    for p in topics:
        add(p, "memory", "project-memory", "never" if mem_off else "on-demand", "memory topic file: read only when the agent opens it")
    memory_checks(mem_dir, index, topics)

# ---- agents, skills, commands, plugins -------------------------------------------------------------
known_agents = set()

def add_listed(p, kind, scope, plugin=None):
    text = read(p) or ""
    fm = frontmatter(text)
    desc = " ".join(x for x in (fm_value(fm, "description"), fm_value(fm, "when_to_use")) if x)
    name = fm_value(fm, "name") or os.path.basename(os.path.dirname(p) if kind == "skill" else p)[:-3 if kind != "skill" else None]
    if kind == "agent":
        known_agents.add(name)
        if plugin:
            known_agents.add(plugin.split("@")[0] + "-" + name)
    user_only = bool(re.search(r"^disable-model-invocation:\s*true", fm, re.M))
    act = "on-demand" if user_only else "listing"
    why = "user-invoked: no description in context" if user_only else "name and description listed every turn; body on demand"
    chars = 0 if user_only else min(len(desc), 1536)
    # skillOverrides (settings) hides or trims a non-plugin skill; plugin skills ignore it.
    override = skill_overrides.get(name) or skill_overrides.get(os.path.basename(os.path.dirname(p))) if kind == "skill" and not plugin else None
    if override == "off":
        act, why, chars = "never", "skillOverrides: off (hidden from the model)", 0
    elif override == "user-invocable-only":
        act, why, chars = "on-demand", "skillOverrides: user-invocable-only (no description in context)", 0
    elif override == "name-only":
        act, why, chars = "listing", "skillOverrides: name-only (name listed, no description)", 0
    # usage_key joins usage-counts.sh: a plugin item is invoked as <plugin>:<name>.
    kw = dict(listing_chars=chars, name=name, usage_key=(plugin.split("@")[0] + ":" + name) if plugin else name)
    if plugin:
        kw["plugin"] = plugin
    return add(p, kind, scope, act, why, **kw)

def declared(base, plugin, key):
    """A plugin's own list for key (skills, agents, commands): plugin.json first, then its entry
    in a marketplace.json shipped in the same install. None means use the default directory."""
    name = (plugin or "").split("@")[0]
    manifests = [load_json(os.path.join(base, ".claude-plugin", "plugin.json")) or {}]
    mk = load_json(os.path.join(base, ".claude-plugin", "marketplace.json")) or {}
    manifests += [e for e in mk.get("plugins") or [] if isinstance(e, dict) and e.get("name") == name]
    for m in manifests:
        val = m.get(key)
        if val:
            return [os.path.normpath(os.path.join(base, v)) for v in ([val] if isinstance(val, str) else val)]
    return None

def scan_listed(base, scope, plugin=None):
    skills = declared(base, plugin, "skills") if plugin else None
    skill_files = [os.path.join(d, "SKILL.md") for d in skills] if skills is not None else glob.glob(os.path.join(base, "skills", "*", "SKILL.md"))
    for p in sorted(f for f in skill_files if os.path.isfile(f)):
        add_listed(p, "skill", scope, plugin)
    for key, kind in (("agents", "agent"), ("commands", "command")):
        listed = declared(base, plugin, key) if plugin else None
        roots = listed if listed is not None else [os.path.join(base, key)]
        files = []
        for r in roots:
            files += [r] if os.path.isfile(r) else glob.glob(os.path.join(r, "**", "*.md"), recursive=True)
        for p in sorted(files):
            add_listed(p, kind, scope, plugin)
    for p in sorted(glob.glob(os.path.join(base, "output-styles", "*.md"))):
        add(p, "output-style", scope, "never", "output style not selected")

scan_listed(config, "user")
scan_listed(os.path.join(project, ".claude"), "project")

def skill_name(s):
    return s.get("name") or os.path.basename(os.path.dirname(s["path"]))

# Personal beats project: a project skill with a user skill's name never loads. When the user copy
# is hidden (skillOverrides "off"), whether the project copy shows is undocumented.
user_skill = {skill_name(s): s for s in sources.values() if s["kind"] == "skill" and s["scope"] == "user"}
for s in list(sources.values()):
    u = user_skill.get(skill_name(s)) if s["kind"] == "skill" and s["scope"] == "project" else None
    if u:
        s["shadowed_by"] = u["path"]
        if u["activation"] == "never":
            s["activation"], s["why"] = "uncertain", "the personal skill of the same name is hidden; whether this project copy shows is undocumented"
        else:
            s["activation"], s["why"], s["listing_chars"] = "never", "shadowed: a personal skill of the same name wins over a project skill", 0

# Third-party skills: what a lock or generator installs is fixed upstream, so only its listed
# description is audited here.
def lock_names(p):
    data = load_json(p) or {}
    val = data.get("skills") if isinstance(data, dict) else None
    return set(val) if isinstance(val, (dict, list)) else set()
user_lock = os.path.join(home, ".agents", ".skill-lock.json")
installers = {"user": [(user_lock, lock_names(user_lock))],
              "project": [(os.path.join(project, "skills-lock.json"), lock_names(os.path.join(project, "skills-lock.json"))),
                          (os.path.join(project, "boost.json"), lock_names(os.path.join(project, "boost.json")))]}
global_store = os.path.realpath(os.path.join(home, ".agents", "skills")) + os.sep
for s in sources.values():
    if s["kind"] != "skill":
        continue
    pairs = list(installers.get(s["scope"], []))
    if s["scope"] == "project" and s["real_path"].startswith(global_store):
        pairs += installers["user"]  # a project link into the global npx-skills store
    for lock, names in pairs:
        if skill_name(s) in names:
            s["third_party"] = lock
            break

plugins = []
installed = load_json(os.path.join(config, "plugins", "installed_plugins.json")) or {}
def plugin_entry(key):
    entries = (installed.get("plugins") or {}).get(key)
    e = entries[0] if isinstance(entries, list) and entries else entries
    return e if isinstance(e, dict) else {}
for key in sorted(installed.get("plugins") or {}):
    entry = plugin_entry(key)
    path = entry.get("installPath") or ""
    state = enabled_plugins.get(key)
    info = dict(key=key, version=entry.get("version"), scope=entry.get("scope"), enabled=state,
                skills=0, model_invoked_skills=0, agents=0, commands=0, listing_chars=0, hooks=False, mcp=False)
    if state is not False and os.path.isdir(path):
        before = set(sources)
        scan_listed(path, "plugin", plugin=key)
        for p in set(sources) - before:
            s = sources[p]
            if state is None:
                s["activation"], s["why"] = "uncertain", "plugin installed but absent from enabledPlugins"
            if s["kind"] in ("skill", "agent", "command"):
                info[s["kind"] + "s"] += 1
                info["listing_chars"] += s.get("listing_chars", 0)
                if s["kind"] == "skill" and s["activation"] == "listing":
                    info["model_invoked_skills"] += 1
        info["hooks"] = os.path.isfile(os.path.join(path, "hooks", "hooks.json"))
        info["mcp"] = os.path.isfile(os.path.join(path, ".mcp.json"))
    plugins.append(info)

# skillOverrides keys that hide nothing: no such user or project skill, or a plugin skill
# (plugin skills ignore skillOverrides, so the entry is dead config either way).
own_skills = {s.get("name") for s in sources.values() if s["kind"] == "skill" and not s.get("plugin")}
own_skills |= {os.path.basename(os.path.dirname(s["path"])) for s in sources.values() if s["kind"] == "skill" and not s.get("plugin")}
plugin_skills = {s.get("name") for s in sources.values() if s["kind"] == "skill" and s.get("plugin")}
own_commands = {s.get("name") for s in sources.values() if s["kind"] == "command" and not s.get("plugin")}
for key, val in sorted(skill_overrides.items()):
    if key not in own_skills:
        why = ("names a plugin skill, and plugin skills ignore skillOverrides" if key in plugin_skills else
               "names a command, not a skill; whether skillOverrides applies to commands is undocumented" if key in own_commands else
               "names no local user or project skill; dead unless a bundled or claude.ai-synced skill of that name is in the session's skill list")
        issues.append(dict(type="skill-override-dead", path=override_src.get(key, ""),
                           detail=f'skillOverrides "{key}": "{val}" {why}'))

# Skill directories: a symlink to nothing, and a skill under .agents/skills (read by Codex and
# other harnesses) with no entry in .claude/skills, which Claude Code cannot load.
claude_skills = os.path.join(project, ".claude", "skills")
for base in (os.path.join(config, "skills"), claude_skills):
    for e in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        p = os.path.join(base, e)
        if os.path.islink(p) and not os.path.exists(p):
            issues.append(dict(type="skill-link-broken", path=p, detail=f"symlink to missing {os.readlink(p)}"))
agents_skills = os.path.join(project, ".agents", "skills")
if os.path.isdir(agents_skills):
    linked_here = {os.path.realpath(os.path.join(claude_skills, e)) for e in os.listdir(claude_skills)} if os.path.isdir(claude_skills) else set()
    for e in sorted(os.listdir(agents_skills)):
        p = os.path.join(agents_skills, e)
        if os.path.isfile(os.path.join(p, "SKILL.md")) and os.path.realpath(p) not in linked_here \
                and not os.path.exists(os.path.join(claude_skills, e)):
            issues.append(dict(type="skill-unlinked", path=os.path.join(p, "SKILL.md"),
                               detail=f"{e} is in .agents/skills but not .claude/skills: other harnesses load it, Claude Code cannot"))

# Settings that name things that do not exist: .mcp.json servers, and permission rules for an
# MCP server a plugin would register when no plugin of that name is installed.
mcp_json_names = set(((load_json(os.path.join(project, ".mcp.json")) or {}).get("mcpServers") or {}).keys())
plugin_names = {k.split("@")[0] for k in (installed.get("plugins") or {})}
for sc, p in settings_files:
    data = settings.get(sc) or {}
    for key in ("enabledMcpjsonServers", "disabledMcpjsonServers"):
        for name in data.get(key) or []:
            if name not in mcp_json_names:
                issues.append(dict(type="mcp-setting-dead", path=p, detail=f'{key} names "{name}", which is not in .mcp.json'))
    for kind_, rules in (data.get("permissions") or {}).items():
        for rule in rules if isinstance(rules, list) else []:
            m = re.match(r"mcp__plugin_(.+?)__", str(rule))
            if m and not any(m.group(1) == n or m.group(1).startswith(n + "_") for n in plugin_names):
                issues.append(dict(type="permission-dead", path=p, detail=f'{kind_} rule "{rule}" names a plugin MCP server, and no matching plugin is installed'))

style = merged("outputStyle")
if style and style.lower() not in ("default",):
    hit = next((p for base in (os.path.join(project, ".claude"), config)
                for p in sorted(glob.glob(os.path.join(base, "output-styles", "*.md")))
                if fm_value(frontmatter(read(p)), "name") == style or os.path.basename(p)[:-3] == style), None)
    if hit:
        s = known(hit) or add(hit, "output-style", "user", "never", "")
        s["activation"], s["why"] = "always", "selected output style: its text joins every request"

# ---- subagent memory ----------------------------------------------------------------------------------
for base, scope in ((os.path.join(config, "agent-memory"), "agent-memory:user"),
                    (os.path.join(project, ".claude", "agent-memory"), "agent-memory:project"),
                    (os.path.join(project, ".claude", "agent-memory-local"), "agent-memory:local")):
    for d in sorted(glob.glob(os.path.join(base, "*"))):
        if not os.path.isdir(d):
            continue
        name = os.path.basename(d)
        has_agent = name in known_agents
        files = sorted(glob.glob(os.path.join(d, "**", "*.md"), recursive=True))
        for p in files:
            act = "agent" if os.path.basename(p) == "MEMORY.md" else "on-demand"
            extra = {}
            if act == "agent":
                extra["loaded_bytes"], extra["window_lines"] = memory_window(read(p) or "")
            s = add(p, "agent-memory", scope, act, f"memory of subagent {name}" + ("" if has_agent else " (no agent of that name found)"), **extra)
            if act == "agent" and s.get("loaded_bytes", 0) < s["bytes"]:
                issues.append(dict(type="memory-index-truncated", path=p,
                                   detail=f"{s['lines']} lines / {s['bytes']} bytes; only the first 200 lines or 25KB reach the agent"))
            if not has_agent:
                issues.append(dict(type="agent-memory-orphan", path=p, detail=f"no installed agent named {name}"))
        index = os.path.join(d, "MEMORY.md")
        memory_checks(d, index, [p for p in files if p != index])

# ---- imports (after every source is known, so a lazy file's imports are lazy) ------------------------
CODE = re.compile(r"(^|\n)(```|~~~).*?(\n\2[^\n]*|$)", re.S)
SPAN = re.compile(r"`[^`\n]*`")
IMPORT = re.compile(r"(?:^|(?<=\s))@((?:~/|/)?[A-Za-z0-9_.][A-Za-z0-9_./-]*)")  # dot segments too: @../.claude/x
LINK = re.compile(r"\]\(([^)#\s]+)\)")
md_kinds = {"claude-md", "claude-local", "rule", "agents-md", "import", "memory-index", "output-style"}
frontier = [p for p, s in sources.items() if s["kind"] in md_kinds and s["activation"] in ("always", "lazy", "uncertain")]
depth = {p: 0 for p in frontier}
while frontier:
    p = frontier.pop(0)
    s = sources[p]
    text = read(p) or ""
    bare = SPAN.sub("", CODE.sub("\n", text))
    for target in IMPORT.findall(bare):
        target = target.rstrip(".,;:)")
        if "/" not in target and "." not in target:
            continue  # a mention (@leek), not a path
        if not target.startswith(("./", "../", "~/", "/")) and "." not in os.path.basename(target):
            continue  # a package name (@types/node), not a file
        full = os.path.normpath(os.path.join(os.path.dirname(p), os.path.expanduser(target)))
        if blocked(s["path"], full):
            issues.append(dict(type="import-outside-roots", path=s["path"],
                               detail=f"@{target} resolves outside the project and config dirs; not read. Claude Code asks before loading it"))
            continue
        s["imports"].append(full)
        if not os.path.isfile(full):
            issues.append(dict(type="import-unresolved", path=s["path"], detail=f"@{target} resolves to nothing"))
            continue
        if depth[p] >= 4:
            issues.append(dict(type="import-too-deep", path=s["path"], detail=f"@{target} is past the 4-hop import limit"))
            continue
        key = os.path.realpath(full)
        before = (known(full) or {}).get("activation")
        add(full, "import", s["scope"], s["activation"], f"imported by {s['path']}")
        if key not in depth or (before and known(full)["activation"] != before):
            depth[key] = min(depth.get(key, 99), depth[p] + 1)
            frontier.append(key)
    if s["activation"] == "always":
        for target in LINK.findall(bare):
            full = os.path.normpath(os.path.join(os.path.dirname(p), target))
            t = known(full)
            if t and t["kind"] == "agents-md" and t["activation"] == "never":
                issues.append(dict(type="link-not-import", path=s["path"],
                                   detail=f"links to {target} ({t['approx_tokens']} tokens) without importing it; that file never loads at startup. Use @{target} to load it"))

# ---- generated instruction files: edits go to the source, then the generator runs ---------------------
GEN = re.compile(r"(?i)\bdo not edit\b|\bauto-?generated\b|\bthis file (?:is|was) generated\b|\bgenerated by\b")
boost_src = os.path.join(project, ".ai", "guidelines")
for p, s in list(sources.items()):
    if s["kind"] not in ("claude-md", "claude-local", "agents-md", "rule", "other-tool") or s.get("plugin"):
        continue
    text = read(p) or ""
    boost_made = "<laravel-boost-guidelines>" in text
    if not (boost_made or GEN.search("\n".join(text.splitlines()[:15]))):
        continue
    s["generated"] = True
    if boost_made and os.path.isdir(boost_src):
        s["generated_from"], s["boost_block"] = boost_src, True
        issues.append(dict(type="generated-file", path=s["path"],
                           detail="built by Laravel Boost: edit .ai/guidelines/, then run php artisan boost:update; never edit this file"))
        for g in sorted(glob.glob(os.path.join(boost_src, "**", "*"), recursive=True)):
            if os.path.isfile(g) and g.endswith((".md", ".blade.php")) and not known(g):
                add(g, "generator-source", "project", "never", f"source of the generated {os.path.relpath(s['path'], project)}")
    else:
        issues.append(dict(type="generated-file", path=s["path"],
                           detail="its header marks it generated: find the source and generator, edit the source, regenerate"))

# ---- upstream-synced copies: fixed in the upstream checkout, never here ------------------------------
for p, s in list(sources.items()):
    if not upstreams or s.get("plugin") or s.get("generated") or not s["path"].startswith(project + os.sep) \
            or s["kind"] in ("settings", "memory", "memory-index", "agent-memory"):
        continue
    rel = os.path.relpath(s["path"], project)
    for u in upstreams:
        up = os.path.join(u, rel)
        if os.path.isfile(up):
            s["upstream"] = u
            if (read(up) or "") != (read(p) or ""):
                s["upstream_drift"] = True
                issues.append(dict(type="upstream-drift", path=s["path"],
                                   detail=f"differs from {up}: settle which side is right and fix it upstream, or the next sync undoes it"))
            break

# ---- pointer docs: .md files an instruction file names, read when the agent follows the pointer ----------
PATH_TOKEN = re.compile(r"(?<![\w@/.-])((?:\.{1,2}/)?[\w.-]+(?:/[\w.-]+)+\.md)(?![\w/-])")
LINK_MD = re.compile(r"\]\(([^)#\s:]+\.md)(?:#[^)]*)?\)")

def resolve_from(src, target):
    for base in (os.path.dirname(src), project):
        full = os.path.normpath(os.path.join(base, target))
        if os.path.isfile(full):
            return full
    return None

def in_project(p):
    rp = os.path.realpath(p)
    return rp.startswith(project + os.sep) and not set(os.path.relpath(rp, project).split(os.sep)) & SKIP_DIRS

pointer_from = md_kinds - {"memory-index"}
frontier = [(p, 0) for p, s in sources.items()
            if s["kind"] in pointer_from and s["activation"] in ("always", "lazy") and not s.get("plugin")]
while frontier:
    p, hop = frontier.pop(0)
    s = sources[p]
    fenced = False
    for n, line in enumerate((read(p) or "").splitlines(), 1):
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if fenced:
            continue
        for target in LINK_MD.findall(line):
            if not resolve_from(p, target):
                issues.append(dict(type="pointer-unresolved", path=s["path"], line=n, detail=f"links to {target}, which does not exist"))
        if hop >= 2:
            continue
        for target in set(PATH_TOKEN.findall(line)) | set(LINK_MD.findall(line)):
            full = resolve_from(p, target)
            if full and in_project(full) and not known(full):
                add(full, "pointer-doc", "project", "on-demand",
                    f"named by {os.path.relpath(s['path'], project)}: loads when the agent opens it")
                frontier.append((os.path.realpath(full), hop + 1))

# ---- globs that match no file: a rule's paths:, and a rules-index table (globs | rule file) -------------
_repo_files = None
def repo_files():
    global _repo_files
    if _repo_files is None:
        _repo_files = [os.path.relpath(f, project) for f in project_files(["*"])]
    return _repo_files

def glob_matches(g):
    rxs = glob_rxs(g[2:] if g.startswith("./") else g)
    return any(r.match(f) for r in rxs for f in repo_files())

def fm_paths(fm):
    m = re.search(r"^paths:[ \t]*(.*)$", fm, re.M)
    if not m:
        return []
    if m.group(1).strip():
        return [x.strip().strip("'\"") for x in re.split(r",(?![^{]*\})", m.group(1).strip().strip("[]")) if x.strip()]
    vals = []
    for line in fm[m.end():].split("\n")[1:]:
        item = re.match(r"^\s*-\s*(.+)$", line)
        if not item:
            break
        vals.append(item.group(1).strip().strip("'\""))
    return vals

GLOB_TOKEN = re.compile(r"^[\w.*?/{}\[\]-]+$")
for p, s in list(sources.items()):
    if s.get("plugin") or not s["path"].startswith(project + os.sep) or (s.get("upstream") and not s.get("upstream_drift")):
        continue
    lines = (read(p) or "").splitlines()
    def line_of(token):
        return next((n for n, l in enumerate(lines, 1) if token in l), None)
    if s["kind"] == "rule":
        for g in fm_paths(frontmatter(read(p))):
            if not glob_matches(g):
                issues.append(dict(type="glob-unmatched", path=s["path"], line=line_of(g), detail=f"paths: glob {g} matches no file, so the rule never loads"))
    if s["kind"] in pointer_from | {"pointer-doc"}:
        for n, line in enumerate(lines, 1):
            cells = [c.strip().strip("`") for c in line.strip().strip("|").split("|")] if line.lstrip().startswith("|") else []
            # An index row is exactly "globs | rule file"; a prose table that mentions a file is not one.
            globs = [x.strip().strip("`") for x in re.split(r",(?![^{]*\})", cells[0])] if len(cells) == 2 else []
            if not globs or not cells[1].endswith(".md") or not resolve_from(p, cells[1]) \
                    or not all(GLOB_TOKEN.match(g) for g in globs):
                continue
            for g in globs:
                if ("/" in g or "*" in g) and not glob_matches(g):
                    issues.append(dict(type="glob-unmatched", path=s["path"], line=n, detail=f"index glob {g} matches no file"))

# ---- identical copies: the same bytes at two paths (a symlink is one source, so these are real copies) ----
by_hash = {}
for p, s in sources.items():
    if s["kind"] in ("claude-md", "claude-local", "rule", "agents-md", "import", "pointer-doc", "skill", "agent") \
            and not s.get("plugin") and s["activation"] != "never" and s["bytes"]:
        by_hash.setdefault(hashlib.sha1((read(p) or "").encode()).hexdigest(), []).append(s)
for group in by_hash.values():
    if len(group) > 1:
        issues.append(dict(type="identical-files", path=group[0]["path"],
                           detail="same bytes as " + ", ".join(g["path"] for g in group[1:])
                                  + ": paid twice when both load, and the copies drift; keep one, or symlink the other"))

# ---- MCP and hooks (config.json: names and structure only) ------------------------------------------
def mcp_entry(name, cfg, scope, plugin=None):
    cfg = cfg if isinstance(cfg, dict) else {}
    url = str(cfg.get("url") or "")
    try:
        host = urllib.parse.urlsplit(url).hostname if url else None
    except ValueError:
        host = None
    # A plugin's server is called as mcp__plugin_<plugin>_<server>__<tool> (usage-counts.sh keys).
    return dict(name=name, scope=scope, type=cfg.get("type") or ("http" if url else "stdio"),
                usage_key=f"plugin_{plugin.split('@')[0]}_{name}" if plugin else name,
                command=os.path.basename(str(cfg.get("command") or "")) or None,
                host=host,
                always_load=bool(cfg.get("alwaysLoad")),
                env_keys=sorted((cfg.get("env") or {}).keys()), header_keys=sorted((cfg.get("headers") or {}).keys()))

mcp = []
for name, cfg in ((load_json(os.path.join(project, ".mcp.json")) or {}).get("mcpServers") or {}).items():
    mcp.append(mcp_entry(name, cfg, "project"))
default_config = os.path.realpath(os.path.join(home, ".claude"))
cj = os.path.join(home, ".claude.json") if config == default_config else os.path.join(config, ".claude.json")
data = load_json(cj)
if isinstance(data, dict):
    for name, cfg in (data.get("mcpServers") or {}).items():
        mcp.append(mcp_entry(name, cfg, "user"))
    projects = data.get("projects") or {}
    entry = projects.get(project) or projects.get(project_given) or {}
    for name, cfg in (entry.get("mcpServers") or {}).items():
        mcp.append(mcp_entry(name, cfg, "local"))
for info in plugins:
    if info["mcp"]:
        entry = plugin_entry(info["key"])
        for name, cfg in ((load_json(os.path.join(entry.get("installPath", ""), ".mcp.json")) or {}).get("mcpServers") or {}).items():
            mcp.append(mcp_entry(name, cfg, "plugin:" + info["key"], plugin=info["key"]))

hooks = []
def collect_hooks(data, scope):
    for event, groups in ((data or {}).get("hooks") or {}).items():
        for g in groups or []:
            for h in (g or {}).get("hooks") or []:
                hooks.append(dict(scope=scope, event=event, matcher=g.get("matcher"), type=h.get("type"),
                                  command=redact(str(h.get("command") or h.get("prompt") or ""))[:200],
                                  injects_context=event in ("SessionStart", "UserPromptSubmit", "SubagentStart", "PostCompact")))
for sc, data in settings.items():
    collect_hooks(data, sc)
for info in plugins:
    if info["hooks"] and info["enabled"] is not False:
        entry = plugin_entry(info["key"])
        collect_hooks(load_json(os.path.join(entry.get("installPath", ""), "hooks", "hooks.json")), "plugin:" + info["key"])

# Hook scripts a settings hook runs: a missing one is an issue; an existing one (and a script it
# runs, one hop) is a source, since its deny and notice messages reach the agent when it fires.
SCRIPT = re.compile(r"[\w.${}~/-]*[\w-]\.(?:sh|py|js|mjs|ts|rb|php)\b")
def script_paths(text, base):
    found = []
    for m in SCRIPT.finditer(text or ""):
        t = m.group(0)
        if (m.start() and text[m.start() - 1] in "*?") or os.path.basename(t).startswith("."):
            continue  # a pattern (*.blade.php) or an extension, not a file
        t2 = os.path.expanduser(re.sub(r"\$\{?CLAUDE_PROJECT_DIR\}?", project, t))
        if "$" in t2 or "{" in t2 or t2.startswith("//"):
            continue  # another variable or a URL: not resolvable here
        found.append((t, os.path.normpath(t2 if os.path.isabs(t2) else os.path.join(base, t2))))
    return found

def ours(p, sc):
    if sc in ("project", "local"):  # the repo's own settings: the repo, nothing else
        return repo_controlled(p) and repo_controlled(os.path.realpath(p))
    return p.startswith((project + os.sep, config + os.sep))

for sc, p in settings_files:
    for event, groups in ((settings.get(sc) or {}).get("hooks") or {}).items():
        for g in groups or []:
            for h in (g or {}).get("hooks") or []:
                for t, full in script_paths(h.get("command"), project):
                    if sc in ("project", "local") and not ours(full, sc):
                        issues.append(dict(type="hook-script-outside", path=p, detail=f"{event} hook runs {t}, outside the repo; not read"))
                    elif not os.path.isfile(full):
                        issues.append(dict(type="hook-script-missing", path=p, detail=f"{event} hook runs {t}, which does not exist"))
                    elif ours(full, sc) and not known(full):
                        add(full, "hook-script", sc, "on-demand", f"{event} hook script: its messages reach the agent when the hook fires")
                        for _, sub in script_paths(read(full), os.path.dirname(full)):
                            if os.path.isfile(sub) and ours(sub, sc) and not known(sub):
                                add(sub, "hook-script", sc, "on-demand", f"run by {os.path.basename(full)} ({event} hook)")

perms = {}
for sc, data in settings.items():
    p = data.get("permissions") or {}
    perms[sc] = {k: [redact(str(x)) for x in p.get(k, [])] for k in ("allow", "deny", "ask") if p.get(k)}
config_out = dict(
    settings={sc: dict(keys=sorted(d.keys()), env_keys=sorted((d.get("env") or {}).keys()),
                       modified=datetime.datetime.fromtimestamp(os.path.getmtime(dict(settings_files)[sc]), datetime.timezone.utc).isoformat(timespec="seconds"))
              for sc, d in settings.items()},
    permissions=perms, claudeMdExcludes=excludes, auto_memory=dict(dir=mem_dir, disabled=mem_off),
    output_style=style, tool_search=env.get("ENABLE_TOOL_SEARCH", os.environ.get("ENABLE_TOOL_SEARCH")),
    plugins=plugins, mcp_servers=mcp, hooks=hooks)
json.dump(config_out, open(os.path.join(out, "config.json"), "w"), indent=1)

# ---- audit units ---------------------------------------------------------------------------------------
editable = {"claude-md", "claude-local", "rule", "agents-md", "import", "memory-index", "memory", "agent-memory", "output-style",
            "pointer-doc", "generator-source", "hook-script"}
declined = set()
if declined_path and os.path.isfile(declined_path):
    for line in open(declined_path, encoding="utf-8"):
        try:
            declined.add(json.loads(line)["fingerprint"])
        except (ValueError, KeyError):
            pass
# Files a past run audited: unchanged bytes and a recent enough audit keep their units out of the
# batches. The age bound matters because a doc goes stale when the code it describes changes.
audited_ok = {}
if audited_path and os.path.isfile(audited_path):
    cutoff = (datetime.date.today() - datetime.timedelta(days=audited_days)).isoformat()
    for line in open(audited_path, encoding="utf-8"):
        try:
            e = json.loads(line)
            if str(e.get("audited_on", "")) >= cutoff:
                audited_ok[e["path"]] = (e["audited_on"], e["sha256"])  # the ledger is in time order: last wins
        except (ValueError, KeyError, TypeError):
            pass
def audited_on(s):
    entry = audited_ok.get(s["real_path"]) or audited_ok.get(s["path"])
    if not entry:
        return None
    try:
        with open(s["real_path"], "rb") as fh:
            return entry[0] if hashlib.sha256(fh.read()).hexdigest() == entry[1] else None
    except OSError:
        return None
BULLET = re.compile(r"^(\s*)(?:[-*+]|\d+[.)])\s+")
units = []

def norm(t):
    return " ".join(re.findall(r"[a-z0-9]+", t.lower()))

MESSAGE = re.compile(r'"((?:[^"\\\n]|\\.){20,})"|\'([^\'\n]{20,})\'')

def emit(s, start, end, heading, kind, text):
    text = text.strip("\n")
    if not text.strip():
        return
    fp = hashlib.sha1((s["path"] + "\0" + norm(text)).encode()).hexdigest()[:12]
    if "audited_on" not in s:
        s["audited_on"] = audited_on(s)
    units.append(dict(id=f"u{len(units) + 1:04d}", path=s["path"], line=start, end_line=end, heading=heading,
                      kind=kind, scope=s["scope"], text=redact(text),
                      activation="never" if s.get("window_lines") is not None and start > s["window_lines"] else s["activation"],
                      fingerprint=fp, declined=fp in declined, audited=bool(s["audited_on"])))

for p, s in sources.items():
    if s["kind"] not in in_scope:
        continue
    if blocked(s["path"], p):
        issues.append(dict(type="source-outside-roots", path=s["path"], detail=f"resolves to {p}, outside the repo; not read"))
        continue
    if SENSITIVE.search(p) or SENSITIVE.search(s["path"]):
        issues.append(dict(type="sensitive-file-skipped", path=s["path"], detail="looks like a secrets file; its text is never put into units"))
        continue
    if s["path"] != p and s["kind"] not in ("hook-script", "generator-source") and not p.endswith(".md"):
        issues.append(dict(type="symlink-to-non-markdown", path=s["path"], detail=f"links to {p}, which is not markdown; not read"))
        continue
    # A generated file is audited through its source (a Boost file keeps its handwritten lines
    # outside the generated block); an unchanged upstream copy, upstream.
    if (s.get("generated_from") and not s.get("boost_block")) or (s.get("upstream") and not s.get("upstream_drift")):
        continue
    if s["kind"] == "hook-script":
        for n, line in enumerate((read(p) or "").splitlines(), 1):
            for m in MESSAGE.finditer(line):
                msg = m.group(1) or m.group(2)
                if len(msg.split()) >= 4 and not msg.lstrip().startswith(("$(", "//")):  # prose, not shell
                    emit(s, n, n, os.path.basename(p), "message", msg)
        continue
    if s["kind"] in ("skill", "agent", "command"):
        if s.get("plugin"):
            continue
        fm = frontmatter(read(p))
        desc = fm_value(fm, "description")
        if desc and s.get("listing_chars"):  # only a description that is actually listed
            line = next((n for n, l in enumerate((read(p) or "").splitlines(), 1) if l.startswith("description:")), 1)
            emit(s, line, line, s.get("name", ""), "description", desc)
        if s["activation"] == "never" or s.get("third_party"):
            continue
        # A user or project skill's body loads when it runs, and an agent's body is its system
        # prompt: both are audited line by line below.
    # Line-level audit only where lines reach a context: a file that never loads, or a
    # subagent's on-demand notes, is judged whole from the inventory. Auto-memory topic files,
    # AGENTS.md, pointer docs, and generator sources are audited anyway: the user's memory, a file
    # often meant to load, docs the agent is told to open, and the text of a generated file.
    elif s["kind"] not in editable or (s["activation"] in ("never", "on-demand", "config")
                                       and s["kind"] not in ("memory", "agents-md", "pointer-doc", "generator-source")):
        continue
    lines = (read(p) or "").splitlines()
    i, heading = 0, ""
    if lines and lines[0] == "---" and "---" in lines[1:]:
        i = lines.index("---", 1) + 1
    if s.get("boost_block"):  # Boost rewrites its block; the lines around it are the user's
        in_block = False
        for k, l in enumerate(lines):
            if "<laravel-boost-guidelines>" in l:
                in_block = True
            if in_block:
                lines[k] = ""
            if "</laravel-boost-guidelines>" in l:
                in_block = False
    cur, cur_start, cur_kind = [], 0, ""
    def flush(end):
        global cur
        if cur:
            emit(s, cur_start, end, heading, cur_kind, "\n".join(cur))
        cur = []
    while i < len(lines):
        line, n = lines[i], i + 1
        fm_ = re.match(r"\s*(`{3,}|~{3,})", line)
        if fm_:
            flush(n - 1)
            fence, start, block = fm_.group(1), n, [line]
            close = re.compile(r"\s*" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*$")
            i += 1
            while i < len(lines):
                block.append(lines[i])
                if close.match(lines[i]):
                    break
                i += 1
            emit(s, start, i + 1, heading, "code", "\n".join(block))
            i += 1
            continue
        if re.match(r"^#{1,6}\s", line):
            flush(n - 1)
            heading = line.lstrip("#").strip()
        elif not line.strip():
            flush(n - 1)
        elif line.lstrip().startswith("|"):
            if cur_kind != "table":
                flush(n - 1)
                cur_start, cur_kind = n, "table"
            cur.append(line)
        elif BULLET.match(line):
            flush(n - 1)
            cur, cur_start, cur_kind = [line], n, "bullet"
        else:
            if not cur:
                cur_start, cur_kind = n, "paragraph"
            cur.append(line)
        i += 1
    flush(len(lines))

with open(os.path.join(out, "units.jsonl"), "w") as fh:
    for u in units:
        fh.write(json.dumps(u) + "\n")

# ---- near-duplicates -------------------------------------------------------------------------------------
STOP = set("a an and are as at be by for from if in into is it its of on or that the this to with when you your not no do does use".split())
words = []
for u in units:
    w = set(norm(u["text"]).split()) - STOP
    words.append(w if len(w) >= 6 and u["kind"] != "code" and not u["declined"] else None)
dupes = []
for a in range(len(units)):
    if words[a] is None:
        continue
    for b in range(a + 1, len(units)):
        if words[b] is None:
            continue
        inter = len(words[a] & words[b])
        if not inter:
            continue
        score = inter / len(words[a] | words[b])
        if score >= 0.6:
            dupes.append(dict(a=units[a]["id"], b=units[b]["id"], score=round(score, 2),
                              cross_file=units[a]["path"] != units[b]["path"]))
dupes.sort(key=lambda d: -d["score"])
with open(os.path.join(out, "dupes.jsonl"), "w") as fh:
    for d in dupes[:400]:
        fh.write(json.dumps(d) + "\n")

# ---- batches: whole sources together where they fit ------------------------------------------------------------
by_path = {}
for u in units:
    if not u["declined"] and not u["audited"]:
        by_path.setdefault(u["path"], []).append(u)

def make_batches(size):
    batches, current = [], []
    for us in by_path.values():
        while us:
            if len(us) > size - len(current) and current and len(us) <= size:
                batches.append(current)
                current = []
                continue
            take, us = us[:size - len(current)], us[size - len(current):]
            current += take
            if len(current) >= size:
                batches.append(current)
                current = []
    return batches + ([current] if current else [])

# Whole sources stay together, which can leave batches part-full: grow the size until they fit.
batch_size = max(batch_size, math.ceil(sum(len(us) for us in by_path.values()) / max(max_batches, 1)))
batches = make_batches(batch_size)
while len(batches) > max(max_batches, 1):
    batch_size = math.ceil(batch_size * 1.1)
    batches = make_batches(batch_size)
paths = []
for k, b in enumerate(batches, 1):
    bp = os.path.join(out, f"batch_{k}.jsonl")
    with open(bp, "w") as fh:
        for u in b:
            fh.write(json.dumps(u) + "\n")
    paths.append(bp)

# ---- totals ----------------------------------------------------------------------------------------------------
def total(pred, field="approx_tokens"):
    return sum(s.get(field, 0) for s in sources.values() if pred(s))
always = sum(tok(s.get("loaded_bytes", s["bytes"])) for s in sources.values() if s["activation"] == "always")
totals = dict(
    sources=len(sources),
    by_activation={a: sum(1 for s in sources.values() if s["activation"] == a) for a in RANK if any(s["activation"] == a for s in sources.values())},
    always_tokens=always,
    listing_tokens=tok(total(lambda s: s["activation"] == "listing", "listing_chars")),
    listing_tokens_own=tok(total(lambda s: s["activation"] == "listing" and not s.get("plugin"), "listing_chars")),
    lazy_tokens=total(lambda s: s["activation"] == "lazy"),
    agent_memory_tokens=total(lambda s: s["activation"] == "agent"),
    never_loaded_tokens=total(lambda s: s["activation"] == "never" and s["kind"] != "settings"),
    editable_stored_tokens=total(lambda s: s["kind"] in editable),
    units=len(units), declined_units=sum(u["declined"] for u in units), dupe_pairs=len(dupes),
    audited_units=sum(u["audited"] and not u["declined"] for u in units),
    batched_units=sum(len(b) for b in batches), batch_size=batch_size,
    third_party_skills=sum(1 for s in sources.values() if s.get("third_party")),
    third_party_body_tokens=total(lambda s: bool(s.get("third_party")) and s["activation"] != "never"),
    shadowed_skills=sum(1 for s in sources.values() if s.get("shadowed_by")),
    mcp_servers=len(mcp), hooks=len(hooks), plugins_enabled=sum(1 for p in plugins if p["enabled"]))

# Issues get a fingerprint too, so a declined one stays quiet on later runs. Every string field is
# redacted here, the one place issues leave the script, before the fingerprint is taken.
for it in issues:
    it.update({k: redact(v) for k, v in it.items() if isinstance(v, str)})
    it["fingerprint"] = hashlib.sha1((it["type"] + "\0" + it.get("path", "") + "\0" + it["detail"]).encode()).hexdigest()[:12]
    it["declined"] = it["fingerprint"] in declined
inv = dict(project=project, repo_root=repo_root, config_dir=config, memory_dir=mem_dir,
           sources=sorted(sources.values(), key=lambda s: (RANK.index(s["activation"]), s["path"])),
           issues=issues, totals=totals)
json.dump(inv, open(os.path.join(out, "inventory.json"), "w"), indent=1)
print(json.dumps(dict(out=out, totals=totals, issues=len(issues), batches=paths)))
PY
