# Inconsistent Style

`Between · Obfuscators · Names`

Formatting and structural conventions that change from file to file, so the
reader's expectations are reset every time they open a new one. Reading a
codebase should feel like reading one book, not a novel whose typeface
changes each page: layout that shifts with each author's preference costs
attention on every screen without ever failing a test. The dangerous variant
is sequence inconsistency: the order of parameters for one concept flipped
between sibling methods. If the flipped parameters have different types the
compiler catches it; if they share a type, the call site keeps compiling and
quietly does the wrong thing. Detect it by comparing sibling files and
sibling signatures, and by checking whether any formatter is actually
enforced rather than merely configured.

## Detection heuristics

### Agnostic

- The same construct formatted differently across files, argument wrapping,
  brace placement, quoting, trailing commas.
- No formatter or linter enforced in CI, so style is per-author and diffs
  carry reformat noise unrelated to the change.
- History contains whole-file reformat commits that undo each other.
- Sibling functions taking the same values in a different parameter order,
  especially same-typed parameters that swap without any error.
- Mixed casing conventions for the same kind of identifier within one
  namespace or module.

### PHP / Laravel

- No Pint or PHP-CS-Fixer config committed, or one that exists but is never
  run in CI; the rules are documented, not enforced.
- Sibling actions taking `(User $user, Team $team)` in one class and
  `(Team $team, User $user)` in another; when the parameters are
  `int $userId, int $teamId` the swapped call site type-checks perfectly.
- The same read expressed three ways across repositories:
  `Model::where(...)->first()`, `Model::query()->where(...)`, and
  `DB::table(...)`.
- Blade templates mixing `@if` / `@endif` directives with raw `<?php ?>`
  blocks, and `{{ }}` with `{!! !!}` where escaping was not the reason.
- A test suite split between Pest `it()` closures and PHPUnit `test_*`
  methods, with different assertion idioms for identical checks.

### TS / React

- Prettier and ESLint both configured but disagreeing, so files flip
  formatting depending on which one ran last; or neither gated in CI.
- Components declared inconsistently within one folder, `function Foo()`
  against `const Foo = () => …`, default exports against named exports.
- Related hooks taking their positional arguments in a different order, with
  matching types, so the swap survives type-checking.
- Mixed declaration conventions for the same shape: `interface` in some
  modules, `type` aliases in others; `React.FC` in some files, explicit props
  typing in the rest.
- The same dependency imported through a path alias in one file and a
  relative path in another, so it reads as two different modules.

## Example

Translated from the upstream Python example.

Smelly; the sequence-inconsistency variant: two sibling methods take the
same two `int` values in opposite order, and the second call site is wrong in
a way nothing will report:

```php
final class Character
{
    public const DAMAGE_BONUS = 1.5;

    public function rangedAttack(Character $enemy, int $damage, int $extraDamage): void
    {
        $total = $damage + $extraDamage * self::DAMAGE_BONUS;
        // ...
    }

    public function meleeAttack(Character $enemy, int $extraDamage, int $damage): void
    {
        $total = $damage + $extraDamage * self::DAMAGE_BONUS;
        // ...
    }
}

$witcher->rangedAttack($skeleton, 300, 200);
$witcher->meleeAttack($skeleton, 300, 200); // 300 is now the bonus, silently wrong
```

Solution: one order across the family, and named arguments at the call sites
so a future reordering breaks loudly instead of silently:

```php
final class Character
{
    public const DAMAGE_BONUS = 1.5;

    public function rangedAttack(Character $enemy, int $damage, int $extraDamage): void
    {
        // ...
    }

    public function meleeAttack(Character $enemy, int $damage, int $extraDamage): void
    {
        // ...
    }
}

$witcher->rangedAttack($skeleton, damage: 300, extraDamage: 200);
$witcher->meleeAttack($skeleton, damage: 300, extraDamage: 200);
```

## Refactorings

- Introduce Linter Rules
- Reorder Parameters

## Related smells

| Smell | Edge |
|---|---|
| [Inconsistent Names](inconsistent-names.md) | family |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Sequence Inconsistency

---

*Derivative work adapted from "Inconsistent Style" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
