# Parallel Inheritance Hierarchies

`Between · Change Preventers · Responsibility`

Two inheritance trees welded together by composition, so that adding a
subclass to one obliges you to add its mirror to the other. The tell is
usually the shared prefix: `BasicUser` needs a `BasicFunctions`,
`PremiumUser` needs a `PremiumFunctions`, and a naming convention is doing
the work an abstraction should be doing. Fowler files it as a special case of
Shotgun Surgery — one conceptual change, two coordinated edits, with nothing
but discipline enforcing the coordination. Some domains genuinely have two
independent axes, and modelling both is fine; the smell is the artificial
version, where the second tree exists only because someone split classes
mechanically along the same seam rather than because its subclasses mean
anything on their own. You pay for it twice: every new variant costs double,
and the trees drift the moment somebody adds one half and forgets the other.

## Detection heuristics

### Agnostic

- Subclass names in the two hierarchies pair up one-for-one by prefix or
  suffix, and the pairing is the only thing holding them together.
- Adding a subclass on one side leaves a hole on the other — a missing branch,
  an unhandled case, or a to-do that a reviewer has to catch.
- One tree's subclasses carry no behaviour of their own; they exist to be
  selected by their counterpart (see [Shotgun Surgery](shotgun-surgery.md)).
- A factory, registry, or `match` maps each subclass of A onto exactly one
  subclass of B, and has grown a line per pair.
- Both trees have the same depth and the same branching factor, and always
  have — the shape is copied, not derived.

### PHP / Laravel

- A single-table-inheritance model tree (subclasses selected off a `type`
  column) shadowed by a parallel tree of service or handler classes, one per
  model subclass, each doing near-identical work.
- An abstract job hierarchy paired one-for-one with validators or DTOs —
  `CsvImportJob`/`CsvImportPayload`, `XmlImportJob`/`XmlImportPayload` — where
  the second half differs only in the class it names.
- An exception hierarchy mirroring a service hierarchy exactly
  (`PaymentService`/`PaymentServiceException`, and so on) when no caller ever
  catches the subclasses distinctly.
- Filament resources or Livewire components subclassed once per model variant,
  where the subclasses override only static properties — configuration
  wearing the costume of inheritance.

### TS / React

- A component tree paired with a hook tree — `useBasicUserPanel`,
  `usePremiumUserPanel` — one hook per component variant, differing by a
  constant.
- A discriminated union of domain types mirrored by a parallel set of props
  interfaces that must be extended in lockstep with it.
- Every variant shipping as a quartet — `Foo`, `FooContainer`, `FooProvider`,
  `FooSkeleton` — when only one member of the quartet actually varies.
- Error classes mirroring API-client subclasses one-for-one, none of them
  narrowed on individually at any call site.

## Example

Translated from the upstream Python example.

Smelly — the second hierarchy exists only to shadow the first, and the prefix
is the contract:

```php
abstract class User
{
    public function __construct(protected Functions $functions)
    {
    }
}

abstract class Functions
{
}

final class BasicUser extends User
{
}

final class BasicFunctions extends Functions
{
}

final class PremiumUser extends User
{
}

final class PremiumFunctions extends Functions
{
}

// every new user subclass drags a same-prefixed Functions subclass with it
```

Upstream contrasts this with a domain where both trees stand on their own.

Solution — the composed hierarchy's subclasses carry independent meaning and
get shared across the first tree, so the two stop mirroring:

```php
abstract class Animal
{
    public function __construct(protected Food $food)
    {
    }
}

abstract class Food
{
}

final class Elephant extends Animal
{
}

final class Lion extends Animal
{
}

final class Vegan extends Food
{
}

final class Carnivore extends Food
{
}

// Vegan and Carnivore are real domain concepts; a third herbivore reuses
// Vegan instead of demanding an ElephantFood
```

Where the second tree has no such meaning of its own, collapse it: fold the
subclasses back into one class and let the variant be data the first
hierarchy passes in.

## Refactorings

- Move Method
- Move Field
- Create Partial
- Collapse Hierarchy

## Related smells

| Smell | Edge |
|---|---|
| [Shotgun Surgery](shotgun-surgery.md) | family |
| [Combinatorial Explosion](combinatorial-explosion.md) | family |
| [Duplicated Code](duplicated-code.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Parallel Inheritance Hierarchies" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
