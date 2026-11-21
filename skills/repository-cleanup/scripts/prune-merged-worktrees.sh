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
#     and node_modules/ go with it).
#   - it is not locked, and it is not the checkout this script runs from.
# Every removal goes through laravel-herd-worktrees' remove-worktree.sh, from the main
# checkout and with no --branch: it checks again everything git would refuse (dirty, locked,
# submodules), unserves the worktree from Herd when Herd serves that exact path, runs
# `git worktree remove` without --force, and deletes the worktree's Pest cache. Local
# branches stay; only the directory goes. A refusal keeps the worktree, with its reason.
# Herd drops a database it made for a worktree (`--database=clone|empty`) when it unserves
# it, so --remove of a Herd-served worktree whose .herd-workspace.json names such a database
# needs a --drop naming that database too; otherwise the run stops before anything changes.
#
# The database half is laravel-herd-worktrees' scratch-db.sh: `scratch-db.sh plan` lists
# the candidates, and `scratch-db.sh drop-selected` drops each selected name, exactly that
# name, on the server the plan listed it on, after the same safety checks every drop runs.
# Candidate databases (pgsql and mysql, local hosts only), each listed by its exact name,
# parallel-testing copies (<database>_test_<N>) included as names of their own:
#   - source "worktree": registered for a candidate worktree, or the DB_DATABASE of its .env
#     and .env.testing. Dropping one needs its worktree in --remove too.
#   - source "registry": a registry line 12 hours old with no worktree, or whose directory is gone
#   - source "orphan": a local database with no registry line whose name is one the skills
#     give a scratch database: <app db>_pr<N>, <app db>_pr<N>_fix<k>, <app db>_issues_<run>,
#     <app db>_sweep_<topic>, <app db>_spec_<slug>_<NN or fix<k>>, or a _test_<N> copy of one
#   - source "prefix-only": any other local database named <app db>_* with no registry line.
#     Only the shared prefix ties it to this repository: it may be a hand-made copy
#     (app_backup), a database Herd made for a branch, or another project's. --drop refuses
#     it unless --allow-prefix-only is passed in the same run.
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
hw="$(cd "$(dirname "$0")" && pwd)/../../laravel-herd-worktrees/scripts"
scratch_db="$hw/scratch-db.sh"
remove_wt="$hw/remove-worktree.sh"
for s in "$scratch_db" "$remove_wt"; do
  [ -f "$s" ] || { echo "Missing $s: install the laravel-herd-worktrees skill beside this one" >&2; exit 1; }
done

main=$(git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10); exit }')
here=$(pwd -P)

kept=()
wt_cands=()   # path<TAB>branch

