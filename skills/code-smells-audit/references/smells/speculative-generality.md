# Speculative Generality

`Between · Dispensables · Unnecessary Complexity`

Machinery built for a requirement that never arrived: an abstract base class
with one subclass, a strategy interface with one strategy, a parameter every
caller passes the same value for, an extension point with no extensions.
Humans are poor guessers about their own future, and the instinct to prepare
for anticipated scenarios is strong enough that developers pay a real cost
today against a benefit that stays hypothetical. The cost is not just the
extra file; it is that readers must understand the general case to follow
the specific one, and later changes have to be threaded through a seam that
was never load-bearing. Left long enough it decays into its neighbours: the
hollow layers become [Lazy Elements](lazy-element.md) and the unused branches
become [Dead Code](dead-code.md). The counterweight is
[Dubious Abstraction](dubious-abstraction.md); the answer is not "never
abstract" but "abstract on the second real case, not the first imagined one".

## Detection heuristics

### Agnostic

- An abstract class or interface with exactly one concrete implementation and
  no second one in flight.
- Generic type parameters instantiated with the same single type at every
  use.
- Parameters, options bags, or config keys where every call site passes the
  same literal, and defaults nobody overrides.
- Hook points (events, callbacks, strategy slots, plugin registries) with
  no subscribers.
- Hedged names: `AbstractBase*`, `Generic*`, `*Provider`, `*Factory`, or a
  `V2` sitting beside a `V1` where only one is live.
- Comments or tickets promising "so we can later support X" where "later"
  has visibly passed.
- Intermediate levels in a hierarchy that add no fields and no behaviour, 
  the layer exists to hold a category, not a difference.
- Unused parameters kept "for symmetry" with a sibling signature.

### PHP / Laravel

- An interface bound to one implementation in a service provider so the
  driver could be swapped later, and it never was, not even by a fake in
  tests.
- A `config/*.php` `driver` key or an `Illuminate\Support\Manager` subclass
  offering a driver menu of exactly one.
- Abstract base models, controllers, or jobs extended by a single class.
- `morphTo` polymorphic relations where the `*_type` column only ever holds
  one class name.
- Methods carrying `array $options = []` or `?Carbon $at = null` parameters
  no caller has ever passed.
- Events dispatched with no listeners registered, and listeners registered
  for events nothing dispatches.
- Multi-tenant, multi-currency, or multi-locale scaffolding, a `tenants`
  table with one row, a `currency` column that is always `USD`: carried by
  an app that has never had a second one.
- Deeply parameterised query builders where every caller uses the same two
  arguments.

### TS / React

- Generic components (`function List<T>(…)`) instantiated with one type
  across the whole app.
- Props like `as`, `variant`, `renderItem`, or `component` with exactly one
  value at every call site, and union members of a `variant` type nothing
  selects.
- A context, provider, and reducer built for state that one component reads.
- An adapter or wrapper layer around `fetch` or a query client "in case we
  switch libraries".
- Render-prop or children-as-function APIs where every consumer passes the
  same shape and could have taken plain JSX.
- Per-entity directory scaffolding (`types/`, `adapters/`, `mappers/`) where
  each folder holds a single trivial file.
- Configurable theme or feature plumbing threaded through props when the app
  ships one theme.

## Example

Translated from the upstream Python example.

Smelly: a medieval fighting game with no animals in it; `Animal` exists
because someday there might be horses:

```php
abstract class Animal
{
    public int $health = 0;
}

abstract class Human extends Animal
{
    public string $name = '';

    public int $attack = 0;

    public int $defense = 0;
}

final class Swordsman extends Human
{
}

final class Archer extends Human
{
}

final class Pikeman extends Human
{
}
```

Solution: collapse the speculative layer into the one that carries real
differences:

```php
abstract class Human
{
    public int $health = 0;

    public string $name = '';

    public int $attack = 0;

    public int $defense = 0;
}

final class Swordsman extends Human
{
}

final class Archer extends Human
{
}

final class Pikeman extends Human
{
}
```

When the horses do arrive, extracting `Animal` again is a mechanical
refactoring against three known subclasses, far cheaper than the years of
readers who had to ask what an `Animal` was doing in a game about soldiers.

## Refactorings

- Collapse Hierarchy
- Inline Method
- Inline Class
- Rename Method

## Related smells

| Smell | Edge |
|---|---|
| [Dubious Abstraction](dubious-abstraction.md) | antagonistic |
| [Lazy Element](lazy-element.md) | causes |
| [Dead Code](dead-code.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Speculative Generality" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
