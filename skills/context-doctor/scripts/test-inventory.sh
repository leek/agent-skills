#!/bin/bash
# Offline test for inventory.sh: a fixture home, profile config dir, and git project, never the
# real ones. Checks activation per loading rule, imports, memory index checks, redaction,
# near-duplicates, and the declined ledger.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"; config="$home/.claude-profiles/p"; proj="$home/code/app"; out="$tmp/out"
mkdir -p "$config/skills/foo" "$proj/docs" "$proj/sub" "$proj/legacy" "$proj/.claude/rules" "$tmp/managed" "$home/.claude"
git -C "$proj" init -q
proj_real=$(cd "$proj" && pwd -P)
slug=$(printf '%s' "$proj_real" | sed 's/[^A-Za-z0-9]/-/g')
mem="$config/projects/$slug/memory"; mkdir -p "$mem"

dup="- Run the whole test suite with composer test before every commit to the main branch."
printf '# Global\n\n%s\n- Ask before any destructive data operation such as drop or truncate.\n' "$dup" > "$config/CLAUDE.md"
echo "- stale default profile rule" > "$home/.claude/CLAUDE.md"
cat > "$config/settings.json" <<JSON
{"env": {"API_TOKEN": "sk-ant-abcdefghijklmnopqrstuvwxyz0123"},
 "claudeMdExcludes": ["$proj_real/legacy/**"],
 "skillOverrides": {"hidden": "off", "terse": "name-only"},
 "enabledPlugins": {"mk@market": true},
 "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo token=supersecretvalue123"}]}]}}
JSON
# A plugin whose install holds a whole marketplace repo: only its declared skill is its own.
plug="$tmp/plug"; mkdir -p "$plug/.claude-plugin" "$plug/skills/one" "$plug/skills/two" "$config/plugins"
echo '{"plugins": [{"name": "mk", "source": "./", "skills": ["./skills/one"]}]}' > "$plug/.claude-plugin/marketplace.json"
printf -- '---\nname: one\ndescription: The plugin skill.\n---\n' > "$plug/skills/one/SKILL.md"
printf -- '---\nname: two\ndescription: Another plugin skill in the same repo.\n---\n' > "$plug/skills/two/SKILL.md"
echo "{\"version\": 2, \"plugins\": {\"mk@market\": [{\"installPath\": \"$plug\"}]}}" > "$config/plugins/installed_plugins.json"
for n in hidden terse; do mkdir -p "$config/skills/$n"; printf -- '---\nname: %s\ndescription: A skill the overrides trim.\n---\n' "$n" > "$config/skills/$n/SKILL.md"; done
mkdir -p "$config/output-styles"; printf -- '- Unselected style line one.\n- Line two.\n' > "$config/output-styles/unused.md"
# Hostile repo: an import and a symlinked rule reaching outside, and a project setting that
# tries to move the memory dir. None of their text may reach the output.
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nOUTSIDEKEYMATERIAL\n-----END OPENSSH PRIVATE KEY-----\n' > "$tmp/outside-key"
ln -s "$tmp/outside-key" "$proj/.claude/rules/linked.md"
echo "{\"autoMemoryDirectory\": \"$tmp\"}" > "$proj/.claude/settings.json"
echo "{\"autoMemoryDirectory\": \"$tmp\"}" > "$proj/.claude/settings.local.json"
mkdir -p "$config/notes"; echo "- USERCONFIGPRIVATE note" > "$config/notes/private.md"
cat > "$proj/CLAUDE.md" <<'MD'
See [AGENTS.md](./AGENTS.md).

@docs/agent-rules.md
@missing.md
@../../../outside-key
@../../.claude-profiles/p/notes/private.md
Mention `@notimport.md` in a span, and email me@example.com.

- Run the whole test suite using composer test before every commit to the main branch.
MD
echo "# Agents" > "$proj/AGENTS.md"
echo "- Imported rule." > "$proj/docs/agent-rules.md"
echo "- Sub rule." > "$proj/sub/CLAUDE.md"
echo "- Legacy rule." > "$proj/legacy/CLAUDE.md"
printf -- '---\npaths:\n  - "app/**/*.php"\n---\n- PHP rule.\n' > "$proj/.claude/rules/php.md"
echo "- Always rule." > "$proj/.claude/rules/always.md"
echo "cursor rule" > "$proj/.cursorrules"
printf -- '- [A](a.md) — a\n- [Gone](gone.md) — gone\n' > "$mem/MEMORY.md"
echo "a" > "$mem/a.md"; echo "orphan" > "$mem/orphan.md"
printf -- '---\nname: foo\ndescription: Does foo things when asked.\n---\nBody.\n' > "$config/skills/foo/SKILL.md"

