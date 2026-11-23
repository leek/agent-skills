---
title: "Complexity-based execution modes for spec runs"
type: grilling
status: closed
claimed-by:
blocked-by: []
---

## Question

How to add Small / Medium / Large execution modes so a spec run stops paying the full orchestration cost for every spec, while keeping the quality gates.

## Settled

- Tiers live inside `implement-spec`: it reads a size and scales its fixed costs. There is no router in front, and `/implement` and `/implement all` stay as they are.
- `to-tickets` writes the size into the spec when it cuts tickets. `spec-run-state.sh` computes it only when the spec has none (or it is stale).
- Cut agents, keep gates. Every tier verifies and re-reviews its fixes:

  | | Small | Medium | Large |
  |---|---|---|---|
  | implementers | 1 subagent | parallel | parallel |
  | exploration subagent | no | when tickets share it | when tickets share it |
  | fixer-setup subagent | no | no | yes (up to 4) |
  | review axes | Correctness, Spec | + Standards | all (+ Design, UI) |
  | verify | inline | inline | verifier subagent |
  | review rounds | 1 + re-review of BLOCKING/MAJOR fixes only | same as Small | 2 + 1 |
  | fixers | 1, in the integration checkout | 1, in the integration checkout | parallel batch |

- A Small run's single implementer builds in the integration worktree: no ticket worktree, no ticket database, no merge step.
- Small and Medium skip step 6's full-suite pass when CI runs the suite on the PR; each ticket's focused tests stand as the evidence.
- `autopilot` reads the same size and scales its review, verify and fix stages the same way, in this same piece of work.

## Defaults applied

- A written size is stale under the same rule that makes `decision_sweep_done` false (a later commit to the spec or a ticket); the script then recomputes it. (context: matches the existing sweep-staleness check)
- Script thresholds: Small = 2 tickets or fewer, or a pure chain (widest frontier 1); Medium = 6 tickets or fewer and widest frontier 3 or fewer; Large = anything more. (default bias: simple, mechanical, tunable later from retro data)
- Risk forces Large whatever the count: any `deploy-gate: true` ticket, a new migration in a ticket's `## Files`, or a spec line marking auth, payments, or data deletion. (default bias: the gates a risky change needs are the Large ones)
- The size is fixed at step 1 and never changes mid-run; it is shown in step 1's summary and the board's `stage`, with no extra question. (default bias: no added question per run)
- The user can force a size in the arguments (`/implement-spec <spec> large`); the argument-hint names it. (established practice: the existing concurrency argument)
- UI axis still runs in any tier when the range changes what a user sees. (context: step 5's existing rule)
- A Small/Medium run whose BLOCKING-only re-review still finds BLOCKING or MAJOR issues takes Large's extra round, then reports the rest. (context: step 5's existing third round)
- Prove the saving with `retro`'s `run-metrics.sh`: compare phase milestones normalized by lines changed, before and after, on a Small and a Medium spec. (context: retro SKILL.md)

## Unresolved risks

- Dropping the Design axis in Small/Medium relies on `to-spec`'s blind designer having run; a spec written without it gets no design challenge.
- Thresholds are guesses until run-metrics data exists.

## Resolution

Shelved on 2026-11-23, before any build. Run data from 10 `implement-spec` runs (streamaba, 2–24 tickets, `retro`'s `run-metrics.sh`):

- Agent minutes: implementers 2,852 (64%), review agents 762 (17%), fixers 553 (12%), verifier 271 (6%).
- Review agents run in parallel, so a round costs about 5–9 min of wall time. Inline verify does the same 11–63 min of work in series. The tiers would save about 5% of wall time.
- Only 1 of 10 runs had 2 tickets or fewer.
- Implementer time is 72% model turns, 10% worktree setup, 9% tests. Turns (42–422 per ticket, 130k–580k context tokens each) scale with ticket size.
- The Python-heredoc edits in implementers are batched, asserted replacements (1 assertion failure in about 109), not waste.

Follow-up: grill which implementer-turn lever to build (ticket size cap, model per ticket, verify during the build, worktree setup).