# One compact JSON value per array element, built by jq; jarr joins them into one array.
jarr() { if [ $# -eq 0 ]; then echo '[]'; else printf '%s\n' "$@" | jq -s -c .; fi; }
keep() { kept+=("$(jq -n -c --arg p "$1" --arg r "$2" '{path: $p, reason: $r}')"); }

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

plan_args=()
while IFS=$'\t' read -r p head branch flags; do
  [ -n "$p" ] || continue
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
  real=$(cd "$p" 2>/dev/null && pwd -P) || real="$p"
  case "$here/" in "$real/"*) reason="current checkout" ;; esac
  case "$flags" in *locked*) reason="locked" ;; esac
  if [ -z "$reason" ] && [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then
    reason="uncommitted or untracked changes"
  fi
  if [ -n "$reason" ]; then keep "$p" "$reason"; continue; fi

  wt_cands+=("$p	${branch/#-/detached}")
  plan_args+=(--worktree "$p")
done <<< "$worktrees"

# --- plan: databases (scratch-db.sh owns the rules) --------------------------------

plan=$(bash "$scratch_db" plan ${plan_args[@]+"${plan_args[@]}"})
while IFS= read -r k; do [ -z "$k" ] || kept+=("$k"); done < <(printf '%s' "$plan" | jq -c '.kept[]')

# --- listing (the default) ------------------------------------------------------

if [ ${#remove_args[@]} -eq 0 ] && [ ${#drop_args[@]} -eq 0 ]; then
  wt_json=()
  for w in ${wt_cands[@]+"${wt_cands[@]}"}; do
    p=${w%%	*}; b=${w##*	}
    wt_json+=("$(printf '%s' "$plan" | jq -c --arg p "$p" --arg b "$b" '{path: $p, branch: $b, databases: [.databases[] | select(.worktree == $p) | .database]}')")
    echo ">> candidate worktree $p ($b)" >&2
  done
  printf '%s' "$plan" | jq -r '.databases[] | ">> candidate \(.connection) database \(.database) (\(.size), \(.source))"' >&2
  echo ">> Nothing changed. Remove only what a human selects: --remove <path> / --drop <connection>:<database>" >&2
  jq -n -c --argjson w "$(jarr ${wt_json[@]+"${wt_json[@]}"})" \
    --argjson d "$(printf '%s' "$plan" | jq -c '[.databases[] | {connection, database, size, source, worktree}]')" \
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
for w in ${wt_cands[@]+"${wt_cands[@]}"}; do wt_paths+=("${w%%	*}"); done

# The database Herd drops itself when remove-worktree.sh unserves this path: one Herd made
# (`--database=clone|empty`, named in the worktree's .herd-workspace.json) for a worktree
# Herd serves. Read from the file even when it is tracked: a planted name only refuses more.
herd_db() {  # herd_db <worktree>: that database's name, or nothing
  local real served meta
  command -v herd >/dev/null 2>&1 || return 0
  real=$(cd "$1" && pwd -P) || return 0
  served=$(herd workspaces --all --json 2>/dev/null | jq -r --arg p "$real" '[.[]? | select(.path == $p and .served == true)] | length' 2>/dev/null) || served=0
  [ "${served:-0}" -gt 0 ] || return 0
  meta="$real/.herd-workspace.json"
  [ -f "$meta" ] || return 0
  case "$(jq -r '.database_mode // "shared"' "$meta" 2>/dev/null)" in
    clone|empty) jq -r '.database_name // empty' "$meta" 2>/dev/null || true ;;
  esac
}

errors=()
for p in ${remove_args[@]+"${remove_args[@]}"}; do
  if ! in_list "$p" ${wt_paths[@]+"${wt_paths[@]}"}; then errors+=("--remove $p: not a candidate worktree"); continue; fi
  # Removing it would drop that database too, so it must be selected as well.
  hdb=$(herd_db "$p")
  if [ -n "$hdb" ]; then
    picked=0
    for a in ${drop_args[@]+"${drop_args[@]}"}; do [ "${a#*:}" != "$hdb" ] || picked=1; done
    [ "$picked" = 1 ] || errors+=("--remove $p: Herd made database $hdb for it and drops it when the worktree is unserved; select --drop <connection>:$hdb too, or keep the worktree")
  fi
done
selected_dbs=()   # one plan entry (compact JSON) each
for a in ${drop_args[@]+"${drop_args[@]}"}; do
  conn=${a%%:*}; d=${a#*:}
  entry=""
  [ "$conn" = "$a" ] || entry=$(printf '%s' "$plan" | jq -c --arg c "$conn" --arg d "$d" 'first(.databases[] | select(.connection == $c and .database == $d)) // empty')
  if [ -z "$entry" ]; then errors+=("--drop $a: not a candidate database"); continue; fi
  w=$(printf '%s' "$entry" | jq -r .worktree)
  if [ "$(printf '%s' "$entry" | jq -r .source)" = prefix-only ] && [ "$allow_prefix_only" = 0 ]; then
    errors+=("--drop $a: only its prefix ties it to this repository; pass --allow-prefix-only to drop it")
  elif [ "$w" != "-" ] && [ -d "$w" ] && ! in_list "$w" ${remove_args[@]+"${remove_args[@]}"}; then
    errors+=("--drop $a: its worktree $w stays, so the database stays")
  else
    selected_dbs+=("$entry")
  fi
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
  # No --branch: local branches stay. No `git worktree prune` either: it would also drop the
  # record of a worktree nobody selected whose directory is only missing for now.
  res=$(cd "$main" && bash "$remove_wt" "$p") || res=""
  if [ "$(printf '%s' "$res" | jq -r '.removed' 2>/dev/null)" = true ]; then
    echo ">> removed $p" >&2; removed+=("$(jq -n -c --arg p "$p" '$p')")
  else
    reason=$(printf '%s' "$res" | jq -r '.reason // empty' 2>/dev/null) || reason=""
    keep "$p" "${reason:-remove-worktree.sh failed}"; failed_wts+=("$p")
  fi
done

for e in ${selected_dbs[@]+"${selected_dbs[@]}"}; do
  d=$(printf '%s' "$e" | jq -r .database)
  w=$(printf '%s' "$e" | jq -r .worktree)
  if in_list "$w" ${failed_wts[@]+"${failed_wts[@]}"}; then keep "$d" "its worktree was not removed"; continue; fi
  res=$(bash "$scratch_db" drop-selected "$(printf '%s' "$e" | jq -r .server)" "$d") || true
  if printf '%s' "$res" | jq -e --arg d "$d" '.dropped | index($d) != null' >/dev/null 2>&1; then
    dropped+=("$(jq -n -c --arg d "$d" '$d')")
  else
    reason=$(printf '%s' "$res" | jq -r --arg d "$d" 'first(.kept[] | select(.database == $d) | .reason) // empty' 2>/dev/null) || reason=""
    keep "$d" "${reason:-drop failed}"
  fi
done

jq -n -c --argjson r "$(jarr ${removed[@]+"${removed[@]}"})" --argjson d "$(jarr ${dropped[@]+"${dropped[@]}"})" \
  --argjson k "$(jarr ${kept[@]+"${kept[@]}"})" '{removed: $r, dropped: $d, kept: $k}'
