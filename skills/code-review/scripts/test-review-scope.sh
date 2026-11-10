#!/bin/bash
# Offline test for review-scope.sh. Builds throwaway repositories in a temp directory.
# Prints one "ok <case>" line per case and exits non-zero on the first failed assertion.

set -e
set -o pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/review-scope.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
# eq <case> <actual> <expected>
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
# run <output file> <args...>: sets $rc, never trips set -e
run() { local out=$1; shift; rc=0; bash "$script" "$@" > "$out" 2> "$tmp/stderr" || rc=$?; }
g() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
# lines <n> <file>: write n numbered lines
lines() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) print "line " i }' > "$2"; }

new_repo() {
  repo="$tmp/$1"
  mkdir -p "$repo"
  cd "$repo"
  git init -q -b main
  echo base > base.txt
  g add base.txt
  g commit -q -m "base"
  base_sha=$(git rev-parse HEAD)
}

# --- commits and files, against the merge-base -------------------------------------
new_repo main-case
g checkout -q -b feat
echo a > a.txt; g add a.txt; g commit -q -m "add a"
mkdir -p "dir with space"; echo b > "dir with space/b.txt"; g add .; g commit -q -m "add b	with tab"
g checkout -q main
echo c > c.txt; g add c.txt; g commit -q -m "main moves on"
main_sha=$(git rev-parse HEAD)
g checkout -q feat
head_sha=$(git rev-parse HEAD)

run "$tmp/out.json" main
eq "main: exit" "$rc" 0
eq "main: fixed_point" "$(jq -r .fixed_point "$tmp/out.json")" main
eq "main: fixed_point_sha" "$(jq -r .fixed_point_sha "$tmp/out.json")" "$main_sha"
eq "main: head_sha" "$(jq -r .head_sha "$tmp/out.json")" "$head_sha"
eq "main: merge_base" "$(jq -r .merge_base "$tmp/out.json")" "$base_sha"
eq "main: diff_cmd" "$(jq -r .diff_cmd "$tmp/out.json")" "git diff main...HEAD"
eq "main: log_cmd" "$(jq -r .log_cmd "$tmp/out.json")" "git log main..HEAD --oneline"
eq "main: files" "$(jq -c .files "$tmp/out.json")" '["a.txt","dir with space/b.txt"]'
eq "main: files_changed" "$(jq -r .files_changed "$tmp/out.json")" 2
eq "main: lines_changed" "$(jq -r .lines_changed "$tmp/out.json")" 2
eq "main: commits" "$(jq -c '[.commits[].subject]' "$tmp/out.json")" '["add b\twith tab","add a"]'
eq "main: commit sha" "$(jq -r '.commits[0].sha' "$tmp/out.json")" "$head_sha"
eq "main: empty" "$(jq -r .empty "$tmp/out.json")" false
eq "main: size" "$(jq -r .size "$tmp/out.json")" inline
eq "main: untracked" "$(jq -c .untracked "$tmp/out.json")" '[]'
# The printed commands run as they are, and agree with the fields.
eq "main: diff_cmd runs" "$(eval "$(jq -r .diff_cmd "$tmp/out.json")" | grep -c '^diff --git')" 2
eq "main: log_cmd runs" "$(eval "$(jq -r .log_cmd "$tmp/out.json")" | wc -l | tr -d ' ')" 2
echo "ok commits and files against the merge-base"

# --- path scope --------------------------------------------------------------------
run "$tmp/out.json" main -- a.txt
eq "scope: exit" "$rc" 0
eq "scope: files" "$(jq -c .files "$tmp/out.json")" '["a.txt"]'
eq "scope: commits" "$(jq -c '[.commits[].subject]' "$tmp/out.json")" '["add a"]'
eq "scope: diff_cmd" "$(jq -r .diff_cmd "$tmp/out.json")" "git diff main...HEAD -- a.txt"
eq "scope: log_cmd" "$(jq -r .log_cmd "$tmp/out.json")" "git log main..HEAD --oneline -- a.txt"
run "$tmp/out.json" main -- "dir with space" a.txt
eq "scope: two paths" "$(jq -r .files_changed "$tmp/out.json")" 2
eq "scope: quoted diff_cmd" "$(jq -r .diff_cmd "$tmp/out.json")" 'git diff main...HEAD -- dir\ with\ space a.txt'
eq "scope: quoted diff_cmd runs" "$(eval "$(jq -r .diff_cmd "$tmp/out.json")" | grep -c '^diff --git')" 2
echo "ok path scope"

# --- a SHA or HEAD~n as the fixed point ----------------------------------------------
run "$tmp/out.json" "HEAD~1"
eq "relative: exit" "$rc" 0
eq "relative: files" "$(jq -c .files "$tmp/out.json")" '["dir with space/b.txt"]'
eq "relative: diff_cmd" "$(jq -r .diff_cmd "$tmp/out.json")" "git diff HEAD~1...HEAD"
echo "ok relative fixed point"

