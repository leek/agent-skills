#!/bin/bash
# Remove one worktree a run created, in the safe order: clean check, unserve from Herd,
# `git worktree remove` (never --force), then `git branch -d` of the branch when named.
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

if [ -n "$(git -C "$wt" status --porcelain)" ]; then
  reason="uncommitted or untracked changes"
else
  meta="$wt/.herd-workspace.json"
  if [ -f "$meta" ] && command -v herd >/dev/null 2>&1; then
    site=$(jq -r .site "$meta")
    mode=$(jq -r '.database_mode // "shared"' "$meta")
    hdb=$(jq -r '.database_name // empty' "$meta")
    if herd workspace:delete "$site" --force --keep-files >&2; then
      echo ">> unserved $site" >&2
      case "$mode" in clone|empty) [ -n "$hdb" ] && bash "$here/scratch-db.sh" unregister "$hdb" ;; esac
    else
      echo ">> herd workspace:delete failed; a $mode database $hdb, if any, still needs dropping" >&2
      herd_failed="{\"database_mode\":$(json_str "$mode"),\"database_name\":$(json_str "$hdb")}"
    fi
  fi
  if git worktree remove "$wt" >&2; then
    removed=1
    echo ">> removed $wt" >&2
    command -v herd >/dev/null 2>&1 && { herd workspaces --all >/dev/null 2>&1 || true; }
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