run() { bash "$here/inventory.sh" --out "$out" --project "$proj" --home "$home" --config-dir "$config" --managed-dir "$tmp/managed" "$@" 2>/dev/null; }
run > "$tmp/summary.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
act() { jq -r --arg p "$1" '.sources[] | select(.path==$p) | .activation' "$out/inventory.json"; }
expect() { [ "$(act "$1")" = "$2" ] || fail "$1: expected $2, got '$(act "$1")'"; }

expect "$config/CLAUDE.md" always
expect "$home/.claude/CLAUDE.md" never
expect "$proj_real/CLAUDE.md" always
expect "$proj_real/docs/agent-rules.md" always
expect "$proj_real/AGENTS.md" never
expect "$proj_real/sub/CLAUDE.md" lazy
expect "$proj_real/legacy/CLAUDE.md" never
expect "$proj_real/.claude/rules/php.md" lazy
expect "$proj_real/.claude/rules/always.md" always
expect "$proj_real/.cursorrules" never
expect "$mem/MEMORY.md" always
expect "$mem/a.md" on-demand
expect "$config/skills/foo/SKILL.md" listing

types=$(jq -r '[.issues[].type] | sort | unique | join(" ")' "$out/inventory.json")
for t in link-not-import import-unresolved memory-pointer-broken memory-orphan; do
  case " $types " in *" $t "*) ;; *) fail "missing issue $t (got: $types)" ;; esac
done
jq -e '[.issues[] | select(.detail | test("notimport|example.com"))] | length == 0' "$out/inventory.json" >/dev/null \
  || fail "a code span or an email was treated as an import"

! grep -rq -e 'abcdefghijklmnopqrstuvwxyz0123' -e 'supersecretvalue123' "$out" || fail "a secret value reached the output"
jq -e '.settings.user.env_keys == ["API_TOKEN"]' "$out/config.json" >/dev/null || fail "env key names missing from config.json"

jq -e 'select(.cross_file)' "$out/dupes.jsonl" >/dev/null || fail "cross-file near-duplicate not found"
jq -e 'select(.kind=="description" and .text=="Does foo things when asked.")' "$out/units.jsonl" >/dev/null || fail "skill description unit missing"

# Declined: a ledger fingerprint marks its unit declined and keeps it out of every batch.
fp=$(jq -r 'select(.text | test("Imported rule")) | .fingerprint' "$out/units.jsonl")
[ -n "$fp" ] || fail "imported file produced no unit"
echo "{\"fingerprint\":\"$fp\"}" > "$tmp/declined.jsonl"
run --declined "$tmp/declined.jsonl" > /dev/null
jq -e --arg f "$fp" 'select(.fingerprint==$f) | .declined' "$out/units.jsonl" >/dev/null || fail "declined unit not marked"
! cat "$out"/batch_*.jsonl | grep -q "$fp" || fail "declined unit still batched"

# Nothing outside the trusted roots is read into units, and project settings cannot move memory.
! grep -rq 'OUTSIDEKEYMATERIAL' "$out" || fail "text from outside the trusted roots reached the output"
! grep -rq 'USERCONFIGPRIVATE' "$out" || fail "a repo import pulled a user config file into the output"
jq -e '[.issues[] | select(.type=="import-outside-roots" and (.detail | test("notes/private.md")))] | length == 1' "$out/inventory.json" >/dev/null || fail "repo import of the config dir not blocked"
for t in import-outside-roots source-outside-roots; do
  jq -e --arg t "$t" '[.issues[] | select(.type==$t)] | length > 0' "$out/inventory.json" >/dev/null || fail "missing issue $t"
done
[ "$(jq -r .memory_dir "$out/inventory.json")" = "$mem" ] || fail "project settings moved the memory dir"