# --- bad ref -------------------------------------------------------------------------
run "$tmp/out.json" no-such-ref
eq "bad ref: exit" "$rc" 1
[ ! -s "$tmp/out.json" ] || fail "bad ref: printed stdout"
grep -q "does not resolve" "$tmp/stderr" || fail "bad ref: no clear message"
echo "ok bad ref exits 1"

# --- empty diff ------------------------------------------------------------------------
run "$tmp/out.json" HEAD
eq "empty: exit" "$rc" 1
eq "empty: flag" "$(jq -r .empty "$tmp/out.json")" true
eq "empty: files_changed" "$(jq -r .files_changed "$tmp/out.json")" 0
grep -q "empty: true" "$tmp/stderr" || fail "empty: stderr does not say empty: true"
run "$tmp/out.json" main -- base.txt
eq "empty scope: exit" "$rc" 1
eq "empty scope: flag" "$(jq -r .empty "$tmp/out.json")" true
echo "ok empty diff exits 1"

# --- usage and environment ---------------------------------------------------------------
run "$tmp/out.json"
eq "usage: no arguments" "$rc" 2
run "$tmp/out.json" --bogus main
eq "usage: unknown option" "$rc" 2
run "$tmp/out.json" main other
eq "usage: two fixed points" "$rc" 2
mkdir -p "$tmp/not-a-repo"
cd "$tmp/not-a-repo"
rc=0; GIT_CEILING_DIRECTORIES="$tmp" bash "$script" main > "$tmp/out.json" 2> "$tmp/stderr" || rc=$?
eq "not a repo: exit" "$rc" 3
echo "ok usage and environment errors"

# --- --wip -------------------------------------------------------------------------------
cd "$tmp/main-case"
echo more >> a.txt
lines 5 new.txt
echo ignored.log > .gitignore
echo x > ignored.log
run "$tmp/out.json" main
eq "no wip: files" "$(jq -c .files "$tmp/out.json")" '["a.txt","dir with space/b.txt"]'
run "$tmp/out.json" main --wip
eq "wip: exit" "$rc" 0
eq "wip: files" "$(jq -c .files "$tmp/out.json")" '[".gitignore","a.txt","dir with space/b.txt","new.txt"]'
eq "wip: untracked" "$(jq -c .untracked "$tmp/out.json")" '[".gitignore","new.txt"]'
eq "wip: diff_cmd" "$(jq -r .diff_cmd "$tmp/out.json")" "git diff $base_sha"
# a.txt 2 lines + b.txt 1 line tracked, .gitignore 1 + new.txt 5 untracked
eq "wip: lines" "$(jq -r .lines_changed "$tmp/out.json")" 9
run "$tmp/out.json" HEAD --wip
eq "wip on HEAD: exit" "$rc" 0
eq "wip on HEAD: commits" "$(jq -c .commits "$tmp/out.json")" '[]'
eq "wip on HEAD: files" "$(jq -c .files "$tmp/out.json")" '[".gitignore","a.txt","new.txt"]'
run "$tmp/out.json" main --wip -- new.txt
eq "wip scope: files" "$(jq -c .files "$tmp/out.json")" '["new.txt"]'
echo "ok --wip covers uncommitted and untracked files"

# --- size classes at their boundaries ------------------------------------------------------
# size_case <name> <files> <lines per file> <extra lines in the first file>
size_case() {
  new_repo "$1"
  g checkout -q -b feat
  local i
  for i in $(seq 1 "$2"); do lines "$3" "f$i.txt"; done
  if [ "$4" -gt 0 ]; then lines $(($3 + $4)) f1.txt; fi
  g add .
  g commit -q -m "change"
  run "$tmp/out.json" main
  eq "$1: exit" "$rc" 0
}
size_case s-3-150 3 50 0
eq "3 files 150 lines: lines" "$(jq -r .lines_changed "$tmp/out.json")" 150
eq "3 files 150 lines" "$(jq -r .size "$tmp/out.json")" inline
size_case s-3-151 3 50 1
eq "3 files 151 lines: lines" "$(jq -r .lines_changed "$tmp/out.json")" 151
eq "3 files 151 lines" "$(jq -r .size "$tmp/out.json")" fanout
size_case s-4 4 1 0
eq "4 files 4 lines" "$(jq -r .size "$tmp/out.json")" fanout
size_case s-25 25 1 0
eq "25 files: count" "$(jq -r .files_changed "$tmp/out.json")" 25
eq "25 files" "$(jq -r .size "$tmp/out.json")" fanout
size_case s-26 26 1 0
eq "26 files: count" "$(jq -r .files_changed "$tmp/out.json")" 26
eq "26 files" "$(jq -r .size "$tmp/out.json")" split
echo "ok size classes at their boundaries"

# --- deletions count as changed lines ---------------------------------------------------
new_repo deletions
lines 10 d.txt; g add d.txt; g commit -q -m "ten lines"
g checkout -q -b feat
lines 4 d.txt; g add d.txt; g commit -q -m "drop six"
run "$tmp/out.json" main
eq "deletions: lines" "$(jq -r .lines_changed "$tmp/out.json")" 6
echo "ok deletions count"
