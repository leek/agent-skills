# GitHub mechanics for PR triage

`gh` expands `{owner}/{repo}` when run inside the repo. `N` is the PR number.

## Gather

```bash
gh pr view N --json number,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,headRefOid,baseRefName,isCrossRepository,maintainerCanModify,statusCheckRollup,reviewRequests,commits,url
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
  --jq '.[] | {id, user: .user.login, path, line: (.line // .original_line), commit: .commit_id[:8], at: .updated_at, reply_to: .in_reply_to_id, url: .html_url, body}'
# Issue comments: bot summaries and humans not on a line
gh api repos/{owner}/{repo}/issues/N/comments --paginate \
  --jq '.[] | {id, user: .user.login, at: .updated_at, url: .html_url, body}'
gh api user --jq .login   # you: your replies and your disposition comment carry this login
```

The snapshot is every `{id, at}` pair from the three comment calls. At step 6, an id
not in it, or an id whose `at` changed, is new: bots often edit a summary comment in
place instead of posting another. Your own replies and your disposition comment are
never new.

**Earlier answers.** An inline comment by you with a `reply_to` is your answer to the
thread it replies to; its `url` is the link a repeat cites. The disposition comment's
table is the rest: the findings that live outside inline threads.

## In-flight signals

```bash
gh pr view N --json reviewRequests -q '.reviewRequests[].login'          # unsubmitted reviewers
gh api repos/{owner}/{repo}/issues/N/reactions --jq '.[] | select(.user.type == "Bot") | {u: .user.login, c: .content}'
# Pending checks. A CheckRun has .status; a commit StatusContext has only .state.
gh pr view N --json statusCheckRollup -q '.statusCheckRollup[]
  | select(if .__typename == "StatusContext" then .state == "PENDING" or .state == "EXPECTED" else .status != "COMPLETED" end)
  | (.name // .context)'
```

This lists CI too. Only a review bot's own check counts as a review in flight; ignore
the rest for that purpose. These signals use the main skill's recorded optional-wait
budget, not an unlimited merge gate. Required human approvals are checked separately.

Verified bot behaviour (2026-10):

- **Both bots review every push.** A new run may start after the push. Resolve completed
  fixes before pushing (step 5); after the final allowed batch, gather available
  findings and carry them instead of waiting for that new run and buying another push.
- **Codex** (`chatgpt-codex-connector[bot]`) reacts with `eyes` while a review runs. It
  reacts `+1` when it finishes with no findings, and posts review comments when it has
  some. Its `<!-- codex-pull-request-review-summary -->` issue comment holds a
  Status/Commit table whose trigger reads `New commits` on a push re-review.
- **Copilot** (`copilot-pull-request-reviewer[bot]`) submits a `COMMENTED` review, whose
  `commit_id` is the commit it reviewed.

## CI failures

Each failed check on the head is a finding. Mark it LEGIT only when the error points at
code this PR changed and the error reproduces at the head. Flaky tests, infra errors,
and failures that also happen on the base are not caused by the PR, so mark them
AUTO-DISMISS.

## Merge gates

- `mergeable`: `CONFLICTING` means rebase or resolve. `UNKNOWN` means GitHub is still
  computing: re-poll with the host wait/yield mechanism for at most one minute, then
  report that gate as unresolved. This does not reset the review or fix budget.
- `mergeStateStatus`: `CLEAN` or `UNSTABLE` (a non-required check failed) means go.
  `BLOCKED` means an approval or required check is missing: a pending required check is
  not a reason to wait (see Merge). `BEHIND` means update the branch only within the
  remaining push budget, combining it with pending fixes when possible, then review
  the new head without waiting on CI. If no push remains or it is behind again at
  the retry, report a blocker instead of looping.
  `DIRTY` means conflicts.
- `reviewDecision`: `CHANGES_REQUESTED` blocks, and pushing a fix does not clear it.
  `REVIEW_REQUIRED` blocks when branch protection requires a review, and your own
  review does not satisfy it: GitHub never lets a PR's author approve it.
- `isDraft`: run `gh pr ready N` only when the context implies the PR should ship.

## Stop cases

Stop instead of merging when:

- branch protection refuses the merge because a required check failed or a required
  approval is missing (`REVIEW_REQUIRED`);
- a conflict would change intent;
- a human `CHANGES_REQUESTED` stands. After you push its fix, re-request that reviewer
  (`gh pr edit N --add-reviewer <login>`) and name them as the blocker. Dismiss a
  review only when the guidance or project context says to;
- a QUESTION the user answered with "hold", or a decision that belongs to someone
  other than the user (an infra or product owner);
- the guidance says not to merge;
- a merge question (draft intent, stacked PR, deploy-branch base: `production`,
  `staging`, or any branch the project context names) that the user answered with
  "hold" in this conversation.

## Check out the head branch safely

