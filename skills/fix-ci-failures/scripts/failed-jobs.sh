#!/bin/bash
# List the latest CI failures of a branch, a pull request's head commit, or one commit, one
# entry per workflow, with each failed job's first error lines. Read-only: it reads existing
# runs and logs and never triggers CI.
#
# For each workflow it takes the newest completed run that was not cancelled, looking back
# at most 10 runs. A workflow that passed since is skipped; one whose last 10 completed runs
# were all cancelled comes back as conclusion "all_cancelled" with no jobs.
#
# Usage: failed-jobs.sh <branch> [--out <dir>] [--lines N]
#        failed-jobs.sh --pr <n> [--out <dir>] [--lines N]
#        failed-jobs.sh --commit <sha> [--out <dir>] [--lines N]
#   --pr <n>      only runs on that pull request's current head commit (run from its repo)
#   --commit <sha> only runs on that commit (the full sha)
#   --out <dir>   keep each failed job's full log here as <job id>.log (default: a temp dir)
#   --lines N     error lines to keep per job (default 5)
# Output: JSON [{"workflow","run_id","url","head_sha","conclusion",
#   "jobs":[{"id","name","url","log","first_errors":[...]}]}]; [] when nothing completed failed.
# Only GitHub Actions runs are listed: a failed check from another CI system has no run here.
# Exit 1 when gh cannot list the runs, read the PR, or list a run's jobs (never [] on a failed read).

set -e

usage() { echo "Usage: failed-jobs.sh <branch> | --pr <n> | --commit <sha> [--out <dir>] [--lines N]" >&2; exit 2; }

branch=""; pr=""; commit=""; out=""; lines=5
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "--pr needs a PR number" >&2; exit 2; }; pr=$2; shift ;;
    --commit) [[ "${2:-}" =~ ^[0-9a-fA-F]{40,64}$ ]] || { echo "--commit needs a full commit sha" >&2; exit 2; }; commit=$2; shift ;;
    --out) [ -n "${2:-}" ] || usage; out=$2; shift ;;
    --lines) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "--lines needs a number" >&2; exit 2; }; lines=$2; shift ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) [ -z "$branch" ] || { echo "Unknown arg: $1" >&2; exit 2; }; branch=$1 ;;
  esac
  shift
done
picked=0
for v in "$branch" "$pr" "$commit"; do [ -z "$v" ] || picked=$((picked + 1)); done
[ "$picked" = 1 ] || usage
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

tmp=$(mktemp); trap 'rm -f "$tmp" "$tmp.txt" "$tmp.jobs"' EXIT

if [ -n "$pr" ]; then
  commit=$(gh pr view "$pr" --json headRefOid --jq .headRefOid)
  [ -n "$commit" ] || { echo "PR #$pr has no head commit" >&2; exit 1; }
  echo ">> PR #$pr head $commit" >&2
fi
if [ -n "$commit" ]; then filter=(--commit "$commit"); else filter=(--branch "$branch"); fi
if [ -z "$out" ]; then out=$(mktemp -d); fi
mkdir -p "$out"

echo ">> latest completed runs on ${commit:-$branch}" >&2
gh run list "${filter[@]}" --status completed --limit 100 \
  --json databaseId,workflowName,conclusion,headSha,createdAt,url \
  --jq 'group_by(.workflowName) | .[] | sort_by(.createdAt) | reverse | .[:10]
        | (map(select(.conclusion != "cancelled")) | first)
          // {workflowName: .[0].workflowName, conclusion: "all_cancelled", url: .[0].url}
        | select(IN(.conclusion; "failure", "timed_out", "startup_failure", "all_cancelled"))
        | {workflow: .workflowName, run_id: .databaseId, url, head_sha: .headSha, conclusion}' > "$tmp"

result=()
while IFS= read -r run; do
  [ -n "$run" ] || continue
  id=$(printf '%s' "$run" | jq -r '.run_id // empty')
  jobs=()
  if [ -n "$id" ]; then
    # To a file first: a failed read must stop the script, not read as "no failed jobs".
    gh run view "$id" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {id: .databaseId, name, url}' > "$tmp.jobs"
    while IFS= read -r job; do
      [ -n "$job" ] || continue
      jid=$(printf '%s' "$job" | jq -r .id)
      log="$out/$jid.log"
      echo ">> failed job $(printf '%s' "$job" | jq -r .name) ($jid)" >&2
      gh run view --job "$jid" --log-failed > "$log" 2>/dev/null || echo ">> no log for job $jid" >&2
      # Lines are "<job>\t<step>\t<timestamp> <text>"; keep the text without ANSI colour.
      # A runner "##[error]" annotation comes first, then test-runner and compiler failure
      # lines. "Process completed with exit code" is never the real error, and config
      # echoes (display_errors=..., fail-on-cache-miss: ...) are not errors.
      cut -f3- "$log" | sed -E 's/^[0-9T:.-]+Z ?//; s/\x1b\[[0-9;]*[A-Za-z]//g; s/\^\[\[[0-9;]*[A-Za-z]//g' > "$tmp.txt"
      errs=$( { grep -E '##\[error\]' "$tmp.txt" | grep -v 'Process completed with exit code' || true
                grep -E '(^|[[:space:]])(FAILED|FAIL|Failed asserting|Error:|error:|ERROR|Exception|ERR!|Fatal|fatal:|✗|⨯|×)' "$tmp.txt" \
                  | grep -vE 'display_errors|fail-on-|fail_on|##\[(group|endgroup|error)\]' || true
              } | sed -E 's/^[[:space:]]+//' | awk '!seen[$0]++' | head -n "$lines" | cut -c1-300 | jq -R . | jq -sc .)
      jobs+=("$(printf '%s' "$job" | jq -c --arg log "$log" --argjson e "${errs:-[]}" '. + {log: $log, first_errors: $e}')")
    done < "$tmp.jobs"
  fi
  result+=("$(printf '%s' "$run" | jq -c --argjson j "[$(IFS=,; echo "${jobs[*]}")]" '. + {jobs: $j}')")
done < "$tmp"

echo ">> full logs in $out" >&2
(IFS=,; echo "[${result[*]}]") | jq -c .
