#!/bin/bash
# Shared database mechanics, sourced (never run) by scratch-db.sh and by
# repository-cleanup's prune-merged-worktrees.sh, so the rules for what may be dropped,
# and the DROP itself, have one home.
#
# The caller sets, before calling any function:
#   main       the main checkout's path (first entry of `git worktree list`)
#   registry   <git-common-dir>/scratch-databases
#   protected  the output of db_protected_set (is_protected reads it)
# creds_for sets host, port, user and pass, which is_local, sql and server_dbs read.
# registry_remove writes through "$registry.tmp": the caller's EXIT trap removes it.
# shellcheck disable=SC2154  # main, registry and protected come from the caller

env_get() {  # env_get <file> <KEY>: value with surrounding quotes stripped
  [ -f "$1" ] || return 0
  grep -E "^$2=" "$1" | tail -n 1 | cut -d= -f2- | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
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

# Credentials for a connection: the first of these env files that uses it.
creds_for() {  # creds_for <connection> <env files...>; sets host port user pass
  local conn=$1 f; shift
  host=127.0.0.1; port=""; user=root; pass=""
  for f in "$@"; do
    [ "$(env_get "$f" DB_CONNECTION)" = "$conn" ] || continue
    host=$(env_get "$f" DB_HOST); port=$(env_get "$f" DB_PORT)
    user=$(env_get "$f" DB_USERNAME); pass=$(env_get "$f" DB_PASSWORD)
    break
  done
  [ -n "$host" ] || host=127.0.0.1
  [ -n "$user" ] || user=root
  [ -n "$port" ] || { [ "$conn" = pgsql ] && port=5432 || port=3306; }
}

is_local() { case "$host" in 127.0.0.1|localhost|::1) return 0 ;; esac; return 1; }

sql() {  # sql <connection> <statement>; uses host port user pass
  case "$1" in
    pgsql) PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d postgres -Atqc "$2" ;;
    mysql) MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -N -B -e "$2" ;;
  esac
}

server_dbs() {  # server_dbs <connection>: "name size" per line; uses host port user pass
  case "$1" in
    pgsql) sql pgsql "SELECT datname || ' ' || pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE NOT datistemplate" ;;
    mysql) sql mysql "SELECT schema_name, '-' FROM information_schema.schemata" | tr '\t' ' ' ;;
  esac
}

registry_remove() {  # registry_remove <db>: delete its registry lines
  [ -f "$registry" ] || return 0
  awk -F'\t' -v d="$1" '$3 != d' "$registry" > "$registry.tmp" && mv "$registry.tmp" "$registry"
}

# The one DROP. It checks nothing: the caller has already proven the name may go.
# A success also deletes the name's registry lines.
drop_database() {  # drop_database <connection> <db>; uses host port user pass
  case "$1" in
    pgsql) sql pgsql "DROP DATABASE IF EXISTS \"$2\"" ;;
    mysql) sql mysql "DROP DATABASE IF EXISTS \`$2\`" ;;
    *) return 1 ;;
  esac || return 1
  registry_remove "$2"
}
