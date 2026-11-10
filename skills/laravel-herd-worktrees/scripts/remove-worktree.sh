#!/bin/bash
# Remove one worktree a run created, in the safe order: clean check, unserve from Herd,
# `git worktree remove` (never --force), then `git branch -d` of the branch when named.
# After git removes the worktree it also deletes that worktree's Pest cache (~/.pest/tia).
# Run it from the main checkout (or the checkout `git branch -d` should check against).
#
# It never drops a database a calling skill created: it prints those still registered
# for the worktree, so the caller drops each (and its <database>_test_<N> copies) with the
# repo's client, then runs `scratch-db.sh unregister <database>` after each success.
# A database Herd created (`--database=clone|empty`) Herd drops itself; this script
# unregisters it.
#
# Usage: remove-worktree.sh <worktree path> [--branch <name>]
# Output: JSON {"path","removed":true|false,"reason","branch","branch_deleted":true|false,
#   "branch_reason","herd_unserve_failed":null|{"database_mode","database_name"},
#   "databases":[{"connection","database","worktree"}]}  (databases is [] when kept)
# Exit 0 whether or not git removed it; "removed" and "reason" say which.

set -e

here=$(cd "$(dirname "$0")" && pwd)
wt=${1:-}
branch=""
[ -n "$wt" ] || { echo "Usage: remove-worktree.sh <worktree path> [--branch <name>]" >&2; exit 2; }
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) [ -n "${2:-}" ] || { echo "--branch needs a name" >&2; exit 2; }; branch=$2; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }
bool() { [ "$1" = 1 ] && echo true || echo false; }

[ -d "$wt" ] || { echo "No such worktree: $wt" >&2; exit 2; }
wt=$(cd "$wt" && pwd -P)

removed=0; reason=""; branch_deleted=0; branch_reason=""; herd_failed=null

# What git will refuse is checked before Herd is touched, so a refusal leaves everything
# in place: a locked worktree, or the main checkout, never loses its site or database.
wt_state=$(git worktree list --porcelain | awk -v w="$wt" '
  /^worktree / { n++; p = substr($0, 10) }
  p == w && n == 1 { main = 1 }
  p == w && /^locked/ { locked = 1 }
  END { if (main) print "main"; else if (locked) print "locked" }')

if [ -n "$(git -C "$wt" status --porcelain)" ]; then
  reason="uncommitted or untracked changes"
elif [ "$wt_state" = locked ]; then
  reason="worktree is locked"
elif [ "$wt_state" = main ]; then
  reason="this is the main checkout, not a linked worktree"
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
      herd_failed="{\"database_mode\":$(json_str "$mode"),\"database_name\":$(json_str "$hdb")}"
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
    if git branch -d "$branch" >&2; then branch_deleted=1; else branch_reason="git branch -d refused (not merged here)"; fi
  else
    branch_reason="worktree kept, so the branch stays"
  fi
fi

if [ "$removed" = 1 ]; then dbs=$(bash "$here/scratch-db.sh" list "$wt"); else dbs="[]"; fi
echo "{\"path\":$(json_str "$wt"),\"removed\":$(bool $removed),\"reason\":$(json_str "$reason"),\"branch\":$(json_str "$branch"),\"branch_deleted\":$(bool $branch_deleted),\"branch_reason\":$(json_str "$branch_reason"),\"herd_unserve_failed\":$herd_failed,\"databases\":$dbs}"
