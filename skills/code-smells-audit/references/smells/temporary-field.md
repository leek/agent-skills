# Temporary Field

`Within · Object Oriented Abusers · Data`

A field that matters during one operation and is dead weight the rest of the
time. It might be null for most of the object's life, populated by one method
purely so another can read it, or computed in the constructor for the benefit
of a single caller — either way, every reader of the class now has to work
out when the field is meaningful, and the answer is not in the field's
declaration. The reasonable expectation of an object is that it needs all of
its fields; one that does not is usually hiding a smaller object inside it,
or an algorithm that used class state to dodge passing parameters. That dodge
is why the smell breeds [Large Class](large-class.md) and
[Special Case](special-case.md): the guards protecting "only valid during X"
accumulate around the field instead of the field being moved somewhere it is
always valid.

## Detection heuristics

### Agnostic

- A field is null or empty except during one operation, and its guards say so
  in comments rather than in types.
- One method writes the field and exactly one other reads it, with nothing in
  between — it is a parameter wearing a field's clothes.
- A field is only meaningful when another field holds a particular value, so
  the object has implicit modes nothing names.
- The constructor computes and stores something only one accessor ever
  returns, which could be derived on demand.
- An algorithm spread across private methods communicates through fields to
  avoid a long signature (see
  [Long Parameter List](long-parameter-list.md)) — the whole cluster wants to
  be its own class.
- Tests must call methods in a specific order before the object is in a state
  where assertions make sense.

### PHP / Laravel

- Service or Action classes stashing per-invocation data in properties
  (`private ?Order $order`) between `handle()` and its private helpers,
  because passing it would widen the signatures.
- Queued job or listener properties assigned inside `handle()` rather than
  the constructor: they serialize as null and exist only mid-run.
- Nullable model columns meaningful in one branch only (`cancelled_at`,
  `refund_reason`, `failed_payment_code`) that belong on a related record or
  a dedicated state object rather than every row of the table.
- A stored column duplicating what an accessor could derive — kept in sync by
  an observer or a `saving()` hook — so the two can drift.
- View data shared globally (`View::share`) or threaded into a layout for the
  benefit of one partial that is rendered on a handful of routes.

### TS / React

- `useState` holding a value derived from props and re-synced by `useEffect`,
  where computing it during render removes both the field and the effect.
- Optional props meaningful for only one variant of a component
  (`stepTwoAnswer?: string`) — the variants want separate components or a
  discriminated union.
- A `useRef` object used as a scratchpad between two callbacks that could
  pass the value directly.
- Store slices holding wizard or form scratch state that a single route
  reads, never cleared on unmount, so the next visit inherits it.
- Context values that are `null` except while a modal or wizard is mounted,
  forcing every consumer to null-check a value that is structurally
  guaranteed inside the subtree.

## Example

Translated from the upstream Python example.

Smelly — `fullDate` exists only so `__toString()` has something to return,
and it must be maintained whenever the parts change:

```php
final class CalendarDate implements Stringable
{
    private string $fullDate;

    public function __construct(
        private int $year,
        private int $month,
        private int $day,
    ) {
        $this->fullDate = "{$year}, {$month}, {$day}";
    }

    public function isLeapYear(): bool
    {
        // ...
    }

    public function dayOfWeek(): int
    {
        // ...
    }

    public function __toString(): string
    {
        return $this->fullDate;
    }
}
```

Solution — derive it where it is needed, and the field stops being a second
source of truth:

```php
final class CalendarDate implements Stringable
{
    public function __construct(
        private int $year,
        private int $month,
        private int $day,
    ) {
    }

    public function isLeapYear(): bool
    {
        // ...
    }

    public function dayOfWeek(): int
    {
        // ...
    }

    public function __toString(): string
    {
        return "{$this->year}, {$this->month}, {$this->day}";
    }
}
```

When the field is expensive rather than trivial to recompute, the answer is
still not a temporary field — it is caching behind the query, so the class
keeps one story about where the value comes from.

## Refactorings

- Introduce Null Object
- Extract Class
- Move Method

## Related smells

| Smell | Edge |
|---|---|
| [Binary Operator in Name](binary-operator-in-name.md) | co-exist |
| [Long Parameter List](long-parameter-list.md) | causes |
| [Large Class](large-class.md) | causes |
| [Special Case](special-case.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Temporary Field" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
