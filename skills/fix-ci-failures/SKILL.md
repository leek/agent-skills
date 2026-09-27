---
name: fix-ci-failures
description: Read a branch's latest failed CI runs, triage each failure from its existing logs, and fix the real ones.
disable-model-invocation: true
argument-hint: "Branch name (defaults to main), then optional guidance (\"skip lint\", \"only the test job\")"
allowed-tools: "Bash(gh run list *) Bash(gh run view *)"
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

Run `git fetch origin`. For each workflow, take only its newest **completed** run on the
branch. An older failure whose workflow has passed since is already fixed, and a run
still in progress is not evidence yet: skip both.

```bash
gh run list --branch B --status completed --limit 100 \
  --json databaseId,workflowName,conclusion,headSha,createdAt,url \
  --jq 'group_by(.workflowName) | map(max_by(.createdAt)) | .[]
        | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure")'
gh run view RUN --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {databaseId, name, url}'
gh run view --job JOB --log-failed
```

No failed workflow: report that the branch's latest completed runs are green, and stop.

Completion criterion: every failed job is listed with its workflow, run URL, `headSha`,
and the first real error from its log (not the trailing `exit code 1`).

## 2. Classify every failure

Read `git log --oneline <headSha>..origin/B` first: commits since the failed run may
already fix it. Then write one line per failed job:

```
Failure N: [LEGIT | STALE | FLAKY | INFRA] — <one-line evidence>
```

- **LEGIT**: the error points at code on the branch, and it reproduces at `origin/B`
  when you run the same command locally.
- **STALE**: a later commit fixed it. Cite the sha, or show the command passing locally.
- **FLAKY**: it passes locally at the same sha, and the log shows timing, ordering, or
  a network call.
- **INFRA**: runner, cache, registry, secret, or quota errors, and anything that needs
  a CI setting or a human decision. Name what it needs.

When the command cannot run locally (a missing service or secret), classify from the
log and the code alone, and say that it is unreproduced.

Completion criterion: every failed job has a line.

## 3. Fix the legit ones

No LEGIT left: go to step 4.

Work on the branch without disturbing a dirty tree or another worktree's checkout. When
the tree is dirty or the branch is checked out elsewhere, use
`git worktree add .claude/worktrees/ci-<branch> origin/B`, and remove it when done. Per
LEGIT failure: make the minimal change, run the failing command locally until it is
green, then commit with explicit staging (Conventional Commits, naming the job).

Before pushing, show the commits and the branch, and push only on the user's approval
in this conversation. The push starts new CI runs. Leave them running and do not come
back for their result.

Completion criterion: every LEGIT failure has a commit that turned its command green
locally, and the push is done or declined.

## 4. Report

One line per failed job: fixed in `<sha>`, stale (`<sha>`), flaky, infra (what it
needs), or unreproduced. Then say whether the commits are pushed.

## Guardrails

CI evidence comes only from runs that already exist. Do not run `gh run rerun`,
`gh workflow run`, or `gh run watch`, do not push an empty or retry commit, and do not
wait on a run.
