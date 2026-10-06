---
name: implement-spec
description: "Build a whole spec fast: parallel implementer subagents work the ticket frontier, each in its own worktree, merging onto one integration branch; then one review, one verification pass, and one PR."
disable-model-invocation: true
argument-hint: "A spec path (.scratch/<slug>/spec.md); a spec with no tickets gets them cut first. Optionally, how many implementers at once (default 4)"
---

# Implement Spec

Build every ticket of one spec in this session by **orchestrating**, not building: implementer subagents do the code, each in its own worktree; you own the tracker, the **integration branch**, the merges, and the final gates. The goal is the whole spec on one integration branch, every ticket closed, one PR.

The tickets are not a list of steps. They are a **task graph**: `blocked-by` edges mean there is always a **frontier** of tickets ready to grab, and every ticket on it can be built at once.

Reach for the neighbours instead when they fit better: `/implement <spec> all` builds the same tickets one after another in this session, with no subagents (and is the fallback when the harness has none: say so and stop); `autopilot` drives the tickets through fresh top-level sessions while you are away.

Talk to subagents in **context pointers**: paths to the spec, the ticket, blocker resolutions, notes, commits. Never paste what a pointer already reaches. Ask them for sparse reports.

## Guardrails

- **Never** reset, roll back, drop, or truncate a database this run did not create, or run another destructive data operation on one, without explicit approval. Schema changes go in new migrations.
- Verify identifiers before using them: route names, config keys, enum values, package APIs.

**Stack references.** Identify the stack from its manifests. If a matching file exists below, read it before step 1 and pass its pointer into every implementer brief: it names that stack's destructive commands, worktree setup, test-config files, and formatter.

- Laravel (`laravel/framework` in `composer.json`): [`references/laravel.md`](references/laravel.md)

## Process

### 1. Load the task graph

Read the spec: its **Build Contract** section first, then what the tickets name. Read every ticket's frontmatter once (`status`, `blocked-by`, `deploy-gate`, `claimed-by`).

**No `tickets/` yet?** Cut them yourself with `to-tickets`' rules: its step 3 for the slicing, its step 4 for the one green light, its step 5 and [Ticket template](../to-tickets/SKILL.md#ticket-template) to publish and commit. Vertical slices with honest `blocked-by` edges are what make the frontier wide; a chain of tickets each blocked by the last builds no faster than `/implement all`.

Leave out closed tickets and tickets claimed by someone else (name them in the report). A `deploy-gate: true` ticket bounds the run: build up to and including it, then stop at step 7 with a PR; its dependents start after that PR is deployed.

Finish when every in-scope ticket and its edges are known and the first frontier is listed.

### 2. Create the integration branch

Follow `implement`'s [PR delivery: before step 1](../implement/references/spec-run.md#pr-delivery-before-step-1-claims-anything): branch `<slug>` from fresh `origin/<default>`, in `.claude/worktrees/<slug>` when the tree is dirty or the user asked, with the spec's `.scratch/<slug>/` carried over. This checkout is the **integration checkout**. Record `base_sha`.

