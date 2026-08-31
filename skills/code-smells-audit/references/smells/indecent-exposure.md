# Indecent Exposure

`Within · Couplers · Data`

Everything is public because nothing was ever made private. Members that only
the class itself uses; a scratch field, a helper that exists to keep one
method readable, the collection behind a getter: sit in the open where any
caller can bind to them, and the moment one does, an implementation detail
has become a contract you have to keep. What follows is predictable: other
classes start operating on the exposed internals rather than asking the owner
to act ([Feature Envy](feature-envy.md)), pairs of classes settle into
trading private knowledge ([Insider Trading](insider-trading.md)), and
callers walk through the exposed structure to get what they want
([Message Chain](message-chain.md)). Exposed mutable fields add
[Mutable Data](mutable-data.md) on top, since the owner can no longer
guarantee its own invariants. The usual cause is not a decision at all but a
habit (write it public to get it working, never go back and tighten it) so
the fix starts as an audit of what actually needs to be visible.

## Detection heuristics

### Agnostic

- A class with no private or protected members at all: the access modifiers
  were never chosen, only defaulted.
- Public methods whose only callers are the class itself and its unit test.
- Accessors generated for every field regardless of whether anything outside
  reads or writes them.
- A getter hands out the internal collection or array by reference, so
  callers can add and remove behind the owner's back.
- Public members named like internals (`buffer`, `tmpState`, `stepTwo`), 
  the vocabulary admits they were never meant to be seen.
- The public surface is much larger than the class's job, so a reader cannot
  tell the entry points from the machinery.

### PHP / Laravel

- Classes where helper methods stay `public` purely by default; `private`,
  `protected`, and `final` appear nowhere in the file.
- Eloquent models with `$guarded = []`, or `$fillable` listing every column,
  so a request payload can mass-assign internals like `status`, `role_id`, or
  `balance`.
- Models serialized straight into responses instead of through an API
  Resource, making the table schema the public contract, `$hidden`,
  `$visible`, and `toArray()` overrides exist precisely to narrow it.
- Relations and query builders exposed for callers to extend
  (`$order->lines()->create(...)` scattered across controllers) instead of an
  `addLine()` on the model that can enforce the rules.
- Traits whose members are all public, so every consuming class silently
  re-publishes them as part of its own API.

### TS / React

- A barrel `index.ts` using `export *`, which promotes every internal symbol
  of every module into the package's public API.
- Modules exporting their helpers, constants, and intermediate types when
  only one function is the intended entry point.
- Passing a `useState` setter or a ref down as a prop so children mutate the
  parent's state directly, rather than a named callback describing the
  intent.
- Store modules exporting raw `setState` or the state object itself, letting
  consumers reach into `store.getState().internals` instead of going through
  named actions and selectors.
- Hooks returning the live array or object held in state without `readonly`
  or `as const`, so consumers can push into the owner's data.

## Example

Translated from the upstream Python example.

Smelly: `count` is public, so anything can set it to anything and the
counter's only rule (it goes up by one) is unenforceable:

```php
final class Counter
{
    public int $count = 0;

    public function bump(): void
    {
        $this->count++;
    }
}

$counter = new Counter();
$counter->bump();
$counter->count = 100; // nothing stops this
```

Solution; the field is private and reachable only through the operations
the class chooses to offer:

```php
final class Counter
{
    private int $count = 0;

    public function count(): int
    {
        return $this->count;
    }

    public function bump(): void
    {
        $this->count++;
    }

    public function reset(): void
    {
        $this->count = 0;
    }
}

$counter = new Counter();
$counter->bump();
echo $counter->count();
```

PHP 8.4's asymmetric visibility gives the same guarantee with less ceremony, 
`public private(set) int $count = 0;` keeps reads open and confines writes to
the class, but the decision is the point either way: publish the operations,
not the state.

## Refactorings

- Choose Proper Access Control
- Encapsulate Field
- Encapsulate Collection
- Hide Behind Method
- Hide Behind Abstract Class
- Hide Behind Interface

## Related smells

| Smell | Edge |
|---|---|
| [Insider Trading](insider-trading.md) | causes |
| [Feature Envy](feature-envy.md) | causes |
| [Message Chain](message-chain.md) | causes |
| [Mutable Data](mutable-data.md) | co-exist |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Excessive Exposure

---

*Derivative work adapted from "Indecent Exposure" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
