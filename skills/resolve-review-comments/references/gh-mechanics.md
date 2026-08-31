# GitHub mechanics

`OWNER/REPO` from `gh repo view --json nameWithOwner -q .nameWithOwner`; `PR` is the
pull-request number.

## Read the three comment surfaces

Review comments live in three different places, pull all three:

```bash
# 1. Reviews (top-level bodies + state; identifies which bot reviewed which commit)
gh api repos/OWNER/REPO/pulls/PR/reviews \
  --jq '.[] | {id, user: .user.login, state, commit: .commit_id[:10], body: (.body[:200])}'

# 2. Inline review comments (the threads you resolve): the reviewed commit is commit_id
gh api repos/OWNER/REPO/pulls/PR/comments \
  --jq '.[] | "=== #\(.id) | \(.user.login) | \(.path):\(.line // .original_line) | commit \(.commit_id[:10]) ===\n\(.body)\n"'

# 3. General issue comments (not attached to a line)
gh api repos/OWNER/REPO/issues/PR/comments --jq '.[] | {id, user: .user.login, body}'
```

The PR's commit range, to compare a reviewed commit against HEAD:

```bash
gh pr view PR --json headRefOid,commits
git log --oneline BASE..HEAD      # what the reviewer had vs what exists now
```

## Map inline comments to resolvable thread ids

REST exposes comment ids but cannot resolve threads. GraphQL `reviewThreads` gives the
thread id (`PRRT_…`) and its member comments' `databaseId` (== the REST comment id):

```bash
gh api graphql -f query='
query {
  repository(owner:"OWNER", name:"REPO") {
    pullRequest(number: PR) {
      reviewThreads(first:100) {
        nodes { id isResolved comments(first:5){ nodes { databaseId path } } }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[]
  | {thread: .id, resolved: .isResolved, comment: .comments.nodes[0].databaseId, path: .comments.nodes[0].path}'
```

## Reply to a thread, then resolve it

```bash
# Reply (adds a comment into the thread of comment COMMENT_ID)
gh api repos/OWNER/REPO/pulls/PR/comments/COMMENT_ID/replies -f body="$BODY"

# Resolve the thread (GraphQL only)
gh api graphql -f query='mutation {
  resolveReviewThread(input:{threadId:"PRRT_…"}) { thread { isResolved } }
}'
```

## Batch script pattern

Reply + resolve every thread in one pass. Keep each `$BODY` free of apostrophes and
backticks so single-quoted assignment and `-f body=` stay safe.

```bash
#!/bin/bash
set -euo pipefail
REPO=OWNER/REPO; PR=NNNN

reply_and_resolve() {  # comment_id  thread_id  body
  gh api "repos/$REPO/pulls/$PR/comments/$1/replies" -f body="$3" --jq '.id' >/dev/null
  gh api graphql -f query="mutation { resolveReviewThread(input:{threadId:\"$2\"}) { thread { isResolved } } }" \
    --jq '.data.resolveReviewThread.thread.isResolved'
}

FIXED_X='Fixed in <sha>. <behaviour now>. Test: <name>.'
NOT_BUG_Y='Reviewed, not a defect. <evidence: spec line / role leaf / existing test>.'

reply_and_resolve 3790734403 PRRT_kwDO…0W "$FIXED_X"
reply_and_resolve 3790734406 PRRT_kwDO…0Y "$NOT_BUG_Y"
```

## Confirm

```bash
gh api graphql -f query='query { repository(owner:"OWNER", name:"REPO"){
  pullRequest(number:PR){ reviewThreads(first:100){ nodes { isResolved } } } } }' \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)] | length'
# 0 == every thread resolved
```

## Notes

- A reply from a bot's own account is not needed; your reply + resolve is the record.
- If a resolve mutation returns nothing, you likely lack write access or the thread id is
  stale, re-query `reviewThreads`.
- Outdated comments (the code moved) still resolve the same way; resolving marks the
  conversation done regardless of the diff position.
