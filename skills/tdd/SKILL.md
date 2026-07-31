---
name: tdd
description: The red → green loop tuned for Pest/PHPUnit in a Laravel codebase — seams, what a good test is, and the anti-patterns to refuse. Use when building features test-first or when another skill needs the loop.
---

# TDD in Laravel

The red → green loop, tuned for Pest/PHPUnit in a Laravel codebase. Consult before and during the loop, not after.

Read `CONTEXT.md` if it exists so test names and interface vocabulary match the project's domain language, and respect ADRs in the area you're touching.

## Rules of the loop

- **Red before green.** Write the failing test first, watch it fail for the right reason (a missing route 404s, not a typo'd import), then write only enough code to pass. No speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle. Each next test responds to what the last cycle taught you — never all tests up front, then all implementation (bulk tests verify *imagined* behavior and go insensitive to real changes).
- **Refactoring is not part of the loop.** It belongs to the review step (`code-review`).

## What a good test is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't. A good test reads like a specification — `user cannot view another users invoice` says exactly what rule exists — and survives refactors because it doesn't care about internal structure.

## Seams — where tests go

A **seam** is the public boundary you test at (`codebase-design` holds the full deep-module vocabulary). Test only at seams agreed with the user; the highest seam that can observe the behavior, and as few seams as possible.

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

## Anti-patterns

- **Implementation-coupled** — mocks internal collaborators, tests private/protected methods, or verifies through a side channel. The tell: the test breaks on refactor while behavior is unchanged.
- **Tautological** — the assertion recomputes the expected value the way the code does (`expect(total($items))->toBe(collect($items)->sum(...))`), so it passes by construction. Expected values come from an independent source — a known-good literal, a worked example, the spec.
- **Presentation assertions** — asserting on displayed copy, labels, headings, nav items, element order, or CSS classes. Those are change-detectors, not tests. Assert behavior, persisted data, validation, authorization, side effects.
- **Framework tests** — asserting that Eloquent saves, that validation rules Laravel ships work, that a route resolves its controller. Test *your* branching, business rules, and edge cases only.
- **Horizontal slicing** — all tests first, then all implementation. Work in vertical slices: one test → one implementation → repeat.
