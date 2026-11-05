#!/bin/bash
# Poll a check command until it passes, fails, or the time budget runs out.
# The check's exit code is its verdict:
#   0   passed   -> print {"result":"passed", ...}, exit 0
#   1   not yet  -> wait <interval> seconds, check again
#   2+  failed   -> print {"result":"failed", ...}, exit 2
# Budget spent  -> print {"result":"timeout", ...}, exit 3
# "detail" is the last line the check printed, so the verdict carries its evidence.
#
# Usage: wait-until.sh [--interval <seconds>] [--timeout <seconds>] -- <check> [args ...]
# Defaults: --interval 30, --timeout 3600. Wrap a compound check in: bash -c '...'
# Run it in the background; it changes nothing itself, it runs only the check you pass.
set -e

usage() { echo "usage: wait-until.sh [--interval <s>] [--timeout <s>] -- <check> [args ...]" >&2; exit 64; }

interval=30
timeout=3600
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) interval=$2; shift 2 ;;
    --timeout) timeout=$2; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[ $# -gt 0 ] || usage
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

out=$(mktemp)
trap 'rm -f "$out"' EXIT

emit() {
  jq -n --arg result "$1" --arg detail "$detail" --argjson code "$code" \
    --argjson elapsed "$elapsed" --argjson checks "$checks" \
    '{result: $result, exit_code: $code, elapsed_seconds: $elapsed, checks: $checks, detail: $detail}'
}

start=$(date +%s)
checks=0
while :; do
  checks=$((checks + 1))
  set +e
  "$@" > "$out" 2>&1
  code=$?
  set -e
  detail=$(tail -n 1 "$out")
  elapsed=$(( $(date +%s) - start ))
  case $code in
    0) emit passed; exit 0 ;;
    1) ;;
    *) emit failed; exit 2 ;;
  esac
  if [ $((elapsed + interval)) -gt "$timeout" ]; then
    emit timeout
    exit 3
  fi
  echo "not yet after ${elapsed}s: $detail" >&2
  sleep "$interval"
done
