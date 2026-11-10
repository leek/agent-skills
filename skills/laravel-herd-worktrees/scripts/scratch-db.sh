#!/bin/bash
# Keep the scratch-database registry, <git-common-dir>/scratch-databases, that every skill
# creating a worktree or a throwaway database writes, and repository-cleanup reads; and drop
# a registered database once its run is done with it.
# One line per database: epoch<TAB>connection<TAB>database<TAB>worktree path, or "-" for none.
# For pgsql and mysql the connection field is <connection>@<host>:<port>: the server the
# database was created on, which `register` reads from the first of the worktree's and the
# main checkout's .env, .env.testing on that connection (the defaults when none is). A line
# written before servers were recorded holds the bare connection.
#
# Usage: scratch-db.sh register <pgsql|mysql|sqlite> <database> [<worktree path>|-]
#        scratch-db.sh unregister <database>      registry only; `drop` already does it
#        scratch-db.sh list [<worktree path>]     JSON [{"connection","database","worktree"}]
#        scratch-db.sh drop <database>            DROP it and its <database>_test_<N> copies
#
# Register the moment the database is created. Unregister only after a successful drop.
#
# drop is destructive: it runs DROP DATABASE IF EXISTS on the database and on each
# parallel-testing copy (<database>_test_<N>) the server lists, and unregisters what it
# dropped. A database already gone counts as dropped. It keeps, with a reason:
#   - a name that is not [A-Za-z0-9_]+
#   - a name with no registry line: the line is what proves a run created it
#   - a sqlite database: it is a file in the worktree, so delete the file, then unregister
#   - a name the main checkout's .env, .env.testing or phpunit.xml(.dist) uses, or a
#     remaining worktree's .env or .env.testing (so remove the worktree first), or a
#     parallel-testing copy of such a name
#   - a database host that is not local (127.0.0.1, localhost, ::1)
#   - a recorded server that no env file here reaches. The DROP goes only to the recorded
#     host and port, with the user and password of the first of the worktree's (when it is
#     still there) and the main checkout's .env, .env.testing on that connection, host and
#     port. So a database of a removed worktree that ran on another server than the main
#     checkout is kept: it is never dropped on the main checkout's server.
#     A line with no recorded server uses the first of those env files on that connection.
#   - a server that cannot be listed, or a DROP that fails
# Output, drop: JSON {"dropped":[names],"kept":[{"database","reason"}]}
# Exit, drop: 0 when the named database was dropped, 1 when it was kept, 2 on a usage error.

set -e

here=$(cd "$(dirname "$0")" && pwd)
usage="Usage: scratch-db.sh register <pgsql|mysql|sqlite> <database> [<worktree>|-] | unregister <database> | list [<worktree>] | drop <database>"
need_jq() { command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }; }
# shellcheck source-path=SCRIPTDIR source=scratch-db-lib.sh
. "$here/scratch-db-lib.sh"
registry="$(git_common_dir)/scratch-databases"
trap registry_cleanup EXIT
main_checkout() { git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }'; }

case "${1:-}" in
  register)
    conn=${2:-}; db=${3:-}; wt=${4:--}
    case "$conn" in pgsql|mysql|sqlite) ;; *) echo "register: connection must be pgsql, mysql or sqlite" >&2; exit 2 ;; esac
    [ -n "$db" ] || { echo "register: database name required" >&2; exit 2; }
    if [ "$wt" != "-" ]; then wt=$(cd "$wt" && pwd -P); fi
    field=$conn
    if [ "$conn" != sqlite ]; then
      main=$(main_checkout)
      if [ "$wt" = "-" ]; then creds_for "$conn" "$main/.env" "$main/.env.testing"
      else creds_for "$conn" "$wt/.env" "$wt/.env.testing" "$main/.env" "$main/.env.testing"; fi
      # shellcheck disable=SC2154  # creds_for sets host and port
      field="$conn@$host:$port"
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
    registry_remove "$db" || { echo "unregister: could not write $registry" >&2; exit 1; }
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
    dropped=""; kept=""   # one compact JSON value per line
    keep() { kept="$kept$(jq -n -c --arg d "$1" --arg r "$2" '{database: $d, reason: $r}')"$'\n'; echo ">> kept $1: $2" >&2; }
    finish() {
      jq -n -c --argjson dropped "$(printf '%s' "$dropped" | jq -s -c .)" --argjson kept "$(printf '%s' "$kept" | jq -s -c .)" \
        '{dropped: $dropped, kept: $kept}'
      printf '%s' "$dropped" | jq -e -s --arg d "$db" 'index($d) != null' >/dev/null || exit 1
      exit 0
    }

    [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || { keep "$db" "name is not [A-Za-z0-9_]+"; finish; }
    lines=""
    [ -f "$registry" ] && lines=$(awk -F'\t' -v d="$db" '$3 == d { print $2 "\t" $4 }' "$registry")
    [ -n "$lines" ] || { keep "$db" "not in the scratch-database registry, so nothing proves a run created it"; finish; }

    main=$(main_checkout)
    # shellcheck disable=SC2034  # is_protected (scratch-db-lib.sh) reads it
    protected=$(db_protected_set)
    while IFS=$'\t' read -r field wt; do
      split_conn_field "$field"   # sets conn, rhost and rport
      # shellcheck disable=SC2154
      case "$conn" in
        pgsql|mysql) ;;
        sqlite) keep "$db" "sqlite database is a file in the worktree: delete the file, then run scratch-db.sh unregister"; continue ;;
        *) keep "$db" "connection $conn is not pgsql or mysql"; continue ;;
      esac
      if is_protected "$db" ""; then keep "$db" "used by the main checkout or a remaining worktree"; continue; fi
      reached=1
      if [ -n "$rhost" ]; then
        creds_for_server "$conn" "$rhost" "$rport" "$wt/.env" "$wt/.env.testing" "$main/.env" "$main/.env.testing" || reached=0
      else
        creds_for "$conn" "$wt/.env" "$wt/.env.testing" "$main/.env" "$main/.env.testing"
      fi
      is_local || { keep "$db" "database host $host is not local"; continue; }
      [ "$reached" = 1 ] || { keep "$db" "registered on $rhost:$rport, and no .env of its worktree or the main checkout reaches that server: drop it there by hand, then run scratch-db.sh unregister"; continue; }
      all=$(server_dbs "$conn" 2>/dev/null) || { keep "$db" "could not list the $conn databases on $host:$port"; continue; }
      # The named database first (DROP IF EXISTS, so one already gone clears its registry line),
      # then each copy the server lists.
      names=$db$'\n'$(printf '%s\n' "$all" | awk -v d="$db" '$1 ~ ("^" d "_test_[0-9]+$") { print $1 }' | sort -u)
      while read -r d; do
        [ -n "$d" ] || continue
        if is_protected "$d" ""; then keep "$d" "used by the main checkout or a remaining worktree"; continue; fi
        if drop_database "$conn" "$d" >&2; then
          echo ">> dropped $conn database $d" >&2
          dropped="$dropped$(jq -n -c --arg d "$d" '$d')"$'\n'
        else
          keep "$d" "drop failed (open connections?)"
        fi
      done <<< "$names"
    done <<< "$lines"
    finish
    ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
esac
