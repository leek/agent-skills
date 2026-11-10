#!/bin/bash
# The one owner of the review-thread GraphQL query: every review thread of a pull request,
# all pages, as one JSON array on stdout:
#   [{"thread": "PRRT_...", "resolved": bool, "ids": [<comment databaseId>, ...]}]
# `ids` holds every comment in the thread, so a reply maps to its thread as well as the root.
# Open threads: `jq '[.[] | select(.resolved | not)] | length'`.
#
# Usage: review-threads.sh <OWNER/REPO> <pr>
# Called by pr-comments.sh, pr-reply.sh, and closeout's pr-state.sh; not by an agent.
# Exit 1 when gh fails (never an empty list: a 403 must not read as "no threads"), 2 on usage.
# Read-only: one paginated GraphQL query.
set -e
set -o pipefail

repo=${1:-}; pr=${2:-}
case "$repo" in */*) ;; *) echo "usage: review-threads.sh <OWNER/REPO> <pr>" >&2; exit 2 ;; esac
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "usage: review-threads.sh <OWNER/REPO> <pr>" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# gh prints one JSON object per page; the jq below joins the pages.
# shellcheck disable=SC2016  # $owner and friends are GraphQL variables, not shell ones
gh api graphql --paginate -f owner="${repo%/*}" -f repo="${repo#*/}" -F pr="$pr" -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $pr) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { id isResolved comments(first: 100) { nodes { databaseId } } } } } } }' > "$tmp"

# A page without the thread list (an error body, a missing PR) fails here instead of counting as none.
jq -s '[.[] | .data.repository.pullRequest.reviewThreads.nodes[]
        | {thread: .id, resolved: .isResolved, ids: [.comments.nodes[].databaseId]}]' "$tmp"
