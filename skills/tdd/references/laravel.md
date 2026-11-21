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
- **Each red → green cycle runs the one test file**: pass its path (`vendor/bin/pest tests/Feature/FooTest.php`, narrowed with `--filter=` inside it). A bare `--filter` still loads every test file. Never a suite directory or the whole suite inside the loop.
- **Tia (Pest v5) is not a loop tool.** Any path or `--filter` turns it off, and an unscoped run after a PHP edit with no PCOV or Xdebug loaded runs the **full suite**. A change to a model, `TestCase` or `tests/Pest.php` marks most of the suite affected anyway. Use a project's own affected-tests command when it has one; an unscoped Tia run is the user's call.
- **`--parallel`** pays off only for a batch of several files (the end-of-slice pass), not one file; paratest takes a single path, so list several files in a phpunit config or the project's wrapper.
