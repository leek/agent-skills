#!/bin/bash
# Offline test for release-plan.sh. Every repository is a throwaway under mktemp -d, remotes
# are local bare repositories, and `gh` is a stub first on PATH.
# Usage: bash test-release-plan.sh      (prints one "ok <case>" line per case; exits 1 on the first failure)
set -e
set -o pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/release-plan.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# No user or system git config: no signing, no hooks, no aliases.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@e.st GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@e.st

mkdir "$T/bin"
printf '#!/bin/bash\n# gh stub: only `auth status`, result from GH_STUB_AUTH\n[ "$1 $2" = "auth status" ] || { echo "gh stub: unexpected: $*" >&2; exit 64; }\nexit "${GH_STUB_AUTH:-0}"\n' > "$T/bin/gh"
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { echo "ok $1"; }
n=0
repo() { n=$((n + 1)); R="$T/r$n"; git init -q -b main "$R"; cd "$R"; }
commit() { echo "$1" >> log.txt; git add log.txt; git commit -q -m "$1" ${2:+-m "$2"}; }
tag() { git tag -a "$1" -m "$1"; }
# plan [arg]: JSON in $out, exit code in $code
plan() { code=0; out="$(bash "$SCRIPT" "$@" 2>"$T/stderr")" || code=$?; }
# want <jq filter> <expected compact JSON>
want() {
  got="$(printf '%s' "$out" | jq -c "$1")"
  [ "$got" = "$2" ] || fail "$case_name: $1 is $got, want $2 (stderr: $(cat "$T/stderr"))"
}

case_name="patch"
repo; commit "chore: init"; tag v1.2.3; commit "fix: a bug"; commit "docs: words"
plan
[ "$code" -eq 0 ] || fail "$case_name: exit $code: $(cat "$T/stderr")"
want '[.last_tag, .tag_style, .branch, .behind, .authenticated]' '["v1.2.3","v","main",0,true]'
want '[.bump, .next, .tag_free]' '["patch","v1.2.4",true]'
want '.commits | map(.subject)' '["docs: words","fix: a bug"]'
want '.commits[0].sha | test("^[0-9a-f]{7,}$")' 'true'
want '.rule' '"No breaking change and no feat commit is patch."'
want '[.version_files, .dirty]' '[[],[]]'
ok "anything else is patch"

case_name="feat"
repo; commit "chore: init"; tag v1.2.3; commit "fix: a bug"; commit "feat(api): a thing"
plan
want '[.bump, .next]' '["minor","v1.3.0"]'
want '.rule | test("feat\\(api\\): a thing")' 'true'
ok "any feat is minor"

case_name="bang"
repo; commit "chore: init"; tag v1.2.3; commit "feat(api)!: drop v1"; commit "fix: wow!"
plan
want '[.bump, .next]' '["major","v2.0.0"]'
ok "a ! subject is major"

case_name="bang only in prose"
repo; commit "chore: init"; tag v1.2.3; commit "fix: stop crashing!"
plan
want '[.bump, .next]' '["patch","v1.2.4"]'
ok "a ! outside the type prefix is not breaking"

case_name="breaking body"
repo; commit "chore: init"; tag v1.2.3; commit "fix: change the default" "BREAKING CHANGE: the default is now off"
plan
want '[.bump, .next]' '["major","v2.0.0"]'
ok "a BREAKING CHANGE footer is major"

case_name="breaking 0.x"
repo; commit "chore: init"; tag v0.4.2; commit "refactor!: BREAKING CHANGE rename everything"
plan
want '[.bump, .next]' '["minor","v0.5.0"]'
want '.rule | test("0\\.x")' 'true'
ok "breaking is minor while still 0.x"

case_name="explicit"
repo; commit "chore: init"; tag v0.4.2; commit "feat: a thing"
plan patch
want '[.bump, .next]' '["patch","v0.4.3"]'
want '.rule | test("argument")' 'true'
plan major
want '[.bump, .next]' '["major","v1.0.0"]'
ok "an explicit argument wins"

case_name="first release, no version file"
repo; commit "feat: first"
plan
want '[.last_tag, .tag_style, .bump, .next, .tag_free]' '[null,"v",null,"v0.1.0",true]'
want '.commits | length' '1'
ok "first release without a version file is v0.1.0"

case_name="first release, version file"
repo; printf '{"name": "x", "version": "0.3.0"}\n' > package.json; git add package.json; commit "feat: first"
plan minor
want '[.last_tag, .bump, .next]' '[null,null,"v0.3.0"]'
want '.version_files' '[{"path":"package.json","matches":1}]'
want '.rule | test("package.json") and test("not applied")' 'true'
ok "first release reads the version file"