# skillOverrides, plugin manifests, usage keys, and never-loaded files.
expect "$config/skills/hidden/SKILL.md" never
expect "$config/skills/terse/SKILL.md" listing
jq -e --arg p "$config/skills/terse/SKILL.md" '.sources[] | select(.path==$p) | .listing_chars == 0' "$out/inventory.json" >/dev/null || fail "name-only skill still counts its description"
expect "$plug/skills/one/SKILL.md" listing
[ -z "$(act "$plug/skills/two/SKILL.md")" ] || fail "an undeclared skill in the plugin's repo was counted"
jq -e --arg p "$plug/skills/one/SKILL.md" '.sources[] | select(.path==$p) | .usage_key == "mk:one"' "$out/inventory.json" >/dev/null || fail "plugin usage_key"
! grep -q -e 'unused.md' -e 'hidden/SKILL.md' "$out/units.jsonl" || fail "units written for a file that never loads"

# --scope narrows units, never the inventory.
run --scope memory > /dev/null
[ -s "$out/units.jsonl" ] || fail "scope memory wrote no units"
! jq -r .path "$out/units.jsonl" | grep -vq "/memory/" || fail "scope memory wrote units outside memory"
expect "$config/CLAUDE.md" always
! run --scope bogus > /dev/null 2>&1 || fail "an unknown scope was accepted"

# A profile CLAUDE.md symlinked to the default one is one always-loaded source, not two.
config2="$home/.claude-profiles/q"; mkdir -p "$config2"
ln -s "$home/.claude/CLAUDE.md" "$config2/CLAUDE.md"
bash "$here/inventory.sh" --out "$out" --project "$proj" --home "$home" --config-dir "$config2" --managed-dir "$tmp/managed" >/dev/null 2>&1
expect "$config2/CLAUDE.md" always
[ -z "$(act "$home/.claude/CLAUDE.md")" ] || fail "the symlinked CLAUDE.md was counted twice"

# A second project: pointer docs, a generated root file, upstream copies, skill and agent bodies,
# hook scripts, and the mechanical checks on globs, links, settings, and subagent memory.
p3="$home/code/three"; up="$tmp/upstream"
mkdir -p "$p3/docs" "$p3/src" "$p3/sub2" "$p3/sub3" "$p3/.ai/guidelines" "$p3/.claude/rules" "$p3/.claude/skills/mine" \
  "$p3/.claude/agents" "$p3/.claude/hooks" "$p3/.agents/skills/lonely" "$p3/.claude/agent-memory/rev" "$up/sub2" "$up/sub3"
