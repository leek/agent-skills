# Hidden Dependencies

`Between · Data Dealers · Data`

A class that quietly fetches what it needs — from the global scope, a
container, a static factory, the environment — instead of being given it. The
constructor takes nothing, so the object looks free to create, and the
dependency only announces itself at runtime, in the branch that happens to
touch it. That makes construction a lie: the caller cannot tell from the
signature what has to exist first, so the class works on the machine where
the environment was already prepared and fails where it was not, and the
preparation ritual itself becomes
[Required Setup or Teardown Code](required-setup-or-teardown-code.md). Every
hidden edge is also a thing a test must mock without any signature telling it
to, and a change to a collaborator that appears in no constructor can break
this class from a distance. [Global Data](global-data.md) is the usual
supplier. The counterweight: making every last collaborator explicit is how
you arrive at a [Long Parameter List](long-parameter-list.md), so group
related dependencies rather than listing them all.

## Detection heuristics

### Agnostic

- An empty (or primitives-only) constructor on an object that is plainly not
  stateless — the collaborators appear halfway down a method body instead.
- Methods that construct or look up their own collaborators rather than
  receiving them.
- The signature does not tell you what must be true for the call to succeed;
  you learn it from a runtime error like "not initialized" or "no active
  context".
- Instantiating one class in a test requires booting the framework, setting
  environment variables, or seeding a global first.
- Behavior varies by execution context (web request vs. background worker vs.
  CLI) with nothing in the API that names the context.
- Editing a class that this one never references — no import, no
  constructor argument — breaks it.

### PHP / Laravel

- `app(Thing::class)` or `resolve(Thing::class)` called inside a method body:
  service location, which hides the edge the container is resolving.
- Facades used inside domain classes (`Cache::`, `Http::`, `Mail::`,
  `Auth::user()`), so the collaborator never appears in the signature and the
  test has to reach for `Cache::fake()` or `Http::fake()` to make the class
  runnable.
- `env()` or `config()` read deep inside a class instead of config values
  being injected at construction, which ties behavior to the process
  environment.
- Implicit clock, randomness, and connection dependencies: `now()`,
  `Carbon::now()`, `Str::uuid()`, `DB::` inside methods. Needing
  `Carbon::setTestNow()` to test a class is the confession.
- Models reaching into the request lifecycle from accessors, observers, or
  global scopes (`request()`, `auth()`, `session()`), so the same model
  behaves differently inside a queued job or Artisan command where there is
  no request and no authenticated user.

### TS / React

- Modules importing an already-instantiated singleton (`db`, `apiClient`,
  `analytics`) at module scope instead of receiving it, so tests can only
  intervene with `vi.mock`/`jest.mock` on the module path.
- Hooks calling `useContext` for a provider the component's props never
  mention, surfacing as "must be used within a Provider" at render time.
- Components calling `fetch` or axios directly rather than taking a client or
  query function, which forces network stubbing (MSW, fetch mocks) into every
  test that renders them.
- `process.env` / `import.meta.env` read inside components and utilities
  rather than passed in as configuration.
- Ambient platform calls buried in logic — `Date.now()`, `Math.random()`,
  `window.localStorage`, `navigator` — requiring fake timers or a jsdom
  global to exercise a pure-looking function.

## Example

Translated from the upstream Python example.

Smelly — `Cart` reaches out and resolves its customer, so nothing at the call
site says a customer is involved:

```php
final class Cart
{
    private Customer $customer;

    public function __construct()
    {
        $this->customer = app(Customer::class); // silently resolved
    }
}

$cart = new Cart();
```

Solution — the dependency is passed in, so the signature states the
requirement and a test can hand over whichever customer it wants:

```php
final class Cart
{
    public function __construct(
        private readonly Customer $customer, // received explicitly
    ) {
    }
}

$cart = new Cart($customer);
```

In Laravel the constructor form costs nothing at the call site — the
container still autowires `Cart` — but the edge is now visible to readers,
to static analysis, and to tests.

## Refactorings

- Inject Dependencies

## Related smells

| Smell | Edge |
|---|---|
| [Global Data](global-data.md) | caused |
| [Required Setup or Teardown Code](required-setup-or-teardown-code.md) | causes |
| [Long Parameter List](long-parameter-list.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Hidden Dependencies" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
