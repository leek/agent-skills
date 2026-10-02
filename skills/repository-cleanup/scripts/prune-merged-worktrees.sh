#!/bin/bash
# List the git worktrees whose pull request has merged, and the scratch databases left
# behind, then remove only the ones a human selected by exact name.
#
# Run with no arguments, the script changes nothing: it prints the candidates (the plan).
# It removes a worktree only when --remove names its path, and drops a database only when
# --drop names it, and each name must be a candidate in the plan this same run computes.
# One name that is not a candidate stops the run before anything changes.
#
# A linked worktree is a candidate only when every check holds:
#   - its HEAD is the head of a merged PR, or an ancestor of it. A worktree on a branch
#     must match a merged PR from that same branch; a detached worktree must sit
#     exactly on a merged PR's head commit.
#   - `git status` shows no modified or untracked files (ignored files such as vendor/
#     and node_modules/ go with it). `git worktree remove` runs without --force, so git
#     refuses a dirty tree a second time.
#   - it is not locked, and it is not the checkout this script runs from.
# Local branches stay; only the directory goes.
#
# Candidate databases (pgsql and mysql, local hosts only), each listed by its exact name,
# parallel-testing copies (<database>_test_<N>) included as names of their own:
#   - source "worktree": registered for a candidate worktree in <git-common-dir>/scratch-databases
#     (lines: epoch<TAB>connection<TAB>database<TAB>worktree path, or "-" for none), or the
#     DB_DATABASE of its .env and .env.testing. Dropping one needs its worktree in --remove too.
#   - source "registry": a registry line 12 hours old with no worktree, or whose directory is gone
#   - source "orphan": a local database named <app db>_* that no checkout uses
# A database named by the main checkout's .env, .env.testing, or phpunit.xml(.dist), or by
# a remaining worktree's .env or .env.testing, is never a candidate, nor is a
# parallel-testing copy of one.
#
# Usage: prune-merged-worktrees.sh                          list candidates, change nothing
#        prune-merged-worktrees.sh [--remove <path>]... [--drop <connection>:<database>]...
#   --dry-run is accepted and does nothing extra: listing is already the default.
#
# Output, listing: JSON {"worktrees":[{"path","branch","databases":[names]}],
#   "databases":[{"connection","database","size","source","worktree"}],"kept":[{"path","reason"}]}
# Output, removing: JSON {"removed":[paths],"dropped":[databases],"kept":[{"path","reason"}]}
# "kept" lists only worktrees and databases a check protected or a removal refused.

set -e

remove_args=()
drop_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) ;;
    --remove) [ -n "${2:-}" ] || { echo "--remove needs a path" >&2; exit 2; }; remove_args+=("$2"); shift ;;
    --drop)   [ -n "${2:-}" ] || { echo "--drop needs <connection>:<database>" >&2; exit 2; }; drop_args+=("$2"); shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

main=$(git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }')
common=$(git rev-parse --path-format=absolute --git-common-dir)
registry="$common/scratch-databases"
here=$(pwd -P)

kept=()
wt_cands=()   # path<TAB>branch
db_cands=()   # connection<TAB>database<TAB>worktree<TAB>source<TAB>size<TAB>host<TAB>port<TAB>user<TAB>pass

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }
join() { local IFS=,; echo "$*"; }
keep() { kept+=("{\"path\":$(json_str "$1"),\"reason\":$(json_str "$2")}"); }

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

is_db_cand() {  # is_db_cand <connection> <db>
  local c
  for c in ${db_cands[@]+"${db_cands[@]}"}; do
    [ "$(printf '%s' "$c" | cut -f1-2)" = "$1	$2" ] && return 0
  done
  return 1
}

add_db_cand() {  # add_db_cand <connection> <db> <worktree> <source> <size>; uses host port user pass
  is_db_cand "$1" "$2" && return 0
  db_cands+=("$1	$2	$3	$4	$5	$host	$port	$user	$pass")
}

