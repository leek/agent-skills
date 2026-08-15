---
name: tdd
description: The red → green loop tuned for Pest/PHPUnit in a Laravel codebase — seams, what a good test is, and the anti-patterns to refuse. Use when building features test-first or when another skill needs the loop.
---

# TDD in Laravel

The red → green loop, tuned for Pest/PHPUnit in a Laravel codebase. Consult before and during the loop, not after.

Read `CONTEXT.md` if it exists so test names and interface vocabulary match the project's domain language, and respect ADRs in the area you're touching.

Before writing or reviewing tests, read
[`references/testing-best-practices.md`](references/testing-best-practices.md)
and apply its value gate and rejection rules throughout the loop.

## Rules of the loop

- **Red before green.** Write the failing test first, watch it fail for the right reason (a missing route 404s, not a typo'd import), then write only enough code to pass. No speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle. Each next test responds to what the last cycle taught you — never all tests up front, then all implementation (bulk tests verify *imagined* behavior and go insensitive to real changes).
- **Refactoring is not part of the loop.** It belongs to the review step (`code-review`).

## What a good test is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't. A good test reads like a specification — `user cannot view another users invoice` says exactly what rule exists — and survives refactors because it doesn't care about internal structure.

## Seams — where tests go

A **seam** is the public boundary you test at (`codebase-design` holds the full deep-module vocabulary). Test at the chosen seams — the caller (`to-spec` or `implement`) picks them from the ranking below and states the choice rather than asking; test at the highest seam that can observe the behavior, and as few seams as possible. Ask only on a genuine fork the rules rank equally.

Highest first:

1. **HTTP boundary** — feature test: `actingAs($user)->post(route(...))` + response and `assertDatabaseHas` assertions. Default for anything with an endpoint.
2. **Livewire / Filament component** — `Livewire::test(...)` / Filament testing helpers, when behavior lives in the component.
3. **Console command** — `$this->artisan('...')->assertExitCode(0)` plus side-effect assertions.
4. **Queued job / listener** — instantiate and `handle()`, or dispatch with real execution, asserting side effects.
5. **Action / service class** — direct test at its public API, for logic shared by several entry points.
6. **Model** — non-trivial scopes, casts, derived attributes only.

## Laravel specifics

- **Database**: use whichever refresh trait the suite already uses (`RefreshDatabase`/`LazilyRefreshDatabase`) — don't introduce a second convention. Never point tests at a real environment's database.
- **Factories**: all test data via model factories; encode meaningful variants as factory states (`Invoice::factory()->overdue()`), not inline attribute soup repeated across tests.
- **Side effects via fakes**: `Queue::fake()`, `Mail::fake()`, `Notification::fake()`, `Event::fake()`, `Storage::fake()`, `Http::fake()` — then assert the effect (`Mail::assertQueued`), not the internal call path. Fake the boundary, never mock your own classes' internals.
- **Time**: `$this->travel(...)` / `travelTo(...)` for anything date-dependent; never `sleep()`.
- **Authorization is behavior**: for every "user can X" test, write the "user cannot X on someone else's record" test — record-level scoping is the most error-prone rule in a multi-tenant app.
- **Fast loops with TIA (Pest v5)**: if the project is on Pest v5, use the [Tia engine](https://pestphp.com/docs/tia) so each red → green cycle replays only impacted tests instead of the whole suite — `./vendor/bin/pest --parallel --tia`, or enable it project-wide with `pest()->tia()->locally()` in `tests/Pest.php`. Requires PCOV or Xdebug. Local only — CI still runs the full suite.
- **Fast loops without TIA (Pest v4, or no coverage driver)**: run the suite with [`--parallel`](https://pestphp.com/docs/optimizing-tests) (`--processes=N` to override the one-per-core default). Tests must be order-independent and not share database state — which the refresh-trait + factories rules above already guarantee.
