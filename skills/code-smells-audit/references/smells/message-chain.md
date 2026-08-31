# Message Chain

`Between · Data Dealers · Message Calls`

A caller that needs something from a distant object walks there hop by hop:
`a.getB().getC().getD()`. Every link in the chain is a dependency the caller
never asked for and now carries, it knows not just its neighbour but the
shape of the whole relationship graph, so a change to any intermediate
structure breaks code several classes away from the edit. Splitting the walk
across temporary variables hides the sequence without removing an ounce of the
coupling. The habit behind it is asking objects for their internals and doing
the work outside them, instead of telling the object that already holds the
data to answer the question, the arrangement the Law of Demeter and Tell,
Don't Ask both argue for. The counterweight matters as much as the smell:
hiding every hop behind a forwarding method converts this into
[Middle Man](middle-man.md), so what you want is a balance between the two,
not zero hops.

## Detection heuristics

### Agnostic

- Three or more dots, arrows, or accessor calls between the caller and the
  value it actually wants.
- The chain's intermediate types appear nowhere else in the calling class, 
  they are transit, not collaborators.
- A rename or restructure two objects away breaks compilation or tests in
  modules that never mention the changed class.
- The same chain is copy-pasted at several call sites, so the graph knowledge
  is now duplicated as well as misplaced (see
  [Duplicated Code](duplicated-code.md)).
- Null or optional guards stack up along the walk, defending against a
  structure the caller should not have to know about.
- Test setup needs a deeply nested fixture built purely so the chain has
  something to traverse.

### PHP / Laravel

- Blade templates walking relations, `$order->customer->address->country->name`
: which couples the view to the schema and lazy-loads a query per hop.
- Controllers and jobs reaching through
  `auth()->user()->team->subscription->plan->limits` instead of asking the
  team for its limit.
- Stacked nullsafe operators (`$user?->team?->owner?->email`) or nested
  `optional()` calls: the number of `?->` is the length of the chain.
- Chains through the container and service objects, like
  `app(Registry::class)->driver('sms')->client()->options()`, so callers
  depend on the driver's internals rather than the registry's contract.
- Passing a whole model into a notification or mailable so the template can
  drill for the two attributes it needs.

### TS / React

- JSX reading `props.user.profile.settings.theme.color`, so the leaf component
  is coupled to the top-level API shape.
- Optional chaining used as structural armour, `a?.b?.c?.d ?? fallback`, 
  where each `?.` marks a relationship the component is guessing at.
- Components indexing deep into store state
  (`state.entities.orders.byId[id].customer.address.city`) rather than
  consuming a selector that exposes the value directly.
- An entire API response threaded down several component levels so a
  descendant can drill into it (see [Tramp Data](tramp-data.md)).
- Mock objects in tests that must reproduce four levels of nesting before a
  component will render.

## Example

Translated from the upstream Python example.

Smelly: `Minion` reaches through `Location` into `Field`, so it depends on
both:

```php
final class Minion
{
    private Location $location;

    public function action(): void
    {
        // ...
        if ($this->location->field->isFrontline()) {
            // ...
        }
    }
}

final class Location
{
    public Field $field;
}

final class Field
{
    public function isFrontline(): bool
    {
        // ...
    }
}
```

Solution: each object answers the question for the one above it, so `Minion`
only knows `Location`:

```php
final class Minion
{
    private Location $location;

    public function action(): void
    {
        // ...
        if ($this->isFrontline()) {
            // ...
        }
    }

    public function isFrontline(): bool
    {
        return $this->location->isFrontline();
    }
}

final class Location
{
    private Field $field;

    public function isFrontline(): bool
    {
        return $this->field->isFrontline();
    }
}

final class Field
{
    public function isFrontline(): bool
    {
        // ...
    }
}
```

Applied once, this is Hide Delegate. Applied to every hop reflexively, it is
how [Middle Man](middle-man.md) is born.

## Refactorings

- Hide Delegate
- Extract Method
- Move Method

## Related smells

| Smell | Edge |
|---|---|
| [Tramp Data](tramp-data.md) | family |
| [Long Parameter List](long-parameter-list.md) | co-exist |
| [Fate over Action](fate-over-action.md) | causes |
| [Indecent Exposure](indecent-exposure.md) | causes |
| [Middle Man](middle-man.md) | antagonistic |
| [Global Data](global-data.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Message Chain" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
