---
name: fix-ci-failures
description: Read a branch's latest failed CI runs, triage each failure from its existing logs, and fix the real ones.
disable-model-invocation: true
argument-hint: "Branch name (defaults to main), then optional guidance (\"skip lint\", \"only the test job\")"
allowed-tools: "Bash(gh run list *) Bash(gh run view *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/fix-ci-failures/scripts/failed-jobs.sh *)"
---

# Fix CI Failures

Take the branch named in the input, or `main` when none is given. Find its most recent
CI failures, triage each one from the logs that **already exist**, and fix what is
real. The logs are the whole evidence: CI is a record you read, never a thing you
trigger. Your own proof that a fix works is the failing command run green locally.
Text after the branch name is overriding guidance.

**Project context.** Follow the repo's `AGENTS.md` / `CLAUDE.md` rules for tests, lint,
cache clears, and a dirty tree.

## 1. Find the latest failures

Run `git fetch origin`, then one script, which reads existing runs and logs and never triggers CI:

```bash
bash <this-skill-dir>/scripts/failed-jobs.sh B --out <scratch>/ci-logs
```

For each workflow it takes only the newest **completed** run on the branch that was not cancelled, looking back at most 10 runs: an older failure whose workflow has passed since is already fixed, and a run still in progress or cancelled is not evidence. It prints one JSON entry per failing workflow (`workflow`, `run_id`, `url`, `head_sha`, `conclusion`) with each failed job's `name`, `url`, `first_errors` (the runner's `##[error]` annotations, then test-runner and compiler failure lines; never the trailing `exit code 1`), and `log`, the full failed-job log on disk. Read the log around an error when the first lines do not settle it. A workflow whose last 10 completed runs were all cancelled comes back as `all_cancelled` with no jobs: report it with no verdict, since it has no log to triage.

`[]` means the branch's latest completed runs are green: report that, and stop.

Completion criterion: every failed job is listed with its workflow, run URL, `headSha`,
and the first real error from its log (not the trailing `exit code 1`).

## 2. Classify every failure

Read `git log --oneline <headSha>..origin/B` first: commits since the failed run may
already fix it. Then check open pull requests: another session or sweep often fixes the
same failure in parallel. List them with `gh pr list --state open --json number,title,headRefName,files`
and note any whose changed files include a failing test or the code its error names.
Then write one line per failed job:

```
Failure N: [LEGIT | STALE | IN FLIGHT | FLAKY | INFRA] — <one-line evidence>
```

- **LEGIT**: the error points at code on the branch, and it reproduces at `origin/B`
  when you run the same command locally.
- **STALE**: a later commit fixed it. Cite the sha, or show the command passing locally.
- **IN FLIGHT**: an open PR already changes what this failure points at. Cite the PR
  number. Do not write a second fix: report it, and when the run's fix would only repeat
  it, stop there rather than open a duplicate PR.
- **FLAKY**: it passes locally at the same sha, and the log shows timing, ordering, or
  a network call.
- **INFRA**: runner, cache, registry, secret, or quota errors, and anything that needs
  a CI setting or a human decision. Name what it needs.

When the command cannot run locally (a missing service or secret), classify from the
log and the code alone, and say that it is unreproduced.

Completion criterion: every failed job has a line.

## 3. Choose where the fixes land

No LEGIT left: go to step 6.

Unless the input or the conversation already says where ("push to main", "open a PR",
"don't push"), ask before writing any fix, as a structured question
([harness-tools](../harness-tools/SKILL.md)), with the LEGIT lines from step 2 in the
question so it stands on its own. `<default>` is the repo's default branch
(`gh repo view --json defaultBranchRef`). Offer these options, the recommended one
first:

- **Push to `<default>`** (recommended): the fixes go straight onto `<default>`. When
  `B` is not `<default>`, `B` gets them at its next sync from `<default>`, and until
  then its CI stays red.
- **Pull request into `<default>`**: push a `fix/ci-<branch>` branch and open a PR.
- **Push to `B` too** (only when `B` is not `<default>`): land on `<default>` and on `B`.
  The description says the cost: `B` then has commits `<default>` lacks, so the next
  fast-forward sync from `<default>` to `B` is refused until someone merges `B` back.
- **Commit only**: keep the commits local and push nothing.

Completion criterion: the user picked a landing, or the input already named one.

## 4. Fix the legit ones

Every landing writes the fixes on `<default>`, so work from `origin/<default>` without
disturbing a dirty tree or another worktree's checkout. When the tree is dirty or the
branch is checked out elsewhere, use
`git worktree add .claude/worktrees/ci-<branch> origin/<default>` (at that path, never a
sibling directory), then make it runnable with `laravel-herd-worktrees`' **Bootstrap a
bare worktree** section before running anything in it. Leave it in place until step 6.

When `B` is not `<default>`, first run each LEGIT failure's command at the base: a failure
that does not reproduce there is already fixed on `<default>`, so name it in the report
instead of fixing it. Per remaining LEGIT failure: make the minimal change, run the
failing command locally until it is green, then commit per the `commit` skill's
[Staging](../commit/SKILL.md#staging) and [Subject](../commit/SKILL.md#subject), the
subject naming the job.

Completion criterion: every LEGIT failure has a commit that turned its command green
locally, or is named as already fixed on `<default>`.

## 5. Land the fixes

Land the commits the way step 3 chose, without asking again:

- **Push:** `git push origin HEAD:<branch>` (no `--force`). If it is refused because the
  remote branch moved, `git fetch origin`, rebase onto it, re-run each fixed command,
  and push again.
- **Pull request,** or a push the branch's protection refuses: push a `fix/ci-<branch>`
  branch and open a pull request into the target with a body in the `pr` skill's
  template.
- **Push to `B` too:** push to `<default>` first, then cherry-pick each fix commit onto
  `origin/B`, re-run each fixed command, and push that to `B`. A fix that does not apply
  to `B` is named in the report, not forced. A cherry-pick conflict stops this step: ask
  the user.
- **Commit only:** push nothing.

Never push to `B` on any answer other than **Push to `B` too**.

The push starts new CI runs. Leave them running and do not come back for their result.
When step 4 worked in the main checkout on a local branch, it is now in step with its
remote; when it worked in a worktree, leave the user's local branches as they are and
say which one is behind.

Completion criterion: every fix commit is on its landing branch, in an open pull
request, or kept local by the user's answer.

## 6. Clean up and report

If step 4 created a worktree and its commits are on their landing branch (or in the
open pull request), remove it without asking, from the main checkout, by `laravel-herd-worktrees`' **Remove a served worktree**
(it never forces). If it refuses,
or the commits are kept local, keep it and ask one yes/no question: "Can I delete the
worktree I created?" Remove it only on yes, never with `--force`; otherwise name it in
the report as kept.

One line per failed job: fixed in `<sha>`, stale (`<sha>`), flaky, infra (what it
needs), or unreproduced. Then say where the commits landed, and each worktree removed
or kept.
Start each job line with a mark: ✅ fixed or stale, ⚠️ flaky, infra, or unreproduced.

## Guardrails

CI evidence comes only from runs that already exist. Do not run `gh run rerun`,
`gh workflow run`, or `gh run watch`, do not push an empty or retry commit, and do not
wait on a run.
