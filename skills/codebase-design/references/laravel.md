# Codebase design in Laravel

The [SKILL.md](../SKILL.md) vocabulary in Laravel's terms.

- **The container is the seam mechanism**: a PHP interface plus a service-provider binding. An interface with exactly one implementation, bound "for mocking", is a hypothetical seam; Laravel's fakes usually make it unnecessary.
- **Framework fakes are adapters at framework-owned seams.** `Storage::fake()`, `Queue::fake()`, `Mail::fake()`, `Http::fake()` are the second adapter for filesystem, queue, mail, and HTTP seams. Prefer them over hand-rolled ports.
- **Eloquent models are a wide, shared interface**: every attribute, scope, and relationship is surface area. Depth usually lives *above* them: an action or service class whose small interface (`ReconcileInvoice::run($invoice)`) hides the queries, state transitions, and side effects.
- **Controllers, commands, jobs, and Livewire/Filament components are entry-point adapters.** Logic accumulating in one is a deepening candidate.

## Dependency categories in Laravel

From [deepening.md](deepening.md):

- **Local-substitutable**: the database via `RefreshDatabase` on SQLite/MySQL, `Storage::fake()`, the `array` cache/session drivers, `Queue::fake()`.
- **Remote but owned**: the port is a PHP interface; production binds the HTTP/queue adapter in a service provider, tests bind an in-memory adapter.
- **True external, thin usage**: vendor calls behind the `Http` client, `Http::fake()` in tests.
- **Outcome assertions**: persisted rows via `assertDatabaseHas`, faked side effects via `Mail::assertQueued`.

## Designing for testability, in PHP

```php
// Testable: gateway injected via constructor (container resolves it)
public function __construct(private PaymentGateway $gateway) {}

// Hard to test: hard-wired inside
public function process(Order $order): void
{
    $gateway = new StripeGateway(config('services.stripe.secret'));
}
```

```php
// Testable: pure calculation, assert on the return value
public function calculateDiscount(Cart $cart): Discount

// Hard to test: mutates and persists as a side effect
public function applyDiscount(Cart $cart): void
```
