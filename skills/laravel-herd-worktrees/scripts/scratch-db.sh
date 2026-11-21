#!/bin/bash
# Keep the scratch-database registry, <git-common-dir>/scratch-databases, that every skill
# creating a worktree or a throwaway database writes, and repository-cleanup reads; plan
# which local databases are left over; and drop a database once its run is done with it.
# This script is the one home of the rules for what may be dropped, and of the DROP itself:
# remove-worktree.sh and repository-cleanup's prune-merged-worktrees.sh run it as a command.
#
# One registry line per database: epoch<TAB>connection<TAB>database<TAB>worktree path, or "-".
# For pgsql and mysql the connection field is <connection>@<host>:<port>: the server the
# database was created on, which `register` reads from the first of the worktree's and the
# main checkout's .env, .env.testing on that connection (the defaults when none is). A line
# written before servers were recorded holds the bare connection.
#
# Usage: scratch-db.sh register <pgsql|mysql|sqlite> <database> [<worktree path>|-]
#        scratch-db.sh unregister <database>      registry only; `drop` already does it
#        scratch-db.sh list [<worktree path>]     JSON [{"connection","database","worktree"}]
#        scratch-db.sh drop <database>            DROP it and its <database>_test_<N> copies
#        scratch-db.sh drop-selected <connection>@<host>:<port> <database>
#                                                 DROP exactly that name, which a human selected
#        scratch-db.sh plan [--worktree <path>]...
#                                                 read-only: the leftover databases, as JSON
#
# Register the moment the database is created. Unregister only after a successful drop.
#
# Every drop, either entry, goes through one pipeline, and keeps, with a reason:
#   - a name that is not [A-Za-z0-9_]+
#   - a sqlite database: it is a file in the worktree, so delete the file, then unregister
#   - a name the main checkout's .env, .env.testing or phpunit.xml(.dist) uses, or a
#     remaining worktree's .env or .env.testing (so remove the worktree first), or a
#     parallel-testing copy of such a name
#   - a database host that is not local (127.0.0.1, localhost, ::1)
#   - a server that no env file here reaches. The DROP goes only to the recorded host and
#     port, with the user and password of the first of the worktree's (when it is still
#     there) and the main checkout's .env, .env.testing on that connection, host and port.
#     So a database of a removed worktree that ran on another server than the main checkout
#     is kept: it is never dropped on the main checkout's server.
#     A line with no recorded server uses the first of those env files on that connection.
#   - a server that cannot be listed (drop only), or a DROP that fails
# It never passes --force anywhere, and unregisters only what it dropped.
#
# drop is what a run uses for its own databases: the name must have a registry line (the
# line is what proves a run created it), and it runs DROP DATABASE IF EXISTS on the name
# and on each parallel-testing copy (<database>_test_<N>) the server lists. A database
# already gone counts as dropped.
#
# drop-selected is repository-cleanup's entry, for one name a human picked from `plan`'s
# list: the human's selection replaces the registry proof, so an unregistered name may go,
# and only that exact name (no copies). The server is named; a registry line for the name
# on that connection that records another server keeps it.
#
# plan --worktree <path> names a worktree about to be removed: its registered databases and
# the DB_DATABASE of its .env and .env.testing are candidates, and its own .env does not
# protect them. Output: JSON {"databases":[{"connection","database","size","source",
# "worktree","server"}],"kept":[{"path","reason"}]}; source is worktree, registry (a line 12
# hours old with no worktree, or whose directory is gone), orphan (an unregistered name a
# skill gives a scratch database) or prefix-only (any other unregistered <app db>_* name).
#
# Output, drop and drop-selected: JSON {"dropped":[names],"kept":[{"database","reason"}]}
# Exit, drop and drop-selected: 0 when the named database was dropped, 1 when it was kept,
# 2 on a usage error.

set -e

usage="Usage: scratch-db.sh register <pgsql|mysql|sqlite> <database> [<worktree>|-] | unregister <database> | list [<worktree>] | drop <database> | drop-selected <connection>@<host>:<port> <database> | plan [--worktree <path>]..."
need_jq() { command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }; }