git -C "$p3" init -q
p3r=$(cd "$p3" && pwd -P)
printf '<laravel-boost-guidelines>\nRead docs/index.md and `docs/guide.md`; see [gone](docs/missing.md).\n</laravel-boost-guidelines>\n' > "$p3/CLAUDE.md"
echo '{"skills": ["boosted"]}' > "$p3/boost.json"
# Third-party skills: a Boost-installed project skill and an npx-skills-locked user skill keep their
# listed description as a unit, never their body. A project copy of a user skill's name is shadowed.
mkdir -p "$p3/.claude/skills/boosted" "$config/skills/locked" "$home/.agents" "$p3/.claude/skills/foo"
printf -- '---\nname: boosted\ndescription: Boost installs me.\n---\n- BOOSTBODY rule.\n' > "$p3/.claude/skills/boosted/SKILL.md"
printf -- '---\nname: locked\ndescription: A lock installs me.\n---\n- LOCKBODY rule.\n' > "$config/skills/locked/SKILL.md"
echo '{"version": 3, "skills": {"locked": {"source": "x/y"}}}' > "$home/.agents/.skill-lock.json"
printf -- '---\nname: foo\ndescription: Project copy of foo.\n---\n- SHADOWBODY rule.\n' > "$p3/.claude/skills/foo/SKILL.md"
echo "- Guideline source rule." > "$p3/.ai/guidelines/core.md"
printf '| Applies to | Rule |\n|---|---|\n| app/Nope/**, src/*.php | docs/guide.md |\n| a form (`*Form`, `*Infolist`) | `docs/guide.md` |\n' > "$p3/docs/index.md"
echo "- The rule pack's own root file." > "$up/CLAUDE.md"
echo "- Guide rule; deeper notes in docs/deep.md." > "$p3/docs/guide.md"
echo "- Deep rule; more in docs/deeper.md." > "$p3/docs/deep.md"
echo "- Deeper rule." > "$p3/docs/deeper.md"
echo "<?php" > "$p3/src/a.php"
printf -- '---\npaths:\n  - "nowhere/**"\n---\n- Rule that never loads.\n' > "$p3/.claude/rules/dead.md"
echo "- Same text in two places." > "$p3/.claude/rules/copy.md"; cp "$p3/.claude/rules/copy.md" "$p3/sub3/CLAUDE.local.md"
echo "- Synced rule." > "$p3/sub2/CLAUDE.md"; cp "$p3/sub2/CLAUDE.md" "$up/sub2/CLAUDE.md"
echo "- Local edit." > "$p3/sub3/CLAUDE.md"; echo "- Upstream text." > "$up/sub3/CLAUDE.md"
printf -- '---\nname: mine\ndescription: A project skill.\n---\n- Skill body rule.\n' > "$p3/.claude/skills/mine/SKILL.md"
ln -s ../../.agents/skills/gone "$p3/.claude/skills/broken"
printf -- '---\nname: lonely\ndescription: Only other harnesses see me.\n---\n' > "$p3/.agents/skills/lonely/SKILL.md"
printf -- '---\nname: rev\ndescription: Reviews.\nmemory: project\n---\n- Agent prompt rule.\n' > "$p3/.claude/agents/rev.md"
printf -- '- [A](a.md)\n- [A again](a.md)\n' > "$p3/.claude/agent-memory/rev/MEMORY.md"
printf -- '---\nname: same\n---\n' > "$p3/.claude/agent-memory/rev/a.md"; cp "$p3/.claude/agent-memory/rev/a.md" "$p3/.claude/agent-memory/rev/b.md"
printf '#!/bin/bash\necho "BLOCKED: this deny message is long enough to become a unit." >&2\n' > "$p3/.claude/hooks/guard.sh"
cat > "$p3/.claude/settings.json" <<'JSON'
{"disabledMcpjsonServers": ["ghost"],
 "permissions": {"allow": ["mcp__plugin_nothere_srv__*", "mcp__plugin_nothere_srv__get(Authorization: Bearer ghp_ISSUETOKEN0123456789abcdef)"]},
 "hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh\""},
                                     {"type": "command", "command": "case \"$f\" in *.blade.php) true ;; esac"}]}],
           "SessionStart": [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gone.sh\""}]}]}}
JSON
bash "$here/inventory.sh" --out "$out" --project "$p3" --home "$home" --config-dir "$config" --managed-dir "$tmp/managed" --upstream "$up" >/dev/null 2>&1 \
  || fail "inventory failed on the second project"

kind() { jq -r --arg p "$1" '.sources[] | select(.path==$p) | .kind' "$out/inventory.json"; }
[ "$(kind "$p3r/docs/guide.md")" = pointer-doc ] || fail "a backticked doc path is not a pointer-doc"
[ "$(kind "$p3r/docs/deep.md")" = pointer-doc ] || fail "a second-hop doc is not a pointer-doc"
[ -z "$(kind "$p3r/docs/deeper.md")" ] || fail "a third-hop doc was followed"
[ "$(kind "$p3r/.ai/guidelines/core.md")" = generator-source ] || fail "boost guideline source not found"
[ "$(kind "$p3r/.claude/hooks/guard.sh")" = hook-script ] || fail "hook script not a source"
has_issue() { jq -e --arg t "$1" --arg d "$2" '[.issues[] | select(.type==$t and (.detail | contains($d)))] | length > 0' "$out/inventory.json" >/dev/null || fail "missing $1 ($2)"; }
has_issue generated-file "boost:update"
has_issue pointer-unresolved "docs/missing.md"
has_issue glob-unmatched "app/Nope/**"
has_issue glob-unmatched "nowhere/**"
has_issue identical-files "sub3/CLAUDE.local.md"
has_issue upstream-drift "sub3/CLAUDE.md"
has_issue skill-link-broken "gone"
has_issue skill-unlinked "lonely"
has_issue mcp-setting-dead "ghost"
has_issue permission-dead "nothere"
has_issue hook-script-missing "gone.sh"
has_issue memory-index-duplicate-row "a.md"
has_issue memory-name-duplicate '"same"'
# Every issue detail is redacted, not only the fields that call redact() by hand.
! grep -rq 'ISSUETOKEN' "$out" || fail "a token in an issue detail reached the output"
none() { jq -e --arg t "$1" --arg d "$2" '[.issues[] | select(.type==$t and (.detail | contains($d)))] | length == 0' "$out/inventory.json" >/dev/null || fail "false $1 ($2)"; }
none glob-unmatched "src/*.php"            # matches src/a.php
none glob-unmatched "Infolist"             # a prose table row, not an index row
none hook-script-missing ".blade.php"      # a case pattern, not a script
jq -e --arg p "$p3r/CLAUDE.md" '[.issues[] | select(.type=="upstream-drift" and .path==$p)] | length == 0' "$out/inventory.json" >/dev/null \
  || fail "a generated file was compared with the upstream checkout's own root file"
