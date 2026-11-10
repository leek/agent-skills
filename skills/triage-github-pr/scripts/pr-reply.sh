#!/bin/bash
# Reply to inline review comments and resolve their threads, a whole batch in one run.
# WRITES to GitHub: one reply per item, then one resolveReviewThread mutation per item
# that asks for it. Bodies are read from the JSON file and sent as a JSON request body, so
# no shell quoting touches them (apostrophes, backticks, and markdown are safe).
#
# Usage: pr-reply.sh <pr> <file.json> [--repo OWNER/REPO]
#   <file.json>  [{"comment_id": 123, "thread": "PRRT_..." | null, "body": "...", "resolve": true | false}]
#     comment_id  the thread's root inline comment (pr-comments.sh: `inline[].id` with `reply_to` null)
#     thread      that comment's `thread` in pr-comments.sh's output; needed only to resolve
#     resolve     true resolves the thread after the reply; false (or absent) leaves it open
# The whole file is checked before the first write: a non-numeric comment_id, an empty body,
# a non-boolean resolve, or `resolve: true` without a thread exits 2 with nothing sent.
#
# Output: {"pr": N, "replies": [{"comment_id", "reply_url", "resolved": bool, "error": null | "..."}],
#          "threads_open": n | null}
#   A failed reply skips its resolve (an unanswered thread is never resolved) and the run
#   goes on to the next item. `threads_open` is re-queried once at the end (review-threads.sh,
#   as pr-comments.sh --count does); null when that query failed, which means not checked.
# Exit: 0 every item sent, 1 any item has an `error` (send only those items again: a rerun
#   of the whole file posts the successful replies twice), 2 usage or an invalid file.
set -e
set -o pipefail

usage() { echo "usage: pr-reply.sh <pr> <file.json> [--repo OWNER/REPO]" >&2; exit 2; }

pr=""; file=""; repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ -n "${2:-}" ] || { echo "--repo needs OWNER/REPO" >&2; exit 2; }; repo=$2; shift ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) if [ -z "$pr" ]; then pr=$1; elif [ -z "$file" ]; then file=$1; else usage; fi ;;
  esac
  shift
done
[[ "$pr" =~ ^[0-9]+$ ]] || usage
[ -n "$file" ] || usage
[ -f "$file" ] || { echo "no such file: $file" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Validate everything before the first write.
if ! jq -r '
  if type != "array" then "the file must hold a JSON array"
  elif length == 0 then "the array is empty: nothing to send"
  else to_entries[] | .key as $i | .value as $v
    | (if ($v | type) != "object" then "is not an object"
       elif (($v.comment_id | type) == "number" and $v.comment_id > 0 and ($v.comment_id | floor) == $v.comment_id
             or (($v.comment_id | type) == "string" and ($v.comment_id | test("^[0-9]+$")))) | not
         then "comment_id must be a number"
       elif (($v.body | type) == "string" and ($v.body | test("\\S"))) | not then "body must be a non-empty string"
       elif ($v | has("resolve")) and ($v.resolve | type) != "boolean" then "resolve must be true or false"
       elif ($v.thread != null) and ((($v.thread | type) == "string" and ($v.thread | test("^[A-Za-z0-9_=-]+$"))) | not)
         then "thread must be a thread id (PRRT_...) or null"
       elif $v.resolve == true and $v.thread == null then "resolve is true but thread is null"
       else empty end)
    | "item \($i): \(.)"
  end' "$file" > "$tmp/invalid" 2> "$tmp/parse-error"; then
  echo "invalid JSON in $file: $(cat "$tmp/parse-error")" >&2
  exit 2
fi
if [ -s "$tmp/invalid" ]; then
  cat "$tmp/invalid" >&2
  echo "nothing was sent" >&2
  exit 2
fi

[ -n "$repo" ] || repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
case "$repo" in */*) ;; *) echo "could not resolve OWNER/REPO" >&2; exit 2 ;; esac

count=$(jq length "$file")
echo ">> $count replies on PR #$pr in $repo" >&2
failed=0
i=0
while [ "$i" -lt "$count" ]; do
  jq --argjson i "$i" '.[$i]' "$file" > "$tmp/item.json"
  id=$(jq -r '.comment_id | tostring' "$tmp/item.json")
  thread=$(jq -r '.thread // ""' "$tmp/item.json")
  resolve=$(jq -r '.resolve // false' "$tmp/item.json")
  jq '{body}' "$tmp/item.json" > "$tmp/body.json"
  url=""; resolved=false; error=""

  if gh api "repos/$repo/pulls/$pr/comments/$id/replies" --input "$tmp/body.json" > "$tmp/reply.json" 2> "$tmp/err"; then
    url=$(jq -r '.html_url // ""' "$tmp/reply.json" 2>/dev/null || true)
    [ -n "$url" ] || error="reply returned no html_url"
  else
    error="reply failed: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)"
  fi

  if [ -z "$error" ] && [ "$resolve" = true ]; then
    # shellcheck disable=SC2016  # $threadId is a GraphQL variable, not a shell one
    if gh api graphql -f threadId="$thread" -f query='
mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } } }' \
        > "$tmp/resolve.json" 2> "$tmp/err"; then
      if [ "$(jq -r '.data.resolveReviewThread.thread.isResolved // false' "$tmp/resolve.json" 2>/dev/null)" = true ]; then
        resolved=true
      else
        error="resolve returned nothing: no write access, or a stale thread id (run pr-comments.sh again)"
      fi
    else
      error="resolve failed: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)"
    fi
  fi

  if [ -n "$error" ]; then
    failed=$((failed + 1))
    echo ">> comment $id: $error" >&2
  fi
  jq -n --slurpfile item "$tmp/item.json" --arg url "$url" --argjson resolved "$resolved" --arg error "$error" \
    '{comment_id: ($item[0].comment_id | tonumber),
      reply_url: (if $url == "" then null else $url end),
      resolved: $resolved,
      error: (if $error == "" then null else $error end)}' > "$tmp/$(printf %05d "$i").out"
  i=$((i + 1))
done

open=null
if bash "$(dirname "$0")/review-threads.sh" "$repo" "$pr" > "$tmp/threads.json" 2> "$tmp/err"; then
  open=$(jq '[.[] | select(.resolved | not)] | length' "$tmp/threads.json")
else
  echo ">> thread re-query failed; threads_open is not checked: $(tr '\n' ' ' < "$tmp/err" | cut -c1-300)" >&2
fi

jq -s --argjson pr "$pr" --argjson open "$open" '{pr: $pr, replies: ., threads_open: $open}' "$tmp"/[0-9]*.out
[ "$failed" -eq 0 ] || exit 1