case_name="tag taken"
repo; commit "chore: init"; tag v1.2.3
git checkout -q -b side; commit "fix: elsewhere"; tag v1.2.4; git checkout -q main
commit "fix: here"
plan
want '[.last_tag, .next, .tag_free]' '["v1.2.3","v1.2.4",false]'
ok "a taken tag is reported"

case_name="behind"
git init -q --bare -b main "$T/remote.git"
repo; commit "chore: init"; tag v1.2.3; commit "fix: mine"
git remote add origin "$T/remote.git"; git push -q -u origin main v1.2.3
git clone -q "$T/remote.git" "$T/other"
(cd "$T/other" && commit "fix: theirs" && commit "fix: theirs too" && git push -q origin main)
plan
want '[.behind, .branch]' '[2,"main"]'
ok "behind the remote is counted after a fetch"

case_name="fetch fails"
repo; commit "chore: init"; tag v1.2.3; commit "fix: mine"
git remote add origin "$T/does-not-exist.git"
plan
[ "$code" -eq 1 ] || fail "$case_name: exit $code, want 1"
[ -z "$out" ] || fail "$case_name: printed a plan: $out"
ok "a failed fetch stops the plan"

case_name="version files"
repo; mkdir .claude-plugin
printf '{"name": "x", "version": "1.2.3"}\n' > .claude-plugin/plugin.json
printf '{"metadata": {"version": "1.2.3"}, "other": "11.2.3 1.2.30"}\n' > .claude-plugin/marketplace.json
printf '{"version": "1.2.3", "dependencies": {"left-pad": "1.2.3"}}\n' > package.json
printf '[package]\nversion = "9.9.9"\n' > Cargo.toml
git add .claude-plugin package.json Cargo.toml; commit "chore: init"; tag v1.2.3
commit "fix: a bug"
echo 1.2.3 > VERSION
plan
want '.version_files' '[{"path":".claude-plugin/marketplace.json","matches":1},{"path":".claude-plugin/plugin.json","matches":1},{"path":"package.json","matches":2}]'
want '.dirty' '["VERSION"]'
ok "version files: one match, two matches reported, no match and untracked left out"

case_name="bare tag style"
repo; commit "chore: init"; tag 1.2.3; commit "feat: a thing"
plan
want '[.last_tag, .tag_style, .next]' '["1.2.3","","1.3.0"]'
ok "a tag style without v is kept"

case_name="unauthenticated"
repo; commit "chore: init"; tag v1.2.3; commit "fix: a bug"
GH_STUB_AUTH=1 plan
[ "$code" -eq 0 ] || fail "$case_name: exit $code, want 0"
want '[.authenticated, .next]' '[false,"v1.2.4"]'
ok "a failing gh auth status is reported, not fatal"

case_name="dirty"
repo; echo a > keep.txt; echo b > "old name.txt"; git add .; commit "chore: init"; tag v1.2.3; commit "fix: a bug"
echo changed >> keep.txt; echo new > untracked.txt; git mv "old name.txt" "new name.txt"
plan
want '.dirty | sort' '["keep.txt","new name.txt","untracked.txt"]'
ok "dirty lists modified, renamed and untracked paths"

case_name="no commits"
repo; commit "chore: init"; tag v1.2.3
plan minor
[ "$code" -eq 0 ] || fail "$case_name: exit $code"
want '[.commits, .bump, .next, .tag_free]' '[[],null,null,null]'
want '.rule' '"No commits since v1.2.3: nothing to release."'
ok "no commits since the tag is nothing to release"

case_name="odd tag"
repo; commit "chore: init"; tag release-5; commit "fix: a bug"
plan
[ "$code" -eq 1 ] || fail "$case_name: exit $code, want 1"
ok "a last tag that is not MAJOR.MINOR.PATCH stops the plan"

case_name="usage"
repo; commit "chore: init"
plan huge
[ "$code" -eq 2 ] || fail "$case_name: exit $code, want 2"
plan minor extra
[ "$code" -eq 2 ] || fail "$case_name: exit $code, want 2"
ok "usage errors exit 2"

case_name="subdirectory"
repo; printf '1.2.3\n' > VERSION; git add VERSION; commit "chore: init"; tag v1.2.3; commit "fix: a bug"
mkdir sub; cd sub
plan
want '.version_files' '[{"path":"VERSION","matches":1}]'
ok "runs from a subdirectory with repo-relative paths"