# A database and its parallel-testing copies, each a candidate unless something uses it.
plan_db() {  # plan_db <connection> <db> <worktree> <source> <env files...>
  local conn=$1 db=$2 wt=$3 src=$4 all d size; shift 4
  case "$conn" in pgsql|mysql) ;; *) return 0 ;; esac   # sqlite files live in the worktree
  [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || return 0
  if is_protected "$db" "$wt"; then keep "$db" "used by the main checkout or a remaining worktree"; return 0; fi
  creds_for "$conn" "$@"
  is_local || { keep "$db" "database host $host is not local"; return 0; }
  all=$(server_dbs "$conn" 2>/dev/null) || return 0
  while read -r d size; do
    [[ "$d" =~ ^${db}(_test_[0-9]+)?$ ]] || continue
    is_protected "$d" "$wt" || add_db_cand "$conn" "$d" "$wt" "$src" "$size"
  done <<< "$all"
}

# --- plan: worktrees ------------------------------------------------------------

echo ">> Fetching merged PRs" >&2
merged=$(gh pr list --state merged --limit 300 --json headRefName,headRefOid \
  --jq '.[] | "\(.headRefName)\t\(.headRefOid)"') || { echo "gh pr list failed; no worktree is a candidate" >&2; merged=""; }

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
  if [ -n "$reason" ]; then keep "$path" "$reason"; continue; fi

  wt_cands+=("$path	${branch/#-/detached}")
  wt_dbs=$(mktemp)
  {
    for f in .env .env.testing; do
      c=$(env_get "$path/$f" DB_CONNECTION); d=$(env_get "$path/$f" DB_DATABASE)
      [ -n "$d" ] && printf '%s\t%s\n' "$c" "$d"
    done
    [ -f "$registry" ] && awk -F'\t' -v w="$path" '$4 == w { print $2 "\t" $3 }' "$registry"
  } | sort -u > "$wt_dbs"
  while IFS=$'\t' read -r c d; do
    [ -n "$d" ] && plan_db "$c" "$d" "$path" worktree "$path/.env" "$path/.env.testing" "$main/.env" "$main/.env.testing"
  done < "$wt_dbs"
  rm -f "$wt_dbs"
done <<< "$worktrees"

# --- plan: registry lines a run left behind, and orphans --------------------------

if [ -f "$registry" ]; then
  now=$(date +%s)
  stale=$(awk -F'\t' -v now="$now" '$1 < now - 43200 { print $2 "\t" $3 "\t" $4 }' "$registry")
  while IFS=$'\t' read -r c d w; do
    [ -n "$d" ] || continue
    [ "$w" = "-" ] || [ ! -d "$w" ] || continue
    plan_db "$c" "$d" "$w" registry "$main/.env" "$main/.env.testing"
  done <<< "$stale"
fi

seen=""
prefixes=$(printf '%s\n' "$protected" | awk -F'\t' '$1 == "MAIN" { print $2 }' | sort -u)
for f in "$main/.env" "$main/.env.testing"; do
  conn=$(env_get "$f" DB_CONNECTION)
  case "$conn" in pgsql|mysql) ;; *) continue ;; esac
  case " $seen " in *" $conn "*) continue ;; esac; seen="$seen $conn"
  creds_for "$conn" "$f"
  is_local || continue
  all=$(server_dbs "$conn" 2>/dev/null) || continue
  while read -r d size; do
    [ -n "$d" ] || continue
    for p in $prefixes; do
      case "$d" in "${p}_"*)
        is_protected "$d" "" || add_db_cand "$conn" "$d" - orphan "$size"
        break ;;
      esac
    done
  done <<< "$all"
done

# --- listing (the default) ------------------------------------------------------

