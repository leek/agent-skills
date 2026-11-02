#!/bin/bash
# Keep the scratch-database registry, <git-common-dir>/scratch-databases, that every skill
# creating a worktree or a throwaway database writes, and repository-cleanup reads.
# One line per database: epoch<TAB>connection<TAB>database<TAB>worktree path, or "-" for none.
#
# Usage: scratch-db.sh register <pgsql|mysql|sqlite> <database> [<worktree path>|-]
#        scratch-db.sh unregister <database>      after the database was dropped
#        scratch-db.sh list [<worktree path>]     JSON [{"connection","database","worktree"}]
#
# Register the moment the database is created. Unregister only after a successful drop.

set -e

registry="$(git rev-parse --path-format=absolute --git-common-dir)/scratch-databases"
json_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

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
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    awk -F'\t' -v d="$db" '$3 != d' "$registry" > "$tmp" && cat "$tmp" > "$registry"
    echo ">> unregistered $db" >&2
    ;;
  list)
    wt=${2:-}
    if [ -n "$wt" ] && [ -d "$wt" ]; then wt=$(cd "$wt" && pwd -P); fi
    out=()
    if [ -f "$registry" ]; then
      while IFS=$'\t' read -r _ c d w; do
        [ -n "$d" ] || continue
        [ -z "$wt" ] || [ "$w" = "$wt" ] || continue
        out+=("{\"connection\":$(json_str "$c"),\"database\":$(json_str "$d"),\"worktree\":$(json_str "$w")}")
      done < "$registry"
    fi
    (IFS=,; echo "[${out[*]}]")
    ;;
  *)
    echo "Usage: scratch-db.sh register <pgsql|mysql|sqlite> <database> [<worktree>|-] | unregister <database> | list [<worktree>]" >&2
    exit 2
    ;;
esac
