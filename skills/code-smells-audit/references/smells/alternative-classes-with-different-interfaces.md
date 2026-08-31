# Alternative Classes with Different Interfaces

`Between · Object Oriented Abusers · Duplication`

Two classes that do the same job, spelled differently. The behavior is
interchangeable but the vocabulary is not: each class names its methods after
the concrete type they live on, so nothing in the type system records that
either one would do. The tell is at the call sites: code must know which
class it is holding before it knows which method to call, and every new
variant adds another branch rather than another implementation. It grows when
two people solve the same problem without knowing about each other's work, or
when no interface or abstract base existed to force one shared name.

## Detection heuristics

### Agnostic

- Method names that differ only by the type they belong to (`hugZombie` /
  `hugSnowman`) while the bodies do the same work.
- Call sites branch on concrete type, `instanceof`, a type tag, a `switch`
  on class name, to choose which spelling to invoke.
- Rename the methods to match and the two bodies read as near-copies (the
  [Duplicated Code](duplicated-code.md) hiding underneath).
- Neither class implements a common interface or extends a base that would
  make the two substitutable.
- Supporting a third variant means editing every caller instead of adding one
  class.

### PHP / Laravel

- Sibling services exposing `chargeStripe()` and `chargePaypal()` instead of
  one `charge()` contract, with `match (true) { $gateway instanceof
  StripeGateway => ... }` at each call site.
- Two implementations of the same concept where neither is bound to an
  interface in a service provider, so nothing can be swapped through the
  container or faked in a Pest test.
- Parallel Eloquent scopes named after the model (`scopeActiveInvoices`,
  `scopeActiveSubscriptions`) applying the same constraints.
- Queued jobs or listeners with identical lifecycles but different entry
  points, so they cannot share an abstract base or be composed with
  `Bus::chain()`.
- Hand-rolled driver variants that ignore the framework contract already
  covering them (`Illuminate\Contracts\Filesystem\Filesystem`,
  `Illuminate\Contracts\Queue\Queue`), putting them out of reach of
  `Storage::extend()` and friends.

### TS / React

- Two modules exporting the same capability under different names
  (`fetchUserData` vs `getUserProfile`) with structurally identical returns.
- Sibling components naming the same event differently (`onSelectUser` vs
  `onPickAccount`), forcing a wrapper lambda at every usage.
- Custom hooks returning the same data under renamed fields (`{ data, loading
  }` vs `{ result, isFetching }`), so no consumer can be typed against one
  shape.
- Duplicate TS interfaces for one entity with renamed fields, bridged by a
  hand-written mapper instead of a single shared type.
- Adapter or provider implementations that declare no shared interface, so
  the compiler never notices when they drift apart.

## Example

Translated from the upstream Python example.

Smelly: same behavior, two vocabularies, so callers must know the concrete
type:

```php
final class Snowman extends Humanoid
{
    public function hugSnowman(): void
    {
        // ...
    }
}

final class Zombie extends Humanoid
{
    public function hugZombie(): void
    {
        // ...
    }
}

$target instanceof Zombie
    ? $target->hugZombie()
    : $target->hugSnowman();
```

Solution: one name, declared once, and the branch at the call site
disappears:

```php
interface Huggable
{
    public function hug(): void;
}

final class Snowman extends Humanoid implements Huggable
{
    public function hug(): void
    {
        // ...
    }
}

final class Zombie extends Humanoid implements Huggable
{
    public function hug(): void
    {
        // ...
    }
}

$target->hug();
```

## Refactorings

- Move Method

## Related smells

| Smell | Edge |
|---|---|
| [Oddball Solution](oddball-solution.md) | family |
| [Duplicated Code](duplicated-code.md) | co-exist |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Duplicate Abstraction

---

*Derivative work adapted from "Alternative Classes with Different Interfaces"
in Marcel Jerzyk's [Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
