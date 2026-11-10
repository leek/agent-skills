#!/bin/bash
# Offline test of prune-merged-worktrees.sh on one fixture: the listing output byte for byte,
# the refusal of a name that is not a candidate, and the removal of selected names.
# `gh`, `psql` and `herd` are stubs first on PATH; psql records every statement.
# Run: bash test-prune-merged-worktrees.sh   (PRUNE_SCRIPT=<path> tests another copy)

set -e

here=$(cd "$(dirname "$0")" && pwd)
script=${PRUNE_SCRIPT:-$here/prune-merged-worktrees.sh}
t=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$t"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }

mkdir -p "$t/bin" "$t/home"
cat > "$t/bin/gh" <<'STUB'
#!/bin/bash
# `gh pr list --state merged ... --jq ...`: prints $STUB_MERGED ("branch<TAB>head oid" lines).
[ -z "${STUB_GH_FAILS:-}" ] || { echo "gh: not logged in" >&2; exit 1; }
cat "$STUB_MERGED"
STUB
cat > "$t/bin/psql" <<'STUB'
#!/bin/bash
host=""; stmt=""
while [ $# -gt 0 ]; do
  case "$1" in -h) host=$2; shift ;; -Atqc) stmt=$2; shift ;; esac
  shift
done
printf 'psql\t%s\t%s\n' "$host" "$stmt" >> "$STUB_LOG"
case "$stmt" in SELECT*) cat "$STUB_DBS" ;; esac
STUB
printf '#!/bin/bash\nexit 0\n' > "$t/bin/herd"
chmod +x "$t/bin/gh" "$t/bin/psql" "$t/bin/herd"
export PATH="$t/bin:$PATH" HOME="$t/home"
export STUB_LOG="$t/sql.log" STUB_DBS="$t/server-dbs" STUB_MERGED="$t/merged"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# --- fixture ----------------------------------------------------------------------------
# main checkout: pgsql on 127.0.0.1, database app.
# wt-merged: PR merged, clean, .env names app_merged      -> candidate, with its database and copy
# wt-dirty:  PR merged, an untracked file                 -> kept
# wt-open:   no merged PR, .env names app_open            -> not listed; app_open protected
# registry:  app_old (2001, no worktree) -> "registry"; app_recent (now) -> not listed
# server:    app_orphan matches <app db>_* and nothing names it -> "orphan"
repo="$t/repo"
git init -q -b main "$repo"
cd "$repo"
printf '.env\n.env.testing\n' > .gitignore
git add .gitignore
git commit -q -m init
printf 'DB_CONNECTION=pgsql\nDB_HOST=127.0.0.1\nDB_PORT=5432\nDB_DATABASE=app\nDB_USERNAME=root\nDB_PASSWORD=\n' > .env
for n in merged dirty open; do
  git worktree add -q -b "feat/$n" "$t/wt-$n"
  printf 'DB_CONNECTION=pgsql\nDB_HOST=127.0.0.1\nDB_DATABASE=app_%s\n' "$n" > "$t/wt-$n/.env"
done
echo scratch > "$t/wt-dirty/untracked.txt"
head=$(git rev-parse HEAD)
printf 'feat/merged\t%s\nfeat/dirty\t%s\n' "$head" "$head" > "$STUB_MERGED"
registry="$repo/.git/scratch-databases"
printf '1000000000\tpgsql\tapp_old\t-\n%s\tpgsql\tapp_recent\t-\n' "$(date +%s)" > "$registry"
cat > "$STUB_DBS" <<'DBS'
postgres 7 MB
app 90 MB
app_test_1 9 MB
app_merged 8 MB
app_merged_test_1 8 MB
app_open 8 MB
app_dirty 8 MB
app_old 12 kB
app_recent 8 MB
app_orphan 8 MB
unrelated 8 MB
DBS
: > "$STUB_LOG"

run() {  # run <args...>: sets out and rc
  set +e
  out=$(bash "$script" "$@" 2> "$t/err"); rc=$?
  set -e
}
drops() { grep -c 'DROP DATABASE' "$STUB_LOG" 2>/dev/null || true; }