Make a notes directory outside every worktree: `notes="$(git rev-parse --path-format=absolute --git-common-dir)/implement-spec/<slug>"`. When several tickets need the same exploration (an unfamiliar module, a package's docs), run one read-only **exploration subagent** first that writes its findings there as Markdown, so implementers build instead of explore.

### 3. Dispatch the frontier

For each frontier ticket, up to the concurrency limit (default 4: each one runs a test suite):

1. **Claim** it in the integration checkout per the tracker's Claim operation, with `claimed-by: implement-spec-<slug>-<run id>`. Only you write `.scratch/`; claims stay uncommitted until step 7.
2. **Worktree.** `git worktree add -b <slug>--<NN> <main checkout>/.claude/worktrees/<slug>--<NN> <integration tip>` (the main checkout's `.claude/worktrees/`, never one inside the integration worktree), then make it runnable (install dependencies, copy local env config) the way the project's docs say, or as the stack reference says. When the tests need a real database, give it its own (`<app db>_spec_<slug>_<NN>`, never a name the main checkout's env or test config uses) and register it the moment you create it:

   ```bash
   printf '%s\t%s\t%s\t%s\n' "$(date +%s)" <pgsql|mysql> <database> "<worktree path>" \
     >> "$(git rev-parse --path-format=absolute --git-common-dir)/scratch-databases"
   ```

3. **Implementer subagent**, in the background where the harness allows (Claude Code: subagents run in the background by default and wake you on completion; pass `run_in_background: true` where the Agent tool offers it; give each a `name` of `<slug>--<NN>` so you can address it later; elsewhere, any sub-agent the harness offers). Its brief gives pointers (worktree path, ticket path, the spec's Build Contract, direct blockers' reports from step 4, the notes directory) and these rules:
   - Work only in that worktree (enter it with `EnterWorktree({path})` where available, otherwise use absolute paths into it). Confirm `git merge-base --is-ancestor <integration tip> HEAD` before starting.
   - Choose seams with the `tdd` skill's **Seams: where tests go** rules and state them; then call the Skill tool with `tdd` and build the ticket test-first. Focused tests and configured static analysis end green.
   - Format touched paths with the repo's configured formatter, commit by explicit path. Never touch `.scratch/`, never push, never write another branch.
   - Before reporting, merge the current integration tip into the branch and rerun the focused tests.
   - Report in at most ten lines: commit SHAs, touched paths, seams (name any public seam a dependent ticket should reuse), the focused test command and result, deviations from the ticket, and anything blocking.

Then end the turn and let completion notifications wake you; never poll.

### 4. Merge as each implementer lands

In the integration checkout: `git merge --no-ff <slug>--<NN>`. On a conflict, call the Skill tool with `resolving-merge-conflicts`. Rerun that ticket's focused tests on the integration branch. A failure goes back to the same implementer with the output, so it keeps its worktree and ticket context (`SendMessage` to its name where available; otherwise brief a fresh implementer with the worktree path, the ticket, and the failure output); a ticket that reports itself blocked is released (clear `claimed-by`), and its dependents stay out of this run.

Keep each implementer's report in `$notes/<NN>.md`: it feeds dependents' briefs and the ticket's `Resolution`. A merged ticket counts as done for its dependents' `blocked-by`, so recompute the frontier and dispatch what it unblocked (step 3).

Finish when every in-scope ticket is merged or released, and no implementer is running.

### 5. Review once, over the whole branch

Call the Skill tool with `code-review` against `base_sha` on the integration branch, scoped to every path the run touched. Hand all actionable findings to **one** implementer subagent working in the integration checkout, through `tdd`, named `<slug>--fix` so later rounds reach it by `SendMessage` where available (otherwise brief a fresh one with the integration checkout path and the findings); re-run `code-review` after its fix commit. Finish when review reports nothing actionable.

### 6. Final checks and verification

Run `implement`'s steps 6 and 7 once over the whole range: ask before the full suite, then call the Skill tool with `verify` and check every ticket's acceptance criteria in one pass. A product failure goes back through step 5's single implementer. Finish when verification passed, or name the exact external blocker and leave those tickets open.

### 7. Close and deliver

For each verified ticket: append `## Resolution` (what was built, deviations, verification evidence, its implementation commits, seams for successors, from `$notes/<NN>.md`) and set `status: closed`; re-read to confirm. Commit the tracker separately (`docs(scratch): <slug> resolutions`), never folded into code. Then follow [PR delivery: after step 8](../implement/references/spec-run.md#pr-delivery-after-step-8): push, open the PR with the `pr` skill's template, read review threads once.

### 8. Clean up

List what the run created: implementer worktrees, their `<slug>--<NN>` branches (all merged), registered databases. Ask once what to remove (`AskUserQuestion` where available: a `multiSelect: true` question, one option per kind created, *Worktrees and branches* and *Databases*, each naming its items, nothing pre-ticked, or a yes/no when only one kind exists; otherwise a plain yes/no question in chat). Remove only what the answer selects: `git worktree remove <path>` (no `--force`; a refusal means unsaved work, so report it), `git branch -d <branch>`, drop each database and its parallel-testing copies (`<database>_test_<N>`), and delete its `scratch-databases` line. Keep the integration worktree: it holds the PR branch (leave it with `ExitWorktree({action: "keep"})` if you entered it). Anything kept is `repository-cleanup`'s job later.

## Stopping mid-run

Merge what has landed. Ask which running implementers to cancel (`AskUserQuestion` with `multiSelect: true` where available, one option per name; otherwise in chat); stop each chosen one with `TaskStop({task_id: <name>})` where available and release its ticket (clear `claimed-by`), keeping its worktree and branch. Where nothing can stop them, leave them running. Running implementers keep their claims. Report per ticket: merged, in flight (worktree path), stopped (worktree path), released, or not started. A re-run on the same spec resumes: a `<slug>--<NN>` branch with a report in `$notes/<NN>.md` is merged first instead of rebuilt; one without (a stopped implementer) goes to a fresh implementer briefed to finish it in its worktree.

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
- **Stopped at a deploy gate** → deploy the PR, then `/implement-spec <spec>` for the dependents
- **Tickets released or left open** → `/implement <ticket>` for each, or `/implement-spec <spec>` again
- **The build exposed a decision nobody made** → `/grill-me` on it, then re-run `/to-spec`
- **The run went sideways** → `/retro this` before clearing
