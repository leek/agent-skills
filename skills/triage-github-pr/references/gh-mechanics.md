# GitHub mechanics for PR triage

`gh` expands `{owner}/{repo}` when run inside the repo. `N` is the PR number.

## Gather

```bash
gh pr view N --json number,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,headRefOid,baseRefName,statusCheckRollup,reviewRequests,commits,url
gh pr diff N
gh pr checks N --json name,state,bucket,link \
  --jq '.[] | select(.bucket == "fail") | {name, link}'   # finished failures on the head
# A GitHub Actions link ends in /job/<job-id>: read only the failed steps
gh run view --job <job-id> --log-failed
# Reviews: state, body, and the commit each one reviewed
gh api repos/{owner}/{repo}/pulls/N/reviews --paginate \
  --jq '.[] | {id, user: .user.login, state, commit: .commit_id[:8], at: .submitted_at, body}'
# Inline comments: where most actionable findings live
gh api repos/{owner}/{repo}/pulls/N/comments --paginate \
  --jq '.[] | {id, user: .user.login, path, line: (.line // .original_line), commit: .commit_id[:8], body}'
# Issue comments: bot summaries and humans not on a line
gh api repos/{owner}/{repo}/issues/N/comments --paginate \
  --jq '.[] | {id, user: .user.login, at: .updated_at, body}'
```

## In-flight signals

```bash
gh pr view N --json reviewRequests -q '.reviewRequests[].login'          # unsubmitted reviewers
gh api repos/{owner}/{repo}/issues/N/reactions --jq '.[] | select(.user.type == "Bot") | {u: .user.login, c: .content}'
gh pr view N --json statusCheckRollup -q '.statusCheckRollup[] | select(.status != "COMPLETED") | .name'
```

Verified bot behaviour (2026-09):

- **Codex** (`chatgpt-codex-connector[bot]`) reacts with `eyes` while a review runs. It
  reacts `+1` when it finishes with no findings, and posts review comments when it has
  some. Its `<!-- codex-pull-request-review-summary -->` issue comment holds a
  Status/Commit table. It re-reviews on PR open, on ready-for-review, and on an
  `@codex review` comment, **not on every push**.
- **Copilot** (`copilot-pull-request-reviewer[bot]`) submits a `COMMENTED` review, whose
  `commit_id` is the commit it reviewed.

## Merge gates

- `mergeable`: `CONFLICTING` means rebase or resolve. `UNKNOWN` means GitHub is still
  computing, so re-poll.
- `mergeStateStatus`: `CLEAN` or `UNSTABLE` (a non-required check failed) means go.
  `BLOCKED` means an approval or required check is missing: a pending required check is
  not a reason to wait (see Merge). `BEHIND` means run `gh pr update-branch N`, then
  merge without waiting for the new CI run. `DIRTY` means conflicts.
- `reviewDecision`: `CHANGES_REQUESTED` blocks. `REVIEW_REQUIRED` blocks when branch
  protection requires a review.
- `isDraft`: run `gh pr ready N` only when the context implies the PR should ship.

## Check out the head branch safely

- The branch is already checked out in another worktree (`git worktree list`): work
  there, or run `git switch --detach origin/<head>` and push with
  `git push origin HEAD:<head>`.
- The tree is clean: `gh pr checkout N`.
- The tree is dirty: run `git fetch origin && git worktree add .claude/worktrees/pr-N <head>`,
  work and push from there, then `git worktree remove` it.

## Merge

```bash
gh pr merge N --squash --delete-branch          # or --rebase / --merge
gh pr view N --json state,mergedAt,mergeCommit
```

If the merge is refused only because required checks are still pending, re-run it with
`--auto` so GitHub lands it when they pass, and report it as queued. Do not wait.
