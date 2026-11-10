#!/bin/bash
# Block until a worktree has gone N minutes with no file change, then print one
# JSON line and exit 0. The stall alarm for a lone implementer: run it under a
# Monitor (or as a background task) and its exit is the wake-up.
#
# Usage: worktree-idle.sh <worktree> [minutes]     (default 20)
# Prints {"worktree":"…","status":"idle","idle_seconds":N} or, when the worktree
# is removed mid-watch, {"worktree":"…","status":"gone"}. Exits 1 on bad input.
#
# Portable (macOS and Linux): it never reads file times. Each poll asks `find`
# for files newer than a marker touched at the previous poll, and keeps the
# last-change time as a shell clock. .git, vendor and node_modules are skipped.
# Env (tests): WORKTREE_IDLE_LIMIT_SECONDS overrides minutes,
# WORKTREE_IDLE_POLL_SECONDS sets the poll interval (default 60).

set -e

dir=${1:?usage: worktree-idle.sh <worktree> [minutes]}
minutes=${2:-20}
case "$minutes" in ''|*[!0-9]*) echo "worktree-idle: minutes must be a whole number: $minutes" >&2; exit 1 ;; esac
[ -d "$dir" ] || { echo "worktree-idle: not a directory: $dir" >&2; exit 1; }
dir=$(cd "$dir" && pwd -P)
limit=${WORKTREE_IDLE_LIMIT_SECONDS:-$((minutes * 60))}
poll=${WORKTREE_IDLE_POLL_SECONDS:-60}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
marker="$tmp/marker"
touch "$marker"
last_change=$(date +%s)

changed_since() {  # changed_since <marker>: true when any watched file is newer
  find "$dir" \( -name .git -o -name vendor -o -name node_modules \) -prune \
    -o -newer "$1" -print 2>/dev/null | grep -q .
}

echo "worktree-idle: watching $dir; alarm after ${limit}s with no file change" >&2
while :; do
  sleep "$poll"
  if [ ! -d "$dir" ]; then
    jq -cn --arg w "$dir" '{worktree:$w,status:"gone"}'
    exit 0
  fi
  # Touch the next marker before the scan so a write during the scan is not lost.
  touch "$tmp/next"
  now=$(date +%s)
  if changed_since "$marker"; then
    last_change=$now
  fi
  mv "$tmp/next" "$marker"
  idle=$((now - last_change))
  if [ "$idle" -ge "$limit" ]; then
    jq -cn --arg w "$dir" --argjson s "$idle" '{worktree:$w,status:"idle",idle_seconds:$s}'
    exit 0
  fi
done