unit() { grep -q -- "$1" "$out/units.jsonl" || fail "no unit for: $1"; }
nounit() { ! grep -q -- "$1" "$out/units.jsonl" || fail "unexpected unit: $1"; }
unit "Guide rule"; unit "Guideline source rule"; unit "Skill body rule"; unit "Agent prompt rule"
unit "deny message is long enough"; unit "Local edit"
nounit "laravel-boost-guidelines"; nounit "Synced rule"
unit "Boost installs me"; unit "A lock installs me"; nounit "BOOSTBODY"; nounit "LOCKBODY"; nounit "SHADOWBODY"
expect "$p3r/.claude/skills/foo/SKILL.md" never
jq -e '.totals.third_party_skills == 2 and .totals.shadowed_skills == 1' "$out/inventory.json" >/dev/null || fail "third-party or shadowed totals"

# An audited, unchanged file keeps its units out of the batches; an old audit or a changed file does not.
guide="$p3r/docs/guide.md"
today=$(date -u +%Y-%m-%d)
echo "{\"path\":\"$guide\",\"sha256\":\"$(shasum -a 256 "$guide" | cut -d' ' -f1)\",\"audited_on\":\"$today\"}" > "$tmp/audited.jsonl"
inv3() { bash "$here/inventory.sh" --out "$out" --project "$p3" --home "$home" --config-dir "$config" --managed-dir "$tmp/managed" --upstream "$up" "$@" >/dev/null 2>&1; }
inv3 --audited "$tmp/audited.jsonl"
jq -e 'select(.text | test("Guide rule")) | .audited' "$out/units.jsonl" >/dev/null || fail "audited unit not marked"
! cat "$out"/batch_*.jsonl | grep -q "Guide rule" || fail "audited unit still batched"
sed 's/"audited_on":"[0-9-]*"/"audited_on":"2000-01-01"/' "$tmp/audited.jsonl" > "$tmp/audited-old.jsonl"
inv3 --audited "$tmp/audited-old.jsonl"
cat "$out"/batch_*.jsonl | grep -q "Guide rule" || fail "an audit past --audited-days still skipped the file"
echo "- Guide rule changed." > "$guide"
inv3 --audited "$tmp/audited.jsonl"
cat "$out"/batch_*.jsonl | grep -q "Guide rule changed" || fail "a changed audited file was skipped"

# --max-batches raises the batch size instead of writing more batches.
for n in 1 2 3; do
  inv3 --max-batches "$n" --batch-size 1
  [ "$(ls "$out"/batch_*.jsonl | wc -l | tr -d ' ')" -le "$n" ] || fail "--max-batches $n wrote more than $n batches"
done

# A fourth project for the panel-review fixes: redaction forms, brace globs, symlinks out of the
# repo, a gitignored CLAUDE.local.md, the profile's own .claude.json, MCP URL credentials, the
# memory window, repo hooks reaching the config dir, output-style precedence, agent-memory names,
# Boost's handwritten lines, package names that are not imports, when_to_use, command bodies,
# secrets files, and nested code fences.
p4="$home/code/four"
mkdir -p "$p4/src" "$p4/sub" "$p4/.ai/guidelines" "$p4/.claude/rules" "$p4/.claude/agents" "$p4/.claude/hooks" "$p4/.claude/output-styles" \
  "$config/output-styles" "$config/agents" "$config/agent-memory/reviewer" "$config/commands" "$config/skills/wtu"
