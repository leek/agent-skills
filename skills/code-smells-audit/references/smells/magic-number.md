# Magic Number

`Within · Lexical Abusers · Names`

A bare numeric literal sitting in the logic with nothing to say what it means.
The reader has to infer the unit, the subject, and the rule from context —
`86400` might be a day in seconds, a cache lifetime, or a quota, and the
number alone cannot tell you which. Because the literal has no name, it also
has no single home: the same value gets retyped wherever the rule applies, so
changing it means grepping for a digit string and hoping every hit is the same
concept.
The one class of exception is a formula that is already the definition of
itself — the `2` in kinetic energy names nothing beyond the formula it lives
in.

## Detection heuristics

### Agnostic

- A literal other than `0`, `1`, or `-1` appearing in a comparison,
  calculation, or configuration argument.
- The same literal typed in more than one place, with no shared declaration
  tying the copies together.
- A comment next to the number explaining what it is — the comment is the
  name the constant should have carried (a ["What" Comment](what-comment.md)).
- The value's unit is not recoverable from the surrounding code: seconds or
  milliseconds, cents or currency units, percent or fraction.
- Changing a business rule means editing digits rather than a declaration.

### PHP / Laravel

- Cache lifetimes written as raw seconds — `Cache::remember($key, 3600, ...)`,
  `Cache::put($key, $v, 86400)` — repeated across services with no named TTL
  or `now()->addDay()` to say what the window is.
- Integer comparisons against a status or type column (`if ($order->status
  === 3)`) where a backed enum plus an Eloquent `casts` entry would name every
  state at once.
- HTTP status codes as literals in `response()->json($payload, 422)` instead
  of the `Response::HTTP_UNPROCESSABLE_ENTITY` constants Laravel already ships
  via Symfony's HttpFoundation.
- Retry and throttle tuning scattered as bare numbers — `public int $tries =
  3;` on a job, `->backoff(60)`, a `RateLimiter::for()` limit of `5` — where
  the same operational budget is expressed in several classes.
- Business rates inline in calculations (`$subtotal * 0.21`, `* 0.10`) and
  page sizes in `->paginate(15)` repeated per controller: the rule lives in
  arithmetic instead of in a named constant or config key.

### TS / React

- Timing literals in `setTimeout`, `setInterval`, and debounce or throttle
  helpers (`300`, `500`, `1000`) duplicated across hooks that are supposed to
  feel consistent.
- Query-client options written per hook — `staleTime: 300_000`, `retry: 3`,
  `refetchInterval: 60_000` — instead of a shared, named config object.
- Breakpoint pixel values hard-coded in `matchMedia` calls or
  `window.innerWidth` comparisons, which must silently stay in sync with the
  Tailwind or CSS breakpoints they mirror.
- Numeric codes from an API compared directly (`if (response.code === 3)`)
  where a `const` object or string union would name the cases.
- Layout and animation numbers inlined in `style` props — z-index values,
  durations, offsets — that only work if they match values declared elsewhere
  in CSS.

## Example

Translated from the upstream Python example.

Smelly — the `100` is load-bearing and unexplained:

```php
public function calculateDamage(Attack $attack): int
{
    $totalDamage = $attack->base + $attack->bonus;

    return min(100, $totalDamage);
}
```

Solution — the literal gets a name, and the name states the rule the number
was quietly enforcing:

```php
final class DamageCalculator
{
    private const MAX_DAMAGE_CAP = 100;

    public function calculate(Attack $attack): int
    {
        $totalDamage = $attack->base + $attack->bonus;

        return min(self::MAX_DAMAGE_CAP, $totalDamage);
    }
}
```

When the cap varies by caller rather than being fixed for the class, the same
fix runs the other way: promote it to a parameter instead of a constant.

## Refactorings

- Replace with Symbolic Constant
- Replace with Parameter

## Related smells

| Smell | Edge |
|---|---|
| [Uncommunicative Name](uncommunicative-name.md) | family |
| [Boolean Blindness](boolean-blindness.md) | family |
| [Obscured Intent](obscured-intent.md) | causes |
| ["What" Comment](what-comment.md) | causes |
| [Duplicated Code](duplicated-code.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Uncommunicative Number

---

*Derivative work adapted from "Magic Number" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