git_common_dir() {  # absolute <git-common-dir>, without --path-format (Git 2.31+)
  local d
  d=$(git rev-parse --git-common-dir) || return 1
  (cd "$d" && pwd -P)
}
main_checkout() { git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }'; }

registry="$(git_common_dir)/scratch-databases"
main=$(main_checkout)

# --- env files ------------------------------------------------------------------------

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
protected_set() {
  local f w
  {
    env_dbs "$main" | awk -v owner=MAIN 'NF { print owner "\t" $0 }'
    for f in "$main/phpunit.xml" "$main/phpunit.xml.dist"; do
      [ -f "$f" ] && awk '
        { buf = buf " " $0 }
        END {
          while (match(buf, /<[A-Za-z]+[[:space:]][^>]*>/)) {   # <env>, and <server>/<var> (Laravel <= 7)
            tag = substr(buf, RSTART, RLENGTH)
            buf = substr(buf, RSTART + RLENGTH)
            if (tag ~ /[[:space:]]name[[:space:]]*=[[:space:]]*("DB_DATABASE"|\047DB_DATABASE\047)/) {
              if (match(tag, /[[:space:]]value[[:space:]]*=[[:space:]]*"[^"]*"/)) {
                v = substr(tag, RSTART, RLENGTH)
                sub(/^[^"]*"/, "", v); sub(/"$/, "", v)
                if (v != "") print "MAIN\t" v
              } else if (match(tag, /[[:space:]]value[[:space:]]*=[[:space:]]*\047[^\047]*\047/)) {
                v = substr(tag, RSTART, RLENGTH)
                sub(/^[^\047]*\047/, "", v); sub(/\047$/, "", v)
                if (v != "") print "MAIN\t" v
              }
            }
          }
        }' "$f"
    done
    git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10) }' | while IFS= read -r w; do
      [ "$w" = "$main" ] || env_dbs "$w" | OWNER="$w" awk 'NF { print ENVIRON["OWNER"] "\t" $0 }'
    done
  } | awk -F'\t' '$2 != ""'
}

# is_protected <protected set> <db> <owner whose names do not count, or "">: true when the set
# names it, or it is a parallel-testing copy of a name in the set. Literal comparison only.
is_protected() {
  printf '%s\n' "$1" | D="$2" W="$3" awk -F'\t' '
    BEGIN { d = ENVIRON["D"]; w = ENVIRON["W"] }
    $1 != w && $2 != "" && (d == $2 || (substr(d, 1, length($2) + 6) == $2 "_test_" && substr(d, length($2) + 7) ~ /^[0-9]+$/)) { f = 1 }
    END { exit !f }'
}

# --- servers --------------------------------------------------------------------------
# A server is one string, "host<US>port<US>user<US>password" (US is the 0x1f unit separator,
# which no env value holds), passed explicitly to every function that talks to it.

US=$'\x1f'
srv() { printf '%s' "$1$US$2$US$3$US$4"; }   # srv <host> <port> <user> <password>
srv_host() { local h _r; IFS=$US read -r h _r <<< "$1"; printf '%s' "$h"; }
srv_port() { local _h p _r; IFS=$US read -r _h p _r <<< "$1"; printf '%s' "$p"; }

srv_default() {  # srv_default <connection>
  if [ "$1" = pgsql ]; then srv 127.0.0.1 5432 root ""; else srv 127.0.0.1 3306 root ""; fi
}

srv_from() {  # srv_from <connection> <env file>: the server it names; 1 when the file is not on that connection
  local h p u v
  [ "$(env_get "$2" DB_CONNECTION)" = "$1" ] || return 1
  h=127.0.0.1; u=root
  if [ "$1" = pgsql ]; then p=5432; else p=3306; fi
  v=$(env_get "$2" DB_HOST); [ -z "$v" ] || h=$v
  v=$(env_get "$2" DB_PORT); [ -z "$v" ] || p=$v
  v=$(env_get "$2" DB_USERNAME); [ -z "$v" ] || u=$v
  srv "$h" "$p" "$u" "$(env_get "$2" DB_PASSWORD)"
}