git -C "$p4" init -q
p4r=$(cd "$p4" && pwd -P)
mem4="$config/projects/$(printf '%s' "$p4r" | sed 's/[^A-Za-z0-9]/-/g')/memory"; mkdir -p "$mem4"
cat > "$p4/CLAUDE.md" <<'MD'
- HANDWRITTEN rule outside the generated block.
<laravel-boost-guidelines>
- BOOSTGENERATED line.
</laravel-boost-guidelines>
Install @types/node first.
@.env
@.env.copy
@.envrc
MD
# A secrets file is never read: not for its size, its @ imports, or the identical-files hash.
echo "PLAINENVVALUE=hello @leaky/ENVIMPORTVALUE_42.md" > "$p4/.env"; cp "$p4/.env" "$p4/.env.copy"
echo "export DIRENVVALUE=hello" > "$p4/.envrc"
cat > "$p4/.claude/rules/secrets.md" <<'MD'
- Export GITHUB_TOKEN=ghxsecretvalue123456 before running.
- Send Authorization: Bearer bearervalue12345678 to the API.
- The database is postgres://admin:hunter2passw@db.internal/app.
- Context budget: tokens: 1200 per turn.
- Staging login password: hunt7r2 for now.
- Config has "client_secret": "sh,ort}x" in it.
- Broken quote: password: "unterm1natedpw
- Bracketed: secret: [br4cketval]
MD
printf -- '- Long: api_key="%s"\n' "LONGSECRET$(printf 'y%.0s' $(seq 1 5000))" >> "$p4/.claude/rules/secrets.md"
printf -- '---\npaths: src/**/*.{ts,tsx}\n---\n- TSX rule.\n' > "$p4/.claude/rules/tsx.md"
echo "x" > "$p4/src/a.tsx"
printf -- '````md\n```\ninner\n```\n````\n- AFTERFENCE rule.\n' > "$p4/.claude/rules/fence.md"
printf -- '---\nname: OUTSIDEAGENTNAME\ndescription: Lives outside the repo.\n---\n' > "$tmp/outside-agent.md"
ln -s "$tmp/outside-agent.md" "$p4/.claude/agents/evil.md"
printf 'CLAUDE.local.md\nwt/\n' > "$p4/.gitignore"; echo "- Ignored local rule." > "$p4/sub/CLAUDE.local.md"
mkdir -p "$p4/wt/nested"; git -C "$p4/wt/nested" init -q  # an ignored nested repo, as a worktree is
echo '{"mcpServers": {"homeonly": {"command": "x"}}}' > "$home/.claude.json"
echo '{"mcpServers": {"api": {"type": "http", "url": "https://abcdefghijklmnopqrstu@api.example.com/mcp"}}}' > "$p4/.mcp.json"
{ echo "- [A](a.md) — a"; for i in $(seq 1 210); do echo "- filler line $i"; done; } > "$mem4/MEMORY.md"; echo "a" > "$mem4/a.md"
echo 'echo "USERHOOKSECRET message is long enough to be a unit"' > "$config/notes/user_hook.sh"
printf '#!/bin/bash\necho "Use pnpm here, not npm." >&2\n' > "$p4/.claude/hooks/guard.sh"
echo "- Project dup style." > "$p4/.claude/output-styles/dup.md"; echo "- User dup style." > "$config/output-styles/dup.md"
printf -- '---\nname: pr-reviewer\ndescription: Reviews.\n---\n' > "$config/agents/pr-reviewer.md"
echo "- reviewer note" > "$config/agent-memory/reviewer/MEMORY.md"
printf -- '---\ndescription: A command.\n---\n- COMMANDBODY line.\n' > "$config/commands/cmd.md"
printf -- '---\nname: wtu\ndescription: Short.\nwhen_to_use: When the user asks.\n---\n' > "$config/skills/wtu/SKILL.md"
cat > "$p4/.claude/settings.json" <<JSON
{"outputStyle": "dup", "skillOverrides": {"projonly": "off"},
 "hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh\""},
                                     {"type": "command", "command": "bash $config/notes/user_hook.sh"}]}]}}
JSON
bash "$here/inventory.sh" --out "$out" --project "$p4" --home "$home" --config-dir "$config" --managed-dir "$tmp/managed" >/dev/null 2>&1 \
  || fail "inventory failed on the fourth project"

