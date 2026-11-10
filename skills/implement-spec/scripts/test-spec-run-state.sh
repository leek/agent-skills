#!/bin/bash
# Offline test for spec-run-state.sh: throwaway repos with a bare origin and a stub gh.
# Usage: test-spec-run-state.sh    (prints one "ok <case>" line per case; exits 1 on the first failure)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/spec-run-state.sh"
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# gh stub: answers `gh pr list ... --jq` with $GH_STATE (one PR state, or nothing).
mkdir "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/bin/bash
printf '%s|' "$@" >> "$GH_LOG"; echo >> "$GH_LOG"
[ -z "$GH_STATE" ] || echo "$GH_STATE"
EOF
chmod +x "$T/bin/gh"
export GH_LOG="$T/gh.log" GH_STATE=""
PATH="$T/bin:$PATH"

fail() { echo "FAIL $1" >&2; [ ! -f "$T/err" ] || sed 's/^/  stderr: /' "$T/err" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
field() { printf '%s' "$out" | jq -r "$1"; }

n=0
new_repo() {  # new_repo [dir name]: sets $repo (a clone on main, one pushed commit) and $origin
  n=$((n + 1))
  origin="$T/$n/origin.git"; repo="$T/$n/${1:-repo}"
  mkdir -p "$T/$n"
  git init -q --bare -b main "$origin"
  git init -q -b main "$repo"
  git -C "$repo" remote add origin "$origin"
  echo one > "$repo/README.md"
  git -C "$repo" add -- README.md
  git -C "$repo" commit -q -m "init"
  git -C "$repo" push -q -u origin main
  : > "$GH_LOG"
}
commit_file() {  # commit_file <path> <content> <message>
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s\n' "$2" > "$repo/$1"
  git -C "$repo" add -- "$1"
  git -C "$repo" commit -q -m "$3"
}
run() {  # run <args>: sets $out and $code; stderr in $T/err
  code=0
  out=$(cd "$repo" && bash "$script" "$@" 2>"$T/err") || code=$?
}
sha() { git -C "$repo" rev-parse "$1"; }
common() { (cd "$repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P); }

# fresh
new_repo
run feat
eq fresh-exit "$code" 0
eq fresh-keys "$(field 'keys_unsorted | join(",")')" "slug,branch,mode,finished,integration_worktree,notes,base_sha,decision_sweep_done,build_decisions,local_default_scratch_only,default"
eq fresh-values "$(field '[.slug, .branch, .mode, (.finished | length), .integration_worktree, .base_sha, .decision_sweep_done, .build_decisions, .local_default_scratch_only, .default] | @csv')" \
  '"feat","feat","fresh",0,"","",false,"",false,"main"'
eq fresh-notes "$(field .notes)" "$(common)/implement-spec/feat"
eq fresh-one-line "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
eq fresh-no-gh "$(cat "$GH_LOG")" ""
echo "ok fresh"

# resume: the branch sits on its recorded base_sha (an ancestor of origin/main, but not landed)
new_repo
git -C "$repo" worktree add -q -b feat "$repo/.claude/worktrees/feat" origin/main
mkdir -p "$(common)/implement-spec/feat"
sha feat > "$(common)/implement-spec/feat/base_sha"
run feat
eq resume-exit "$code" 0
eq resume-values "$(field '[.branch, .mode, (.finished | length)] | @csv')" '"feat","resume",0'
eq resume-base "$(field .base_sha)" "$(sha feat)"
eq resume-worktree "$(field .integration_worktree)" "$repo/.claude/worktrees/feat"
echo "ok resume on the recorded base_sha"

# resume: base_sha from the first ticket merge when no note exists; an open PR is not finished
new_repo
git -C "$repo" switch -q -c feat
base=$(sha HEAD)
git -C "$repo" switch -q -c feat--01
commit_file a.txt a "ticket 1"
git -C "$repo" switch -q feat
git -C "$repo" merge -q --no-ff -m "merge 01" feat--01
git -C "$repo" switch -q main
GH_STATE=OPEN
run feat
eq merge-values "$(field '[.branch, .mode] | @csv')" '"feat","resume"'
eq merge-base "$(field .base_sha)" "$base"
grep -q '^pr|list|--head|feat|' "$GH_LOG" || fail "resume: gh pr list not asked for feat"
echo "ok resume takes base_sha from the first merge"

# <slug>-2: the first branch landed in origin/main
new_repo
git -C "$repo" switch -q -c feat
commit_file a.txt a "ticket 1"
git -C "$repo" switch -q main
git -C "$repo" merge -q --ff-only feat
git -C "$repo" push -q origin main
GH_STATE=""
run feat
eq landed-exit "$code" 0
eq landed-values "$(field '[.branch, .mode, (.finished | join(" ")), .base_sha] | @csv')" '"feat-2","fresh","feat",""'
eq landed-notes "$(field .notes)" "$(common)/implement-spec/feat-2"
echo "ok <slug>-2 when the first landed"

# <slug>-3: the first landed, the second's PR merged (gh), and finished stays a JSON array
git -C "$repo" switch -q -c feat-2
commit_file b.txt b "ticket 2"
git -C "$repo" switch -q main
GH_STATE=MERGED
run feat
eq merged-values "$(field '[.branch, .mode, (.finished | type), (.finished | join(" "))] | @csv')" '"feat-3","fresh","array","feat feat-2"'
GH_STATE=""
echo "ok <slug>-3 when a PR merged"

# decision_sweep_done, build_decisions and local_default_scratch_only
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
commit_file .scratch/feat/tickets/01.md "ticket" "docs(scratch): feat tickets"
commit_file .scratch/feat/decisions/01-build-decisions.md "# Build decisions" "docs(scratch): feat build decisions"
run feat
eq sweep-values "$(field '[.decision_sweep_done, .build_decisions, .local_default_scratch_only] | @csv')" 'true,".scratch/feat/decisions/01-build-decisions.md",true'
commit_file .scratch/feat/spec.md "the spec, revised" "docs(scratch): feat spec revised"
run feat
eq sweep-stale "$(field '[.decision_sweep_done, .build_decisions] | @csv')" 'false,".scratch/feat/decisions/01-build-decisions.md"'
commit_file README.md two "unrelated"
run feat
eq sweep-other-commit "$(field .local_default_scratch_only)" false
echo "ok decision_sweep_done and local_default_scratch_only"

# --default-only: the two fields start-branch.sh reads, and no gh call
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
git -C "$repo" branch -q feat
run feat --default-only
eq only-exit "$code" 0
eq only-json "$out" '{"default":"main","local_default_scratch_only":true}'
eq only-no-gh "$(cat "$GH_LOG")" ""
run feat --default-only --default trunk
eq only-default "$out" '{"default":"trunk","local_default_scratch_only":false}'
echo "ok --default-only"

# a path with a tab and a double quote still yields valid JSON
new_repo "$(printf 'we\tird"repo')"
run feat
eq odd-exit "$code" 0
eq odd-notes "$(field .notes)" "$(common)/implement-spec/feat"
echo "ok valid JSON for a tab and a quote in a path"

# usage errors, and a missing jq
run
eq usage-no-slug "$code" 2
run feat --bogus
eq usage-unknown "$code" 2
run feat --default
eq usage-default "$code" 2
mkdir "$T/nojq"
for tool in git sed awk tr head grep bash dirname; do ln -s "$(command -v "$tool")" "$T/nojq/$tool"; done
code=0
out=$(cd "$repo" && PATH="$T/nojq" /bin/bash "$script" feat 2>"$T/err") || code=$?
eq nojq-exit "$code" 1
eq nojq-stdout "$out" ""
grep -q 'needs jq' "$T/err" || fail "missing jq: no clear message"
echo "ok usage errors and missing jq"

# a slug that is not one directory name is a usage error; a trailing slash is dropped
new_repo
for bad in .. . ../x a/b -x; do
  run "$bad"
  eq "slug '$bad' exit" "$code" 2
  eq "slug '$bad' stdout" "$out" ""
done
run feat/
eq slash-exit "$code" 0
eq slash-slug "$(field '[.slug, .branch] | @csv')" '"feat","feat"'
eq slash-notes "$(field .notes)" "$(common)/implement-spec/feat"
echo "ok a slug of .., ., ../x or a/b exits 2; a trailing slash is dropped"
