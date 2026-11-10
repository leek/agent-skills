# GitHub mechanics

`OWNER/REPO` from `gh repo view --json nameWithOwner -q .nameWithOwner`; `PR` is the
pull-request number.

## Read the three comment surfaces

Review comments live in three places (reviews, inline review threads, issue comments),
and REST cannot resolve a thread. One read-only script pulls all three, paginated, with
each inline comment's GraphQL thread id (`thread`, the `PRRT_…` that resolves it) and
`resolved` flag. `<this-skill-dir>` is this skill's directory; the scripts are the
`triage-github-pr` skill's, installed beside it:

```bash
bash <this-skill-dir>/../triage-github-pr/scripts/pr-comments.sh PR            # reviews, inline, issue, threads_open
bash <this-skill-dir>/../triage-github-pr/scripts/pr-comments.sh PR --count    # {threads_open}: the confirm step
```

Its header names every field ([`pr-comments.sh`](../../triage-github-pr/scripts/pr-comments.sh)).

The PR's commit range, to compare a reviewed commit against HEAD:

```bash
gh pr view PR --json headRefOid,commits
git log --oneline BASE..HEAD      # what the reviewer had vs what exists now
```

## Reply to every thread, then resolve it

Write one item per thread to a scratch file, then send the batch in one run of
[`pr-reply.sh`](../../triage-github-pr/scripts/pr-reply.sh), which writes to GitHub.
`comment_id` is the thread's root comment (`reply_to` null) and `thread` its `thread`
from `pr-comments.sh`; `body` is sent exactly as written.

```json
[{"comment_id": 3790734403, "thread": "PRRT_kwDO…0W", "body": "Fixed in <sha>. <behaviour now>. Test: <name>.", "resolve": true},
 {"comment_id": 3790734406, "thread": "PRRT_kwDO…0Y", "body": "Reviewed, not a defect. <evidence: spec line / role leaf / existing test>.", "resolve": true}]
```

```bash
bash <this-skill-dir>/../triage-github-pr/scripts/pr-reply.sh PR <scratch>/pr-PR-replies.json
```

It prints each item's `reply_url`, `resolved`, and `error`, then `threads_open`. An
invalid file exits 2 with nothing sent. On exit 1, send only the items with an `error`
again.

## Confirm

`threads_open` in that output (or `pr-comments.sh PR --count`) is 0 when every thread is
resolved, across every page; null means the count was not read, so run `--count`.

## Failed checks

After the wait, read the failed checks on the PR's head commit in one call:

```bash
bash <this-skill-dir>/../fix-ci-failures/scripts/failed-jobs.sh --pr PR --out <scratch>/pr-PR-ci
```

It prints each failing workflow's failed jobs with `first_errors` and `log` (the full
log's path); `[]` means no completed run on that commit failed.

## Notes

- A reply from a bot's own account is not needed; your reply + resolve is the record.
- An `error` on an item's resolve means you lack write access or the thread id is stale:
  run `pr-comments.sh PR` again.
- Outdated comments (the code moved) still resolve the same way; resolving marks the
  conversation done regardless of the diff position.