Never reuse a checkout without proof that it is the PR head. Before the first change,
`git rev-parse HEAD` must equal `headRefOid`; if it does not, use a fresh worktree.

- **Fork PR** (`isCrossRepository` is true): you can push only when
  `maintainerCanModify` is true; otherwise stop, naming that as the blocker. A push
  refused with 403 while it is true means an organization owns the fork, which blocks
  maintainer pushes: treat it as false, and offer merge-then-follow-up-PR in the report. Run
  `git worktree add --detach .claude/worktrees/pr-N`, `cd` into it, run
  `gh pr checkout N` there (it tracks the fork's branch), and push with `git push`.
- **The tree is clean** and no other worktree has the branch: first record where the
  main checkout is (`git branch --show-current`, or `git rev-parse HEAD` when that
  prints nothing), then `gh pr checkout N`. If it refuses because a local branch of
  that name has diverged, use the worktree below.
- **Otherwise** (a dirty tree, or the branch checked out in another worktree, which may
  hold someone's unsaved work): `git fetch origin && git worktree add --detach
  .claude/worktrees/pr-N origin/<head>`, always at that path, never a sibling
  directory. Work there, and push with `git push origin HEAD:<head>` (no `--force`;
  if the push is refused, refresh step 3 once within the existing batch and review
  the changed head. A second concurrent refusal or head movement is a reported
  concurrency blocker, not a new batch or snapshot).

A new worktree starts bare (no `vendor/`, no `.env`): make it runnable with `laravel-herd-worktrees`' **Bootstrap a bare worktree** section before running anything in it. Its last check proves `HEAD` equals `headRefOid`, which also catches a helper that branched off the default branch.

**Return the main checkout.** When a PR you checked out in the main checkout is done
(merged, queued, or stopped), switch it back to what you recorded before the next PR:
`git switch <branch>`, or `git switch --detach <sha>`. If git refuses, report it, and
leave the tree as it is.

At step 7, once the PR shows merged, `cd` back to the main checkout and remove
`.claude/worktrees/pr-N` by `laravel-herd-worktrees`' **Remove a served worktree** (it never forces; if it refuses, the tree
holds unsaved work, so report it instead). A stopped or `--auto`-queued PR keeps its
worktree unless the user selects it at step 7.

## Reply and resolve

Reply to an inline comment, then resolve its thread. Map comment ids to thread ids
first: REST cannot resolve, and GraphQL `reviewThreads` gives the thread id (`PRRT_…`)
with its comments' `databaseId` (the REST comment id).

```bash
gh api graphql --paginate -F owner='{owner}' -F repo='{repo}' -F pr=N -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $pr) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | {thread: .id, resolved: .isResolved, comment: .comments.nodes[0].databaseId}'
gh api repos/{owner}/{repo}/pulls/N/comments/COMMENT_ID/replies -f body="$BODY"
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "PRRT_…"}) { thread { isResolved } } }'
```

Keep `$BODY` free of apostrophes and backticks. A resolve that returns nothing means no
write access or a stale thread id: re-query the threads.

Bodies and resolution by delivery state:

| State | Reply | Resolve? |
|---|---|---|
| Verified LEGIT, eligible for current batch | `<severity>; verified; fixing in current batch` | No |
| Validated and committed | `fixed in <sha>; validated; push pending` | Yes |
| Carried LEGIT | `<severity>; carried to a follow-up PR` (add the link after opening it) | Yes |
| AUTO-DISMISS or HALLUCINATION | One-line evidence | Yes |
| Answered QUESTION | `decided by owner: <answer>` | Yes |
| STALE or repeat | `repeat of <earlier reply url>` | Yes |
| Unanswered QUESTION | The pending owner decision | No |

Publish the classification reply before coding, then reply again when its state
changes. A local fix SHA is the same after pushing, but is not yet remotely available;
record the published head in the disposition only after the push succeeds. Re-query
the unresolved thread count before pushing, right after each push, and before merging:
a reviewer watching the PR sees each batch's threads close as it lands, not all at the end. An unresolved owner decision
or accepted-but-unfixed current-batch finding stays visible, not falsely resolved.

## Count rounds

A round is a push to the head branch after the PR opened. Reconcile bounded batch
SHAs against this history; [exhaustive mode](exhaustive-triage.md#round-budget) uses
the total count as its five-round limit. GitHub's activity feed records every push, force
pushes and `gh pr update-branch` merges included:

```bash
created=$(gh pr view N --json createdAt --jq .createdAt)
head=$(gh pr view N --json headRefName --jq .headRefName)
gh api --paginate "repos/{owner}/{repo}/activity?ref=refs/heads/$head&activity_type=push&per_page=100" \
  --jq "[.[] | select(.timestamp > \"$created\")] | length" | paste -sd+ - | bc
