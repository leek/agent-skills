# Null Check

`Between · Bloaters · Conditional Logic`

Because every mainstream language lets a reference be nothing, the absence of a
value leaks out of the object that produced it and becomes everyone else's
problem: guard clauses at the top of methods, `if` blocks around each use, and
defensive branches in views that only exist to survive a value that never
arrived. The same check reappears at every call site, so one design gap turns
into scattered [Duplicated Code](duplicated-code.md), and the model loses its
one-to-one correspondence with the domain — `null` is not a state the business
recognises, it is the type system shrugging. The fix is to give absence a
representation: a Null Object that implements the interface with do-nothing
behaviour, or an explicit optional type that forces the decision once, at the
boundary, rather than everywhere downstream. `Null Check` is the most common
instance of the broader [Special Case](special-case.md) smell, and the same
defensive instinct that produces it produces
[Afraid to Fail](afraid-to-fail.md). One guard is not a smell; a codebase where
every consumer of a value repeats the same guard is.

## Detection heuristics

### Agnostic

- The same null guard appears at three or more call sites for the same value —
  the check belongs to the producer, not each consumer.
- Functions returning `T | null` whose callers all immediately branch, so the
  nullability propagates up the stack instead of being resolved at its source.
- Guard clauses that return nothing meaningful (`return;`, `return null`) and
  therefore push the same decision onto the next caller.
- Null branches that are untested or unreachable in practice, kept "just in
  case" — a sign the value is never actually absent and the type is wrong.
- Absence is expressed by more than one sentinel in the same codebase (`null`,
  `''`, `0`, `-1`, empty array), so consumers check several of them.
- Every use of the value is preceded by the same fallback default, repeated
  literal by literal.

### PHP / Laravel

- Nullsafe operators and `optional()` used as ambient armour — `$user->profile
  ?->avatar_url ?? asset('img/default.png')` copy-pasted across Blade views
  and controllers.
- `belongsTo`/`hasOne` relations that could carry `->withDefault([...])` — the
  framework's built-in Null Object — but instead leave every reader guarding
  the relation.
- `find()`/`first()` followed by a hand-rolled `abort_if($model === null,
  404)` at each call site, where `findOrFail()`, `firstOrFail()`, `sole()`, or
  route model binding would resolve it once.
- Blade templates wrapping every field in `@if`/`@isset` because the view model
  hands the template raw nullable attributes instead of presentable values.
- Nullable columns without database defaults, so accessors, validators, and
  exports each re-implement the same `?? 0` / `?? 'N/A'` fallback.

### TS / React

- Optional chaining plus nullish coalescing at every read of the same value
  (`data?.user?.name ?? 'Anonymous'`), repeated across components.
- State typed `useState<Foo | null>(null)`, forcing every consumer to
  distinguish "loading" from "empty" — a discriminated union of explicit
  states removes the branch.
- Conditional rendering used purely as a null guard, `{user && <Profile
  user={user} />}`, in several components that all need the same fallback.
- Non-null assertions (`data!.items`) or casts that silence the compiler while
  the actual absence remains unhandled at runtime.
- Props typed `T | null | undefined` threaded through intermediate components
  that never read them, so every leaf re-checks
  ([Tramp Data](tramp-data.md)).

## Example

Translated from the upstream Python example.

Smelly — `bonusDamage()` may return nothing, so every consumer of the result
guards, and the nullability spreads into their return types:

```php
interface BonusDamage
{
    public function increaseDamage(float $damage): float;
}

final class Critical implements BonusDamage
{
    public function __construct(private readonly float $multiplier) {}

    public function increaseDamage(float $damage): float
    {
        return $damage + ($damage * $this->multiplier * random_int(0, 2));
    }
}

final class Magical implements BonusDamage
{
    public function __construct(private readonly float $multiplier) {}

    public function increaseDamage(float $damage): float
    {
        return $damage * $this->multiplier;
    }
}

final class Attack
{
    public function damage(float $base, ?BonusDamage $bonus): ?float
    {
        if ($bonus === null) {
            return null;
        }

        return $bonus->increaseDamage($base);
    }
}
```

Solution — absence gets a class that honours the contract, so the guard
disappears and the signatures stop lying:

```php
final class NoBonusDamage implements BonusDamage
{
    public function increaseDamage(float $damage): float
    {
        return $damage;
    }
}

final class Attack
{
    public function damage(float $base, BonusDamage $bonus): float
    {
        return $bonus->increaseDamage($base);
    }
}
```

The producer — `Perk::bonusDamage()` — now returns `NoBonusDamage` instead of
`null`, and the decision is made once where the value originates.

## Refactorings

- Introduce Null Object
- Introduce Optional

## Related smells

| Smell | Edge |
|---|---|
| [Special Case](special-case.md) | family |
| [Afraid To Fail](afraid-to-fail.md) | caused |
| [Flag Argument](flag-argument.md) | causes |
| [Conditional Complexity](conditional-complexity.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Null Check" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
