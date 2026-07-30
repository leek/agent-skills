# Shotgun Surgery

`Between · Change Preventers · Responsibility`

One conceptual change, many files. Behavior that should have lived in a single
place got smeared across several classes, so introducing or modifying it means
a wide, shallow edit all over the codebase — and the wider the sweep, the
easier it is to miss a site and ship a bug. It is the sibling of Divergent
Change: there, one class keeps changing for unrelated reasons; here, one
reason keeps changing many classes. Wake traces it to an overzealous attempt
to cure Divergent Change, splitting a responsibility until no class owns it;
cascading relationships and several classes each solving a fragment of one
simple problem produce it too. Kerievsky named the same thing Solution Sprawl,
the difference being how you notice it — Divergent Change is felt while
editing, sprawl is seen when you survey the change afterwards.

## Detection heuristics

### Agnostic

- A one-line feature change produces a wide, shallow diff: a dozen files, two
  or three lines each, none of them referencing one another.
- You locate the edit sites by grepping for a literal or a constant rather
  than by following calls — the code has no path connecting them.
- Adding one case to an enum, status, or type forces edits in modules that
  have no other reason to know about each other.
- The same guard, format, or validation is restated in many places, so the
  rule has no single home (see [Duplicated Code](duplicated-code.md)).
- Review comments are routinely "you missed one", and follow-up commits keep
  patching sites the original change forgot.
- The variants you must find are each shaped differently, which is
  [Oddball Solution](oddball-solution.md) feeding this smell.

### PHP / Laravel

- Adding one order status means editing the PHP enum, a Blade `@switch` badge
  map, a policy method, a Filament column's state map, and a notification —
  five files with no link between them.
- The same authorization rule expressed in a policy, again in a Blade `@can`,
  and again in route middleware, so tightening it means finding all three.
- One business rule split across a FormRequest's `rules()`, a model cast or
  mutator, and a migration constraint.
- Queue conventions (`$tries`, `$backoff`, `retryUntil()`) set per job across
  dozens of job classes instead of on a shared base or via a middleware.
- Tenancy or rate-limit concerns repeated per route rather than applied once
  through a middleware group or a global scope.

### TS / React

- Adding a variant to a discriminated union requires editing several `switch`
  statements the compiler cannot flag, because each has a `default` case.
- Adding one form field touches the type, the schema, the initial state, the
  reducer, the submit mapper, and the API payload type.
- Spacing, colour, or z-index values hardcoded per component instead of
  tokens, so one design decision becomes a repository-wide sweep.
- Every component re-implementing loading, error, and retry handling around
  `fetch`, so changing the retry policy means touching all of them.
- A new route registered separately in the router config, the nav array, the
  breadcrumb map, and the permission list.

## Example

Translated from the upstream Python example.

Smelly — the energy check and its failure handling are restated in every
action, so changing what "no energy" does means editing all four:

```php
final class Minion
{
    public int $energy;

    public function attack(): void
    {
        if ($this->energy < 20) {
            $this->animate('no-energy');
            $this->skipTurn();

            return;
        }
        // ...
    }

    public function castSpell(): void
    {
        if ($this->energy < 50) {
            $this->animate('no-energy');
            $this->skipTurn();

            return;
        }
        // ...
    }

    public function block(): void
    {
        if ($this->energy < 10) {
            $this->animate('no-energy');
            $this->skipTurn();

            return;
        }
        // ...
    }

    public function move(): void
    {
        if ($this->energy < 35) {
            $this->animate('no-energy');
            $this->skipTurn();

            return;
        }
        // ...
    }
}
```

Solution — the rule gets one home, so the next change to it is one edit:

```php
final class Minion
{
    public int $energy;

    public function attack(): void
    {
        if (! $this->hasEnergy(20)) {
            return;
        }
        // ...
    }

    public function castSpell(): void
    {
        if (! $this->hasEnergy(50)) {
            return;
        }
        // ...
    }

    public function block(): void
    {
        if (! $this->hasEnergy(10)) {
            return;
        }
        // ...
    }

    public function move(): void
    {
        if (! $this->hasEnergy(35)) {
            return;
        }
        // ...
    }

    private function hasEnergy(int $required): bool
    {
        if ($this->energy < $required) {
            $this->handleNoEnergy();

            return false;
        }

        return true;
    }

    private function handleNoEnergy(): void
    {
        $this->animate('no-energy');
        $this->skipTurn();
    }
}
```

## Refactorings

- Extract Method
- Combine Functions into Class
- Combine Functions into Transform
- Split Phase
- Move Method
- Move Field
- Inline Method
- Inline Class

## Related smells

| Smell | Edge |
|---|---|
| [Divergent Change](divergent-change.md) | family |
| [Parallel Inheritance Hierarchies](parallel-inheritance-hierarchies.md) | family |
| [Oddball Solution](oddball-solution.md) | caused |
| [Base Class Depends on Subclass](base-class-depends-on-subclass.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Solution Sprawl

---

*Derivative work adapted from "Shotgun Surgery" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
