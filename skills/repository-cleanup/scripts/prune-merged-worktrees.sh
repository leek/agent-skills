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
#     exactly on a merged PR's head commit. A merged PR from a fork (isCrossRepository)
#     shares only its branch's name with a local branch, so it matches only a worktree
#     that sits exactly on its head commit.
#   - `git status` shows no modified or untracked files (ignored files such as vendor/
#     and node_modules/ go with it). `git worktree remove` runs without --force, so git
#     refuses a dirty tree a second time.
#   - it is not locked, and it is not the checkout this script runs from.
# Local branches stay; only the directory goes. A Herd-served worktree's link and certificate
# go too (Herd forgets workspaces whose checkout is gone).
#
# Candidate databases (pgsql and mysql, local hosts only), each listed by its exact name,
# parallel-testing copies (<database>_test_<N>) included as names of their own:
#   - source "worktree": registered for a candidate worktree in <git-common-dir>/scratch-databases
#     (lines: epoch<TAB>connection[@host:port]<TAB>database<TAB>worktree path, or "-" for
#     none), or the DB_DATABASE of its .env and .env.testing. Dropping one needs its worktree
#     in --remove too.
#   - source "registry": a registry line 12 hours old with no worktree, or whose directory is gone
#   - source "orphan": a local database with no registry line whose name is one the skills
#     give a scratch database: <app db>_pr<N>, <app db>_pr<N>_fix<k>, <app db>_issues_<run>,
#     <app db>_sweep_<topic>, <app db>_spec_<slug>_<NN or fix<k>>, or a _test_<N> copy of one
#   - source "prefix-only": any other local database named <app db>_* with no registry line.
#     Only the shared prefix ties it to this repository: it may be a hand-made copy
#     (app_backup), a database Herd made for a branch, or another project's. --drop refuses
#     it unless --allow-prefix-only is passed in the same run.
# A registry line that records its server (connection@host:port) is listed, and dropped, only
# on that server, with the credentials of an env file that names the same host and port.
# A database named by the main checkout's .env, .env.testing, or phpunit.xml(.dist), or by
# a remaining worktree's .env or .env.testing, is never a candidate, nor is a
# parallel-testing copy of one; nor is a database a registry line still names (younger than
# 12 hours, or with its worktree still there), under "orphan" or "prefix-only".
#
# Usage: prune-merged-worktrees.sh                          list candidates, change nothing
#        prune-merged-worktrees.sh [--remove <path>]... [--drop <connection>:<database>]...
#                                  [--allow-prefix-only]
#   --dry-run is accepted and does nothing extra: listing is already the default.
#   --allow-prefix-only lets --drop take a "prefix-only" database. It selects nothing itself.
#
# Output, listing: JSON {"worktrees":[{"path","branch","databases":[names]}],
#   "databases":[{"connection","database","size","source","worktree"}],"kept":[{"path","reason"}]}
# Output, removing: JSON {"removed":[paths],"dropped":[databases],"kept":[{"path","reason"}]}
# "kept" lists only worktrees and databases a check protected or a removal refused.

set -e

remove_args=()
drop_args=()
allow_prefix_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) ;;
    --allow-prefix-only) allow_prefix_only=1 ;;
    --remove) [ -n "${2:-}" ] || { echo "--remove needs a path" >&2; exit 2; }; remove_args+=("$2"); shift ;;
    --drop)   [ -n "${2:-}" ] || { echo "--drop needs <connection>:<database>" >&2; exit 2; }; drop_args+=("$2"); shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
lib="$(cd "$(dirname "$0")" && pwd)/../../laravel-herd-worktrees/scripts/scratch-db-lib.sh"
[ -f "$lib" ] || { echo "Missing $lib: install the laravel-herd-worktrees skill beside this one" >&2; exit 1; }

main=$(git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }')
here=$(pwd -P)

kept=()
wt_cands=()   # path<TAB>branch
db_cands=()   # connection<TAB>database<TAB>worktree<TAB>source<TAB>size<TAB>host<TAB>port<TAB>user<TAB>pass

