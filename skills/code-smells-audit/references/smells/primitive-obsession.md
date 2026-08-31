# Primitive Obsession

`Between · Bloaters · Data`

A concept from the domain, money, a phone number, a postcode, an order
status: is represented by a bare `string`, `int`, or `float` because no one
ever created the type it deserved. The primitive is only pretending: nothing
about `string` says which strings are valid, so every place that receives one
has to re-derive the rules, and the rules drift apart as they spread. Fowler
observes that programmers are oddly reluctant to introduce fundamental types
of their own, and Mäntylä's canonical example (money as a primitive) shows
what it costs: rounding, currency, and formatting logic end up scattered
across the callers instead of living in one object that owns them. Because
primitives are cheap to pass, they travel further than a real type would,
which is how this smell seeds [Data Clump](data-clump.md) and
[Obscured Intent](obscured-intent.md). The counterweight is
[Lazy Element](lazy-element.md): a wrapper that adds no behaviour and no
validation is not a value object, it is a rename.

## Detection heuristics

### Agnostic

- The same validation (a regex, a range check, a length limit) is written
  at more than one boundary because the type cannot carry it.
- Units or currency live in the variable name (`amountInCents`, `delayMs`,
  `weightKg`) rather than in a type, so conversions happen by convention (see
  [Type Embedded in Name](type-embedded-in-name.md)).
- A closed set of states is compared as raw string or integer literals, 
  a type code where an enum or polymorphism belongs.
- Parsing and formatting helpers named after the concept
  (`formatPhoneNumber`, `parseSku`) sit in a utility module far from the data
  they operate on.
- The same two or three primitives are always passed together, in the same
  order (see [Data Clump](data-clump.md)).
- An invalid value can only be detected where it is used, never where it was
  constructed.

### PHP / Laravel

- Status and type columns compared as strings, `$order->status === 'paid'`, 
  where a backed enum cast (`protected function casts(): array { return
  ['status' => OrderStatus::class]; }`) would make the set closed and
  exhaustive in `match`.
- Money as `float` or as an `int` of cents, with `number_format()` and
  division by 100 repeated in models, jobs, and Blade, instead of a `Money`
  object behind a custom cast implementing `CastsAttributes`.
- The same `regex:`, `email`, or `size:` rules copied across several
  FormRequests: the shared rule is the type that was never written.
- Associative arrays standing in for objects, `['lat' => $x, 'lng' => $y]`
  passed between services with an `array{lat: float, lng: float}` docblock
  doing the type's job.
- Identifiers passed as bare `int` or `string` through the container and into
  queries, so a `$userId` and an `$accountId` are interchangeable to the type
  checker and only route model binding ever validates them.

### TS / React

- `type UserId = string` aliases: structurally identical to `string`, so
  every string is assignable and the alias documents without constraining.
  A branded type (`string & { readonly __brand: 'UserId' }`) or a class
  actually enforces it.
- Component props typed `string` or `number` for constrained concepts, with
  the check done inside the component (`if (!email.includes('@'))`).
- The same string-literal union declared in several files, with `switch`
  statements over raw literals rather than one exported type.
- API responses consumed without a parse boundary (no Zod or Valibot schema),
  so untyped JSON fields flow into hooks and props as loose primitives.
- Dates carried as ISO strings through props and re-parsed with
  `new Date(value)` in every component that needs to compare or format them.

## Example

Translated from the upstream Python example.

Smelly: two dates that are only strings, so nothing rejects
`'2021-13-45'` and every consumer parses for itself:

```php
$birthdayDate = '1998-03-04';
$nameDayDate = '2021-03-20';
```

Solution: a type that owns its own validity and rendering:

```php
final readonly class CalendarDate implements Stringable
{
    public function __construct(
        public int $year,
        public int $month,
        public int $day,
    ) {
        if (! checkdate($month, $day, $year)) {
            throw new InvalidArgumentException('Not a calendar date.');
        }
    }

    public function __toString(): string
    {
        return sprintf('%04d-%02d-%02d', $this->year, $this->month, $this->day);
    }
}

$birthday = new CalendarDate(1998, 3, 4);
$nameDay = new CalendarDate(2021, 3, 20);
```

Upstream notes the trap on its own example, and it applies here too: PHP
already ships `DateTimeImmutable`, so hand-rolling a date type is
[Clever Code](clever-code.md). Introduce the value object for concepts the
language does not already model.

## Refactorings

- Replace Data Value with Object
- Extract Class
- Introduce Parameter Object
- Replace Array with Object
- Replace Type Code with Class
- Replace Type Code with State/Strategy
- Move Embellishment to Decorator

## Related smells

| Smell | Edge |
|---|---|
| [Type Embedded In Name](type-embedded-in-name.md) | co-exist |
| [Obscured Intent](obscured-intent.md) | causes |
| [Lazy Element](lazy-element.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Primitive Obsession" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
