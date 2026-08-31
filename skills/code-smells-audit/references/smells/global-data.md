# Global Data

`Between · Data Dealers · Data`

State that lives in the global scope is a broker every module can reach, 
the same intermediary role [Middle Man](middle-man.md) plays, except the
broker here is the program itself, so nothing constrains who talks to it.
Any code can read it and, worse, any code can write it, and there is no
mechanical way to find out which code does: the dependency is invisible at
every call site, which is exactly the [Hidden Dependencies](hidden-dependencies.md)
smell, and if the value is mutable you also inherit
[Mutable Data](mutable-data.md) with an unbounded set of writers. Fowler's
framing is the useful one, in the era before objects, even a
[Long Parameter List](long-parameter-list.md) was considered the lesser evil,
and a Singleton is the same problem wearing a pattern's name. The exception
worth remembering: modules do have to communicate somehow, and driving global
state to zero usually just relocates the pain into
[Tramp Data](tramp-data.md) or a [Message Chain](message-chain.md), so the
goal is balance, not purity.

## Detection heuristics

### Agnostic

- Mutable state at module, file, or program scope that more than one unit
  writes to.
- Singletons, static registries, and service locators used as a place to
  stash values rather than as a lookup for behavior.
- You cannot enumerate the writers of a value without grepping the entire
  codebase; the read sites are findable, the write sites are not.
- Behavior depends on execution order: a test passes alone and fails in the
  suite, or the second run of a job behaves differently from the first.
- Tests need explicit reset or teardown to undo state a previous test left
  behind (see [Required Setup or Teardown Code](required-setup-or-teardown-code.md)).
- Concurrency hazards: the same value is shared across threads, workers, or
  requests with no ownership rule.

### PHP / Laravel

- `$GLOBALS`, `global $x`, and mutable `public static` properties, including
  static caches hung off models or helper classes.
- `config(['services.x.key' => $value])` used as a runtime scratchpad: the
  write mutates the shared config repository for the rest of the process, so
  under Octane or a long-lived queue worker it leaks into the next request or
  job.
- Container singletons (`$app->singleton()`, `app()->instance()`) that carry
  request-specific state, reached through a facade from anywhere, and never
  reset between jobs on the same worker.
- Values smuggled through the request lifecycle instead of arguments, 
  `request()->merge()`, `session()->put()`, or middleware setting a static
  "current tenant" that everything downstream reads.
- `env()` called outside `config/`, which makes behavior depend on the
  process environment and silently returns `null` once `config:cache` has
  run.

### TS / React

- Module-scope `let` that is imported widely and reassigned: one instance per
  bundle, shared by every consumer, and, on a Node server, shared across
  concurrent requests.
- Values parked on `window` or `globalThis` to hand data between modules that
  do not import each other.
- A Zustand/Redux store instantiated at module scope and imported directly
  rather than created per-request and supplied through a React context
  provider.
- `localStorage`/`sessionStorage` read and written ad hoc from components and
  utilities, used as a de facto global database.
- Test files needing `vi.resetModules()`, `jest.resetModules()`, or manual
  `store.setState(initialState)` in `beforeEach` because module state
  survives between tests.

## Example

Authored for this card: upstream has no code example for this smell.

Smelly; the current tenant lives in a public static property, so every layer
can read it and any layer can change it:

```php
final class TenantContext
{
    public static ?int $currentTenantId = null;
}

// middleware, console command, test bootstrap, a job retry, anywhere
TenantContext::$currentTenantId = $tenant->id;

final class InvoiceReport
{
    public function outstandingTotal(): int
    {
        return Invoice::query()
            ->where('tenant_id', TenantContext::$currentTenantId)
            ->where('status', 'unpaid')
            ->sum('amount');
    }
}
```

Solution; the value is encapsulated in an object that owns it and is handed
to the collaborators that need it, so the dependency is declared and the set
of writers is exactly one:

```php
final readonly class TenantContext
{
    public function __construct(
        public int $tenantId,
    ) {
    }
}

final readonly class InvoiceReport
{
    public function __construct(
        private TenantContext $tenant,
    ) {
    }

    public function outstandingTotal(): int
    {
        return Invoice::query()
            ->where('tenant_id', $this->tenant->tenantId)
            ->where('status', 'unpaid')
            ->sum('amount');
    }
}
```

Encapsulating the variable is the mechanical first step and is worth doing
even alone: once every read and write goes through one owner, you can see the
writers, and only then is it obvious whether the value should be injected,
scoped to the request, or passed as an argument.

## Refactorings

- Encapsulate Field

## Related smells

| Smell | Edge |
|---|---|
| [Middle Man](middle-man.md) | family |
| [Hidden Dependencies](hidden-dependencies.md) | causes |
| [Inappropriate Static](inappropriate-static.md) | co-exist |
| [Tramp Data](tramp-data.md) | antagonistic |
| [Long Parameter List](long-parameter-list.md) | antagonistic |
| [Message Chain](message-chain.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Global Variables

---

*Derivative work adapted from "Global Data" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
