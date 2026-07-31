---
name: implement
description: Implement one ticket or spec end to end in a Laravel codebase — claim it, TDD at pre-agreed seams, review, verify, commit, close the ticket.
disable-model-invocation: true
---

# Implement

Implement the work described by a ticket, a spec, or the conversation — one ticket per session, test-first, verified end to end.

Pipeline position: decide (`grill-with-docs`/`wayfinder`) → spec (`to-spec`) → slice (`to-tickets`) → **build (`implement`, review and verify inside)**.

## Process

### 1. Load and claim the work

Given a ticket reference, fetch its full body and comments, plus the parent spec if it links one. Resolve the tracker through `docs/agents/issue-tracker.md` (written by `/setup`) or an `## Issue tracker` section in `CLAUDE.md`/`AGENTS.md`; when neither exists, it's a local markdown ticket under `.scratch/`. On a shared tracker, **claim it first** — assign it to the driving dev — so concurrent sessions skip it. Confirm its blockers are all closed; if not, say so and stop rather than building on sand.

Given only conversation context, restate the scope in two or three lines before starting.

### 2. Confirm the seams

Tests go at **pre-agreed seams** — the public boundaries where behavior is observed (the `tdd` skill holds the seam ladder). If the spec already agreed them, use those. If not, propose seams and confirm with the user (via `AskUserQuestion` where available, otherwise a plain question in chat) before writing any test.

### 3. TDD loop

Red → green, one slice at a time, per the `tdd` skill:

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

Run `/code-review` against the ticket's base commit — it reviews the diff on two axes (**Standards**: repo conventions and smell baseline; **Spec**: faithful to the ticket, nothing missing, nothing smuggled in) via foreground sub-agents and reports them side by side. If the harness additionally ships its own correctness review, run that too — bug-hunting is a third axis the two-axis review doesn't cover.

Fix what's real; skip stylistic nitpicks tooling already handles.

### 7. Verify end to end

Run the `verify` skill: exercise the actual flow once — hit the route, run the command, dispatch the job, click through the Filament page. Report what you observed, not what should happen.

### 8. Commit

Stage only files you touched, **by explicit path** — never `git add -A` or `git add .`. Check `git status --porcelain` before committing; unstage anything foreign. Commit to the current branch.

### 9. Close the loop

On a tracker: post a resolution comment (what was built, where it deviated from the ticket and why, anything the next ticket should know), check off satisfied acceptance criteria, close the ticket. Never close or modify the parent spec/map issue. On local markdown tickets, set `status: closed` and append the resolution.

Then stop. The next ticket gets a fresh session with a clean context.

## When you're done

End the session by printing the block below — on a clean finish, a stop, or a dead end. On harnesses without slash commands, write the command as plain phrasing (`run implement on <ref>`) instead of `/implement <ref>`.

```text
---
Pipeline: decide → spec → slice → **build**   (4 of 4)
Done: <what now works, the ticket ref, the commit>
Next:
  • <condition> → /<skill> <ref>
```

Check the tracker for the remaining frontier before writing the block — don't guess at what's left. List only the conditions that actually apply, most likely first:

- **More frontier tickets on the parent spec** → `/clear`, then `/implement <next frontier ticket>`; name it and how many remain
- **Every ticket on the parent spec is closed** → nothing to run; say the spec is complete and name anything deferred out of scope
- **Remaining tickets are all blocked** → `/implement <the blocker>` first, or `/grill-me` if the blocker is a decision
- **The build exposed a decision nobody made** → `/grill-me` on it, then re-run `/to-spec` if the spec is now wrong
- **Stopped mid-ticket** → say what passes, what's uncommitted, and the next red test to write