if [ ${#remove_args[@]} -eq 0 ] && [ ${#drop_args[@]} -eq 0 ]; then
  wt_json=()
  for w in ${wt_cands[@]+"${wt_cands[@]}"}; do
    p=$(printf '%s' "$w" | cut -f1); b=$(printf '%s' "$w" | cut -f2)
    names=()
    for c in ${db_cands[@]+"${db_cands[@]}"}; do
      [ "$(printf '%s' "$c" | cut -f3)" = "$p" ] && names+=("$(json_str "$(printf '%s' "$c" | cut -f2)")")
    done
    wt_json+=("{\"path\":$(json_str "$p"),\"branch\":$(json_str "$b"),\"databases\":[$(join ${names[@]+"${names[@]}"})]}")
    echo ">> candidate worktree $p ($b)" >&2
  done
  db_json=()
  for c in ${db_cands[@]+"${db_cands[@]}"}; do
    IFS=$'\t' read -r conn d w src size _ <<< "$c"
    db_json+=("{\"connection\":$(json_str "$conn"),\"database\":$(json_str "$d"),\"size\":$(json_str "$size"),\"source\":$(json_str "$src"),\"worktree\":$(json_str "$w")}")
    echo ">> candidate $conn database $d ($size, $src)" >&2
  done
  echo ">> Nothing changed. Remove only what a human selects: --remove <path> / --drop <connection>:<database>" >&2
  echo "{\"worktrees\":[$(join ${wt_json[@]+"${wt_json[@]}"})],\"databases\":[$(join ${db_json[@]+"${db_json[@]}"})],\"kept\":[$(join ${kept[@]+"${kept[@]}"})]}"
  exit 0
fi

# --- check every selected name before changing anything --------------------------

in_list() {  # in_list <value> <items...>
  local v=$1 i; shift
  for i in "$@"; do [ "$i" = "$v" ] && return 0; done
  return 1
}

wt_paths=()
for w in ${wt_cands[@]+"${wt_cands[@]}"}; do wt_paths+=("$(printf '%s' "$w" | cut -f1)"); done

errors=()
for p in ${remove_args[@]+"${remove_args[@]}"}; do
  in_list "$p" ${wt_paths[@]+"${wt_paths[@]}"} || errors+=("--remove $p: not a candidate worktree")
done
selected_dbs=()
for a in ${drop_args[@]+"${drop_args[@]}"}; do
  conn=${a%%:*}; d=${a#*:}
  if [ "$conn" = "$a" ] || ! is_db_cand "$conn" "$d"; then errors+=("--drop $a: not a candidate database"); continue; fi
  for c in "${db_cands[@]}"; do
    [ "$(printf '%s' "$c" | cut -f1-2)" = "$conn	$d" ] || continue
    w=$(printf '%s' "$c" | cut -f3)
    if [ "$w" != "-" ] && [ -d "$w" ] && ! in_list "$w" ${remove_args[@]+"${remove_args[@]}"}; then
      errors+=("--drop $a: its worktree $w stays, so the database stays")
    else
      selected_dbs+=("$c")
    fi
  done
done
if [ ${#errors[@]} -gt 0 ]; then
  printf '>> %s\n' "${errors[@]}" >&2
  echo ">> Nothing changed. Run with no arguments to list the candidates." >&2
  exit 1
fi

# --- remove exactly the selected names ----------------------------------------------

removed=()
dropped=()
failed_wts=()
for p in ${remove_args[@]+"${remove_args[@]}"}; do
  if git -C "$main" worktree remove "$p" >&2; then
    echo ">> removed $p" >&2; removed+=("$(json_str "$p")")
  else
    keep "$p" "git worktree remove refused"; failed_wts+=("$p")
  fi
done
[ ${#removed[@]} -eq 0 ] || git -C "$main" worktree prune

for c in ${selected_dbs[@]+"${selected_dbs[@]}"}; do
  IFS=$'\t' read -r conn d w src size host port user pass <<< "$c"
  if in_list "$w" ${failed_wts[@]+"${failed_wts[@]}"}; then keep "$d" "its worktree was not removed"; continue; fi
  if case "$conn" in pgsql) sql pgsql "DROP DATABASE IF EXISTS \"$d\"" ;; mysql) sql mysql "DROP DATABASE IF EXISTS \`$d\`" ;; esac; then
    echo ">> dropped $conn database $d" >&2; dropped+=("$(json_str "$d")")
    if [ -f "$registry" ]; then
      awk -F'\t' -v d="$d" '$3 != d' "$registry" > "$registry.tmp" && mv "$registry.tmp" "$registry"
    fi
  else
    keep "$d" "drop failed (open connections?)"
  fi
done

echo "{\"removed\":[$(join ${removed[@]+"${removed[@]}"})],\"dropped\":[$(join ${dropped[@]+"${dropped[@]}"})],\"kept\":[$(join ${kept[@]+"${kept[@]}"})]}"