! grep -rq -e 'ghxsecretvalue123456' -e 'bearervalue12345678' -e 'hunter2passw' -e 'abcdefghijklmnopqrstu' -e 'hunt7r2' -e 'sh,ort' -e 'unterm1natedpw' -e 'br4cketval' -e 'LONGSECRET' -e 'yyyyyyyyyy' "$out" || fail "a secret form survived redaction"
grep -q 'GITHUB_TOKEN=\[REDACTED\]' "$out/units.jsonl" || fail "redaction dropped the key name"
grep -q 'tokens: 1200' "$out/units.jsonl" || fail "redaction ate a short count"
jq -e '.mcp_servers[] | select(.name=="api") | .host == "api.example.com"' "$out/config.json" >/dev/null || fail "MCP host kept its userinfo"
jq -e '[.mcp_servers[] | select(.name=="homeonly")] | length == 0' "$out/config.json" >/dev/null || fail "a profile read ~/.claude.json"
none glob-unmatched "tsx"
! grep -rq 'OUTSIDEAGENTNAME' "$out" || fail "a symlinked agent outside the repo was read"
expect "$p4r/sub/CLAUDE.local.md" lazy
jq -e '[.sources[] | select(.kind=="claude-local" and (.path | endswith("CLAUDE.local.md") | not))] | length == 0' "$out/inventory.json" >/dev/null \
  || fail "an ignored directory was listed as a CLAUDE.local.md"
jq -e 'select(.text | test("filler line 205")) | .activation == "never"' "$out/units.jsonl" >/dev/null || fail "a MEMORY.md line past the window is not marked never"
jq -e 'select(.text | test("filler line 5$")) | .activation == "always"' "$out/units.jsonl" >/dev/null || fail "a MEMORY.md line inside the window is not always"
! grep -rq 'USERHOOKSECRET' "$out" || fail "a repo hook pulled a user config script into the output"
has_issue hook-script-outside "user_hook.sh"
unit "Use pnpm here, not npm."
expect "$p4r/.claude/output-styles/dup.md" always
expect "$config/output-styles/dup.md" never
has_issue agent-memory-orphan "reviewer"
unit "HANDWRITTEN rule"; nounit "BOOSTGENERATED"
jq -e '[.issues[] | select(.detail | test("types/node"))] | length == 0' "$out/inventory.json" >/dev/null || fail "@types/node treated as an import"
jq -e --arg p "$config/skills/wtu/SKILL.md" '.sources[] | select(.path==$p) | .listing_chars == ("Short. When the user asks." | length)' "$out/inventory.json" >/dev/null \
  || fail "when_to_use not counted in the listing size"
jq -e --arg p "$p4r/.claude/settings.json" '[.issues[] | select(.type=="skill-override-dead" and (.detail | contains("projonly")) and .path==$p)] | length == 1' "$out/inventory.json" >/dev/null \
  || fail "skill-override-dead blamed the wrong settings file"
unit "COMMANDBODY"
! grep -rq 'PLAINENVVALUE' "$out" || fail "an imported .env reached the output"
! grep -rq 'DIRENVVALUE' "$out" || fail "an imported .envrc reached the output"
has_issue sensitive-file-skipped "secrets file"
! grep -rq 'ENVIMPORTVALUE' "$out" || fail "an imported .env was walked for @ imports"
none identical-files ".env.copy"
jq -e --arg p "$p4r/.env" '.sources[] | select(.path==$p) | .bytes == 0' "$out/inventory.json" >/dev/null || fail "an imported .env was read for its size"
jq -e 'select(.kind=="bullet" and .text=="- AFTERFENCE rule.")' "$out/units.jsonl" >/dev/null || fail "text after a nested fence lost"
! jq -e 'select(.kind=="paragraph" and .text=="inner")' "$out/units.jsonl" >/dev/null || fail "a nested fence closed early"

# An excluded CLAUDE.md does not load, so it does not shadow AGENTS.md; ** matches any depth.
p5="$home/code/five"; mkdir -p "$p5/.claude"; git -C "$p5" init -q; p5r=$(cd "$p5" && pwd -P)
echo "- Excluded root." > "$p5/CLAUDE.md"; echo "# Agents five" > "$p5/AGENTS.md"
echo '{"claudeMdExcludes": ["**/five/CLAUDE.md"]}' > "$p5/.claude/settings.json"
bash "$here/inventory.sh" --out "$out" --project "$p5" --home "$home" --config-dir "$config" --managed-dir "$tmp/managed" >/dev/null 2>&1
expect "$p5r/CLAUDE.md" never
expect "$p5r/AGENTS.md" always

echo "test-inventory: ok"
