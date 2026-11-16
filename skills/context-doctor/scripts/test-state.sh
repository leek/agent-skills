#!/bin/bash
# Offline test for state.sh: snapshot, edit and delete, restore, and the declined ledger.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export CONTEXT_DOCTOR_STATE="$tmp/state"
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "original a" > "$tmp/a.md"; echo "original b" > "$tmp/b.md"
backup=$(bash "$here/state.sh" snapshot "$tmp/a.md" "$tmp/b.md" 2>/dev/null | jq -r .backup)
[ -f "$backup/manifest.tsv" ] || fail "no manifest"
echo "edited" > "$tmp/a.md"; rm "$tmp/b.md"
bash "$here/state.sh" restore "$backup" > /dev/null
[ "$(cat "$tmp/a.md")" = "original a" ] || fail "edited file not restored"
[ "$(cat "$tmp/b.md")" = "original b" ] || fail "deleted file not recreated"
! bash "$here/state.sh" snapshot "$tmp/nope.md" 2>/dev/null || fail "snapshot of a missing file succeeded"

r=$(printf '{"fingerprint":"aaa","path":"x"}\n{"fingerprint":"bbb"}\n{"no":"fp"}\n' | bash "$here/state.sh" decline)
[ "$(echo "$r" | jq .added)" = 2 ] || fail "decline added: $r"
r=$(printf '{"fingerprint":"aaa"}\n' | bash "$here/state.sh" decline)
[ "$(echo "$r" | jq .added)" = 0 ] && [ "$(echo "$r" | jq .total)" = 2 ] || fail "repeat decline: $r"
[ "$(bash "$here/state.sh" dir)" = "$tmp/state" ] || fail "dir"

r=$(bash "$here/state.sh" audited "$tmp/a.md" 2>/dev/null)
[ "$(echo "$r" | jq .added)" = 1 ] || fail "audited: $r"
jq -e --arg h "$(shasum -a 256 "$tmp/a.md" | cut -d' ' -f1)" 'select(.sha256==$h and (.path|endswith("/a.md")) and .audited_on)' "$tmp/state/audited.jsonl" >/dev/null || fail "audited entry"
! bash "$here/state.sh" audited "$tmp/nope.md" 2>/dev/null || fail "audited a missing file"

echo "test-state: ok"
