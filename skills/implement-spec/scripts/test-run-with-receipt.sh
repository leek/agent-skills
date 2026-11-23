#!/bin/bash
# Offline regression tests: receipts must miss whenever execution inputs differ.
set -e

here=$(cd "$(dirname "$0")" && pwd)
helper="$here/run-with-receipt.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export RECEIPT_COUNTER="$T/calls"
receipt="$T/receipt.json"
context="$T/context.json"
mkdir "$T/repo"
cd "$T/repo"
git init -q
git config user.email receipt@example.test
git config user.name 'Receipt test'
cat >run.sh <<'SH'
#!/bin/bash
echo run >> "$RECEIPT_COUNTER"
echo 'test output'
case "${1:-}" in
  fail) exit 7 ;;
  mutate) echo change >> tracked ;;
esac
SH
echo original >tracked
git add -- run.sh tracked
git commit -qm initial
cat >"$context" <<'JSON'
{"reproducible":true,"runtime":"runtime-1","dependencies":"deps-1","configuration":"config-1","environment":"env-1","fixtures":"fixtures-1"}
JSON

fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$helper" "$receipt" "$context" -- bash run.sh "$@" 2>"$T/stderr"; }
status() { printf '%s' "$1" | jq -r .status; }
calls() { wc -l <"$RECEIPT_COUNTER" | tr -d ' '; }
expect() { [ "$1" = "$2" ] || fail "expected $2, got $1"; }

out=$(run)
expect "$(status "$out")" passed
expect "$(printf '%s' "$out" | jq -r .cached)" true
grep -q 'test output' "$T/stderr" || fail 'command output not forwarded'
out=$(run)
expect "$(status "$out")" reused
expect "$(calls)" 1
echo 'ok identical inputs reuse successful evidence' >&2

# Commit identity differs, but both the empty commit and a staged merge tree match.
git commit --allow-empty -qm equivalent
expect "$(status "$(run)")" reused
git checkout -qb feature
echo feature >feature
git add -- feature
git commit -qm feature
out=$(run)
expect "$(status "$out")" passed
git checkout -q -
git merge --no-ff --no-commit feature >"$T/merge" 2>&1
expect "$(status "$(run)")" reused
git commit -qm merged
echo 'ok equivalent commit and prospective merge trees reuse' >&2

# Each non-Git input participates in the key.
for field in runtime dependencies configuration environment fixtures; do
  jq --arg field "$field" '.[$field] += "-changed"' "$context" >"$T/new-context"
  mv "$T/new-context" "$context"
  expect "$(status "$(run)")" passed
  expect "$(status "$(run)")" reused
done
expect "$(status "$(run other-command-args)")" passed
echo 'ok command and all context inputs invalidate' >&2

echo dirty >>tracked
out=$(run)
expect "$(printf '%s' "$out" | jq -r .cached)" false
[ ! -f "$receipt" ] || fail 'dirty run retained receipt'
git checkout -- tracked
echo extra >untracked
out=$(run)
expect "$(printf '%s' "$out" | jq -r .cached)" false
rm untracked
out=$(run mutate)
expect "$(printf '%s' "$out" | jq -r .cached)" false
git checkout -- tracked
echo 'ok dirty, untracked and command-mutated files cannot cache' >&2

out=$(run)
set +e
out=$(run fail)
code=$?
set -e
expect "$code" 7
expect "$(status "$out")" failed
[ ! -f "$receipt" ] || fail 'failed run retained receipt'
expect "$(status "$(run)")" passed
echo broken >"$receipt"
expect "$(status "$(run)")" passed
echo 'ok failures propagate and corrupt receipts run fresh' >&2

cp "$context" "$T/good-context"
for invalid in '{}' '{"reproducible":false}' 'invalid'; do
  printf '%s\n' "$invalid" >"$context"
  out=$(run)
  expect "$(printf '%s' "$out" | jq -r .cached)" false
done
rm "$context"
out=$(run)
expect "$(printf '%s' "$out" | jq -r .cached)" false
cp "$T/good-context" "$context"

# Equal trees in different repositories are not interchangeable.
out=$(run)
git worktree add -q --detach "$T/linked" HEAD
cd "$T/linked"
expect "$(status "$(run)")" reused
cd "$T/repo"
git clone -q "$T/repo" "$T/clone"
cd "$T/clone"
expect "$(status "$(run)")" passed
echo 'ok linked worktrees reuse; uncertain context and other repositories run fresh' >&2

git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),module"
out=$(run)
expect "$(printf '%s' "$out" | jq -r .cached)" false
git reset -q HEAD -- module
set +e
bash "$helper" "$context" "$context" -- bash run.sh >"$T/same" 2>"$T/stderr"
code=$?
set -e
expect "$code" 2
[ -s "$context" ] || fail 'same-file arguments destroyed context'
echo 'ok submodule state is uncacheable and context cannot be overwritten' >&2

# Integration claims are dirty by design; excluding them requires explicit proof.
mkdir .scratch
echo ready >.scratch/ticket.md
git add -- .scratch/ticket.md
git -c user.name=Test -c user.email=test@example.test commit -qm tracker
out=$(run)
echo claimed >.scratch/ticket.md
out=$(run)
expect "$(printf '%s' "$out" | jq -r .cached)" false
jq '.planning_metadata_unused = true' "$context" >"$T/new-context"
mv "$T/new-context" "$context"
expect "$(status "$(run)")" passed
echo another-claim >.scratch/ticket.md
echo notes >.scratch/new.md
expect "$(status "$(run)")" reused
echo changed >>tracked
out=$(run)
expect "$(printf '%s' "$out" | jq -r .cached)" false
echo 'ok verified planning-only exclusion tolerates claims but never code changes' >&2
