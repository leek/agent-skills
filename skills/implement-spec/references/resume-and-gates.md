# Resume, deploy gates, and stopping

Read this when [`scripts/spec-run-state.sh`](../scripts/spec-run-state.sh) reports `mode: resume`, when a `deploy-gate: true` ticket has dependents in scope, or when the user stops the run.

## Resuming an earlier run

`mode: resume` means the branch the script named exists and is unfinished. (Finished means `origin/<default>` contains it, or its PR merged or closed; the script then names the next free `<slug>-<n>`, for a deploy gate's dependents or a later re-run.)

- **Step 1.** Run step 1's `ticket.sh frontier` call inside the old integration worktree when one exists (the script's `integration_worktree`; earlier claims sit there uncommitted until step 7), otherwise read the ticket frontmatter with `git show <slug>:<path>`. A claim from that earlier run (`implement-spec-<slug>-*`) is no proof it stopped, since a long test writes no file: ask the **Resume** question (take the claims over, or leave them; recommend take-over when none of its worktrees changed a file in the last 30 minutes). Each claim taken over is rewritten with this run's id: `ticket.sh release <path>`, then step 3's claim.
- **Step 2.** The integration checkout is the script's `integration_worktree`, otherwise `git worktree add <main checkout>/.claude/worktrees/<slug> <slug>`, or `git switch <slug>` when step 1 chose this checkout. `base_sha` is the script's `base_sha` (from `$notes/base_sha`, else the first parent of `<slug>`'s first ticket merge). Keep the PRs a stack already opened, and when `gh pr list --head <slug>` finds none, open the integration PR with the `--existing --base-sha <base_sha>` call in `implement`'s [PR delivery](../../implement/references/spec-run.md#pr-delivery-before-step-1-claims-anything) step 6.
- **Step 3.** A `<slug>--<NN>` branch with a report in `$notes/<NN>.md` is merged first instead of rebuilt; one without (a stopped implementer) goes to a fresh implementer briefed to finish it in its worktree.

## Deploy gate

A `deploy-gate: true` ticket bounds the run: build up to and including it, then stop at step 7 with a PR; its dependents start after that PR is deployed.

When dependents would wait behind a gate, ask once, in step 1's question call, before the first dispatch (not after the gate PR opens): stop at the gate, or build the dependents in this run on a second integration branch `<slug>-2` cut from the gate branch's tip.

- Before dispatching the first contract/drop ticket on `<slug>-2`, confirm the gate branch `<slug>` has no remaining writes or reads to the columns or tables `<slug>-2` drops.
- `<slug>-2` takes changes only by merging `<slug>` (the gate ticket and its review fixes), never by merging or cherry-picking any other branch.
- Once the gate PR merges, move `<slug>-2`'s delta onto fresh `origin/<default>` for a second PR.

## Stopping mid-run

Merge what has landed. Ask which running implementers to cancel (a structured question ([harness-tools](../../harness-tools/SKILL.md)), with `multiSelect: true`, one option per name; otherwise in chat); stop each chosen one with `TaskStop({task_id: <name>})` in Claude Code, or per [harness-tools](../../harness-tools/SKILL.md) elsewhere, and release its ticket (`ticket.sh release <path> --note "<why>"`), keeping its worktree and branch. Where nothing can stop them, leave them running. Running implementers keep their claims. Report per ticket: merged (with its PR in a stack), in flight (worktree path), stopped (worktree path), released, or not started. A re-run on the same spec resumes (above).
