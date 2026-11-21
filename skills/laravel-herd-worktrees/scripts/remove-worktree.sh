#!/bin/bash
# Remove one worktree a run created, in the safe order: clean check, unserve from Herd,
# `git worktree remove` (never --force), then `git branch -d` of the branch when named.
# After git removes the worktree it also deletes that worktree's Pest cache (~/.pest/tia).
# Run it from the main checkout (or the checkout `git branch -d` should check against).
#
# Herd is touched only when git will agree. Every reason `git worktree remove` refuses
# without --force is checked first, and each leaves the worktree, its site and its
# databases as they were ("removed": false, with the reason):
#   - the path is not a worktree of this repository, or is the main checkout
#   - the worktree is locked
#   - it holds submodules (git's own test: a modules/ directory in the worktree's git
#     directory, or a checked-out submodule)
#   - `git status --porcelain --ignore-submodules=none` prints a line (git's own test), or
#     fails; untracked files count here even when status.showUntrackedFiles hides them
# What cannot be seen up front: a file written between the check and the removal, and a
# failure while git deletes the directory (a permission, a file in use). Then the site is
# already unserved, and "reason" is "git worktree remove refused".
#
# By default it drops no database a calling skill created: it prints those still registered
# for the worktree. With --drop-databases, once git has removed the worktree, it runs
# `scratch-db.sh drop <database>` (the one drop, with all its safety checks) for each of
# them, and reports what went and what stayed; a kept worktree drops nothing.
# A database Herd created (`--database=clone|empty`) Herd drops itself; this script
# unregisters it.
#
# Usage: remove-worktree.sh <worktree path> [--branch <name>] [--drop-databases]
# Output: JSON {"path","removed":true|false,"reason","branch","branch_deleted":true|false,
#   "branch_reason","herd_unserve_failed":null|{"database_mode","database_name"},
#   "databases":[{"connection","database","worktree"}]}  (databases is [] when kept)
#   With --drop-databases it adds "dropped":[names] and "kept":[{"database","reason"}], and
#   "databases" lists what is still registered for the path after the drops.
# Exit 0 whether or not git removed it; "removed" and "reason" say which.

set -e

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
wt=${1:-}
branch=""
drop_dbs=0
usage="Usage: remove-worktree.sh <worktree path> [--branch <name>] [--drop-databases]"
case "$wt" in -h|--help) echo "$usage" >&2; exit 0 ;; esac
[ -n "$wt" ] || { echo "$usage" >&2; exit 2; }
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) [ -n "${2:-}" ] || { echo "--branch needs a name" >&2; exit 2; }; branch=$2; shift ;;
    --drop-databases) drop_dbs=1 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

bool() { [ "$1" = 1 ] && echo true || echo false; }

[ -d "$wt" ] || { echo "No such worktree: $wt" >&2; exit 2; }
wt=$(cd "$wt" && pwd -P)

removed=0; reason=""; branch_deleted=0; branch_reason=""; herd_failed=null

# What git will refuse is checked before Herd is touched, so a refusal leaves everything
# in place: a locked worktree, or the main checkout, never loses its site or database.
wt_state=$(git worktree list --porcelain | W="$wt" awk '
  BEGIN { w = ENVIRON["W"] }   # not -v, which would rewrite a backslash in the path
  /^worktree / { n++; p = substr($0, 10) }
  p == w { found = 1 }
  p == w && n == 1 { main = 1 }
  p == w && /^locked/ { locked = 1 }
  END { if (main) print "main"; else if (locked) print "locked"; else if (found) print "linked" }')

# git refuses a worktree with submodules: its git directory has a modules/ directory, or
# the index holds a gitlink whose directory is checked out (it has a .git).
has_submodules() {
  local gd entry
  gd=$(cd "$wt" && cd "$(git rev-parse --git-dir)" && pwd -P) || return 1
  [ ! -d "$gd/modules" ] || return 0
  while IFS= read -r -d '' entry; do   # "<mode> <sha> <stage><TAB><path>"
    case "$entry" in
      "160000 "*) [ ! -e "$wt/${entry#*$'\t'}/.git" ] || return 0 ;;
    esac
  done < <(git -C "$wt" ls-files -z -s)
  return 1
}

status_rc=0
dirty=$(git -C "$wt" status --porcelain --ignore-submodules=none --untracked-files=normal 2>/dev/null) || status_rc=$?
if [ "$status_rc" != 0 ]; then
  reason="git status failed in the worktree"
elif [ -n "$dirty" ]; then
  reason="uncommitted or untracked changes"
elif [ "$wt_state" = locked ]; then
  reason="worktree is locked"
elif [ "$wt_state" = main ]; then
  reason="this is the main checkout, not a linked worktree"
elif [ "$wt_state" != linked ]; then
  reason="not a worktree of this repository"
elif has_submodules; then
  reason="worktree holds submodules, which git worktree remove refuses"
