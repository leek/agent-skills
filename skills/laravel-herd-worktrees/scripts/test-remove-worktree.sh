#!/bin/bash
# Offline test of remove-worktree.sh: the refusals (dirty tree, locked, main checkout), the
# removal, and valid JSON for a path and a branch argument holding a space, a double quote
# and a tab. `herd` is a stub first on PATH that records its calls; HOME is a temp directory.
# Run: bash test-remove-worktree.sh

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/remove-worktree.sh"
t=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$t"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }

# --- stub herd: serves every path listed in $STUB_SERVED ("path<TAB>site" lines) -------
mkdir -p "$t/bin" "$t/home"
cat > "$t/bin/herd" <<'STUB'
#!/bin/bash
printf 'herd' >> "$STUB_LOG"; printf ' %s' "$@" >> "$STUB_LOG"; printf '\n' >> "$STUB_LOG"
case "$1" in
  workspaces)
    case " $* " in *" --json "*)
      jq -R -s '[split("\n")[] | select(length > 0) | split("\t") | {path: .[:-1] | join("\t"), site: .[-1], served: true}]' "$STUB_SERVED" ;;
    esac ;;
  workspace:delete) exit "${STUB_DELETE_RC:-0}" ;;
esac
STUB
chmod +x "$t/bin/herd"
export PATH="$t/bin:$PATH" HOME="$t/home"
export STUB_LOG="$t/herd.log" STUB_SERVED="$t/served"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
: > "$STUB_SERVED"; : > "$STUB_LOG"

repo="$t/repo"
git init -q -b main "$repo"
cd "$repo"
printf '.herd-workspace.json\n' > .gitignore
git add .gitignore
git commit -q -m init
registry="$repo/.git/scratch-databases"

run() {  # run <args...>: sets out and rc
  set +e
  out=$(bash "$script" "$@" 2> "$t/err"); rc=$?
  set -e
}
is_json() { printf '%s' "$out" | jq -e . >/dev/null || fail "$1: stdout is not valid JSON: $out"; }
jqt() { printf '%s' "$out" | jq -e "$1" >/dev/null || fail "$2: expected $1, got $out"; }
serve() { printf '%s\t%s\n' "$1" "$2" >> "$STUB_SERVED"; }
unserved() { grep -q 'workspace:delete' "$STUB_LOG" && fail "$1: Herd was asked to unserve"; return 0; }

# --- usage ---------------------------------------------------------------------------
run
[ "$rc" = 2 ] || fail "no argument exits 2, got $rc"
run "$t/nowhere"
[ "$rc" = 2 ] || fail "a missing path exits 2, got $rc"
git worktree add -q -b u1 "$t/wt-usage"
run "$t/wt-usage" --bogus
[ "$rc" = 2 ] || fail "an unknown flag exits 2, got $rc"
[ -d "$t/wt-usage" ] || fail "a usage error removed the worktree"
ok "usage errors exit 2 and change nothing"

# --- dirty tree refused -----------------------------------------------------------------
git worktree add -q -b dirty "$t/wt-dirty"
serve "$t/wt-dirty" dirty.app.test
bash "$here/scratch-db.sh" register pgsql app_dirty "$t/wt-dirty" 2>/dev/null
echo scratch > "$t/wt-dirty/untracked.txt"
: > "$STUB_LOG"
run "$t/wt-dirty" --branch dirty
[ "$rc" = 0 ] || fail "dirty tree: exit $rc"
[ "$out" = "{\"path\":\"$t/wt-dirty\",\"removed\":false,\"reason\":\"uncommitted or untracked changes\",\"branch\":\"dirty\",\"branch_deleted\":false,\"branch_reason\":\"worktree kept, so the branch stays\",\"herd_unserve_failed\":null,\"databases\":[]}" ] \
  || fail "dirty tree output: $out"
[ -d "$t/wt-dirty" ] || fail "dirty tree: the worktree is gone"
git rev-parse -q --verify refs/heads/dirty >/dev/null || fail "dirty tree: the branch is gone"
[ ! -s "$STUB_LOG" ] || fail "dirty tree: Herd was called: $(cat "$STUB_LOG")"
grep -q "	app_dirty	" "$registry" || fail "dirty tree: its database was unregistered"
ok "dirty tree refused: worktree, branch, site and registry line all stay"

# --- locked refused before Herd is touched ------------------------------------------------
git worktree add -q -b locked "$t/wt-locked"
git worktree lock "$t/wt-locked"
serve "$t/wt-locked" locked.app.test
: > "$STUB_LOG"
run "$t/wt-locked"
jqt '.removed == false and .reason == "worktree is locked" and .databases == [] and .herd_unserve_failed == null' "locked"
[ -d "$t/wt-locked" ] || fail "locked: the worktree is gone"
[ ! -s "$STUB_LOG" ] || fail "locked: Herd was called before the refusal: $(cat "$STUB_LOG")"
ok "locked worktree refused before Herd is touched"

