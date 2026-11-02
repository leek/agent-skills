#!/bin/bash
# Gather a pull request's three comment surfaces in one read-only pass, with every inline
# comment already mapped to its resolvable review thread, as one JSON object on stdout:
#   pr, head (headRefOid), me (your login), threads_open (unresolved review threads),
#   reviews  [{id, user, state, commit, at, body}]                     at = submitted_at
#   inline   [{id, user, path, line, commit, at, reply_to, url, thread, resolved, body}]
#   issue    [{id, user, at, url, body}]                                at = updated_at
# `thread` is the GraphQL id (PRRT_...) that resolveReviewThread takes; null when unmapped.
#
# Usage: pr-comments.sh <pr> [--repo OWNER/REPO] [--since <earlier output.json>] [--count]
#   --since  keep only items new or edited since that snapshot: an id not in it, or an id
#            whose `at` changed (bots edit summaries in place). Your own items are dropped.
#   --count  print only {"pr","head","threads_open"}: the re-query before a push or merge.
# Save a full run to a file as the snapshot (`> <scratch>/pr-<N>-snapshot.json`).
# Read-only: GET calls and one GraphQL query.
set -e

pr=""; repo=""; since=""; count=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  [ -n "${2:-}" ] || { echo "--repo needs OWNER/REPO" >&2; exit 2; }; repo=$2; shift ;;
    --since) [ -f "${2:-}" ] || { echo "--since needs an existing snapshot file" >&2; exit 2; }; since=$2; shift ;;
    --count) count=1 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) pr=$1 ;;
  esac
  shift
done
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "usage: pr-comments.sh <pr> [--repo OWNER/REPO] [--since <file>] [--count]" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

[ -n "$repo" ] || repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
owner=${repo%/*}; name=${repo#*/}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo ">> PR #$pr in $repo" >&2
gh pr view "$pr" -R "$repo" --json headRefOid -q .headRefOid > "$tmp/head"

# Every thread with all its comment ids, so a reply maps to its thread as well as the root.
gh api graphql --paginate -F owner="$owner" -F repo="$name" -F pr="$pr" -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $pr) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { id isResolved comments(first: 100) { nodes { databaseId } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | {thread: .id, resolved: .isResolved, ids: [.comments.nodes[].databaseId]}' \
  | jq -s . > "$tmp/threads.json"

if [ "$count" = 1 ]; then
  jq -n --argjson pr "$pr" --arg head "$(cat "$tmp/head")" --slurpfile t "$tmp/threads.json" \
    '{pr: $pr, head: $head, threads_open: ([$t[0][] | select(.resolved | not)] | length)}'
  exit 0
fi

gh api user --jq .login > "$tmp/me" 2>/dev/null || { echo ">> gh api user failed; own comments are not filtered" >&2; : > "$tmp/me"; }
gh api "repos/$repo/pulls/$pr/reviews" --paginate \
  --jq '.[] | {id, user: .user.login, state, commit: (.commit_id // "")[:8], at: .submitted_at, body}' | jq -s . > "$tmp/reviews.json"
gh api "repos/$repo/pulls/$pr/comments" --paginate \
  --jq '.[] | {id, user: .user.login, path, line: (.line // .original_line), commit: (.commit_id // "")[:8], at: .updated_at, reply_to: .in_reply_to_id, url: .html_url, body}' | jq -s . > "$tmp/inline.json"
gh api "repos/$repo/issues/$pr/comments" --paginate \
  --jq '.[] | {id, user: .user.login, at: .updated_at, url: .html_url, body}' | jq -s . > "$tmp/issue.json"

[ -n "$since" ] || { echo '{"reviews":[],"inline":[],"issue":[]}' > "$tmp/since.json"; since="$tmp/since.json"; }

jq -n --argjson pr "$pr" --arg head "$(cat "$tmp/head")" --arg me "$(cat "$tmp/me")" \
  --argjson delta "$([ "$since" = "$tmp/since.json" ] && echo false || echo true)" \
  --slurpfile t "$tmp/threads.json" --slurpfile r "$tmp/reviews.json" \
  --slurpfile i "$tmp/inline.json" --slurpfile c "$tmp/issue.json" --slurpfile old "$since" '
  def seen($k): [$old[0][$k][]? | "\(.id)@\(.at)"];
  def fresh($k): if $delta then map(select(.user != $me and ("\(.id)@\(.at)" | IN(seen($k)[]) | not))) else . end;
  ($t[0]) as $threads
  | {pr: $pr, head: $head, me: $me,
     threads_open: ([$threads[] | select(.resolved | not)] | length),
     reviews: ($r[0] | fresh("reviews")),
     inline: ($i[0] | map(. as $x | ([$threads[] | select(.ids | index($x.id))][0]) as $th
                         | $x + {thread: $th.thread, resolved: $th.resolved}) | fresh("inline")),
     issue: ($c[0] | fresh("issue"))}'
