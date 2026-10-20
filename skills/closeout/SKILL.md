---
name: closeout
description: "Check whether this session is safe to close: unsaved work, running jobs, open PRs, unanswered questions, and steps still to run. Read-only; each open item names its fix."
disable-model-invocation: true
---

# Closeout

Answer "can I close this session?" with one verdict and the items behind it. This skill **reports and routes**: it commits, pushes, stops, removes, and answers nothing itself. Each item ends with the command or skill that clears it, and the user runs it.

**Scope is this session.** An item counts only when this conversation created, edited, started, opened, or asked it. Older branches, worktrees, PRs, and stashes stay out of the report, even when a command below prints them. When the conversation was compacted (an earlier part replaced by a summary), items from before the summary may be missing: say so in the report.

## 1. Inventory the session

From the conversation, write down:

- **Files** created, edited, or deleted, grouped by the checkout or worktree they sit in.
- **Branches and worktrees** created, and **PRs** opened or pushed to (number and repo).
- **Jobs** started: background Bash tasks, subagents (`Agent` in Claude Code, `spawn_agent` in Codex), `Monitor`s, `CronCreate` jobs, `ScheduleWakeup` loops, dev servers, watchers, queue workers.
- **Questions** you asked the user, and every grill ledger branch still `open` or `deferred`.
- **Asks**: each thing the user asked this session to do.
- **Deploy facts**: migrations, new env keys (`.env.example`), new scheduled commands or queued jobs, config or cache changes, and any "after merge" or "after deploy" step said in the conversation.

Done when every checkout, branch, PR, and job the session touched is on the list. An empty inventory is a **Clean** verdict: skip to step 4.

## 2. Check for blockers

A **blocker** is an item that loses work or stops a job if the session closes now.

- **Git state**: run [`scripts/git-state.sh`](scripts/git-state.sh) `<path> …` once, with every checkout and worktree from step 1. In its `changes`, count only the files on your list; another session's files are not yours, the same rule `commit` follows. Uncommitted files → `/commit`. `unpushed` above 0, or `upstream` null on a session branch → `git push`. A non-null `operation` → `/resolving-merge-conflicts`, or the `--continue`/`--abort` that finishes it.
- **Running jobs**: every background task or subagent with no completion notification yet → wait for it, or stop it (`TaskStop` in Claude Code, `interrupt_agent` in Codex). For a cron job or wakeup loop this session made, confirm it still exists (`CronList`) → `CronDelete`, or keep it on purpose. For a dev server or watcher, confirm it is still alive (`lsof -iTCP:<port> -sTCP:LISTEN`, or `ps -p <pid>`) → stop it, or keep it on purpose. A job you cannot check in this harness is **not checked**, not finished.

Done when every git path and every job from step 1 is cleared or listed as a blocker.

## 3. Check for follow-ups

A **follow-up** is an item that waits, but closing loses nothing.

- **PRs**: from inside each repo, run [`scripts/pr-state.sh`](scripts/pr-state.sh) `<number> …` with the session's PRs. List each open PR with what it waits on. `checks_failed` → `/fix-ci-failures`. `threads_open` above 0 → `/resolve-review-comments`. Review still required, with green checks → waiting for a reviewer, or `/triage-github-pr` to drive it to merge. A merged PR whose session branch or worktree still exists → `/repository-cleanup`.
- **Unanswered questions**: each question from step 1 that the user did not answer, quoted in a few words. An open grill branch → `/grill-me` on that branch.
- **Unmet asks**: each ask from step 1 that the session did not finish, or said it would do later.
- **Untested edits**: code edited after the last passing test run → run the tests. A behavior change never seen in the running app → `/verify`.
- **Post-merge and post-deploy steps**: each deploy fact from step 1, plus each PR's `merge_danger`, written as the step to run and when (for example "after deploy: `php artisan migrate`").
- **Open `.scratch/` work** this session touched → `/scratch-status`.

When follow-ups exist and the next session needs this one's context, also name `/handoff`.

Done when every PR, question, ask, edit, and deploy fact from step 1 is cleared or listed.

## 4. Report

Print exactly this shape and stop. Each item is one line that ends with its fix.

```text
<verdict>

Blockers
- <item> → <fix>

Follow-ups
- <item> → <fix>

Not checked
- <check> (<reason>)
```

The verdict is one line:

- `❌ Not safe to close`: one or more blockers.
- `⚠️ Safe to close, with follow-ups`: no blockers, one or more follow-ups.
- `✅ Clean, safe to close`: nothing open.

Leave out an empty section. **Not checked** lists each check that could not run (`gh` not logged in, not a git repo, a tool this harness lacks, a compacted conversation), so a skipped check never reads as passed. Use only the three verdict marks, on the verdict line.