# The first of these env files that uses the connection, else the defaults.
srv_for() {  # srv_for <connection> <env files...>
  local conn=$1 f; shift
  for f in "$@"; do
    if srv_from "$conn" "$f"; then return 0; fi
  done
  srv_default "$conn"
}

# One recorded server: the first env file on that connection whose host and port are exactly
# the recorded ones; or the defaults, when no env file is on that connection at all and the
# defaults are that server (what `register` recorded then). Prints the recorded host and
# port with no credentials, and returns 1, when nothing here reaches it: the caller then
# refuses, and never falls back to another server.
srv_reaching() {  # srv_reaching <connection> <host> <port> <env files...>
  local conn=$1 h=$2 p=$3 f s used=0; shift 3
  for f in "$@"; do
    s=$(srv_from "$conn" "$f") || continue
    used=1
    if [ "$(srv_host "$s")" = "$h" ] && [ "$(srv_port "$s")" = "$p" ]; then printf '%s' "$s"; return 0; fi
  done
  s=$(srv_default "$conn")
  if [ "$used" = 0 ] && [ "$(srv_host "$s")" = "$h" ] && [ "$(srv_port "$s")" = "$p" ]; then printf '%s' "$s"; return 0; fi
  srv "$h" "$p" "" ""
  return 1
}

is_local_host() { case "$1" in 127.0.0.1|localhost|::1) return 0 ;; esac; return 1; }

sql() {  # sql <connection> <server> <statement>
  local h p u pw
  IFS=$US read -r h p u pw <<< "$2"
  case "$1" in
    pgsql) PGPASSWORD="$pw" psql -h "$h" -p "$p" -U "$u" -d postgres -Atqc "$3" ;;
    mysql) MYSQL_PWD="$pw" mysql -h "$h" -P "$p" -u "$u" -N -B -e "$3" ;;
    *) return 1 ;;
  esac
}

# A client that fails returns 1 here, never an empty listing: the mysql output is taken
# first and reshaped after, because a pipeline would report only the last command.
server_dbs() {  # server_dbs <connection> <server>: "name size" per line
  local rows
  case "$1" in
    pgsql) sql pgsql "$2" "SELECT datname || ' ' || pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE NOT datistemplate" ;;
    mysql)
      rows=$(sql mysql "$2" "SELECT schema_name, '-' FROM information_schema.schemata") || return 1
      printf '%s\n' "$rows" | tr '\t' ' ' ;;
    *) return 1 ;;
  esac
}