```

The push that opened the PR predates `createdAt`, so it is round 0. Recount before every
classification and every merge: anyone may have pushed since. A fork PR's pushes live
in the fork: run the same call against the head repository
(`gh pr view N --json headRepositoryOwner,headRepository`).

## Disposition comment

One issue comment per PR, owned by you, edited in place as claims are verified and
delivery states change. Publish it before coding and keep it current during each
batch. It records the delivery mode, starting SHA, snapshot, batch checkpoint,
optional wait used, verdicts and push count; GitHub activity owns that count:

```markdown
<!-- triage-disposition -->
**Triage, round N** at `<head sha>`
Mode: bounded | exhaustive
Starting head: <sha>; snapshot: <ids and timestamps, or artifact link>
Batch: <number>; not needed | fixing | validated at <sha>
Optional review wait used: <total minutes of 20>
Checkpoint: <initial / after batch 1 / exhaustive round N>; wait used: <minutes of 10>
Active wait started: <timestamp, or not waiting>
Published head: <sha, or push pending>

| Finding | Author | Where | Verdict | Delivery state |
|---|---|---|---|---|
| <one-line claim> | <login> | <path:line or review/comment link> | LEGIT <severity> / stale / auto-dismiss / hallucination / decided by owner | fixing / validated commit, push pending / fixed at published head / carried / resolved / pending decision |

Carried findings: <each carried finding, with its link; the follow-up PR link once opened>
Open threads: <live count, separated into fixing and pending decisions>
Blocker: <only in a stop case>
```

Find it, then create or edit it:

```bash
me=$(gh api user --jq .login)
gh api repos/{owner}/{repo}/issues/N/comments --paginate \
  --jq ".[] | select(.user.login == \"$me\" and (.body | test(\"<!-- triage-(disposition|round: [0-9]+) -->\"))) | {id, url: .html_url, body}"
gh api repos/{owner}/{repo}/issues/N/comments -F body=@<file>                 # first time
gh api -X PATCH repos/{owner}/{repo}/issues/comments/COMMENT_ID -F body=@<file>   # later rounds
```

Write the body to a scratch file and pass it with `-F body=@<file>` (`-f` would send the literal path), so markdown and
quotes survive. Never mention a bot (`@codex`) in it: a mention triggers a review.
When more than one such comment exists, edit only the newest. An older run's
`<!-- triage-round: N -->` marker is replaced by `<!-- triage-disposition -->` on the
first edit.

## Scratch databases

Run tests against the repo's configured test database when you can. When the run
needs its own (a worktree `.env`, a throwaway test database), name it
`<app db>_pr<N>`, never a name the main checkout's `.env`, `.env.testing`, or
`phpunit.xml` uses, and register it the moment you create it:

```bash
printf '%s\t%s\t%s\t%s\n' "$(date +%s)" <pgsql|mysql> <database> "<worktree path, or ->" \
  >> "$(git rev-parse --path-format=absolute --git-common-dir)/scratch-databases"
```

At step 7, once the PR shows merged (or the user selected it), drop the database and
its parallel-testing copies (`<database>_test_<N>`) with the repo's client
(`DROP DATABASE IF EXISTS`), then delete its line from that file. A database the user
kept stays registered for `repository-cleanup`.

## Merge

```bash
gh pr list --base <head> --state open --json number,title,url   # PRs stacked on this one
gh pr merge N --squash --match-head-commit <reviewed head sha>  # or the repo's Merge method; never --delete-branch
gh pr view N --json state,mergedAt,mergeCommit,autoMergeRequest
```

A PR in a stack (its base is another PR's head, or the list above is not empty) merges
with `--merge` instead, bottom-up, and the PRs above it are retargeted after: see
[Stacked PRs](stacked-prs.md).

`--match-head-commit` makes GitHub refuse the merge when the head moved after your
re-check. Refresh, review the changed range and retry this checkpoint once. A second
head movement is a reported concurrency blocker, not another fix round. For other
merge failures, inspect the refusal, perform one applicable correction within the
budget, then report any remaining gate rather than repeating indefinitely.

Never pass `--delete-branch`, and never delete a branch by any other route
(`git push --delete`, `gh api -X DELETE .../git/refs/...`). A branch deleted outside a
merge closes every open PR that uses it as its base. When the repo has "automatically
delete head branches" on (`gh api repos/{owner}/{repo} --jq .delete_branch_on_merge`
is `true`), the merge deletes the head branch and GitHub retargets the PRs based on it
to the merged PR's base ([changelog, 2020-05](https://github.blog/changelog/2020-05-19-pull-request-retargeting));
the retarget check in [Stacked PRs](stacked-prs.md) confirms it. Do not change that
repo setting yourself.

If the merge is refused only because required checks are still pending, re-run it with
`--auto` (keeping `--match-head-commit`) so GitHub lands it when they pass, and report
it as queued: `autoMergeRequest` is set. Do not wait.
