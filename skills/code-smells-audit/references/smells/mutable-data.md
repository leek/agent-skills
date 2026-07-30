# Mutable Data

`Between · Functional Abusers · Data`

A value that anything holding a reference can rewrite at any moment. The
object is handed around, each collaborator writes to it, and the last writer
wins — silently, and in an order nobody declared. Bugs from this class of
data are expensive precisely because they are rare and timing-dependent: the
failure needs a specific sequence to reproduce, and by the time execution is
paused the field already holds someone else's value. Fowler names shared
mutability as one of the pressures that pushed functional programming into
the mainstream, where data is replaced rather than edited; the point is not
that object-oriented code should become functional, but that a field which
never needs to change should be unable to. The habit compounds with
[Side Effects](side-effects.md), because a method free to mutate its input
rarely stops at the one field it advertises, and with
[Global Data](global-data.md), which is mutable data with unlimited reach.

## Detection heuristics

### Agnostic

- A variable reassigned several times in one scope while keeping the same
  name, so the name describes a slot rather than a value.
- Setters exist for fields that have no legitimate reason to change after
  construction, and none of them enforce an invariant.
- A method both answers a question and changes state, so callers cannot read
  without writing (Separate Query from Modifier is the fix).
- One object handed to several collaborators in sequence, each of which may
  write to it — the object's final state is a function of call order.
- Derived values stored next to the inputs they were computed from and kept
  in sync by hand, so the two can disagree.
- A defect that reproduces under load or in a specific test order but never
  when stepped through.

### PHP / Laravel

- Value-shaped classes with public writable properties or bare setters where
  PHP 8.1 `readonly` properties (or an 8.2 `readonly class`) would state the
  intent and let the engine enforce it.
- An Eloquent model passed through jobs, listeners, and observers where any
  of them may `fill()`, `setAttribute()`, or assign `$model->attr = ...`, and
  the eventual `save()` sits far from the mutation that mattered.
- Runtime configuration writes — `Config::set()` or `config(['a.b' => $x])`
  mid-request — mutating state every later resolve reads.
- Container singletons (`app()->singleton()`, `app()->instance()`) or static
  properties holding request-scoped data; under Octane the container outlives
  the request, so the mutation leaks into the next one.
- In-place collection mutation (`transform()`, `push()`, `forget()`) or
  arrays taken by reference (`function f(array &$rows)`) where the
  non-mutating counterparts (`map()`, `reject()`, a returned array) exist.

### TS / React

- State or props written directly — `state.items.push(item)`,
  `props.user.name = 'x'` — so React's `Object.is` comparison sees the same
  reference and skips the re-render the code was counting on.
- In-place array methods (`sort`, `reverse`, `splice`) applied to values held
  in state, where `toSorted`, `toReversed`, or a `slice()` copy would leave
  the original alone.
- Module-level `let` bindings or `useRef().current` used as an informal
  store, mutated outside the render cycle and invisible to React's
  scheduling.
- Objects placed in context or a store (Zustand, Redux) and then mutated by
  consumers; with Redux Toolkit, an Immer draft captured and written to after
  the reducer has returned.
- `const` treated as immutability for objects, with no `Readonly<T>`,
  `as const`, or `Object.freeze` anywhere at the boundary.

## Example

Translated from the upstream Python example.

Smelly — the quote is passed through pricing, discounting, and invoicing, any
of which may rewrite it:

```php
final class Quote
{
    public function __construct(
        public string $name,
        public float $value,
        public bool $premium,
    ) {
    }
}

$quote = new Quote('Annual plan', 1200.00, false);

$discounts->apply($quote);   // may rewrite $quote->value
$invoices->issue($quote);    // reads whatever the last writer left
```

Solution — the class is `readonly`, so a change means producing a new value
and the state transition becomes something a reader can see:

```php
final readonly class Quote
{
    public function __construct(
        public string $name,
        public float $value,
        public bool $premium,
    ) {
    }

    public function withValue(float $value): self
    {
        return new self($this->name, $value, $this->premium);
    }
}

$quote = new Quote('Annual plan', 1200.00, false);

$discounted = $discounts->apply($quote);   // returns a new Quote
$invoices->issue($discounted);
```

The cost is an allocation per change; the gain is that every change has a
name and a call site.

## Refactorings

- Remove Setting Method
- Choose Proper Access Control
- Separate Query from Modifier
- Change Reference to Value
- Replace Derived Variable with Query
- Extract Method
- Encapsulate Field
- Combine Functions into Class

## Related smells

| Smell | Edge |
|---|---|
| [Fate Over Action](fate-over-action.md) | family |
| [Side Effects](side-effects.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Mutable Data" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
