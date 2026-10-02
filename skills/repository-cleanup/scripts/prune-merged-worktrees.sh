#!/bin/bash
# Remove git worktrees whose pull request has merged, when nothing in them can be lost,
# and drop the scratch databases created for them.
#
# A linked worktree is removed only when every check holds:
#   - its HEAD is the head of a merged PR, or an ancestor of it. A worktree on a branch
#     must match a merged PR from that same branch; a detached worktree must sit
#     exactly on a merged PR's head commit.
#   - `git status` shows no modified or untracked files (ignored files such as vendor/
#     and node_modules/ go with it). `git worktree remove` runs without --force, so git
#     refuses a dirty tree a second time.
#   - it is not locked, and it is not the checkout this script runs from.
# Local branches stay; only the directory goes.
#
# Databases dropped after a worktree is removed (pgsql and mysql, local hosts only):
#   - every database registered for that worktree in <git-common-dir>/scratch-databases
#     (lines: epoch<TAB>connection<TAB>database<TAB>worktree path, or "-" for none)
#   - the DB_DATABASE of the worktree's .env and .env.testing
#   - the parallel-testing copies of each: <database>_test_<N>
# Registry lines with no worktree, or whose worktree directory is gone, are dropped once
# they are 12 hours old. A database named by the main checkout's .env, .env.testing, or
# phpunit.xml(.dist), or by a remaining worktree's .env or .env.testing, is never dropped,
# nor is a parallel-testing copy of one.
#
# Usage: prune-merged-worktrees.sh [--dry-run] [--orphan-databases]
#   --dry-run  report what would be removed and dropped, change nothing
#   --orphan-databases  list, never drop, local databases named <app db>_* that no checkout
#              uses (leftovers of removed worktrees and one-off test runs), as JSON
#              [{"connection","database","size"}]; touches no worktree and needs no gh
#
# Output (default): JSON {"removed":[paths],"dropped":[databases],"kept":[{"path","reason"}]} on
# stdout. "kept" lists only worktrees and databases a check protected.

set -e

DRY_RUN=0
ORPHANS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --orphan-databases) ORPHANS=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

main=$(git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }')
common=$(git rev-parse --path-format=absolute --git-common-dir)
registry="$common/scratch-databases"
here=$(pwd -P)

removed=()
dropped=()
kept=()

# --- databases ------------------------------------------------------------------

env_get() {  # env_get <file> <KEY>: value with surrounding quotes stripped
  [ -f "$1" ] || return 0
  grep -E "^$2=" "$1" | tail -n 1 | cut -d= -f2- | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

env_dbs() {  # env_dbs <dir>: the DB_DATABASE of its .env and .env.testing
  local f
  for f in "$1/.env" "$1/.env.testing"; do env_get "$f" DB_DATABASE; done
}

# Databases nothing may drop: the main checkout's, then each worktree's under its path.
protected=$( {
  env_dbs "$main" | sed 's/^/MAIN\t/'
  for f in "$main/phpunit.xml" "$main/phpunit.xml.dist"; do
    [ -f "$f" ] && sed -n 's/.*name="DB_DATABASE"[^>]*value="\([^"]*\)".*/MAIN\t\1/p' "$f"
  done
  git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10) }' | while read -r w; do
    [ "$w" = "$main" ] || env_dbs "$w" | sed "s|^|$w\t|"
  done
} | awk -F'\t' '$2 != ""' )

is_protected() {  # is_protected <db> <worktree being removed>: named, or a parallel-testing copy of one
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
  [ -n "$port" ] || { [ "$conn" = pgsql ] && port=5432 || port=3306; }
}

sql() {  # sql <connection> <statement>; uses host port user pass
  case "$1" in
    pgsql) PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d postgres -Atqc "$2" ;;
    mysql) MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -N -B -e "$2" ;;
  esac
}

