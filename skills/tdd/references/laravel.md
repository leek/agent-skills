# TDD in Laravel

The [SKILL.md](../SKILL.md) loop, seam ranking, and rules, mapped onto Pest/PHPUnit in a Laravel codebase.

## Seams in Laravel

1. **Transport boundary**: feature test: `actingAs($user)->post(route(...))` + response and `assertDatabaseHas` assertions.
2. **UI component**: `Livewire::test(...)` / Filament testing helpers.
3. **CLI command**: `$this->artisan('...')->assertExitCode(0)` plus side-effect assertions.
4. **Background job / event handler**: a queued job or listener: instantiate and `handle()`, or dispatch with real execution.
5. **Domain service / action**: an action or service class, tested at its public API.
6. **Model / data type**: Eloquent scopes, casts, and accessors.

## Laravel specifics

- **Database**: use whichever refresh trait the suite already uses (`RefreshDatabase`/`LazilyRefreshDatabase`).
- **Factories**: all test data via model factories; variants as factory states (`Invoice::factory()->overdue()`).
- **Side effects via fakes**: `Queue::fake()`, `Mail::fake()`, `Notification::fake()`, `Event::fake()`, `Storage::fake()`, `Http::fake()`: then assert the effect (`Mail::assertQueued`).
- **Time**: `$this->travel(...)` / `travelTo(...)`.
- **Fast loops with TIA (Pest v5)**: if the project is on Pest v5, use the [Tia engine](https://pestphp.com/docs/tia) so each red → green cycle replays only impacted tests instead of the whole suite, `./vendor/bin/pest --parallel --tia`, or enable it project-wide with `pest()->tia()->locally()` in `tests/Pest.php`. Requires PCOV or Xdebug. Local only, CI still runs the full suite.
- **Fast loops without TIA (Pest v4, or no coverage driver)**: run the suite with [`--parallel`](https://pestphp.com/docs/optimizing-tests) (`--processes=N` to override the one-per-core default).