else
  # The site comes from Herd's own state for this exact path, never from the checkout:
  # a branch could commit a .herd-workspace.json naming another site. The database
  # name from that file is used only when it is untracked and registered for this path.
  site=""; mode=shared; hdb=""
  if command -v herd >/dev/null 2>&1; then
    site=$(herd workspaces --all --json 2>/dev/null | jq -r --arg p "$wt" '[.[]? | select(.path == $p and .served == true) | .site] | first // empty' 2>/dev/null) || site=""
  fi
  meta="$wt/.herd-workspace.json"
  if [ -n "$site" ] && [ -f "$meta" ] && ! git -C "$wt" ls-files --error-unmatch .herd-workspace.json >/dev/null 2>&1; then
    mode=$(jq -r '.database_mode // "shared"' "$meta" 2>/dev/null || echo shared)
    hdb=$(jq -r '.database_name // empty' "$meta" 2>/dev/null || true)
    registered=$(bash "$here/scratch-db.sh" list "$wt" | jq -r --arg d "$hdb" 'map(select(.database == $d)) | length')
    [ "$registered" -gt 0 ] || hdb=""
  fi
  if [ -n "$site" ]; then
    if herd workspace:delete --force --keep-files -- "$site" >&2; then
      echo ">> unserved $site" >&2
      case "$mode" in clone|empty) [ -n "$hdb" ] && bash "$here/scratch-db.sh" unregister "$hdb" ;; esac
    else
      echo ">> herd workspace:delete failed for $site" >&2
      herd_failed=$(jq -n -c --arg m "$mode" --arg d "$hdb" '{database_mode: $m, database_name: $d}')
    fi
  fi
  if git worktree remove "$wt" >&2; then
    removed=1
    echo ">> removed $wt" >&2
    command -v herd >/dev/null 2>&1 && { herd workspaces --all >/dev/null 2>&1 || true; }
    # Pest keeps a test-impact cache folder per project root under ~/.pest/tia and never
    # deletes it. A linked worktree has no .git/config, so Pest names its folder
    # <slug of basename>-<first 16 hex of sha256(realpath)>. Delete exactly that folder.
    tia_root="${HOME:-}/.pest/tia"
    if [ -n "${HOME:-}" ] && [ -d "$tia_root" ]; then
      tia_slug=$(basename "$wt" | tr '[:upper:]' '[:lower:]' | sed -E -e 's/[^a-z0-9]+/-/g' -e 's/^-+//' -e 's/-+$//')
      if command -v shasum >/dev/null 2>&1; then tia_hash=$(printf '%s' "$wt" | shasum -a 256 | cut -c1-16)
      else tia_hash=$(printf '%s' "$wt" | sha256sum | cut -c1-16); fi
      if printf '%s' "$tia_hash" | grep -Eq '^[0-9a-f]{16}$'; then
        tia_dir="$tia_root/${tia_slug:+$tia_slug-}$tia_hash"
        if [ -d "$tia_dir" ]; then rm -rf -- "$tia_dir" && echo ">> removed Pest cache $tia_dir" >&2 || true; fi
      fi
    fi
  else
    reason="git worktree remove refused"
  fi
fi

if [ -n "$branch" ]; then
  if [ "$removed" = 1 ]; then
    if git branch -d -- "$branch" >&2; then branch_deleted=1; else branch_reason="git branch -d refused (not merged here)"; fi
  else
    branch_reason="worktree kept, so the branch stays"
  fi
fi

if [ "$removed" = 1 ]; then dbs=$(bash "$here/scratch-db.sh" list "$wt"); else dbs="[]"; fi

# --drop-databases: only after git removed the worktree (a kept one keeps its databases),
# each registered name once, through scratch-db.sh drop, which exits 1 when it keeps one.
drops='{"dropped":[],"kept":[]}'
if [ "$drop_dbs" = 1 ] && [ "$removed" = 1 ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    res=$(bash "$here/scratch-db.sh" drop "$d") || true
    printf '%s' "$res" | jq -e 'has("dropped") and has("kept")' >/dev/null 2>&1 \
      || res=$(jq -n -c --arg d "$d" '{dropped: [], kept: [{database: $d, reason: "scratch-db.sh drop failed"}]}')
    drops=$(jq -n -c --argjson a "$drops" --argjson b "$res" '{dropped: ($a.dropped + $b.dropped), kept: ($a.kept + $b.kept)}')
  done < <(printf '%s' "$dbs" | jq -r '[.[].database] | unique[]')
  dbs=$(bash "$here/scratch-db.sh" list "$wt")
fi

jq -n -c --arg path "$wt" --argjson removed "$(bool $removed)" --arg reason "$reason" --arg branch "$branch" \
  --argjson branch_deleted "$(bool $branch_deleted)" --arg branch_reason "$branch_reason" \
  --argjson herd_unserve_failed "$herd_failed" --argjson databases "$dbs" \
  --argjson drops "$drops" --argjson with_drops "$(bool $drop_dbs)" \
  '{path: $path, removed: $removed, reason: $reason, branch: $branch, branch_deleted: $branch_deleted,
    branch_reason: $branch_reason, herd_unserve_failed: $herd_unserve_failed, databases: $databases}
   + (if $with_drops then $drops else {} end)'
