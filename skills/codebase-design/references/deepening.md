# Deepening

How to deepen a cluster of shallow modules safely, given its dependencies. Assumes the vocabulary in [SKILL.md](../SKILL.md): **module**, **interface**, **seam**, **adapter**.

## Dependency categories

When assessing a candidate for deepening, classify its dependencies. The category determines how the deepened module is tested across its seam.

### 1. In-process

Pure computation, in-memory state, no I/O (money math, state transitions, validation rules. Always deepenable) merge the modules and test through the new interface directly. No adapter needed.

### 2. Local-substitutable

Dependencies with test stand-ins the suite can run locally: the database via `RefreshDatabase` on SQLite/MySQL, `Storage::fake()`, the `array` cache/session drivers, `Queue::fake()`. Deepenable whenever the stand-in exists, which in Laravel is most framework-owned I/O. The deepened module is tested with the stand-in running in the suite. The seam is internal; no port at the module's external interface.

### 3. Remote but owned (Ports & Adapters)

Your own services across a network boundary (internal APIs, sibling apps). Define a **port** (PHP interface) at the seam. The deep module owns the logic; the transport is injected as an **adapter** via the container. Tests bind an in-memory adapter; production binds the HTTP/queue adapter in a service provider.

Recommendation shape: *"Define a port at the seam, implement an HTTP adapter for production and an in-memory adapter for testing, so the logic sits in one deep module even though it's deployed across a network."*

### 4. True external (fake at the edge)

Third-party services (Stripe, Twilio, S3-compatible APIs) you don't control. Two workable shapes, by how much of the vendor surface you use:

- **Thin usage** → keep vendor calls behind the framework's HTTP client and use `Http::fake()` in tests; the framework seam is the port.
- **Rich usage** → give the module an injected port (`PaymentGateway`) with a vendor adapter for production and a fake adapter for tests, so vendor types never leak into the deep module's interface.

## Seam discipline

- **One adapter means a hypothetical seam. Two adapters means a real one.** Don't introduce a port unless at least two adapters are justified (typically production + test). A single-adapter seam is just indirection, and in Laravel, an interface bound to one implementation "for mocking" when a framework fake already covers it.
- **Internal seams vs external seams.** A deep module can have internal seams (private to its implementation, used by its own tests) as well as the external seam at its interface. Don't expose internal seams through the interface just because tests use them.

## Testing strategy: replace, don't layer

- Old unit tests on shallow modules become waste once tests at the deepened module's interface exist, delete them.
- Write new tests at the deepened module's interface. The **interface is the test surface**.
- Tests assert on observable outcomes through the interface (return values, persisted rows (`assertDatabaseHas`), faked side effects (`Mail::assertQueued`)) not internal state or call order.
- Tests should survive internal refactors; they describe behaviour, not implementation. If a test has to change when the implementation changes, it's testing past the interface.
