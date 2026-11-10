#!/bin/bash
# Offline test of scratch-db.sh: the registry subcommands, and `drop` with its refusals.
# psql and mysql are stubs first on PATH that record every statement they are asked to run;
# no database server is touched. Run: bash test-scratch-db.sh

set -e

here=$(cd "$(dirname "$0")" && pwd)
script="$here/scratch-db.sh"
t=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$t"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }
ok() { echo "ok $1"; }

# --- stubs ------------------------------------------------------------------------
mkdir -p "$t/bin"
cat > "$t/bin/psql" <<'STUB'
#!/bin/bash
# Records "psql<TAB>host<TAB>statement"; lists $STUB_DBS for a SELECT.
host=""; stmt=""
while [ $# -gt 0 ]; do
  case "$1" in -h) host=$2; shift ;; -Atqc) stmt=$2; shift ;; esac
  shift
done
printf 'psql\t%s\t%s\n' "$host" "$stmt" >> "$STUB_LOG"
case "$stmt" in
  SELECT*) [ -z "${STUB_LIST_FAILS:-}" ] || exit 1; cat "$STUB_DBS" ;;
  DROP*) case "$stmt" in *"\"${STUB_DROP_FAILS:-/}\""*) echo "database is being accessed by other users" >&2; exit 1 ;; esac ;;
esac
STUB
cat > "$t/bin/mysql" <<'STUB'
#!/bin/bash
host=""; stmt=""
while [ $# -gt 0 ]; do
  case "$1" in -h) host=$2; shift ;; -e) stmt=$2; shift ;; esac
  shift
done
printf 'mysql\t%s\t%s\n' "$host" "$stmt" >> "$STUB_LOG"
case "$stmt" in SELECT*) awk '{ print $1 "\t-" }' "$STUB_DBS" ;; esac
STUB
chmod +x "$t/bin/psql" "$t/bin/mysql"
export PATH="$t/bin:$PATH"
export STUB_LOG="$t/sql.log" STUB_DBS="$t/server-dbs"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# --- fixture: a main checkout on a local pgsql server, and one remaining worktree ----
repo="$t/repo"
git init -q -b main "$repo"
cd "$repo"
printf '.env\n.env.testing\n' > .gitignore
git add .gitignore
git commit -q -m init
env_main() {  # env_main <host> [<connection>]
  printf 'DB_CONNECTION=%s\nDB_HOST=%s\nDB_PORT=5432\nDB_DATABASE=app\nDB_USERNAME=root\nDB_PASSWORD="se cret"\n' "${2:-pgsql}" "$1" > "$repo/.env"
}
env_main 127.0.0.1
printf 'DB_CONNECTION=pgsql\nDB_DATABASE=app_env_testing\n' > .env.testing
printf '<phpunit><php>\n<env name="DB_DATABASE" value="app_phpunit"/>\n</php></phpunit>\n' > phpunit.xml
git worktree add -q -b other "$t/wt-other"
printf 'DB_CONNECTION=pgsql\nDB_DATABASE=app_other\n' > "$t/wt-other/.env"
registry="$repo/.git/scratch-databases"

cat > "$STUB_DBS" <<'DBS'
postgres 7 MB
app 90 MB
app_test_1 9 MB
app_x 8 MB
app_x_test_1 8 MB
app_x_test_2 8 MB
app_x_test_abc 8 MB
app_xy 8 MB
app_other 8 MB
app_y 8 MB
app_y_test_1 8 MB
DBS

run() {  # run <args...>: sets out and rc; stderr goes to $t/err
  set +e
  out=$(bash "$script" "$@" 2> "$t/err"); rc=$?
  set -e
}
drops() { grep -c 'DROP DATABASE' "$STUB_LOG" 2>/dev/null || true; }
reset_log() { : > "$STUB_LOG"; }
is_json() { printf '%s' "$out" | jq -e . >/dev/null || fail "$1: stdout is not valid JSON: $out"; }
jqt() { printf '%s' "$out" | jq -e "$1" >/dev/null || fail "$2: expected $1, got $out"; }

