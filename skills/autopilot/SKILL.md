---
name: autopilot
description: Build a whole spec while you are away. Asks every question up front, then a runner drives parallel fresh top-level Claude Code, Codex, or Grok sessions, one per ticket in its own worktree, onto one integration branch, delivered as one PR or a stack of PRs.
disable-model-invocation: true
argument-hint: "A spec path (.scratch/<slug>/spec.md); a spec with no tickets gets them cut first. Optionally, how many workers at once (default 5)"
---

# Autopilot

Build every ticket of one spec with fresh top-level agent sessions, and deliver it the way `implement-spec` does: one integration branch, then one PR, a stack of PRs, or a pushed branch. `implement-spec` stays authoritative for the build. This skill replaces its orchestrator with a script, so the run survives this session, and its subagents with top-level CLI processes.

The work has three parts. **You** (this session) do everything that needs the user: cut the tickets, sweep for open decisions, ask the questions, create the integration branch. **The runner** ([`scripts/autopilot.sh`](scripts/autopilot.sh)) then works the ticket frontier with no user: up to 5 build workers at once, each a fresh process in its own worktree, each landing its ticket on the integration branch. **The finish worker**, one last fresh process, reviews and verifies the whole branch, resolves the tickets, and delivers.

Autopilot takes a spec and nothing else. For a `wayfinder` map, finish the map and run `to-spec` first; for one ticket, use `/implement <ticket>`. Reach for `/implement-spec <spec>` instead when you want the same build inside this session, with you watching.

## 1. Prepare the run, with the user

Do `implement-spec`'s [step 1](../implement-spec/SKILL.md#1-load-the-task-graph) and [step 2](../implement-spec/SKILL.md#2-create-the-integration-branch) as written, with its scripts and its stack reference. They cut the tickets when the spec has none, open the ticket board, sweep for open decisions, ask the questions in one structured-question call, create the integration branch, and commit the answers to it. The differences:

- **Workers cannot ask, so ask now.** The decision sweep is the run's one chance to settle a choice with the user. Never skip it on a guess: only on `decision_sweep_done`.
- **Questions.** Ask the open decisions, **Worktree**, **Delivery**, and **Cleanup**. Do not ask **Deploy gate**: the runner always stops at a gate, and its dependents are a later run. Do not ask **Resume** about claims named `autopilot:<run id>` when `--status` (below) shows an unfinished run for this spec: the runner resumes its own claims. Ask it for anyone else's.
- **Approval.** The workers run with permission prompts and sandboxing bypassed (`--dangerously-skip-permissions` / `--dangerously-bypass-approvals-and-sandbox` / `--always-approve`). Start the runner only on a spec the user asked to have built autonomously; the request to run this skill is that approval.
- **Make the integration checkout runnable** (start-branch.sh's `todo`): the finish worker verifies there.
- Skip step 2's exploration subagent: each worker is a fresh session that explores for itself.

Finish when the tickets and the decisions are committed on the integration branch, `$notes/base_sha` is written, and you know the integration checkout's path, the delivery shape, and the cleanup answer.

## 2. Start the runner

Select the current harness as the provider: `claude` in Claude Code, `codex` in Codex, `grok` in Grok. Run the bundled script by absolute path (`<this-skill-dir>` is this skill's directory), from the main checkout:

```bash
bash <this-skill-dir>/scripts/autopilot.sh --provider <claude|codex|grok> --root .scratch/<spec slug>/spec.md \
  --integration <integration checkout> --delivery <pr|stack|branch> --cleanup <auto|list>
```

`--delivery` is `pr` for One PR, `stack` for Stacked PRs, `branch` for the branch with no PR. `--cleanup` is `auto` when the user chose to remove leftovers without asking, else `list`. Add `--concurrency <n>` when the user named a number. `bash <this-skill-dir>/scripts/autopilot.sh --help` is the reference for every flag (`--repo`, `--max-iterations`, `--model`, `--effort`, `--log-file`, `--tmux`, `--finish-now`), the observer modes, the progress lines, and the exit codes.

Run it as a background task: a run takes hours and outlasts any foreground timeout. Its exit is the completion signal (for a `--tmux` run, one background `--wait`). Report the run ID, the worker model and effort, the log path, and the printed observer commands at once.

Every worker session reports its model and reasoning effort, and where each came from. Pin them with `--model <name> --effort <level>` (or `AUTOPILOT_MODEL` / `AUTOPILOT_EFFORT`); the runner rejects an effort level its provider does not take.

## 3. Follow the run

Stream the milestones by running `--follow 2>&1 | grep --line-buffered -E 'Autopilot: (Autopilot |selected |ticket |question |board |worker [^ ]+ (started|alive|result|failed)|next )|quiet threshold|gate|invalid|interrupted'` under `Monitor` where available (re-arm it when it expires; every line is `<timestamp> Autopilot: <message>`). Otherwise read `--status` and the log tail each time the turn resumes. To wait on a run you did not start in this shell, use one background `--wait`, never a sleep or a poll loop.

**Ticket board.** The pane beside the chat shows this run the way it shows an `implement-spec` run, per [`ticket-board.md`](../wayfinder/references/ticket-board.md) with `kind: "spec"` and that skill's statuses. Step 1 opened it. The workers have no board tool, so you send every change, one call per runner line:

| Runner line | Send |
|---|---|
| `selected <ticket> (…)` | that ticket `running` |
| `ticket <NN> merged (…)` | `merged`, note: the SHA in `$notes/landed/<NN>` |
| `question <NN>: …` or `ticket <NN> blocked: …` | `released`, note: why |
| `worker <NN> failed: …` | `not-built`, note: the failure |
| `board <json>` | the object as it is: a `stage`, a finding, or an `open` entry from the finish worker |
| `worker finish result continue` | each landed ticket `closed`; the delivery ticket `closed`, or `awaiting-deploy` at `ready-for-human` |

When the reply says no pane shows the run, post `implement-spec`'s progress line for each merge instead.

Also act on these lines as they arrive:

- **`ticket <NN> assumed: <choice>`**: the worker built on a reversible assumption. Ask the user to confirm it (a structured question, the built answer first). A different answer is a follow-up fix after the run: record it in the spec's `decisions/`, never interrupt the runner for it.
- **`question <NN>: <text>`**: the choice was not reversible, so the worker stopped and the runner released the ticket. It keeps building every ticket that does not depend on it. Ask the user now; the answer is used in step 4.
- **`worker <NN> alive (…); quiet threshold reached`**: no provider event for two heartbeats (`AUTOPILOT_HEARTBEAT_SECONDS`, default five minutes each). Read the log or attach before you call it hung. The runner never kills quiet work.

## 4. When the runner exits

Read the result object: its `status` and `reason` say what happened. Ping the user on any exit but 0 (`PushNotification` where available).

- **`0` complete**: every ticket is closed and delivered. Run `implement-spec`'s screenshot check (`screenshots-report.sh $notes`), ask about the leftovers the result names when cleanup was `list` (per [`leftovers.md`](../implement-spec/references/leftovers.md)), and report.
- **`2` needs input**, with questions: write each answer into the spec's `decisions/` on the integration branch as a closed decision ticket and commit it, then run the same command again. It builds the released tickets and their dependents, then finishes once. When the user would rather ship without them, add `--finish-now`.
- **`2` needs input**, at a deploy gate or a delivery ticket at `ready-for-human`: the delivery is done. The user deploys; then run this skill again for a gate's dependents, or `/implement <delivery ticket>` for its after-deploy steps.
- **`3` blocked**: a ticket could not be built, or the open tickets are claimed by someone else. Name them.
- **`4` failed**: a worker crashed or returned an invalid result. Its ticket keeps its claim and its worktree; the other workers landed first. Read the log for the cause, then run the same command again: it resumes that ticket.
- **`5`**: the runner could not start or stopped (bad flags, the worker-session limit). Fix what `reason` names.

Run state, the log, and raw provider events are under the repository's Git directory, keyed by the spec; a per-spec lock stops two runners sharing a run. Rerunning the same command resumes an unfinished run (its claims carry the run ID) and starts a new one after a completed run.

Print the end-of-session block as `implement-spec`'s [When you're done](../implement-spec/SKILL.md#when-youre-done) gives it, with `/autopilot <spec>` where it says `/implement-spec <spec>`.

## What the runner guarantees

- **One tracker writer at a time.** The runner claims each ticket (`autopilot:<run id>`) in the integration checkout before its worker starts, and releases it when the worker cannot build it. Build workers never write `.scratch/`. The finish worker resolves the tickets, and the runner fails the run when that worker reports success while a landed ticket is still open.
- **The integration branch only holds trees a worker tested.** [`scripts/land.sh`](scripts/land.sh) is a lock: a worker merges the integration tip into its branch, reruns its focused tests, and merges back, while no other worker lands.
- **No two workers edit one file.** A ticket whose `## Files` share a path with a running ticket's waits for that one to land.
- **A deploy gate bounds the run.** Once a `deploy-gate: true` ticket lands, its dependents are not dispatched on this branch.
- **Nothing is forced.** The runner creates each worktree at `<main checkout>/.claude/worktrees/<branch>--<NN>` and removes none; the finish worker cleans up through [`laravel-herd-worktrees`](../laravel-herd-worktrees/SKILL.md), as `implement-spec` step 8 says.
