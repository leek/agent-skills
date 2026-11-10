---
name: run-after
description: "Run this session's waiting steps (a backfill after deploy, a command after commit or merge) once their trigger lands. Start the deploy, then run this: it confirms the steps, watches for the trigger, and runs them."
disable-model-invocation: true
argument-hint: "What the steps wait on (deploy, merge, commit, CI) or which step; omitted = every waiting step in this session"
---

# Run After

The session has **waiting steps**: commands that must run only after an event the agent cannot see coming, such as a backfill after a deploy or a cache clear after a merge. The user starts that event, then runs this skill. This skill **confirms, watches, then runs**: nothing runs before the user approves the plan in step 3, and no step runs before its **gate** (the event it waits on) has passed for this session's change.

## 1. Collect the waiting steps

From the conversation, list each step that was put off until an event: "after deploy", "after merge", "once this is committed", "when CI is green", a migration or backfill planned but not run, and every post-deploy step `closeout` named. For each one record:

- **Command**: the exact command, with its flags and arguments as agreed in the conversation.
- **Where it runs**: local, a worktree, or a remote target (production through the access path the conversation used, such as SSH or ECS exec).
- **Gate**: commit, push, merge, CI, or deploy, plus the **change** it waits for: the commit SHA, branch, or PR number.
- **Order**: steps that depend on an earlier step (migrate before backfill).
- **Writes data**: yes when the step changes or deletes data outside the repo.

With an argument, keep only the steps it names or whose gate it names. When the conversation was compacted, steps from before the summary may be missing: say so in step 3.

Done when every waiting step has all five fields. With none found, ask the user which command waits on which event, and record it the same way.

## 2. Find how to see each gate pass

A gate passes only when **this change** reached it: a deploy that ships an older commit is not a pass. For a squash or rebase merge, the change is the merge commit on the base branch (`gh pr view <n> --json state,mergeCommit`), not the branch SHA.

| Gate | Passed when | Check |
|---|---|---|
| commit | the change's files are committed | `git status --porcelain -- <paths>` prints nothing, and `git log -1` names the commit |
| push | the remote branch holds the commit | `git fetch` then `git merge-base --is-ancestor <sha> origin/<branch>` |
| merge | the PR is merged | `gh pr view <n> --json state,mergeCommit`: `MERGED` (`CLOSED` is a fail) |
| CI | every check on the SHA is green | `gh run list --commit <sha>` for the run id, then `gh run watch <id> --exit-status` |
| deploy | the target runs a release that contains the change | see below |

For a **deploy**, find the project's own signal, in this order, and stop at the first that exists:

1. A deploy check written down in the project: `AGENTS.md`, `CLAUDE.md`, a project skill, or memory.
2. A deploy workflow in `.github/workflows/` → `gh run list --workflow <file>` for the run on a commit that contains the change, then `gh run watch <id> --exit-status`.
3. An endpoint or CLI that reports the running release: a version or health URL that prints the SHA, `aws ecs describe-services` (deployment `rolloutState` `COMPLETED`, task definition image tag contains the SHA), or the hosting platform's CLI. Then `git merge-base --is-ancestor <change-sha> <deployed-sha>`.
4. None found → ask the user how to tell the deploy finished, with "I will tell you when it is done" as one option (structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat).

Run each check once now. A gate that already passed needs no watch.

Done when every gate has a check command whose exit says passed, not yet, or failed, and you know its state now.

## 3. Confirm the plan

Print the plan, one line per step, in run order:

```text
<n>. <command>  @ <where>  after <gate> of <change>  [<gate state now>]  <"writes data" when it does>
```

Under it, name how each gate is watched and the time limit (60 minutes unless the user gives one). Then ask the user to choose (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat): run them all, run only some (then pick which), or cancel. The answer is the user's approval for exactly those commands, run once each, after their gates pass. A step not on the plan, or a command that changes after this point, needs a new approval.

Done when the user approved a set of steps, or cancelled (stop).

## 4. Watch the gates

Watch with a command that ends by itself when the gate passes or fails, and let its end wake you. Never a foreground sleep, and never a poll loop in the turn.

- A command that blocks until done (`gh run watch <id> --exit-status`): run it in the background (Claude Code: Bash with `run_in_background`).
- Any other check: wrap it as `bash <this-skill-dir>/scripts/wait-until.sh --interval 30 --timeout <limit> -- bash -c '<check>'` (`<this-skill-dir>` is this skill's directory) and run that in the background. The check exits 0 when passed, 1 when not yet, and 2 when failed (a failed workflow, a closed PR, a rollback). The script prints one JSON verdict: `passed`, `failed`, or `timeout`.
- A harness with no background commands: run `wait-until.sh` in the foreground with the same limit, or, when a wake-up tool exists (`ScheduleWakeup` in Claude Code), schedule one check every 5 minutes up to the limit.
- "I will tell you": end the turn and wait for the user.

Tell the user what you are watching and how to stop it, then end the turn.

Done when every approved step's gate has a verdict. A `failed` or `timeout` gate stops every step behind it: go to step 6.

## 5. Run the steps

Run the approved steps whose gates passed, in order, each exactly as approved and where approved. After each step, read its output for proof that it worked: the exit code, plus the counts or messages it prints (a backfill that reports 0 rows when rows were expected is a ⚠️, not a ✅).

When a step fails, stop: do not run it again and do not run the steps after it. A step that writes data may have half run; say what its output shows was done.

Done when every approved step ran, or the first failure stopped the run.

## 6. Report

When the harness can notify the user (Claude Code: `PushNotification`), send one line with the outcome, since the user may have walked away. Then print one line per step:

```text
✅ <command>: <what its output proved>
❌ <command>: <error, quoted>
⚠️ <command>: <gate failed / timed out / output looked wrong, and why>
👉 <next step, when there is one>
```

Use only these four marks, at the start of each line. A step that never ran says which gate or failure held it back.
