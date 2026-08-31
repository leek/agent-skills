# Inappropriate Static

`Between · Object Oriented Abusers · Interfaces`

A static method is a decision that the behaviour it holds will never need to
vary. That is true of a genuinely stateless operation, `max`, a pure format
helper, a global constant, and it is the reason Fowler and Martin both treat
those as fine. It stops being true the moment the method encodes a rule that
could plausibly have a second version: `HourlyPayCalculator::calculatePay()` is
one payment algorithm among many that will eventually be asked for, and being
static means no caller can be handed a different one. The cost lands first in
tests, where faking a hard-wired static needs a mocking framework doing tricks
rather than a seam the design provides, and then in production, where every
call site is welded to one implementation. The counterweight is
[Speculative Generality](speculative-generality.md): if no second algorithm
exists or is planned and the operation holds no state, leave it static, 
the smell is a static that resists substitution *and* has a reason to vary.

## Detection heuristics

### Agnostic

- A static method whose first parameter is a domain object it then reasons
  about; that is an instance method on that type, spelled backwards.
- Static methods carrying business rules that already have known variants:
  pricing, tax, discounting, ranking, permissions, scoring.
- Static state: caches, counters, memoization tables, "current" values, that
  is [Global Data](global-data.md) with an access modifier.
- The test for a caller can only be written by monkey-patching, aliasing, or
  rewriting the class loader; or it silently hits the real clock, filesystem,
  or network because there was no seam to interpose.
- No caller can select an alternative implementation in *any* environment, 
  not in tests, not per tenant, not behind a flag.
- A `*Utils` / `*Helper` class of statics with a private constructor: a module
  of procedures wearing a class as a namespace.
- Not the smell: pure functions with no plausible second implementation, and
  statics that the framework already makes substitutable.

### PHP / Laravel

- Distinguish framework idiom from your own hard-wiring. `User::query()`,
  `Cache::get()`, `Bus::dispatch()` and friends look static but resolve through
  the container, so `Cache::shouldReceive()`, `Bus::fake()`, `Http::fake()` and
  `Carbon::setTestNow()` / `travelTo()` all give you a seam. Those are not the
  smell. Your own `PriceCalculator::for($order)` with no interface and no
  container binding is.
- Static domain rules called directly from controllers, jobs, and listeners:
  `TaxTable::rateFor($country)`, `Scoring::rank($lead)`: no constructor to
  inject, so every consumer is coupled to the one implementation.
- Static methods on Eloquent models that are not query scopes and not factories
 (`Order::monthlyRevenue()` running its own queries) which cannot be varied
  per tenant or faked in a unit test.
- `public static` arrays or properties used as caches or lookup tables that
  survive across requests under Octane and across jobs on a long-lived worker
  (see [Global Data](global-data.md)).
- Traits used as a bag of `public static` helpers, so `use` becomes an import
  statement for procedures rather than shared behaviour.
- The strongest tell is in the test suite: `Mockery::mock('alias:App\\Foo')` or
  `'overload:App\\Foo'` means the production design offered no way in.

### TS / React

- `class DateUtils { static format() {} }`: the `static` keyword is doing
  namespace duty; a plain exported function is simpler, and either way the
  substitution problem is the *direct import*, not the keyword.
- A component or hook importing a concrete effectful function
  (`import { chargeCard } from '../lib/payments'`) and calling it inline, so
  every test has to reach for `vi.mock('../lib/payments')` instead of passing
  the function in as a prop, context value, or argument.
- Module-scope singletons exported ready-made (`export const api = new
  ApiClient()`) and used from everywhere as if static.
- `static` registries or handler maps on a class, populated at import time by
  side-effecting modules.
- `Date.now()`, `crypto.randomUUID()`, `Math.random()` called inline inside
  reducers, hooks, or render bodies, non-deterministic statics that force fake
  timers on every test that touches the component.

## Example

Translated from the upstream Python example.

Smelly; the pay rule is a static utility, so `PayrollRun` is welded to it:

```php
final class PayCalculator
{
    public static function calculatePay(Employee $employee, float $overtimeRate): int
    {
        return (int) round(
            $employee->base_hours * $employee->hourly_rate
            + $employee->overtime_hours * $employee->hourly_rate * $overtimeRate
        );
    }
}

final class PayrollRun
{
    public function payslipFor(Employee $employee): Payslip
    {
        return new Payslip($employee, PayCalculator::calculatePay($employee, 1.5));
    }
}
```

Solution; the rule becomes an object behind a contract, injected by the
container, so a salaried or contractor calculator can be bound in its place and
the test supplies a stub instead of patching a class:

```php
interface PayCalculator
{
    public function calculate(Employee $employee): int;
}

final readonly class HourlyPayCalculator implements PayCalculator
{
    public function __construct(private float $overtimeRate = 1.5)
    {
    }

    public function calculate(Employee $employee): int
    {
        return (int) round(
            $employee->base_hours * $employee->hourly_rate
            + $employee->overtime_hours * $employee->hourly_rate * $this->overtimeRate
        );
    }
}

final readonly class PayrollRun
{
    public function __construct(private PayCalculator $calculator)
    {
    }

    public function payslipFor(Employee $employee): Payslip
    {
        return new Payslip($employee, $this->calculator->calculate($employee));
    }
}
```

## Refactorings

- Inject Dependencies

## Related smells

| Smell | Edge |
|---|---|
| [Global Data](global-data.md) | co-exist |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Static Cling

---

*Derivative work adapted from "Inappropriate Static" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
