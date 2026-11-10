#!/bin/bash
# Shared database mechanics, sourced (never run) by scratch-db.sh and by
# repository-cleanup's prune-merged-worktrees.sh, so the rules for what may be dropped,
# and the DROP itself, have one home.
#
# The caller sets, before calling any function:
#   main       the main checkout's path (first entry of `git worktree list`)
#   registry   <git-common-dir>/scratch-databases
#   protected  the output of db_protected_set (is_protected reads it)
# creds_for and creds_for_server set host, port, user and pass, which is_local, sql and
# server_dbs read.
#
# A registry line is epoch<TAB>connection<TAB>database<TAB>worktree path or "-". The
# connection field is <connection>@<host>:<port> when `register` recorded the server the
# database was created on, and the bare <connection> on a line written before that.
# Every registry write holds the lock directory "$registry.lock" and goes through a temp
# file of its own beside the registry: the caller's EXIT trap runs registry_cleanup.
# shellcheck disable=SC2154  # main, registry and protected come from the caller

git_common_dir() {  # absolute <git-common-dir>, without --path-format (Git 2.31+)
  local d
  d=$(git rev-parse --git-common-dir) || return 1
  (cd "$d" && pwd -P)
}

# The value dotenv reads: the last KEY= line; a quoted value is what the quotes hold (a #
# inside stays); an unquoted one ends at whitespace followed by #. No carriage return.
env_get() {  # env_get <file> <KEY>
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    { sub(/\r$/, "") }
    match($0, "^[ \t]*(export[ \t]+)?" k "[ \t]*=") { v = substr($0, RLENGTH + 1); found = 1 }
    END {
      if (!found) exit
      t = v; sub(/^[ \t]+/, "", t); q = substr(t, 1, 1)
      if (q == "\"" || q == "\047") {
        v = substr(t, 2); i = index(v, q); if (i) v = substr(v, 1, i - 1)
      } else {   # the leading whitespace is still there, so "KEY= # note" is all comment
        sub(/[ \t]+#.*$/, "", v); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      }
      print v
    }' "$1"
}

env_dbs() {  # env_dbs <dir>: the DB_DATABASE of its .env and .env.testing
  local f
  for f in "$1/.env" "$1/.env.testing"; do env_get "$f" DB_DATABASE; done
}

# Databases nothing may drop, one "owner<TAB>database" line each: the main checkout's
# (.env, .env.testing, phpunit.xml(.dist)) under MAIN, then each worktree's under its path.
db_protected_set() {
  local f w
  {
    env_dbs "$main" | sed 's/^/MAIN\t/'
    for f in "$main/phpunit.xml" "$main/phpunit.xml.dist"; do
      [ -f "$f" ] && sed -n 's/.*name="DB_DATABASE"[^>]*value="\([^"]*\)".*/MAIN\t\1/p' "$f"
    done
    git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10) }' | while read -r w; do
      [ "$w" = "$main" ] || env_dbs "$w" | sed "s|^|$w\t|"
    done
  } | awk -F'\t' '$2 != ""'
}

is_protected() {  # is_protected <db> <worktree being removed, or "">: named, or a parallel-testing copy of one
  printf '%s\n' "$protected" | awk -F'\t' -v d="$1" -v w="$2" '$1 != w && (d == $2 || d ~ ("^" $2 "_test_[0-9]+$")) { f = 1 } END { exit !f }'
}

creds_default() {  # creds_default <connection>: sets host port user pass to the defaults
  host=127.0.0.1; user=root; pass=""
  if [ "$1" = pgsql ]; then port=5432; else port=3306; fi
}

creds_from() {  # creds_from <connection> <env file>: sets host port user pass; 1 when the file is not on that connection
  local v
  [ "$(env_get "$2" DB_CONNECTION)" = "$1" ] || return 1
  creds_default "$1"
  v=$(env_get "$2" DB_HOST); [ -z "$v" ] || host=$v
  v=$(env_get "$2" DB_PORT); [ -z "$v" ] || port=$v
  v=$(env_get "$2" DB_USERNAME); [ -z "$v" ] || user=$v
  pass=$(env_get "$2" DB_PASSWORD)
}

# Credentials for a connection: the first of these env files that uses it, else the defaults.
creds_for() {  # creds_for <connection> <env files...>; sets host port user pass
  local conn=$1 f; shift
  for f in "$@"; do
    if creds_from "$conn" "$f"; then return 0; fi
  done
  creds_default "$conn"
}