drop_db() {  # drop_db <connection> <db> <worktree being removed> <env files...>
  local conn=$1 db=$2 wt=$3 d all; shift 3
  case "$conn" in pgsql|mysql) ;; *) return 0 ;; esac   # sqlite files live in the worktree
  [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || return 0
  is_protected "$db" "$wt" && return 0   # shared with the main checkout or a remaining worktree
  creds_for "$conn" "$@"
  case "$host" in 127.0.0.1|localhost|::1) ;; *)
    kept+=("{\"path\":\"$db\",\"reason\":\"database host $host is not local\"}"); return 0 ;;
  esac
  case "$conn" in
    pgsql) all=$(sql pgsql "SELECT datname FROM pg_database" 2>/dev/null) || return 0 ;;
    mysql) all=$(sql mysql "SHOW DATABASES" 2>/dev/null) || return 0 ;;
  esac
  for d in $(printf '%s\n' "$all" | grep -E "^${db}(_test_[0-9]+)?$"); do
    is_protected "$d" "$wt" && continue
    if [ "$DRY_RUN" -eq 1 ]; then
      echo ">> would drop $conn database $d" >&2; dropped+=("\"$d\"")
    elif case "$conn" in pgsql) sql pgsql "DROP DATABASE IF EXISTS \"$d\"" ;; mysql) sql mysql "DROP DATABASE IF EXISTS \`$d\`" ;; esac; then
      echo ">> dropped $conn database $d" >&2; dropped+=("\"$d\"")
    else
      kept+=("{\"path\":\"$d\",\"reason\":\"drop failed (open connections?)\"}")
    fi
  done
}

forget() {  # forget <db> <worktree>: delete matching registry lines
  [ "$DRY_RUN" -eq 0 ] && [ -f "$registry" ] || return 0
  awk -F'\t' -v d="$1" -v w="$2" '!($3 == d && $4 == w)' "$registry" > "$registry.tmp" && mv "$registry.tmp" "$registry"
}

if [ "$ORPHANS" -eq 1 ]; then
  out=()
  for f in "$main/.env" "$main/.env.testing"; do
    conn=$(env_get "$f" DB_CONNECTION)
    case "$conn" in pgsql|mysql) ;; *) continue ;; esac
    case " ${seen:-} " in *" $conn "*) continue ;; esac; seen="${seen:-} $conn"
    creds_for "$conn" "$f"
    case "$host" in 127.0.0.1|localhost|::1) ;; *) continue ;; esac
    case "$conn" in
      pgsql) all=$(sql pgsql "SELECT datname || ' ' || pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE NOT datistemplate" 2>/dev/null) || continue ;;
      mysql) all=$(sql mysql "SELECT schema_name, '-' FROM information_schema.schemata" 2>/dev/null | tr '\t' ' ') || continue ;;
    esac
    prefixes=$(printf '%s\n' "$protected" | awk -F'\t' '$1 == "MAIN" { print $2 }' | sort -u)
    while read -r d size; do
      [ -n "$d" ] || continue
      for p in $prefixes; do
        case "$d" in "${p}_"*)
          is_protected "$d" "" || out+=("{\"connection\":\"$conn\",\"database\":\"$d\",\"size\":\"$size\"}")
          break ;;
        esac
      done
    done <<< "$all"
  done
  join() { local IFS=,; echo "$*"; }
  echo "[$(join "${out[@]}")]"
  exit 0
fi

# --- worktrees ------------------------------------------------------------------

echo ">> Fetching merged PRs" >&2
merged=$(gh pr list --state merged --limit 300 --json headRefName,headRefOid \
  --jq '.[] | "\(.headRefName)\t\(.headRefOid)"') || { echo "gh pr list failed; no worktree removed" >&2; merged=""; }

