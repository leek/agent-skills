#!/bin/bash
# Land one ticket branch on the integration branch, one worker at a time. An Autopilot build
# worker runs it from inside its ticket worktree. The lock makes the tree a worker tested the
# tree that lands: `begin` takes the lock and merges the integration tip into the ticket
# branch, the worker reruns its focused tests, and `finish` merges the ticket branch into the
# integration branch and frees the lock.
#
# Usage (current directory: the ticket worktree, on its ticket branch):
#   land.sh begin  --notes <dir> --integration <dir>
#   land.sh finish --notes <dir> --integration <dir> --ticket <NN> [--stack]
#   land.sh abort  --notes <dir>
#   --notes        the run's notes directory (the lock, landed/ and the stack list live there)
#   --integration  the checkout that has the integration branch checked out
#   --stack        Stacked PRs: also cut <integration branch>-stack-<NN> at the merge commit
#                  and push it, so the branch below is on the remote before the next lands
#
# Output: one JSON object on stdout; messages on stderr.
#   begin   {"locked":true,"merged":true,"tip":sha}
#           {"locked":true,"merged":false,"conflicts":[paths]}   exit 1: resolve, commit, go on
#           {"locked":false,"owner":branch}                      exit 3: busy, call begin again
#   finish  {"landed":true,"ticket","merge_sha","position":n|null,"cut":branch|null,
#            "base":branch|null,"pushed":true|false|null}        exit 1 when pushed is false
#           {"landed":false,"reason"}                            exit 1, the lock is kept
#   abort   {"released":true|false}
# Exit: 0 done, 1 refused (see above), 2 usage error or a wrong starting state, 3 lock busy.
#
# LAND_WAIT_SECONDS (default 90) is how long `begin` waits for a busy lock before exit 3.

set -e

usage() {
  echo "Usage: land.sh begin|finish|abort --notes <dir> [--integration <dir>] [--ticket <NN>] [--stack]" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || { echo "land.sh needs jq on PATH" >&2; exit 2; }

action="${1:-}"
[ -n "$action" ] || usage
shift
notes=""
integration=""
ticket=""
stack=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) [ -n "${2:-}" ] || usage; notes=$2; shift ;;
    --integration) [ -n "${2:-}" ] || usage; integration=$2; shift ;;
    --ticket) [ -n "${2:-}" ] || usage; ticket=$2; shift ;;
    --stack) stack=1 ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
  shift
done
[ -n "$notes" ] || usage
mkdir -p -- "$notes"

branch="$(git branch --show-current 2>/dev/null || true)"
[ -n "$branch" ] || { echo "land.sh: run it inside the ticket worktree, on its branch" >&2; exit 2; }
lock="$notes/land.lock"
wait_seconds="${LAND_WAIT_SECONDS:-90}"

lock_owner() {
  [ -f "$lock/owner" ] && sed -n '1p' "$lock/owner" || true
}

release_lock() {
  rm -f -- "$lock/owner"
  rmdir "$lock" 2>/dev/null || true
}

integration_branch() {
  [ -n "$integration" ] || usage
  [ -d "$integration" ] || { echo "land.sh: no integration checkout at $integration" >&2; exit 2; }
  ibranch="$(git -C "$integration" branch --show-current 2>/dev/null || true)"
  [ -n "$ibranch" ] || { echo "land.sh: the integration checkout is on no branch" >&2; exit 2; }
  [ "$ibranch" != "$branch" ] || { echo "land.sh: this is the integration branch, not a ticket branch" >&2; exit 2; }
}

tracked_changes() {
  git status --porcelain --untracked-files=no
}

case "$action" in
  begin)
    integration_branch
    if [ "$(lock_owner)" != "$branch" ]; then
      [ -z "$(tracked_changes)" ] || { echo "land.sh: commit the ticket's changes before landing" >&2; exit 2; }
      waited=0
      while ! mkdir "$lock" 2>/dev/null; do
        if [ "$waited" -ge "$wait_seconds" ]; then
          jq -cn --arg owner "$(lock_owner)" '{locked: false, owner: $owner}'
          exit 3
        fi
        sleep 3
        waited=$((waited + 3))
      done
      printf '%s\n' "$branch" >"$lock/owner"
    fi
    if git merge --no-edit "$ibranch" >&2; then
      jq -cn --arg tip "$(git rev-parse "$ibranch")" '{locked: true, merged: true, tip: $tip}'
      exit 0
    fi
    git diff --name-only --diff-filter=U | jq -Rsc '{locked: true, merged: false, conflicts: (split("\n") | map(select(. != "")))}'
    exit 1
    ;;

  finish)
    integration_branch
    [ -n "$ticket" ] || usage
    [ "$(lock_owner)" = "$branch" ] || { echo "land.sh: $branch does not hold the landing lock; run begin first" >&2; exit 2; }
    refuse() {
      jq -cn --arg reason "$1" '{landed: false, reason: $reason}'
      exit 1
    }
    [ -z "$(tracked_changes)" ] || refuse "the ticket worktree has uncommitted changes"
    git merge-base --is-ancestor "$ibranch" HEAD || refuse "$branch does not hold the integration tip; run begin again"
    [ -z "$(git -C "$integration" diff --cached --name-only)" ] || refuse "the integration checkout has staged changes"
    if ! git -C "$integration" merge --no-ff --no-edit -m "Merge $branch into $ibranch" "$branch" >&2; then
      git -C "$integration" merge --abort 2>/dev/null || true
      refuse "the merge into $ibranch failed"
    fi
    merge_sha="$(git -C "$integration" rev-parse HEAD)"
    mkdir -p -- "$notes/landed"
    printf '%s\n' "$merge_sha" >"$notes/landed/$ticket"

    position=null
    cut=""
    base=""
    pushed=null
    if [ "$stack" = 1 ]; then
      touch "$notes/stack"
      position=$(( $(wc -l <"$notes/stack" | tr -d ' ') + 1 ))
      cut="$ibranch-stack-$ticket"
      base="$ibranch"
      [ "$position" = 1 ] || base="$(tail -n 1 "$notes/stack" | cut -f3)"
      printf '%s\t%s\t%s\t%s\n' "$position" "$ticket" "$cut" "$base" >>"$notes/stack"
      git branch -f "$cut" "$merge_sha" >&2
      if git push -u origin "$cut" >&2; then pushed=true; else pushed=false; fi
    fi
    release_lock
    jq -cn --arg ticket "$ticket" --arg merge_sha "$merge_sha" --argjson position "$position" \
      --arg cut "$cut" --arg base "$base" --argjson pushed "$pushed" \
      '{landed: true, ticket: $ticket, merge_sha: $merge_sha, position: $position,
        cut: (if $cut == "" then null else $cut end), base: (if $base == "" then null else $base end),
        pushed: $pushed}'
    [ "$pushed" != false ] || exit 1
    ;;

  abort)
    if [ "$(lock_owner)" = "$branch" ]; then
      release_lock
      jq -cn '{released: true}'
    else
      jq -cn '{released: false}'
    fi
    ;;

  *) usage ;;
esac
