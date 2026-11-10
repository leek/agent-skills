#!/bin/bash
# Offline test for publish-spec.sh: throwaway repos with a bare origin.
# Usage: test-publish-spec.sh    (prints one "ok <case>" line per case; exits 1 on the first failure)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/publish-spec.sh"
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

fail() { echo "FAIL $1" >&2; [ ! -f "$T/err" ] || sed 's/^/  stderr: /' "$T/err" >&2; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
field() { printf '%s' "$out" | jq -r "$1"; }

n=0
new_repo() {  # sets $repo (a clone on main, one pushed commit, an unpublished .scratch/feat) and $origin
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
  mkdir -p "$repo/.scratch/feat"
  echo "the spec" > "$repo/.scratch/feat/spec.md"
}
commit_file() {  # commit_file <path> <content> <message>
  printf '%s\n' "$2" > "$repo/$1"
  git -C "$repo" add -- "$1"
  git -C "$repo" commit -q -m "$3"
}
run() {  # run <args>: sets $out and $code; stderr in $T/err
  code=0
  out=$(cd "$repo" && bash "$script" "$@" 2>"$T/err") || code=$?
}
sha() { git -C "$repo" rev-parse "$1"; }
wt() { echo "$repo/.claude/worktrees/docs-feat-spec"; }

# .scratch ignored
new_repo
commit_file .gitignore ".scratch" "ignore scratch"
before=$(sha HEAD)
run feat -m "docs(scratch): feat spec"
eq ignored-exit "$code" 0
eq ignored-json "$out" '{"where":"ignored","branch":"","sha":""}'
eq ignored-head "$(sha HEAD)" "$before"
echo "ok ignored .scratch"

# current branch; then unchanged
new_repo
run feat -m "docs(scratch): feat spec"
eq current-exit "$code" 0
eq current-keys "$(field 'keys_unsorted | join(",")')" "where,branch,sha"
eq current-values "$(field '[.where, .branch] | @csv')" '"current","main"'
eq current-sha "$(field .sha)" "$(sha main)"
eq current-subject "$(git -C "$repo" log -1 --format=%s)" "docs(scratch): feat spec"
eq current-files "$(git -C "$repo" show --name-only --format= HEAD)" ".scratch/feat/spec.md"
run feat -m "docs(scratch): feat spec" --own "$(sha HEAD)"
eq unchanged-json "$out" '{"where":"current","branch":"main","sha":""}'
echo "ok current-branch commit"

# current branch: only .scratch/<slug> is committed, other staged work stays staged
new_repo
echo two >> "$repo/README.md"
git -C "$repo" add -- README.md
run feat -m "docs(scratch): feat spec"
eq only-files "$(git -C "$repo" show --name-only --format= HEAD)" ".scratch/feat/spec.md"
eq only-staged "$(git -C "$repo" diff --cached --name-only)" "README.md"
echo "ok current-branch commit leaves other staged work"

# HEAD carries a foreign commit: docs branch, checkout untouched
new_repo
commit_file other.txt x "someone else's work"
foreign=$(sha HEAD)
run feat -m "docs(scratch): feat spec"
eq docs-exit "$code" 0
eq docs-values "$(field '[.where, .branch] | @csv')" '"docs-branch","docs/feat-spec"'
eq docs-sha "$(field .sha)" "$(sha docs/feat-spec)"
eq docs-parent "$(sha docs/feat-spec^)" "$(sha origin/main)"
eq docs-content "$(git -C "$repo" show docs/feat-spec:.scratch/feat/spec.md)" "the spec"
eq docs-head "$(sha HEAD)" "$foreign"
eq docs-branch-stays "$(git -C "$repo" branch --show-current)" main
[ ! -e "$(wt)" ] || fail "docs branch: temporary worktree left behind"
[ -f "$repo/.scratch/feat/spec.md" ] || fail "docs branch: the checkout's copy is gone"
echo "ok docs-branch commit when HEAD carries a foreign commit"

# the docs branch exists: a revision commits there again; unchanged commits nothing
echo "revised" > "$repo/.scratch/feat/spec.md"
run feat -m "docs(scratch): feat spec revised" --own "$foreign"
eq revise-values "$(field '[.where, .branch] | @csv')" '"docs-branch","docs/feat-spec"'
eq revise-content "$(git -C "$repo" show docs/feat-spec:.scratch/feat/spec.md)" "revised"
run feat -m "docs(scratch): feat spec revised"
eq revise-unchanged "$out" '{"where":"docs-branch","branch":"docs/feat-spec","sha":""}'
[ ! -e "$(wt)" ] || fail "revision: temporary worktree left behind"
echo "ok docs-branch revision"

# --own: this session's commit is not foreign
new_repo
commit_file other.txt x "this session's work"
run feat -m "docs(scratch): feat spec" --own "$(sha HEAD)"
eq own-values "$(field '[.where, .branch] | @csv')" '"current","main"'
echo "ok --own keeps the commit on the current branch"

# missing origin/<default>
new_repo
run feat -m "docs(scratch): feat spec" --default nope
eq nodefault-exit "$code" 2
eq nodefault-stdout "$out" ""
eq nodefault-head "$(sha HEAD)" "$(sha origin/main)"
echo "ok missing origin/<default> exits 2"

# a failing pre-commit hook leaves no worktree behind; the second run succeeds
new_repo
commit_file other.txt x "someone else's work"
hook="$repo/.git/hooks/pre-commit"
mkdir -p "$repo/.git/hooks"
printf '#!/bin/bash\necho "hook says no" >&2\nexit 1\n' > "$hook"
chmod +x "$hook"
run feat -m "docs(scratch): feat spec"
[ "$code" != 0 ] || fail "hook: the run did not fail"
eq hook-stdout "$out" ""
[ ! -e "$(wt)" ] || fail "hook: temporary worktree left behind"
eq hook-no-commit "$(sha docs/feat-spec)" "$(sha origin/main)"
[ -f "$repo/.scratch/feat/spec.md" ] || fail "hook: the checkout's copy is gone"
rm "$hook"
run feat -m "docs(scratch): feat spec"
eq hook-retry-exit "$code" 0
eq hook-retry-values "$(field '[.where, .branch] | @csv')" '"docs-branch","docs/feat-spec"'
eq hook-retry-sha "$(field .sha)" "$(sha docs/feat-spec)"
echo "ok failing pre-commit hook leaves no worktree; second run succeeds"

# a branch name with a double quote still yields valid JSON
new_repo
git -C "$repo" switch -q -c 'we"ird'
run feat -m "docs(scratch): feat spec" --default main
eq quote-exit "$code" 0
eq quote-branch "$(field .branch)" 'we"ird'
echo "ok valid JSON for a quote in the branch name"

# usage errors, and a missing jq
new_repo
run
eq usage-no-slug "$code" 2
run feat
eq usage-no-message "$code" 2
run feat -m x --bogus
eq usage-unknown "$code" 2
run nope -m x
eq usage-no-dir "$code" 2
mkdir "$T/nojq"
for tool in git sed awk bash; do ln -s "$(command -v "$tool")" "$T/nojq/$tool"; done
code=0
out=$(cd "$repo" && PATH="$T/nojq" /bin/bash "$script" feat -m x 2>"$T/err") || code=$?
eq nojq-exit "$code" 1
grep -q 'needs jq' "$T/err" || fail "missing jq: no clear message"
eq nojq-no-commit "$(sha HEAD)" "$(sha origin/main)"
echo "ok usage errors and missing jq"

# a slug that would reach outside .scratch/<slug> is a usage error, and nothing is committed
new_repo
echo "not the spec" > "$repo/other.txt"
before=$(sha HEAD)
for bad in .. ../repo . feat/../.. a/b -x "feat/.."; do
  run "$bad" -m "docs(scratch): feat spec"
  eq "slug '$bad' exit" "$code" 2
  eq "slug '$bad' stdout" "$out" ""
  eq "slug '$bad' head" "$(sha HEAD)" "$before"
  eq "slug '$bad' untracked" "$(git -C "$repo" status --porcelain | sort | tr '\n' ' ')" "?? .scratch/ ?? other.txt "
done
echo "ok a slug of .., ., ../x or a/b exits 2 and commits nothing"

# a trailing slash is dropped
run feat/ -m "docs(scratch): feat spec"
eq slash-exit "$code" 0
eq slash-files "$(git -C "$repo" show --name-only --format= HEAD)" ".scratch/feat/spec.md"
echo "ok a trailing slash on the slug is dropped"

# .scratch ignored by a directory-only rule, and by a contents rule
for rule in ".scratch/" "/.scratch/" ".scratch/*"; do
  new_repo
  commit_file .gitignore "$rule" "ignore scratch"
  before=$(sha HEAD)
  run feat -m "docs(scratch): feat spec"
  eq "ignored '$rule' exit" "$code" 0
  eq "ignored '$rule' json" "$out" '{"where":"ignored","branch":"","sha":""}'
  eq "ignored '$rule' head" "$(sha HEAD)" "$before"
done
echo "ok ignored .scratch by the rules .scratch/, /.scratch/ and .scratch/*"

# detached HEAD: the commit goes on the docs branch, never on no branch
new_repo
git -C "$repo" switch -q --detach
before=$(sha HEAD)
run feat -m "docs(scratch): feat spec"
eq detached-exit "$code" 0
eq detached-values "$(field '[.where, .branch] | @csv')" '"docs-branch","docs/feat-spec"'
eq detached-sha "$(field .sha)" "$(sha docs/feat-spec)"
eq detached-head "$(sha HEAD)" "$before"
eq detached-still "$(git -C "$repo" branch --show-current)" ""
[ ! -e "$(wt)" ] || fail "detached: temporary worktree left behind"
echo "ok detached HEAD commits on the docs branch"
