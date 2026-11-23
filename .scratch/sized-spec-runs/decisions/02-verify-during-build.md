---
title: "Verify each ticket as it merges, not once at the end"
type: grilling
status: closed
claimed-by:
blocked-by: []
---

## Question

How `implement-spec` takes the end-of-run verifier (5–63 min, alone on the critical path, fixers waiting on it) off the critical path. Chosen over size tiers, ticket-size caps, model per ticket and worktree pools after the run data in [01-size-tiers-in-implement-spec.md](01-size-tiers-in-implement-spec.md).

## Settled

- Build this lever first.

## Defaults applied

- One long-lived verifier subagent, started after the first merge and kept alive by follow-up messages ("ticket NN merged at SHA, verify its criteria"). It pays the environment setup once. (evidence: past verifiers spend their first 15–20 calls on database clone, migrate, operations, seeders, `npm run build`)
- The verifier works in its own detached verify worktree with its own registered database and Herd workspace, and moves it to each merge SHA, then runs only incremental setup (migrate, operations, build when assets changed). It never works in the integration checkout, so merges never change files under it. (default bias: isolation, the same as every implementer)
- Dependents dispatch at merge, as today; verification never gates the frontier. (user goal: speed)
- Verification follow-ups queue: the verifier takes one ticket at a time, in merge order. (default bias: one browser session, one database)
- A ticket's verify failure goes back to the same implementer, the same as a failed merge test in step 4; its fix merges like any other commit and the verifier re-checks that ticket. (context: step 4's existing rule)
- Step 5 keeps one verify pass, now narrow: only criteria whose code a later merge or a fix touched, plus anything that crosses tickets. Code review still runs once over the whole branch. (context: step 5's existing re-verify rule)
- Screenshots keep the `$notes/screenshots/<NN>-<what>.png` naming. (context: step 5)
- `autopilot` gets the same shape in the same change. (context: the shelved plan's choice to keep the two in step)
- Prove it with `run-metrics.sh`: time from last merge to delivery, before and after, on a run of 5 or more tickets. (context: retro SKILL.md)

## Unresolved risks

- A long-lived verifier's context grows with every ticket; on a 20-ticket run it may need a fresh verifier part way, briefed with the verify worktree path.
- A dependent built on a ticket that later fails verification may need its own small fix after the upstream fix lands.

## Resolution

Built on 2026-11-23 in `implement-spec` (step 4 verifier, narrow step 5 pass, step 8 cleanup) and `autopilot` (runner `verify` worker mode, worker contract, help text). Deviations from the defaults above, found in review before commit:

- Step 4 no longer waits for the verifier: step 5's review starts at once, and the verifier's last batch runs beside it.
- The orchestrator holds the queue: it hands the verifier one batch (every ticket merged since the last handoff) when its report lands.
- Each record names the commit it checked (`sha:`), so step 5 re-verifies only tickets whose code changed after it.
- The board shows a pass as `merged` with the note `verified`; the board rejects new statuses.
- `autopilot` has no long-lived subagent: the runner starts a fresh verify worker per batch in the shared `<branch>--verify` worktree, only while a build worker runs. Its failures are recorded for the finish worker's fix batch, never sent back to a build worker. Verify sessions do not count toward `--max-iterations`, and a crashed verify worker never fails the run.

Evidence: `autopilot`'s stub-runner tests (`test-run.sh`) and `verify-skills-collection.sh`. No real spec run has exercised it yet: compare one with `run-metrics.sh` (last merge to delivery).
