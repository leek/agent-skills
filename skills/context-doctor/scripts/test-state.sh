#!/bin/bash
# Offline test for state.sh: snapshot, edit and delete, restore, and the declined ledger.
set -e

here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$tmp"' EXIT
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

# Restore never writes through a symlink planted after the snapshot, removes --new files, and
# refuses a tampered backup.
echo "keep me" > "$tmp/victim"; echo "orig c" > "$tmp/c.md"
b2=$(bash "$here/state.sh" snapshot "$tmp/c.md" --new "$tmp/created.md" 2>/dev/null | jq -r .backup)
rm "$tmp/c.md"; ln -s "$tmp/victim" "$tmp/c.md"; echo "new file" > "$tmp/created.md"
r=$(bash "$here/state.sh" restore "$b2")
[ "$(cat "$tmp/victim")" = "keep me" ] || fail "restore wrote through a symlink"
[ ! -L "$tmp/c.md" ] && [ "$(cat "$tmp/c.md")" = "orig c" ] || fail "symlinked path not restored as the original file"
[ ! -e "$tmp/created.md" ] || fail "--new file not removed on restore"
echo "$r" | jq -e '.removed | length == 1 and (.[0] | endswith("/created.md"))' >/dev/null || fail "removed list: $r"
! bash "$here/state.sh" snapshot --new "$tmp/c.md" 2>/dev/null || fail "--new accepted an existing file"
b3=$(bash "$here/state.sh" snapshot "$tmp/c.md" 2>/dev/null | jq -r .backup)
echo "tampered" > "$b3/files$tmp/c.md"; echo "edited" > "$tmp/c.md"
! bash "$here/state.sh" restore "$b3" 2>/dev/null || fail "restore accepted a changed backup copy"
[ "$(cat "$tmp/c.md")" = "edited" ] || fail "a refused restore still changed files"
# A symlink is snapshotted and restored as a symlink.
ln -s "$tmp/victim" "$tmp/link.md"
b4=$(bash "$here/state.sh" snapshot "$tmp/link.md" 2>/dev/null | jq -r .backup)
rm "$tmp/link.md"; echo "replaced" > "$tmp/link.md"
bash "$here/state.sh" restore "$b4" > /dev/null
[ -L "$tmp/link.md" ] && [ "$(readlink "$tmp/link.md")" = "$tmp/victim" ] || fail "symlink not restored as a symlink"
# State is private, and decline reads a file argument.
[ "$(stat -f '%Lp' "$b4" 2>/dev/null || stat -c '%a' "$b4")" = 700 ] || fail "backup dir not private"
printf '{"fingerprint":"ccc"}\n' > "$tmp/d.jsonl"
[ "$(bash "$here/state.sh" decline "$tmp/d.jsonl" | jq .added)" = 1 ] || fail "decline from a file"

echo "test-state: ok"
