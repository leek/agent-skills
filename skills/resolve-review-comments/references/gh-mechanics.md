# GitHub mechanics

`OWNER/REPO` from `gh repo view --json nameWithOwner -q .nameWithOwner`; `PR` is the
pull-request number.

## Read the three comment surfaces

Review comments live in three places (reviews, inline review threads, issue comments),
and REST cannot resolve a thread. One read-only script pulls all three, paginated, with
each inline comment's GraphQL thread id (`thread`, the `PRRT_…` that resolves it) and
`resolved` flag. `<triage-dir>` is the `triage-github-pr` skill's directory, beside this
one:

```bash
bash <triage-dir>/scripts/pr-comments.sh PR            # reviews, inline, issue, threads_open
bash <triage-dir>/scripts/pr-comments.sh PR --count    # {threads_open}: the confirm step
```

Its header names every field ([`pr-comments.sh`](../../triage-github-pr/scripts/pr-comments.sh)).

The PR's commit range, to compare a reviewed commit against HEAD:

```bash
gh pr view PR --json headRefOid,commits
git log --oneline BASE..HEAD      # what the reviewer had vs what exists now
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

`pr-comments.sh PR --count` prints `threads_open`; 0 means every thread is resolved,
across every page.

## Notes

- A reply from a bot's own account is not needed; your reply + resolve is the record.
- If a resolve mutation returns nothing, you likely lack write access or the thread id is
  stale, run `pr-comments.sh PR` again.
- Outdated comments (the code moved) still resolve the same way; resolving marks the
  conversation done regardless of the diff position.