# One tab-separated line per linked worktree (the main worktree is skipped): path, HEAD,
# branch, flags. Empty fields become "-" because read collapses adjacent tabs.
worktrees=$(git worktree list --porcelain | awk '
  function flush() { if (p != "") { if (n++) print p "\t" (h ? h : "-") "\t" (b ? b : "-") "\t" (f ? f : "-"); p = "" } }
  /^worktree / { flush(); p = substr($0, 10); h = ""; b = ""; f = "" }
  /^HEAD /     { h = $2 }
  /^branch /   { b = substr($0, 8); sub("^refs/heads/", "", b) }
  /^locked/    { f = f "locked," }
  /^prunable/  { f = f "prunable," }
  END { flush() }')

while IFS=$'\t' read -r path head branch flags; do
  [ -n "$path" ] || continue
  case "$flags" in *prunable*) continue ;; esac   # directory already gone; `git worktree prune` below

  match=0
  if [ "$branch" = "-" ]; then
    printf '%s\n' "$merged" | awk -F'\t' -v h="$head" '$2 == h { found = 1 } END { exit !found }' && match=1
  else
    for oid in $(printf '%s\n' "$merged" | awk -F'\t' -v b="$branch" '$1 == b { print $2 }'); do
      if [ "$head" = "$oid" ] || git merge-base --is-ancestor "$head" "$oid" 2>/dev/null; then match=1; break; fi
    done
  fi
  [ -n "$merged" ] && [ "$match" -eq 1 ] || continue

  reason=""
  real=$(cd "$path" 2>/dev/null && pwd -P) || real="$path"
  case "$here/" in "$real/"*) reason="current checkout" ;; esac
  case "$flags" in *locked*) reason="locked" ;; esac
  if [ -z "$reason" ] && [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    reason="uncommitted or untracked changes"
  fi
  if [ -n "$reason" ]; then
    echo ">> keep $path ($reason)" >&2
    kept+=("{\"path\":\"$path\",\"reason\":\"$reason\"}")
    continue
  fi

  # Read the databases before the .env files go with the directory.
  stash=$(mktemp -d); trap 'rm -rf "$stash"' EXIT
  for f in .env .env.testing; do [ -f "$path/$f" ] && cp "$path/$f" "$stash/$f"; done
  dbs=$( {
    for f in .env .env.testing; do
      c=$(env_get "$stash/$f" DB_CONNECTION); d=$(env_get "$stash/$f" DB_DATABASE)
      [ -n "$d" ] && printf '%s\t%s\n' "$c" "$d"
    done
    [ -f "$registry" ] && awk -F'\t' -v w="$path" '$4 == w { print $2 "\t" $3 }' "$registry"
  } | sort -u )

  if [ "$DRY_RUN" -eq 1 ]; then
    echo ">> would remove $path (${branch/#-/detached})" >&2
  elif git -C "$main" worktree remove "$path" >&2; then
    echo ">> removed $path (${branch/#-/detached})" >&2
  else
    kept+=("{\"path\":\"$path\",\"reason\":\"git worktree remove refused\"}")
    rm -rf "$stash"; continue
  fi
  removed+=("\"$path\"")

  while IFS=$'\t' read -r c d; do
    [ -n "$d" ] || continue
    drop_db "$c" "$d" "$path" "$stash/.env" "$stash/.env.testing" "$main/.env" "$main/.env.testing"
    forget "$d" "$path"
  done <<< "$dbs"
  rm -rf "$stash"
done <<< "$worktrees"

[ "$DRY_RUN" -eq 1 ] || git -C "$main" worktree prune

# Registry lines a run left behind: no worktree, or its directory is gone, 12 hours on.
if [ -f "$registry" ]; then
  now=$(date +%s)
  stale=$(awk -F'\t' -v now="$now" '$1 < now - 43200 { print $2 "\t" $3 "\t" $4 }' "$registry")
  while IFS=$'\t' read -r c d w; do
    [ -n "$d" ] || continue
    [ "$w" = "-" ] || [ ! -d "$w" ] || continue
    drop_db "$c" "$d" "$w" "$main/.env" "$main/.env.testing"
    forget "$d" "$w"
  done <<< "$stale"
fi

join() { local IFS=,; echo "$*"; }
echo "{\"removed\":[$(join "${removed[@]}")],\"dropped\":[$(join "${dropped[@]}")],\"kept\":[$(join "${kept[@]}")]}"