# One compact JSON value per array element, built by jq; jarr joins them into one array.
jarr() { if [ $# -eq 0 ]; then echo '[]'; else printf '%s\n' "$@" | jq -s -c .; fi; }
keep() { kept+=("$(jq -n -c --arg p "$1" --arg r "$2" '{path: $p, reason: $r}')"); }

# --- databases ------------------------------------------------------------------

# env_get, env_dbs, db_protected_set, is_protected, creds_for, creds_for_server, is_local, sql,
# server_dbs and drop_database: the rules for what may be dropped, and the DROP, shared with
# scratch-db.sh.
# shellcheck source-path=SCRIPTDIR source=../../laravel-herd-worktrees/scripts/scratch-db-lib.sh
. "$lib"
registry="$(git_common_dir)/scratch-databases"
wt_dbs=""
on_exit() { [ -z "$wt_dbs" ] || rm -f "$wt_dbs"; registry_cleanup; }
trap on_exit EXIT

# Databases nothing may drop: the main checkout's, then each worktree's under its path.
protected=$(db_protected_set)

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
# A registry line that records its server is looked up there and nowhere else.
plan_db() {  # plan_db <connection>[@<host>:<port>] <db> <worktree> <source> <env files...>
  local conn rhost rport db=$2 wt=$3 src=$4 all d size reached=1
  split_conn_field "$1"; shift 4
  case "$conn" in pgsql|mysql) ;; *) return 0 ;; esac   # sqlite files live in the worktree
  [[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || return 0
  if is_protected "$db" "$wt"; then keep "$db" "used by the main checkout or a remaining worktree"; return 0; fi
  if [ -n "$rhost" ]; then creds_for_server "$conn" "$rhost" "$rport" "$@" || reached=0; else creds_for "$conn" "$@"; fi
  is_local || { keep "$db" "database host $host is not local"; return 0; }
  [ "$reached" = 1 ] || { keep "$db" "registered on $rhost:$rport, which no .env here reaches"; return 0; }
  all=$(server_dbs "$conn" 2>/dev/null) || return 0
  while read -r d size; do
    [[ "$d" =~ ^${db}(_test_[0-9]+)?$ ]] || continue
    is_protected "$d" "$wt" || add_db_cand "$conn" "$d" "$wt" "$src" "$size"
  done <<< "$all"
}

# --- plan: worktrees ------------------------------------------------------------

echo ">> Fetching merged PRs" >&2
# branch<TAB>head oid<TAB>true when the PR came from a fork.
merged=$(gh pr list --state merged --limit 300 --json headRefName,headRefOid,isCrossRepository \
  --jq '.[] | "\(.headRefName)\t\(.headRefOid)\t\(.isCrossRepository)"') || { echo "gh pr list failed; no worktree is a candidate" >&2; merged=""; }

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
  case "$flags" in *prunable*) continue ;; esac   # directory already gone: nothing here to remove

  match=0
  if [ "$branch" = "-" ]; then
    printf '%s\n' "$merged" | awk -F'\t' -v h="$head" '$2 == h { found = 1 } END { exit !found }' && match=1
  else
    # A fork's PR is another repository's branch of that name: only the exact commit proves it.
    for pr in $(printf '%s\n' "$merged" | awk -F'\t' -v b="$branch" '$1 == b { print $2 ":" $3 }'); do
      oid=${pr%%:*}
      if [ "$head" = "$oid" ]; then match=1; break; fi
      if [ "${pr#*:}" != true ] && git merge-base --is-ancestor "$head" "$oid" 2>/dev/null; then match=1; break; fi
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
  # Registry lines first (they may record the server), then the env files' names; one line
  # per connection and database.
  {
    [ -f "$registry" ] && awk -F'\t' -v w="$path" '$4 == w { print $2 "\t" $3 }' "$registry"
    for f in .env .env.testing; do
      c=$(env_get "$path/$f" DB_CONNECTION); d=$(env_get "$path/$f" DB_DATABASE)
      [ -n "$d" ] && printf '%s\t%s\n' "$c" "$d"
    done
  } | awk -F'\t' '{ c = $1; sub(/@.*/, "", c) } !seen[c FS $2]++' > "$wt_dbs"
  while IFS=$'\t' read -r c d; do
    [ -n "$d" ] && plan_db "$c" "$d" "$path" worktree "$path/.env" "$path/.env.testing" "$main/.env" "$main/.env.testing"
  done < "$wt_dbs"
  rm -f "$wt_dbs"; wt_dbs=""
done <<< "$worktrees"

# --- plan: registry lines a run left behind, and orphans --------------------------

recent=""   # databases registered in the last 12 hours: a run may still use them
if [ -f "$registry" ]; then
  now=$(date +%s)
  recent=$(awk -F'\t' -v now="$now" '$1 >= now - 43200 { print $3 }' "$registry")
  stale=$(awk -F'\t' -v now="$now" '$1 < now - 43200 { print $2 "\t" $3 "\t" $4 }' "$registry")
  while IFS=$'\t' read -r c d w; do
    [ -n "$d" ] || continue
    [ "$w" = "-" ] || [ ! -d "$w" ] || continue
    plan_db "$c" "$d" "$w" registry "$main/.env" "$main/.env.testing"
  done <<< "$stale"
fi

is_recent() {  # is_recent <db>: registered in the last 12 hours, or a parallel-testing copy of one
  [ -n "$recent" ] || return 1
  printf '%s\n' "$recent" | awk -v d="$1" '$0 != "" && (d == $0 || d ~ ("^" $0 "_test_[0-9]+$")) { f = 1 } END { exit !f }'
}

# A name a registry line holds is never an orphan: an old line with no worktree is a
# "registry" candidate above, and any other line means a run or a worktree still owns it.
registered=""
[ -f "$registry" ] && registered=$(cut -f3 "$registry")
is_registered() {  # is_registered <db>: named by a registry line, or a parallel-testing copy of one
  [ -n "$registered" ] || return 1
  printf '%s\n' "$registered" | awk -v d="$1" '$0 != "" && (d == $0 || d ~ ("^" $0 "_test_[0-9]+$")) { f = 1 } END { exit !f }'
}

# The names the skills give a scratch database, after "<app db>_" (rg "<app db>_" skills):
# triage-github-pr pr<N> and pr<N>_fix<k>, fix-github-issues issues_<run>, sweep
# sweep_<topic>, implement-spec spec_<slug>_<NN> and spec_<slug>_fix<k>; each may carry
# Laravel's parallel-testing suffix _test_<N>.
skill_name='(pr[0-9]+(_fix[0-9]+)?|issues_[A-Za-z0-9_]+|sweep_[A-Za-z0-9_]+|spec_[A-Za-z0-9_]+)(_test_[0-9]+)?'

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
        if ! is_protected "$d" "" && ! is_recent "$d" && ! is_registered "$d"; then
          if [[ "$d" =~ ^${p}_${skill_name}$ ]]; then src=orphan; else src=prefix-only; fi
          add_db_cand "$conn" "$d" - "$src" "$size"
        fi
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
      [ "$(printf '%s' "$c" | cut -f3)" = "$p" ] && names+=("$(jq -n -c --arg d "$(printf '%s' "$c" | cut -f2)" '$d')")
    done
    wt_json+=("$(jq -n -c --arg p "$p" --arg b "$b" --argjson dbs "$(jarr ${names[@]+"${names[@]}"})" '{path: $p, branch: $b, databases: $dbs}')")
    echo ">> candidate worktree $p ($b)" >&2
  done
  db_json=()
  for c in ${db_cands[@]+"${db_cands[@]}"}; do
    IFS=$'\t' read -r conn d w src size _ <<< "$c"
    db_json+=("$(jq -n -c --arg c "$conn" --arg d "$d" --arg s "$size" --arg src "$src" --arg w "$w" \
      '{connection: $c, database: $d, size: $s, source: $src, worktree: $w}')")
    echo ">> candidate $conn database $d ($size, $src)" >&2
  done
  echo ">> Nothing changed. Remove only what a human selects: --remove <path> / --drop <connection>:<database>" >&2
  jq -n -c --argjson w "$(jarr ${wt_json[@]+"${wt_json[@]}"})" --argjson d "$(jarr ${db_json[@]+"${db_json[@]}"})" \
    --argjson k "$(jarr ${kept[@]+"${kept[@]}"})" '{worktrees: $w, databases: $d, kept: $k}'
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
    if [ "$(printf '%s' "$c" | cut -f4)" = prefix-only ] && [ "$allow_prefix_only" = 0 ]; then
      errors+=("--drop $a: only its prefix ties it to this repository; pass --allow-prefix-only to drop it")
    elif [ "$w" != "-" ] && [ -d "$w" ] && ! in_list "$w" ${remove_args[@]+"${remove_args[@]}"}; then
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
    echo ">> removed $p" >&2; removed+=("$(jq -n -c --arg p "$p" '$p')")
  else
    keep "$p" "git worktree remove refused"; failed_wts+=("$p")
  fi
done
if [ ${#removed[@]} -gt 0 ]; then
  # No `git worktree prune` here: it would also drop the record of a worktree nobody
  # selected whose directory is only missing for now (an unmounted volume).
  # A worktree Herd served (`herd workspace`) leaves a link, certificate and PHP pin behind;
  # listing workspaces makes Herd forget the ones whose checkout is gone. Its database, if
  # Herd created one, is a "worktree" candidate (the worktree's .env names it) for --drop.
  if command -v herd >/dev/null 2>&1; then herd workspaces --all >/dev/null 2>&1 || true; fi
fi

for c in ${selected_dbs[@]+"${selected_dbs[@]}"}; do
  IFS=$'\t' read -r conn d w src size host port user pass <<< "$c"
  if in_list "$w" ${failed_wts[@]+"${failed_wts[@]}"}; then keep "$d" "its worktree was not removed"; continue; fi
  if drop_database "$conn" "$d" >&2; then   # the DROP, then its registry lines
    echo ">> dropped $conn database $d" >&2; dropped+=("$(jq -n -c --arg d "$d" '$d')")
  else
    keep "$d" "drop failed (open connections?)"
  fi
done

jq -n -c --argjson r "$(jarr ${removed[@]+"${removed[@]}"})" --argjson d "$(jarr ${dropped[@]+"${dropped[@]}"})" \
  --argjson k "$(jarr ${kept[@]+"${kept[@]}"})" '{removed: $r, dropped: $d, kept: $k}'