# Split a registry connection field into "connection<TAB>host<TAB>port" (host and port empty
# on a line with no recorded server). The port is what follows the last colon (IPv6 works).
split_field() {  # split_field <connection>[@<host>:<port>]
  local c=${1%%@*} h="" p=""
  case "$1" in *@*:*) h=${1#*@}; p=${h##*:}; h=${h%:*} ;; esac
  printf '%s\t%s\t%s' "$c" "$h" "$p"
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

registry_cleanup() {  # the EXIT trap: this process's temp file and lock only
  [ -z "$registry_tmp" ] || rm -f "$registry_tmp"
  registry_tmp=""
  registry_unlock
}
trap registry_cleanup EXIT

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

registry_remove() {  # registry_remove <connection|""> <db>: delete its registry lines (all connections when "")
  local c=${1%%@*} d=$2 rc=0
  [ -f "$registry" ] || return 0
  registry_lock || return 1
  if [ -f "$registry" ]; then
    registry_tmp=$(mktemp "$registry.XXXXXX") || rc=1
    if [ "$rc" = 0 ]; then
      { awk -F'\t' -v c="$c" -v d="$d" '{ x = $2; sub(/@.*/, "", x) } !(($3 == d) && (c == "" || x == c))' "$registry" > "$registry_tmp" && mv "$registry_tmp" "$registry"; } || rc=1
      rm -f "$registry_tmp"; registry_tmp=""
    fi
  fi
  registry_unlock
  return $rc
}

registry_lines() {  # registry_lines <db>: "connection field<TAB>worktree" per registry line for it
  [ -f "$registry" ] || return 0
  awk -F'\t' -v d="$1" '$3 == d { print $2 "\t" $4 }' "$registry"
}

# --- the drop pipeline ---------------------------------------------------------------------

# drop_on <protected set> <connection> <recorded host|""> <recorded port|""> <worktree|-> <copies 0|1> <db>
# Resolves the server, proves every name may go, DROPs it, and unregisters it. With copies=1
# it also drops each <db>_test_<N> the server lists. Prints one result line per name:
# "dropped<TAB>name" or "kept<TAB>name<TAB>reason"; never fails.
drop_on() {
  local prot=$1 conn=$2 rhost=$3 rport=$4 wt=$5 copies=$6 db=$7 s reached=1 host all names d stmt
  trap registry_cleanup EXIT   # it runs in a command substitution, which has no EXIT trap of its own
  case "$conn" in
    pgsql|mysql) ;;
    sqlite) printf 'kept\t%s\t%s\n' "$db" "sqlite database is a file in the worktree: delete the file, then run scratch-db.sh unregister"; return 0 ;;
    *) printf 'kept\t%s\t%s\n' "$db" "connection $conn is not pgsql or mysql"; return 0 ;;
  esac
  if is_protected "$prot" "$db" ""; then printf 'kept\t%s\t%s\n' "$db" "used by the main checkout or a remaining worktree"; return 0; fi
  local envs=("$main/.env" "$main/.env.testing")
  [ "$wt" = "-" ] || envs=("$wt/.env" "$wt/.env.testing" "${envs[@]}")
  if [ -n "$rhost" ]; then
    s=$(srv_reaching "$conn" "$rhost" "$rport" "${envs[@]}") || reached=0
  else
    s=$(srv_for "$conn" "${envs[@]}")
  fi
  host=$(srv_host "$s")
  is_local_host "$host" || { printf 'kept\t%s\t%s\n' "$db" "database host $host is not local"; return 0; }
  [ "$reached" = 1 ] || { printf 'kept\t%s\t%s\n' "$db" "registered on $rhost:$rport, and no .env of its worktree or the main checkout reaches that server: drop it there by hand, then run scratch-db.sh unregister"; return 0; }
  names=$db
  if [ "$copies" = 1 ]; then
    all=$(server_dbs "$conn" "$s" 2>/dev/null) || { printf 'kept\t%s\t%s\n' "$db" "could not list the $conn databases on $host:$(srv_port "$s")"; return 0; }
    # The named database first (DROP IF EXISTS, so one already gone clears its registry
    # line), then each copy the server lists.
    names=$db$'\n'$(printf '%s\n' "$all" | awk -v d="$db" '$1 ~ ("^" d "_test_[0-9]+$") { print $1 }' | sort -u)
  fi
  while read -r d; do
    [ -n "$d" ] || continue
    if is_protected "$prot" "$d" ""; then printf 'kept\t%s\t%s\n' "$d" "used by the main checkout or a remaining worktree"; continue; fi
    case "$conn" in
      pgsql) stmt="DROP DATABASE IF EXISTS \"$d\"" ;;
      mysql) stmt="DROP DATABASE IF EXISTS \`$d\`" ;;
    esac
    if sql "$conn" "$s" "$stmt" >&2; then
      echo ">> dropped $conn database $d" >&2
      registry_remove "$conn" "$d" || echo ">> $d is dropped, but its registry line stays: run scratch-db.sh unregister $d" >&2
      printf 'dropped\t%s\n' "$d"
    else
      printf 'kept\t%s\t%s\n' "$d" "drop failed (open connections?)"
    fi
  done <<< "$names"
}

kept_line() { printf 'kept\t%s\t%s\n' "$1" "$2"; }   # kept_line <db> <reason>: one drop_on result line

# Print {"dropped","kept"} from drop_on's result lines, and exit 0 when <db> was dropped.
finish_drop() {  # finish_drop <db> <result lines>
  printf '%s' "$2" | awk -F'\t' '$1 == "kept" { print ">> kept " $2 ": " $3 }' >&2
  printf '%s' "$2" | jq -R -s -c '[split("\n")[] | select(length > 0) | split("\t")]
    | {dropped: [.[] | select(.[0] == "dropped") | .[1]], kept: [.[] | select(.[0] == "kept") | {database: .[1], reason: .[2]}]}'
  printf '%s' "$2" | awk -F'\t' -v d="$1" '$1 == "dropped" && $2 == d { f = 1 } END { exit !f }' || exit 1
  exit 0
}

