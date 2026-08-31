# Data Clump

`Between · Bloaters · Data`

The same small group of values keeps travelling together, through parameter
lists, field declarations, payload keys, form inputs, without ever being
given a name. `red, green, blue`; `street, city, postcode`; `amount,
currency`. Each occurrence is cheap on its own, which is why the group never
gets promoted into the class it is obviously describing, but the cost is paid
everywhere at once: the concept stays implicit, so every signature that
accepts it gets wider (see [Long Parameter List](long-parameter-list.md)), the
rules that govern the group are re-implemented at each site instead of living
with the data, and the values can drift apart because nothing enforces that
they arrive as a set. Fowler's test is the quick one: remove one value from
the group and ask whether the rest still mean anything: if they do not, the
group is an object. The counterweight is that the extracted object should be
immutable; a shared mutable bundle passed everywhere just trades this smell
for [Mutable Data](mutable-data.md).

## Detection heuristics

### Agnostic

- Two or more parameters recur in the same order across several signatures,
  often with a shared prefix or suffix (`startDate`/`endDate`,
  `billingStreet`/`billingCity`); the shared affix is the missing type name.
- Delete one member of the group from a signature and the remainder stops
  making sense.
- The same cluster of fields is declared side by side in more than one class.
- The group also appears as adjacent keys in a map, tuple, or serialized
  payload, so the concept exists in the data but not in the type system.
- Validation, formatting, or conversion for the group is re-written at each
  place that accepts it (see [Duplicated Code](duplicated-code.md)).
- Adding a member to the concept means editing every signature that carries
  it: the [Shotgun Surgery](shotgun-surgery.md) tell.

### PHP / Laravel

- Several FormRequests repeating the same `rules()` fragment (`street`,
  `city`, `postcode`, `country`), and the controller then passing those
  validated keys to services one argument at a time.
- Migrations creating the same column cluster on multiple tables (`amount` +
  `currency`, `lat` + `lng`) with no Eloquent custom cast, a class
  implementing `CastsAttributes` (or a `Castable` value object) is how a
  column group becomes one attribute.
- `$casts` listing the members as separate primitives, so every consumer
  re-assembles the concept from `$model->amount` and `$model->currency`.
- Blade components taking the group as separate props, 
  `<x-price :amount="$amount" :currency="$currency" />`: repeated at many
  call sites instead of `<x-price :money="$money" />`.
- Queued jobs, events, and notifications whose constructors accept the same
  primitives and serialize them individually into the payload, where one
  `readonly` DTO would travel as a single argument.

### TS / React

- Function and component signatures repeatedly destructuring the same shape
  (`{ startDate, endDate }`, `{ x, y }`) with no named `type` or `interface`
  for it.
- The group drilled as separate props through several component levels (see
  [Tramp Data](tramp-data.md)) rather than one typed object.
- Adjacent `useState` calls that are always set together in the same handler, 
  one state object or a `useReducer` is the missing bundle.
- Zod/Valibot schemas repeating the same field trio in several places instead
  of composing a shared sub-schema via `.extend()` or `.merge()`.
- API client functions taking positional primitives (`fetchRange(from, to,
  tz)`) with the same triple duplicated across the module's call sites.

## Example

Translated from the upstream Python example.

Smelly: the three components travel together through every signature that
touches a color:

```php
function colorize(int $red, int $green, int $blue): string
{
    // ...
}

function darken(int $red, int $green, int $blue, float $factor): array
{
    // ...
}
```

Solution; the group becomes the immutable object it was describing, and the
behavior that operated on it moves in with the data:

```php
final readonly class Rgb
{
    public function __construct(
        public int $red,
        public int $green,
        public int $blue,
    ) {
    }

    public function darken(float $factor): self
    {
        return new self(
            (int) round($this->red * $factor),
            (int) round($this->green * $factor),
            (int) round($this->blue * $factor),
        );
    }
}

function colorize(Rgb $rgb): string
{
    // ...
}
```

The parameter object is the first step; the payoff arrives when the rules
about the group (range checks, conversions, formatting) stop being duplicated
at each call site and move onto the new class.

## Refactorings

- Extract Class
- Introduce Parameter Object

## Related smells

| Smell | Edge |
|---|---|
| [Mutable Data](mutable-data.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Data Clump" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
