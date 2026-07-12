---
name: implement-plus
description: Implement one ticket or spec end to end in a Laravel codebase — claim it, TDD at pre-agreed seams with Pest/PHPUnit, run static analysis and Pint, review and verify the result, commit, and close the ticket. Use when the user says "implement this ticket/spec", passes a ready-for-agent issue, or wants to work the next frontier ticket.
---

# Implement Plus

Implement the work described by a ticket, a spec, or the conversation — one ticket per session, test-first, verified end to end.

Pipeline position: `to-spec-plus` (record) → `to-tickets-plus` (slice) → **`implement-plus`** (build).

## Process

### 1. Load and claim the work

Given a ticket reference, fetch its full body and comments, plus the parent spec if it links one (tracker fast path: `docs/agents/issue-tracker.md` → `## Issue tracker` section in `AGENTS.md`/`CLAUDE.md` → detect Linear MCP / GitHub `gh` / local markdown). On a shared tracker, **claim it first** — assign it to the driving dev — so concurrent sessions skip it. Confirm its blockers are all closed; if not, say so and stop rather than building on sand.

Given only conversation context, restate the scope in two or three lines before starting.

### 2. Confirm the seams

Tests go at **pre-agreed seams** — the public boundaries where behavior is observed (see [references/tdd-laravel.md](references/tdd-laravel.md) for the seam ladder). If the spec already agreed them, use those. If not, propose seams and confirm via `AskUserQuestion` before writing any test.

### 3. TDD loop

Red → green, one slice at a time, per [references/tdd-laravel.md](references/tdd-laravel.md):

- Write one failing test at an agreed seam, watch it fail for the right reason, write only enough code to pass it, repeat.
- Run the focused test each cycle: `php artisan test --filter=<TestName>` (or `vendor/bin/pest --filter`).
- Run static analysis regularly if the repo has it configured — check `composer.json` scripts for PHPStan/Larastan (`composer analyse` or similar) before assuming the command exists.
- Refactoring is not part of the loop — it belongs to the review step.

### 4. Laravel guardrails

- **Never** run `migrate:fresh`, `migrate:rollback`, or any destructive DB operation without explicit approval. Schema changes go in new migrations; live-table changes follow expand–contract as the ticket sequence dictates.
- Verify identifiers before using them — route names, config keys, enum values, icon names, package APIs. Presence in `composer.json` is not proof a package is registered or used.
- Test data comes from model factories; add factory states rather than hand-building models in tests.

### 5. Full suite, once

Run the full test suite once at the end (`php artisan test`). Fix failures you caused. Don't chase pre-existing failures — prove one is pre-existing (fails on the base commit too), then note it plainly and move on.

Run Pint before committing: `vendor/bin/pint --dirty`.

### 6. Review

Run the harness's code review (`/code-review`) if available. Otherwise spawn two parallel sub-agents over `git diff <base>...HEAD` and report both axes separately — a change can pass one and fail the other:

- **Standards** — does the diff follow the repo's documented conventions and avoid obvious smells (duplication, feature envy, speculative generality, primitive obsession)?
- **Spec** — does the diff faithfully implement what the ticket/spec asked: anything missing, anything nobody asked for, anything implemented wrong? Quote the spec line per finding.

Fix what's real; skip stylistic nitpicks tooling already handles.

### 7. Verify end to end

Tests passing is not the finish line — exercise the actual flow once (`/verify` skill if available): hit the route, run the command, dispatch the job, click through the Filament page. Report what you observed, not what should happen.

### 8. Commit

Stage only files you touched, **by explicit path** — never `git add -A` or `git add .`. Check `git status --porcelain` before committing; unstage anything foreign. Commit to the current branch.

### 9. Close the loop

On a tracker: post a resolution comment (what was built, where it deviated from the ticket and why, anything the next ticket should know), check off satisfied acceptance criteria, close the ticket. Never close or modify the parent spec/map issue. On local markdown tickets, set `status: closed` and append the resolution.

Then stop. The next ticket gets a fresh session with a clean context.
