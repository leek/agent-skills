#!/bin/bash
# Keep the scratch-database registry, <git-common-dir>/scratch-databases, that every skill
# creating a worktree or a throwaway database writes, and repository-cleanup reads; and drop
# a registered database once its run is done with it.
# One line per database: epoch<TAB>connection<TAB>database<TAB>worktree path, or "-" for none.
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
#   - a database host that is not local (127.0.0.1, localhost, ::1); credentials come from
#     the first of the worktree's and the main checkout's .env, .env.testing on that connection
#   - a server that cannot be listed, or a DROP that fails
# Output, drop: JSON {"dropped":[names],"kept":[{"database","reason"}]}
# Exit, drop: 0 when the named database was dropped, 1 when it was kept, 2 on a usage error.

set -e

here=$(cd "$(dirname "$0")" && pwd)
registry="$(git rev-parse --path-format=absolute --git-common-dir)/scratch-databases"
usage="Usage: scratch-db.sh register <pgsql|mysql|sqlite> <database> [<worktree>|-] | unregister <database> | list [<worktree>] | drop <database>"
need_jq() { command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }; }
# shellcheck source-path=SCRIPTDIR source=scratch-db-lib.sh
. "$here/scratch-db-lib.sh"
trap 'rm -f "$registry.tmp"' EXIT

case "${1:-}" in
  register)
    conn=${2:-}; db=${3:-}; wt=${4:--}
    case "$conn" in pgsql|mysql|sqlite) ;; *) echo "register: connection must be pgsql, mysql or sqlite" >&2; exit 2 ;; esac
    [ -n "$db" ] || { echo "register: database name required" >&2; exit 2; }
    if [ "$wt" != "-" ]; then wt=$(cd "$wt" && pwd -P); fi
    if [ -f "$registry" ] && awk -F'\t' -v c="$conn" -v d="$db" '$2 == c && $3 == d { f = 1 } END { exit !f }' "$registry"; then
      echo ">> $conn database $db already registered" >&2
    else
      printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$conn" "$db" "$wt" >> "$registry"
      echo ">> registered $conn database $db ($wt)" >&2
    fi
    ;;
  unregister)
    db=${2:-}
    [ -n "$db" ] || { echo "unregister: database name required" >&2; exit 2; }
    [ -f "$registry" ] || exit 0
    registry_remove "$db"
    echo ">> unregistered $db" >&2
    ;;
  list)
    need_jq
    wt=${2:-}
    if [ -n "$wt" ] && [ -d "$wt" ]; then wt=$(cd "$wt" && pwd -P); fi
    if [ -f "$registry" ]; then cat "$registry"; fi | jq -R -s -c --arg wt "$wt" '
      [ split("\n")[] | split("\t") | select((.[2] // "") != "")
        | {connection: .[1], database: .[2], worktree: (.[3:] | join("\t"))}
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

    main=$(git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }')
    # shellcheck disable=SC2034  # is_protected (scratch-db-lib.sh) reads it
    protected=$(db_protected_set)
    while IFS=$'\t' read -r conn wt; do
      case "$conn" in
        pgsql|mysql) ;;
        sqlite) keep "$db" "sqlite database is a file in the worktree: delete the file, then run scratch-db.sh unregister"; continue ;;
        *) keep "$db" "connection $conn is not pgsql or mysql"; continue ;;
      esac
      if is_protected "$db" ""; then keep "$db" "used by the main checkout or a remaining worktree"; continue; fi
      creds_for "$conn" "$wt/.env" "$wt/.env.testing" "$main/.env" "$main/.env.testing"
      # shellcheck disable=SC2154  # creds_for sets host
      is_local || { keep "$db" "database host $host is not local"; continue; }
      all=$(server_dbs "$conn" 2>/dev/null) || { keep "$db" "could not list the $conn databases on $host"; continue; }
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