# Credentials for one recorded server: the first env file on that connection whose host
# and port are exactly the recorded ones; or the defaults, when no env file is on that
# connection at all and the defaults are that server (what `register` recorded then).
# Returns 1, with host and port set to the recorded ones, when nothing here reaches it:
# the caller then refuses, and never falls back to another server.
creds_for_server() {  # creds_for_server <connection> <host> <port> <env files...>
  local conn=$1 h=$2 p=$3 f used=0; shift 3
  for f in "$@"; do
    creds_from "$conn" "$f" || continue
    used=1
    if [ "$host" = "$h" ] && [ "$port" = "$p" ]; then return 0; fi
  done
  creds_default "$conn"
  if [ "$used" = 0 ] && [ "$host" = "$h" ] && [ "$port" = "$p" ]; then return 0; fi
  host=$h; port=$p; user=""; pass=""
  return 1
}

# Split a registry connection field. Sets conn, and rhost and rport ("" on a line with
# no recorded server). The port is what follows the last colon, so an IPv6 host works.
# shellcheck disable=SC2034  # the caller reads conn, rhost and rport
split_conn_field() {  # split_conn_field <connection>[@<host>:<port>]
  conn=${1%%@*}; rhost=""; rport=""
  case "$1" in
    *@*:*) rhost=${1#*@}; rport=${rhost##*:}; rhost=${rhost%:*} ;;
  esac
}

is_local() { case "$host" in 127.0.0.1|localhost|::1) return 0 ;; esac; return 1; }

sql() {  # sql <connection> <statement>; uses host port user pass
  case "$1" in
    pgsql) PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d postgres -Atqc "$2" ;;
    mysql) MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -N -B -e "$2" ;;
  esac
}

# A client that fails returns 1 here, never an empty listing: the mysql output is taken
# first and reshaped after, because a pipeline would report only the last command.
server_dbs() {  # server_dbs <connection>: "name size" per line; uses host port user pass
  local rows
  case "$1" in
    pgsql) sql pgsql "SELECT datname || ' ' || pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE NOT datistemplate" ;;
    mysql)
      rows=$(sql mysql "SELECT schema_name, '-' FROM information_schema.schemata") || return 1
      printf '%s\n' "$rows" | tr '\t' ' ' ;;
    *) return 1 ;;
  esac
}

# --- registry writes: one writer at a time, each through its own temp file ---------------

registry_tmp=""
registry_locked=0

# mkdir is atomic on every filesystem, and flock is not on macOS. A lock left by a killed
# run is never broken here: the wait ends after about 10 seconds (SCRATCH_DB_LOCK_TRIES
# tenths of a second, default 100) with the path to remove.
registry_lock() {
  local i=0
  while ! mkdir "$registry.lock" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt "${SCRATCH_DB_LOCK_TRIES:-100}" ]; then
      echo ">> $registry.lock is held: another run is writing the registry. If none is, remove that directory." >&2
      return 1
    fi
    sleep 0.1
  done
  registry_locked=1
}

registry_unlock() {
  [ "$registry_locked" = 1 ] || return 0
  rmdir "$registry.lock" 2>/dev/null || true
  registry_locked=0
}

registry_cleanup() {  # the caller's EXIT trap: this process's temp file and lock only
  [ -z "$registry_tmp" ] || rm -f "$registry_tmp"
  registry_tmp=""
  registry_unlock
}

registry_add() {  # registry_add <connection field> <db> <worktree|->: 0 added, 3 already registered, 1 failed
  local c rc=0
  c=${1%%@*}
  registry_lock || return 1
  if [ -f "$registry" ] && awk -F'\t' -v c="$c" -v d="$2" '{ x = $2; sub(/@.*/, "", x) } x == c && $3 == d { f = 1 } END { exit !f }' "$registry"; then
    rc=3
  else
    printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$1" "$2" "$3" >> "$registry" || rc=1
  fi
  registry_unlock
  return $rc
}

registry_remove() {  # registry_remove <db>: delete its registry lines
  local rc=0
  [ -f "$registry" ] || return 0
  registry_lock || return 1
  if [ -f "$registry" ]; then
    registry_tmp=$(mktemp "$registry.XXXXXX") || rc=1
    if [ "$rc" = 0 ]; then
      { awk -F'\t' -v d="$1" '$3 != d' "$registry" > "$registry_tmp" && mv "$registry_tmp" "$registry"; } || rc=1
      rm -f "$registry_tmp"; registry_tmp=""
    fi
  fi
  registry_unlock
  return $rc
}

# The one DROP. It checks nothing: the caller has already proven the name may go.
# A success also deletes the name's registry lines; when only that part fails the
# database is gone all the same, so the result is still success, with a note.
drop_database() {  # drop_database <connection> <db>; uses host port user pass
  case "$1" in
    pgsql) sql pgsql "DROP DATABASE IF EXISTS \"$2\"" ;;
    mysql) sql mysql "DROP DATABASE IF EXISTS \`$2\`" ;;
    *) return 1 ;;
  esac || return 1
  registry_remove "$2" || echo ">> $2 is dropped, but its registry line stays: run scratch-db.sh unregister $2" >&2
}