# --- plan: leftover databases (read-only) ----------------------------------------------------

plan() {
  local prot wts=() w f c d src size s conn rhost rport cand_keys="" recent="" registered="" now stale
  local -a cands=() kept=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --worktree) [ -n "${2:-}" ] || { echo "plan: --worktree needs a path" >&2; exit 2; }; wts+=("$2"); shift ;;
      *) echo "plan: unknown arg $1" >&2; exit 2 ;;
    esac
    shift
  done
  prot=$(protected_set)

  # add <connection> <db> <worktree> <source> <size> <server>: once per connection and name
  add() {
    case "$cand_keys" in *$'\n'"$1"$'\t'"$2"$'\n'*) return 0 ;; esac
    cand_keys="$cand_keys"$'\n'"$1"$'\t'"$2"$'\n'
    cands+=("$(jq -n -c --arg c "$1" --arg d "$2" --arg w "$3" --arg src "$4" --arg s "$5" --arg srv "$6" \
      '{connection: $c, database: $d, size: $s, source: $src, worktree: $w, server: $srv}')")
  }
  keep() { kept+=("$(jq -n -c --arg p "$1" --arg r "$2" '{path: $p, reason: $r}')"); }

  # A database and its parallel-testing copies, each a candidate unless something uses it.
  # A registry line that records its server is looked up there and nowhere else.
  plan_db() {  # plan_db <connection field> <db> <worktree> <source> <env files...>
    local field=$1 db=$2 wt=$3 src=$4 reached=1 all host port conn rhost rport s d size
    IFS=$'\t' read -r conn rhost rport <<< "$(split_field "$field")"; shift 4
    case "$conn" in pgsql|mysql) ;; *) return 0 ;; esac   # sqlite files live in the worktree
    [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || return 0
    if is_protected "$prot" "$db" "$wt"; then keep "$db" "used by the main checkout or a remaining worktree"; return 0; fi
    if [ -n "$rhost" ]; then s=$(srv_reaching "$conn" "$rhost" "$rport" "$@") || reached=0; else s=$(srv_for "$conn" "$@"); fi
    host=$(srv_host "$s"); port=$(srv_port "$s")
    is_local_host "$host" || { keep "$db" "database host $host is not local"; return 0; }
    [ "$reached" = 1 ] || { keep "$db" "registered on $rhost:$rport, which no .env here reaches"; return 0; }
    all=$(server_dbs "$conn" "$s" 2>/dev/null) || return 0
    while read -r d size; do
      [[ "$d" =~ ^${db}(_test_[0-9]+)?$ ]] || continue
      is_protected "$prot" "$d" "$wt" || add "$conn" "$d" "$wt" "$src" "$size" "$conn@$host:$port"
    done <<< "$all"
  }

  # Each worktree about to go: registry lines first (they may record the server), then its
  # env files' names; one per connection and database.
  for w in ${wts[@]+"${wts[@]}"}; do
    while IFS=$'\t' read -r c d; do
      [ -n "$d" ] && plan_db "$c" "$d" "$w" worktree "$w/.env" "$w/.env.testing" "$main/.env" "$main/.env.testing"
    done < <({
      [ -f "$registry" ] && awk -F'\t' -v w="$w" '$4 == w { print $2 "\t" $3 }' "$registry"
      for f in .env .env.testing; do
        c=$(env_get "$w/$f" DB_CONNECTION); d=$(env_get "$w/$f" DB_DATABASE)
        [ -n "$d" ] && printf '%s\t%s\n' "$c" "$d"
      done
    } | awk -F'\t' '{ c = $1; sub(/@.*/, "", c) } !seen[c FS $2]++')
  done

  # Registry lines a run left behind: 12 hours old, with no worktree or a gone one.
  if [ -f "$registry" ]; then
    now=$(date +%s)
    recent=$(awk -F'\t' -v now="$now" '$1 >= now - 43200 { print $3 }' "$registry")
    stale=$(awk -F'\t' -v now="$now" '$1 < now - 43200 { print $2 "\t" $3 "\t" $4 }' "$registry")
    while IFS=$'\t' read -r c d w; do
      [ -n "$d" ] || continue
      [ "$w" = "-" ] || [ ! -d "$w" ] || continue
      plan_db "$c" "$d" "$w" registry "$main/.env" "$main/.env.testing"
    done <<< "$stale"
    registered=$(cut -f3 "$registry")
  fi

  # A line matches <db> when it names it, or <db> is its parallel-testing copy <line>_test_<N>.
  # Literal comparison: a name is never a regex, so foo(bar cannot make awk fail open.
  # shellcheck disable=SC2016  # an awk program, not a shell expansion
  local copy_of='BEGIN { d = ENVIRON["D"] }
    $0 != "" && (d == $0 || (substr(d, 1, length($0) + 6) == $0 "_test_" && substr(d, length($0) + 7) ~ /^[0-9]+$/)) { f = 1 }
    END { exit !f }'
  # A name a registry line holds is never an orphan: an old line with no worktree is a
  # "registry" candidate above, and any other line means a run or a worktree still owns it.
  named_in() { [ -n "$1" ] && printf '%s\n' "$1" | D="$2" awk "$copy_of"; }

  # The names the skills give a scratch database, after "<app db>_" (rg "<app db>_" skills):
  # triage-github-pr pr<N> and pr<N>_fix<k>, fix-github-issues issues_<run>, sweep
  # sweep_<topic>, implement-spec spec_<slug>_<NN> and spec_<slug>_fix<k>; each may carry
  # Laravel's parallel-testing suffix _test_<N>.
  local skill_name='(pr[0-9]+(_fix[0-9]+)?|issues_[A-Za-z0-9_]+|sweep_[A-Za-z0-9_]+|spec_[A-Za-z0-9_]+)(_test_[0-9]+)?'
  local seen="" prefixes p host port all
  prefixes=$(printf '%s\n' "$prot" | awk -F'\t' '$1 == "MAIN" { print $2 }' | sort -u)
  for f in "$main/.env" "$main/.env.testing"; do
    conn=$(env_get "$f" DB_CONNECTION)
    case "$conn" in pgsql|mysql) ;; *) continue ;; esac
    case " $seen " in *" $conn "*) continue ;; esac; seen="$seen $conn"
    s=$(srv_for "$conn" "$f"); host=$(srv_host "$s"); port=$(srv_port "$s")
    is_local_host "$host" || continue
    all=$(server_dbs "$conn" "$s" 2>/dev/null) || continue
    while read -r d size; do
      [ -n "$d" ] || continue
      for p in $prefixes; do
        case "$d" in "${p}_"*)
          if ! is_protected "$prot" "$d" "" && ! named_in "$recent" "$d" && ! named_in "$registered" "$d"; then
            if [[ "$d" =~ ^${p}_${skill_name}$ ]]; then src=orphan; else src=prefix-only; fi
            add "$conn" "$d" - "$src" "$size" "$conn@$host:$port"
          fi
          break ;;
        esac
      done
    done <<< "$all"
  done

  jq -n -c --argjson d "$(if [ ${#cands[@]} -eq 0 ]; then echo '[]'; else printf '%s\n' "${cands[@]}" | jq -s -c .; fi)" \
    --argjson k "$(if [ ${#kept[@]} -eq 0 ]; then echo '[]'; else printf '%s\n' "${kept[@]}" | jq -s -c .; fi)" \
    '{databases: $d, kept: $k}'
}

