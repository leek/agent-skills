#!/bin/bash
# Print the state of each pull request, as one JSON array on stdout:
#   number, url, state, draft, review   (review is gh's reviewDecision, or null)
#   checks_failed   names of checks that failed, errored, were cancelled, timed out, or never started
#   checks_pending  count of checks not finished yet
#   threads_open    count of review threads not resolved, or null when the thread query failed
#   merge_danger    the body's "## Merge Danger" section (the pr skill's format), or null
#
# Usage: pr-state.sh <number> [<number> ...]
# Run from inside the repository the PRs belong to.
# A PR that gh cannot read prints {"number", "error"}.
# Read-only.
set -e

[ $# -gt 0 ] || { echo "usage: pr-state.sh <number> [<number> ...]" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

i=0
for n in "$@"; do
  i=$((i + 1))
  out="$tmp/$(printf %03d "$i").json"
  echo "Checking PR #$n..." >&2
  if ! gh pr view "$n" --json number,url,state,isDraft,reviewDecision,statusCheckRollup,body > "$tmp/pr.json"; then
    jq -n --arg number "$n" '{number: ($number | tonumber? // $number), error: "gh pr view failed"}' > "$out"
    continue
  fi
  repo=$(jq -r '.url | split("/") | .[3] + "/" + .[4]' "$tmp/pr.json")
  if gh api graphql --paginate -F owner="${repo%/*}" -F repo="${repo#*/}" -F pr="$n" -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $pr) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { isResolved } } } } }' \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not) | 1' > "$tmp/threads"; then
    open=$(wc -l < "$tmp/threads" | tr -d ' ')
  else
    open=null
  fi
  jq --argjson open "$open" '
    def outcome:
      if (.status // "COMPLETED" | ascii_upcase) != "COMPLETED" then "PENDING"
      else (.conclusion // .state // "") | ascii_upcase end;
    {number, url, state, draft: .isDraft,
     review: (if .reviewDecision == "" then null else .reviewDecision end),
     checks_failed: [.statusCheckRollup[]? | select(outcome | IN("FAILURE", "CANCELLED", "TIMED_OUT", "ERROR", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE")) | (.name // .context)],
     checks_pending: [.statusCheckRollup[]? | select(outcome | IN("", "PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED"))] | length,
     threads_open: $open,
     merge_danger: ((.body // "") | (capture("## Merge Danger\\s*(?<s>[\\s\\S]*?)(\\n## |\\z)").s)? // null)}' \
    "$tmp/pr.json" > "$out"
done

jq -s . "$tmp"/[0-9]*.json