# --- listing: unchanged, byte for byte ------------------------------------------------------
expected="{\"worktrees\":[{\"path\":\"$t/wt-merged\",\"branch\":\"feat/merged\",\"databases\":[\"app_merged\",\"app_merged_test_1\"]}],\"databases\":[{\"connection\":\"pgsql\",\"database\":\"app_merged\",\"size\":\"8 MB\",\"source\":\"worktree\",\"worktree\":\"$t/wt-merged\"},{\"connection\":\"pgsql\",\"database\":\"app_merged_test_1\",\"size\":\"8 MB\",\"source\":\"worktree\",\"worktree\":\"$t/wt-merged\"},{\"connection\":\"pgsql\",\"database\":\"app_old\",\"size\":\"12 kB\",\"source\":\"registry\",\"worktree\":\"-\"},{\"connection\":\"pgsql\",\"database\":\"app_orphan\",\"size\":\"8 MB\",\"source\":\"orphan\",\"worktree\":\"-\"}],\"kept\":[{\"path\":\"$t/wt-dirty\",\"reason\":\"uncommitted or untracked changes\"}]}"
run
[ "$rc" = 0 ] || fail "listing: exit $rc ($(cat "$t/err"))"
[ "$out" = "$expected" ] || fail "listing output changed:
  got      $out
  expected $expected"
[ "$(drops)" = 0 ] || fail "listing ran a DROP"
[ -d "$t/wt-merged" ] || fail "listing removed a worktree"
run --dry-run
[ "$out" = "$expected" ] || fail "--dry-run output differs from the listing"
ok "listing output is unchanged on the fixture (worktree, registry and orphan databases, kept)"

# --- a failing gh: no worktree is a candidate ---------------------------------------------
export STUB_GH_FAILS=1
run
unset STUB_GH_FAILS
[ "$rc" = 0 ] || fail "failing gh: exit $rc"
printf '%s' "$out" | jq -e '.worktrees == [] and .kept == [] and (.databases | map(.database) == ["app_old","app_orphan"])' >/dev/null \
  || fail "failing gh: $out"
ok "a failing gh makes no worktree a candidate"

# --- one name that is not a candidate stops the run before anything changes ----------------
before=$(cat "$registry")
for args in "--drop pgsql:app" "--drop pgsql:app_open" "--drop pgsql:app_recent" "--drop pgsql:app_test_1" \
  "--remove $t/wt-open" "--remove $t/wt-dirty" "--remove $t/wt-merged --drop pgsql:app_merged --drop pgsql:app" \
  "--drop pgsql:app_merged" "--drop app_old"; do
  : > "$STUB_LOG"
  # shellcheck disable=SC2086
  run $args
  [ "$rc" = 1 ] || fail "$args: exit $rc, expected 1"
  [ -z "$out" ] || fail "$args: printed $out"
  [ "$(drops)" = 0 ] || fail "$args: a DROP ran"
  [ -d "$t/wt-merged" ] && [ -d "$t/wt-open" ] && [ -d "$t/wt-dirty" ] || fail "$args: a worktree was removed"
  [ "$(cat "$registry")" = "$before" ] || fail "$args: the registry changed"
done
ok "a name that is not a candidate stops the run before anything changes"

run --remove
[ "$rc" = 2 ] || fail "--remove with no path exits 2, got $rc"
run --bogus
[ "$rc" = 2 ] || fail "an unknown flag exits 2, got $rc"
ok "usage errors exit 2"

# --- remove exactly the selected names ---------------------------------------------------------
: > "$STUB_LOG"
run --remove "$t/wt-merged" --drop pgsql:app_merged --drop pgsql:app_old
[ "$rc" = 0 ] || fail "removing: exit $rc ($(cat "$t/err"))"
[ "$out" = "{\"removed\":[\"$t/wt-merged\"],\"dropped\":[\"app_merged\",\"app_old\"],\"kept\":[{\"path\":\"$t/wt-dirty\",\"reason\":\"uncommitted or untracked changes\"}]}" ] \
  || fail "removing output: $out"
[ ! -e "$t/wt-merged" ] || fail "the selected worktree is still there"
[ -d "$t/wt-open" ] && [ -d "$t/wt-dirty" ] || fail "an unselected worktree was removed"
git rev-parse -q --verify refs/heads/feat/merged >/dev/null || fail "the local branch was deleted"
[ "$(drops)" = 2 ] || fail "ran $(drops) DROP statements, expected 2"
grep -q 'DROP DATABASE IF EXISTS "app_merged"$' "$STUB_LOG" || fail "no DROP for app_merged"
grep -q 'DROP DATABASE IF EXISTS "app_old"$' "$STUB_LOG" || fail "no DROP for app_old"
grep -q "	app_old	" "$registry" && fail "app_old is still registered"
grep -q "	app_recent	" "$registry" || fail "app_recent lost its registry line"
[ ! -e "$registry.tmp" ] || fail "a temp file was left beside the registry"
ok "removes the selected worktree and drops the selected databases only, updating the registry"
