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
cat > "$proj/CLAUDE.md" <<'MD'
See [AGENTS.md](./AGENTS.md).

@docs/agent-rules.md
@missing.md
@../../../outside-key
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

echo "test-inventory: ok"