# --- registry subcommands -----------------------------------------------------------
reset_log
run list
[ "$out" = "[]" ] || fail "list with no registry prints []: $out"
run register pgsql app_x "$t/wt-other"
[ "$rc" = 0 ] || fail "register"
run register pgsql app_x "$t/wt-other"
[ "$(grep -c . "$registry")" = 1 ] || fail "register twice keeps one line"
run register mysql app_m -
run list
[ "$out" = "[{\"connection\":\"pgsql\",\"database\":\"app_x\",\"worktree\":\"$t/wt-other\"},{\"connection\":\"mysql\",\"database\":\"app_m\",\"worktree\":\"-\"}]" ] || fail "list output: $out"
run list "$t/wt-other"
jqt 'length == 1 and .[0].database == "app_x"' "list <worktree>"
run unregister app_m
run list
jqt 'map(.database) == ["app_x"]' "unregister"
run register oracle app_q -
[ "$rc" = 2 ] || fail "register with a bad connection exits 2, got $rc"
run nonsense
[ "$rc" = 2 ] || fail "unknown subcommand exits 2, got $rc"
ok "register, list, unregister"

odd=$(printf '%s/w t"x\ty' "$t")
mkdir -p "$odd"
run register pgsql app_odd "$odd"
run list "$odd"
is_json "list with an odd path"
[ "$(printf '%s' "$out" | jq -r '.[0].worktree')" = "$odd" ] || fail "list keeps a path with a space, a quote and a tab: $out"
run unregister app_odd
ok "list prints valid JSON for a worktree path with a space, a double quote and a tab"

# --- drop: the registered database and its two parallel-testing copies ----------------
run register pgsql app_keep -
reset_log
run drop app_x
[ "$rc" = 0 ] || fail "drop of a registered database exits 0, got $rc ($(cat "$t/err"))"
[ "$out" = '{"dropped":["app_x","app_x_test_1","app_x_test_2"],"kept":[]}' ] || fail "drop output: $out"
[ "$(drops)" = 3 ] || fail "drop ran $(drops) DROP statements, expected 3"
for d in app_x app_x_test_1 app_x_test_2; do
  grep -q "DROP DATABASE IF EXISTS \"$d\"\$" "$STUB_LOG" || fail "no DROP recorded for $d"
done
grep -q 'app_x_test_abc"\|app_xy"\|"app"' "$STUB_LOG" && fail "drop touched a database that is not a copy"
[ "$(cut -f2 "$STUB_LOG" | sort -u)" = 127.0.0.1 ] || fail "drop used a host other than 127.0.0.1"
grep -q "	app_x	" "$registry" && fail "dropped database is still registered"
grep -q "	app_keep	" "$registry" || fail "drop removed another database's registry line"
ok "drop of a registered database drops it and its two _test_<N> copies, and unregisters it"

# --- drop: refusals ------------------------------------------------------------------
before=$(cat "$registry")
refused() {  # refused <case> <database> <reason pattern>: kept, exit 1, no SQL at all, registry as it was
  reset_log
  run drop "$2"
  [ "$rc" = 1 ] || fail "$1: exit $rc, expected 1 ($out)"
  is_json "$1"
  printf '%s' "$out" | jq -e --arg d "$2" --arg r "$3" '.dropped == [] and (.kept | length == 1) and .kept[0].database == $d and (.kept[0].reason | test($r))' >/dev/null \
    || fail "$1: expected $2 kept for /$3/, got $out"
  [ "$(drops)" = 0 ] || fail "$1: a DROP ran"
  [ "$(cat "$registry")" = "$before" ] || fail "$1: the registry changed"
}

refused "unregistered name" app_y "not in the scratch-database registry"
[ ! -s "$STUB_LOG" ] || fail "unregistered name: the client was called"
ok "drop refuses a name that is not registered"

# Registered by mistake: the registry line alone never unlocks a database a checkout uses.
for d in app app_test_1 app_env_testing app_phpunit app_phpunit_test_3 app_other app_other_test_2; do
  bash "$script" register pgsql "$d" - 2>/dev/null