# --- main checkout refused ----------------------------------------------------------------
serve "$repo" app.test
: > "$STUB_LOG"
run "$repo"
jqt '.removed == false and .reason == "this is the main checkout, not a linked worktree"' "main checkout"
[ -d "$repo/.git" ] || fail "main checkout: it is gone"
[ ! -s "$STUB_LOG" ] || fail "main checkout: Herd was called: $(cat "$STUB_LOG")"
ok "main checkout refused before Herd is touched"

# --- a path and a branch argument with a space, a double quote and a tab -------------------
odd=$(printf '%s/w t"x\ty' "$t")
oddbranch=$(printf 'we ird"\tname')
git worktree add -q -b odd "$odd"
serve "$odd" odd.app.test
bash "$here/scratch-db.sh" register pgsql app_odd "$odd" 2>/dev/null
echo scratch > "$odd/untracked.txt"
run "$odd" --branch "$oddbranch"
is_json "odd path, kept"
[ "$(printf '%s' "$out" | jq -r .path)" = "$odd" ] || fail "odd path, kept: .path is not the path: $out"
[ "$(printf '%s' "$out" | jq -r .branch)" = "$oddbranch" ] || fail "odd branch: .branch is not the argument: $out"
jqt '.removed == false and .branch_deleted == false' "odd path, kept"
rm "$odd/untracked.txt"
tia="$HOME/.pest/tia/w-t-x-y-$(printf '%s' "$odd" | shasum -a 256 | cut -c1-16)"
mkdir -p "$tia" "$HOME/.pest/tia/other-0123456789abcdef"
: > "$STUB_LOG"
run "$odd" --branch odd
is_json "odd path, removed"
[ "$(printf '%s' "$out" | jq -r .path)" = "$odd" ] || fail "odd path, removed: .path is not the path: $out"
jqt '.removed == true and .reason == "" and .branch == "odd" and .branch_deleted == true and .branch_reason == "" and .herd_unserve_failed == null' "odd path, removed"
[ "$(printf '%s' "$out" | jq -r '.databases[0].worktree')" = "$odd" ] || fail "odd path: databases[0].worktree is not the path: $out"
jqt '.databases | length == 1 and .[0].connection == "pgsql" and .[0].database == "app_odd"' "odd path, databases"
[ ! -e "$odd" ] || fail "odd path: the worktree is still there"
git rev-parse -q --verify refs/heads/odd >/dev/null && fail "odd path: the branch is still there"
grep -q '^herd workspace:delete --force --keep-files -- odd.app.test$' "$STUB_LOG" || fail "odd path: Herd was not asked to unserve its site: $(cat "$STUB_LOG")"
grep -q "	app_odd	" "$registry" || fail "odd path: the caller's database was unregistered"
[ ! -e "$tia" ] || fail "the worktree's Pest cache was kept"
[ -d "$HOME/.pest/tia/other-0123456789abcdef" ] || fail "another project's Pest cache was deleted"
ok "path and branch with a space, a double quote and a tab come out as valid JSON, kept and removed"

# --- Herd's own database is unregistered; an unmerged branch stays ---------------------------
git worktree add -q -b herd-db "$t/wt-herd"
git -C "$t/wt-herd" commit -q --allow-empty -m "unmerged work"
printf '{"database_mode":"clone","database_name":"app_herd_db"}\n' > "$t/wt-herd/.herd-workspace.json"
serve "$t/wt-herd" herd-db.app.test
bash "$here/scratch-db.sh" register pgsql app_herd_db "$t/wt-herd" 2>/dev/null
bash "$here/scratch-db.sh" register pgsql app_mine "$t/wt-herd" 2>/dev/null
run "$t/wt-herd" --branch herd-db
jqt '.removed == true and .branch_deleted == false and .branch_reason == "git branch -d refused (not merged here)"' "herd database"
jqt '.databases | map(.database) == ["app_mine"]' "herd database: only the caller's database is listed"
git rev-parse -q --verify refs/heads/herd-db >/dev/null || fail "an unmerged branch was deleted"
ok "a database Herd created is unregistered; git branch -d refusing keeps the branch"

# --- Herd fails to unserve: reported, and git still decides ----------------------------------
git worktree add -q -b herd-down "$t/wt-down"
printf '{"database_mode":"empty","database_name":"app_down"}\n' > "$t/wt-down/.herd-workspace.json"
serve "$t/wt-down" down.app.test
bash "$here/scratch-db.sh" register pgsql app_down "$t/wt-down" 2>/dev/null
export STUB_DELETE_RC=1
run "$t/wt-down"
unset STUB_DELETE_RC
jqt '.removed == true and .herd_unserve_failed == {"database_mode":"empty","database_name":"app_down"} and (.databases | map(.database) == ["app_down"])' "herd down"
jqt '.branch == "" and .branch_deleted == false and .branch_reason == ""' "no --branch"
ok "a failed herd workspace:delete is reported in herd_unserve_failed and its database stays registered"

# --- a worktree Herd does not serve --------------------------------------------------------
git worktree add -q -b plain "$t/wt-plain"
: > "$STUB_LOG"
run "$t/wt-plain" --branch plain
jqt '.removed == true and .branch_deleted == true and .databases == []' "unserved worktree"
unserved "unserved worktree"
ok "a worktree Herd does not serve is removed without workspace:delete"