# --- commands ------------------------------------------------------------------------------

case "${1:-}" in
  register)
    conn=${2:-}; db=${3:-}; wt=${4:--}
    case "$conn" in pgsql|mysql|sqlite) ;; *) echo "register: connection must be pgsql, mysql or sqlite" >&2; exit 2 ;; esac
    [ -n "$db" ] || { echo "register: database name required" >&2; exit 2; }
    if [ "$wt" != "-" ]; then wt=$(cd "$wt" && pwd -P); fi
    field=$conn
    if [ "$conn" != sqlite ]; then
      if [ "$wt" = "-" ]; then s=$(srv_for "$conn" "$main/.env" "$main/.env.testing")
      else s=$(srv_for "$conn" "$wt/.env" "$wt/.env.testing" "$main/.env" "$main/.env.testing"); fi
      field="$conn@$(srv_host "$s"):$(srv_port "$s")"
    fi
    rc=0; registry_add "$field" "$db" "$wt" || rc=$?
    case "$rc" in
      0) echo ">> registered $field database $db ($wt)" >&2 ;;
      3) echo ">> $conn database $db already registered" >&2 ;;
      *) echo "register: could not write $registry" >&2; exit 1 ;;
    esac
    ;;
  unregister)
    db=${2:-}
    [ -n "$db" ] || { echo "unregister: database name required" >&2; exit 2; }
    [ -f "$registry" ] || exit 0
    registry_remove "" "$db" || { echo "unregister: could not write $registry" >&2; exit 1; }
    echo ">> unregistered $db" >&2
    ;;
  list)
    need_jq
    wt=${2:-}
    if [ -n "$wt" ] && [ -d "$wt" ]; then wt=$(cd "$wt" && pwd -P); fi
    if [ -f "$registry" ]; then cat "$registry"; fi | jq -R -s -c --arg wt "$wt" '
      [ split("\n")[] | split("\t") | select((.[2] // "") != "")
        | {connection: (.[1] | sub("@.*$"; "")), database: .[2], worktree: (.[3:] | join("\t"))}
        | select($wt == "" or .worktree == $wt) ]'
    ;;
  drop)
    need_jq
    db=${2:-}
    [ -n "$db" ] && [ $# -eq 2 ] || { echo "drop: exactly one database name required" >&2; exit 2; }
    [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || finish_drop "$db" "$(kept_line "$db" "name is not [A-Za-z0-9_]+")"
    lines=$(registry_lines "$db")
    [ -n "$lines" ] || finish_drop "$db" "$(kept_line "$db" "not in the scratch-database registry, so nothing proves a run created it")"
    prot=$(protected_set)
    results=""
    while IFS=$'\t' read -r field wt; do
      IFS=$'\t' read -r conn rhost rport <<< "$(split_field "$field")"
      results="$results$(drop_on "$prot" "$conn" "$rhost" "$rport" "$wt" 1 "$db")"$'\n'
    done <<< "$lines"
    finish_drop "$db" "$results"
    ;;
  drop-selected)
    need_jq
    server=${2:-}; db=${3:-}
    [ $# -eq 3 ] && [ -n "$db" ] || { echo "drop-selected: <connection>@<host>:<port> <database> required" >&2; exit 2; }
    IFS=$'\t' read -r conn host port <<< "$(split_field "$server")"
    case "$conn" in pgsql|mysql) ;; *) echo "drop-selected: connection must be pgsql or mysql" >&2; exit 2 ;; esac
    [ -n "$host" ] && [ -n "$port" ] || { echo "drop-selected: name the server as <connection>@<host>:<port>" >&2; exit 2; }
    [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || finish_drop "$db" "$(kept_line "$db" "name is not [A-Za-z0-9_]+")"
    # A registry line on this connection says which worktree it belonged to, and, when it
    # records a server, that server must be the named one.
    wt=-
    while IFS=$'\t' read -r field w; do
      [ -n "$field" ] || continue
      IFS=$'\t' read -r c rh rp <<< "$(split_field "$field")"
      [ "$c" = "$conn" ] || continue
      if [ -n "$rh" ] && { [ "$rh" != "$host" ] || [ "$rp" != "$port" ]; }; then
        finish_drop "$db" "$(kept_line "$db" "registered on $rh:$rp, not on $host:$port")"
      fi
      [ "$w" = "-" ] || wt=$w
    done <<< "$(registry_lines "$db")"
    finish_drop "$db" "$(drop_on "$(protected_set)" "$conn" "$host" "$port" "$wt" 0 "$db")"
    ;;
  plan)
    need_jq
    shift
    plan "$@"
    ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
esac
