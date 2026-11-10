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
# Records "psql<TAB>host<TAB>statement", and "port<TAB>user<TAB>statement" in $STUB_LOG.ports;
# lists $STUB_DBS for a SELECT.
host=""; stmt=""; port=""; user=""
while [ $# -gt 0 ]; do
  case "$1" in -h) host=$2; shift ;; -p) port=$2; shift ;; -U) user=$2; shift ;; -Atqc) stmt=$2; shift ;; esac
  shift
done
printf 'psql\t%s\t%s\n' "$host" "$stmt" >> "$STUB_LOG"
printf '%s\t%s\t%s\n' "$port" "$user" "$stmt" >> "$STUB_LOG.ports"
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
case "$stmt" in SELECT*) [ -z "${STUB_LIST_FAILS:-}" ] || { echo "ERROR 2002: cannot connect" >&2; exit 1; }; awk '{ print $1 "\t-" }' "$STUB_DBS" ;; esac
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
reset_log() { : > "$STUB_LOG"; : > "$STUB_LOG.ports"; }
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
grep -q "	pgsql@127.0.0.1:5432	app_x	$t/wt-other\$" "$registry" || fail "register did not record the server: $(cat "$registry")"
grep -q "	mysql@127.0.0.1:3306	app_m	-\$" "$registry" && fail "unregister left app_m"
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

# Registered while the main checkout was on a remote host: the recorded host decides,
# although the main checkout is local again.
env_main db.example.com
bash "$script" register pgsql app_remote - 2>/dev/null
env_main 127.0.0.1
grep -q "	pgsql@db.example.com:5432	app_remote	" "$registry" || fail "register did not record the remote host"
before=$(cat "$registry")
refused "remote host" app_remote "host db.example.com is not local"
[ ! -s "$STUB_LOG" ] || fail "remote host: the client was called"
# A line written before servers were recorded takes the server from the env files.
printf '1000000000\tpgsql\tapp_legacy\t-\n' >> "$registry"
before=$(cat "$registry")
env_main db.example.com
refused "remote host, line with no recorded server" app_legacy "host db.example.com is not local"
[ ! -s "$STUB_LOG" ] || fail "remote host, old line: the client was called"
env_main 127.0.0.1
ok "drop refuses a database on a host that is not local, without calling the client"

bash "$script" register pgsql app_y - 2>/dev/null
before=$(cat "$registry")

STUB_LIST_FAILS=1 refused "server cannot be listed" app_y "could not list"
ok "drop keeps the database when the server cannot be listed"

# mysql: a client that fails must not read as an empty listing (the DROP would follow).
env_main localhost mysql
bash "$script" register mysql app_my - 2>/dev/null
before=$(cat "$registry")
STUB_LIST_FAILS=1 refused "mysql server cannot be listed" app_my "could not list the mysql databases"
env_main 127.0.0.1
ok "drop keeps a mysql database when the mysql client fails to list the server"

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

# --- the DROP goes to the server the database was registered on, or nowhere ----------------
# A worktree on port 5433 while the main checkout is on 5432. After the worktree is removed
# its .env is gone: the drop must not run on the main checkout's server.
env_main 127.0.0.1
git worktree add -q -b w5433 "$t/wt-5433"
printf 'DB_CONNECTION=pgsql\nDB_HOST=127.0.0.1\nDB_PORT=5433\nDB_DATABASE=app\nDB_USERNAME=wt\n' > "$t/wt-5433/.env"
bash "$script" register pgsql app_w "$t/wt-5433" 2>/dev/null
grep -q "	pgsql@127.0.0.1:5433	app_w	$t/wt-5433\$" "$registry" || fail "register did not record the worktree's port: $(cat "$registry")"
git worktree remove "$t/wt-5433"
before=$(cat "$registry")
refused "worktree on another port, removed" app_w "registered on 127.0.0.1:5433"
[ ! -s "$STUB_LOG" ] || fail "worktree on another port: the client was called: $(cat "$STUB_LOG.ports")"
ok "drop refuses a removed worktree's database on port 5433 when the main checkout is on 5432, with no SQL sent"

# An env file that names that server gives the credentials, and every statement goes to 5433.
printf 'DB_CONNECTION=pgsql\nDB_PORT=5433\nDB_USERNAME=wt\nDB_DATABASE=app_env_testing\n' > .env.testing
reset_log
run drop app_w
[ "$rc" = 0 ] || fail "drop on the recorded port exits 0, got $rc ($(cat "$t/err"))"
jqt '.dropped == ["app_w"] and .kept == []' "drop on the recorded port"
[ "$(cut -f1,2 "$STUB_LOG.ports" | sort -u)" = "5433	wt" ] || fail "a statement went elsewhere than port 5433 as wt: $(cat "$STUB_LOG.ports")"
printf 'DB_CONNECTION=pgsql\nDB_DATABASE=app_env_testing\n' > .env.testing
ok "drop sends every statement to the recorded port 5433, with the credentials of the env file that names it"