done
before=$(cat "$registry")
refused "main checkout .env" app "used by the main checkout"
refused "copy of the main checkout's" app_test_1 "used by the main checkout"
ok "drop refuses the main checkout's database and its _test_1 copy"
refused "main checkout .env.testing" app_env_testing "used by the main checkout"
refused "main checkout phpunit.xml" app_phpunit "used by the main checkout"
refused "copy of the phpunit.xml database" app_phpunit_test_3 "used by the main checkout"
refused "remaining worktree .env" app_other "remaining worktree"
refused "copy of a remaining worktree's" app_other_test_2 "remaining worktree"
ok "drop refuses a database named by .env.testing, phpunit.xml or a remaining worktree, and copies of them"

refused "bad name" 'app-x"; DROP' "not \\[A-Za-z0-9_\\]\\+"
ok "drop refuses a name that is not [A-Za-z0-9_]+"

bash "$script" register sqlite app_lite - 2>/dev/null
before=$(cat "$registry")
refused "sqlite" app_lite "sqlite database is a file in the worktree"
ok "drop refuses a sqlite database and says it is a file in the worktree"

bash "$script" register pgsql app_y - 2>/dev/null
before=$(cat "$registry")
env_main db.example.com
refused "remote host" app_y "host db.example.com is not local"
[ ! -s "$STUB_LOG" ] || fail "remote host: the client was called"
env_main 127.0.0.1
ok "drop refuses a database on a host that is not local, without calling the client"

STUB_LIST_FAILS=1 refused "server cannot be listed" app_y "could not list"
ok "drop keeps the database when the server cannot be listed"

run drop
[ "$rc" = 2 ] || fail "drop with no name exits 2, got $rc"
run drop app_y app_keep
[ "$rc" = 2 ] || fail "drop with two names exits 2, got $rc"
[ "$(cat "$registry")" = "$before" ] || fail "a usage error changed the registry"
ok "drop with no name, or two, is a usage error (exit 2)"

# --- drop: a failing DROP keeps its registry line; only what was dropped is unregistered ---
bash "$script" register pgsql app_y_test_1 - 2>/dev/null   # a copy registered under its own name
reset_log
export STUB_DROP_FAILS=app_y_test_1
run drop app_y
unset STUB_DROP_FAILS
[ "$rc" = 0 ] || fail "drop with a failing copy still exits 0 for the named database, got $rc"
jqt '.dropped == ["app_y"] and .kept == [{"database":"app_y_test_1","reason":"drop failed (open connections?)"}]' "failing copy"
grep -q "	app_y	" "$registry" && fail "app_y is still registered after its drop"
grep -q "	app_y_test_1	" "$registry" || fail "app_y_test_1 was unregistered although its drop failed"
ok "registry updated only for what was dropped (a failed copy keeps its line)"

reset_log
export STUB_DROP_FAILS=app_keep
run drop app_keep
unset STUB_DROP_FAILS
[ "$rc" = 1 ] || fail "a failed drop of the named database exits 1, got $rc"
jqt '.dropped == [] and .kept[0].database == "app_keep"' "failing named drop"
grep -q "	app_keep	" "$registry" || fail "app_keep was unregistered although its drop failed"
ok "a failed DROP of the named database exits 1 and keeps its registry line"

# --- drop: mysql, and a database already gone ------------------------------------------
env_main localhost mysql
bash "$script" register mysql app_gone - 2>/dev/null
reset_log
run drop app_gone
[ "$rc" = 0 ] || fail "mysql drop exits 0, got $rc ($(cat "$t/err"))"
[ "$out" = '{"dropped":["app_gone"],"kept":[]}' ] || fail "mysql drop output: $out"
grep -q '^mysql	localhost	DROP DATABASE IF EXISTS `app_gone`$' "$STUB_LOG" || fail "mysql DROP not recorded: $(cat "$STUB_LOG")"
grep -q "	app_gone	" "$registry" && fail "app_gone is still registered"
ok "drop on mysql quotes with backticks, and a database already gone is dropped and unregistered"

[ ! -e "$registry.tmp" ] || fail "a temp file was left beside the registry"
ok "no temp file left behind"
