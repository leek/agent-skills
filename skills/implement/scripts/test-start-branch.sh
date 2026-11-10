#!/bin/bash
# Offline test for start-branch.sh: throwaway repos with a bare origin and a stub gh.
# Usage: test-start-branch.sh    (prints one "ok <case>" line per case; exits 1 on the first failure)

set -e

here=$(cd "$(dirname "$0")" && pwd)
sb="$here/start-branch.sh"
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

mkdir "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/bin/bash
printf '%s|' "$@" >> "$GH_LOG"; echo >> "$GH_LOG"
[ -z "$GH_FAIL" ] || { echo "gh: stub failure" >&2; exit 1; }
if [ "$1 $2" = "pr create" ]; then echo "https://github.com/o/r/pull/41"; fi
EOF
chmod +x "$T/bin/gh"
export GH_LOG="$T/gh.log" GH_FAIL=""
PATH="$T/bin:$PATH"

fail() { echo "FAIL $1" >&2; [ ! -f "$T/err" ] || sed 's/^/  stderr: /' "$T/err" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
field() { printf '%s' "$out" | jq -r "$1"; }

n=0
new_repo() {  # sets $repo (a clone on main, one pushed commit) and $origin
  n=$((n + 1))
  origin="$T/$n/origin.git"; repo="$T/$n/repo"
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
  git -C "$repo" add -f -- "$1"
  git -C "$repo" commit -q -m "$3"
}
spec_on_docs_branch() {  # docs/feat-spec holds .scratch/feat/spec.md; the checkout returns to main
  git -C "$repo" switch -q -c docs/feat-spec
  commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
  git -C "$repo" switch -q main
}
run() {  # run <args>: sets $out and $code; stderr in $T/err
  code=0
  out=$(cd "$repo" && bash "$sb" "$@" 2>"$T/err") || code=$?
}
sha() { git -C "$repo" rev-parse "$1"; }

# plain branch
new_repo
run feat --branch feat
eq plain-exit "$code" 0
eq plain-branch "$(field .branch)" feat
eq plain-worktree "$(field .worktree)" ""
eq plain-base "$(field .base_sha)" "$(sha origin/main)"
eq plain-default "$(field .default)" main
eq plain-current "$(git -C "$repo" branch --show-current)" feat
eq plain-rest "$(field '[.scratch_source, .scratch_commit, .untracked_copy, .default_ahead_scratch_only, .default_reset, .integration_pr, (.todo | length)] | @csv')" '"","","none",false,false,,0'
eq plain-no-gh "$(cat "$GH_LOG")" ""
echo "ok plain branch"

# worktree
new_repo
run feat --branch feat --worktree
eq worktree-exit "$code" 0
eq worktree-path "$(field .worktree)" "$repo/.claude/worktrees/feat"
eq worktree-branch "$(git -C "$repo/.claude/worktrees/feat" branch --show-current)" feat
eq worktree-main-stays "$(git -C "$repo" branch --show-current)" main
eq worktree-todo "$(field '.todo | length')" 2
field '.todo[0]' | grep -q 'runnable' || fail "worktree: todo names no bootstrap"
field '.todo[1]' | grep -q "$repo/.claude/worktrees/feat" || fail "worktree: todo names no path"
echo "ok worktree"

# scratch carried from docs/<slug>-spec
new_repo
spec_on_docs_branch
run feat --branch feat --worktree
eq docs-exit "$code" 0
eq docs-source "$(field .scratch_source)" docs/feat-spec
eq docs-commit "$(field .scratch_commit)" "$(sha feat)"
eq docs-base "$(field .base_sha)" "$(sha feat)"
eq docs-subject "$(git -C "$repo" log -1 --format=%s feat)" "docs(scratch): feat"
eq docs-parent "$(sha feat^)" "$(sha origin/main)"
eq docs-file "$(cat "$repo/.claude/worktrees/feat/.scratch/feat/spec.md")" "the spec"
eq docs-untracked "$(field .untracked_copy)" none
echo "ok scratch carried from docs/<slug>-spec"

# untracked copy in the main checkout: deleted when equal
new_repo
spec_on_docs_branch
mkdir -p "$repo/.scratch/feat"; echo "the spec" > "$repo/.scratch/feat/spec.md"
run feat --branch feat --worktree
eq deleted-exit "$code" 0
eq deleted-field "$(field .untracked_copy)" deleted
[ ! -e "$repo/.scratch/feat" ] || fail "untracked copy still there"
echo "ok untracked copy deleted"

# untracked copy: left when it differs
new_repo
spec_on_docs_branch
mkdir -p "$repo/.scratch/feat"; echo "edited since" > "$repo/.scratch/feat/spec.md"
run feat --branch feat --worktree
eq differs-exit "$code" 0
eq differs-field "$(field .untracked_copy)" differs
eq differs-kept "$(cat "$repo/.scratch/feat/spec.md")" "edited since"
echo "ok untracked copy differs"

# local default ahead by scratch only: reported, not moved, without --reset-default
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
ahead=$(sha main)
run feat --branch feat --worktree
eq noflag-exit "$code" 0
eq noflag-source "$(field .scratch_source)" main
eq noflag-only "$(field .default_ahead_scratch_only)" true
eq noflag-reset "$(field .default_reset)" false
eq noflag-main "$(sha main)" "$ahead"
field '.todo[]' | grep -q 'pulling main after the merge conflicts' || fail "no-flag: todo lacks the report line"
echo "ok reset refused without the flag"

# --reset-default, default checked out in the main checkout: git reset --keep
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
run feat --branch feat --worktree --reset-default
eq reset-exit "$code" 0
eq reset-only "$(field .default_ahead_scratch_only)" true
eq reset-done "$(field .default_reset)" true
eq reset-main "$(sha main)" "$(sha origin/main)"
[ ! -e "$repo/.scratch/feat/spec.md" ] || fail "reset --keep left the spec in the main checkout"
eq reset-carried "$(cat "$repo/.claude/worktrees/feat/.scratch/feat/spec.md")" "the spec"
eq reset-todo "$(field '.todo | length')" 2
echo "ok reset performed with the flag (reset --keep)"

# --reset-default, no checkout holds default: git branch -f
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
run feat --branch feat --reset-default
eq branchf-exit "$code" 0
eq branchf-done "$(field .default_reset)" true
eq branchf-main "$(sha main)" "$(sha origin/main)"
eq branchf-file "$(cat "$repo/.scratch/feat/spec.md")" "the spec"
eq branchf-clean "$(git -C "$repo" status --porcelain)" ""
echo "ok reset performed with the flag (branch -f)"

# other commits ahead too: no reset
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
commit_file README.md two "unrelated"
ahead=$(sha main)
run feat --branch feat --worktree --reset-default
eq other-exit "$code" 0
eq other-only "$(field .default_ahead_scratch_only)" false
eq other-reset "$(field .default_reset)" false
eq other-main "$(sha main)" "$ahead"
grep -q 'not moved' "$T/err" || fail "other commits: no reason on stderr"
echo "ok other commits ahead: no reset"

# the docs copy is newer than local default's: carried from docs, default not moved
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
ahead=$(sha main)
git -C "$repo" switch -q -c docs/feat-spec
commit_file .scratch/feat/spec.md "revised" "docs(scratch): feat spec revised"
git -C "$repo" switch -q main
run feat --branch feat --worktree --reset-default
eq newer-exit "$code" 0
eq newer-source "$(field .scratch_source)" docs/feat-spec
eq newer-reset "$(field .default_reset)" false
eq newer-main "$(sha main)" "$ahead"
echo "ok newest copy wins; default kept when its copy differs"

# dirty tree without --worktree
new_repo
echo dirty >> "$repo/README.md"
run feat --branch feat
eq dirty-exit "$code" 1
eq dirty-stdout "$out" ""
grep -q 'dirty' "$T/err" || fail "dirty: stderr does not say so"
git -C "$repo" rev-parse --verify -q refs/heads/feat >/dev/null && fail "dirty: branch was created"
eq dirty-current "$(git -C "$repo" branch --show-current)" main
echo "ok dirty tree refused without --worktree"

# --stack: empty commit, push of base_sha, draft PR
new_repo
run feat --branch feat --stack --title "My title"
eq stack-exit "$code" 0
eq stack-subject "$(git -C "$repo" log -1 --format=%s feat)" "chore(feat): open integration branch"
eq stack-base "$(field .base_sha)" "$(sha feat)"
eq stack-pushed "$(git -C "$origin" rev-parse refs/heads/feat)" "$(field .base_sha)"
eq stack-pr "$(field .integration_pr)" 41
eq stack-pr-type "$(field '.integration_pr | type')" number
eq stack-gh "$(cat "$GH_LOG")" "pr|create|--draft|--base|main|--head|feat|--title|[feat] My title|--body|Integration: lands the feat stack, then merges into main.|"
eq stack-upstream "$(git -C "$repo" config branch.feat.merge)" refs/heads/main
echo "ok --stack pushes base_sha and opens the draft PR"

# --stack with a carried spec: no empty commit
new_repo
spec_on_docs_branch
run feat --branch feat --worktree --stack --title "T"
eq stack2-exit "$code" 0
eq stack2-count "$(git -C "$repo" rev-list --count origin/main..feat)" 1
eq stack2-pushed "$(git -C "$origin" rev-parse refs/heads/feat)" "$(field .scratch_commit)"
echo "ok --stack adds no empty commit over a carried spec"

# a failing gh: exit 1, what exists is named, nothing removed; --existing finishes
new_repo
GH_FAIL=1 run feat --branch feat --worktree --stack --title "T"
eq ghfail-exit "$code" 1
eq ghfail-stdout "$out" ""
grep -q "branch feat, in the worktree $repo/.claude/worktrees/feat" "$T/err" || fail "gh failure: branch not named"
grep -q "origin/feat, pushed at" "$T/err" || fail "gh failure: push not named"
grep -q -- "--existing --base-sha $(sha feat)" "$T/err" || fail "gh failure: no way on"
[ -d "$repo/.claude/worktrees/feat" ] || fail "gh failure: worktree removed"
base=$(sha feat)
: > "$GH_LOG"
run feat --branch feat --stack --title "T" --existing --base-sha "$base"
eq existing-exit "$code" 0
eq existing-pr "$(field .integration_pr)" 41
eq existing-base "$(field .base_sha)" "$base"
eq existing-worktree "$(field .worktree)" "$repo/.claude/worktrees/feat"
grep -q 'not pushed again' "$T/err" || fail "--existing pushed a second time"
echo "ok failing gh leaves everything; --existing --base-sha finishes"

# --existing without --base-sha: steps 4-6 after the agent's own commit
new_repo
run feat --branch feat
commit_file notes.md "decisions" "docs: decisions"
run feat --branch feat --stack --title "T" --existing
eq existing2-exit "$code" 0
eq existing2-base "$(field .base_sha)" "$(sha feat)"
eq existing2-count "$(git -C "$repo" rev-list --count origin/main..feat)" 1
eq existing2-pushed "$(git -C "$origin" rev-parse refs/heads/feat)" "$(sha feat)"
echo "ok --existing takes base_sha at the tip"

# .scratch ignored: nothing carried
new_repo
commit_file .gitignore ".scratch" "ignore scratch"
git -C "$repo" push -q origin main
mkdir -p "$repo/.scratch/feat"; echo "the spec" > "$repo/.scratch/feat/spec.md"
run feat --branch feat --worktree
eq ignored-exit "$code" 0
eq ignored-rest "$(field '[.scratch_source, .scratch_commit, .untracked_copy] | @csv')" '"","","none"'
eq ignored-base "$(field .base_sha)" "$(sha origin/main)"
[ -f "$repo/.scratch/feat/spec.md" ] || fail "ignored: the main checkout's copy was touched"
echo "ok .scratch ignored: nothing carried"

# the new branch already holds the same content
new_repo
commit_file .scratch/feat/spec.md "the spec" "docs(scratch): feat spec"
git -C "$repo" push -q origin main
git -C "$repo" branch -q docs/feat-spec main
run feat --branch feat --worktree
eq same-exit "$code" 0
eq same-rest "$(field '[.scratch_source, .scratch_commit] | @csv')" '"",""'
eq same-base "$(field .base_sha)" "$(sha origin/main)"
echo "ok same content already on the branch: nothing carried"

# refusals and usage
new_repo
git -C "$repo" branch -q feat
run feat --branch feat --worktree
eq exists-exit "$code" 1
[ ! -e "$repo/.claude/worktrees/feat" ] || fail "existing branch: a worktree was made"
run feat
eq usage-no-branch "$code" 2
run feat --branch other --stack
eq usage-no-title "$code" 2
run feat --branch other --existing
eq usage-existing "$code" 2
run feat --branch other --bogus
eq usage-unknown "$code" 2
run feat --branch other --default nope
eq usage-no-default "$code" 2
git -C "$repo" rev-parse --verify -q refs/heads/other >/dev/null && fail "usage error created a branch"
echo "ok refusals and usage errors"