# --- env_get reads a value the way dotenv does ----------------------------------------------
get() { ( . "$here/scratch-db-lib.sh"; env_get "$t/dotenv" "$1" ); }
printf 'A=app # main\r\nB="quo # ted" # note\r\nC=\047single # q\047\nD=plain\r\nE= # only a comment\nF=a#b\n export G = spaced \nH=first\nH=last\nI=\n' > "$t/dotenv"
[ "$(get A)" = "app" ] || fail "env_get: inline comment and CR not stripped: [$(get A)]"
[ "$(get B)" = "quo # ted" ] || fail "env_get: a double-quoted value keeps its #: [$(get B)]"
[ "$(get C)" = "single # q" ] || fail "env_get: a single-quoted value keeps its #: [$(get C)]"
[ "$(get D)" = "plain" ] || fail "env_get: trailing CR: [$(get D)]"
[ -z "$(get E)" ] || fail "env_get: a value that is only a comment is empty: [$(get E)]"
[ "$(get F)" = "a#b" ] || fail "env_get: a # with no whitespace before it is part of the value: [$(get F)]"
[ "$(get G)" = "spaced" ] || fail "env_get: export and spaces round =: [$(get G)]"
[ "$(get H)" = "last" ] || fail "env_get: the last assignment wins: [$(get H)]"
[ -z "$(get I)$(get MISSING)" ] || fail "env_get: an empty or missing key is empty"
ok "env_get strips an inline comment, a carriage return and whitespace, and keeps # inside quotes"

# The consequence: the main checkout's database stays protected when its line has a comment.
printf 'DB_CONNECTION=pgsql\r\nDB_HOST=127.0.0.1\r\nDB_PORT=5432\r\nDB_DATABASE=app # main\r\nDB_USERNAME=root\r\n' > "$repo/.env"
before=$(cat "$registry")
refused "main checkout .env with an inline comment and CRLF" app "used by the main checkout"
refused "copy of it" app_test_1 "used by the main checkout"
env_main 127.0.0.1
ok "a DB_DATABASE line with an inline comment and CRLF still protects the main checkout's database"

# --- concurrent registry writers lose no update and leave no temp file ------------------------
: > "$registry"
bash "$script" register pgsql app_stays - 2>/dev/null
pids=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  bash "$script" register pgsql "app_c$i" - 2>/dev/null & pids="$pids $!"
done
for pid in $pids; do wait "$pid" || fail "a concurrent register failed"; done
[ "$(grep -c . "$registry")" = 21 ] || fail "concurrent register lost a line: $(grep -c . "$registry") of 21"
pids=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if [ $((i % 2)) = 0 ]; then bash "$script" unregister "app_c$i" 2>/dev/null & pids="$pids $!"
  else bash "$script" drop "app_c$i" >/dev/null 2>&1 & pids="$pids $!"; fi
done
for pid in $pids; do wait "$pid" || fail "a concurrent unregister or drop failed"; done
[ "$(cut -f3 "$registry")" = app_stays ] || fail "concurrent unregister and drop lost an update: $(cut -f3 "$registry" | tr '\n' ' ')"
ok "20 concurrent registers, then 20 concurrent unregister and drop calls, lose no update"

# A lock nobody releases: the write gives up with the path, and changes nothing.
mkdir "$registry.lock"
before=$(cat "$registry")
set +e
SCRATCH_DB_LOCK_TRIES=2 bash "$script" unregister app_stays 2> "$t/err"; rc=$?
set -e
[ "$rc" = 1 ] || fail "unregister under a held lock exits 1, got $rc"
grep -q "$registry.lock" "$t/err" || fail "a held lock: stderr does not name the lock"
[ "$(cat "$registry")" = "$before" ] || fail "a held lock: the registry changed"
[ -d "$registry.lock" ] || fail "a run removed a lock it did not take"
rmdir "$registry.lock"
ok "a held lock stops the write with the lock's path, and the lock stays"

[ "$(find "$repo/.git" -maxdepth 1 -name 'scratch-databases*' | wc -l | tr -d ' ')" = 1 ] \
  || fail "a temp file or lock was left beside the registry: $(find "$repo/.git" -maxdepth 1 -name 'scratch-databases*')"
ok "no temp file or lock left behind"
