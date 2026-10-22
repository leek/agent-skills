---
name: implement-spec
description: "Build a whole spec fast: parallel implementer subagents work the ticket frontier, each in its own worktree, merging onto one integration branch; then one review, one verification pass, and one PR or a stack of PRs."
disable-model-invocation: true
argument-hint: "A spec path (.scratch/<slug>/spec.md); a spec with no tickets gets them cut first. Optionally, how many implementers at once (default 4)"
---

# Implement Spec

Build every ticket of one spec in this session by **orchestrating**, not building: implementer subagents do the code, each in its own worktree; you own the tracker, the **integration branch**, the merges, and the final gates. The goal is the whole spec on one integration branch, every ticket closed, delivered as the user chose: one PR, a stack of PRs (one per ticket), or a pushed branch.

The tickets are not a list of steps. They are a **task graph**: `blocked-by` edges mean there is always a **frontier** of tickets ready to grab, and every ticket on it can be built at once.

Reach for the neighbours instead when they fit better: `/implement <spec> all` builds the same tickets one after another in this session, with no subagents (and is the fallback when the harness has none: say so and stop); `autopilot` drives the tickets through fresh top-level sessions while you are away.

Talk to subagents in **context pointers**: paths to the spec, the ticket, blocker resolutions, notes, commits. Never paste what a pointer already reaches. Ask them for sparse reports.

## Guardrails

- **Never** reset, roll back, drop, or truncate a database this run did not create, or run another destructive data operation on one, without explicit approval. Schema changes go in new migrations.
- Verify identifiers before using them: route names, config keys, enum values, package APIs.

**Stack references.** Identify the stack from its manifests. If a matching file exists below, read it before step 1 and pass its pointer into every implementer brief: it names that stack's destructive commands, worktree setup, test-config files, and formatter.

- Laravel (`laravel/framework` in `composer.json`): [`references/laravel.md`](references/laravel.md)

**Ticket board.** Report each ticket's status per [`ticket-board.md`](../wayfinder/references/ticket-board.md), with `kind: "spec"`: `ready` and `blocked` (note: the blockers) from step 1, `skipped` for tickets left out, `running` at dispatch, `fixing` when a failure goes back to its implementer, `merged` (note: the merge SHA), `released` (note: why), and `closed` in step 7.

## Process

### 1. Load the task graph

Read the spec: its **Build Contract** section first, then what the tickets name. Read every ticket's frontmatter once (`status`, `blocked-by`, `deploy-gate`, `claimed-by`).

**No `tickets/` yet?** Cut them yourself with `to-tickets`' rules: its step 3 for the slicing, its step 4 for the one green light, its step 5 and [Ticket template](../to-tickets/SKILL.md#ticket-template) to publish and commit. Vertical slices with honest `blocked-by` edges are what make the frontier wide; a chain of tickets each blocked by the last builds no faster than `/implement all`.

Leave out closed tickets and tickets claimed by someone else (name them in the report). A `deploy-gate: true` ticket bounds the run: build up to and including it, then stop at step 7 with a PR; its dependents start after that PR is deployed. When dependents would wait behind a gate, ask once, here, before the first dispatch (not after the gate PR opens): stop at the gate, or build the dependents in this run on a second integration branch `<slug>-2` cut from the gate branch's tip. Before dispatching the first contract/drop ticket on `<slug>-2`, confirm the gate branch `<slug>` has no remaining writes or reads to the columns or tables `<slug>-2` drops. `<slug>-2` takes changes only by merging `<slug>` (the gate ticket and its review fixes), never by merging or cherry-picking any other branch, and once the gate PR merges, move `<slug>-2`'s delta onto fresh `origin/<default>` for a second PR.

Before the first dispatch, ask these in one `AskUserQuestion` call where available (otherwise one message in chat), and nothing else:

- **Worktree**: build the integration branch in a worktree at `.claude/worktrees/<slug>` (recommended: this checkout stays as it is), or switch this checkout to `<slug>`. Skip it when the tree is dirty (the worktree is the only option; say so) or the request already says. Each implementer gets its own worktree either way: that is what lets them build in parallel.
- **Delivery**: `implement`'s [delivery question](../implement/references/spec-run.md#choose-the-delivery-shape) for a whole spec: one PR, stacked PRs, or the branch with no PR.
- **Deploy gate**, when one applies (above).

Finish when every in-scope ticket and its edges are known, the worktree and delivery choices are made, and the first frontier is listed.

### 2. Create the integration branch

Follow `implement`'s [PR delivery: before step 1](../implement/references/spec-run.md#pr-delivery-before-step-1-claims-anything): branch `<slug>` from fresh `origin/<default>`, in `.claude/worktrees/<slug>` when step 1's worktree answer (or a dirty tree) says so, with the spec's `.scratch/<slug>/` carried over. This checkout is the **integration checkout**. Record `base_sha`.

