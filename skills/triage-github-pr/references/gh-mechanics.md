# GitHub mechanics for PR triage

`N` is the PR number. `<this-skill-dir>` is the triage-github-pr skill's directory.

Every read and write of a PR's review state goes through one script,
[`scripts/pr.sh`](../scripts/pr.sh), run from the repo: `state` (the gate snapshot),
`comments` (the comment surfaces, grouped into threads), `reply` (reply and resolve), and
`disposition` (your disposition comment). Its header names every subcommand's fields,
flags, and exit codes; never write a raw `gh api` call or a comment marker for these by
hand. Other skills run it as `<this-skill-dir>/../triage-github-pr/scripts/pr.sh`.

## Gather

```bash
bash <this-skill-dir>/scripts/pr.sh state N    # the gate snapshot; several numbers give one row each
gh pr view N --json body,commits
gh pr diff N
```

The gate snapshot holds, per PR, the metadata and merge gates, the finished failures on
the head (`checks_failed`), the in-flight signals, `threads_open`, `rounds`,
`stacked_above`, `code_review` (the trusted `<!-- code-review: head=<sha> model=<model> -->`
marker from your own same-repo PR body, or null), and the `repo` settings; the sections below name the fields they use.
A field listed in `unchecked` is null because its read failed: not checked, never zero
or empty. Run it again wherever a step re-reads a gate.

The three comment surfaces (reviews, inline review threads, issue comments) and your
login come from `pr.sh comments`. Save the first run as the snapshot:

```bash
bash <this-skill-dir>/scripts/pr.sh comments N | tee <scratch>/pr-N-snapshot.json   # step 3
bash <this-skill-dir>/scripts/pr.sh comments N --since <scratch>/pr-N-snapshot.json  # step 6: new or edited only
bash <this-skill-dir>/scripts/pr.sh comments N --count                              # unresolved threads
```

Its JSON holds `reviews`, `threads`, `issue`, `me`, `pr_author`, `head`, `threads_open`,
and `disposition`. Each entry in `threads` is one inline review thread, already whole:
its `root` (the comment a reply goes to), `thread` (the id that resolves it), `resolved`,
the root's `path`, `line`, and reviewed `commit`, and its `comments`, oldest first. Every
row carries `bot`, `assoc` (author_association), `agent` (an agent wrote it, though it
shows under your login), and `owner` (a human owner wrote it, so its answer is a
direction). The snapshot is every `{id, at}` pair in it. `--since` prints only an id not
in it, or an id whose `at` changed (bots often edit a summary comment in place instead of
posting another), and never an agent's row; a thread with any new comment comes back
whole, each comment marked `new`.

**Earlier answers.** A comment with `agent` true is an earlier answer to its thread; the
thread's `agent_reply` is the newest one's url, the link a repeat cites. An `owner`
comment is a direction, never an earlier answer. The disposition comment's table is the
rest: the findings that live outside inline threads.

## In-flight signals

