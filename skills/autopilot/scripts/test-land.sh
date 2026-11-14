#!/bin/bash
# Offline test for land.sh: the landing lock, the merge of the integration tip into a ticket
# branch, the merge onto the integration branch, and the stacked-PR cut. Fixtures are a
# throwaway repository, two ticket worktrees, and a bare `origin` under mktemp -d. No network.
# Prints one `ok <case>` line per case; exits non-zero on the first failed assertion.
set -e
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
land_sh="$here/land.sh"
for tool in jq git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "test-land.sh: $tool is required" >&2; exit 2; }
done

t="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$t"' EXIT

fail() {
  echo "FAIL $1" >&2
  exit 1
}

eq() {
  [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"
}

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

r="$t/repo"
notes="$t/notes"
git init -q --bare "$t/origin.git"
git init -q "$r"
printf 'base\n' >"$r/shared.txt"
git -C "$r" add -- shared.txt
git -C "$r" commit -q -m base
git -C "$r" remote add origin "$t/origin.git"
git -C "$r" switch -q -c foo
for n in 01 02 03; do
  git -C "$r" worktree add -q -b "foo--$n" "$t/wt-$n" foo
done

# land <NN> <action> [arguments]: stdout is the script's JSON; sets rc.
land() {
  local n="$1" action="$2"
  shift 2
  rc=0
  out="$(cd "$t/wt-$n" && LAND_WAIT_SECONDS=0 bash "$land_sh" "$action" --notes "$notes" "$@" 2>/dev/null)" || rc=$?
}

commit_file() {  # commit_file <NN> <file> <content>
  printf '%s\n' "$3" >"$t/wt-$1/$2"
  git -C "$t/wt-$1" add -- "$2"
  git -C "$t/wt-$1" commit -q -m "ticket $1"
}

land 01 finish --integration "$r" --ticket 01
eq "finish without begin exit" "$rc" 2
echo "ok finish needs the lock"

commit_file 01 one.txt one
land 01 begin --integration "$r"
eq "begin exit" "$rc" 0
eq "begin" "$(printf '%s' "$out" | jq -c '[.locked, .merged]')" '[true,true]'
eq "lock owner" "$(cat "$notes/land.lock/owner")" "foo--01"

commit_file 02 shared.txt two
land 02 begin --integration "$r"
eq "busy exit" "$rc" 3
eq "busy" "$(printf '%s' "$out" | jq -c '.')" '{"locked":false,"owner":"foo--01"}'
echo "ok one worker lands at a time"

land 01 finish --integration "$r" --ticket 01 --stack
eq "finish exit" "$rc" 0
eq "finish" "$(printf '%s' "$out" | jq -c '[.landed, .ticket, .position, .cut, .base, .pushed]')" '[true,"01",1,"foo-stack-01","foo",true]'
eq "merge sha" "$(printf '%s' "$out" | jq -r '.merge_sha')" "$(git -C "$r" rev-parse foo)"
eq "landed marker" "$(cat "$notes/landed/01")" "$(git -C "$r" rev-parse foo)"
[ -f "$r/one.txt" ] || fail "the ticket's file is not in the integration checkout"
[ ! -e "$notes/land.lock" ] || fail "the lock outlived finish"
eq "cut on the remote" "$(git -C "$t/origin.git" rev-parse foo-stack-01)" "$(git -C "$r" rev-parse foo)"
echo "ok finish merges with a merge commit, marks the ticket landed, and frees the lock"

# 03 changes the same line as 02 and lands first: 02 then conflicts on begin.
commit_file 03 shared.txt three
land 03 begin --integration "$r"
eq "second begin exit" "$rc" 0
land 03 finish --integration "$r" --ticket 03 --stack
eq "second finish" "$(printf '%s' "$out" | jq -c '[.position, .cut, .base]')" '[2,"foo-stack-03","foo-stack-01"]'
echo "ok the stack bases each cut on the one below"

land 02 begin --integration "$r"
eq "conflict exit" "$rc" 1
eq "conflict" "$(printf '%s' "$out" | jq -c '.')" '{"locked":true,"merged":false,"conflicts":["shared.txt"]}'
land 02 finish --integration "$r" --ticket 02
eq "finish mid-merge exit" "$rc" 1
eq "finish mid-merge" "$(printf '%s' "$out" | jq -r '.landed')" "false"
eq "lock kept through the conflict" "$(cat "$notes/land.lock/owner")" "foo--02"
printf 'two and three\n' >"$t/wt-02/shared.txt"
git -C "$t/wt-02" add -- shared.txt
git -C "$t/wt-02" commit -q -m "merge foo"
land 02 begin --integration "$r"
eq "begin again exit" "$rc" 0
land 02 finish --integration "$r" --ticket 02
eq "resolved finish" "$(printf '%s' "$out" | jq -c '[.landed, .position, .pushed]')" '[true,null,null]'
eq "resolved content" "$(cat "$r/shared.txt")" "two and three"
echo "ok a conflict keeps the lock until the worker resolves it and lands"

land 01 begin --integration "$r"
land 02 abort
eq "abort by another branch" "$(printf '%s' "$out" | jq -r '.released')" "false"
land 01 abort
eq "abort" "$(printf '%s' "$out" | jq -r '.released')" "true"
[ ! -e "$notes/land.lock" ] || fail "the lock outlived abort"
echo "ok abort frees only the caller's lock"