Make a notes directory outside every worktree: `notes="$(git rev-parse --path-format=absolute --git-common-dir)/implement-spec/<slug>"`. When several tickets need the same exploration (an unfamiliar module, a package's docs), run one read-only **exploration subagent** first that writes its findings there as Markdown, so implementers build instead of explore.

### 3. Dispatch the frontier

For each frontier ticket, up to the concurrency limit (default 4: each one runs a test suite):

1. **Claim** it in the integration checkout per the tracker's Claim operation, with `claimed-by: implement-spec-<slug>-<run id>`. Only you write `.scratch/`; claims stay uncommitted until step 7.
2. **Worktree.** `git worktree add -b <slug>--<NN> <main checkout>/.claude/worktrees/<slug>--<NN> <integration tip>` (the main checkout's `.claude/worktrees/`, never one inside the integration worktree), then make it runnable (install dependencies, copy local env config) the way the project's docs say, or as the stack reference says. When the tests need a real database, give it its own (`<app db>_spec_<slug>_<NN>`, never a name the main checkout's env or test config uses) and register it the moment you create it:

   ```bash
   printf '%s\t%s\t%s\t%s\n' "$(date +%s)" <pgsql|mysql> <database> "<worktree path>" \
     >> "$(git rev-parse --path-format=absolute --git-common-dir)/scratch-databases"
   ```

3. **Implementer subagent**, in the background where the harness allows (Claude Code: subagents run in the background by default and wake you on completion; pass `run_in_background: true` where the Agent tool offers it; give each a `name` of `<slug>--<NN>` so you can address it later; Codex: `spawn_agent`, keeping each returned agent id against `<slug>--<NN>`, and `wait_agent` to collect reports; elsewhere, any sub-agent the harness offers). Its brief gives pointers (worktree path, ticket path, the spec's Build Contract, direct blockers' reports from step 4, the notes directory) and these rules:
   - Work only in that worktree (enter it with `EnterWorktree({path})` where available, otherwise use absolute paths into it). Confirm `git merge-base --is-ancestor <integration tip> HEAD` before starting.
   - Choose seams with the `tdd` skill's **Seams: where tests go** rules and state them; then call the Skill tool with `tdd` and build the ticket test-first. Focused tests and configured static analysis end green.
   - Run tests in the foreground and wait for the result. Never send a test run to the background and go idle on it: an idle implementer may not wake when the run ends. A run too long for the tool's timeout is too broad; run fewer files.
   - Format touched paths with the repo's configured formatter, commit by explicit path. Never touch `.scratch/`, never push, never write another branch.
   - Before reporting, merge the current integration tip into the branch and rerun the focused tests.
   - Report in at most ten lines: commit SHAs, touched paths, seams (name any public seam a dependent ticket should reuse), the focused test command and result, deviations from the ticket, and anything blocking.

Then end the turn and let completion notifications wake you; never poll. An idle notification with no report and no new commit is a stall, not progress: message that implementer at once (`SendMessage` in Claude Code, `followup_task` in Codex) to finish or say what blocks it.

### 4. Merge as each implementer lands

In the integration checkout: `git merge --no-ff <slug>--<NN>`. On a conflict, call the Skill tool with `resolving-merge-conflicts`. Rerun that ticket's focused tests on the integration branch. A failure goes back to the same implementer with the output, so it keeps its worktree and ticket context (`SendMessage` to its name in Claude Code, `followup_task` to its agent in Codex; otherwise brief a fresh implementer with the worktree path, the ticket, and the failure output); a ticket that reports itself blocked is released (clear `claimed-by`), and its dependents stay out of this run.

Keep each implementer's report in `$notes/<NN>.md`: it feeds dependents' briefs and the ticket's `Resolution`. A merged ticket counts as done for its dependents' `blocked-by`, so recompute the frontier and dispatch what it unblocked (step 3).

After each merge, update the ticket board, and post one progress line so the user never has to ask for status: `<NN> merged (<k> of <M>); running: <NNs>; next: <NNs>`. Skip the line when the board's pane shows the run.

**A question never stops the run.** When a ticket needs the user's decision, release that ticket and its dependents, keep building the rest of the frontier, and ask the open questions together at the next merge, or in the final report when nothing else is running. Stop and wait only when every remaining ticket is blocked on an answer.

Finish when every in-scope ticket is merged or released, and no implementer is running.

### 5. Review once, over the whole branch

Call the Skill tool with `code-review` against `base_sha` on the integration branch, scoped to every path the run touched. Hand all actionable findings to **one** implementer subagent working in the integration checkout, through `tdd`, named `<slug>--fix` so later rounds reach it by `SendMessage` in Claude Code or `followup_task` in Codex (otherwise brief a fresh one with the integration checkout path and the findings); re-run `code-review` after its fix commit as a re-review, passing the previous round's findings and head. A finding that needs the user's decision never holds the round: send every other finding now, ask that one in parallel, and pass the answer on as a follow-up. Two review rounds is the budget: when the second still has actionable findings, stop fixing and name them in the final report and the PR, with the commit each round reviewed (if the user asks to ship them in a follow-up PR, open **one** follow-up PR for all remaining findings, never one PR per finding, based on the integration branch while that PR is open; once it has merged, retarget per [Follow-up on a delivered PR](../implement/references/spec-run.md#follow-up-on-a-delivered-pr)). Finish when review reports nothing actionable, or when the second round is done.

### 6. Final checks and verification

Run `implement`'s steps 6 and 7 once over the whole range. Skip the full-suite question when the repo's rules or the user's saved preferences already settle it (CI runs the suite, or "do not run the full suite unless asked"); otherwise ask once. A declined full suite is never replaced by a broad sweep of many test files: each ticket's focused tests stand as the evidence. Then call the Skill tool with `verify` and check every ticket's acceptance criteria in one pass. A product failure goes back through step 5's single implementer. Finish when verification passed, or name the exact external blocker and leave those tickets open.

### 7. Close and deliver

For each verified ticket: append `## Resolution` (what was built, deviations, verification evidence, its implementation commits, seams for successors, from `$notes/<NN>.md`) and set `status: closed`; re-read to confirm. Commit the tracker separately (`docs(scratch): <slug> resolutions`), never folded into code. Then follow [PR delivery: after step 8](../implement/references/spec-run.md#pr-delivery-after-step-8) for the chosen shape: push, open the PR (or cut and open the stack per its [Stacked PRs](../implement/references/spec-run.md#stacked-prs)), read review threads once.

### 8. Clean up

Run cleanup from the integration checkout, so `git branch -d` checks each ticket branch against `<slug>`. For each ticket merged into the integration branch, clean up only the environment this run created, in order: `herd unlink <name>` from inside the worktree if the bootstrap linked it, `git worktree remove <path>` (no `--force`), then `git branch -d <slug>--<NN>`, then drop its registered `<app db>_spec_<slug>_<NN>` database and parallel-testing copies (`<database>_test_<N>`). Delete each `scratch-databases` line only after its database was successfully dropped. If worktree removal refuses, stop cleanup for that ticket: retain its branch, database, parallel-testing copies, and registry entries together. `git branch -d` is the only branch delete. When it refuses, the branch stays with whatever remains, and the report names the refusal. Git's force-delete hint (`-D`) is not a go-ahead. If a database drop fails, retain the remaining resources and registry entries and report the failure. List each successful removal.

Ask once only about what is left that you created: a refused environment, or the environment of an unmerged or released ticket (`AskUserQuestion` where available: a `multiSelect: true` question with one option per ticket's retained environment, naming its worktree, branch, database and copies, nothing pre-ticked, at most 4 per question and further questions for the rest; otherwise a plain yes/no question in chat: "Can I delete these too?"). Remove only selected environments, following the same ordered cleanup above, never with `--force`. Keeping a worktree keeps its associated resources. Skip the question when nothing is left. Keep the integration worktree: it holds the PR branch (leave it with `ExitWorktree({action: "keep"})` if you entered it). Anything kept is `repository-cleanup`'s job later.

## Stopping mid-run

Merge what has landed. Ask which running implementers to cancel (`AskUserQuestion` with `multiSelect: true` where available, one option per name; otherwise in chat); stop each chosen one with `TaskStop({task_id: <name>})` in Claude Code or `interrupt_agent` in Codex, and release its ticket (clear `claimed-by`), keeping its worktree and branch. Where nothing can stop them, leave them running. Running implementers keep their claims. Report per ticket: merged, in flight (worktree path), stopped (worktree path), released, or not started. A re-run on the same spec resumes: a `<slug>--<NN>` branch with a report in `$notes/<NN>.md` is merged first instead of rebuilt; one without (a stopped implementer) goes to a fresh implementer briefed to finish it in its worktree.

## When you're done

Print the end-of-session block using the frame in [`wayfinder/references/pipeline-end-block.md`](../wayfinder/references/pipeline-end-block.md):

```text
---
Pipeline: decide → spec → tickets → **build**   (4 of 4)
Done: <tickets closed of total, integration branch, PR, verification state>
Next:
  • <condition> → /<skill> <ref>
```

- **A PR is open and review bots are still running** → `/resolve-review-comments <PR>` once they post
- **A stack of PRs is open** → `/triage-github-pr <every PR, bottom-up>` to land it bottom-up with merge commits
- **Stopped at a deploy gate** → deploy the PR, then `/implement-spec <spec>` for the dependents
- **Tickets released or left open** → `/implement <ticket>` for each, or `/implement-spec <spec>` again
- **The build exposed a decision nobody made** → `/grill-me` on it, then re-run `/to-spec`
- **The run went sideways** → `/retro this` before clearing