The snapshot ([Gather](#gather)) holds them: `requested_reviewers` (unsubmitted),
`bot_reactions` (`{user, content}`), `reviews_owed` (`{reviewer, why}`, read from the
PR timeline), `head_pushed_at`, and `checks_pending` (every unfinished check, by name).

`checks_pending` lists CI too. Only a review bot's own check counts as a review in
flight; ignore the rest for that purpose. Required human approvals are checked
separately.

**Taking the wait.** Each checkpoint watches the reviewers with this one background
command, capped at what is left of the PR's 10-minute review-wait budget. Wait on it per
[harness-tools](../../harness-tools/SKILL.md) (move: waiting on a background shell command)
(without background commands, schedule one check every 5 minutes up to the cap, or name
the reviewers still running and treat it as the cap):

```bash
bash <this-skill-dir>/../run-after/scripts/wait-until.sh --interval 30 --timeout <seconds left of the PR's 10-minute budget> -- bash <this-skill-dir>/scripts/pr.sh state N --in-flight --no-required --check "<a review bot's own check>"
```

`--in-flight` counts every requested reviewer, every bot `eyes` reaction, every entry
in `reviews_owed`, and a PR pushed, opened, or marked ready under two minutes ago (bots
take up to a minute to register each, so a read right after one would look clear). `--no-required` keeps
required CI out of the wait; pass one `--check` per pending check you judged a review
bot's own, or none. Several PR numbers make one wait for the queue, which spends that
time from every listed PR's budget; use `--interval 60` for a queue, since each read
costs five API calls per PR. The verdict is
`passed` (nothing in flight: gather now), `timeout` (the cap: gather what arrived, and
carry what is still running to the late-review sweep), or `failed` (a read failed:
run it once more in the foreground; failing again,
the reviewers' state is unknown, which is the cap too). Its `detail` names what was
still running in `counted`.

Verified bot behaviour (2026-10):

- **Both bots review every push**, starting up to a minute after it. Resolve completed
  fixes before pushing (step 5); after the final allowed batch, merge and let the
  late-review sweep collect that run, carrying its findings instead of buying another push.
- **Codex** (`chatgpt-codex-connector[bot]`) reacts with `eyes` while a review runs. It
  reacts `+1` when it finishes with no findings, and posts review comments when it has
  some. Its `<!-- codex-pull-request-review-summary -->` issue comment, edited in place,
  carries `<!-- codex-review-state:v1 {"code_review":{"commit_sha","status"}} -->`:
  `running` while it reviews, `completed` with the commit when done. A
  `"security_review"` beside it has the same shape and stays null until Codex starts
  one. `reviews_owed` counts a running security review too, so the one wait covers
  both; never write a second wait for it. (2026-11)
- **Copilot** (`copilot-pull-request-reviewer[bot]`, `Copilot` in the timeline) is
  re-requested on each push and submits a `COMMENTED` review, whose `commit_id` is the
  commit it reviewed. Its pending request was seen in the issue timeline but not in
  `reviewRequests`: a merge on 2026-11-14 read "no requested reviewers" while Copilot's
  review was a minute out. `reviews_owed` reads the timeline for that reason.

## CI failures

Each failed check on the head (the snapshot's `checks_failed`) is a finding. Read them
all in one call, pinned to the head commit, with the raw logs kept on disk:

```bash
bash <this-skill-dir>/../fix-ci-failures/scripts/failed-jobs.sh --pr N --out <scratch>/pr-N-ci
```

It prints each failing workflow's failed jobs with `name`, `url`, `first_errors`, and
`log` (the full log's path): read the log around an error only when `first_errors` does
not settle it. A `checks_failed` entry with no job here is another CI system's: read its `link`.

Mark a failure LEGIT only when the error points at
code this PR changed and the error reproduces at the head. Flaky tests, infra errors,
and failures that also happen on the base are not caused by the PR, so mark them
AUTO-DISMISS.

CI gets **one** fix pass per triage. Include finished failures from the initial
snapshot in batch 1. If that CI pass is unused, a newly verified BLOCKING or MAJOR
failure can join bounded batch 2; after the fix budget, classify and carry new
failures. An actual branch-protection refusal remains a blocker. Exhaustive mode can
use its one CI fix pass within its round budget.

## Merge gates

- `mergeable`: `CONFLICTING` means rebase or resolve. `UNKNOWN` means GitHub is still
  computing: re-poll with the host wait/yield mechanism for at most one minute, then
  report that gate as unresolved. This does not reset the review or fix budget.
- `merge_state`: `CLEAN` or `UNSTABLE` (a non-required check failed) means go.
  `BLOCKED` means an approval or required check is missing: a pending required check is
  not a reason to wait (see Merge). `BEHIND` means update the branch only within the
  remaining push budget, combining it with pending fixes when possible, then review
  the new head without waiting on CI. If no push remains or it is behind again at
  the retry, report a blocker instead of looping.
  `DIRTY` means conflicts.
- `review`: `CHANGES_REQUESTED` blocks, and pushing a fix does not clear it.
  `REVIEW_REQUIRED` blocks when branch protection requires a review, and your own
  review does not satisfy it: GitHub never lets a PR's author approve it.
- `draft`: run `gh pr ready N` only when the context implies the PR should ship.
- in flight: before batch 2, `pr.sh state N --in-flight --no-required` (with the review
  bots' own `--check`s) must read clear after the last push. Watch it by
  [Taking the wait](#in-flight-signals). After a spent budget or batch 2 it is not a
  gate: the late-review sweep collects what is still running.

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
- a merge question (draft intent, stacked PR,
  deploy-branch base: `production`, `staging`, or any branch the project context names)
  that the user answered with "hold" in this conversation.

## Check out the head branch safely

Never reuse a checkout without proof that it is the PR head. Before the first change,
`git rev-parse HEAD` must equal the snapshot's `head_sha`; if it does not, use a fresh worktree.

- **Fork PR** (`cross_repo` is true): you can push only when
  `maintainer_can_modify` is true; otherwise stop, naming that as the blocker. A push
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

A new worktree starts bare (no `vendor/`, no `.env`): make it runnable with `laravel-herd-worktrees`' **Bootstrap a bare worktree** section before running anything in it. Its last check proves `HEAD` equals `head_sha`, which also catches a helper that branched off the default branch.

**Return the main checkout.** When a PR you checked out in the main checkout is done
(merged, queued, or stopped), switch it back to what you recorded before the next PR:
`git switch <branch>`, or `git switch --detach <sha>`. If git refuses, report it, and
leave the tree as it is.

At step 7, once the PR shows merged, `cd` back to the main checkout and remove
`.claude/worktrees/pr-N` by `laravel-herd-worktrees`' **Remove a served worktree**
(`remove-worktree.sh --drop-databases`; it never forces, and a refusal means unsaved work, so report it).
A stopped or `--auto`-queued PR keeps its worktree unless the user selects it at step 7.

## A test failing outside your fix

A test failing outside your fix runs on the starting SHA first: with your work
committed, `git switch --detach <starting sha>` in the same worktree, run that one test,
then switch back to your tip. Failing there too, it is a finding against the PR, not a
defect of your fix to debug: write its step 4 line and publish it now. It joins this
batch when the shipping budget makes it eligible; otherwise it is carried.

## Reply and resolve

Reply to review threads and resolve them as one batch. Write one item per thread to a
scratch file, then run `pr.sh reply`, which writes to GitHub:

```json
[{"comment_id": 3790734403, "thread": "PRRT_kwDO…0W", "body": "fixed in abc123; validated; push pending", "resolve": true},
 {"comment_id": 3790734406, "thread": "PRRT_kwDO…0Y", "body": "Reviewed, not a defect. <evidence>.", "resolve": true}]
```

```bash
bash <this-skill-dir>/scripts/pr.sh reply N <scratch>/pr-N-replies.json
```

`comment_id` is the thread's `root` and `thread` its `thread` in `pr.sh comments`'
output; `body` is sent exactly as written, marked as the agent's so later reads flag it
`agent`, and `resolve` follows the table below. It prints each item's `reply_url`,
`replied`, `resolved`, and `error`, then `threads_open`; an invalid file exits 2 with
nothing sent. On exit 1, retry only the items with an `error`, never the whole file: an
item with `replied: false` goes again as it was; an item with `replied: true, resolved:
false` already has its reply on GitHub, so send it resolve-only, which posts nothing:

```json
[{"comment_id": 3790734403, "thread": "PRRT_kwDO…0W", "body": null, "resolve": true}]
```

An `error` on the resolve means no write access or a stale thread id: run
`pr.sh comments N` again for the thread id first. Outdated comments (the code moved)
resolve the same way. `threads_open` there (or `pr.sh comments N --count`) is 0 when
every thread is resolved, across every page; null means the count was not read, so run
`--count`.

Bodies and resolution by delivery state:

| State | Reply | Resolve? |
|---|---|---|
| Verified LEGIT, eligible for current batch | `<severity>; verified; fixing in current batch` | No |
| Validated and committed | `fixed in <sha>; validated; push pending` | Yes |
| Carried LEGIT | `<severity>; carried to a follow-up PR` (add the link after opening it) | Yes |
| AUTO-DISMISS or HALLUCINATION | One-line evidence | Yes |
| Answered QUESTION | `decided by owner: <answer>` | Yes |
| Directed agreement, fixed | `fixed in <sha> as directed: <what changed>; push pending` | Yes |
| Directed refusal | `Left as is, per <author>'s reply: <reason>` | Yes |
| STALE or repeat | `repeat of <earlier reply url>` | Yes |
| Unanswered QUESTION | The pending owner decision | No |

Publish the classification reply before coding, then reply again when its state
changes. Before each batch is sent, run the directed-reply check in
[Reply to a directed thread](../../resolve-review-comments/references/threads.md#reply-to-a-directed-thread). A local fix SHA is the same after pushing, but is not yet remotely available;
record the published head in the disposition only after the push succeeds. Re-query
the unresolved thread count (`pr.sh comments N --count`; `pr.sh reply` prints it too) before pushing, right after each push, and before merging:
a reviewer watching the PR sees each batch's threads close as it lands, not all at the end. An unresolved owner decision
or accepted-but-unfixed current-batch finding stays visible, not falsely resolved.

## Count rounds

A round is a push to the head branch after the PR opened. Reconcile bounded batch
SHAs against this history; [exhaustive mode](exhaustive-triage.md#round-budget) uses
the total count as its five-round limit. The count is the snapshot's `rounds`
([Gather](#gather)): the pushes in GitHub's activity feed for the head branch after the
PR's `createdAt`, force pushes and `gh pr update-branch` merges included, read from the
head repository, so a fork PR counts the fork's pushes.

The push that opened the PR predates `createdAt`, so it is round 0. Recount before every
classification and every merge: anyone may have pushed since.

## Disposition comment

One issue comment per PR, owned by you, edited in place as claims are verified and
delivery states change. Publish it before coding and keep it current during each
batch. It records the delivery mode, starting SHA, snapshot, batch checkpoint,
review-wait budget used, verdicts and push count; GitHub activity owns that count:

```markdown
**Triage, round N** at `<head sha>`
Mode: bounded | exhaustive
Starting head: <sha>; snapshot: <ids and timestamps, or artifact link>
Batch: <number>; not needed | fixing | validated at <sha>
Checkpoint: <initial / after batch 1 / after batch 2 / exhaustive round N>; review wait used: <minutes of the PR's 10>, <clear | capped: reviewers still running | not waited: after batch 2>
Active wait started: <timestamp, or not waiting>
Published head: <sha, or push pending>

| Finding | Author | Where | Verdict | Delivery state |
|---|---|---|---|---|
| <one-line claim> | <login> | <path:line or review/comment link> | LEGIT <severity> / stale / auto-dismiss / hallucination / decided by owner | fixing / validated commit, push pending / fixed at published head / carried / resolved / pending decision |

Carried findings: <each carried finding, with its link; the follow-up PR link once opened>
Open threads: <live count, separated into fixing and pending decisions>
Blocker: <only in a stop case>
```

Read the current one from `pr.sh comments N`'s `disposition` (`{id, url, body}`; null
when you have none, or when `me` is empty, which means not checked). Write the whole new
body to a scratch file, then:

```bash
bash <this-skill-dir>/scripts/pr.sh disposition N <scratch>/pr-N-disposition.md
```

It edits your disposition comment in place, or posts it the first time, and prints
`{pr, id, url, action}`. It adds the comment's marker itself (and replaces an older
run's), so the body never carries one. It refuses a body that @-mentions anyone, since a
mention of a bot (`@codex`) triggers a review: write the login without the `@`, or put it (or code such as
`@param`) in backticks. Exit 1
means nothing was written or the write failed (its stderr says which); run it again
once the cause is fixed.

## Scratch databases

Run tests against the repo's configured test database when you can. When the run
needs its own (a worktree `.env`, a throwaway test database), name it
`<app db>_pr<N>`, never a name the main checkout's `.env`, `.env.testing`, or
`phpunit.xml` uses, and register it the moment you create it, per `laravel-herd-worktrees`'
[Scratch database registry](../../laravel-herd-worktrees/SKILL.md#scratch-database-registry)
(`bash <this-skill-dir>/../laravel-herd-worktrees/scripts/scratch-db.sh register <pgsql|mysql> <database> <worktree path, or ->`).

A browser check needs a database at the PR branch's schema. The main checkout's
development database is often behind the base branch, and a login that fails on a
missing column is that stale schema, not a PR defect. So before opening the browser,
point the worktree at a scratch database as above, then migrate and seed it with the
repo's own commands (`php artisan migrate --seed` unless its docs name another). Never
migrate the main checkout's database for a review. Record a browser check as skipped
only after this was tried and failed, with the error.

At step 7, once the PR shows merged (or the user selected it), a database registered for
the worktree goes with it (the removal's `--drop-databases`). For one registered with `-`
(no worktree), run
`bash <this-skill-dir>/../laravel-herd-worktrees/scripts/scratch-db.sh drop <database>`: it
drops the database and its parallel-testing copies (`<database>_test_<N>`) and unregisters
each. Either way the JSON has `dropped` and `kept` (each with its `reason`); name a kept one
in the report. A database the user kept stays registered for `repository-cleanup`.

## Merge

```bash
gh pr merge N --squash --match-head-commit <reviewed head sha>  # or the repo's Merge method; never --delete-branch
gh pr view N --json state,mergedAt,mergeCommit,autoMergeRequest
```

A PR in a stack (its base is another PR's head, or the snapshot's `stacked_above` is not
empty) merges
with `--merge` instead, bottom-up, and the PRs above it are retargeted after: see
[Stacked PRs](stacked-prs.md).

`--match-head-commit` makes GitHub refuse the merge when the head moved after your
re-check. Refresh, review the changed range and retry this checkpoint once. A second
head movement is a reported concurrency blocker, not another fix round. For other
merge failures, inspect the refusal, perform one applicable correction within the
budget, then report any remaining gate rather than repeating indefinitely.

**Concurrent head changes.** An external head change gets one refreshed
review/checkpoint attempt, shared across push refusals and the pinned merge. A second
concurrent head movement or push refusal stops the run with concurrent changes
reported; it does not restart the batch or snapshot.

Never pass `--delete-branch`, and never delete a branch by any other route
(`git push --delete`, `gh api -X DELETE .../git/refs/...`). A branch deleted outside a
merge closes every open PR that uses it as its base. When the repo has "automatically
delete head branches" on (the snapshot's `repo.delete_branch_on_merge` is `true`), the merge deletes the head branch and GitHub retargets the PRs based on it
to the merged PR's base ([changelog, 2020-05](https://github.blog/changelog/2020-05-19-pull-request-retargeting));
the retarget check in [Stacked PRs](stacked-prs.md) confirms it. Do not change that
repo setting yourself.

If the merge is refused only because required checks are still pending, re-run it with
`--auto` (keeping `--match-head-commit`) so GitHub lands it when they pass, and report
it as queued: `autoMergeRequest` is set. Do not wait.

## Follow-up PR

After the merge, gather the comment surfaces once more for findings that have arrived.
A merge after batch 2, on "merge now", or after a spent budget skips the review wait,
so reviews may still be running; the late-review sweep below waits for them while this
follow-up is built. Classify new claims, then branch from the merged
base, fix all verified carried findings, and open a follow-up PR linking the merged PR
and each finding. Review and validate its fixes before opening it. Report the link;
leave it open and triage it only when the user names it. If the original is stopped or
auto-merge queued, record carried findings and the pending follow-up instead of
branching from an unmerged base.

**Late-review sweep.** A review that was in flight at the merge lands after that one
gather. So as the run's last GitHub step, after the last named PR and before clean-up,
gather every PR this run merged once more (`pr.sh comments --since` its snapshot, and
every review or comment dated after its merge). When a review is still in flight on one
(`pr.sh state` on merged PRs reads the same), watch it first by
[Taking the wait](#in-flight-signals), one wait for all of them, capped at 20 minutes.
Classify what arrived; verified findings join that PR's
follow-up PR (opened now if it had none). The report carries one line per merged PR:
`late reviews: none as of <time>`, the findings and their follow-up link, or
`late reviews: <reviewer> still running at <time>` when the cap ran out.
